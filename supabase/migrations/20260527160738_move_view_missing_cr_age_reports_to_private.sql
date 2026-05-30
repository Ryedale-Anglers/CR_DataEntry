-- public.view_missing_cr_age_report3 source
drop view public.view_missing_cr_age_report3;
drop view public.view_missing_cr_age_report2;
CREATE OR REPLACE VIEW private.view_missing_cr_age_report3
AS WITH reservation_stats AS (
         SELECT vrcs.cr_name,
            count(*) AS total_reservations
           FROM view_reservations_confirmed_staging vrcs
          WHERE vrcs.date < CURRENT_DATE AND NOT (EXISTS ( SELECT 1
                   FROM catch_returns_staging_table disqualified
                  WHERE disqualified.catch_date = vrcs.date AND disqualified.rod_name = vrcs.cr_name AND (disqualified.dnf = true OR disqualified.guest = true)))
          GROUP BY vrcs.cr_name
        ), return_stats AS (
         SELECT vrcs.cr_name,
            CURRENT_DATE - vrcs.date AS days_old,
                CASE
                    WHEN crst.rod_name IS NOT NULL THEN 1
                    ELSE 0
                END AS was_submitted
           FROM view_reservations_confirmed_staging vrcs
             LEFT JOIN ( SELECT catch_returns_staging_table.id,
                    catch_returns_staging_table."timestamp",
                    catch_returns_staging_table.rod_name,
                    catch_returns_staging_table.catch_date,
                    catch_returns_staging_table.beat,
                    catch_returns_staging_table.guest,
                    catch_returns_staging_table.dnf,
                    row_number() OVER (PARTITION BY catch_returns_staging_table.catch_date, catch_returns_staging_table.rod_name ORDER BY catch_returns_staging_table."timestamp" DESC) AS rn
                   FROM catch_returns_staging_table
                  WHERE catch_returns_staging_table.dnf = false AND catch_returns_staging_table.guest = false) crst ON vrcs.cr_name = crst.rod_name AND vrcs.date = crst.catch_date AND crst.rn = 1
          WHERE vrcs.date < CURRENT_DATE AND NOT (EXISTS ( SELECT 1
                   FROM catch_returns_staging_table disqualified
                  WHERE disqualified.catch_date = vrcs.date AND disqualified.rod_name = vrcs.cr_name AND (disqualified.dnf = true OR disqualified.guest = true)))
        )
 SELECT m.member_name,
    res.total_reservations AS "Total Reservations",
    sum(rs.was_submitted) AS "Returns Submitted",
    COALESCE(round(sum(rs.was_submitted)::numeric / NULLIF(res.total_reservations, 0)::numeric * 100::numeric, 1), 0::numeric) AS pct_compliance,
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
   FROM view_member_names m
     JOIN return_stats rs ON m.cr_name = rs.cr_name
     LEFT JOIN reservation_stats res ON m.cr_name = res.cr_name
  GROUP BY m.member_name, res.total_reservations
 HAVING count(
        CASE
            WHEN rs.was_submitted = 0 THEN 1
            ELSE NULL::integer
        END) > 0
  ORDER BY (count(
        CASE
            WHEN rs.was_submitted = 0 THEN 1
            ELSE NULL::integer
        END)) DESC;

CREATE OR REPLACE VIEW private.view_missing_cr_age_report2
AS WITH reservation_stats AS (
         SELECT vrcs.cr_name,
            count(*) AS total_reservations
           FROM view_reservations_confirmed_staging vrcs
          WHERE vrcs.date < CURRENT_DATE AND NOT (EXISTS ( SELECT 1
                   FROM catch_returns_staging_table disqualified
                  WHERE disqualified.catch_date = vrcs.date AND disqualified.rod_name = vrcs.cr_name AND (disqualified.dnf = true OR disqualified.guest = true)))
          GROUP BY vrcs.cr_name
        ), return_stats AS (
         SELECT vrcs.cr_name,
            CURRENT_DATE - vrcs.date AS days_old,
                CASE
                    WHEN crst.rod_name IS NOT NULL THEN 1
                    ELSE 0
                END AS was_submitted
           FROM view_reservations_confirmed_staging vrcs
             LEFT JOIN ( SELECT catch_returns_staging_table.id,
                    catch_returns_staging_table."timestamp",
                    catch_returns_staging_table.rod_name,
                    catch_returns_staging_table.catch_date,
                    catch_returns_staging_table.beat,
                    catch_returns_staging_table.brown_trout_released,
                    catch_returns_staging_table.grayling,
                    catch_returns_staging_table.rainbow_trout,
                    catch_returns_staging_table.other_species,
                    catch_returns_staging_table.brown_trout_retained,
                    catch_returns_staging_table.guest,
                    catch_returns_staging_table.comments,
                    catch_returns_staging_table.dnf,
                    row_number() OVER (PARTITION BY catch_returns_staging_table.catch_date, catch_returns_staging_table.rod_name ORDER BY catch_returns_staging_table."timestamp" DESC) AS rn
                   FROM catch_returns_staging_table
                  WHERE catch_returns_staging_table.dnf = false AND catch_returns_staging_table.guest = false) crst ON vrcs.cr_name = crst.rod_name AND vrcs.date = crst.catch_date AND crst.rn = 1
          WHERE vrcs.date < CURRENT_DATE AND NOT (EXISTS ( SELECT 1
                   FROM catch_returns_staging_table disqualified
                  WHERE disqualified.catch_date = vrcs.date AND disqualified.rod_name = vrcs.cr_name AND (disqualified.dnf = true OR disqualified.guest = true)))
        )
 SELECT m.member_name,
    res.total_reservations AS "Total Reservations",
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
   FROM view_member_names m
     JOIN return_stats rs ON m.cr_name = rs.cr_name
     LEFT JOIN reservation_stats res ON m.cr_name = res.cr_name
  GROUP BY m.member_name, res.total_reservations
 HAVING count(
        CASE
            WHEN rs.was_submitted = 0 THEN 1
            ELSE NULL::integer
        END) > 0
  ORDER BY (count(
        CASE
            WHEN rs.was_submitted = 0 THEN 1
            ELSE NULL::integer
        END)) DESC;