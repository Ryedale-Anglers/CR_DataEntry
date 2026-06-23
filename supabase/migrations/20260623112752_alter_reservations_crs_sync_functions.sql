CREATE OR REPLACE VIEW private.report_2_4_members_zero_reservations_scd
AS WITH yr_param AS (
         SELECT target_start_date,
            target_end_date,
            target_year
           FROM private.year_param
         LIMIT 1
        ), date_series AS (
         SELECT generate_series((( SELECT target_start_date
                   from yr_param))::timestamp with time zone, LEAST(CURRENT_DATE, ( SELECT target_end_date
                   FROM yr_param))::timestamp with time zone, '1 day'::interval)::date AS dt
        ), first_reservation AS (
         SELECT r.members_id,
            min(r.date) AS first_booked_on
           FROM private.reservations_confirmed r
             JOIN private.members m_1 ON m_1.id = r.members_id
          WHERE r.date <= CURRENT_DATE AND m_1.year_of_membership = (( SELECT target_year
                   FROM yr_param))
          GROUP BY r.members_id
        ), total_members AS (
         SELECT count(*) AS total
           FROM private.members
          WHERE members.year_of_membership = (( select target_year
                   FROM yr_param))
        ), members_with_reservation_by_date AS (
         SELECT d.dt,
            count(fr.members_id) AS has_booked
           FROM date_series d
             LEFT JOIN first_reservation fr ON fr.first_booked_on <= d.dt
          GROUP BY d.dt
        )
 SELECT m.dt AS date,
    tm.total - m.has_booked AS members_without_reservation
   FROM members_with_reservation_by_date m
     CROSS JOIN total_members tm
  ORDER BY m.dt;

CREATE OR REPLACE FUNCTION private.append_reservations_from_res_conf_staging(target_year integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    INSERT INTO private.reservations_confirmed ("date", members_id, beats_id)
    SELECT DISTINCT ON (rcs.date, b.beat_id)
        rcs.date, m.id, b.beat_id
    FROM public.reservations_confirmed_staging rcs
    INNER JOIN private.members m ON rcs.cr_name = m.cr_name
    INNER JOIN reservation_beats b ON rcs.resource = b.beat
    WHERE m.year_of_membership = target_year
    ORDER BY 
        rcs.date, 
        b.beat_id,
        CASE WHEN lower(rcs.name) = 'synthetic' THEN 1 ELSE 0 END
    ON CONFLICT ON CONSTRAINT uq_priv_reservation_confirmed_date_member_beat DO NOTHING;

END;
$function$
;

CREATE UNIQUE INDEX uq_priv_catch_returns_member_date_beat_if_not_guest 
ON private.catch_returns USING btree (member_name, catch_date, beats_id) WHERE (guest = false);

DROP INDEX private.uq_priv_catch_returns_member_date_only_if_not_guest;

CREATE OR REPLACE FUNCTION private.append_catch_returns_from_cr_staging_table()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    INSERT INTO private.catch_returns (
        member_name, 
        catch_date, 
        brown_trout, 
        brown_trout_killed, 
        grayling, 
        rainbow_trout, 
        other_species, 
        guest, 
        beats_id, 
        dnf
    )
    SELECT 
        crst.rod_name, 
        crst.catch_date, 
        crst.brown_trout_released, 
        crst.brown_trout_retained, 
        crst.grayling, 
        crst.rainbow_trout, 
        crst.other_species, 
        crst.guest, 
        b.id, 
        crst.dnf
    FROM public.catch_returns_staging_table crst
    INNER JOIN public.beats b ON crst.beat = b.beat
    -- Matches the exact columns and WHERE clause of your partial index:
    --ON CONFLICT (member_name, catch_date) WHERE (guest = false) DO NOTHING; 
    ON CONFLICT ON CONSTRAINT uq_priv_catch_returns_member_date_beat_if_not_guest DO NOTHING;

END;
$function$
;