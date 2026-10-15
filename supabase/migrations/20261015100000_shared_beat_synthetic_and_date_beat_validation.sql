-- Three fixes to the reservation-first catch return functions, found in the
-- pre-cutover review of index_supabase.html:
--
-- 1. Shared beat, two booking resources. 'Fishing Hut & Railway Bridge'
--    (beats.id = 4) maps to two resources, '17. Fishing Hut' and
--    '18. Railway Bridge'. submit_catch_return_no_reservation and
--    submit_catch_return_different_beat picked a resource for the Synthetic
--    reservation with an unordered LIMIT 1 and only skipped the insert when
--    that exact resource was already reserved. A member whose real booking
--    was on the other resource got a second reservation for the same
--    beat/date - a duplicate row in their reservation list and a double
--    count in the report views. Both now skip the Synthetic insert when the
--    member already has a reservation for any resource of that beat on that
--    date (as the old batch insert_synthetic_reservations did), and pick the
--    resource deterministically. get_member_reservations also collapses
--    reservations on two resources of the same beat/date into one row.
--
-- 2. "Reservation not listed" accepted any date. submit_catch_return_no_reservation
--    now rejects a catch date in the future or outside the current season
--    (private.year_param target_start_date .. target_end_date). The other
--    two submit functions take their date from an existing reservation, so
--    need no extra check.
--
-- 3. "Fished a different beat" accepted the reserved beat itself as the
--    beat actually fished, which marks the reservation DNF and then
--    immediately overwrites that DNF. submit_catch_return_different_beat now
--    rejects p_new_beat = p_original_beat.
--
-- Also: member lookups use upper(cr_name) = upper(p_surname) instead of
-- ILIKE, so '%' / '_' in a surname aren't wildcards (see 20261015110000).
--
-- Signatures are unchanged, so CREATE OR REPLACE keeps the existing grants.

CREATE OR REPLACE FUNCTION public.get_member_reservations(p_password text, p_surname text)
RETURNS TABLE(
    reservation_date date,
    beat             text,
    cr_exists        boolean,
    cr_dnf           boolean,
    cr_submitted_at  text,
    guest_cr_count   integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    pw_valid       boolean;
    current_year   text;
    canonical_name text;
    v_season_start date;
    v_season_end   date;
BEGIN
    SELECT (value_hash = crypt(p_password, value_hash))
    INTO pw_valid
    FROM private.club_settings
    WHERE key = 'shared_catch_password'
    LIMIT 1;

    IF NOT COALESCE(pw_valid, FALSE) THEN
        RAISE EXCEPTION 'Invalid club password';
    END IF;

    SELECT value_hash INTO current_year
    FROM private.club_settings
    WHERE key = 'current_member_year'
    LIMIT 1;

    SELECT cr_name INTO canonical_name
    FROM private.members
    WHERE upper(cr_name) = upper(p_surname)
      AND year_of_membership::text = current_year
    LIMIT 1;

    IF canonical_name IS NULL THEN
        RAISE EXCEPTION 'Member surname not recognised';
    END IF;

    SELECT target_start_date, target_end_date
    INTO v_season_start, v_season_end
    FROM private.year_param
    WHERE id = 1;

    -- DISTINCT ON collapses reservations on two resources of the same beat
    -- (17. Fishing Hut / 18. Railway Bridge) on the same date into one row -
    -- catch returns are keyed by beat, so both would show the same status.
    RETURN QUERY
    SELECT DISTINCT ON (rcs.date, b.beat)
        rcs.date,
        b.beat,
        (crst.id IS NOT NULL) AS cr_exists,
        crst.dnf AS cr_dnf,
        crst."timestamp" AS cr_submitted_at,
        (SELECT COUNT(*)::integer
           FROM private.catch_returns_staging_table gcrst
          WHERE gcrst.rod_name   = rcs.cr_name
            AND gcrst.catch_date = rcs.date
            AND gcrst.beat       = b.beat
            AND gcrst.guest      = true) AS guest_cr_count
    FROM private.reservations_confirmed_staging rcs
    INNER JOIN private.reservation_beats rb ON rb.beat = rcs.resource
    INNER JOIN private.beats b ON b.id = rb.beat_id
    LEFT JOIN private.catch_returns_staging_table crst
        ON crst.rod_name = rcs.cr_name
        AND crst.catch_date = rcs.date
        AND crst.beat = b.beat
        AND crst.guest = false
    WHERE rcs.cr_name = canonical_name
      AND rcs.date BETWEEN v_season_start AND v_season_end
    ORDER BY rcs.date DESC, b.beat;
END;
$function$;


CREATE OR REPLACE FUNCTION public.submit_catch_return_different_beat(
    p_password text,
    p_surname text,
    p_original_beat text,
    p_catch_date date,
    p_new_beat text,
    p_dnf boolean DEFAULT false,
    p_bt_released integer DEFAULT 0,
    p_grayling integer DEFAULT 0,
    p_rainbow integer DEFAULT 0,
    p_other integer DEFAULT 0,
    p_bt_retained integer DEFAULT 0,
    p_comments text DEFAULT ''::text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    pw_valid                       boolean;
    current_year                   text;
    canonical_name                 text;
    v_original_reservation_exists  boolean;
    v_new_beat_id                  integer;
    v_new_resource                 text;
BEGIN
    SELECT (value_hash = crypt(p_password, value_hash))
    INTO pw_valid
    FROM private.club_settings
    WHERE key = 'shared_catch_password'
    LIMIT 1;

    IF NOT COALESCE(pw_valid, FALSE) THEN
        RAISE EXCEPTION 'Invalid club password';
    END IF;

    SELECT value_hash INTO current_year
    FROM private.club_settings
    WHERE key = 'current_member_year'
    LIMIT 1;

    SELECT cr_name INTO canonical_name
    FROM private.members
    WHERE upper(cr_name) = upper(p_surname)
      AND year_of_membership::text = current_year
    LIMIT 1;

    IF canonical_name IS NULL THEN
        RAISE EXCEPTION 'Member surname not recognised';
    END IF;

    IF p_new_beat = p_original_beat THEN
        RAISE EXCEPTION 'The beat you fished is the beat you reserved - use Enter Catch Return instead.';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM private.reservations_confirmed_staging rcs
        INNER JOIN private.reservation_beats rb ON rb.beat = rcs.resource
        INNER JOIN private.beats b ON b.id = rb.beat_id
        WHERE rcs.cr_name = canonical_name
          AND rcs.date = p_catch_date
          AND b.beat = p_original_beat
    ) INTO v_original_reservation_exists;

    IF NOT v_original_reservation_exists THEN
        RAISE EXCEPTION 'No reservation found for % on %', p_original_beat, p_catch_date;
    END IF;

    -- 1. Mark the original reservation's beat as DNF (unconditional).
    INSERT INTO private.catch_returns_staging_table (
        "timestamp", rod_name, catch_date, beat, dnf, guest,
        brown_trout_released, grayling, rainbow_trout, other_species,
        brown_trout_retained, comments
    ) VALUES (
        NOW()::text, canonical_name, p_catch_date, p_original_beat, true, false,
        0, 0, 0, 0, 0, 'Auto-marked DNF: member fished a different beat'
    )
    ON CONFLICT (rod_name, catch_date, beat)
    WHERE guest = false
    DO UPDATE SET
        "timestamp"           = EXCLUDED."timestamp",
        dnf                   = true,
        brown_trout_released  = 0,
        grayling              = 0,
        rainbow_trout         = 0,
        other_species         = 0,
        brown_trout_retained  = 0,
        comments              = 'Auto-marked DNF: member fished a different beat';

    -- 2. Create a Synthetic reservation for the beat actually fished, unless
    -- the member already has a reservation for any resource of that beat on
    -- that date.
    SELECT bt.id, rb.beat INTO v_new_beat_id, v_new_resource
    FROM private.reservation_beats rb
    INNER JOIN private.beats bt ON rb.beat_id = bt.id
    WHERE bt.beat = p_new_beat
    ORDER BY rb.beat
    LIMIT 1;

    IF v_new_resource IS NULL THEN
        RAISE EXCEPTION 'No resource found for beat: %', p_new_beat;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM private.reservations_confirmed_staging rcs
        INNER JOIN private.reservation_beats rb ON rb.beat = rcs.resource
        WHERE rcs.cr_name = canonical_name
          AND rcs.date = p_catch_date
          AND rb.beat_id = v_new_beat_id
    ) THEN
        INSERT INTO private.reservations_confirmed_staging (date, resource, name, cr_name)
        VALUES (p_catch_date, v_new_resource, 'Synthetic', canonical_name)
        ON CONFLICT (date, cr_name, resource) DO NOTHING;
    END IF;

    -- 3. Insert/update the catch return for the beat actually fished.
    INSERT INTO private.catch_returns_staging_table (
        "timestamp", rod_name, catch_date, beat, dnf, guest,
        brown_trout_released, grayling, rainbow_trout, other_species,
        brown_trout_retained, comments
    ) VALUES (
        NOW()::text, canonical_name, p_catch_date, p_new_beat, p_dnf, false,
        p_bt_released, p_grayling, p_rainbow, p_other, p_bt_retained, p_comments
    )
    ON CONFLICT (rod_name, catch_date, beat)
    WHERE guest = false
    DO UPDATE SET
        "timestamp"          = EXCLUDED."timestamp",
        dnf                  = EXCLUDED.dnf,
        brown_trout_released = EXCLUDED.brown_trout_released,
        grayling             = EXCLUDED.grayling,
        rainbow_trout        = EXCLUDED.rainbow_trout,
        other_species        = EXCLUDED.other_species,
        brown_trout_retained = EXCLUDED.brown_trout_retained,
        comments             = EXCLUDED.comments;
END;
$function$;


CREATE OR REPLACE FUNCTION public.submit_catch_return_no_reservation(
    p_password text,
    p_surname text,
    p_catch_date date,
    p_beat text,
    p_dnf boolean DEFAULT false,
    p_bt_released integer DEFAULT 0,
    p_grayling integer DEFAULT 0,
    p_rainbow integer DEFAULT 0,
    p_other integer DEFAULT 0,
    p_bt_retained integer DEFAULT 0,
    p_comments text DEFAULT ''::text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    pw_valid       boolean;
    current_year   text;
    canonical_name text;
    v_season_start date;
    v_season_end   date;
    v_beat_id      integer;
    v_resource     text;
BEGIN
    SELECT (value_hash = crypt(p_password, value_hash))
    INTO pw_valid
    FROM private.club_settings
    WHERE key = 'shared_catch_password'
    LIMIT 1;

    IF NOT COALESCE(pw_valid, FALSE) THEN
        RAISE EXCEPTION 'Invalid club password';
    END IF;

    SELECT value_hash INTO current_year
    FROM private.club_settings
    WHERE key = 'current_member_year'
    LIMIT 1;

    SELECT cr_name INTO canonical_name
    FROM private.members
    WHERE upper(cr_name) = upper(p_surname)
      AND year_of_membership::text = current_year
    LIMIT 1;

    IF canonical_name IS NULL THEN
        RAISE EXCEPTION 'Member surname not recognised';
    END IF;

    SELECT target_start_date, target_end_date
    INTO v_season_start, v_season_end
    FROM private.year_param
    WHERE id = 1;

    IF p_catch_date > CURRENT_DATE THEN
        RAISE EXCEPTION 'Catch date % is in the future', p_catch_date;
    END IF;

    IF p_catch_date NOT BETWEEN v_season_start AND v_season_end THEN
        RAISE EXCEPTION 'Catch date % is outside the season (% to %)', p_catch_date, v_season_start, v_season_end;
    END IF;

    SELECT bt.id, rb.beat INTO v_beat_id, v_resource
    FROM private.reservation_beats rb
    INNER JOIN private.beats bt ON rb.beat_id = bt.id
    WHERE bt.beat = p_beat
    ORDER BY rb.beat
    LIMIT 1;

    IF v_resource IS NULL THEN
        RAISE EXCEPTION 'No resource found for beat: %', p_beat;
    END IF;

    -- Only create a Synthetic reservation when the member has no reservation
    -- for any resource of this beat on this date.
    IF NOT EXISTS (
        SELECT 1
        FROM private.reservations_confirmed_staging rcs
        INNER JOIN private.reservation_beats rb ON rb.beat = rcs.resource
        WHERE rcs.cr_name = canonical_name
          AND rcs.date = p_catch_date
          AND rb.beat_id = v_beat_id
    ) THEN
        INSERT INTO private.reservations_confirmed_staging (date, resource, name, cr_name)
        VALUES (p_catch_date, v_resource, 'Synthetic', canonical_name)
        ON CONFLICT (date, cr_name, resource) DO NOTHING;
    END IF;

    INSERT INTO private.catch_returns_staging_table (
        "timestamp", rod_name, catch_date, beat, dnf, guest,
        brown_trout_released, grayling, rainbow_trout, other_species,
        brown_trout_retained, comments
    ) VALUES (
        NOW()::text, canonical_name, p_catch_date, p_beat, p_dnf, false,
        p_bt_released, p_grayling, p_rainbow, p_other, p_bt_retained, p_comments
    )
    ON CONFLICT (rod_name, catch_date, beat)
    WHERE guest = false
    DO UPDATE SET
        "timestamp"          = EXCLUDED."timestamp",
        dnf                  = EXCLUDED.dnf,
        brown_trout_released = EXCLUDED.brown_trout_released,
        grayling             = EXCLUDED.grayling,
        rainbow_trout        = EXCLUDED.rainbow_trout,
        other_species        = EXCLUDED.other_species,
        brown_trout_retained = EXCLUDED.brown_trout_retained,
        comments             = EXCLUDED.comments;
END;
$function$;
