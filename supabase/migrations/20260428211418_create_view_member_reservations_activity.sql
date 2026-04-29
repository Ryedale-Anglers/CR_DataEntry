CREATE OR REPLACE VIEW public.view_member_reservations_activity
AS 
WITH reservation_stats AS (
    SELECT 
        cr_name,
        count(*) AS total_reservations
    FROM view_reservations_confirmed_staging
    GROUP BY cr_name
), 
return_stats AS (
    SELECT 
        vrcs.cr_name,
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
SELECT 
    m.member_name,
    COALESCE(res.total_reservations, 0) AS "Total Reservations",
    COALESCE(sum(rs.was_submitted), 0) AS "Returns Submitted"
FROM members m
LEFT JOIN return_stats rs ON m.cr_name = rs.cr_name
LEFT JOIN reservation_stats res ON m.cr_name = res.cr_name
GROUP BY m.member_name, res.total_reservations
ORDER BY 
    "Total Reservations" DESC, 
    -- Get the last word (Surname)
    split_part(m.member_name, ' ', array_length(regexp_split_to_array(m.member_name, '\s+'), 1)) ASC,
    -- Get everything except the last word (Initials)
    regexp_replace(m.member_name, '\s+\S+$', '') ASC;

