CREATE OR REPLACE VIEW private.report_2_4_members_engagement_reservations_scd as
WITH yr_param AS (
         SELECT year_param.target_start_date,
            year_param.target_end_date,
            year_param.target_year
           FROM private.year_param
         LIMIT 1
        ), date_series AS (
         SELECT generate_series((( SELECT yr_param.target_start_date
                   FROM yr_param))::timestamp with time zone, LEAST(CURRENT_DATE, ( SELECT yr_param.target_end_date
                   FROM yr_param))::timestamp with time zone, '1 day'::interval)::date AS dt
        ), first_reservation AS (
         SELECT r.members_id,
            min(r.date) AS first_booked_on
           FROM private.reservations_confirmed r
             JOIN private.members m_1 ON m_1.id = r.members_id
          WHERE r.date <= CURRENT_DATE AND m_1.year_of_membership = (( SELECT yr_param.target_year
                   FROM yr_param))
          GROUP BY r.members_id
        ), total_members AS (
         SELECT count(*) AS total
           FROM private.members
          WHERE members.year_of_membership = (( SELECT yr_param.target_year
                   FROM yr_param))
        ), members_with_reservation_by_date AS (
         SELECT d.dt,
            count(fr.members_id) AS has_booked
           FROM date_series d
             LEFT JOIN first_reservation fr ON fr.first_booked_on <= d.dt
          GROUP BY d.dt
        )
 SELECT m.dt AS date,tm.total as total_num_members,
     m.has_booked AS num_members_engaged
   FROM members_with_reservation_by_date m
     CROSS JOIN total_members tm
  ORDER BY m.dt;