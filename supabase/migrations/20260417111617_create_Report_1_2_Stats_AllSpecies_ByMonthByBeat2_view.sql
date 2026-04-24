CREATE VIEW public.Report_1_2_Stats_AllSpecies_ByMonthByBeat2 AS 
SELECT 
    "Beat", "Apr", "May", "Jun", "Jul", "Aug", "Sept"
FROM (
    -- PART 1: Individual Beat Averages
    SELECT
        b."river_order" AS "SortKey", 
        b."beat" AS "Beat",
        ROUND(AVG(CASE WHEN vtsd."seasonal_month" LIKE 'Apr%' THEN vtsd."total_fish_caught" END)::numeric, 1) AS "Apr",
        ROUND(AVG(CASE WHEN vtsd."seasonal_month" LIKE 'May%' THEN vtsd."total_fish_caught" END)::numeric, 1) AS "May",
        ROUND(AVG(CASE WHEN vtsd."seasonal_month" LIKE 'Jun%' THEN vtsd."total_fish_caught" END)::numeric, 1) AS "Jun",
        ROUND(AVG(CASE WHEN vtsd."seasonal_month" LIKE 'Jul%' THEN vtsd."total_fish_caught" END)::numeric, 1) AS "Jul",
        ROUND(AVG(CASE WHEN vtsd."seasonal_month" LIKE 'Aug%' THEN vtsd."total_fish_caught" END)::numeric, 1) AS "Aug",
        ROUND(AVG(CASE WHEN vtsd."seasonal_month" LIKE 'Sep%' THEN vtsd."total_fish_caught" END)::numeric, 1) AS "Sept"
    FROM "beats" b
    LEFT JOIN "view_troutseasondata" vtsd ON vtsd."beat" = b."beat" 
        AND vtsd."seasonal_year_int" = (SELECT "target_year" FROM "year_param" LIMIT 1)
    WHERE b."beat" NOT LIKE '%Not Recorded%'
    GROUP BY b."river_order", b."beat"

    UNION ALL

    -- PART 2: The Grand Total
    SELECT 
        'z' AS "SortKey", 
        'Grand Total (Avg)' AS "Beat",
        ROUND(AVG(CASE WHEN v2."seasonal_month" LIKE 'Apr%' THEN v2."total_fish_caught" END)::numeric, 1) AS "Apr",
        ROUND(AVG(CASE WHEN v2."seasonal_month" LIKE 'May%' THEN v2."total_fish_caught" END)::numeric, 1) AS "May",
        ROUND(AVG(CASE WHEN v2."seasonal_month" LIKE 'Jun%' THEN v2."total_fish_caught" END)::numeric, 1) AS "Jun",
        ROUND(AVG(CASE WHEN v2."seasonal_month" LIKE 'Jul%' THEN v2."total_fish_caught" END)::numeric, 1) AS "Jul",
        ROUND(AVG(CASE WHEN v2."seasonal_month" LIKE 'Aug%' THEN v2."total_fish_caught" END)::numeric, 1) AS "Aug",
        ROUND(AVG(CASE WHEN v2."seasonal_month" LIKE 'Sep%' THEN v2."total_fish_caught" END)::numeric, 1) AS "Sept"
    FROM "view_troutseasondata" v2
    WHERE v2."seasonal_year_int" = (SELECT "target_year" FROM "year_param" LIMIT 1)
) AS "CombinedStats"
ORDER BY "SortKey" ASC;