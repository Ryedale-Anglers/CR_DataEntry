-- Add SECURITY DEFINER to allow trigger to insert into reservations_confirmed_staging
-- without granting anon key direct insert privileges on that table
CREATE OR REPLACE FUNCTION public.check_and_insert_reservation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_resource TEXT;
BEGIN
    SELECT rb.beat INTO v_resource
    FROM reservation_beats rb
    INNER JOIN beats bt ON rb.beat_id = bt.id
    WHERE bt.beat = NEW.beat
    LIMIT 1;

    IF v_resource IS NULL THEN
        RAISE EXCEPTION 'No resource found for beat: %', NEW.beat;
    END IF;

    INSERT INTO reservations_confirmed_staging (date, resource, name, cr_name)
    VALUES (NEW.catch_date, v_resource, 'Synthetic', NEW.rod_name)
    ON CONFLICT (date, cr_name) DO NOTHING;

    RETURN NEW;
END;
$function$;