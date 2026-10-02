-- Reservation-based reports counted reservations more than once, and let some DNF
-- reservations through, because they re-joined private.catch_returns on date and
-- member only (no beat) and then filtered on dnf/guest row by row.
--
-- DNF returns and their reservations are now excluded when the season is rolled over
-- (20261002130000), so the final tables hold no DNF rows and these joins are redundant.
-- IMPORTANT: apply after private.rollover_season() has been re-run for 2026 with the new
-- functions, otherwise the 32 DNF reservations still in reservations_confirmed are counted.
--
-- Column lists and order are unchanged for every view below.

CREATE OR REPLACE VIEW private.view_reservations_confirmed AS
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
    rc.beats_id,
    rc.members_id,
    m.year_of_membership
FROM private.reservations_confirmed rc
JOIN private.members m ON rc.members_id = m.id
JOIN private.beats b ON rc.beats_id = b.id;

CREATE OR REPLACE VIEW private.report_2_3_num_days_fished_by_year_v2 AS
SELECT year,
       sum(record_count) AS total_count
FROM (
    SELECT vrc.seasonal_year_int AS year,
           count(vrc.id) AS record_count
    FROM private.view_reservations_confirmed vrc
    GROUP BY vrc.seasonal_year_int
    UNION ALL
    SELECT vt.seasonal_year_int AS year,
           count(*) AS record_count
    FROM private.view_troutseasondata vt
    WHERE vt.beats_id = 18
    GROUP BY vt.seasonal_year_int
) combined
WHERE year IS NOT NULL
GROUP BY year
ORDER BY year;

CREATE OR REPLACE VIEW private.report_2_0_num_days_fished_by_beat_v2 AS
SELECT b.beat_short AS beat,
    count(vrc.id) AS num_days_fished
FROM private.beats b
CROSS JOIN ( SELECT year_param.target_year
             FROM private.year_param
             LIMIT 1) yp
LEFT JOIN private.view_reservations_confirmed vrc
       ON vrc.beats_id = b.id
      AND vrc.date >= make_date(yp.target_year, 4, 1)
      AND vrc.date <= make_date(yp.target_year, 9, 30)
WHERE b.id <> 18
GROUP BY b.beat_short, b.river_order
ORDER BY b.river_order;

CREATE OR REPLACE VIEW private.report_2_1_num_days_fished_by_beat_by_month_v2 AS
SELECT b.beat_short,
    b.river_order,
    vrc.seasonal_month,
    count(vrc.id) AS num_days_fished
FROM private.beats b
CROSS JOIN ( SELECT year_param.target_year
             FROM private.year_param
             LIMIT 1) yp
LEFT JOIN private.view_reservations_confirmed vrc
       ON vrc.beats_id = b.id
      AND vrc.date >= make_date(yp.target_year, 4, 1)
      AND vrc.date <= make_date(yp.target_year, 9, 30)
WHERE b.id <> 18
GROUP BY b.beat_short, vrc.seasonal_month, b.river_order
ORDER BY b.river_order;
