CREATE OR REPLACE VIEW private.view_catch_returns_missing
AS SELECT date,
    cr_name,
    beat_id,
    beat,
    floor(EXTRACT(day FROM CURRENT_TIMESTAMP - date::timestamp without time zone::timestamp with time zone)) AS full_days_elapsed
   FROM public.view_reservations_confirmed_staging vrcs
  WHERE date < CURRENT_DATE AND NOT (EXISTS ( SELECT 1
           FROM public.catch_returns_staging_table crst
          WHERE vrcs.date = crst.catch_date AND vrcs.beat = crst.beat AND vrcs.cr_name = crst.rod_name))
  ORDER BY (floor(EXTRACT(day FROM CURRENT_TIMESTAMP - date::timestamp without time zone::timestamp with time zone))) DESC;

drop view public.view_catch_returns_missing;

CREATE OR REPLACE VIEW private.view_member_names AS 
SELECT  id,
        cr_name,
        member_name,
        year_of_membership
   FROM private.members;

CREATE OR REPLACE VIEW private.view_in_season_dashb_3_freq_of_reservation
AS SELECT reservation_count,
    count(*) AS frequency
   FROM ( SELECT m.cr_name,
            count(DISTINCT vrcs.id) AS reservation_count
           FROM private.view_member_names m
             LEFT JOIN view_reservations_confirmed_staging vrcs ON m.cr_name = vrcs.cr_name
             LEFT JOIN catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name
          WHERE crst.dnf IS DISTINCT FROM true AND m.year_of_membership::numeric = (( SELECT EXTRACT(year FROM CURRENT_DATE) AS "extract"))
          GROUP BY m.cr_name) member_counts
  GROUP BY reservation_count
  ORDER BY reservation_count;

CREATE OR REPLACE VIEW private.view_missing_cr_age_report5
AS WITH reservation_stats AS (
         SELECT vrcs.cr_name,
            count(*) AS total_reservations
           FROM view_reservations_confirmed_staging vrcs
             LEFT JOIN catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name AND vrcs.beat = crst.beat
          WHERE crst.guest IS DISTINCT FROM true AND crst.dnf IS DISTINCT FROM true AND vrcs.date < CURRENT_DATE
          GROUP BY vrcs.cr_name
        ), catch_returns_stats AS (
         SELECT vrcs.cr_name,
            sum(
                CASE
                    WHEN crst.rod_name IS NOT NULL THEN 1
                    ELSE 0
                END) AS total_submitted,
            count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 1 AND (CURRENT_DATE - vrcs.date) <= 7) AS "1-7 Days",
            count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 8 AND (CURRENT_DATE - vrcs.date) <= 14) AS "8-14 Days",
            count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 15 AND (CURRENT_DATE - vrcs.date) <= 21) AS "15-21 Days",
            count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 22 AND (CURRENT_DATE - vrcs.date) <= 28) AS "22-28 Days",
            count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) > 28) AS "28+ Days"
           FROM view_reservations_confirmed_staging vrcs
             LEFT JOIN catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name AND vrcs.beat = crst.beat
          WHERE crst.guest IS DISTINCT FROM true AND crst.dnf IS DISTINCT FROM true AND vrcs.date < CURRENT_DATE
          GROUP BY vrcs.cr_name
        )
 SELECT m.member_name,
    COALESCE(res.total_reservations, 0::bigint) AS "Reservations",
    COALESCE(crs.total_submitted, 0::bigint) AS "Catch Returns",
    COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint) AS "CRs Due",
    COALESCE(round(crs.total_submitted::numeric / NULLIF(res.total_reservations, 0)::numeric * 100::numeric, 1), 0::numeric) AS pct_compliance,
    COALESCE(crs."1-7 Days", 0::bigint) AS "1-7 Days",
    COALESCE(crs."8-14 Days", 0::bigint) AS "8-14 Days",
    COALESCE(crs."15-21 Days", 0::bigint) AS "15-21 Days",
    COALESCE(crs."22-28 Days", 0::bigint) AS "22-28 Days",
    COALESCE(crs."28+ Days", 0::bigint) AS "28+ Days"
   FROM private.view_member_names m
     LEFT JOIN reservation_stats res ON m.cr_name = res.cr_name
     LEFT JOIN catch_returns_stats crs ON m.cr_name = crs.cr_name
  WHERE (COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint)) > 0
  ORDER BY (COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint)) DESC;

CREATE OR REPLACE VIEW private.view_member_reservations_activity
AS WITH reservation_stats AS (
         SELECT vrcs.cr_name,
            count(*) AS total_reservations
           FROM view_reservations_confirmed_staging vrcs
             LEFT JOIN catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name AND vrcs.beat = crst.beat
          WHERE crst.guest IS DISTINCT FROM true AND crst.dnf IS DISTINCT FROM true AND vrcs.date < CURRENT_DATE
          GROUP BY vrcs.cr_name
        ), catch_returns_stats AS (
         SELECT vrcs.cr_name,
            sum(
                CASE
                    WHEN crst.rod_name IS NOT NULL THEN 1
                    ELSE 0
                END) AS total_submitted
           FROM view_reservations_confirmed_staging vrcs
             LEFT JOIN catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name AND vrcs.beat = crst.beat
          WHERE crst.guest IS DISTINCT FROM true AND crst.dnf IS DISTINCT FROM true AND vrcs.date < CURRENT_DATE
          GROUP BY vrcs.cr_name
        )
 SELECT m.member_name,
    m.cr_name,
    COALESCE(res.total_reservations, 0::bigint) AS "Reservations",
    COALESCE(crs.total_submitted, 0::bigint) AS "Catch Returns",
    COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint) AS "CRs Due"
   FROM private.view_member_names m
     LEFT JOIN reservation_stats res ON m.cr_name = res.cr_name
     LEFT JOIN catch_returns_stats crs ON m.cr_name = crs.cr_name
  WHERE m.year_of_membership::numeric = EXTRACT(year FROM CURRENT_DATE)
  ORDER BY (COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint)) DESC, m.cr_name;


CREATE OR REPLACE FUNCTION public.get_private_dashb_3_data()
RETURNS TABLE (reservation_count int, frequency int)
LANGUAGE sql
SECURITY DEFINER
SET search_path = private, public
AS $$
  SELECT reservation_count, frequency FROM private.view_in_season_dashb_3_freq_of_reservation;
$$;

GRANT EXECUTE ON FUNCTION public.get_private_dashb_3_data() TO authenticated, anon;

drop view public.view_in_season_dashb_3_freq_of_reservation;

drop view public.view_member_names;
