CREATE OR REPLACE VIEW public.report_2_0_num_days_fished_by_beat_v2
AS SELECT b.beat_short AS beat,
    count(vrc.id) AS num_days_fished
   FROM beats b
     CROSS JOIN ( SELECT year_param.target_year
           FROM year_param
         LIMIT 1) yp
     LEFT JOIN view_reservations_confirmed vrc ON vrc.beats_id = b.id AND vrc.date >= make_date(yp.target_year, 4, 1) AND vrc.date <= make_date(yp.target_year, 9, 30)
     LEFT JOIN catch_returns cr ON vrc.date = cr.catch_date AND vrc.cr_name = cr.member_name
  WHERE b.id <> 18 AND cr.dnf IS DISTINCT FROM true AND cr.guest IS DISTINCT FROM true
  GROUP BY b.beat_short, b.river_order
  ORDER BY b.river_order;

Drop view public.report_2_1_num_days_fished_by_beat_by_month_v2;
CREATE OR REPLACE VIEW public.report_2_1_num_days_fished_by_beat_by_month_v2
AS SELECT b.beat_short,
    b.river_order,
    vrc.seasonal_month,
    count(vrc.id) AS num_days_fished
   FROM beats b
     CROSS JOIN ( SELECT year_param.target_year
           FROM year_param
         LIMIT 1) yp
     LEFT JOIN view_reservations_confirmed vrc ON vrc.beats_id = b.id AND vrc.date >= make_date(yp.target_year, 4, 1) AND vrc.date <= make_date(yp.target_year, 9, 30)
     LEFT JOIN catch_returns cr ON vrc.date = cr.catch_date AND vrc.cr_name = cr.member_name
  WHERE b.id <> 18 AND cr.dnf IS DISTINCT FROM true AND cr.guest IS DISTINCT FROM true
  GROUP BY b.beat_short, vrc.seasonal_month, b.river_order
  ORDER BY b.river_order;

CREATE OR REPLACE VIEW public.view_reservations_confirmed
AS SELECT rc.id,
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
    rc.beats_id,
    rc.members_id,
    m.year_of_membership
   FROM reservations_confirmed rc
     JOIN private.members m ON rc.members_id = m.id
     JOIN beats b ON rc.beats_id = b.id
     LEFT JOIN catch_returns_staging_table crst ON rc.date = crst.catch_date AND m.cr_name = crst.rod_name AND crst.guest IS DISTINCT FROM true
  WHERE crst.dnf IS DISTINCT FROM true;

CREATE OR REPLACE VIEW public.view_troutseasondata AS 
SELECT c.id,
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
    COALESCE(c.brown_trout, 0) + COALESCE(c.brown_trout_killed, 0) + COALESCE(c.grayling, 0) + COALESCE(c.rainbow_trout, 0) + COALESCE(c.other_species, 0) AS total_fish_caught,
    c.beats_id
   FROM catch_returns c
     JOIN beats b ON c.beats_id = b.id
  WHERE c.guest IS false and c.dnf is false;

  create view report_2_3_num_days_fished_by_year_v2 as
SELECT
    year,
    SUM(record_count) AS total_count
FROM (
    SELECT vrc.seasonal_year_int AS year, COUNT(vrc.id) AS record_count
    FROM view_reservations_confirmed vrc
    LEFT JOIN view_troutseasondata vt
        ON vt.catch_date = vrc.date
        AND vt.member_name = vrc.cr_name
        AND vt.seasonal_year_int = vrc.year_of_membership
    GROUP BY vrc.seasonal_year_int

    UNION ALL

    SELECT vt.seasonal_year_int AS year, COUNT(*) AS record_count
    FROM view_troutseasondata vt
    WHERE vt.beats_id = 18
    GROUP BY vt.seasonal_year_int
) combined
GROUP BY year
ORDER BY year

  