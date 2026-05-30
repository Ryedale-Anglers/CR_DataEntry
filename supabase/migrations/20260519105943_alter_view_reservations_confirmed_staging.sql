-- adding rcs.name to be able to see 'synthetic' records
CREATE OR REPLACE VIEW public.view_reservations_confirmed_staging AS 
SELECT rcs.date,
    rcs.cr_name,
    rb.beat_id,
    bt.beat,
    bt.river_order,
    rcs.id,
    rcs.name
   FROM reservations_confirmed_staging rcs
     JOIN reservation_beats rb ON rb.beat = rcs.resource
     JOIN beats bt ON rb.beat_id = bt.id
  ORDER BY rcs.date;

-- adding rc.beats_id
CREATE OR REPLACE VIEW public.view_reservations_confirmed AS
SELECT rc.id,
    rc.date,
    m.cr_name,
    b.beat,
    b.beat_short,
    b.river_order,
    to_char(rc.date::timestamp with time zone, 'Mon'::text) AS seasonal_month,
        CASE
            WHEN to_char(rc.date::timestamp with time zone, 'MM'::text) >= '04'::text AND to_char(rc.date::timestamp with time zone, 'MM'::text) <= '09'::text THEN to_char(rc.date::timestamp with time zone, 'YYYY'::text)
            ELSE 'Off-Season'::text
        END AS seasonal_year,
        CASE
            WHEN to_char(rc.date::timestamp with time zone, 'MM'::text) >= '04'::text AND to_char(rc.date::timestamp with time zone, 'MM'::text) <= '09'::text THEN to_char(rc.date::timestamp with time zone, 'YYYY'::text)::integer
            ELSE NULL::integer
        END AS seasonal_year_int,
        rc.beats_id
   FROM reservations_confirmed rc
     JOIN private.members m ON rc.members_id = m.id
     JOIN beats b ON rc.beats_id = b.id
     LEFT JOIN catch_returns_staging_table crst ON rc.date = crst.catch_date AND m.cr_name = crst.rod_name AND crst.guest IS DISTINCT FROM true
  WHERE crst.dnf IS DISTINCT FROM true;

-- revised report_2_0 to use view_reservations_confirmed instead of catch_returns
CREATE OR REPLACE VIEW public.report_2_0_num_days_fished_by_beat_v2 AS 
SELECT b.beat_short AS beat,
    count(vrc.id) AS num_days_fished
   FROM beats b
     CROSS JOIN ( SELECT year_param.target_year
           FROM year_param
         LIMIT 1) yp
     LEFT JOIN view_reservations_confirmed vrc 
     	ON vrc.beats_id = b.id 
     		AND vrc.date >= make_date(yp.target_year, 4, 1) 
     		AND vrc.date <= make_date(yp.target_year, 9, 30)
     LEFT JOIN catch_returns_staging_table crst 
     	ON vrc.date = crst.catch_date AND vrc.cr_name = crst.rod_name
  WHERE b.id <> 18 AND crst.dnf IS DISTINCT FROM true and crst.guest is distinct from true
  GROUP BY b.beat_short, b.river_order
  ORDER BY b.river_order;

create view report_1_6_2_tr_v_gr_ratio_historical_monthly as
SELECT 
    sum((vt.brown_trout + vt.brown_trout_killed)) as total_brown_trout,
    sum(vt.grayling) as total_grayling,
    round(sum(grayling)::numeric * 100.0 / NULLIF(sum((vt.brown_trout + vt.brown_trout_killed))
        + sum(grayling), 0)::numeric, 1) AS grayling_percentage,
    vt.seasonal_month
FROM view_troutseasondata vt
WHERE seasonal_year !~~ 'Off%'::text and seasonal_year_int <> (SELECT year_param.target_year FROM year_param LIMIT 1)
GROUP BY vt.seasonal_month
ORDER BY TO_DATE(vt.seasonal_month, 'Mon');
		
create view report_1_6_2_tr_v_gr_ratio_curr_year_monthly as
SELECT 
    sum((vt.brown_trout + vt.brown_trout_killed)) as total_brown_trout,
    sum(vt.grayling) as total_grayling,
    round(sum(grayling)::numeric * 100.0 / NULLIF(sum((vt.brown_trout + vt.brown_trout_killed))
        + sum(grayling), 0)::numeric, 1) AS grayling_percentage,
    vt.seasonal_month
FROM view_troutseasondata vt
WHERE seasonal_year_int = (SELECT year_param.target_year FROM year_param LIMIT 1)
GROUP BY vt.seasonal_month
ORDER BY TO_DATE(vt.seasonal_month, 'Mon');	

CREATE OR REPLACE VIEW public.report_2_1_num_days_fished_by_beat_by_month_v2 as
SELECT b.beat_short AS beat, b.river_order, vrc.seasonal_month,
    count(vrc.id) AS num_days_fished
   FROM beats b
     CROSS JOIN ( SELECT year_param.target_year
           FROM year_param
         LIMIT 1) yp
     LEFT JOIN view_reservations_confirmed vrc ON vrc.beats_id = b.id AND vrc.date >= make_date(yp.target_year, 4, 1) AND vrc.date <= make_date(yp.target_year, 9, 30)
     LEFT JOIN catch_returns_staging_table crst ON vrc.date = crst.catch_date AND vrc.cr_name = crst.rod_name
  WHERE b.id <> 18 AND crst.dnf IS DISTINCT FROM true AND crst.guest IS DISTINCT FROM true
  GROUP BY b.beat_short, vrc.seasonal_month, b.river_order
  ORDER BY b.river_order;

-- adding beats_id column to this view
CREATE OR REPLACE VIEW public.view_troutseasondata
AS SELECT c.id,
    c.member_name,
    COALESCE(c.brown_trout, 0) + COALESCE(c.brown_trout_killed, 0) AS brown_trout,
    c.brown_trout_killed,
    c.rainbow_trout,
    c.grayling,
    c.other_species,
    to_char(c.catch_date::timestamp with time zone, 'Mon'::text) AS seasonal_month,
        CASE
            WHEN to_char(c.catch_date::timestamp with time zone, 'MM'::text) >= '04'::text AND to_char(c.catch_date::timestamp with time zone, 'MM'::text) <= '09'::text THEN to_char(c.catch_date::timestamp with time zone, 'YYYY'::text)
            ELSE 'Off-Season'::text
        END AS seasonal_year,
        CASE
            WHEN to_char(c.catch_date::timestamp with time zone, 'MM'::text) >= '04'::text AND to_char(c.catch_date::timestamp with time zone, 'MM'::text) <= '09'::text THEN to_char(c.catch_date::timestamp with time zone, 'YYYY'::text)::integer
            ELSE NULL::integer
        END AS seasonal_year_int,
    c.catch_date,
    b.beat,
    b.beat_short,
    b.river_order,
    b.upper_lower,
    c.guest,
    COALESCE(c.brown_trout, 0) + COALESCE(c.brown_trout_killed, 0) + COALESCE(c.grayling, 0) 
    	+ COALESCE(c.rainbow_trout, 0) + COALESCE(c.other_species, 0) AS total_fish_caught,
    c.beats_id
   FROM catch_returns c
     JOIN beats b ON c.beats_id = b.id
  WHERE c.guest IS FALSE;