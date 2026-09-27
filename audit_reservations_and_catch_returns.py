import os
from datetime import datetime, timedelta

from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.exc import OperationalError

load_dotenv()

CLOUD_DB_URL = os.getenv('CLOUD_DB_URL')
CLOUD_DB_URL_POOLER = os.getenv('CLOUD_DB_URL_POOLER')
LOCAL_DB_URL = os.getenv('LOCAL_DB_URL')

# Flip to LOCAL_DB_URL for testing against the local dev instance.
TARGET_URL = CLOUD_DB_URL

STALE_SYNTHETIC_DAYS = 5


def build_engine():
    if not TARGET_URL:
        raise ValueError("Missing environment variable. Check your .env file.")

    direct_engine = create_engine(TARGET_URL)
    try:
        with direct_engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        print("Connected via direct connection.")
        return direct_engine
    except OperationalError as e:
        print(f"Direct connection failed ({e}); falling back to connection pooler...")
        if not CLOUD_DB_URL_POOLER:
            raise ValueError("Direct connection failed and CLOUD_DB_URL_POOLER is not set in .env.")
        pooler_engine = create_engine(CLOUD_DB_URL_POOLER)
        with pooler_engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        print("Connected via connection pooler.")
        return pooler_engine


def check_stale_synthetic_reservations(conn):
    """
    Synthetic reservations should always be replaced by a real one once
    etl_reservations_only_to_supabase.py downloads it (see the Synthetic/real
    collision fix). One still sitting here after several days means either the
    booking never actually came through, or the member self-attested "not
    synced yet" incorrectly.
    """
    rows = conn.execute(
        text("""
            SELECT date, resource, cr_name
            FROM private.reservations_confirmed_staging
            WHERE name = 'Synthetic'
              AND date <= :cutoff
            ORDER BY date
        """),
        {"cutoff": (datetime.now() - timedelta(days=STALE_SYNTHETIC_DAYS)).date()}
    ).fetchall()
    return rows


def check_unresolved_beat_mismatches(conn):
    """
    A real reservation with no catch return at all against it, while the same
    member has a real (non-DNF) catch return for a different beat that day.
    The interactive form should resolve this at submission time now
    (previously auto-fixed nightly by insert_dnf_for_beat_mismatch) - any
    occurrence here means something slipped through, e.g. a cancelled dialog.
    """
    rows = conn.execute(
        text("""
            SELECT r.date, r.cr_name, b.beat AS reserved_beat, cr.beat AS actually_fished_beat
            FROM private.reservations_confirmed_staging r
            INNER JOIN private.reservation_beats rb ON rb.beat = r.resource
            INNER JOIN private.beats b ON b.id = rb.beat_id
            INNER JOIN private.catch_returns_staging_table cr
                ON cr.rod_name = r.cr_name
                AND cr.catch_date = r.date
                AND cr.guest = false
                AND cr.dnf = false
            WHERE cr.beat != b.beat
              AND r.name != 'Synthetic'
              AND NOT EXISTS (
                  SELECT 1 FROM private.catch_returns_staging_table existing
                  WHERE existing.rod_name = r.cr_name
                    AND existing.catch_date = r.date
                    AND existing.beat = b.beat
              )
            ORDER BY r.date
        """)
    ).fetchall()
    return rows


def check_uncorrected_wrong_beat_submissions(conn):
    """
    A real (non-DNF) catch return sitting on a beat that only has a Synthetic
    reservation, while the same member has a proper catch return elsewhere
    that day backed by a real reservation - the old
    mark_wrong_beat_submissions_as_dnf pattern.
    """
    rows = conn.execute(
        text("""
            SELECT cr.rod_name, cr.catch_date, cr.beat
            FROM private.catch_returns_staging_table cr
            WHERE cr.dnf = false
              AND cr.guest = false
              AND EXISTS (
                  SELECT 1
                  FROM private.reservations_confirmed_staging r
                  INNER JOIN private.reservation_beats rb ON rb.beat = r.resource
                  INNER JOIN private.beats b ON b.id = rb.beat_id
                  WHERE r.cr_name = cr.rod_name
                    AND r.date = cr.catch_date
                    AND b.beat = cr.beat
                    AND r.name = 'Synthetic'
              )
              AND NOT EXISTS (
                  SELECT 1
                  FROM private.reservations_confirmed_staging r
                  INNER JOIN private.reservation_beats rb ON rb.beat = r.resource
                  INNER JOIN private.beats b ON b.id = rb.beat_id
                  WHERE r.cr_name = cr.rod_name
                    AND r.date = cr.catch_date
                    AND b.beat = cr.beat
                    AND r.name != 'Synthetic'
              )
              AND EXISTS (
                  SELECT 1
                  FROM private.catch_returns_staging_table cr2
                  WHERE cr2.rod_name = cr.rod_name
                    AND cr2.catch_date = cr.catch_date
                    AND cr2.beat != cr.beat
                    AND cr2.dnf = false
                    AND cr2.guest = false
                    AND EXISTS (
                        SELECT 1
                        FROM private.reservations_confirmed_staging r2
                        INNER JOIN private.reservation_beats rb2 ON rb2.beat = r2.resource
                        INNER JOIN private.beats b2 ON b2.id = rb2.beat_id
                        WHERE r2.cr_name = cr2.rod_name
                          AND r2.date = cr2.catch_date
                          AND b2.beat = cr2.beat
                          AND r2.name != 'Synthetic'
                    )
              )
            ORDER BY cr.catch_date
        """)
    ).fetchall()
    return rows


def check_duplicate_catch_returns(conn):
    """
    Should always be empty - the partial unique index
    (rod_name, catch_date, beat) WHERE guest=false enforces this at the DB
    level. A hit here is a smoke test failure, not a data entry edge case.
    """
    rows = conn.execute(
        text("""
            SELECT rod_name, catch_date, beat, count(*) AS n
            FROM private.catch_returns_staging_table
            WHERE guest = false
            GROUP BY rod_name, catch_date, beat
            HAVING count(*) > 1
        """)
    ).fetchall()
    return rows


CHECKS = [
    ("Stale Synthetic reservations (never superseded by a real download)", check_stale_synthetic_reservations),
    ("Unresolved beat mismatches (reservation never fulfilled or DNF'd)", check_unresolved_beat_mismatches),
    ("Uncorrected wrong-beat submissions", check_uncorrected_wrong_beat_submissions),
    ("Duplicate non-guest catch returns (should never happen)", check_duplicate_catch_returns),
]


if __name__ == "__main__":
    datestamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    print("===============================================")
    print(f"Reservations/Catch Returns data audit - {datestamp}")
    print("Read-only: no changes are made. Flagged rows need manual review.")
    print("===============================================")

    engine = build_engine()
    total_flagged = 0

    with engine.connect() as conn:
        for title, check_fn in CHECKS:
            rows = check_fn(conn)
            print(f"\n{title}: {len(rows)} found")
            for row in rows:
                print(f"   {dict(row._mapping)}")
            total_flagged += len(rows)

    print("\n===============================================")
    if total_flagged == 0:
        print("✅ No anomalies found.")
    else:
        print(f"⚠️  {total_flagged} row(s) flagged across all checks - review above.")
