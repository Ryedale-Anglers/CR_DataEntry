drop view public.view_member_reservations_activity;

create view private.view_member_reservations_activity as
WITH reservation_stats AS (
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
 SELECT m.member_name, m.cr_name,
    COALESCE(res.total_reservations, 0::bigint) AS "Reservations",
    COALESCE(crs.total_submitted, 0::bigint) AS "Catch Returns",
    COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint) AS "CRs Due"
   FROM view_member_names m
     LEFT JOIN reservation_stats res ON m.cr_name = res.cr_name
     LEFT JOIN catch_returns_stats crs ON m.cr_name = crs.cr_name
     where m.year_of_membership = EXTRACT(YEAR FROM CURRENT_DATE)
  ORDER BY (COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint)) desc, m.cr_name;