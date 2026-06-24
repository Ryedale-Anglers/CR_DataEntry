CREATE OR REPLACE VIEW public.view_in_season_dashb_1_count_res_cr AS 
WITH 
timeline AS (
	SELECT generate_series(
    (DATE_TRUNC('year', CURRENT_DATE) + INTERVAL '3 months')::timestamp with time zone,
    (CURRENT_DATE - 1)::timestamp with time zone,
    '7 days'::interval)::date AS week_starting
	), 
filtered_reservations AS (
         SELECT vrcs.date,
            vrcs.cr_name,
            vrcs.beat,
            crst."timestamp"
           FROM view_reservations_confirmed_staging vrcs
             LEFT JOIN catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name AND vrcs.beat = crst.beat
          WHERE crst.dnf IS DISTINCT FROM true AND vrcs.date < CURRENT_DATE AND crst.guest IS DISTINCT FROM true
        )
 SELECT week_starting,
    ( SELECT count(*) AS count
           FROM filtered_reservations fr
          WHERE fr.date >= t.week_starting AND fr.date < (t.week_starting + 7)) AS reservations,
    ( SELECT count(*) AS count
           FROM filtered_reservations fr
          WHERE fr.date >= t.week_starting AND fr.date < (t.week_starting + 7) AND fr."timestamp" IS NOT NULL) AS catches_returns
   FROM timeline t
  ORDER BY week_starting;

  