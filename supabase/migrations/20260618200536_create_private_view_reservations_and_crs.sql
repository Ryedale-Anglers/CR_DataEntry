create view private.view_reservations_and_crs as 
select  vrcs.name, vrcs.date, vrcs.beat,
        crst.brown_trout_released, crst.grayling, crst.comments
from public.view_reservations_confirmed_staging vrcs 
left join public.catch_returns_staging_table crst 
on vrcs.cr_name = crst.rod_name and vrcs.date = crst.catch_date and vrcs.beat = crst.beat 
where crst.dnf is distinct from true and crst.guest is distinct from true
order by vrcs.date asc