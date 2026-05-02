drop view if exists public.view_missing_cr_age_report2;

create or replace view public.view_missing_cr_age_report2 as
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
SELECT m.member_name,
    res.total_reservations AS "Total Reservations",
    sum(rs.was_submitted) AS "Returns Submitted",
    count(
        CASE WHEN rs.was_submitted = 0 AND rs.days_old <= 7 THEN 1 ELSE NULL END
    ) AS "1-7 Days",
    count(
        CASE WHEN rs.was_submitted = 0 AND rs.days_old > 7 AND rs.days_old <= 14 THEN 1 ELSE NULL END
    ) AS "8-14 Days",
    count(
        CASE WHEN rs.was_submitted = 0 AND rs.days_old > 14 AND rs.days_old <= 21 THEN 1 ELSE NULL END
    ) AS "15-21 Days",
    count(
        CASE WHEN rs.was_submitted = 0 AND rs.days_old > 21 AND rs.days_old <= 28 THEN 1 ELSE NULL END
    ) AS "21-28 Days",
    count(
        CASE WHEN rs.was_submitted = 0 AND rs.days_old > 28 THEN 1 ELSE NULL END
    ) AS "28+ Days",
    count(
        CASE WHEN rs.was_submitted = 0 THEN 1 ELSE NULL END
    ) AS "Total Missing"
FROM members m
JOIN return_stats rs ON m.cr_name = rs.cr_name
LEFT JOIN reservation_stats res ON m.cr_name = res.cr_name
GROUP BY m.member_name, res.total_reservations
HAVING count(
    CASE WHEN rs.was_submitted = 0 THEN 1 ELSE NULL END
) > 0
ORDER BY count(
    CASE WHEN rs.was_submitted = 0 THEN 1 ELSE NULL END
) DESC;