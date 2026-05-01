CREATE OR REPLACE VIEW public.view_members_reserv_and_cr_history AS 
SELECT vrcs.date,
    vrcs.beat,
    crst.brown_trout_released + crst.brown_trout_retained AS brown_trout,
    crst.grayling,
    crst.comments,
    crst.guest,
    vrcs.cr_name
   FROM view_reservations_confirmed_staging vrcs
     LEFT JOIN catch_returns_staging_table crst 
     ON vrcs.cr_name = crst.rod_name AND vrcs.date = crst.catch_date
     where (crst.guest = false or crst.guest is null) 
  ORDER BY vrcs.date;