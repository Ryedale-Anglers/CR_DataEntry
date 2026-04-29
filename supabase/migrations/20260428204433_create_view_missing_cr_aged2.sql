CREATE OR REPLACE VIEW public.view_missing_cr_age_report2
AS 
WITH 
reservation_stats AS (
    SELECT 
        cr_name, 
        COUNT(*) AS total_reservations
    FROM view_reservations_confirmed_staging
    GROUP BY cr_name
),
return_stats AS (
    SELECT vrcs.cr_name,
        CURRENT_DATE - vrcs.date AS days_old,
        CASE
            WHEN crst.rod_name IS NOT NULL THEN 1
            ELSE 0
        END AS was_submitted
    FROM view_reservations_confirmed_staging vrcs
    LEFT JOIN catch_returns_staging_table crst 
        ON vrcs.cr_name = crst.rod_name 
        AND vrcs.date = crst.catch_date
    WHERE vrcs.date < CURRENT_DATE
)
SELECT m.member_name,
    res.total_reservations AS "Total Reservations", -- Added from the new CTE
    sum(rs.was_submitted) AS "Returns Submitted",
        count(
        CASE
            WHEN rs.was_submitted = 0 AND rs.days_old <= 7 THEN 1
            ELSE NULL::integer
        END) AS "1-7 Days",
    count(
        CASE
            WHEN rs.was_submitted = 0 AND rs.days_old > 7 AND rs.days_old <= 14 THEN 1
            ELSE NULL::integer
        END) AS "8-14 Days",
    count(
        CASE
            WHEN rs.was_submitted = 0 AND rs.days_old > 14 AND rs.days_old <= 21 THEN 1
            ELSE NULL::integer
        END) AS "15-21 Days",
    count(
        CASE
            WHEN rs.was_submitted = 0 AND rs.days_old > 21 AND rs.days_old <= 28 THEN 1
            ELSE NULL::integer
        END) AS "21-28 Days",
    count(
        CASE
            WHEN rs.was_submitted = 0 AND rs.days_old > 28 THEN 1
            ELSE NULL::integer
        END) AS "28+ Days",
    count(
        CASE
            WHEN rs.was_submitted = 0 THEN 1
            ELSE NULL::integer
        END) AS "Total Missing"
FROM members m
JOIN return_stats rs ON m.cr_name = rs.cr_name
LEFT JOIN reservation_stats res ON m.cr_name = res.cr_name -- Joined here
GROUP BY m.member_name, res.total_reservations
HAVING count(
        CASE
            WHEN rs.was_submitted = 0 THEN 1
            ELSE NULL::integer
        END) > 0
ORDER BY "Total Missing" DESC;