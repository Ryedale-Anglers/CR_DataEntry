create view view_catch_returns_staging_table_anonymous as
select	crst.catch_date, 
		crst.beat, 
		crst.brown_trout_released, 
		crst.grayling, 
		crst.rainbow_trout, 
		crst.other_species, crst.brown_trout_retained, crst."comments" 
from catch_returns_staging_table crst
where (EXTRACT(MONTH FROM crst.catch_date) BETWEEN 4 AND 9)
order by catch_date, beat