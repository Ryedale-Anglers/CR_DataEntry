CREATE OR REPLACE VIEW public.view_in_season_dashb_1_count_res_cr AS 
WITH timeline AS (
         SELECT generate_series('2026-04-01'::date::timestamp with time zone, CURRENT_DATE::timestamp with time zone, '7 days'::interval)::date AS week_starting
        ), filtered_reservations AS (
         SELECT vrcs.date,
            vrcs.cr_name,
            crst.guest
           FROM reservations_confirmed_staging vrcs
             LEFT JOIN catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name
          WHERE crst.dnf IS DISTINCT FROM true and vrcs.date < CURRENT_DATE and (crst.guest = false or crst.guest is null)
        )
 SELECT week_starting,
    ( SELECT count(*) AS count
           FROM filtered_reservations fr
          WHERE fr.date >= t.week_starting AND fr.date < (t.week_starting + 7)) AS reservations,
    ( SELECT count(*) AS count
           FROM catch_returns_staging_table c
          WHERE c.catch_date >= t.week_starting AND c.catch_date < (t.week_starting + 7) AND c.dnf IS DISTINCT FROM true and c.guest = false) AS catches_returns
   FROM timeline t
  ORDER BY week_starting;