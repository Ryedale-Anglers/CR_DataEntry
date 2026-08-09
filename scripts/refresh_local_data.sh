#!/bin/bash
set -e

LOCAL_DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
DUMP_FILE="/tmp/prod_data.sql"

echo "Dumping production data..."
supabase db dump --data-only --linked --schema public,private -f "$DUMP_FILE"

echo "Resetting local database to clean schema (reapplies migrations + any seed.sql)..."
supabase db reset

echo "Truncating all public/private tables to clear seeded rows before loading production data..."
TABLES=$(psql "$LOCAL_DB" -Atc "
    SELECT string_agg(format('%I.%I', schemaname, tablename), ', ')
    FROM pg_tables
    WHERE schemaname IN ('public', 'private')
")

if [ -n "$TABLES" ]; then
    psql "$LOCAL_DB" -c "TRUNCATE $TABLES RESTART IDENTITY CASCADE;"
else
    echo "No tables found in public/private schemas — skipping truncate."
fi

echo "Loading production data into local..."
psql "$LOCAL_DB" -v ON_ERROR_STOP=1 -f "$DUMP_FILE"

echo "Done. Local now mirrors production data."
