CREATE OR REPLACE VIEW private.view_secrep_membername_catchreturns_count_operational
AS WITH filtered_data AS (
         SELECT vrcs.cr_name,
            crst.catch_date AS has_return
           FROM private.reservations_confirmed_staging vrcs
             LEFT JOIN private.catch_returns_staging_table crst 
             	ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name
          WHERE crst.dnf IS DISTINCT FROM true
        )
 SELECT cr_name,
    count(*) AS reservations_count,
    count(has_return) AS returns_count,
    count(*) - count(has_return) AS variance
   FROM filtered_data
  GROUP BY cr_name
  ORDER BY (count(*)) DESC;

CREATE OR REPLACE VIEW private.view_in_season_dashb_4_freq_catchsize
AS WITH total_catch AS (
         SELECT COALESCE(crst.brown_trout_released, 0) + 
         	COALESCE(crst.brown_trout_retained, 0) + 
         		COALESCE(crst.grayling, 0) + 
         			COALESCE(crst.other_species, 0) + 
         				COALESCE(crst.rainbow_trout, 0) AS catchsize
           FROM private.catch_returns_staging_table crst
        ), max_val AS (
         SELECT max(total_catch.catchsize) AS m
           FROM total_catch
        ), all_numbers AS (
         SELECT generate_series(0, ( SELECT max_val.m
                   FROM max_val)) AS catchsize
        )
 SELECT n.catchsize,
    count(t.catchsize) AS frequency
   FROM all_numbers n
     LEFT JOIN total_catch t ON n.catchsize = t.catchsize
  GROUP BY n.catchsize
  ORDER BY n.catchsize;

drop table public.catch_returns_staging_table;

CREATE OR REPLACE VIEW private.view_reservations_confirmed_staging_anon
AS SELECT rcs.date,
    rb.beat_id,
    bt.beat,
    bt.river_order,
    rcs.id
   FROM private.reservations_confirmed_staging rcs
     JOIN private.reservation_beats rb ON rb.beat = rcs.resource
     JOIN private.beats bt ON rb.beat_id = bt.id
  ORDER BY rcs.date;

--drop view public.view_reservations_confirmed_staging_anon;

drop table public.reservations_confirmed_staging;
