-- Report V5_5: count a guest return as the member's own return when it is the only
-- return for one of the member's reservations.
--
-- Rule (one rod on the river per reservation):
--  * Member returns (guest = false, dnf = false) count as before.
--  * A guest return counts only when the member has a reservation for that date and
--    beat (private.reservations_confirmed) and there is no member return for it.
--  * If that reservation has two or more guest returns, only the one with the largest
--    total catch (brown trout + trout killed + grayling + rainbow trout + other species)
--    counts. On a tie, the lowest id is used.
--  * Guest returns with no reservation (all seasons before 2026) stay excluded.
--
-- These are new _v5_5 views alongside the existing ones, so report V5_4 is unchanged
-- and both versions can be run and compared. Reservation-only views (sections 2.0,
-- 2.1/2.2, 2.3 reservations and 2.4) already include these reservations and are not copied.
-- Note: the 1.6.2 monthly views add brown_trout_killed to brown_trout, which already
-- includes it; that is copied unchanged so V5_4 and V5_5 differ only by the guest rule.

-- Catch returns counted under the V5_5 rule, one row per rod-day.
CREATE OR REPLACE VIEW private.view_catch_returns_v5_5 AS
SELECT c.id, c.member_name, c.catch_date, c.brown_trout, c.brown_trout_killed,
       c.grayling, c.rainbow_trout, c.other_species, c.guest, c.beats_id, c.dnf,
       false AS guest_substitute
FROM private.catch_returns c
WHERE c.guest IS FALSE AND c.dnf IS FALSE
UNION ALL
SELECT g.id, g.member_name, g.catch_date, g.brown_trout, g.brown_trout_killed,
       g.grayling, g.rainbow_trout, g.other_species, g.guest, g.beats_id, g.dnf,
       true AS guest_substitute
FROM (
    SELECT DISTINCT ON (c.member_name, c.catch_date, c.beats_id) c.*
    FROM private.catch_returns c
    WHERE c.guest IS TRUE
      AND c.dnf IS FALSE
      AND EXISTS (
            SELECT 1
            FROM private.reservations_confirmed rc
            JOIN private.members m ON m.id = rc.members_id
            WHERE m.cr_name   = c.member_name
              AND rc.date     = c.catch_date
              AND rc.beats_id = c.beats_id)
      AND NOT EXISTS (
            SELECT 1
            FROM private.catch_returns mc
            WHERE mc.guest IS FALSE
              AND mc.member_name = c.member_name
              AND mc.catch_date  = c.catch_date
              AND mc.beats_id    = c.beats_id)
    ORDER BY c.member_name, c.catch_date, c.beats_id,
             COALESCE(c.brown_trout, 0) + COALESCE(c.brown_trout_killed, 0) + COALESCE(c.grayling, 0)
               + COALESCE(c.rainbow_trout, 0) + COALESCE(c.other_species, 0) DESC,
             c.id
) g;

-- Same columns as private.view_troutseasondata, plus guest_substitute.
CREATE OR REPLACE VIEW private.view_troutseasondata_v5_5 AS
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
    c.beats_id,
    c.guest_substitute
   FROM private.view_catch_returns_v5_5 c
     JOIN private.beats b ON c.beats_id = b.id;

-- Same columns as private.view_base_catch, plus guest_substitute.
CREATE OR REPLACE VIEW private.view_base_catch_v5_5 AS
 SELECT b.river_order,
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
        END AS seasonalyear_int,
    c.guest_substitute
   FROM private.view_catch_returns_v5_5 c
     JOIN private.beats b ON c.beats_id = b.id;

-- Report views: unchanged copies that read view_troutseasondata_v5_5.
CREATE OR REPLACE VIEW private.report_1_2_stats_allspecies_bymonthbybeat2_v5_5 AS
 SELECT "Beat",
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
             LEFT JOIN private.view_troutseasondata_v5_5 vtsd ON vtsd.beat = b.beat AND vtsd.seasonal_year_int = (( SELECT year_param.target_year
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
           FROM private.view_troutseasondata_v5_5 v2
          WHERE v2.seasonal_year_int = (( SELECT year_param.target_year
                   FROM private.year_param
                 LIMIT 1))) "CombinedStats"
  ORDER BY "SortKey";

CREATE OR REPLACE VIEW private.report_1_4_freq_totalfishcaught_v5_5 AS
 SELECT total_fish_caught AS catchsize,
    count(*) AS frequency
   FROM private.view_troutseasondata_v5_5 vt
  WHERE seasonal_year_int = (( SELECT year_param.target_year
           FROM private.year_param
         LIMIT 1))
  GROUP BY total_fish_caught
  ORDER BY total_fish_caught;

CREATE OR REPLACE VIEW private.report_1_4_freq_browntrout_v5_5 AS
 SELECT brown_trout AS catchsize,
    count(*) AS frequency
   FROM private.view_troutseasondata_v5_5 vt
  WHERE seasonal_year_int = (( SELECT year_param.target_year
           FROM private.year_param
         LIMIT 1))
  GROUP BY brown_trout
  ORDER BY brown_trout;

CREATE OR REPLACE VIEW private.report_1_4_freq_grayling_v5_5 AS
 SELECT grayling AS catchsize,
    count(*) AS frequency
   FROM private.view_troutseasondata_v5_5 vt
  WHERE seasonal_year_int = (( SELECT year_param.target_year
           FROM private.year_param
         LIMIT 1))
  GROUP BY grayling
  ORDER BY grayling;

CREATE OR REPLACE VIEW private.report_1_5_upper_lower_all_v5_5 AS
 SELECT seasonal_year,
    round(avg(
        CASE
            WHEN upper_lower = 'Upper'::text THEN total_fish_caught
            ELSE NULL::integer
        END), 1) AS upper_avg,
    round(avg(
        CASE
            WHEN upper_lower = 'Lower'::text THEN total_fish_caught
            ELSE NULL::integer
        END), 1) AS lower_avg
   FROM private.view_troutseasondata_v5_5 vtsd
  WHERE seasonal_year !~~ 'Off%'::text
  GROUP BY seasonal_year
  ORDER BY seasonal_year;

CREATE OR REPLACE VIEW private.report_1_5_upper_lower_browntrout_v5_5 AS
 SELECT seasonal_year,
    round(avg(
        CASE
            WHEN upper_lower = 'Upper'::text THEN brown_trout
            ELSE NULL::integer
        END), 1) AS upper_avg,
    round(avg(
        CASE
            WHEN upper_lower = 'Lower'::text THEN brown_trout
            ELSE NULL::integer
        END), 1) AS lower_avg
   FROM private.view_troutseasondata_v5_5 vtsd
  WHERE seasonal_year !~~ 'Off%'::text
  GROUP BY seasonal_year
  ORDER BY seasonal_year;

CREATE OR REPLACE VIEW private.report_1_5_upper_lower_grayling_v5_5 AS
 SELECT seasonal_year,
    round(avg(
        CASE
            WHEN upper_lower = 'Upper'::text THEN grayling
            ELSE NULL::integer
        END), 1) AS upper_avg,
    round(avg(
        CASE
            WHEN upper_lower = 'Lower'::text THEN grayling
            ELSE NULL::integer
        END), 1) AS lower_avg
   FROM private.view_troutseasondata_v5_5 vtsd
  WHERE seasonal_year !~~ 'Off%'::text
  GROUP BY seasonal_year
  ORDER BY seasonal_year;

CREATE OR REPLACE VIEW private.report_1_6_tr_v_gr_ratio_v5_5 AS
 SELECT seasonal_year,
    sum(brown_trout) AS total_brown_trout,
    sum(grayling) AS total_grayling,
    round(sum(grayling)::numeric * 100.0 / NULLIF(sum(brown_trout) + sum(grayling), 0)::numeric, 1) AS grayling_percentage
   FROM private.view_troutseasondata_v5_5 vtsd
  WHERE seasonal_year !~~ 'Off%'::text
  GROUP BY seasonal_year
  ORDER BY seasonal_year;

CREATE OR REPLACE VIEW private.report_1_6_1_tr_v_gr_ratio_upper_lower_v5_5 AS
 SELECT seasonal_year,
    upper_lower,
    sum(brown_trout) AS total_brown_trout,
    sum(grayling) AS total_grayling,
    round(sum(grayling)::numeric * 100.0 / NULLIF(sum(brown_trout) + sum(grayling), 0)::numeric, 1) AS grayling_percentage
   FROM private.view_troutseasondata_v5_5 vtsd
  WHERE seasonal_year !~~ 'Off%'::text AND upper_lower !~~ 'Unk%'::text
  GROUP BY seasonal_year, upper_lower
  ORDER BY seasonal_year;

CREATE OR REPLACE VIEW private.report_1_6_2_tr_v_gr_ratio_historical_monthly_v5_5 AS
 SELECT sum(brown_trout + brown_trout_killed) AS total_brown_trout,
    sum(grayling) AS total_grayling,
    round(sum(grayling)::numeric * 100.0 / NULLIF(sum(brown_trout + brown_trout_killed) + sum(grayling), 0)::numeric, 1) AS grayling_percentage,
    seasonal_month
   FROM private.view_troutseasondata_v5_5 vt
  WHERE seasonal_year !~~ 'Off%'::text AND seasonal_year_int <> (( SELECT year_param.target_year
           FROM private.year_param
         LIMIT 1))
  GROUP BY seasonal_month
  ORDER BY (to_date(seasonal_month, 'Mon'::text));

CREATE OR REPLACE VIEW private.report_1_6_2_tr_v_gr_ratio_curr_year_monthly_v5_5 AS
 SELECT sum(brown_trout + brown_trout_killed) AS total_brown_trout,
    sum(grayling) AS total_grayling,
    round(sum(grayling)::numeric * 100.0 / NULLIF(sum(brown_trout + brown_trout_killed) + sum(grayling), 0)::numeric, 1) AS grayling_percentage,
    seasonal_month
   FROM private.view_troutseasondata_v5_5 vt
  WHERE seasonal_year_int = (( SELECT year_param.target_year
           FROM private.year_param
         LIMIT 1))
  GROUP BY seasonal_month
  ORDER BY (to_date(seasonal_month, 'Mon'::text));
