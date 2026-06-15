drop view private.view_missing_cr_age_report5;

create view private.view_missing_cr_age_report5 as 
WITH reservation_stats AS (
    SELECT 
        vrcs.cr_name,
        COUNT(*) AS total_reservations
    FROM view_reservations_confirmed_staging vrcs
    LEFT JOIN catch_returns_staging_table crst 
        ON vrcs.date = crst.catch_date 
       AND vrcs.cr_name = crst.rod_name 
       AND vrcs.beat = crst.beat
    WHERE crst.guest IS DISTINCT FROM true 
      AND crst.dnf IS DISTINCT FROM true
      -- Only look at reservations from yesterday or older
      AND vrcs.date < CURRENT_DATE
    GROUP BY vrcs.cr_name
), 
catch_returns_stats AS (
    SELECT 
        vrcs.cr_name,
        SUM(CASE WHEN crst.rod_name IS NOT NULL THEN 1 ELSE 0 END) AS total_submitted,
        -- Aging buckets now perfectly align with the data grain
        COUNT(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) BETWEEN 1 AND 7) AS "1-7 Days",
        COUNT(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) BETWEEN 8 AND 14) AS "8-14 Days",
        COUNT(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) BETWEEN 15 AND 21) AS "15-21 Days",
        COUNT(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) BETWEEN 22 AND 28) AS "22-28 Days",
        COUNT(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) > 28) AS "28+ Days"
    FROM view_reservations_confirmed_staging vrcs
    LEFT JOIN catch_returns_staging_table crst 
        ON vrcs.date = crst.catch_date 
       AND vrcs.cr_name = crst.rod_name 
       AND vrcs.beat = crst.beat
    WHERE crst.guest IS DISTINCT FROM true 
      AND crst.dnf IS DISTINCT FROM true
      -- Only look at reservations from yesterday or older
      AND vrcs.date < CURRENT_DATE
    GROUP BY vrcs.cr_name
)
SELECT 
    m.member_name,
    COALESCE(res.total_reservations, 0::bigint) AS "Reservations",
    COALESCE(crs.total_submitted, 0::bigint) AS "Catch Returns",
    (COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint)) AS "CRs Due",
    COALESCE(ROUND(crs.total_submitted::numeric / NULLIF(res.total_reservations, 0)::numeric * 100::numeric, 1), 0::numeric) AS pct_compliance,
    COALESCE(crs."1-7 Days", 0::bigint) AS "1-7 Days",
    COALESCE(crs."8-14 Days", 0::bigint) AS "8-14 Days",
    COALESCE(crs."15-21 Days", 0::bigint) AS "15-21 Days",
    COALESCE(crs."22-28 Days", 0::bigint) AS "22-28 Days",
    COALESCE(crs."28+ Days", 0::bigint) AS "28+ Days"
FROM view_member_names m
LEFT JOIN reservation_stats res ON m.cr_name = res.cr_name
LEFT JOIN catch_returns_stats crs ON m.cr_name = crs.cr_name
WHERE (COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint)) > 0
ORDER BY "CRs Due" DESC;