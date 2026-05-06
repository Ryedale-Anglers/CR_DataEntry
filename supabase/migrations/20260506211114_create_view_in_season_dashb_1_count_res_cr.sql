CREATE OR REPLACE VIEW public.view_in_season_dashb_1_count_res_cr
AS WITH timeline AS (
         SELECT generate_series('2026-04-01'::date::timestamp with time zone, CURRENT_DATE::timestamp with time zone, '7 days'::interval)::date AS week_starting
        ), res_calculations AS (
         SELECT '2026-04-01'::date + (floor((reservations_confirmed_staging.date - '2026-04-01'::date)::numeric / 7.0) * 7::numeric)::integer AS res_week,
            count(*) AS res_count
           FROM reservations_confirmed_staging
          WHERE reservations_confirmed_staging.date >= '2026-04-01'::date
          GROUP BY ('2026-04-01'::date + (floor((reservations_confirmed_staging.date - '2026-04-01'::date)::numeric / 7.0) * 7::numeric)::integer)
        ), catch_calculations AS (
         SELECT '2026-04-01'::date + (floor((catch_returns_staging_table.catch_date - '2026-04-01'::date)::numeric / 7.0) * 7::numeric)::integer AS catch_week,
            count(*) AS catch_count
           FROM catch_returns_staging_table
          WHERE catch_returns_staging_table.catch_date >= '2026-04-01'::date
          GROUP BY ('2026-04-01'::date + (floor((catch_returns_staging_table.catch_date - '2026-04-01'::date)::numeric / 7.0) * 7::numeric)::integer)
        )
 SELECT t.week_starting,
    COALESCE(r.res_count, 0::bigint) AS reservations,
    COALESCE(c.catch_count, 0::bigint) AS catches_returns
   FROM timeline t
     LEFT JOIN res_calculations r ON t.week_starting = r.res_week
     LEFT JOIN catch_calculations c ON t.week_starting = c.catch_week
  ORDER BY t.week_starting;