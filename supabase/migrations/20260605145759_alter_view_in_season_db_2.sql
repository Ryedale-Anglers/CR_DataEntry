CREATE OR REPLACE VIEW public.view_in_season_dashb_2_count_reserv_by_beat AS 
SELECT b.beat_short AS beat,
    count(DISTINCT vrcs.date) AS reservation_count
   FROM beats b
     LEFT JOIN view_reservations_confirmed_staging vrcs ON vrcs.beat_id = b.id AND vrcs.date >= make_date(EXTRACT(year FROM CURRENT_DATE)::integer, 4, 1)
     AND vrcs.date <= make_date(EXTRACT(year FROM CURRENT_DATE)::integer, 9, 30)
     LEFT JOIN catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name and vrcs.beat = crst.beat
  WHERE b.id <> 18 AND crst.dnf IS DISTINCT FROM true
  GROUP BY b.beat_short, b.river_order
  ORDER BY b.river_order;