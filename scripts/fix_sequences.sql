-- Move every id counter (identity/serial sequence) in the public and private
-- schemas up to the table's highest existing id, so the next insert gets a
-- new id instead of failing with "duplicate key value violates unique
-- constraint ..._pkey".
--
-- Counters fall behind when rows arrive with their id already set, without
-- the counter's own value - e.g. restoring selected tables from a dump
-- (pg_restore --table, as sync_prod_to_local.sh --tables-only does), or
-- importing rows with an id column in Studio / DBeaver / pandas.
--
-- Only ever raises a counter; never lowers one (so ids of deleted rows are
-- never reused). Safe to run on any database, any number of times:
--   psql "$DB_URL" -f scripts/fix_sequences.sql
DO $$
DECLARE
    r       record;
    v_max   bigint;
    v_last  bigint;
    v_called boolean;
    v_fixed int := 0;
BEGIN
    FOR r IN
        SELECT n.nspname AS schema_name, c.relname AS table_name, a.attname AS column_name,
               pg_get_serial_sequence(format('%I.%I', n.nspname, c.relname), a.attname) AS seq
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
        WHERE c.relkind = 'r'
          AND n.nspname IN ('public', 'private')
          AND pg_get_serial_sequence(format('%I.%I', n.nspname, c.relname), a.attname) IS NOT NULL
        ORDER BY 1, 2
    LOOP
        EXECUTE format('SELECT max(%I) FROM %I.%I', r.column_name, r.schema_name, r.table_name) INTO v_max;
        EXECUTE format('SELECT last_value, is_called FROM %s', r.seq) INTO v_last, v_called;
        -- Behind if the next id would be <= the highest existing id.
        IF v_max IS NOT NULL AND (v_max > v_last OR (v_max = v_last AND NOT v_called)) THEN
            PERFORM setval(r.seq, v_max, true);
            v_fixed := v_fixed + 1;
            RAISE NOTICE 'fixed %.%: counter % -> % (next id %)',
                r.schema_name, r.table_name, v_last, v_max, v_max + 1;
        END IF;
    END LOOP;
    RAISE NOTICE 'id counters checked; % fixed', v_fixed;
END $$;
