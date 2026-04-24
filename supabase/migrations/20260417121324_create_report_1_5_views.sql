CREATE VIEW public.report_1_5_upper_lower_all as
SELECT 
    seasonal_year, 
    ROUND(AVG(CASE WHEN upper_lower = 'Upper' THEN total_fish_caught END), 1) AS Upper_Avg,
    ROUND(AVG(CASE WHEN upper_lower = 'Lower' THEN total_fish_caught END), 1) AS Lower_Avg
FROM view_troutseasondata vtsd
WHERE vtsd.seasonal_year NOT LIKE 'Off%' 
GROUP BY vtsd.seasonal_year
ORDER BY vtsd.seasonal_year ASC;

CREATE VIEW public.report_1_5_upper_lower_grayling as
SELECT 
    seasonal_year, 
    ROUND(AVG(CASE WHEN upper_lower = 'Upper' THEN grayling END), 1) AS Upper_Avg,
    ROUND(AVG(CASE WHEN upper_lower = 'Lower' THEN grayling END), 1) AS Lower_Avg
FROM view_troutseasondata vtsd
WHERE vtsd.seasonal_year NOT LIKE 'Off%' 
GROUP BY vtsd.seasonal_year
ORDER BY vtsd.seasonal_year ASC;

CREATE VIEW public.report_1_5_upper_lower_browntrout as
SELECT 
    seasonal_year, 
    ROUND(AVG(CASE WHEN upper_lower = 'Upper' THEN brown_trout END), 1) AS Upper_Avg,
    ROUND(AVG(CASE WHEN upper_lower = 'Lower' THEN brown_trout END), 1) AS Lower_Avg
FROM view_troutseasondata vtsd
WHERE vtsd.seasonal_year NOT LIKE 'Off%' 
GROUP BY vtsd.seasonal_year
ORDER BY vtsd.seasonal_year ASC;