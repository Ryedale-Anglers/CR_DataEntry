-- Section 1.6.2 (monthly trout vs grayling ratio) counted trout killed twice.
-- In view_troutseasondata (and _v5_5), brown_trout is already released + killed,
-- but these views added brown_trout_killed again. They now use sum(brown_trout),
-- the same as report_1_6_tr_v_gr_ratio. Columns and their order are unchanged.
-- Fixed in both the V5_4 views and their _v5_5 copies.

CREATE OR REPLACE VIEW private.report_1_6_2_tr_v_gr_ratio_curr_year_monthly AS
SELECT sum(brown_trout) AS total_brown_trout,
       sum(grayling) AS total_grayling,
       round(sum(grayling)::numeric * 100.0 / NULLIF(sum(brown_trout) + sum(grayling), 0)::numeric, 1) AS grayling_percentage,
       seasonal_month
FROM private.view_troutseasondata vt
WHERE seasonal_year_int = (SELECT year_param.target_year FROM private.year_param LIMIT 1)
GROUP BY seasonal_month
ORDER BY (to_date(seasonal_month, 'Mon'::text));

CREATE OR REPLACE VIEW private.report_1_6_2_tr_v_gr_ratio_historical_monthly AS
SELECT sum(brown_trout) AS total_brown_trout,
       sum(grayling) AS total_grayling,
       round(sum(grayling)::numeric * 100.0 / NULLIF(sum(brown_trout) + sum(grayling), 0)::numeric, 1) AS grayling_percentage,
       seasonal_month
FROM private.view_troutseasondata vt
WHERE seasonal_year !~~ 'Off%'::text
  AND seasonal_year_int <> (SELECT year_param.target_year FROM private.year_param LIMIT 1)
GROUP BY seasonal_month
ORDER BY (to_date(seasonal_month, 'Mon'::text));

CREATE OR REPLACE VIEW private.report_1_6_2_tr_v_gr_ratio_curr_year_monthly_v5_5 AS
SELECT sum(brown_trout) AS total_brown_trout,
       sum(grayling) AS total_grayling,
       round(sum(grayling)::numeric * 100.0 / NULLIF(sum(brown_trout) + sum(grayling), 0)::numeric, 1) AS grayling_percentage,
       seasonal_month
FROM private.view_troutseasondata_v5_5 vt
WHERE seasonal_year_int = (SELECT year_param.target_year FROM private.year_param LIMIT 1)
GROUP BY seasonal_month
ORDER BY (to_date(seasonal_month, 'Mon'::text));

CREATE OR REPLACE VIEW private.report_1_6_2_tr_v_gr_ratio_historical_monthly_v5_5 AS
SELECT sum(brown_trout) AS total_brown_trout,
       sum(grayling) AS total_grayling,
       round(sum(grayling)::numeric * 100.0 / NULLIF(sum(brown_trout) + sum(grayling), 0)::numeric, 1) AS grayling_percentage,
       seasonal_month
FROM private.view_troutseasondata_v5_5 vt
WHERE seasonal_year !~~ 'Off%'::text
  AND seasonal_year_int <> (SELECT year_param.target_year FROM private.year_param LIMIT 1)
GROUP BY seasonal_month
ORDER BY (to_date(seasonal_month, 'Mon'::text));
