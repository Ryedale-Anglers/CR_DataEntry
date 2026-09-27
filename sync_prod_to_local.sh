#!/bin/bash
#
# sync_prod_to_local.sh
#
# Restores the most recent (or a specified) production pg_dump backup of
# CR_DataEntry into the local Supabase Postgres instance. Data only - it does
# NOT touch schema, so your local `public`/`private` schema must already be
# up to date via `supabase db reset` / `supabase db push` before running this.
#
# Usage:
#   ./sync_prod_to_local.sh              # restores the latest backup found
#   ./sync_prod_to_local.sh /path/to/specific_backup.dump

set -euo pipefail

BACKUP_DIR="/var/backups/cr-dataentry"
LOCAL_DB_URL="postgresql://postgres:postgres@localhost:54322/postgres"
SCHEMAS=(public private)

echo "==============================================="
echo " CR_DataEntry: Sync Production Data -> Local"
echo "==============================================="

# --- 1. Confirm local Supabase is running ---
echo "Checking local Supabase status..."
if ! supabase status >/dev/null 2>&1; then
    echo "❌ Local Supabase does not appear to be running."
    echo "   Run 'supabase start' (or use supabase_mgr.sh) first, then retry."
    exit 1
fi
echo "✅ Local Supabase is running."

# --- 2. Pick the dump file ---
if [ $# -eq 1 ]; then
    DUMP_FILE="$1"
    if [ ! -f "$DUMP_FILE" ]; then
        echo "❌ Specified backup file not found: $DUMP_FILE"
        exit 1
    fi
else
    DUMP_FILE=$(ls -t "$BACKUP_DIR"/cr_dataentry_*.dump 2>/dev/null | head -n 1)
    if [ -z "$DUMP_FILE" ]; then
        echo "❌ No backup files found in $BACKUP_DIR"
        exit 1
    fi
fi

echo ""
echo "Selected backup: $DUMP_FILE"
ls -lh "$DUMP_FILE"
echo ""

# --- 3. Confirm before doing anything destructive ---
echo "⚠️  This will WIPE existing data in the local ${SCHEMAS[*]} schema(s)"
echo "   and replace it with data from the backup above."
echo "   Schema objects (tables/views/functions) are left untouched -"
echo "   make sure local schema is already current via 'supabase db reset'"
echo "   or 'supabase db push' before continuing."
echo ""
read -p "Continue? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# --- 4. Truncate existing data first (pg_restore --data-only can't use --clean) ---
echo ""
echo "🧹 Truncating existing data in ${SCHEMAS[*]} schema(s) before reload..."
for SCHEMA in "${SCHEMAS[@]}"; do
    TRUNCATE_SQL=$(psql "$LOCAL_DB_URL" -Atqc "
        SELECT string_agg(format('TRUNCATE TABLE %I.%I RESTART IDENTITY CASCADE;', schemaname, tablename), ' ')
        FROM pg_tables
        WHERE schemaname = '$SCHEMA';
    ")
    if [ -n "$TRUNCATE_SQL" ]; then
        psql "$LOCAL_DB_URL" -c "$TRUNCATE_SQL"
        echo "✅ Truncated tables in schema '$SCHEMA'."
    else
        echo "ℹ️  No tables found in schema '$SCHEMA' - nothing to truncate."
    fi
done

# --- 5. Data-only restore, schema untouched ---
# --data-only        : never touch table/view/function definitions
# --disable-triggers  : avoids FK constraint errors while loading out of order
# --no-owner --no-acl : local roles won't match production roles/owners
# (tables are truncated above instead of using --clean, which pg_restore
#  disallows combining with --data-only)
for SCHEMA in "${SCHEMAS[@]}"; do
    echo ""
    echo "🔄 Restoring schema: $SCHEMA ..."
    pg_restore \
        --data-only \
        --disable-triggers \
        --no-owner \
        --no-acl \
        --schema="$SCHEMA" \
        --dbname="$LOCAL_DB_URL" \
        --verbose \
        "$DUMP_FILE"
    echo "✅ Schema '$SCHEMA' restored."
done

echo ""
echo "==============================================="
echo "✅ Local database refreshed from: $(basename "$DUMP_FILE")"
echo "==============================================="
