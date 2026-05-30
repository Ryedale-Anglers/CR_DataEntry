Drop view public.view_reservations_confirmed;
CREATE OR REPLACE VIEW public.view_reservations_confirmed AS 
SELECT 	rc.id,
		rc.date,
	    m.cr_name,
	    b.beat,
	    b.beat_short,
	    b.river_order,
	    to_char(rc.date::timestamp with time zone, 'Mon'::text) AS seasonal_month,
	        CASE
	            WHEN to_char(rc.date::timestamp with time zone, 'MM'::text) >= '04'::text AND to_char(rc.date::timestamp with time zone, 'MM'::text) <= '09'::text THEN to_char(rc.date::timestamp with time zone, 'YYYY'::text)
	            ELSE 'Off-Season'::text
	        END AS seasonal_year,
	        CASE
	            WHEN to_char(rc.date::timestamp with time zone, 'MM'::text) >= '04'::text AND to_char(rc.date::timestamp with time zone, 'MM'::text) <= '09'::text THEN to_char(rc.date::timestamp with time zone, 'YYYY'::text)::integer
	            ELSE NULL::integer
	        END AS seasonal_year_int
FROM reservations_confirmed rc
  JOIN private.members m ON rc.members_id = m.id
  JOIN beats b ON rc.beats_id = b.id
  LEFT JOIN catch_returns_staging_table crst ON rc.date = crst.catch_date 
                                             AND m.cr_name = crst.rod_name
                                             AND crst.guest IS DISTINCT FROM TRUE
WHERE crst.dnf IS DISTINCT FROM true;

-- DROP FUNCTION private.append_reservations_from_res_conf_staging(int4);

CREATE OR REPLACE FUNCTION private.append_reservations_from_res_conf_staging(target_year integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    -- Sync Reservations utilizing the integer target_year parameter
    INSERT INTO public.reservations_confirmed ("date", members_id, beats_id)
    SELECT rcs.date, m.id, b.beat_id
    FROM public.reservations_confirmed_staging rcs
    INNER JOIN private.members m ON rcs.cr_name = m.cr_name
    INNER JOIN reservation_beats b ON rcs.resource = b.beat
    WHERE m.year_of_membership = target_year  -- Now comparing INT = INT
    ON CONFLICT ON CONSTRAINT uq_reservation_confirmed_date_member_beat DO NOTHING;

    -- Optional: Clear staging records if desired after processing
    -- TRUNCATE TABLE public.reservations_confirmed_staging;

END;
$function$
;