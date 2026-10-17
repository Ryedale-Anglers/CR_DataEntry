-- 'Fishing Hut & Railway Bridge' (beats.id = 4) has two booking resources,
-- '17. Fishing Hut' and '18. Railway Bridge'. A member who books both on the
-- same day has booked one beat - catch returns are keyed by beat - but
-- private.view_reservations_confirmed_staging returned one row per resource,
-- so every report view built on it counted two reservations (and, with no
-- catch return, two returns due). Seen in the in-season compliance report:
-- 8 reservations shown for a member with 7 beat bookings.
--
-- 1. The base view now returns one row per date, member and beat. Where two
--    resources collapse into one row, a real booking is kept in preference to
--    a Synthetic placeholder. Rows with no matched member (cr_name NULL) are
--    keyed on the booking name instead, so two different unmatched bookers
--    are never merged. Columns are unchanged, so dependent views are
--    unaffected apart from the corrected counts.
--
-- 2. view_secrep_membername_catchreturns_count_operational read the staging
--    table directly with its own resource join; it now reads the base view so
--    it gets the same one-row-per-beat counting. Otherwise unchanged.
--
-- view_reservations_confirmed_staging_anon (public dashboard) is deliberately
-- left per resource: it has no member column, so it can't tell one member's
-- double booking from two members each booking one resource.

CREATE OR REPLACE VIEW private.view_reservations_confirmed_staging AS
SELECT DISTINCT ON (rcs.date, COALESCE(rcs.cr_name, 'unmatched: ' || rcs.name), rb.beat_id)
    rcs.date,
    rcs.cr_name,
    rb.beat_id,
    bt.beat,
    bt.river_order,
    rcs.id,
    rcs.name
FROM private.reservations_confirmed_staging rcs
JOIN private.reservation_beats rb ON rb.beat = rcs.resource
JOIN private.beats bt ON rb.beat_id = bt.id
ORDER BY rcs.date,
         COALESCE(rcs.cr_name, 'unmatched: ' || rcs.name),
         rb.beat_id,
         (rcs.name = 'Synthetic'),
         rcs.id;

CREATE OR REPLACE VIEW private.view_secrep_membername_catchreturns_count_operational AS
WITH filtered_data AS (
    SELECT vrcs.cr_name,
           crst.catch_date AS has_return
    FROM private.view_reservations_confirmed_staging vrcs
    CROSS JOIN (SELECT year_param.target_year FROM private.year_param WHERE year_param.id = 1) yp
    LEFT JOIN private.catch_returns_staging_table crst
           ON vrcs.date = crst.catch_date
          AND vrcs.cr_name = crst.rod_name
          AND vrcs.beat = crst.beat
          AND crst.guest = false
    WHERE crst.dnf IS DISTINCT FROM true
      AND vrcs.date >= make_date(yp.target_year, 4, 1)
      AND vrcs.date <= make_date(yp.target_year, 9, 30)
)
SELECT cr_name,
       count(*) AS reservations_count,
       count(has_return) AS returns_count,
       count(*) - count(has_return) AS variance
FROM filtered_data
GROUP BY cr_name
ORDER BY count(*) DESC;
