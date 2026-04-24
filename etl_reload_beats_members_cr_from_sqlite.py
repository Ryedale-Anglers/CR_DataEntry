import os
import pandas as pd
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

# Load variables from .env
load_dotenv()

# --- CONFIGURATION FROM ENV ---
SQLITE_DB_PATH = os.getenv('SQLITE_DB_PATH')
SUPABASE_CONN_STRING = os.getenv('LOCAL_DB_URL')

if not SUPABASE_CONN_STRING or not SQLITE_DB_PATH:
    raise ValueError("Missing environment variables. Check your .env file.")
#1
sqlite_engine = create_engine(f'sqlite:///{SQLITE_DB_PATH}')
# 2. Connect to Supabase
supabase_engine = create_engine(SUPABASE_CONN_STRING)

def migrate_beats(conn):
    try:
        # 1. Connect to SQLite and extract data
        print(f"Reading beats data from {SQLITE_DB_PATH}...")
        df = pd.read_sql('SELECT * FROM beats', sqlite_engine)
        
        # Mapping SQLite column names (PascalCase) to Supabase (snake_case)
        df.columns = ['id', 'beat', 'beat_short', 'river_order', 'upper_lower']
        print(f"Successfully extracted {len(df)} beats records.")        
       
        # 3. Truncate target table and reset identity
        print("Truncating Supabase table...")
        conn.execute(text("TRUNCATE TABLE public.beats RESTART IDENTITY CASCADE;"))
        
        # 4. Load data (maintaining the 'id' values)
        print("Loading data into Supabase...")
        df.to_sql(
            'beats', 
            conn, 
            schema='public', 
            if_exists='append', 
            index=False, 
            method='multi'
        )
        
        # 5. Sync the identity sequence
        # Since we manually inserted IDs, we must update the sequence 
        # so the next auto-insert starts at the correct number.
        print("Syncing identity sequence...")
        conn.execute(text("""
            SELECT setval(
                pg_get_serial_sequence('public.beats', 'id'), 
                COALESCE(MAX(id), 1)
            ) FROM public.beats;
        """))

        print("✅ Migration complete.")

    except Exception as e:
        print(f"❌ Migration failed: {e}")

def migrate_reservation_beats(conn):
    try:
        # 1. Connect to SQLite and extract data
        print(f"Reading reservation beats data from {SQLITE_DB_PATH}...")
        df = pd.read_sql('SELECT * FROM reservation_beats', sqlite_engine)
        
        # Mapping SQLite column names (PascalCase) to Supabase (snake_case)
        df.columns = ['id', 'beat', 'beat_id']
        print(f"Successfully extracted {len(df)} reservation beats records.")        
       
        # 3. Truncate target table and reset identity
        print("Truncating Supabase table...")
        conn.execute(text("TRUNCATE TABLE public.reservation_beats RESTART IDENTITY CASCADE;"))
        
        # 4. Load data (maintaining the 'id' values)
        print("Loading data into Supabase...")
        df.to_sql(
            'reservation_beats', 
            conn, 
            schema='public', 
            if_exists='append', 
            index=False, 
            method='multi'
        )
        
        # 5. Sync the identity sequence
        # Since we manually inserted IDs, we must update the sequence 
        # so the next auto-insert starts at the correct number.
        print("Syncing identity sequence...")
        conn.execute(text("""
            SELECT setval(
                pg_get_serial_sequence('public.reservation_beats', 'id'), 
                COALESCE(MAX(id), 1)
            ) FROM public.reservation_beats;
        """))

        print("✅ Migration complete.")

    except Exception as e:
        print(f"❌ Migration failed: {e}")

def migrate_members(conn):
    try:
        # 1. Connect to SQLite and extract data
        print(f"Reading members data from {SQLITE_DB_PATH}...")
        df = pd.read_sql('SELECT * FROM members', sqlite_engine)
        
        # Mapping SQLite column names (PascalCase) to Supabase (snake_case)
        df.columns = ['id', 'cr_name', 'email_address', 'member_name', 'year_of_membership']
        print(f"Successfully extracted {len(df)} member records.")

        
        # Truncate target table and reset identity
        print("Truncating Supabase table...")
        conn.execute(text("TRUNCATE TABLE public.members RESTART IDENTITY CASCADE;"))
        
        # Load data (maintaining the 'id' values)
        print("Loading data into Supabase...")
        df.to_sql(
            'members', 
            conn, 
            schema='public', 
            if_exists='append', 
            index=False, 
            method='multi'
        )
        
        # Sync the identity sequence
        # Since we manually inserted IDs, we must update the sequence 
        # so the next auto-insert starts at the correct number.
        print("Syncing identity sequence...")
        conn.execute(text("""
            SELECT setval(
                pg_get_serial_sequence('public.members', 'id'), 
                COALESCE(MAX(id), 1)
            ) FROM public.members;
        """))

        print("✅ Migration complete.")

    except Exception as e:
        print(f"❌ Migration failed: {e}")

def migrate_historic_catchreturns(conn):
    try:
        # 1. Connect to SQLite and extract data
        print(f"Reading Historic Catch Returns data from {SQLITE_DB_PATH}...")
        #df = pd.read_sql('SELECT * FROM catchreturns', sqlite_engine)
        # 1. Extract specifically named columns to avoid the "10 vs 9" length mismatch
        query = """
            SELECT 
                ID, MemberName, CatchDate, BrownTrout, BrownTroutKilled, 
                Grayling, RainBowTrout, OtherSpecies, Guest, Beats_ID 
            FROM catchreturns
        """
        df = pd.read_sql(query, sqlite_engine)

        # Mapping SQLite column names (PascalCase) to Supabase (snake_case)
        df.columns = [
            'id', 'member_name', 'catch_date', 'brown_trout', 'brown_trout_killed', 
            'grayling', 'rainbow_trout', 'other_species', 'guest', 'beats_id'
        ]
        print(f"Successfully extracted {len(df)} historic catch return records.")

        
        # Truncate target table and reset identity
        print("Truncating Supabase table...")
        conn.execute(text("TRUNCATE TABLE public.catch_returns RESTART IDENTITY CASCADE;"))

        # 3. FIX DATA TYPES
        
        # Convert 'guest' to actual Boolean (True/False)
        # This converts 1/0 or '1'/'0' to actual Python Booleans which Postgres accepts
        # This handles strings, integers, and actual booleans correctly
        map_bool = {
            'TRUE': True, 'True': True, 1: True, True: True,
            'FALSE': False, 'False': False, 0: False, False: False,
            None: False # or True, depending on your business logic
        }

        df['id'] = df['id'].astype(int)
        df['guest'] = df['guest'].map(map_bool).fillna(False).astype(bool)

        # Ensure numeric columns are actually numeric (handle potential NaNs)
        numeric_cols = ['brown_trout', 'brown_trout_killed', 'grayling', 'rainbow_trout', 'other_species', 'beats_id']
        for col in numeric_cols:
            df[col] = pd.to_numeric(df[col], errors='coerce')

        # 4. Handle the 'dnf' column (Optional)
        # If you want to explicitly set the 11th column:
        df['dnf'] = False
        
        # Load data (maintaining the 'id' values)
        print("Loading data into Supabase...")
        # Load to Supabase
        df.to_sql(
            'catch_returns', 
            conn, 
            if_exists='append', 
            index=False, 
            method='multi',
            chunksize=500 # Smaller chunks can help identify which row causes an error
        )
        
        # Sync the identity sequence
        # Since we manually inserted IDs, we must update the sequence 
        # so the next auto-insert starts at the correct number.
        print("Syncing identity sequence...")
        conn.execute(text("""
            SELECT setval(
                pg_get_serial_sequence('public.catch_returns', 'id'), 
                COALESCE(MAX(id), 1)
            ) FROM public.catch_returns;
        """))

        print("✅ Migration complete.")

    except Exception as e:
        print(f"❌ Migration failed: {e}")

def migrate_report_versions(conn):
    try:
        # 1. Connect to SQLite and extract data
        print(f"Reading report versions data from {SQLITE_DB_PATH}...")
        df = pd.read_sql('SELECT * FROM ReportVersionTable', sqlite_engine)
        
        # Mapping SQLite column names (PascalCase) to Supabase (snake_case)
        df.columns = ['id', 'report_version', 'report_year', 'changes_txt', 'creation_date', 'report_type']
        print(f"Successfully extracted {len(df)} report versions records.")        
       
        # 3. Truncate target table and reset identity
        print("Truncating Supabase table...")
        conn.execute(text("TRUNCATE TABLE public.report_versions RESTART IDENTITY CASCADE;"))
        
        # 4. Load data (maintaining the 'id' values)
        print("Loading data into Supabase...")
        df.to_sql(
            'report_versions', 
            conn, 
            schema='public', 
            if_exists='append', 
            index=False, 
            method='multi'
        )
        
        # 5. Sync the identity sequence
        # Since we manually inserted IDs, we must update the sequence 
        # so the next auto-insert starts at the correct number.
        print("Syncing identity sequence...")
        conn.execute(text("""
            SELECT setval(
                pg_get_serial_sequence('public.report_versions', 'id'), 
                COALESCE(MAX(id), 1)
            ) FROM public.report_versions;
        """))

        print("✅ Migration complete.")

    except Exception as e:
        print(f"❌ Migration failed: {e}")

if __name__ == "__main__":
    with supabase_engine.begin() as conn: 
        migrate_beats(conn)
        migrate_reservation_beats(conn)
        migrate_members(conn)
        migrate_historic_catchreturns(conn)
        migrate_report_versions(conn)
