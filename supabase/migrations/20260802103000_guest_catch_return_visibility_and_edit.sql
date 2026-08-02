-- Guest catch returns (a member's reservation can have their own catch return
-- plus one or more guest catch returns) were entirely invisible after
-- submission: get_member_reservations only ever counted the member's own
-- (guest=false) record, and check_existing_catch_return explicitly refuses to
-- look up guest rows at all. Guests are intentionally anonymous - a guest
-- catch return is stored under the hosting member's own rod_name with
-- guest=true, with no field identifying which guest - so there's nothing to
-- key an edit lookup on except the row's own id.

-- 1. Add a guest catch count to the reservation list, so the member gets
-- feedback that a guest submission landed (previously silently invisible).
DROP FUNCTION IF EXISTS public.get_member_reservations(text, text);

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
    ORDER BY rcs.date DESC;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_member_reservations(text, text) TO anon;


-- 2. List the guest catch returns already logged against a reservation, so
-- the client can offer them for editing. Guests have no identifying field
-- beyond their row id and submission time - labelling is necessarily
-- "submitted at <time>", not a guest name.
CREATE OR REPLACE FUNCTION public.get_guest_catch_returns_for_reservation(
    p_password   text,
    p_surname    text,
    p_catch_date date,
    p_beat       text
)
RETURNS TABLE (
    id                    integer,
    submitted_at          text,
    dnf                   boolean,
    brown_trout_released  integer,
    grayling              integer,
    rainbow_trout         integer,
    other_species         integer,
    brown_trout_retained  integer,
    comments              text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    pw_valid       boolean;
    current_year   text;
    canonical_name text;
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

    RETURN QUERY
    SELECT crst.id, crst."timestamp", crst.dnf, crst.brown_trout_released,
           crst.grayling, crst.rainbow_trout, crst.other_species,
           crst.brown_trout_retained, crst.comments
    FROM private.catch_returns_staging_table crst
    WHERE crst.rod_name   = canonical_name
      AND crst.catch_date = p_catch_date
      AND crst.beat       = p_beat
      AND crst.guest      = true
    ORDER BY crst."timestamp" ASC;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_guest_catch_returns_for_reservation(text, text, date, text) TO anon;


-- 3. Allow editing a specific guest catch return by id. p_id is only
-- reachable via a value returned from get_guest_catch_returns_for_reservation
-- for this same canonical_name - the WHERE clause re-checks rod_name/guest
-- ownership regardless, since p_id is a client-supplied value passed to a
-- publicly-callable RPC (the anon key is not a secret) and ids are plain
-- sequential integers, not random tokens. Without this check a call scoped
-- to member A could silently overwrite a row belonging to member B (guest or
-- even their own non-guest catch return).
DROP FUNCTION IF EXISTS public.submit_catch_return_for_reservation(text, text, date, text, boolean, boolean, integer, integer, integer, integer, integer, text);

CREATE OR REPLACE FUNCTION public.submit_catch_return_for_reservation(
    p_password     text,
    p_surname      text,
    p_catch_date   date,
    p_beat         text,
    p_guest        boolean DEFAULT false,
    p_dnf          boolean DEFAULT false,
    p_bt_released  integer DEFAULT 0,
    p_grayling     integer DEFAULT 0,
    p_rainbow      integer DEFAULT 0,
    p_other        integer DEFAULT 0,
    p_bt_retained  integer DEFAULT 0,
    p_comments     text DEFAULT ''::text,
    p_id           integer DEFAULT NULL
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
    v_updated_id         integer;
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

    IF p_id IS NOT NULL THEN
        IF NOT p_guest THEN
            RAISE EXCEPTION 'p_id is only valid for guest catch returns';
        END IF;

        UPDATE private.catch_returns_staging_table
        SET "timestamp"          = NOW()::text,
            dnf                  = p_dnf,
            brown_trout_released = p_bt_released,
            grayling             = p_grayling,
            rainbow_trout        = p_rainbow,
            other_species        = p_other,
            brown_trout_retained = p_bt_retained,
            comments             = p_comments
        WHERE id = p_id
          AND rod_name = canonical_name
          AND catch_date = p_catch_date
          AND beat = p_beat
          AND guest = true
        RETURNING id INTO v_updated_id;

        IF v_updated_id IS NULL THEN
            RAISE EXCEPTION 'Guest catch return not found';
        END IF;

        RETURN;
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

GRANT EXECUTE ON FUNCTION public.submit_catch_return_for_reservation(text, text, date, text, boolean, boolean, integer, integer, integer, integer, integer, text, integer) TO anon;
