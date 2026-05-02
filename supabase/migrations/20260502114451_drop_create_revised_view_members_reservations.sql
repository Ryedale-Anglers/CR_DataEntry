drop view if exists public.view_members_reserv_and_cr_history;

CREATE OR REPLACE VIEW public.view_members_reserv_and_cr_history
AS
SELECT
    vrcs.date,
    vrcs.cr_name,
    vrcs.beat,
    crst.brown_trout_released + crst."brown_trout_retained" AS brown_trout,
    crst.grayling,
    crst.comments
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
) crst
    ON vrcs.date = crst.catch_date
    AND vrcs.cr_name = crst.rod_name
    AND crst.rn = 1
WHERE NOT EXISTS (
    SELECT 1
    FROM catch_returns_staging_table disqualified
    WHERE disqualified.catch_date = vrcs.date
      AND disqualified.rod_name = vrcs.cr_name
      AND (disqualified.dnf = true OR disqualified.guest = true)
)
ORDER BY vrcs.date asc, vrcs.cr_name asc;