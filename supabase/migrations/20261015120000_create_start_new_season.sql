-- Start-of-season switch. Two settings hold "the current year" and must move
-- together each April, once the new year's members have been loaded:
--   private.year_param          - target_year and season dates; drives the
--                                 reservations ETL, the report views and the
--                                 season bounds in index_supabase.html's RPCs
--   private.club_settings       - current_member_year; drives the member
--                                 lookup in every index_supabase.html RPC
-- Until now nothing set current_member_year, and year_param was only set as
-- a side effect of running the catch-return report. This sets both in one
-- transaction. Run via rac_reports.py option "Start new season".
--
-- Refuses to run (nothing changed) unless:
--   - p_year is the current target_year or the one after (re-running for the
--     current year just re-applies the same values);
--   - members have been loaded for p_year;
--   - last season's rollover (private.rollover_season) has been done, i.e.
--     if staging holds reservations / catch returns for p_year - 1, the
--     archive tables have rows for that year too. Once the new season's
--     reservations ETL runs it removes last season's reservations from
--     staging, so they must be archived first.

CREATE OR REPLACE FUNCTION private.start_new_season(p_year integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_current_year int;
    v_members      bigint;
    v_prev_start   date := make_date(p_year - 1, 1, 1);
    v_prev_end     date := make_date(p_year, 1, 1);   -- exclusive
    v_res_staged   bigint;
    v_res_archived bigint;
    v_cr_staged    bigint;
    v_cr_archived  bigint;
BEGIN
    SELECT target_year INTO v_current_year
    FROM private.year_param
    WHERE id = 1
    FOR UPDATE;

    IF v_current_year IS NULL THEN
        RAISE EXCEPTION 'start_new_season: private.year_param.target_year is not set';
    END IF;

    IF p_year NOT IN (v_current_year, v_current_year + 1) THEN
        RAISE EXCEPTION 'start_new_season: % is not the current season (%) or the next one; nothing changed',
            p_year, v_current_year;
    END IF;

    SELECT count(*) INTO v_members
    FROM private.members
    WHERE year_of_membership = p_year;

    IF v_members = 0 THEN
        RAISE EXCEPTION 'start_new_season: no members loaded for %; nothing changed', p_year;
    END IF;

    SELECT count(*) INTO v_res_staged
    FROM private.reservations_confirmed_staging
    WHERE date >= v_prev_start AND date < v_prev_end;

    SELECT count(*) INTO v_res_archived
    FROM private.reservations_confirmed
    WHERE date >= v_prev_start AND date < v_prev_end;

    SELECT count(*) INTO v_cr_staged
    FROM private.catch_returns_staging_table
    WHERE catch_date >= v_prev_start AND catch_date < v_prev_end;

    SELECT count(*) INTO v_cr_archived
    FROM private.catch_returns
    WHERE catch_date >= v_prev_start AND catch_date < v_prev_end;

    IF (v_res_staged > 0 AND v_res_archived = 0) OR (v_cr_staged > 0 AND v_cr_archived = 0) THEN
        RAISE EXCEPTION 'start_new_season: % season has not been rolled over (run rollover_season first); nothing changed',
            p_year - 1;
    END IF;

    UPDATE private.year_param
    SET target_year       = p_year,
        target_start_date = make_date(p_year, 4, 1),
        target_end_date   = make_date(p_year, 9, 30)
    WHERE id = 1;

    UPDATE private.club_settings
    SET value_hash = p_year::text
    WHERE key = 'current_member_year';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'start_new_season: club_settings has no current_member_year row; nothing changed';
    END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION private.start_new_season(integer) FROM PUBLIC, anon, authenticated;
