import os
import requests
import shutil
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


# 1. Supabase Localhost Connection ---
# Default local Supabase connection details:
# User: postgres, Password: postgres, Host: localhost, Port: 54322, DB: postgres
#DB_URL = "postgresql://postgres:postgres@localhost:54322/postgres"
# --- CONFIGURATION FROM ENV ---
#SQLITE_DB_PATH = os.getenv('SQLITE_DB_PATH')
SUPABASE_CONN_STRING = os.getenv('CLOUD_DB_URL')

#if not SUPABASE_CONN_STRING or not SQLITE_DB_PATH:
if not SUPABASE_CONN_STRING:
    raise ValueError("Missing environment variable. Check your .env file.")

engine = create_engine(SUPABASE_CONN_STRING)

def run_reservations_download():
    # 1. Create a unique filename (e.g., report_2026-04-22.csv)
    datestamp = datetime.now().strftime("%Y%m%d")
    filename = f"./reservations_data/reservations_confirmed_{datestamp}.csv"
    
    print(f"Bypassing the UI to download report for: {DATE_STR}...")

    try:
        # 2. Execute the POST request
        response = requests.post(URL, data=PAYLOAD, timeout=30)
        response.raise_for_status()

        # 3. Save the file locally
        with open(filename, 'wb') as f:
            f.write(response.content)
        
        print(f"Successfully downloaded: {filename}")

        # 4. Trigger your existing DB script
        # Assuming your upload script has a function called 'upload'
        # import your_db_script
        # your_db_script.upload(filename)
        print("Ready for DB upload.")
        return filename

    except requests.exceptions.RequestException as e:
        print(f"Network error: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")

def process_reservations_file(downloaded_file):
    # The 'static' path your DB script looks for
    target_path = "./reservations_data/reservations_confirmed.csv"
    
    # Ensure the directory exists so the script doesn't crash
    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    
    try:
        # Copy the dated file to the static filename (overwrites if exists)
        shutil.copy2(downloaded_file, target_path)
        print(f"File staged: {downloaded_file} -> {target_path}")
        
    except Exception as e:
        print(f"Error during file processing: {e}")

def refresh_catch_returns_data(conn):
    try:
        sheet_id = "1QhLqiUqe9Qy5eHvDGj8k2HDtsrORytQ-KSmNAp5Sqzs"
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
        df_final['catch_date'] = pd.to_datetime(df_final['catch_date']).dt.date
        print(f"Fetched {len(df_final)} records from Google Sheets.")

        print(f"Wiping old catch_returns_staging data...")
        conn.execute(text("TRUNCATE TABLE catch_returns_staging_table RESTART IDENTITY;"))
        
        print(f"Uploading {len(df_final)} fresh records...")
        df_final.to_sql('catch_returns_staging_table', conn, if_exists='append', index=False)
        print("✅ Catch Returns Sync complete!")
    except Exception as e:
        # We re-raise the error so the Master Transaction knows to Rollback
        print(f"❌ Catch Returns Error: {e}")
        raise e 

def refresh_reservations_table_data(csv_filename, table_name, conn):
    try:
        df_reservations = pd.read_csv(csv_filename, skiprows=1, encoding='utf-8-sig')
        #df_reservations.rename(columns={'Start date': 'Date'}, inplace=True)
        df_reservations.columns = df_reservations.columns.str.strip()
        print(f"Fetched {len(df_reservations)} records reservations CSV.")
        print(f"Wiping old {table_name} data...")
        # FIX: Use format to safely inject table name into TRUNCATE
        conn.execute(text(f"TRUNCATE TABLE {table_name} RESTART IDENTITY;"))

 # 1. THE MAPPING DICTIONARY
        res_mapping = {
            "Start date": "date",
            "Resource": "resource",
            "Name": "name"
        }
        
        # 2. Apply the rename
        df_reservations.rename(columns=res_mapping, inplace=True)  
        
        # 3. Explicitly select the columns you want to send
        # We EXCLUDE 'id' and 'cr_name' here because:
        # - 'id' is generated by Postgres automatically
        # - 'cr_name' is empty right now and filled later by your matching function
        target_cols = ["date", "resource", "name"]
        
        # This will fail LOUDLY if a column is missing, which is better for debugging
        df_final = df_reservations[target_cols].copy()

        # 4. Data Type Cleanup
        if 'date' in df_final.columns:
            # Errors='coerce' handles any messy text in the date column
            df_final['date'] = pd.to_datetime(df_final['date'], errors='coerce').dt.date

        # 5. Upload
        # index=False ensures Pandas doesn't try to turn its own index into a DB column
        df_final.to_sql(table_name, conn, if_exists='append', index=False)
        print(f"✅ Table '{table_name}' refreshed successfully.")

    except Exception as e:
        print(f"❌ Reservations Upload Error: {e}")
        raise e

def match_and_update_reservation_names(conn):
    try:    
        # FIX: Use .scalar() for single values
        start_date = conn.execute(text("SELECT target_start_date FROM year_param WHERE id = 1")).scalar()
        membership_year = conn.execute(text("SELECT target_year FROM year_param WHERE id = 1")).scalar()

        # FIX: Use bind parameters for the WHERE clause
        result = conn.execute(
            text("SELECT cr_name FROM members WHERE year_of_membership = :yr"),
            {"yr": membership_year}
        )
        master_lookup = {row[0].upper(): row[0] for row in result.fetchall()}

        result = conn.execute(text("SELECT id, name FROM reservations_confirmed_staging"))
        updates = []

        for row_id, full_name in result.fetchall():
            if not full_name: continue
            parts = full_name.strip().split(' ')
            if len(parts) < 2: continue
                
            initial, surname = parts[0][0].upper(), parts[-1].upper()
            prefixed_key, surname_key = f"{initial}{surname}", surname
            
            if prefixed_key in master_lookup:
                updates.append({"cr_name": master_lookup[prefixed_key], "id": row_id})
            elif surname_key in master_lookup:
                updates.append({"cr_name": master_lookup[surname_key], "id": row_id})
            else:
                # This will trigger the try/except block below
                #raise ValueError(f"No match found in members table for name: {full_name} (ID: {row_id})")
                print(f"❌ Name Matching Error: No match found in members table for name: {full_name} (ID: {row_id})")

        if updates:
            conn.execute(
                text("UPDATE reservations_confirmed_staging SET cr_name = :cr_name WHERE id = :id"),
                updates
            )
        print(f"✅ Name update complete. {len(updates)} records matched.")

    except Exception as e:
        print(f"❌ Name Matching Error: {e}")
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

        downloaded_path = run_reservations_download()
        
        # 2. Check if the download actually worked before trying to process it
        if downloaded_path:
            # This function just copies the file to the static path your DB script expects, so it can be picked up in the next step
            process_reservations_file(downloaded_path)
        else:
            print("Download failed, skipping file processing.")

        # This is where 'conn' is created for the whole session
        with engine.begin() as conn: 
            print(f"🚀 Starting Master Sync : to... {SUPABASE_CONN_STRING}")
            
            # 1. Load Reservations
            refresh_reservations_table_data(
                './reservations_data/reservations_confirmed.csv', 
                'reservations_confirmed_staging',
                conn  # Pass it in
            )
            
            # 2. Match Names
            match_and_update_reservation_names(conn) # Pass it in
            
            # 3. Load Catch Returns
            refresh_catch_returns_data(conn) # Pass it in
            
            print("✅ All steps completed. Transaction committed.")

    except Exception as e:
        # If ANY of the functions above crash, engine.begin() 
        # automatically rolls back everything.
        print(f"❌ Transaction Failed! No data was changed in Supabase. Error: {e}")