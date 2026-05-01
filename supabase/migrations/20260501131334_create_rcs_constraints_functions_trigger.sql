ALTER TABLE reservations_confirmed_staging
ADD CONSTRAINT uq_reservation_date_cr_name UNIQUE (date, cr_name);

-- Create trigger function to auto-insert reservation if missing
CREATE OR REPLACE FUNCTION check_and_insert_reservation()
RETURNS TRIGGER AS $$
DECLARE
    v_resource TEXT;
BEGIN
    -- Lookup the resource value from reservation_beats via beats
    SELECT rb.beat INTO v_resource
    FROM reservation_beats rb
    INNER JOIN beats bt ON rb.beat_id = bt.id
    WHERE bt.beat = NEW.beat
    LIMIT 1;

    -- Guard against no match
    IF v_resource IS NULL THEN
        RAISE EXCEPTION 'No resource found for beat: %', NEW.beat;
    END IF;

    INSERT INTO reservations_confirmed_staging (date, resource, name, cr_name)
    VALUES (NEW.catch_date, v_resource, 'Synthetic', NEW.rod_name)
    ON CONFLICT (date, cr_name) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach trigger to catch_returns_staging_table
CREATE TRIGGER trg_check_reservation_on_catch_insert
BEFORE INSERT ON catch_returns_staging_table
FOR EACH ROW
EXECUTE FUNCTION check_and_insert_reservation();