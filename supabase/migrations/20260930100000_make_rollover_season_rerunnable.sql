-- Makes private.rollover_season() safely re-runnable for the target year.
--
-- Previously the append functions used ON CONFLICT DO NOTHING, so a re-run never
-- picked up edits/deletions made in staging, and rollover_season() emptied both
-- staging tables afterwards (a second run would then find nothing to promote).
--
-- Now staging is no longer truncated daily (reservations ETL reconciles instead;
-- catch returns are written directly by index_supabase.html), so:
--   1. rollover_season() leaves staging untouched.
--   2. It refuses to run (RAISE EXCEPTION) if either staging table has no rows
--      for the target year, BEFORE deleting anything.
--   3. It deletes only the target calendar year's rows from reservations_confirmed
--      (by date) and catch_returns (by catch_date), then re-inserts that year from
--      staging. Earlier years are untouched. All in one transaction.
-- Both append functions now filter staging to the target year so the delete and
-- the insert cover exactly the same rows.

-- The catch returns append function now takes the target year.
DROP FUNCTION IF EXISTS private.append_catch_returns_from_cr_staging_table();

CREATE OR REPLACE FUNCTION private.append_catch_returns_from_cr_staging_table(target_year integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    INSERT INTO private.catch_returns (
        member_name,
        catch_date,
        brown_trout,
        brown_trout_killed,
        grayling,
        rainbow_trout,
        other_species,
        guest,
        beats_id,
        dnf
    )
    SELECT
        crst.rod_name,
        crst.catch_date,
        crst.brown_trout_released,
        crst.brown_trout_retained,
        crst.grayling,
        crst.rainbow_trout,
        crst.other_species,
        crst.guest,
        b.id,
        crst.dnf
    FROM private.catch_returns_staging_table crst
    INNER JOIN private.beats b ON crst.beat = b.beat
    WHERE crst.catch_date >= make_date(target_year, 1, 1)
      AND crst.catch_date <  make_date(target_year + 1, 1, 1)
    -- uq_priv_catch_returns_member_date_beat_if_not_guest is a partial unique INDEX,
    -- so infer it by columns/predicate rather than ON CONFLICT ON CONSTRAINT.
    ON CONFLICT (member_name, catch_date, beats_id) WHERE (guest = false) DO NOTHING;
END;
$function$;

CREATE OR REPLACE FUNCTION private.append_reservations_from_res_conf_staging(target_year integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    INSERT INTO private.reservations_confirmed ("date", members_id, beats_id)
    SELECT DISTINCT ON (rcs.date, b.beat_id)
        rcs.date, m.id, b.beat_id
    FROM private.reservations_confirmed_staging rcs
    INNER JOIN private.members m ON rcs.cr_name = m.cr_name
    INNER JOIN private.reservation_beats b ON rcs.resource = b.beat
    WHERE m.year_of_membership = target_year
      AND rcs.date >= make_date(target_year, 1, 1)
      AND rcs.date <  make_date(target_year + 1, 1, 1)
    ORDER BY
        rcs.date,
        b.beat_id,
        CASE WHEN lower(rcs.name) = 'synthetic' THEN 1 ELSE 0 END
    ON CONFLICT ON CONSTRAINT uq_priv_reservation_confirmed_date_member_beat DO NOTHING;
END;
$function$;

CREATE OR REPLACE FUNCTION private.rollover_season()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_target_year int;
    v_year_start  date;
    v_year_end    date;   -- exclusive
    v_res_staged  bigint;
    v_cr_staged   bigint;
BEGIN
    SELECT target_year INTO v_target_year
    FROM private.year_param
    WHERE id = 1;

    IF v_target_year IS NULL THEN
        RAISE EXCEPTION 'rollover_season: private.year_param.target_year is not set';
    END IF;

    v_year_start := make_date(v_target_year, 1, 1);
    v_year_end   := make_date(v_target_year + 1, 1, 1);

    -- Guard: never delete the year's data unless there is something to replace it with.
    SELECT count(*) INTO v_res_staged
    FROM private.reservations_confirmed_staging
    WHERE date >= v_year_start AND date < v_year_end;

    SELECT count(*) INTO v_cr_staged
    FROM private.catch_returns_staging_table
    WHERE catch_date >= v_year_start AND catch_date < v_year_end;

    IF v_res_staged = 0 THEN
        RAISE EXCEPTION 'rollover_season: no reservations_confirmed_staging rows for %; nothing deleted', v_target_year;
    END IF;
    IF v_cr_staged = 0 THEN
        RAISE EXCEPTION 'rollover_season: no catch_returns_staging_table rows for %; nothing deleted', v_target_year;
    END IF;

    -- Clear the target year only, then re-promote it fresh. Earlier years untouched.
    DELETE FROM private.reservations_confirmed
    WHERE date >= v_year_start AND date < v_year_end;

    DELETE FROM private.catch_returns
    WHERE catch_date >= v_year_start AND catch_date < v_year_end;

    PERFORM private.append_reservations_from_res_conf_staging(v_target_year);
    PERFORM private.append_catch_returns_from_cr_staging_table(v_target_year);

    -- Staging is intentionally left as is.
END;
$function$;
