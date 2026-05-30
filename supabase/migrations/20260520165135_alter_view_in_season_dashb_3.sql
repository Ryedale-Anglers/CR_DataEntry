-- public.view_in_season_dashb_3_freq_of_reservation source

CREATE OR REPLACE VIEW public.view_in_season_dashb_3_freq_of_reservation
AS SELECT reservation_count,
    count(*) AS frequency
   FROM ( SELECT m.cr_name,
            count(DISTINCT vrcs.id) AS reservation_count
           FROM view_member_names m
             LEFT JOIN view_reservations_confirmed_staging vrcs ON m.cr_name = vrcs.cr_name
             LEFT JOIN catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name
          WHERE crst.dnf IS DISTINCT FROM true and m.year_of_membership = 2026
          GROUP BY m.cr_name) member_counts
  GROUP BY reservation_count
  ORDER BY reservation_count;