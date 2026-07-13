-- append_reservations_from_res_conf_staging and append_catch_returns_from_cr_staging_table
-- (created in 20260623112752 / 20260623155018) still referenced public.reservations_confirmed_staging,
-- public.catch_returns_staging_table and public.beats - all moved to the private schema by
-- 20260625160123 and 20260626203224, which were applied after these functions were written.
-- append_catch_returns_from_cr_staging_table also targeted an ON CONFLICT ON CONSTRAINT that
-- was never a real constraint (uq_priv_catch_returns_member_date_beat_if_not_guest is a plain
-- CREATE UNIQUE INDEX from the same migration, not an ALTER TABLE ... ADD CONSTRAINT).
-- Both discovered broken while testing the new private.rollover_season() function, which calls both.
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
    ORDER BY
        rcs.date,
        b.beat_id,
        CASE WHEN lower(rcs.name) = 'synthetic' THEN 1 ELSE 0 END
    ON CONFLICT ON CONSTRAINT uq_priv_reservation_confirmed_date_member_beat DO NOTHING;

END;
$function$
;

CREATE OR REPLACE FUNCTION private.append_catch_returns_from_cr_staging_table()
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
    -- uq_priv_catch_returns_member_date_beat_if_not_guest is a partial unique INDEX
    -- (20260623112752), not a table CONSTRAINT, so ON CONFLICT ON CONSTRAINT can't
    -- target it - infer the same index by its columns/predicate instead.
    ON CONFLICT (member_name, catch_date, beats_id) WHERE (guest = false) DO NOTHING;

END;
$function$
;
