-- Function 1: validate password + surname and return member email + canonical name.
-- Called first by the edge function; replaces the old separate verify_club_password
-- + public members table lookup that broke when members moved to private schema.
CREATE OR REPLACE FUNCTION public.get_member_info_for_email(
    p_surname  text,
    p_password text
)
RETURNS TABLE (
    email_address text,
    cr_name       text
)
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
    WHERE m.cr_name ILIKE p_surname
      AND m.year_of_membership::text = season_year
    LIMIT 1;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_member_info_for_email(text, text) TO anon;

-- Function 2: return the member's reservations and catch returns for the current season.
-- Season start is derived from current_member_year in club_settings so an admin
-- year-roll keeps this correct without any code change.
-- No password re-validation here: the edge function calls get_member_info_for_email first.
CREATE OR REPLACE FUNCTION public.get_member_season_history(
    p_surname text
)
RETURNS TABLE (
    res_date    date,
    beat        text,
    bt_released integer,
    grayling    integer,
    comments    text,
    dnf         boolean,
    guest       boolean
)
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
      AND vrcs.cr_name  ILIKE p_surname
    ORDER BY vrcs.date;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_member_season_history(text) TO anon;
