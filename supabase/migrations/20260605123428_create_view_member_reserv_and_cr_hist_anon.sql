create view view_members_reserv_and_cr_history_anonymous as
select 	vrcs.date, vrcs.beat, 
		crst.brown_trout_released + crst.brown_trout_retained AS brown_trout,
    	crst.grayling,
    	crst.comments
    	from view_reservations_confirmed_staging vrcs
left join catch_returns_staging_table crst on 
vrcs.date = crst.catch_date and vrcs.cr_name = crst.rod_name and vrcs.beat = crst.beat
where crst.dnf is distinct from true and crst.guest is distinct from true
order by vrcs.date asc;