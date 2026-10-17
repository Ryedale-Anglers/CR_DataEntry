-- Two findings from the pre-cutover review of index_supabase.html.
--
-- 1. public.get_member_season_history(p_surname) was granted to anon and has
--    no password check, so anyone with the public (publishable) key could
--    call it with '%' and read every member's reservations, catches and
--    comments. Its only caller is the send_Res_CR_history_email edge
--    function, which validates the club password first and then calls it
--    with the service role - so anon/authenticated access is revoked.
--
-- 2. Every member lookup matched with "cr_name ILIKE p_surname", so '%' or
--    '_' in the surname typed at login acted as a wildcard ('%' logged in as
--    an arbitrary member). Replaced with a case-insensitive exact match,
--    upper(cr_name) = upper(p_surname), in every function that had it.
--    The four functions also redefined by other pending migrations
--    (submit_catch_return_for_reservation in 20260929120000;
--    get_member_reservations, submit_catch_return_different_beat and
--    submit_catch_return_no_reservation in 20261015100000) carry the same
--    change in those files instead. Otherwise these definitions are
--    unchanged; CREATE OR REPLACE keeps the existing grants.

REVOKE EXECUTE ON FUNCTION public.get_member_season_history(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_member_season_history(text) TO service_role;

CREATE OR REPLACE FUNCTION public.validate_member_surname(p_surname text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    current_year text;
    is_valid     boolean;
BEGIN
    SELECT value_hash INTO current_year
    FROM private.club_settings
    WHERE key = 'current_member_year'
    LIMIT 1;

    SELECT EXISTS (
        SELECT 1
        FROM private.members
        WHERE upper(cr_name) = upper(p_surname)
          AND year_of_membership::text = current_year
    ) INTO is_valid;

    RETURN COALESCE(is_valid, FALSE);
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_existing_catch_return(p_password text, p_surname text, p_catch_date date, p_beat text, p_guest boolean DEFAULT false)
 RETURNS TABLE(brown_trout_released integer, grayling integer, rainbow_trout integer, other_species integer, brown_trout_retained integer, dnf boolean, comments text, submitted_at text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    pw_valid       boolean;
    current_year   text;
    canonical_name text;
BEGIN
    IF p_guest THEN
        RETURN;
    END IF;

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

    RETURN QUERY
    SELECT crst.brown_trout_released, crst.grayling, crst.rainbow_trout,
           crst.other_species, crst.brown_trout_retained, crst.dnf, crst.comments,
           crst."timestamp" AS submitted_at
    FROM private.catch_returns_staging_table crst
    WHERE crst.rod_name   = canonical_name
      AND crst.catch_date = p_catch_date
      AND crst.beat       = p_beat
      AND crst.guest      = false;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_guest_catch_returns_for_reservation(p_password text, p_surname text, p_catch_date date, p_beat text)
 RETURNS TABLE(id integer, submitted_at text, dnf boolean, brown_trout_released integer, grayling integer, rainbow_trout integer, other_species integer, brown_trout_retained integer, comments text)
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
    WHERE upper(cr_name) = upper(p_surname)
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

CREATE OR REPLACE FUNCTION public.get_member_info_for_email(p_surname text, p_password text)
 RETURNS TABLE(email_address text, cr_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    pw_valid    boolean;
    season_year text;
BEGIN
    SELECT (value_hash = crypt(p_password, value_hash))
    INTO pw_valid
    FROM private.club_settings
    WHERE key = 'shared_catch_password'
    LIMIT 1;

    IF NOT COALESCE(pw_valid, FALSE) THEN
        RAISE EXCEPTION 'Invalid club password';
    END IF;

    SELECT value_hash INTO season_year
    FROM private.club_settings
    WHERE key = 'current_member_year'
    LIMIT 1;

    RETURN QUERY
    SELECT m.email_address::text, m.cr_name::text
    FROM private.members m
    WHERE upper(m.cr_name) = upper(p_surname)
      AND m.year_of_membership::text = season_year
    LIMIT 1;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_member_season_history(p_surname text)
 RETURNS TABLE(res_date date, beat text, bt_released integer, grayling integer, comments text, dnf boolean, guest boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    season_year  text;
    season_start date;
BEGIN
    SELECT value_hash INTO season_year
    FROM private.club_settings
    WHERE key = 'current_member_year'
    LIMIT 1;

    season_start := make_date(season_year::integer, 4, 1);

    RETURN QUERY
    SELECT
        vrcs.date,
        vrcs.beat::text,
        crst.brown_trout_released,
        crst.grayling,
        crst.comments::text,
        crst.dnf,
        crst.guest
    FROM private.view_reservations_confirmed_staging vrcs
    LEFT JOIN private.catch_returns_staging_table crst
        ON  vrcs.cr_name  = crst.rod_name
        AND vrcs.date     = crst.catch_date
        AND vrcs.beat     = crst.beat
    WHERE vrcs.date    >= season_start
      AND upper(vrcs.cr_name) = upper(p_surname)
    ORDER BY vrcs.date;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_outstanding_reservations(p_password text, p_surname text)
 RETURNS TABLE(reservation_date date, beat text)
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

    RETURN QUERY
    SELECT rcs.date, b.beat
    FROM private.reservations_confirmed_staging rcs
    INNER JOIN private.reservation_beats rb ON rb.beat = rcs.resource
    INNER JOIN private.beats b ON b.id = rb.beat_id
    WHERE rcs.cr_name = canonical_name
      AND rcs.date BETWEEN v_season_start AND v_season_end
      AND NOT EXISTS (
          SELECT 1
          FROM private.catch_returns_staging_table crst
          WHERE crst.rod_name   = canonical_name
            AND crst.catch_date = rcs.date
            AND crst.beat       = b.beat
            AND crst.guest      = false
      )
    ORDER BY rcs.date;
END;
$function$;

CREATE OR REPLACE FUNCTION public.reservation_exists_for_beat_date(p_password text, p_surname text, p_catch_date date, p_beat text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    pw_valid       boolean;
    current_year   text;
    canonical_name text;
    v_exists       boolean;
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

    SELECT EXISTS (
        SELECT 1
        FROM private.reservations_confirmed_staging rcs
        INNER JOIN private.reservation_beats rb ON rb.beat = rcs.resource
        INNER JOIN private.beats b ON b.id = rb.beat_id
        WHERE rcs.cr_name = canonical_name
          AND rcs.date    = p_catch_date
          AND b.beat      = p_beat
    ) INTO v_exists;

    RETURN v_exists;
END;
$function$;

CREATE OR REPLACE FUNCTION public.insert_catch_return(p_password text, p_surname text, p_catch_date date, p_beat text, p_dnf boolean, p_guest boolean DEFAULT false, p_bt_released integer DEFAULT 0, p_grayling integer DEFAULT 0, p_rainbow integer DEFAULT 0, p_other integer DEFAULT 0, p_bt_retained integer DEFAULT 0, p_comments text DEFAULT ''::text, p_create_synthetic boolean DEFAULT false, p_dnf_other_beat text DEFAULT NULL::text, p_dnf_other_date date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    current_year   text;
    pw_valid       boolean;
    canonical_name text;
    v_resource     text;
BEGIN
    -- Re-validate club password
    SELECT (value_hash = crypt(p_password, value_hash))
    INTO pw_valid
    FROM private.club_settings
    WHERE key = 'shared_catch_password'
    LIMIT 1;

    IF NOT COALESCE(pw_valid, FALSE) THEN
        RAISE EXCEPTION 'Invalid club password';
    END IF;

    -- Get current membership year
    SELECT value_hash INTO current_year
    FROM private.club_settings
    WHERE key = 'current_member_year'
    LIMIT 1;

    -- Re-validate member surname and retrieve canonical name in one query
    SELECT cr_name INTO canonical_name
    FROM private.members
    WHERE upper(cr_name) = upper(p_surname)
      AND year_of_membership::text = current_year
    LIMIT 1;

    IF canonical_name IS NULL THEN
        RAISE EXCEPTION 'Member surname not recognised';
    END IF;

    INSERT INTO private.catch_returns_staging_table (
        "timestamp",
        rod_name,
        catch_date,
        beat,
        dnf,
        guest,
        brown_trout_released,
        grayling,
        rainbow_trout,
        other_species,
        brown_trout_retained,
        comments
    ) VALUES (
        NOW()::text,
        canonical_name,
        p_catch_date,
        p_beat,
        p_dnf,
        p_guest,
        p_bt_released,
        p_grayling,
        p_rainbow,
        p_other,
        p_bt_retained,
        p_comments
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

    -- Non-guest only: create a synthetic reservation for the beat/date actually
    -- fished, if the member confirmed they had no reservation for it.
    IF p_create_synthetic AND NOT p_guest THEN
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
    END IF;

    -- Non-guest only: mark a different, now-abandoned reservation as DNF, if the
    -- member confirmed they fished elsewhere/another date instead of using it.
    IF NOT p_guest AND p_dnf_other_beat IS NOT NULL AND p_dnf_other_date IS NOT NULL THEN
        INSERT INTO private.catch_returns_staging_table (
            "timestamp", rod_name, catch_date, beat, dnf, guest,
            brown_trout_released, grayling, rainbow_trout, other_species,
            brown_trout_retained, comments
        ) VALUES (
            NOW()::text, canonical_name, p_dnf_other_date, p_dnf_other_beat, true, false,
            0, 0, 0, 0, 0,
            'Auto-marked DNF: member fished a different beat/date'
        )
        ON CONFLICT (rod_name, catch_date, beat) WHERE guest = false DO NOTHING;
    END IF;
END;
$function$;
