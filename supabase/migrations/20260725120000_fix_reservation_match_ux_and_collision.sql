-- Fix 1: "edit/overwrite spuriously re-triggers No Reservation Found" bug.
-- get_outstanding_reservations only returns UNFULFILLED reservations (it excludes
-- any date/beat that already has a catch return), which is correct for building
-- the "pick one of your other reservations" list, but the client was also reusing
-- that same list to answer a different question: "does a reservation exist at all
-- for the exact date/beat just entered?" Once a catch return exists (i.e. you're
-- editing/overwriting your own record), the reservation disappears from that list
-- even though it's still a real match, so the exact-match check always failed on
-- edits. This function answers the existence question directly, independent of
-- whether a catch return has already been logged against it - covers both real
-- and Synthetic reservations, since a Synthetic one is just as valid a match.
CREATE OR REPLACE FUNCTION public.reservation_exists_for_beat_date(
    p_password text,
    p_surname text,
    p_catch_date date,
    p_beat text
)
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
          AND rcs.date    = p_catch_date
          AND b.beat      = p_beat
    ) INTO v_exists;

    RETURN v_exists;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.reservation_exists_for_beat_date(text, text, date, text) TO anon;

-- Fix 2 (UX part): the "Existing Record Found" overwrite dialog should tell the
-- member when they originally submitted the record they're about to replace, not
-- just what's in it. Requires adding the submission timestamp to the return set.
-- Return type is changing (new column), so the function must be dropped first -
-- CREATE OR REPLACE cannot alter an existing RETURNS TABLE shape.
DROP FUNCTION IF EXISTS public.check_existing_catch_return(text, text, date, text, boolean);

CREATE FUNCTION public.check_existing_catch_return(p_password text, p_surname text, p_catch_date date, p_beat text, p_guest boolean DEFAULT false)
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
    WHERE cr_name ILIKE p_surname
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

GRANT EXECUTE ON FUNCTION public.check_existing_catch_return(text, text, date, text, boolean) TO anon;
