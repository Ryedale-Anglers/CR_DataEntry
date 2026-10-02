-- DNF ("Did Not Fish") catch returns, and the reservations they relate to, did not
-- happen, so they must not be promoted from staging into the final tables.
--
--  * append_catch_returns_from_cr_staging_table: skip staging rows where dnf is true.
--  * append_reservations_from_res_conf_staging: skip any staging reservation that has a
--    DNF catch return for the same date, member and beat. The beat is compared through
--    private.beats (reservation_beats.beat_id), so the "17. Fishing Hut" and
--    "18. Railway Bridge" resources both match the combined beat 4.
--
-- The DNF filter runs before the one-reservation-per-date-and-beat rule, so when a
-- DNF reservation is dropped, another member's (e.g. synthetic) reservation for the
-- same date and beat can be promoted in its place.
-- Staging is untouched, so the in-season views that read staging still see the DNFs.
-- rollover_season() is unchanged: it deletes the target year from the final tables and
-- re-promotes it, so re-running it removes DNF rows already present for that year.

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
      AND crst.dnf IS NOT TRUE
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
    INNER JOIN private.beats bt ON bt.id = b.beat_id
    WHERE m.year_of_membership = target_year
      AND rcs.date >= make_date(target_year, 1, 1)
      AND rcs.date <  make_date(target_year + 1, 1, 1)
      AND NOT EXISTS (
            SELECT 1
            FROM private.catch_returns_staging_table dnf
            WHERE dnf.dnf IS TRUE
              AND dnf.catch_date = rcs.date
              AND dnf.rod_name   = rcs.cr_name
              AND dnf.beat       = bt.beat
          )
    ORDER BY
        rcs.date,
        b.beat_id,
        CASE WHEN lower(rcs.name) = 'synthetic' THEN 1 ELSE 0 END
    ON CONFLICT ON CONSTRAINT uq_priv_reservation_confirmed_date_member_beat DO NOTHING;
END;
$function$;
