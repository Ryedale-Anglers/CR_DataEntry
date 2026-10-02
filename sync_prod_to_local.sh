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
#   ./sync_prod_to_local.sh                          # full sync, latest backup
#   ./sync_prod_to_local.sh /path/to/specific.dump    # full sync, specified backup
#   ./sync_prod_to_local.sh --tables-only             # staging tables only, latest backup
#   ./sync_prod_to_local.sh --tables-only /path/to/specific.dump
#
# --tables-only restores just private.reservations_confirmed_staging and
# private.catch_returns_staging_table, leaving every other local table
# (members, beats, reservations_confirmed, catch_returns, club_settings, ...)
# untouched. Useful for refreshing local test data with a recent production
# snapshot of in-season activity without disturbing anything else local
# testing depends on.
#
# Note: catch_returns_staging_table carries a CHECK constraint
# (chk_guest_dnf_mutually_exclusive) that --disable-triggers does NOT bypass
# (it only suspends triggers, not constraints). If the chosen dump contains a
# pre-existing guest=true AND dnf=true row, that table's restore will fail
# and be left empty. Shouldn't occur from normal use of index_supabase.html,
# but worth knowing if a restore ever errors out here.

set -euo pipefail

# `supabase status` resolves the project from the CWD, so this can't rely on
# being invoked from inside this repo (e.g. rac_reports.py in a sibling repo
# shells out to this script from its own directory) - pin it explicitly. Any
# relative dump-file argument below is resolved against ORIGINAL_PWD (the
# caller's actual directory), not this repo, so that still works as expected.
ORIGINAL_PWD="$PWD"
REPO_DIR="/home/brian/Documents/github/CR_DataEntry"
cd "$REPO_DIR"

BACKUP_DIR="/var/backups/cr-dataentry"
LOCAL_DB_URL="postgresql://postgres:postgres@localhost:54322/postgres"
SCHEMAS=(public private)
# Unqualified names - pg_restore's --table on this version does not match
# the schema-qualified form (private.x silently selects nothing); confirmed
# unqualified names are unambiguous across the whole dump for these two.
STAGING_TABLES=(reservations_confirmed_staging catch_returns_staging_table)

# --- 0. Parse args ---
TABLES_ONLY=false
if [[ "${1:-}" == "--tables-only" ]]; then
    TABLES_ONLY=true
    shift
fi

echo "==============================================="
if $TABLES_ONLY; then
    echo " CR_DataEntry: Sync Production Data -> Local (staging tables only)"
else
    echo " CR_DataEntry: Sync Production Data -> Local (full schema)"
fi
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
    if [[ "$DUMP_FILE" != /* ]]; then
        DUMP_FILE="$ORIGINAL_PWD/$DUMP_FILE"
    fi
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
if $TABLES_ONLY; then
    echo "⚠️  This will WIPE existing data in LOCAL only, in these two tables:"
    echo "     - private.reservations_confirmed_staging"
    echo "     - private.catch_returns_staging_table"
    echo "   and replace it with data from the backup above."
    echo "   Every other local table is left untouched."
else
    echo "⚠️  This will WIPE existing data in LOCAL only, in the ${SCHEMAS[*]} schema(s)"
    echo "   (every table in them), and replace it with data from the backup above."
fi
echo "   This always targets the LOCAL database (${LOCAL_DB_URL}) - production is"
echo "   never written to by this script."
echo "   Schema objects (tables/views/functions) are left untouched -"
echo "   make sure local schema is already current via 'supabase db reset'"
echo "   or 'supabase db push' before continuing."
echo ""
read -p "Continue? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

if $TABLES_ONLY; then
    # --- 4. Truncate the two staging tables ---
    echo ""
    echo "🧹 Truncating staging tables before reload..."
    psql "$LOCAL_DB_URL" -c "TRUNCATE TABLE private.reservations_confirmed_staging, private.catch_returns_staging_table RESTART IDENTITY CASCADE;"
    echo "✅ Truncated staging tables."

    # --- 5. Data-only restore, staging tables only ---
    echo ""
    echo "🔄 Restoring staging tables..."
    pg_restore \
        --data-only \
        --disable-triggers \
        --no-owner \
        --no-acl \
        --table="${STAGING_TABLES[0]}" \
        --table="${STAGING_TABLES[1]}" \
        --dbname="$LOCAL_DB_URL" \
        --verbose \
        "$DUMP_FILE"
    echo "✅ Staging tables restored."
else
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
fi

echo ""
echo "==============================================="
echo "✅ Local database refreshed from: $(basename "$DUMP_FILE")"
echo "==============================================="
