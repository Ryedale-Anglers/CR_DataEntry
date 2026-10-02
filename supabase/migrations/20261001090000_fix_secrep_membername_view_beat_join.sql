-- private.view_secrep_membername_catchreturns_count_operational joined
-- reservations to catch returns on (date, cr_name) only - never beat. A
-- member with more than one reservation on the same date (routine: both the
-- "fished a different beat" and "no reservation" flows create same-day
-- Synthetic reservations) gets every one of their catch returns for that
-- date matched against every one of their reservations for that date,
-- fanning out N reservations x M catch returns instead of pairing them 1:1
-- by beat. Confirmed against real data: RIEVAULX had 2 reservations and 2
-- catch returns on the same date (different beats each), reported as 4/4.
--
-- Also excludes guest catch returns from the match - a guest's catch isn't
-- evidence the member submitted their own.
CREATE OR REPLACE VIEW private.view_secrep_membername_catchreturns_count_operational
AS WITH filtered_data AS (
         SELECT vrcs.cr_name,
            crst.catch_date AS has_return
           FROM private.reservations_confirmed_staging vrcs
             INNER JOIN private.reservation_beats rb ON rb.beat = vrcs.resource
             INNER JOIN private.beats b ON b.id = rb.beat_id
             LEFT JOIN private.catch_returns_staging_table crst
                ON vrcs.date = crst.catch_date
               AND vrcs.cr_name = crst.rod_name
               AND b.beat = crst.beat
               AND crst.guest = false
          WHERE crst.dnf IS DISTINCT FROM true
        )
 SELECT cr_name,
    count(*) AS reservations_count,
    count(has_return) AS returns_count,
    count(*) - count(has_return) AS variance
   FROM filtered_data
  GROUP BY cr_name
  ORDER BY (count(*)) DESC;
