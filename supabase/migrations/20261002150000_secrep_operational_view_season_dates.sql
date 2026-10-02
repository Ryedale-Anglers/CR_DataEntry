-- view_secrep_membername_catchreturns_count_operational (used by the club secretary's
-- in-season compliance report) had no date filter, so a reservation outside the
-- season (e.g. CHARTLEY, 2026-10-02) was counted and shown as an outstanding catch return.
-- Restrict it to the target year's season, 1 April to 30 September inclusive.
-- Otherwise unchanged: same columns, same DNF exclusion.
CREATE OR REPLACE VIEW private.view_secrep_membername_catchreturns_count_operational AS
WITH filtered_data AS (
    SELECT vrcs.cr_name,
           crst.catch_date AS has_return
    FROM private.reservations_confirmed_staging vrcs
    JOIN private.reservation_beats rb ON rb.beat = vrcs.resource
    JOIN private.beats b ON b.id = rb.beat_id
    CROSS JOIN (SELECT target_year FROM private.year_param WHERE id = 1) yp
    LEFT JOIN private.catch_returns_staging_table crst
           ON vrcs.date = crst.catch_date
          AND vrcs.cr_name = crst.rod_name
          AND b.beat = crst.beat
          AND crst.guest = false
    WHERE crst.dnf IS DISTINCT FROM true
      AND vrcs.date BETWEEN make_date(yp.target_year, 4, 1) AND make_date(yp.target_year, 9, 30)
)
SELECT cr_name,
       count(*) AS reservations_count,
       count(has_return) AS returns_count,
       count(*) - count(has_return) AS variance
FROM filtered_data
GROUP BY cr_name
ORDER BY (count(*)) DESC;
