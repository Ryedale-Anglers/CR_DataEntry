CREATE OR REPLACE VIEW public.view_in_season_dashb_3_freq_of_reservation AS
SELECT 
    reservation_count,
    count(*) AS frequency
FROM (
    SELECT 
        m.cr_name,
        -- CHANGE: Use DISTINCT so one reservation ID is only counted once 
        -- even if multiple catch returns exist for it.
        count(DISTINCT vrcs.id) AS reservation_count
    FROM members m
    LEFT JOIN view_reservations_confirmed_staging vrcs 
        ON m.cr_name = vrcs.cr_name
    LEFT JOIN catch_returns_staging_table crst 
        ON vrcs.date = crst.catch_date 
        AND vrcs.cr_name = crst.rod_name
    -- Filter logic stays the same
    WHERE (crst.dnf IS DISTINCT FROM true) 
    GROUP BY m.cr_name
) member_counts
GROUP BY reservation_count
ORDER BY reservation_count;

CREATE OR REPLACE VIEW public.view_in_season_dashb_2_count_reserv_by_beat AS 
SELECT 
    b.beat_short AS beat,
    -- CHANGE: Count unique dates per beat instead of unique reservation IDs
    -- this is required because of 2 reservations by different members on the same beat 
    -- on the same day. (mentoring activity I guess and a Booking system mistake)
    -- but we only want to count the beat has having been fished once, one day, not twice (two days)
    COUNT(DISTINCT vrcs.date) AS reservation_count
FROM beats b
LEFT JOIN view_reservations_confirmed_staging vrcs 
    ON vrcs.beat_id = b.id 
    AND vrcs.date >= make_date(EXTRACT(year FROM CURRENT_DATE)::integer, 4, 1) 
    AND vrcs.date <= make_date(EXTRACT(year FROM CURRENT_DATE)::integer, 9, 30)
LEFT JOIN catch_returns_staging_table crst 
    ON vrcs.date = crst.catch_date 
    AND vrcs.cr_name = crst.rod_name
WHERE b.id <> 18 
  AND (crst.dnf IS DISTINCT FROM true)
GROUP BY b.beat_short, b.river_order
ORDER BY b.river_order;

CREATE OR REPLACE VIEW public.view_in_season_dashb_1_count_res_cr
AS WITH timeline AS (
         SELECT generate_series('2026-04-01'::date::timestamp with time zone, CURRENT_DATE::timestamp with time zone, '7 days'::interval)::date AS week_starting
        ), filtered_reservations AS (
         SELECT vrcs.date,
            vrcs.cr_name
           FROM reservations_confirmed_staging vrcs
             LEFT JOIN catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name
          WHERE crst.dnf IS DISTINCT FROM true
        )
 SELECT week_starting,
    ( SELECT count(*) AS count
           FROM filtered_reservations fr
          WHERE fr.date >= t.week_starting AND fr.date < (t.week_starting + 7)) AS reservations,
    ( SELECT count(*) AS count
           FROM catch_returns_staging_table c
          WHERE c.catch_date >= t.week_starting AND c.catch_date < (t.week_starting + 7) AND c.dnf IS DISTINCT FROM true) AS catches_returns
   FROM timeline t
  ORDER BY week_starting;

  CREATE OR REPLACE VIEW public.view_in_season_dashb_1_count_res_cr AS 
WITH timeline AS (
    SELECT generate_series(
        '2026-04-01'::date, 
        CURRENT_DATE, 
        '7 days'::interval
    )::date AS week_starting
),
filtered_reservations AS (
    -- This CTE gets only the reservations we actually want to count
    SELECT 
        vrcs.date,
        vrcs.cr_name
    FROM reservations_confirmed_staging vrcs
    LEFT JOIN catch_returns_staging_table crst 
        ON vrcs.date = crst.catch_date 
        AND vrcs.cr_name = crst.rod_name
    WHERE (crst.dnf IS DISTINCT FROM true) 
    -- 'IS DISTINCT FROM true' handles cases where dnf is false OR where no return exists (null)
)
SELECT 
    t.week_starting,
    (SELECT count(*) 
     FROM filtered_reservations fr 
     WHERE fr.date >= t.week_starting 
       AND fr.date < (t.week_starting + 7)
    ) AS reservations,
    (SELECT count(*) 
     FROM catch_returns_staging_table c 
     WHERE c.catch_date >= t.week_starting 
       AND c.catch_date < (t.week_starting + 7)
       AND c.dnf IS DISTINCT FROM true -- Optional: exclude DNFs from the returns count too?
    ) AS catches_returns
FROM timeline t
ORDER BY t.week_starting;