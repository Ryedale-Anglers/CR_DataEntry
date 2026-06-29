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
        WHERE cr_name ILIKE p_surname
          AND year_of_membership::text = current_year
    ) INTO is_valid;

    RETURN COALESCE(is_valid, FALSE);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.validate_member_surname(text) TO anon;

CREATE OR REPLACE FUNCTION public.insert_catch_return(
    p_password      text,
    p_surname       text,
    p_catch_date    date,
    p_beat          text,
    p_dnf           boolean,
    p_guest         boolean DEFAULT false,
    p_bt_released   integer DEFAULT 0,
    p_grayling      integer DEFAULT 0,
    p_rainbow       integer DEFAULT 0,
    p_other         integer DEFAULT 0,
    p_bt_retained   integer DEFAULT 0,
    p_comments      text    DEFAULT ''
)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    current_year   text;
    pw_valid       boolean;
    canonical_name text;
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
END;
$function$;

GRANT EXECUTE ON FUNCTION public.insert_catch_return(text, text, date, text, boolean, boolean, integer, integer, integer, integer, integer, text) TO anon;

-- Partial unique index required by the ON CONFLICT clause above.
-- Enforces that a non-guest member can have at most one catch return record
-- per rod_name + catch_date + beat, whether it is a DNF or a real return.
-- A later submission for the same combination replaces the earlier one.
CREATE UNIQUE INDEX IF NOT EXISTS uq_cr_staging_member_date_beat
    ON private.catch_returns_staging_table (rod_name, catch_date, beat)
    WHERE guest = false;
