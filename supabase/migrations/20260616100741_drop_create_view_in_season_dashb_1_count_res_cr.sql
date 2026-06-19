drop view view_in_season_dashb_1_count_res_cr;
create view view_in_season_dashb_1_count_res_cr as
WITH timeline AS (
         SELECT generate_series('2026-04-01'::date::timestamp with time zone, CURRENT_DATE::timestamp with time zone, '7 days'::interval)::date AS week_starting
        ), filtered_reservations AS (
         SELECT vrcs.date,
            	vrcs.cr_name,
            	vrcs.beat,
            	crst.timestamp
           FROM view_reservations_confirmed_staging vrcs
             LEFT JOIN catch_returns_staging_table crst ON vrcs.date = crst.catch_date 
             			AND vrcs.cr_name = crst.rod_name
             			and vrcs.beat = crst.beat
          WHERE crst.dnf IS DISTINCT FROM true AND vrcs.date < '2026-06-15' AND crst.guest is distinct from true
        )
 SELECT week_starting,
    ( SELECT count(*) AS count
           FROM filtered_reservations fr
          WHERE fr.date >= t.week_starting AND fr.date < (t.week_starting + 7)) AS reservations,
    (SELECT count(*) AS count
           FROM filtered_reservations fr
          WHERE fr.date >= t.week_starting AND fr.date < (t.week_starting + 7) 
          and fr.timestamp is not NULL) AS catches_returns
   FROM timeline t
  ORDER BY week_starting;