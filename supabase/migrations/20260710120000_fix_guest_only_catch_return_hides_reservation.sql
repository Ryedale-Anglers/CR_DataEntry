-- private.view_members_reserv_and_cr_history_anonymous feeds recent_beat_reservations.html.
-- Its old WHERE clause excluded any reservation whose only matching catch_returns_staging_table
-- row had guest = true, silencing the whole reservation from the grid. Case: member reserves a
-- beat, doesn't fish it themselves and never submits a DNF, but their guest does fish and
-- submits a guest catch return - the reservation should still show, with the guest's catch data.
--
-- The join on (catch_date, rod_name, beat) with no guest filter can also match more than one
-- catch_returns_staging_table row for the same reservation (e.g. the member's own row plus one
-- or more guest rows). Pick exactly one representative row per reservation: prefer the
-- guest = false row when present, else the most recent guest = true row. Comments only ever
-- come from a guest = false row; if the only available data is from a guest, show a fixed note
-- instead of the guest's own comment text. A member DNF (guest = false, dnf = true) only hides
-- the reservation when there's no other catch data to fall back on - if a guest also fished and
-- reported a catch for the same reservation, the guest's catch wins and the row is shown.
CREATE OR REPLACE VIEW private.view_members_reserv_and_cr_history_anonymous AS
WITH ranked_catch AS (
    SELECT
        crst.catch_date,
        crst.rod_name,
        crst.beat,
        crst.brown_trout_released,
        crst.brown_trout_retained,
        crst.grayling,
        crst.guest,
        crst.comments,
        ROW_NUMBER() OVER (
            PARTITION BY crst.catch_date, crst.rod_name, crst.beat
            ORDER BY crst.guest ASC, crst."timestamp" DESC
        ) AS rn
    FROM private.catch_returns_staging_table crst
    WHERE crst.dnf IS DISTINCT FROM true
)
SELECT
    vrcs.date,
    vrcs.beat,
    rc.brown_trout_released + rc.brown_trout_retained AS brown_trout,
    rc.grayling,
    CASE WHEN rc.guest = true THEN 'NB: Only guest catch return available' ELSE rc.comments END AS comments
FROM private.view_reservations_confirmed_staging vrcs
LEFT JOIN ranked_catch rc
    ON vrcs.date = rc.catch_date AND vrcs.cr_name = rc.rod_name AND vrcs.beat = rc.beat AND rc.rn = 1
WHERE rc.catch_date IS NOT NULL   -- there is non-DNF catch data (member or guest) to show
   OR NOT EXISTS (                -- or there's no member DNF blocking it - nothing at all, show as CR Due
        SELECT 1 FROM private.catch_returns_staging_table dnf_check
        WHERE dnf_check.catch_date = vrcs.date
          AND dnf_check.rod_name  = vrcs.cr_name
          AND dnf_check.beat      = vrcs.beat
          AND dnf_check.guest     = false
          AND dnf_check.dnf       = true
      )
ORDER BY vrcs.date;
