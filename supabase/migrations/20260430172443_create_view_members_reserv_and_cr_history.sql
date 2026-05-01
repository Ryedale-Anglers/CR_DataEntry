create view public.view_members_reserv_and_cr_history as
select 	vrcs."date",
		vrcs.beat, 
		crst.brown_trout_released + crst.brown_trout_retained as brown_trout, 
		crst.grayling, 
		crst."comments",
		crst.guest
from 
view_reservations_confirmed_staging vrcs 
left join 
catch_returns_staging_table crst 
on 
vrcs.cr_name = crst.rod_name 
and 
vrcs."date" = crst.catch_date
order by vrcs."date" asc