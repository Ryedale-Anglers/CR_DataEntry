CREATE VIEW public.report_1_4_freq_browntrout as 
SELECT 
    brown_trout  as CatchSize, 
    COUNT(*) AS Frequency
FROM view_troutseasondata vt 
WHERE vt.seasonal_year_int  = (SELECT target_year FROM year_param LIMIT 1)
GROUP BY vt.brown_trout 
ORDER BY vt.brown_trout  ASC;

CREATE VIEW public.report_1_4_freq_grayling as 
SELECT 
    grayling  as CatchSize, 
    COUNT(*) AS Frequency
FROM view_troutseasondata vt 
WHERE vt.seasonal_year_int  = (SELECT target_year FROM year_param LIMIT 1)
GROUP BY vt.grayling 
ORDER BY vt.grayling  ASC;

CREATE VIEW public.report_1_4_freq_totalfishcaught as 
SELECT 
    total_fish_caught  as CatchSize, 
    COUNT(*) AS Frequency
FROM view_troutseasondata vt 
WHERE vt.seasonal_year_int  = (SELECT target_year FROM year_param LIMIT 1)
GROUP BY vt.total_fish_caught 
ORDER BY vt.total_fish_caught  ASC;