-- Precheck: does a non-guest catch return already exist for this member/date/beat?
-- Used by the UI to show current values and ask for explicit overwrite confirmation
-- before insert_catch_return silently upserts it.
CREATE OR REPLACE FUNCTION public.check_existing_catch_return(
    p_password   text,
    p_surname    text,
    p_catch_date date,
    p_beat       text,
    p_guest      boolean DEFAULT false
)
RETURNS TABLE (
    brown_trout_released integer,
    grayling             integer,
    rainbow_trout        integer,
    other_species        integer,
    brown_trout_retained integer,
    dnf                  boolean,
    comments             text
)
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
    WHERE cr_name ILIKE p_surname
      AND year_of_membership::text = current_year
    LIMIT 1;

    IF canonical_name IS NULL THEN
        RAISE EXCEPTION 'Member surname not recognised';
    END IF;

    RETURN QUERY
    SELECT crst.brown_trout_released, crst.grayling, crst.rainbow_trout,
           crst.other_species, crst.brown_trout_retained, crst.dnf, crst.comments
    FROM private.catch_returns_staging_table crst
    WHERE crst.rod_name   = canonical_name
      AND crst.catch_date = p_catch_date
      AND crst.beat       = p_beat
      AND crst.guest      = false;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.check_existing_catch_return(text, text, date, text, boolean) TO anon;


-- Outstanding reservations for this member across the whole current season:
-- reservations with no catch-return row at all yet (real or DNF). Used to let
-- the member resolve a beat/date mismatch themselves instead of relying on
-- after-the-fact heuristics.
CREATE OR REPLACE FUNCTION public.get_outstanding_reservations(
    p_password text,
    p_surname  text
)
RETURNS TABLE (
    reservation_date date,
    beat             text
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

GRANT EXECUTE ON FUNCTION public.get_outstanding_reservations(text, text) TO anon;


-- Extend insert_catch_return with the interactively-resolved outcome from the
-- outstanding-reservations flow: optionally create a synthetic reservation for
-- the beat/date actually being submitted, and/or mark a different, now-abandoned
-- reservation as DNF. Both are decided client-side by the member, not inferred
-- here - this function just executes what was already decided, atomically.
--
-- CREATE OR REPLACE cannot change a function's parameter list in place - it
-- would leave the old 12-arg signature as a separate overload alongside the
-- new 15-arg one. Drop the old signature explicitly first.
DROP FUNCTION IF EXISTS public.insert_catch_return(
    text, text, date, text, boolean, boolean, integer, integer, integer, integer, integer, text
);

CREATE OR REPLACE FUNCTION public.insert_catch_return(
    p_password          text,
    p_surname           text,
    p_catch_date        date,
    p_beat              text,
    p_dnf               boolean,
    p_guest             boolean DEFAULT false,
    p_bt_released       integer DEFAULT 0,
    p_grayling          integer DEFAULT 0,
    p_rainbow           integer DEFAULT 0,
    p_other             integer DEFAULT 0,
    p_bt_retained       integer DEFAULT 0,
    p_comments          text    DEFAULT '',
    p_create_synthetic  boolean DEFAULT false,
    p_dnf_other_beat    text    DEFAULT NULL,
    p_dnf_other_date    date    DEFAULT NULL
)
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
    WHERE cr_name ILIKE p_surname
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

GRANT EXECUTE ON FUNCTION public.insert_catch_return(
    text, text, date, text, boolean, boolean, integer, integer, integer, integer, integer, text,
    boolean, text, date
) TO anon;
