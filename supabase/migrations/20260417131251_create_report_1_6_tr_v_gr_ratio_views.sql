CREATE VIEW public.report_1_6_tr_v_gr_ratio as
SELECT 
    vtsd.seasonal_year,
    SUM(vtsd.brown_trout) AS total_brown_trout, 
    SUM(vtsd.grayling) AS total_grayling,
    -- The Calculation: (Grayling / Total) * 100
    ROUND(
        (SUM(vtsd.grayling) * 100.0) / NULLIF(SUM(vtsd.brown_trout) + SUM(vtsd.grayling), 0), 
        1
    ) AS grayling_percentage
FROM view_troutseasondata vtsd 
WHERE vtsd.seasonal_year NOT LIKE 'Off%'
GROUP BY vtsd.seasonal_year 
ORDER BY vtsd.seasonal_year ASC;

CREATE VIEW public.report_1_6_1_tr_v_gr_ratio_upper_lower as
SELECT 
    vtsd.seasonal_year,
    upper_lower,
    SUM(vtsd.brown_trout) AS total_brown_trout, 
    SUM(vtsd.grayling) AS total_grayling,
    -- The Calculation: (Grayling / Total) * 100
    ROUND(
        (SUM(vtsd.grayling) * 100.0) / NULLIF(SUM(vtsd.brown_trout) + SUM(vtsd.grayling), 0), 
        1
    ) AS grayling_percentage
FROM view_troutseasondata vtsd 
WHERE vtsd.seasonal_year NOT LIKE 'Off%' and upper_lower not like 'Unk%'
GROUP BY vtsd.seasonal_year, upper_lower
ORDER BY vtsd.seasonal_year ASC;