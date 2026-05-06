CREATE OR REPLACE VIEW public.view_in_season_dashb_3_freq_of_reservation
AS SELECT reservation_count,
    count(*) AS frequency
   FROM ( SELECT m.cr_name,
            count(vrcs.cr_name) AS reservation_count
           FROM members m
             LEFT JOIN view_reservations_confirmed_staging vrcs ON m.cr_name = vrcs.cr_name
          GROUP BY m.cr_name) member_counts
  GROUP BY reservation_count
  ORDER BY reservation_count;