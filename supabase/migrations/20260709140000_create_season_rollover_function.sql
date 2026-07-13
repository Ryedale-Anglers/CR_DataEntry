-- Bundles the existing manual end-of-season steps (promote staging rows into
-- the confirmed tables used for reporting/multi-year analysis, then clear the
-- staging tables ready for next season) into a single command. Still invoked
-- manually by the club secretary when the season is deemed over - not scheduled.
CREATE OR REPLACE FUNCTION private.rollover_season()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_target_year int;
BEGIN
    SELECT target_year INTO v_target_year
    FROM private.year_param
    WHERE id = 1;

    PERFORM private.append_reservations_from_res_conf_staging(v_target_year);
    PERFORM private.append_catch_returns_from_cr_staging_table();

    DELETE FROM private.reservations_confirmed_staging;
    DELETE FROM private.catch_returns_staging_table;
END;
$function$;
