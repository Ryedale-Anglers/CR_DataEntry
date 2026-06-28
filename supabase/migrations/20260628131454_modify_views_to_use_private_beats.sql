CREATE OR REPLACE VIEW private.view_troutseasondata
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
    COALESCE(c.brown_trout, 0) + COALESCE(c.brown_trout_killed, 0) + COALESCE(c.grayling, 0) + COALESCE(c.rainbow_trout, 0) + COALESCE(c.other_species, 0) AS total_fish_caught,
    c.beats_id
   FROM private.catch_returns c
     JOIN private.beats b ON c.beats_id = b.id
  WHERE c.guest IS FALSE AND c.dnf IS FALSE;

CREATE OR REPLACE VIEW private.view_reservations_confirmed
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
   FROM private.reservations_confirmed rc
     JOIN private.members m ON rc.members_id = m.id
     JOIN private.beats b ON rc.beats_id = b.id
     LEFT JOIN private.catch_returns cr ON rc.date = cr.catch_date AND m.cr_name = cr.member_name AND cr.guest IS DISTINCT FROM true
  WHERE cr.dnf IS DISTINCT FROM true;

-- private.report_2_0_num_days_fished_by_beat_v2 source

CREATE OR REPLACE VIEW private.report_2_0_num_days_fished_by_beat_v2
AS SELECT b.beat_short AS beat,
    count(vrc.id) AS num_days_fished
   FROM private.beats b
     CROSS JOIN ( SELECT target_year
           FROM private.year_param
         LIMIT 1) yp
     LEFT JOIN private.view_reservations_confirmed vrc ON vrc.beats_id = b.id AND vrc.date >= make_date(yp.target_year, 4, 1) AND vrc.date <= make_date(yp.target_year, 9, 30)
     LEFT JOIN private.catch_returns cr ON vrc.date = cr.catch_date AND vrc.cr_name = cr.member_name
  WHERE b.id <> 18 AND cr.dnf IS DISTINCT FROM true AND cr.guest IS DISTINCT FROM true
  GROUP BY b.beat_short, b.river_order
  ORDER BY b.river_order;

CREATE OR REPLACE VIEW private.view_base_catch
AS SELECT b.river_order,
    b.beat,
    b.beat_short,
    c.catch_date,
    COALESCE(c.brown_trout, 0) + COALESCE(c.brown_trout_killed, 0) AS browntrout,
    COALESCE(c.grayling, 0) AS grayling,
    COALESCE(c.brown_trout, 0) + COALESCE(c.brown_trout_killed, 0) + COALESCE(c.grayling, 0) + COALESCE(c.rainbow_trout, 0) + COALESCE(c.other_species, 0) AS totalcaught,
    c.guest,
        CASE
            WHEN to_char(c.catch_date::timestamp with time zone, 'MM'::text) >= '04'::text AND to_char(c.catch_date::timestamp with time zone, 'MM'::text) <= '09'::text THEN to_char(c.catch_date::timestamp with time zone, 'YYYY'::text)
            ELSE 'Off-Season'::text
        END AS seasonalyear,
        CASE
            WHEN to_char(c.catch_date::timestamp with time zone, 'MM'::text) >= '04'::text AND to_char(c.catch_date::timestamp with time zone, 'MM'::text) <= '09'::text THEN to_char(c.catch_date::timestamp with time zone, 'YYYY'::text)::integer
            ELSE NULL::integer
        END AS seasonalyear_int
   FROM private.catch_returns c
     JOIN private.beats b ON c.beats_id = b.id
  WHERE c.guest IS DISTINCT FROM true AND c.dnf IS DISTINCT FROM true;

CREATE OR REPLACE VIEW private.report_2_1_num_days_fished_by_beat_by_month_v2
AS SELECT b.beat_short,
    b.river_order,
    vrc.seasonal_month,
    count(vrc.id) AS num_days_fished
   FROM private.beats b
     CROSS JOIN ( SELECT target_year
           FROM private.year_param
         LIMIT 1) yp
     LEFT JOIN private.view_reservations_confirmed vrc ON vrc.beats_id = b.id AND vrc.date >= make_date(yp.target_year, 4, 1) AND vrc.date <= make_date(yp.target_year, 9, 30)
     LEFT JOIN private.catch_returns cr ON vrc.date = cr.catch_date AND vrc.cr_name = cr.member_name
  WHERE b.id <> 18 AND cr.dnf IS DISTINCT FROM true AND cr.guest IS DISTINCT FROM true
  GROUP BY b.beat_short, vrc.seasonal_month, b.river_order
  ORDER BY b.river_order;

-- private.report_1_2_stats_allspecies_bymonthbybeat2 source

CREATE OR REPLACE VIEW private.report_1_2_stats_allspecies_bymonthbybeat2
AS SELECT "Beat",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sept"
   FROM ( SELECT b.river_order AS "SortKey",
            b.beat AS "Beat",
            round(avg(
                CASE
                    WHEN vtsd.seasonal_month ~~ 'Apr%'::text THEN vtsd.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Apr",
            round(avg(
                CASE
                    WHEN vtsd.seasonal_month ~~ 'May%'::text THEN vtsd.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "May",
            round(avg(
                CASE
                    WHEN vtsd.seasonal_month ~~ 'Jun%'::text THEN vtsd.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Jun",
            round(avg(
                CASE
                    WHEN vtsd.seasonal_month ~~ 'Jul%'::text THEN vtsd.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Jul",
            round(avg(
                CASE
                    WHEN vtsd.seasonal_month ~~ 'Aug%'::text THEN vtsd.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Aug",
            round(avg(
                CASE
                    WHEN vtsd.seasonal_month ~~ 'Sep%'::text THEN vtsd.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Sept"
           FROM private.beats b
             LEFT JOIN private.view_troutseasondata vtsd ON vtsd.beat = b.beat AND vtsd.seasonal_year_int = (( SELECT year_param.target_year
                   FROM private.year_param
                 LIMIT 1))
          WHERE b.beat !~~ '%Not Recorded%'::text
          GROUP BY b.river_order, b.beat
        UNION ALL
         SELECT 'z'::text AS "SortKey",
            'Grand Total (Avg)'::text AS "Beat",
            round(avg(
                CASE
                    WHEN v2.seasonal_month ~~ 'Apr%'::text THEN v2.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Apr",
            round(avg(
                CASE
                    WHEN v2.seasonal_month ~~ 'May%'::text THEN v2.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "May",
            round(avg(
                CASE
                    WHEN v2.seasonal_month ~~ 'Jun%'::text THEN v2.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Jun",
            round(avg(
                CASE
                    WHEN v2.seasonal_month ~~ 'Jul%'::text THEN v2.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Jul",
            round(avg(
                CASE
                    WHEN v2.seasonal_month ~~ 'Aug%'::text THEN v2.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Aug",
            round(avg(
                CASE
                    WHEN v2.seasonal_month ~~ 'Sep%'::text THEN v2.total_fish_caught
                    ELSE NULL::integer
                END), 1) AS "Sept"
           FROM private.view_troutseasondata v2
          WHERE v2.seasonal_year_int = (( SELECT year_param.target_year
                   FROM private.year_param
                 LIMIT 1))) "CombinedStats"
  ORDER BY "SortKey";

CREATE OR REPLACE VIEW private.view_reservations_confirmed_staging
AS SELECT rcs.date,
    rcs.cr_name,
    rb.beat_id,
    bt.beat,
    bt.river_order,
    rcs.id,
    rcs.name
   FROM private.reservations_confirmed_staging rcs
     JOIN private.reservation_beats rb ON rb.beat = rcs.resource
     JOIN private.beats bt ON rb.beat_id = bt.id
  ORDER BY rcs.date;

CREATE OR REPLACE VIEW private.view_in_season_dashb_2_count_reserv_by_beat
AS SELECT b.beat_short AS beat,
    count(DISTINCT vrcs.date) AS reservation_count
   FROM private.beats b
     LEFT JOIN private.view_reservations_confirmed_staging vrcs 
     	ON vrcs.beat_id = b.id AND vrcs.date >= make_date(EXTRACT(year FROM CURRENT_DATE)::integer, 4, 1) 
     		AND vrcs.date <= make_date(EXTRACT(year FROM CURRENT_DATE)::integer, 9, 30)
     LEFT JOIN private.catch_returns_staging_table crst 
     	ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name AND vrcs.beat = crst.beat
  WHERE b.id <> 18 AND crst.dnf IS DISTINCT FROM true AND crst.guest IS DISTINCT FROM true
  GROUP BY b.beat_short, b.river_order
  ORDER BY b.river_order;

drop table public.beats;
drop table public.reservation_beats;

