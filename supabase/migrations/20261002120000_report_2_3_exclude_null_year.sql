-- report_2_3_num_days_fished_by_year_v2 returned a row with a NULL year for
-- reservations (or beat 18 catch returns) dated outside the April-September
-- season, because seasonal_year_int is NULL for those dates. Exclude them so
-- only seasonal years are reported. Columns and their order are unchanged.
CREATE OR REPLACE VIEW private.report_2_3_num_days_fished_by_year_v2 AS
SELECT year,
       sum(record_count) AS total_count
FROM (
    SELECT vrc.seasonal_year_int AS year,
           count(vrc.id) AS record_count
    FROM private.view_reservations_confirmed vrc
    LEFT JOIN private.view_troutseasondata vt
           ON vt.catch_date = vrc.date
          AND vt.member_name = vrc.cr_name
          AND vt.seasonal_year_int = vrc.year_of_membership
    GROUP BY vrc.seasonal_year_int
    UNION ALL
    SELECT vt.seasonal_year_int AS year,
           count(*) AS record_count
    FROM private.view_troutseasondata vt
    WHERE vt.beats_id = 18
    GROUP BY vt.seasonal_year_int
) combined
WHERE year IS NOT NULL
GROUP BY year
ORDER BY year;
