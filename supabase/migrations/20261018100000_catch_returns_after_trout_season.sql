-- Catch returns continue after the trout season: the grayling season runs on
-- past 30 September. Three member-facing functions stopped at 30 September
-- (private.year_param.target_end_date / 30 Sep of current_member_year), so:
--   - "Reservation Not Listed" (submit_catch_return_no_reservation) rejected
--     October dates with "outside the season";
--   - get_member_reservations never listed bookings after 30 September, so
--     members couldn't enter returns against them either;
--   - get_member_season_history (Email My Returns YTD) left them out.
--
-- Each now runs from the season start (1 April) with no end date; the
-- existing "not in the future" check still applies to catch returns. Until
-- the next season is started (private.start_new_season in April), this also
-- covers grayling fishing in January to March.
--
-- Unchanged on purpose: the report and dashboard views, which measure the
-- trout season (1 April to 30 September) only, and year_param's season dates.
-- Signatures unchanged; CREATE OR REPLACE keeps the existing grants.

CREATE OR REPLACE FUNCTION public.get_member_reservations(p_password text, p_surname text)
 RETURNS TABLE(reservation_date date, beat text, cr_exists boolean, cr_dnf boolean, cr_submitted_at text, guest_cr_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    pw_valid       boolean;
    current_year   text;
    canonical_name text;
    v_season_start date;
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

    SELECT target_start_date
    INTO v_season_start
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
      AND rcs.date >= v_season_start
    ORDER BY rcs.date DESC, b.beat;
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_catch_return_no_reservation(p_password text, p_surname text, p_catch_date date, p_beat text, p_dnf boolean DEFAULT false, p_bt_released integer DEFAULT 0, p_grayling integer DEFAULT 0, p_rainbow integer DEFAULT 0, p_other integer DEFAULT 0, p_bt_retained integer DEFAULT 0, p_comments text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    pw_valid       boolean;
    current_year   text;
    canonical_name text;
    v_season_start date;
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

    SELECT target_start_date
    INTO v_season_start
    FROM private.year_param
    WHERE id = 1;

    IF p_catch_date > CURRENT_DATE THEN
        RAISE EXCEPTION 'Catch date % is in the future', p_catch_date;
    END IF;

    IF p_catch_date < v_season_start THEN
        RAISE EXCEPTION 'Catch date % is before the start of the season (%)', p_catch_date, v_season_start;
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

    -- DISTINCT ON collapses bookings on both resources of a shared beat
    -- (17. Fishing Hut / 18. Railway Bridge) on the same date - catch returns
    -- are keyed by beat, so each catch return would otherwise be listed twice.
    -- crst.id keeps one row per catch return (own and each guest).
    RETURN QUERY
    SELECT DISTINCT ON (vrcs.date, vrcs.beat, crst.id)
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
    WHERE vrcs.date >= season_start
      AND upper(vrcs.cr_name) = upper(p_surname)
    ORDER BY vrcs.date, vrcs.beat, crst.id;
END;
$function$;
