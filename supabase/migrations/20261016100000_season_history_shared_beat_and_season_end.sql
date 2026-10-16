-- The "Email My Returns YTD" history (get_member_season_history, called by the
-- send_Res_CR_history_email edge function) listed a booking twice when the
-- member had booked both resources of the shared beat 'Fishing Hut & Railway
-- Bridge' (17. Fishing Hut / 18. Railway Bridge) on the same date - each
-- catch return appeared once per resource. Collapse to one row per date, beat
-- and catch return, matching get_member_reservations (20261015100000).
--
-- Also bound the history to the season (1 April to 30 September of
-- current_member_year): it had a start but no end, so October bookings
-- appeared in the email.
--
-- Signature unchanged; CREATE OR REPLACE keeps the existing grants
-- (service_role only, see 20261015110000).

CREATE OR REPLACE FUNCTION public.get_member_season_history(p_surname text)
 RETURNS TABLE(res_date date, beat text, bt_released integer, grayling integer, comments text, dnf boolean, guest boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    season_year  text;
    season_start date;
    season_end   date;
BEGIN
    SELECT value_hash INTO season_year
    FROM private.club_settings
    WHERE key = 'current_member_year'
    LIMIT 1;

    season_start := make_date(season_year::integer, 4, 1);
    season_end   := make_date(season_year::integer, 9, 30);

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
    WHERE vrcs.date BETWEEN season_start AND season_end
      AND upper(vrcs.cr_name) = upper(p_surname)
    ORDER BY vrcs.date, vrcs.beat, crst.id;
END;
$function$;
