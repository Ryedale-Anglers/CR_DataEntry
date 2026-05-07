CREATE OR REPLACE VIEW public.view_in_season_dashb_5_prop_grayling
AS WITH week_series AS (
         SELECT generate_series('2026-04-01'::date::timestamp with time zone, (( SELECT max(catch_returns_staging_table.catch_date) AS max
                   FROM catch_returns_staging_table))::timestamp with time zone, '7 days'::interval)::date AS week_start
        ), weekly_counts AS (
         SELECT ws.week_start,
            sum(COALESCE(crst.brown_trout_released, 0) + COALESCE(crst.brown_trout_retained, 0) + COALESCE(crst.grayling, 0)) AS total_caught,
            sum(COALESCE(crst.grayling, 0)) AS total_grayling
           FROM week_series ws
             LEFT JOIN catch_returns_staging_table crst ON crst.catch_date >= ws.week_start AND crst.catch_date < (ws.week_start + 7)
          GROUP BY ws.week_start
        )
 SELECT week_start AS season_week_start,
    total_caught,
    total_grayling,
    round(COALESCE(total_grayling::numeric / NULLIF(total_caught, 0)::numeric * 100::numeric, 0::numeric), 1) AS grayling_percentage
   FROM weekly_counts
  ORDER BY week_start;