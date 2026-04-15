CREATE OR REPLACE VIEW public.view_base_catch AS
SELECT 
    b.river_order, 
    b.beat, 
    b.beat_short,
    c.catch_date,
    COALESCE(c.brown_trout, 0) + COALESCE(c.brown_trout_killed, 0) AS BrownTrout,
    COALESCE(c.grayling, 0) AS Grayling,
    (
        COALESCE(c.brown_trout, 0) + 
        COALESCE(c.brown_trout_killed, 0) + 
        COALESCE(c.grayling, 0) + 
        COALESCE(c.rainbow_trout, 0) + 
        COALESCE(c.other_species, 0)
    ) AS TotalCaught,
    c.guest,
    CASE 
        WHEN TO_CHAR(c.catch_date, 'MM') BETWEEN '04' AND '09' 
        THEN TO_CHAR(c.catch_date, 'YYYY')
        ELSE 'Off-Season' 
    END AS SeasonalYear,
    CASE 
        WHEN TO_CHAR(c.catch_date, 'MM') BETWEEN '04' AND '09' 
        THEN CAST(TO_CHAR(c.catch_date, 'YYYY') AS INTEGER)
        ELSE NULL 
    END AS SeasonalYear_Int  
FROM public.catch_returns AS c
INNER JOIN public.beats AS b ON c.beats_id = b.id
WHERE c.guest IS FALSE;


CREATE OR REPLACE VIEW public.report_1_1_stats_allspecies_bybeat AS
WITH AnnualStats AS (
    SELECT 
        beat_short, -- Using your Postgres column naming convention
        river_order,
        COUNT(*) AS Visits,
        SUM(totalcaught) AS TotalFish, 
        ROUND(AVG(totalcaught)::numeric, 1) AS Average,
        MAX(totalcaught) AS MaxCatch,
        MIN(totalcaught) AS MinCatch
    FROM view_base_catch -- Using the view we just created
    WHERE seasonalyear_int = (SELECT target_year FROM year_param LIMIT 1) 
    GROUP BY beat_short, river_order
),
StackedStats AS (
    SELECT beat_short, '1_Max' AS StatType, MaxCatch AS Val, NULL::numeric AS RawSum, NULL::bigint AS RawCount FROM AnnualStats
    UNION ALL
    SELECT beat_short, '2_Average' AS StatType, Average, TotalFish::numeric, Visits::bigint FROM AnnualStats
    UNION ALL
    SELECT beat_short, '3_Min' AS StatType, MinCatch, NULL::numeric, NULL::bigint FROM AnnualStats
    UNION ALL
    SELECT beat_short, '4_Visits' AS StatType, Visits, NULL::numeric, NULL::bigint FROM AnnualStats
)
SELECT 
    substring(StatType from 3) AS Statistic,
    NULLIF(MAX(CASE WHEN beat_short = 'G''cliffe' THEN Val END), 0) AS "G'liffe",
    NULLIF(MAX(CASE WHEN beat_short = 'Abbey' THEN Val END), 0) AS "Abbey",
    NULLIF(MAX(CASE WHEN beat_short = 'Holl''s Wood' THEN Val END), 0) AS "H's Wood",
    NULLIF(MAX(CASE WHEN beat_short = 'P''horse Br' THEN Val END), 0) AS "P'hrse Br",
    NULLIF(MAX(CASE WHEN beat_short = 'Mill Weir' THEN Val END), 0) AS "Mill Weir",
    NULLIF(MAX(CASE WHEN beat_short = 'D''combe Pk' THEN Val END), 0) AS "D'omb Pk",
    NULLIF(MAX(CASE WHEN beat_short = 'Hy Field' THEN Val END), 0) AS "Hy Field",
    NULLIF(MAX(CASE WHEN beat_short = 'F''land' THEN Val END), 0) AS "F'ry land",
    NULLIF(MAX(CASE WHEN beat_short = 'S''age Farm' THEN Val END), 0) AS "S'age Farm",
    NULLIF(MAX(CASE WHEN beat_short = 'The Cut' THEN Val END), 0) AS "T'Cut",
    NULLIF(MAX(CASE WHEN beat_short = 'Upr Rye Hse' THEN Val END), 0) AS "Upr Rye Hse",
    NULLIF(MAX(CASE WHEN beat_short = 'Lwr Rye Hse' THEN Val END), 0) AS "Lwr Rye Hse",
    NULLIF(MAX(CASE WHEN beat_short = 'Heronry' THEN Val END), 0) AS "H'onry",
    NULLIF(MAX(CASE WHEN beat_short = 'Upr H''rome' THEN Val END), 0) AS "Up H'ome",
    NULLIF(MAX(CASE WHEN beat_short = 'Mid H''rome' THEN Val END), 0) AS "Md H'ome",
    NULLIF(MAX(CASE WHEN beat_short = 'Lwr H''rome' THEN Val END), 0) AS "Lw H'ome",
    NULLIF(MAX(CASE WHEN beat_short = 'F''hut & R''way Br' THEN Val END), 0) AS "F'hut & R'way Br",
    CASE StatType
        WHEN '1_Max'     THEN MAX(Val)
        WHEN '2_Average' THEN ROUND((SUM(RawSum) / NULLIF(SUM(RawCount), 0))::numeric, 1) 
        WHEN '3_Min'     THEN MIN(Val)
        WHEN '4_Visits'  THEN SUM(Val)
    END AS "River Total"
FROM StackedStats
GROUP BY StatType
ORDER BY StatType;

CREATE OR REPLACE VIEW public.report_1_1_stats_browntrout_bybeat AS
WITH AnnualStats AS (
    SELECT 
        beat_short, -- Using your Postgres column naming convention
        river_order,
        COUNT(*) AS Visits,
        SUM(browntrout) AS TotalFish, 
        ROUND(AVG(browntrout)::numeric, 1) AS Average,
        MAX(browntrout) AS MaxCatch,
        MIN(browntrout) AS MinCatch
    FROM view_base_catch -- Using the view we just created
    WHERE seasonalyear_int = (SELECT target_year FROM year_param LIMIT 1) 
    GROUP BY beat_short, river_order
),
StackedStats AS (
    SELECT beat_short, river_order, '1_Max' AS StatType, MaxCatch AS Val, NULL AS RawSum, NULL AS RawCount FROM AnnualStats
    UNION ALL
    SELECT beat_short, river_order, '2_Average' AS StatType, Average, TotalFish, Visits FROM AnnualStats
    UNION ALL
    SELECT beat_short, river_order, '3_Min' AS StatType, MinCatch, NULL, NULL FROM AnnualStats
    UNION ALL
    SELECT beat_short, river_order, '4_Visits' AS StatType, Visits, NULL, NULL FROM AnnualStats
)
SELECT 
    substring(StatType from 3) AS Statistic,
    NULLIF(MAX(CASE WHEN beat_short = 'G''cliffe' THEN Val END), 0) AS "G'liffe",
    NULLIF(MAX(CASE WHEN beat_short = 'Abbey' THEN Val END), 0) AS "Abbey",
    NULLIF(MAX(CASE WHEN beat_short = 'Holl''s Wood' THEN Val END), 0) AS "H's Wood",
    NULLIF(MAX(CASE WHEN beat_short = 'P''horse Br' THEN Val END), 0) AS "P'hrse Br",
    NULLIF(MAX(CASE WHEN beat_short = 'Mill Weir' THEN Val END), 0) AS "Mill Weir",
    NULLIF(MAX(CASE WHEN beat_short = 'D''combe Pk' THEN Val END), 0) AS "D'omb Pk",
    NULLIF(MAX(CASE WHEN beat_short = 'Hy Field' THEN Val END), 0) AS "Hy Field",
    NULLIF(MAX(CASE WHEN beat_short = 'F''land' THEN Val END), 0) AS "F'ry land",
    NULLIF(MAX(CASE WHEN beat_short = 'S''age Farm' THEN Val END), 0) AS "S'age Farm",
    NULLIF(MAX(CASE WHEN beat_short = 'The Cut' THEN Val END), 0) AS "T'Cut",
    NULLIF(MAX(CASE WHEN beat_short = 'Upr Rye Hse' THEN Val END), 0) AS "Upr Rye Hse",
    NULLIF(MAX(CASE WHEN beat_short = 'Lwr Rye Hse' THEN Val END), 0) AS "Lwr Rye Hse",
    NULLIF(MAX(CASE WHEN beat_short = 'Heronry' THEN Val END), 0) AS "H'onry",
    NULLIF(MAX(CASE WHEN beat_short = 'Upr H''rome' THEN Val END), 0) AS "Up H'ome",
    NULLIF(MAX(CASE WHEN beat_short = 'Mid H''rome' THEN Val END), 0) AS "Md H'ome",
    NULLIF(MAX(CASE WHEN beat_short = 'Lwr H''rome' THEN Val END), 0) AS "Lw H'ome",
    NULLIF(MAX(CASE WHEN beat_short = 'F''hut & R''way Br' THEN Val END), 0) AS "F'hut & R'way Br",
    CASE StatType
        WHEN '1_Max'     THEN MAX(Val)
        WHEN '2_Average' THEN ROUND((SUM(RawSum) / NULLIF(SUM(RawCount), 0))::numeric, 1)
        WHEN '3_Min'     THEN MIN(Val)
        WHEN '4_Visits'  THEN SUM(Val)
    END AS "River Total"
FROM StackedStats
GROUP BY StatType
ORDER BY StatType;

CREATE OR REPLACE VIEW public.report_1_1_stats_grayling_bybeat AS
WITH AnnualStats AS (
    SELECT 
        beat_short, -- Using your Postgres column naming convention
        river_order,
        COUNT(*) AS Visits,
        SUM(grayling) AS TotalFish, 
        ROUND(AVG(grayling)::numeric, 1) AS Average,
        MAX(grayling) AS MaxCatch,
        MIN(grayling) AS MinCatch
    FROM view_base_catch -- Using the view we just created
    WHERE seasonalyear_int = (SELECT target_year FROM year_param LIMIT 1) 
    GROUP BY beat_short, river_order
),
StackedStats AS (
    SELECT beat_short, river_order, '1_Max' AS StatType, MaxCatch AS Val, NULL AS RawSum, NULL AS RawCount FROM AnnualStats
    UNION ALL
    SELECT beat_short, river_order, '2_Average' AS StatType, Average, TotalFish, Visits FROM AnnualStats
    UNION ALL
    SELECT beat_short, river_order, '3_Min' AS StatType, MinCatch, NULL, NULL FROM AnnualStats
    UNION ALL
    SELECT beat_short, river_order, '4_Visits' AS StatType, Visits, NULL, NULL FROM AnnualStats
)
SELECT 
    substring(StatType from 3) AS Statistic,
    NULLIF(MAX(CASE WHEN beat_short = 'G''cliffe' THEN Val END), 0) AS "G'liffe",
    NULLIF(MAX(CASE WHEN beat_short = 'Abbey' THEN Val END), 0) AS "Abbey",
    NULLIF(MAX(CASE WHEN beat_short = 'Holl''s Wood' THEN Val END), 0) AS "H's Wood",
    NULLIF(MAX(CASE WHEN beat_short = 'P''horse Br' THEN Val END), 0) AS "P'hrse Br",
    NULLIF(MAX(CASE WHEN beat_short = 'Mill Weir' THEN Val END), 0) AS "Mill Weir",
    NULLIF(MAX(CASE WHEN beat_short = 'D''combe Pk' THEN Val END), 0) AS "D'omb Pk",
    NULLIF(MAX(CASE WHEN beat_short = 'Hy Field' THEN Val END), 0) AS "Hy Field",
    NULLIF(MAX(CASE WHEN beat_short = 'F''land' THEN Val END), 0) AS "F'ry land",
    NULLIF(MAX(CASE WHEN beat_short = 'S''age Farm' THEN Val END), 0) AS "S'age Farm",
    NULLIF(MAX(CASE WHEN beat_short = 'The Cut' THEN Val END), 0) AS "T'Cut",
    NULLIF(MAX(CASE WHEN beat_short = 'Upr Rye Hse' THEN Val END), 0) AS "Upr Rye Hse",
    NULLIF(MAX(CASE WHEN beat_short = 'Lwr Rye Hse' THEN Val END), 0) AS "Lwr Rye Hse",
    NULLIF(MAX(CASE WHEN beat_short = 'Heronry' THEN Val END), 0) AS "H'onry",
    NULLIF(MAX(CASE WHEN beat_short = 'Upr H''rome' THEN Val END), 0) AS "Up H'ome",
    NULLIF(MAX(CASE WHEN beat_short = 'Mid H''rome' THEN Val END), 0) AS "Md H'ome",
    NULLIF(MAX(CASE WHEN beat_short = 'Lwr H''rome' THEN Val END), 0) AS "Lw H'ome",
    NULLIF(MAX(CASE WHEN beat_short = 'F''hut & R''way Br' THEN Val END), 0) AS "F'hut & R'way Br",
    CASE StatType
        WHEN '1_Max'     THEN MAX(Val)
        WHEN '2_Average' THEN ROUND((SUM(RawSum) / NULLIF(SUM(RawCount), 0))::numeric, 1)
        WHEN '3_Min'     THEN MIN(Val)
        WHEN '4_Visits'  THEN SUM(Val)
    END AS "River Total"
FROM StackedStats
GROUP BY StatType
ORDER BY StatType;

-- View_TroutSeasonData source


CREATE OR REPLACE VIEW public.view_troutseasondata AS
SELECT 
    c.id, 
    c.member_name, 
    -- COALESCE handles potential NULLs so math doesn't break
    COALESCE(c.brown_trout, 0) + COALESCE(c.brown_trout_killed, 0) AS brown_trout, 
    c.brown_trout_killed, 
    c.rainbow_trout, 
    c.grayling, 
    c.other_species,
    -- TO_CHAR with 'Mon' gives the 3-character month (Jan, Feb, etc.)
    TO_CHAR(c.catch_date, 'Mon') AS seasonal_month,
    -- Seasonal Year Logic
    CASE 
        WHEN TO_CHAR(c.catch_date, 'MM') BETWEEN '04' AND '09' 
        THEN TO_CHAR(c.catch_date, 'YYYY')
        ELSE 'Off-Season' 
    END AS seasonal_year,
    -- In Postgres, this column MUST be one type. 
    -- We use NULL for Off-Season to keep the column as an INTEGER.
    CASE 
        WHEN TO_CHAR(c.catch_date, 'MM') BETWEEN '04' AND '09' 
        THEN CAST(TO_CHAR(c.catch_date, 'YYYY') AS INTEGER)
        ELSE NULL 
    END AS seasonal_year_int,
    c.catch_date, 
    b.beat, 
    b.beat_short, 
    b.river_order, 
    b.upper_lower, 
    c.guest,
    (
        COALESCE(c.brown_trout, 0) + 
        COALESCE(c.brown_trout_killed, 0) + 
        COALESCE(c.grayling, 0) + 
        COALESCE(c.rainbow_trout, 0) + 
        COALESCE(c.other_species, 0)
    ) AS total_fish_caught
FROM public.catch_returns c
JOIN public.beats b ON c.beats_id = b.id
-- Boolean check: no quotes or LIKE needed
WHERE c.guest IS FALSE;

-- 1. Explicitly drop the old view first to clear the column schema
DROP VIEW IF EXISTS public.view_missing_cr_age_report;

-- 2. Now create the new version with the new columns
CREATE VIEW "public"."view_missing_cr_age_report" AS
WITH return_stats AS (
    SELECT 
        vrcs.cr_name,
        CURRENT_DATE - vrcs.date AS days_old,
        -- 1 if submitted, 0 if missing
        CASE WHEN crst.rod_name IS NOT NULL THEN 1 ELSE 0 END as was_submitted
    FROM view_reservations_confirmed_staging vrcs
    LEFT JOIN catch_returns_staging_table crst 
        ON vrcs.cr_name = crst.rod_name 
        AND vrcs.date = crst.catch_date
    WHERE vrcs.date < CURRENT_DATE
)
SELECT 
    m.member_name,
    SUM(rs.was_submitted) AS "Returns Submitted",
    --COUNT(CASE WHEN rs.was_submitted = 0 AND rs.days_old <= 7 THEN 1 END) AS "1-7 Days",
    COUNT(CASE WHEN rs.was_submitted = 0 AND rs.days_old > 7 AND rs.days_old <= 14 THEN 1 END) AS "8-14 Days",
    COUNT(CASE WHEN rs.was_submitted = 0 AND rs.days_old > 14 AND rs.days_old <= 21 THEN 1 END) AS "15-21 Days",
    COUNT(CASE WHEN rs.was_submitted = 0 AND rs.days_old > 21 AND rs.days_old <= 28 THEN 1 END) AS "21-28 Days",
    COUNT(CASE WHEN rs.was_submitted = 0 AND rs.days_old > 28 THEN 1 END) AS "28+ Days",
    COUNT(CASE WHEN rs.was_submitted = 0 THEN 1 END) AS "Total Missing"
FROM members m
JOIN return_stats rs ON m.cr_name = rs.cr_name
GROUP BY m.member_name
-- Filter: Only show members where the count of missing returns is greater than 0
HAVING COUNT(CASE WHEN rs.was_submitted = 0 THEN 1 END) > 0
ORDER BY "Total Missing" DESC;