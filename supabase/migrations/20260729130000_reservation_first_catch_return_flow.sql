-- New reservation-first catch return entry flow, replacing the old
-- type-first/reconcile-after model. The member picks a reservation from
-- their own list first; beat/date come from the reservation, not free text.
-- This eliminates the whole class of bugs found in the old flow (spurious
-- re-prompts on edit, DNF with no reservation validation, self-attest
-- silently orphaning a same-day reservation) by removing the inference step
-- that caused them - there's no "type freely, then guess what they meant."
--
-- Supersedes get_outstanding_reservations, reservation_exists_for_beat_date,
-- and insert_catch_return for the client's purposes (kept in the DB for now,
-- not dropped, in case anything else references them).

-- 1. Returns ALL of a member's reservations for the current season (real and
-- Synthetic treated identically - no distinction exposed to the client),
-- each annotated with whether the member's own (non-guest) catch return
-- already exists against it. Ordered most-recent-first; the client fetches
-- everything in one call and slices client-side for "show 5 / show more"
-- (confirmed fine - max ~30 reservations/member/season).
CREATE OR REPLACE FUNCTION public.get_member_reservations(p_password text, p_surname text)
RETURNS TABLE(
    reservation_date date,
    beat text,
    cr_exists boolean,
    cr_dnf boolean,
    cr_submitted_at text
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
    WHERE cr_name ILIKE p_surname
      AND year_of_membership::text = current_year
    LIMIT 1;

    IF canonical_name IS NULL THEN
        RAISE EXCEPTION 'Member surname not recognised';
    END IF;

    SELECT target_start_date, target_end_date
    INTO v_season_start, v_season_end
    FROM private.year_param
    WHERE id = 1;

    RETURN QUERY
    SELECT
        rcs.date,
        b.beat,
        (crst.id IS NOT NULL) AS cr_exists,
        crst.dnf AS cr_dnf,
        crst."timestamp" AS cr_submitted_at
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
    ORDER BY rcs.date DESC;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_member_reservations(text, text) TO anon;


-- 2. Submit/update a catch return against an ALREADY-SELECTED reservation.
-- Date/beat come from the reservation (client locks these fields, doesn't
-- let them be typed) - this is the only path guests use (guest=true just
-- skips the overwrite semantics via the UPSERT, doesn't need its own
-- reservation). No synthetic-reservation logic needed at all: the
-- reservation is guaranteed to already exist by construction.
CREATE OR REPLACE FUNCTION public.submit_catch_return_for_reservation(
    p_password text,
    p_surname text,
    p_catch_date date,
    p_beat text,
    p_guest boolean DEFAULT false,
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
    pw_valid             boolean;
    current_year         text;
    canonical_name       text;
    v_reservation_exists boolean;
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
    WHERE cr_name ILIKE p_surname
      AND year_of_membership::text = current_year
    LIMIT 1;

    IF canonical_name IS NULL THEN
        RAISE EXCEPTION 'Member surname not recognised';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM private.reservations_confirmed_staging rcs
        INNER JOIN private.reservation_beats rb ON rb.beat = rcs.resource
        INNER JOIN private.beats b ON b.id = rb.beat_id
        WHERE rcs.cr_name = canonical_name
          AND rcs.date = p_catch_date
          AND b.beat = p_beat
    ) INTO v_reservation_exists;

    IF NOT v_reservation_exists THEN
        RAISE EXCEPTION 'No reservation found for % on %', p_beat, p_catch_date;
    END IF;

    INSERT INTO private.catch_returns_staging_table (
        "timestamp", rod_name, catch_date, beat, dnf, guest,
        brown_trout_released, grayling, rainbow_trout, other_species,
        brown_trout_retained, comments
    ) VALUES (
        NOW()::text, canonical_name, p_catch_date, p_beat, p_dnf, p_guest,
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

GRANT EXECUTE ON FUNCTION public.submit_catch_return_for_reservation(text, text, date, text, boolean, boolean, integer, integer, integer, integer, integer, text) TO anon;


-- 3. Member fished a different beat to a selected reservation. Member-only
-- (no p_guest - a guest doesn't have their own reservation to divert from).
-- Unconditionally marks the original reservation's beat as DNF - this is
-- what closes the "self-attest silently orphans a same-day reservation" gap
-- found in the old flow, since there's no separate escape hatch that can
-- skip this: diverging from a specific reservation IS this call.
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
    WHERE cr_name ILIKE p_surname
      AND year_of_membership::text = current_year
    LIMIT 1;

    IF canonical_name IS NULL THEN
        RAISE EXCEPTION 'Member surname not recognised';
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

    -- 2. Create a Synthetic reservation for the beat actually fished.
    SELECT rb.beat INTO v_new_resource
    FROM private.reservation_beats rb
    INNER JOIN private.beats bt ON rb.beat_id = bt.id
    WHERE bt.beat = p_new_beat
    LIMIT 1;

    IF v_new_resource IS NULL THEN
        RAISE EXCEPTION 'No resource found for beat: %', p_new_beat;
    END IF;

    INSERT INTO private.reservations_confirmed_staging (date, resource, name, cr_name)
    VALUES (p_catch_date, v_new_resource, 'Synthetic', canonical_name)
    ON CONFLICT (date, cr_name, resource) DO NOTHING;

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

GRANT EXECUTE ON FUNCTION public.submit_catch_return_different_beat(text, text, text, date, text, boolean, integer, integer, integer, integer, integer, text) TO anon;


-- 4. No valid reservation showing at all. Member-only (no p_guest - guests
-- always attach to the member's own reservation via
-- submit_catch_return_for_reservation instead). Creates a Synthetic
-- reservation to back the entry - DNF is valid here too (the real
-- reservation may simply not have synced yet).
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
    WHERE cr_name ILIKE p_surname
      AND year_of_membership::text = current_year
    LIMIT 1;

    IF canonical_name IS NULL THEN
        RAISE EXCEPTION 'Member surname not recognised';
    END IF;

    SELECT rb.beat INTO v_resource
    FROM private.reservation_beats rb
    INNER JOIN private.beats bt ON rb.beat_id = bt.id
    WHERE bt.beat = p_beat
    LIMIT 1;

    IF v_resource IS NULL THEN
        RAISE EXCEPTION 'No resource found for beat: %', p_beat;
    END IF;

    INSERT INTO private.reservations_confirmed_staging (date, resource, name, cr_name)
    VALUES (p_catch_date, v_resource, 'Synthetic', canonical_name)
    ON CONFLICT (date, cr_name, resource) DO NOTHING;

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

GRANT EXECUTE ON FUNCTION public.submit_catch_return_no_reservation(text, text, date, text, boolean, integer, integer, integer, integer, integer, text) TO anon;
