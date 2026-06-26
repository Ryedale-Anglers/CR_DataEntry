CREATE OR REPLACE VIEW private.view_in_season_dashb_2_count_reserv_by_beat AS 
SELECT b.beat_short AS beat,
    count(DISTINCT vrcs.date) AS reservation_count
   FROM beats b
     LEFT JOIN public.view_reservations_confirmed_staging vrcs 
     	ON vrcs.beat_id = b.id AND vrcs.date >= make_date(EXTRACT(year FROM CURRENT_DATE)::integer, 4, 1) 
     		AND vrcs.date <= make_date(EXTRACT(year FROM CURRENT_DATE)::integer, 9, 30)
     LEFT JOIN public.catch_returns_staging_table crst 
     	ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name AND vrcs.beat = crst.beat
  WHERE b.id <> 18 AND crst.dnf IS DISTINCT FROM true and crst.guest is distinct from true
  GROUP BY b.beat_short, b.river_order
  ORDER BY b.river_order;

drop view public.view_in_season_dashb_2_count_reserv_by_beat;

CREATE OR REPLACE FUNCTION public.get_private_dashb_2_data()
 RETURNS TABLE(beat text, reservation_count integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'private', 'public'
AS $function$
  SELECT beat, reservation_count FROM private.view_in_season_dashb_2_count_reserv_by_beat;
$function$
;
GRANT EXECUTE ON FUNCTION public.get_private_dashb_2_data() TO authenticated, anon;

CREATE OR REPLACE VIEW private.view_in_season_dashb_4_freq_catchsize
AS WITH total_catch AS (
         SELECT COALESCE(crst.brown_trout_released, 0) + 
         	COALESCE(crst.brown_trout_retained, 0) + 
         	COALESCE(crst.grayling, 0) + 
         	COALESCE(crst.other_species, 0) + 
         	COALESCE(crst.rainbow_trout, 0) AS catchsize
           FROM public.catch_returns_staging_table crst
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

CREATE OR REPLACE FUNCTION public.get_private_dashb_4_data()
 RETURNS TABLE(catchsize integer, frequency integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'private', 'public'
AS $function$
  SELECT catchsize, frequency FROM private.view_in_season_dashb_4_freq_catchsize;
$function$
;
GRANT EXECUTE ON FUNCTION public.get_private_dashb_4_data() TO authenticated, anon;

drop view public.view_in_season_dashb_4_freq_catchsize;

CREATE OR REPLACE VIEW private.view_in_season_dashb_5_prop_grayling
AS WITH week_series AS (
         SELECT generate_series('2026-04-01'::date::timestamp with time zone, (( SELECT max(public.catch_returns_staging_table.catch_date) AS max
                   FROM public.catch_returns_staging_table))::timestamp with time zone, '7 days'::interval)::date AS week_start
        ), weekly_counts AS (
         SELECT ws.week_start,
            sum(COALESCE(crst.brown_trout_released, 0) + COALESCE(crst.brown_trout_retained, 0) + COALESCE(crst.grayling, 0)) AS total_caught,
            sum(COALESCE(crst.grayling, 0)) AS total_grayling
           FROM week_series ws
             LEFT JOIN public.catch_returns_staging_table crst ON crst.catch_date >= ws.week_start AND crst.catch_date < (ws.week_start + 7)
          GROUP BY ws.week_start
        )
 SELECT week_start AS season_week_start,
    total_caught,
    total_grayling,
    round(COALESCE(total_grayling::numeric / NULLIF(total_caught, 0)::numeric * 100::numeric, 0::numeric), 1) AS grayling_percentage
   FROM weekly_counts
  ORDER BY week_start;

CREATE OR REPLACE FUNCTION public.get_private_dashb_5_data()
 RETURNS TABLE(season_week_start date, total_caught integer, total_grayling integer, grayling_percentage numeric)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'private', 'public'
AS $function$
  SELECT season_week_start, total_caught, total_grayling, grayling_percentage FROM private.view_in_season_dashb_5_prop_grayling;
$function$
;
GRANT EXECUTE ON FUNCTION public.get_private_dashb_5_data() TO authenticated, anon;

drop view public.view_in_season_dashb_5_prop_grayling;