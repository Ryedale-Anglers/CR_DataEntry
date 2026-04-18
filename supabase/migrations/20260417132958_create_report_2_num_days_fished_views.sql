CREATE VIEW report_2_0_num_days_fished_by_beat as
select beat, count(ID) as num_days_fished from view_troutseasondata vtsd 
WHERE seasonal_year_int = (SELECT target_year FROM year_param LIMIT 1)
group by vtsd.beat, vtsd.river_order
Order by vtsd.river_order;

CREATE VIEW report_2_1_num_days_fished_by_beat_by_month as
select beat_short, river_order, seasonal_month, count(ID) as num_days_fished from view_troutseasondata vtsd 
WHERE seasonal_year_int = (SELECT target_year FROM year_param LIMIT 1)
group by vtsd.beat_short, vtsd.seasonal_month, vtsd.river_order
Order by vtsd.river_order;

CREATE VIEW public.report_2_3_num_days_fished__by_year as
Select seasonal_year, Count(ID) as num_catch_returns 
from view_troutseasondata vtsd 
where seasonal_year not like '%Off%'
group by seasonal_year
order by seasonal_year ASC;