CREATE OR REPLACE VIEW public.view_in_season_dashb_4_freq_catchsize
AS WITH total_catch AS (
         SELECT COALESCE(crst.brown_trout_released, 0) + COALESCE(crst.brown_trout_retained, 0) + COALESCE(crst.grayling, 0) + COALESCE(crst.other_species, 0) + COALESCE(crst.rainbow_trout, 0) AS catchsize
           FROM catch_returns_staging_table crst
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