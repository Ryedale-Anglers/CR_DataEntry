CREATE OR REPLACE VIEW private.view_member_reservations_activity
AS WITH reservation_stats AS (
         SELECT vrcs.cr_name,
            count(*) AS total_reservations
           FROM private.view_reservations_confirmed_staging vrcs
             LEFT JOIN private.catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name AND vrcs.beat = crst.beat
          WHERE crst.guest IS DISTINCT FROM true AND crst.dnf IS DISTINCT FROM true AND vrcs.date < CURRENT_DATE
          GROUP BY vrcs.cr_name
        ), catch_returns_stats AS (
         SELECT vrcs.cr_name,
            sum(
                CASE
                    WHEN crst.rod_name IS NOT NULL THEN 1
                    ELSE 0
                END) AS total_submitted
           FROM private.view_reservations_confirmed_staging vrcs
             LEFT JOIN private.catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name AND vrcs.beat = crst.beat
          WHERE crst.guest IS DISTINCT FROM true AND crst.dnf IS DISTINCT FROM true AND vrcs.date < CURRENT_DATE
          GROUP BY vrcs.cr_name
        )
 SELECT m.member_name,
    m.cr_name,
    COALESCE(res.total_reservations, 0::bigint) AS "Reservations",
    COALESCE(crs.total_submitted, 0::bigint) AS "Catch Returns",
    COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint) AS "CRs Due"
   FROM private.view_member_names m
     LEFT JOIN reservation_stats res ON m.cr_name = res.cr_name
     LEFT JOIN catch_returns_stats crs ON m.cr_name = crs.cr_name
  WHERE m.year_of_membership::numeric = EXTRACT(year FROM CURRENT_DATE)
  ORDER BY (COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint)) DESC, m.cr_name;

CREATE OR REPLACE VIEW private.view_reservations_and_crs
AS SELECT vrcs.name,
    vrcs.date,
    vrcs.beat,
    crst.brown_trout_released,
    crst.grayling,
    crst.comments
   FROM private.view_reservations_confirmed_staging vrcs
     LEFT JOIN private.catch_returns_staging_table crst 
     	ON vrcs.cr_name = crst.rod_name AND vrcs.date = crst.catch_date AND vrcs.beat = crst.beat
  WHERE crst.dnf IS DISTINCT FROM true AND crst.guest IS DISTINCT FROM true
  ORDER BY vrcs.date;

CREATE OR REPLACE VIEW private.view_catch_returns_missing
AS SELECT date,
    cr_name,
    beat_id,
    beat,
    floor(EXTRACT(day FROM CURRENT_TIMESTAMP - date::timestamp without time zone::timestamp with time zone)) AS full_days_elapsed
   FROM private.view_reservations_confirmed_staging vrcs
  WHERE date < CURRENT_DATE AND NOT (EXISTS ( SELECT 1
           FROM private.catch_returns_staging_table crst
          WHERE vrcs.date = crst.catch_date AND vrcs.beat = crst.beat AND vrcs.cr_name = crst.rod_name))
  ORDER BY (floor(EXTRACT(day FROM CURRENT_TIMESTAMP - date::timestamp without time zone::timestamp with time zone))) DESC;

CREATE OR REPLACE VIEW private.view_in_season_dashb_3_freq_of_reservation
AS SELECT reservation_count,
    count(*) AS frequency
   FROM ( SELECT m.cr_name,
            count(DISTINCT vrcs.id) AS reservation_count
           FROM private.view_member_names m
             LEFT JOIN private.view_reservations_confirmed_staging vrcs ON m.cr_name = vrcs.cr_name
             LEFT JOIN private.catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name
          WHERE crst.dnf IS DISTINCT FROM true AND m.year_of_membership::numeric = (( SELECT EXTRACT(year FROM CURRENT_DATE) AS "extract"))
          GROUP BY m.cr_name) member_counts
  GROUP BY reservation_count
  ORDER BY reservation_count;

CREATE OR REPLACE VIEW private.view_in_season_dashb_1_count_res_cr
AS WITH timeline AS (
         SELECT generate_series(date_trunc('year'::text, CURRENT_DATE::timestamp with time zone) + '3 mons'::interval, (CURRENT_DATE - 1)::timestamp with time zone, '7 days'::interval)::date AS week_starting
        ), filtered_reservations AS (
         SELECT vrcs.date,
            vrcs.cr_name,
            vrcs.beat,
            crst."timestamp"
           FROM private.view_reservations_confirmed_staging vrcs
             LEFT JOIN private.catch_returns_staging_table crst 
             	ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name AND vrcs.beat = crst.beat
          WHERE crst.dnf IS DISTINCT FROM true AND vrcs.date < CURRENT_DATE AND crst.guest IS DISTINCT FROM true
        )
 SELECT week_starting,
    ( SELECT count(*) AS count
           FROM filtered_reservations fr
          WHERE fr.date >= t.week_starting AND fr.date < (t.week_starting + 7)) AS reservations,
    ( SELECT count(*) AS count
           FROM filtered_reservations fr
          WHERE fr.date >= t.week_starting AND fr.date < (t.week_starting + 7) AND fr."timestamp" IS NOT NULL) AS catch_returns
   FROM timeline t
  ORDER BY week_starting;

CREATE OR REPLACE VIEW private.view_in_season_dashb_2_count_reserv_by_beat
AS SELECT b.beat_short AS beat,
    count(DISTINCT vrcs.date) AS reservation_count
   FROM beats b
     LEFT JOIN private.view_reservations_confirmed_staging vrcs 
     	ON vrcs.beat_id = b.id AND vrcs.date >= make_date(EXTRACT(year FROM CURRENT_DATE)::integer, 4, 1) 
     		AND vrcs.date <= make_date(EXTRACT(year FROM CURRENT_DATE)::integer, 9, 30)
     LEFT JOIN private.catch_returns_staging_table crst 
     	ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name AND vrcs.beat = crst.beat
  WHERE b.id <> 18 AND crst.dnf IS DISTINCT FROM true AND crst.guest IS DISTINCT FROM true
  GROUP BY b.beat_short, b.river_order
  ORDER BY b.river_order;

CREATE OR REPLACE VIEW private.view_in_season_dashb_5_prop_grayling
AS WITH week_series AS (
         SELECT generate_series('2026-04-01'::date::timestamp with time zone, (( SELECT max(catch_date) AS max
                   FROM private.catch_returns_staging_table))::timestamp with time zone, '7 days'::interval)::date AS week_start
        ), weekly_counts AS (
         SELECT ws.week_start,
            sum(COALESCE(crst.brown_trout_released, 0) + COALESCE(crst.brown_trout_retained, 0) + COALESCE(crst.grayling, 0)) AS total_caught,
            sum(COALESCE(crst.grayling, 0)) AS total_grayling
           FROM week_series ws
             LEFT JOIN private.catch_returns_staging_table crst ON crst.catch_date >= ws.week_start AND crst.catch_date < (ws.week_start + 7)
          GROUP BY ws.week_start
        )
 SELECT week_start AS season_week_start,
    total_caught,
    total_grayling,
    round(COALESCE(total_grayling::numeric / NULLIF(total_caught, 0)::numeric * 100::numeric, 0::numeric), 1) AS grayling_percentage
   FROM weekly_counts
  ORDER BY week_start;

-- private.view_missing_cr_age_report5 source

CREATE OR REPLACE VIEW private.view_missing_cr_age_report5
AS WITH reservation_stats AS (
         SELECT vrcs.cr_name,
            count(*) AS total_reservations
           FROM private.view_reservations_confirmed_staging vrcs
             LEFT JOIN private.catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name AND vrcs.beat = crst.beat
          WHERE crst.guest IS DISTINCT FROM true AND crst.dnf IS DISTINCT FROM true AND vrcs.date < CURRENT_DATE
          GROUP BY vrcs.cr_name
        ), catch_returns_stats AS (
         SELECT vrcs.cr_name,
            sum(
                CASE
                    WHEN crst.rod_name IS NOT NULL THEN 1
                    ELSE 0
                END) AS total_submitted,
            count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 1 AND (CURRENT_DATE - vrcs.date) <= 7) AS "1-7 Days",
            count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 8 AND (CURRENT_DATE - vrcs.date) <= 14) AS "8-14 Days",
            count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 15 AND (CURRENT_DATE - vrcs.date) <= 21) AS "15-21 Days",
            count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 22 AND (CURRENT_DATE - vrcs.date) <= 28) AS "22-28 Days",
            count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) > 28) AS "28+ Days"
           FROM private.view_reservations_confirmed_staging vrcs
             LEFT JOIN private.catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name AND vrcs.beat = crst.beat
          WHERE crst.guest IS DISTINCT FROM true AND crst.dnf IS DISTINCT FROM true AND vrcs.date < CURRENT_DATE
          GROUP BY vrcs.cr_name
        )
 SELECT m.member_name,
    COALESCE(res.total_reservations, 0::bigint) AS "Reservations",
    COALESCE(crs.total_submitted, 0::bigint) AS "Catch Returns",
    COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint) AS "CRs Due",
    COALESCE(round(crs.total_submitted::numeric / NULLIF(res.total_reservations, 0)::numeric * 100::numeric, 1), 0::numeric) AS pct_compliance,
    COALESCE(crs."1-7 Days", 0::bigint) AS "1-7 Days",
    COALESCE(crs."8-14 Days", 0::bigint) AS "8-14 Days",
    COALESCE(crs."15-21 Days", 0::bigint) AS "15-21 Days",
    COALESCE(crs."22-28 Days", 0::bigint) AS "22-28 Days",
    COALESCE(crs."28+ Days", 0::bigint) AS "28+ Days"
   FROM private.view_member_names m
     LEFT JOIN reservation_stats res ON m.cr_name = res.cr_name
     LEFT JOIN catch_returns_stats crs ON m.cr_name = crs.cr_name
  WHERE (COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint)) > 0
  ORDER BY (COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint)) DESC;

drop view public.view_reservations_confirmed_staging;