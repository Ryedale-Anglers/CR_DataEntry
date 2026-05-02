drop view if exists public.view_secrep_membername_catchreturns_count_operational;

create or replace view public.view_secrep_membername_catchreturns_count_operational as 
WITH reservation_stats AS (
    SELECT vrcs.cr_name,
        count(*) AS total_reservations
    FROM view_reservations_confirmed_staging vrcs
    WHERE vrcs.date < CURRENT_DATE
      AND NOT EXISTS (
          SELECT 1
          FROM catch_returns_staging_table disqualified
          WHERE disqualified.catch_date = vrcs.date
            AND disqualified.rod_name = vrcs.cr_name
            AND (disqualified.dnf = true OR disqualified.guest = true)
      )
    GROUP BY vrcs.cr_name
), return_stats AS (
    SELECT vrcs.cr_name,
        CURRENT_DATE - vrcs.date AS days_old,
        CASE
            WHEN crst.rod_name IS NOT NULL THEN 1
            ELSE 0
        END AS was_submitted
    FROM view_reservations_confirmed_staging vrcs
    LEFT JOIN (
        SELECT *,
            ROW_NUMBER() OVER (
                PARTITION BY catch_date, rod_name
                ORDER BY "timestamp" DESC
            ) AS rn
        FROM catch_returns_staging_table
        WHERE dnf = false
          AND guest = false
    ) crst ON vrcs.cr_name = crst.rod_name
          AND vrcs.date = crst.catch_date
          AND crst.rn = 1
    WHERE vrcs.date < CURRENT_DATE
      AND NOT EXISTS (
          SELECT 1
          FROM catch_returns_staging_table disqualified
          WHERE disqualified.catch_date = vrcs.date
            AND disqualified.rod_name = vrcs.cr_name
            AND (disqualified.dnf = true OR disqualified.guest = true)
      )
)
SELECT m.cr_name,
    COALESCE(res.total_reservations, 0) AS "Total Reservations",
    COALESCE(sum(rs.was_submitted), 0) AS "Returns Submitted",
    -- Wrapping the subtraction in COALESCE ensures Variance isn't NULL either
    COALESCE(res.total_reservations, 0) - COALESCE(sum(rs.was_submitted), 0) as Variance
    FROM members m
    LEFT JOIN reservation_stats res ON m.cr_name = res.cr_name
    LEFT JOIN return_stats rs ON m.cr_name = rs.cr_name
GROUP BY m.cr_name, res.total_reservations
ORDER BY "Total Reservations" desc , m.cr_name ASC; -- Used the alias here to keep the 0s sorted correctly