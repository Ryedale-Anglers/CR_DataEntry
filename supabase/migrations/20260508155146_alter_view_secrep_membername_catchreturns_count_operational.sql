drop view if exists public.view_secrep_membername_catchreturns_count_operational;
create or replace view public.view_secrep_membername_catchreturns_count_operational as
WITH filtered_data AS (
    SELECT 
        vrcs.cr_name,
        -- We keep the catch_date (or id) from the catch table 
        -- to know if a return actually exists
        crst.catch_date AS has_return 
    FROM reservations_confirmed_staging vrcs
    LEFT JOIN catch_returns_staging_table crst 
        ON vrcs.date = crst.catch_date 
        AND vrcs.cr_name = crst.rod_name
    -- Exclude where they explicitly said "Did Not Fish"
    WHERE crst.dnf IS DISTINCT FROM true
)
SELECT 
    cr_name, 
    COUNT(*) AS reservations_count,
    -- COUNT(column) only counts non-null values. 
    -- Since it's a LEFT JOIN, has_return is NULL if no return was filed.
    COUNT(has_return) AS returns_count,
    -- Optional: Calculate the variance (missing returns)
    (COUNT(*) - COUNT(has_return)) AS variance
FROM filtered_data
GROUP BY cr_name
ORDER BY reservations_count DESC;