import os
import requests
import shutil
import io
import pandas as pd
from sqlalchemy import create_engine
from sqlalchemy import text
from dotenv import load_dotenv
from datetime import datetime

# Load environment variables (for your DB password/connection string)
load_dotenv()

#================================================================
# ibookfishing report download configuration
URL = os.getenv('IBOOKFISHING_REPORT_PAGE_URL')
IBOOKFISHING_REPORT_SHSEC = os.getenv('IBOOKFISHING_REPORT_SHSEC')
IBOOKFISHING_REPORT_CALENDAR_ID = os.getenv('IBOOKFISHING_REPORT_CALENDAR_ID')
IBOOKFISHING_REPORT_S2 = os.getenv('IBOOKFISHING_REPORT_S2')
GOOGLE_SHEETS_ID = os.getenv('GOOGLE_SHEETS_ID')

# The exact string you type into the browser
# It defines 'from the start of the season until today' for the report'
# and makes it year agnostic so you don't have to update it every year.
thisYear = datetime.now().year
DATE_STR = f"{thisYear}-04-01 to Today"

# Payload built from your screenshots
PAYLOAD = {
    'type': '1',
    'alt_type': '1',
    'download': 'csv',
    'alt_days': DATE_STR,
    'required_status': '4',
    'sort_field': 'name',
    'id': '759',
    'calendar': IBOOKFISHING_REPORT_CALENDAR_ID,
    'shsec': IBOOKFISHING_REPORT_SHSEC,
    's2': IBOOKFISHING_REPORT_S2
}


# 1. Supabase Connection ---
# --- CONFIGURATION FROM ENV ---
SUPABASE_CONN_STRING = os.getenv('CLOUD_DB_URL')
#SUPABASE_CONN_STRING = os.getenv('LOCAL_DB_URL')

if not SUPABASE_CONN_STRING:
    raise ValueError("Missing environment variable. Check your .env file.")

engine = create_engine(SUPABASE_CONN_STRING)

def run_reservations_download():
    print(f"Bypassing the UI to download report for: {DATE_STR}...")
    try:
        response = requests.post(URL, data=PAYLOAD, timeout=30)
        response.raise_for_status()
        
        # Return the bytes directly
        print("Successfully downloaded data to memory.")
        return response.content 

    except requests.exceptions.RequestException as e:
        print(f"Network error: {e}")
        return None

def refresh_catch_returns_data(conn):
    try:
        sheet_id = GOOGLE_SHEETS_ID
        url = f"https://docs.google.com/spreadsheets/d/{sheet_id}/export?format=csv"
        df_new = pd.read_csv(url)

        mapping = {
            "Timestamp": "timestamp", "Rod Name": "rod_name", "Date": "catch_date",
            "Beat": "beat", "Brown Trout Released": "brown_trout_released",
            "Grayling": "grayling", "Rainbow Trout": "rainbow_trout",
            "Other Species": "other_species", "Brown Trout Retained": "brown_trout_retained",
            "Guest": "guest", "Comments": "comments", "DNF": "dnf"
        }
        df_new.rename(columns=mapping, inplace=True)
        df_final = df_new[list(mapping.values())].copy()
        
        # --- FIXES START HERE ---
        # 1. Convert Yes/No to Boolean
        df_final['guest'] = df_final['guest'].map({'Yes': True, 'No': False})
        #
        #Sort out the dnf column which might have nulls and is being inserted into a boolean field
        # 1. Map 'Yes' to True, and 'No' to False. 
        # Anything else (like empty/NULL) will become NaN temporarily.
        df_final['dnf'] = df_final['dnf'].map({'Yes': True, 'No': False})

        # 2. Now explicitly turn those NaNs (the empty cells) into False.
        df_final['dnf'] = df_final['dnf'].fillna(False)

        # 3. Final safety check: ensure the column is a boolean type for the DB
        df_final['dnf'] = df_final['dnf'].astype(bool)
        
        # 2. Ensure date conversion
        df_final['catch_date'] = pd.to_datetime(df_final['catch_date']).dt.date
        # --- FIXES END HERE ---

        print(f"Fetched {len(df_final)} records from Google Sheets.")

        print(f"Wiping old PRIVATE catch_returns_staging data...")
        conn.execute(text("TRUNCATE TABLE private.catch_returns_staging_table RESTART IDENTITY;"))

        print(f"Uploading {len(df_final)} fresh records to private...")
        df_final.to_sql('catch_returns_staging_table', conn, schema='private', if_exists='append', index=False)
        print(f"✅ Catch Returns Sync of private complete!")
    except Exception as e:
        print(f"❌ Catch Returns Error: {e}")
        raise e

def refresh_reservations_table_data(csv_bytes, table_name, conn):
    try:
        # Wrap bytes in a stream so Pandas can read it like a file
        csv_buffer = io.BytesIO(csv_bytes)
        
        df_reservations = pd.read_csv(csv_buffer, skiprows=2, names=['date', 'resource', 'name'])
        
        df_reservations.columns = df_reservations.columns.str.strip()
        print(f"Fetched {len(df_reservations)} records from memory buffer.")
        print(f"Fetched {len(df_reservations)} records reservations CSV.")

        # --- Truncate private schema table ---
        private_table = f"private.{table_name}"

        print(f"Wiping old {private_table} data...")
        conn.execute(text(f"TRUNCATE TABLE {private_table} RESTART IDENTITY;"))

        res_mapping = {
            "Start date": "date",
            "Beat": "resource",
            "Name": "name"
        }
        
        target_cols = ["date", "resource", "name"]
        df_final = df_reservations[target_cols].copy()

        # Data Type Cleanup
        if 'date' in df_final.columns:
            df_final['date'] = pd.to_datetime(df_final['date'], errors='coerce').dt.date

        # --- Upload to private schema table ---
        df_final.to_sql(table_name, conn, schema='private', if_exists='append', index=False)
        print(f"✅ Table '{private_table}' refreshed successfully.")

    except Exception as e:
        print(f"❌ Reservations Upload Error: {e}")
        raise e

def match_and_update_reservation_names(conn):
    try:    
        start_date = conn.execute(text("SELECT target_start_date FROM private.year_param WHERE id = 1")).scalar()
        membership_year = conn.execute(text("SELECT target_year FROM private.year_param WHERE id = 1")).scalar()

        result = conn.execute(
            text("SELECT cr_name FROM private.view_member_names WHERE year_of_membership = :yr"),
            {"yr": membership_year}
        )
        master_lookup = {row[0].upper(): row[0] for row in result.fetchall()}

        # Read from private (source of truth going forward)
        result = conn.execute(text("SELECT id, name FROM private.reservations_confirmed_staging"))
        updates = []

        for row_id, full_name in result.fetchall():
            if not full_name: continue
            parts = full_name.strip().split()
            if len(parts) < 2: continue

            surname = parts[-1].upper()
            given_names = parts[:-1]

            # Tier 1: Initial + surname (e.g. BPUNDYKE, JPUNDYKE)
            possible_keys = [f"{part[0].upper()}{surname}" for part in given_names if part]

            # Tier 2: Full given name(s) + surname, no spaces (e.g. FRANKCOLLIN, FREDCOLLIN)
            for part in given_names:
                if part:
                    possible_keys.append(f"{part.upper()}{surname}")

            # Tier 3: Standalone surname as last resort (e.g. PUNDYKE)
            possible_keys.append(surname)

            matched_key = next((key for key in possible_keys if key in master_lookup), None)

            if matched_key:
                updates.append({"cr_name": master_lookup[matched_key], "id": row_id})
            else:
                print(f"❌ Name Matching Error: No match found in members table for name: {full_name} (ID: {row_id})")

        if updates:
            conn.execute(
                text("UPDATE private.reservations_confirmed_staging SET cr_name = :cr_name WHERE id = :id"),
                updates
            )
            print(f"✅ private.reservations_confirmed_staging: {len(updates)} records updated.")

        print(f"✅ Name update complete. {len(updates)} records matched.")

    except Exception as e:
        print(f"❌ Name Matching Error: {e}")
        raise e
    
def insert_dnf_for_beat_mismatch(conn):
    """
    Detects the edge case where a member has a reservation for Beat_A on a given
    date, but submitted their (non-guest) catch return for Beat_B.
    The trigger will have already created a synthetic reservation for Beat_B.
    This function inserts a DNF catch return for Beat_A to mark it as not fished.
    Applied to the private schema. Lookup tables (beats, reservation_beats) are
    read from public as the shared reference schema.
    """
    try:
        schema = "private"
        # Find reservations where the member's non-guest catch return that day
        # was for a DIFFERENT beat than the one reserved.
        # We join through reservation_beats -> beats to get the catch-return
        # beat name that corresponds to the reservation's resource.
        mismatch_sql = text(f"""
            SELECT
                r.date,
                r.cr_name,
                b.beat AS reserved_beat_cr_name
            FROM {schema}.reservations_confirmed_staging r
            -- Map the reservation's resource to the beats.beat name
            INNER JOIN private.reservation_beats rb ON rb.beat = r.resource
            INNER JOIN private.beats b ON b.id = rb.beat_id
            -- Find that member's non-guest catch return(s) for the same date
            INNER JOIN {schema}.catch_returns_staging_table cr
                ON cr.rod_name = r.cr_name
                AND cr.catch_date = r.date
                AND cr.guest = false
                AND cr.dnf = false
            -- The catch return beat differs from the reservation beat
            WHERE cr.beat != b.beat
            -- Exclude synthetic reservations (already created by the trigger
            -- for the beat the member DID fish - we don't want to DNF those)
            AND r.name != 'Synthetic'
            -- Exclude if a DNF already exists for this beat on this date
            AND NOT EXISTS (
                SELECT 1
                FROM {schema}.catch_returns_staging_table existing_dnf
                WHERE existing_dnf.rod_name   = r.cr_name
                AND   existing_dnf.catch_date = r.date
                AND   existing_dnf.beat       = b.beat
                AND   existing_dnf.dnf        = true
            )
            -- Exclude if a real catch return already exists for the reserved beat:
            -- member corrected their earlier wrong-beat submission, so no DNF needed
            AND NOT EXISTS (
                SELECT 1
                FROM {schema}.catch_returns_staging_table correct_cr
                WHERE correct_cr.rod_name   = r.cr_name
                AND   correct_cr.catch_date = r.date
                AND   correct_cr.beat       = b.beat
                AND   correct_cr.dnf        = false
                AND   correct_cr.guest      = false
            )
        """)

        result = conn.execute(mismatch_sql)
        mismatches = result.fetchall()

        if not mismatches:
            print(f"✅ Beat mismatch check ({schema}): No DNF insertions required.")
            return

        print(f"⚠️  Beat mismatch detected ({schema}): {len(mismatches)} DNF record(s) to insert.")

        for date, cr_name, reserved_beat in mismatches:
            print(f"   Inserting DNF for {cr_name} on {date} for beat '{reserved_beat}'")

        # Build list of dicts for the bulk insert
        dnf_records = [
            {
                "rod_name":              row.cr_name,
                "catch_date":            row.date,
                "beat":                  row.reserved_beat_cr_name,
                "dnf":                   True,
                "guest":                 False,
                "brown_trout_released":  0,
                "brown_trout_retained":  0,
                "grayling":              0,
                "rainbow_trout":         0,
                "other_species":         0,
                "comments":              "Auto-marked DNF: member fished a different beat",
                "timestamp":             datetime.now().isoformat(),
            }
            for row in mismatches
        ]

        conn.execute(
            text(f"""
                INSERT INTO {schema}.catch_returns_staging_table
                    (rod_name, catch_date, beat, dnf, guest,
                     brown_trout_released, brown_trout_retained, grayling,
                     rainbow_trout, other_species, comments, timestamp)
                VALUES
                    (:rod_name, :catch_date, :beat, :dnf, :guest,
                     :brown_trout_released, :brown_trout_retained, :grayling,
                     :rainbow_trout, :other_species, :comments, :timestamp)
            """),
            dnf_records
        )

        print(f"✅ Beat mismatch DNF insert complete ({schema}). {len(dnf_records)} record(s) inserted.")

    except Exception as e:
        print(f"❌ Beat Mismatch DNF Error: {e}")
        raise e

def insert_synthetic_reservations(conn):
    """
    Replicates the logic of the check_and_insert_reservation trigger for the
    bulk-loaded catch returns, since Pandas to_sql bypasses row-level triggers.
    For every catch return that has no matching reservation (by date, cr_name,
    and beat_id), inserts a synthetic reservation record.
    Note: where two reservation resources share the same beat_id (e.g.
    '17. Fishing Hut' and '18. Railway Bridge' both map to beats.id=4),
    a catch return for that beat satisfies ALL reservations for that beat_id,
    so no synthetic record is created for the secondary resource.
    Applied to the private schema. Lookup tables (beats, reservation_beats)
    are read from public as the shared reference schema.
    """
    try:
        schema = "private"
        missing_sql = text(f"""
            SELECT
                cr.catch_date,
                cr.rod_name,
                rb.beat    AS resource
            FROM {schema}.catch_returns_staging_table cr
            -- Map CR beat name to beat_id via shared lookup tables
            INNER JOIN private.beats b ON b.beat = cr.beat
            -- Get ALL reservation resources that share this beat_id
            INNER JOIN private.reservation_beats rb ON rb.beat_id = b.id
            -- Only where no reservation exists for this date/cr_name
            -- for ANY resource sharing the same beat_id
            WHERE NOT EXISTS (
                SELECT 1
                FROM {schema}.reservations_confirmed_staging r
                INNER JOIN private.reservation_beats rb2 ON rb2.beat = r.resource
                WHERE r.date    = cr.catch_date
                AND   r.cr_name = cr.rod_name
                AND   rb2.beat_id = b.id
            )
        """)

        result = conn.execute(missing_sql)
        missing = result.fetchall()

        if not missing:
            print(f"✅ Synthetic reservation check ({schema}): None required.")
            return

        print(f"⚠️  {len(missing)} synthetic reservation(s) to insert into {schema}.")
        for row in missing:
            print(f"   Synthetic reservation: {row.rod_name} / {row.resource} / {row.catch_date}")

        synthetic_records = [
            {
                "date":     row.catch_date,
                "resource": row.resource,
                "name":     "Synthetic",
                "cr_name":  row.rod_name,
            }
            for row in missing
        ]

        conn.execute(
            text(f"""
                INSERT INTO {schema}.reservations_confirmed_staging
                    (date, resource, name, cr_name)
                VALUES
                    (:date, :resource, :name, :cr_name)
                ON CONFLICT (date, cr_name, resource) DO NOTHING
            """),
            synthetic_records
        )

        print(f"✅ Synthetic reservation insert complete ({schema}). {len(synthetic_records)} record(s) inserted.")

    except Exception as e:
        print(f"❌ Synthetic Reservation Error: {e}")
        raise e
    
def mark_wrong_beat_submissions_as_dnf(conn):
    """
    Handles the correction scenario: member submits a catch return for the
    wrong beat, then immediately resubmits for their actual reserved beat.
    insert_synthetic_reservations will have created a Synthetic for the wrong
    beat. This function detects those wrong-beat records and marks them DNF,
    so they are not counted as real catch data and don't trigger a false-positive
    in insert_dnf_for_beat_mismatch.

    Detection criteria (all must be true):
      1. Non-guest, non-DNF catch return exists for Beat_X.
      2. Beat_X has only a Synthetic reservation for that member+date (no real one).
      3. The same member has a non-guest, non-DNF catch return for a different
         beat on the same date that HAS a real (non-Synthetic) reservation.
    """
    try:
        schema = "private"
        sql = text(f"""
            WITH wrong_beat_crs AS (
                SELECT cr.id
                FROM {schema}.catch_returns_staging_table cr
                WHERE cr.dnf   = false
                  AND cr.guest = false
                -- Beat_X has a Synthetic reservation for this member+date
                AND EXISTS (
                    SELECT 1
                    FROM {schema}.reservations_confirmed_staging r
                    INNER JOIN private.reservation_beats rb ON rb.beat = r.resource
                    INNER JOIN private.beats b ON b.id = rb.beat_id
                    WHERE r.cr_name = cr.rod_name
                      AND r.date    = cr.catch_date
                      AND b.beat    = cr.beat
                      AND r.name    = 'Synthetic'
                )
                -- No real reservation exists for Beat_X
                AND NOT EXISTS (
                    SELECT 1
                    FROM {schema}.reservations_confirmed_staging r
                    INNER JOIN private.reservation_beats rb ON rb.beat = r.resource
                    INNER JOIN private.beats b ON b.id = rb.beat_id
                    WHERE r.cr_name = cr.rod_name
                      AND r.date    = cr.catch_date
                      AND b.beat    = cr.beat
                      AND r.name   != 'Synthetic'
                )
                -- Member also has a real catch return for a different beat
                -- that has a real reservation on the same date
                AND EXISTS (
                    SELECT 1
                    FROM {schema}.catch_returns_staging_table cr2
                    WHERE cr2.rod_name   = cr.rod_name
                      AND cr2.catch_date = cr.catch_date
                      AND cr2.beat      != cr.beat
                      AND cr2.dnf        = false
                      AND cr2.guest      = false
                      AND EXISTS (
                          SELECT 1
                          FROM {schema}.reservations_confirmed_staging r2
                          INNER JOIN private.reservation_beats rb2 ON rb2.beat = r2.resource
                          INNER JOIN private.beats b2 ON b2.id = rb2.beat_id
                          WHERE r2.cr_name = cr2.rod_name
                            AND r2.date    = cr2.catch_date
                            AND b2.beat    = cr2.beat
                            AND r2.name   != 'Synthetic'
                      )
                )
            )
            UPDATE {schema}.catch_returns_staging_table
            SET dnf                  = true,
                brown_trout_released = 0,
                grayling             = 0,
                rainbow_trout        = 0,
                other_species        = 0,
                brown_trout_retained = 0,
                comments             = 'Auto-corrected: wrong beat submission'
            WHERE id IN (SELECT id FROM wrong_beat_crs)
        """)
        result = conn.execute(sql)
        count = result.rowcount
        if count == 0:
            print(f"✅ Wrong-beat correction check: No records to correct.")
        else:
            print(f"⚠️  Wrong-beat correction: Marked {count} record(s) as DNF.")

    except Exception as e:
        print(f"❌ Wrong-beat correction error: {e}")
        raise e

def deduplicate_catch_returns(conn):
    """
    Where a member has submitted more than one non-guest, non-DNF catch return
    for the same rod_name + catch_date + beat, keep only the latest by timestamp
    and delete the earlier ones. Applied to the private schema.
    """
    try:
        schema = "private"
        dedup_sql = text(f"""
            DELETE FROM {schema}.catch_returns_staging_table
            WHERE id IN (
                SELECT id
                FROM (
                    SELECT
                        id,
                        ROW_NUMBER() OVER (
                            PARTITION BY rod_name, catch_date, beat
                            ORDER BY timestamp DESC
                        ) AS rn
                    FROM {schema}.catch_returns_staging_table
                    WHERE guest = false
                      AND dnf   = false
                ) ranked
                WHERE rn > 1
            )
        """)
        result = conn.execute(dedup_sql)
        count = result.rowcount
        if count == 0:
            print(f"✅ Duplicate CR check ({schema}): No duplicates found.")
        else:
            print(f"⚠️  Duplicate CR check ({schema}): Deleted {count} earlier duplicate record(s).")

    except Exception as e:
        print(f"❌ Duplicate CR deduplication error: {e}")
        raise e

# --- EXECUTION AREA ---
if __name__ == "__main__":
    try:
        # Identify timestamp this program is being run 
        # for the log file
        datestamp = datetime.now().strftime("%Y-%m-%d: %H:%M")
        print(" ")
        print("===============================================")
        print(f"Starting ETL process for Catch Returns and Reservations at {datestamp}")
        # 1. Download directly into a variable (bytes)
        downloaded_data = run_reservations_download()
        
        if downloaded_data:
            with engine.begin() as conn: 
                print(f"🚀 Starting Master Sync...")
                
                # 2. Pass the bytes directly to the processing function
                refresh_reservations_table_data(
                    downloaded_data, 
                    'reservations_confirmed_staging',
                    conn
                )
                
                # 3. Match Names & Catch Returns
                print(f"Starting - match_and_update_reservation_name")
                match_and_update_reservation_names(conn)
                print(f"Starting - Refresh Catch Returns")
                refresh_catch_returns_data(conn)
                print(f"De-duplicating Catch Returns")
                deduplicate_catch_returns(conn)
                print(f"Starting - insert_synthetic_reservations")
                insert_synthetic_reservations(conn)
                print(f"Starting - mark_wrong_beat_submissions_as_dnf")
                mark_wrong_beat_submissions_as_dnf(conn)
                print(f"Starting - insert_dnf_for_beat_mismatch")
                insert_dnf_for_beat_mismatch(conn)
                
                print("✅ All steps completed.")
        else:
            print("No data received from download.")

    except Exception as e:
        print(f"❌ Transaction Failed! Error: {e}")