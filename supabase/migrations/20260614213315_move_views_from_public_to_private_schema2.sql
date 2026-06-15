drop view public.report_1_1_stats_allspecies_bybeat;
drop view public.report_1_1_stats_grayling_bybeat;
drop view public.report_1_1_stats_browntrout_bybeat;
drop view public.report_1_2_stats_allspecies_bymonthbybeat2;
CREATE OR REPLACE VIEW private.report_1_2_stats_allspecies_bymonthbybeat2
AS SELECT "Beat",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sept"
   FROM ( SELECT b.river_order AS "SortKey",
            b.beat AS "Beat",
            round(avg(
                CASE
                    WHEN vtsd.seasonal_month ~~ 'Apr%'::text THEN vtsd.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Apr",
            round(avg(
                CASE
                    WHEN vtsd.seasonal_month ~~ 'May%'::text THEN vtsd.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "May",
            round(avg(
                CASE
                    WHEN vtsd.seasonal_month ~~ 'Jun%'::text THEN vtsd.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Jun",
            round(avg(
                CASE
                    WHEN vtsd.seasonal_month ~~ 'Jul%'::text THEN vtsd.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Jul",
            round(avg(
                CASE
                    WHEN vtsd.seasonal_month ~~ 'Aug%'::text THEN vtsd.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Aug",
            round(avg(
                CASE
                    WHEN vtsd.seasonal_month ~~ 'Sep%'::text THEN vtsd.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Sept"
           FROM beats b
             LEFT JOIN view_troutseasondata vtsd ON vtsd.beat = b.beat AND vtsd.seasonal_year_int = (( SELECT year_param.target_year
                   FROM year_param
                 LIMIT 1))
          WHERE b.beat !~~ '%Not Recorded%'::text
          GROUP BY b.river_order, b.beat
        UNION ALL
         SELECT 'z'::text AS "SortKey",
            'Grand Total (Avg)'::text AS "Beat",
            round(avg(
                CASE
                    WHEN v2.seasonal_month ~~ 'Apr%'::text THEN v2.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Apr",
            round(avg(
                CASE
                    WHEN v2.seasonal_month ~~ 'May%'::text THEN v2.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "May",
            round(avg(
                CASE
                    WHEN v2.seasonal_month ~~ 'Jun%'::text THEN v2.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Jun",
            round(avg(
                CASE
                    WHEN v2.seasonal_month ~~ 'Jul%'::text THEN v2.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Jul",
            round(avg(
                CASE
                    WHEN v2.seasonal_month ~~ 'Aug%'::text THEN v2.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Aug",
            round(avg(
                CASE
                    WHEN v2.seasonal_month ~~ 'Sep%'::text THEN v2.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Sept"
           FROM view_troutseasondata v2
          WHERE v2.seasonal_year_int = (( SELECT year_param.target_year
                   FROM year_param
                 LIMIT 1))) "CombinedStats"
  ORDER BY "SortKey";