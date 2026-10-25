-- Allow a guest catch return with no member catch return, when the member confirms
-- that they did not fish the reservation themselves and their guest fished in their
-- place. This relaxes rule (b) of 20260929120000; rules (a) and (c) are unchanged:
--   a) a guest catch return can never be DNF;
--   c) marking the member's own return DNF deletes the reservation's guest returns
--      (DNF means nobody fished it).
--
-- 1. catch_returns_staging_table.host_did_not_fish: true on a guest return when the
--    member has confirmed they did not fish that reservation. Only a guest return
--    can carry it.
-- 2. submit_catch_return_for_reservation gains p_host_did_not_fish. A NEW guest
--    return is accepted when:
--      - the member's own return exists and is not DNF (as before), or
--      - there is no member return and either p_host_did_not_fish is true or the
--        member already confirmed it for this reservation (asked once per
--        reservation; a second guest return needs no new confirmation).
--    Once confirmed, every guest return on the reservation carries the flag.
--    A member DNF return still blocks new guest returns.
-- 3. When the member later enters their own return for the reservation, the flag is
--    cleared on its guest returns (trigger, so every write path is covered).
-- 4. get_guest_catch_returns_for_reservation also returns host_did_not_fish, so the
--    form knows whether the confirmation has already been given.
-- 5. A confirmed guest-only return fulfils the member's obligation, so the v2 member
--    summary drops member_returns_missing; view_reservation_return_status_staging
--    gains host_did_not_fish. Statuses are unchanged.

-- 1. Column
ALTER TABLE private.catch_returns_staging_table
    ADD COLUMN IF NOT EXISTS host_did_not_fish boolean NOT NULL DEFAULT false;

ALTER TABLE private.catch_returns_staging_table
    DROP CONSTRAINT IF EXISTS chk_host_did_not_fish_guest_only;
ALTER TABLE private.catch_returns_staging_table
    ADD CONSTRAINT chk_host_did_not_fish_guest_only CHECK (NOT host_did_not_fish OR guest);

-- 2. Submit function (new parameter, so drop and recreate, keeping the same grants)
DROP FUNCTION IF EXISTS public.submit_catch_return_for_reservation(
    text, text, date, text, boolean, boolean, integer, integer, integer, integer, integer, text, integer);

CREATE FUNCTION public.submit_catch_return_for_reservation(
    p_password          text,
    p_surname           text,
    p_catch_date        date,
    p_beat              text,
    p_guest             boolean DEFAULT false,
    p_dnf               boolean DEFAULT false,
    p_bt_released       integer DEFAULT 0,
    p_grayling          integer DEFAULT 0,
    p_rainbow           integer DEFAULT 0,
    p_other             integer DEFAULT 0,
    p_bt_retained       integer DEFAULT 0,
    p_comments          text DEFAULT ''::text,
    p_id                integer DEFAULT NULL,
    p_host_did_not_fish boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    pw_valid             boolean;
    current_year         text;
    canonical_name       text;
    v_reservation_exists boolean;
    v_own_found          boolean;
    v_own_dnf            boolean;
    v_host_did_not_fish  boolean := false;
    v_updated_id         integer;
BEGIN
    SELECT (value_hash = crypt(p_password, value_hash))
    INTO pw_valid
    FROM private.club_settings
    WHERE key = 'shared_catch_password'
    LIMIT 1;

    IF NOT COALESCE(pw_valid, FALSE) THEN
        RAISE EXCEPTION 'Invalid club password';
    END IF;

    SELECT value_hash INTO current_year
    FROM private.club_settings
    WHERE key = 'current_member_year'
    LIMIT 1;

    SELECT cr_name INTO canonical_name
    FROM private.members
    WHERE upper(cr_name) = upper(p_surname)
      AND year_of_membership::text = current_year
    LIMIT 1;

    IF canonical_name IS NULL THEN
        RAISE EXCEPTION 'Member surname not recognised';
    END IF;

    -- Rule (a): a guest catch return can never be DNF.
    IF p_guest AND p_dnf THEN
        RAISE EXCEPTION 'A guest catch return cannot be marked Did Not Fish.';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM private.reservations_confirmed_staging rcs
        INNER JOIN private.reservation_beats rb ON rb.beat = rcs.resource
        INNER JOIN private.beats b ON b.id = rb.beat_id
        WHERE rcs.cr_name = canonical_name
          AND rcs.date = p_catch_date
          AND b.beat = p_beat
    ) INTO v_reservation_exists;

    IF NOT v_reservation_exists THEN
        RAISE EXCEPTION 'No reservation found for % on %', p_beat, p_catch_date;
    END IF;

    -- A NEW guest catch return (p_id IS NULL; editing one by id is unaffected).
    IF p_guest AND p_id IS NULL THEN
        SELECT true, dnf INTO v_own_found, v_own_dnf
        FROM private.catch_returns_staging_table
        WHERE rod_name   = canonical_name
          AND catch_date = p_catch_date
          AND beat       = p_beat
          AND guest      = false;

        IF COALESCE(v_own_found, false) THEN
            IF v_own_dnf THEN
                RAISE EXCEPTION 'Your catch return for this reservation is marked Did Not Fish, so a guest catch return cannot be added. Edit your own catch return first if you did fish.';
            END IF;
        ELSE
            -- No member return: the member must confirm they did not fish, once
            -- per reservation.
            v_host_did_not_fish := p_host_did_not_fish OR EXISTS (
                SELECT 1
                FROM private.catch_returns_staging_table
                WHERE rod_name   = canonical_name
                  AND catch_date = p_catch_date
                  AND beat       = p_beat
                  AND guest      = true
                  AND host_did_not_fish = true);

            IF NOT v_host_did_not_fish THEN
                RAISE EXCEPTION 'Confirm that you did not fish this reservation yourself, or enter your own catch return first, before adding a guest catch return.';
            END IF;

            -- Apply the confirmation to the reservation's existing guest returns too.
            UPDATE private.catch_returns_staging_table
            SET host_did_not_fish = true
            WHERE rod_name   = canonical_name
              AND catch_date = p_catch_date
              AND beat       = p_beat
              AND guest      = true
              AND host_did_not_fish = false;
        END IF;
    END IF;

    IF p_id IS NOT NULL THEN
        IF NOT p_guest THEN
            RAISE EXCEPTION 'p_id is only valid for guest catch returns';
        END IF;

        UPDATE private.catch_returns_staging_table
        SET "timestamp"          = NOW()::text,
            dnf                  = p_dnf,
            brown_trout_released = p_bt_released,
            grayling             = p_grayling,
            rainbow_trout        = p_rainbow,
            other_species        = p_other,
            brown_trout_retained = p_bt_retained,
            comments             = p_comments
        WHERE id = p_id
          AND rod_name = canonical_name
          AND catch_date = p_catch_date
          AND beat = p_beat
          AND guest = true
        RETURNING id INTO v_updated_id;

        IF v_updated_id IS NULL THEN
            RAISE EXCEPTION 'Guest catch return not found';
        END IF;

        RETURN;
    END IF;

    INSERT INTO private.catch_returns_staging_table (
        "timestamp", rod_name, catch_date, beat, dnf, guest,
        brown_trout_released, grayling, rainbow_trout, other_species,
        brown_trout_retained, comments, host_did_not_fish
    ) VALUES (
        NOW()::text, canonical_name, p_catch_date, p_beat, p_dnf, p_guest,
        p_bt_released, p_grayling, p_rainbow, p_other, p_bt_retained, p_comments,
        v_host_did_not_fish
    )
    ON CONFLICT (rod_name, catch_date, beat)
    WHERE guest = false
    DO UPDATE SET
        "timestamp"          = EXCLUDED."timestamp",
        dnf                  = EXCLUDED.dnf,
        brown_trout_released = EXCLUDED.brown_trout_released,
        grayling             = EXCLUDED.grayling,
        rainbow_trout        = EXCLUDED.rainbow_trout,
        other_species        = EXCLUDED.other_species,
        brown_trout_retained = EXCLUDED.brown_trout_retained,
        comments             = EXCLUDED.comments;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.submit_catch_return_for_reservation(
    text, text, date, text, boolean, boolean, integer, integer, integer, integer, integer, text, integer, boolean)
    TO anon, authenticated, service_role;

-- 3. Member's own return clears the confirmation on that reservation's guest returns.
CREATE OR REPLACE FUNCTION private.clear_host_did_not_fish_on_member_return()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
    IF NEW.guest = false THEN
        UPDATE private.catch_returns_staging_table
        SET host_did_not_fish = false
        WHERE rod_name   = NEW.rod_name
          AND catch_date = NEW.catch_date
          AND beat       = NEW.beat
          AND guest      = true
          AND host_did_not_fish = true;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_clear_host_did_not_fish_on_member_return ON private.catch_returns_staging_table;

CREATE TRIGGER trg_clear_host_did_not_fish_on_member_return
AFTER INSERT OR UPDATE ON private.catch_returns_staging_table
FOR EACH ROW
EXECUTE FUNCTION private.clear_host_did_not_fish_on_member_return();

-- 4. Guest returns lookup also returns the flag (return type changes, so drop and recreate).
DROP FUNCTION IF EXISTS public.get_guest_catch_returns_for_reservation(text, text, date, text);

CREATE FUNCTION public.get_guest_catch_returns_for_reservation(p_password text, p_surname text, p_catch_date date, p_beat text)
RETURNS TABLE(id integer, submitted_at text, dnf boolean, brown_trout_released integer, grayling integer,
              rainbow_trout integer, other_species integer, brown_trout_retained integer, comments text,
              host_did_not_fish boolean)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    pw_valid       boolean;
    current_year   text;
    canonical_name text;
BEGIN
    SELECT (value_hash = crypt(p_password, value_hash))
    INTO pw_valid
    FROM private.club_settings
    WHERE key = 'shared_catch_password'
    LIMIT 1;

    IF NOT COALESCE(pw_valid, FALSE) THEN
        RAISE EXCEPTION 'Invalid club password';
    END IF;

    SELECT value_hash INTO current_year
    FROM private.club_settings
    WHERE key = 'current_member_year'
    LIMIT 1;

    SELECT cr_name INTO canonical_name
    FROM private.members
    WHERE upper(cr_name) = upper(p_surname)
      AND year_of_membership::text = current_year
    LIMIT 1;

    IF canonical_name IS NULL THEN
        RAISE EXCEPTION 'Member surname not recognised';
    END IF;

    RETURN QUERY
    SELECT crst.id, crst."timestamp", crst.dnf, crst.brown_trout_released,
           crst.grayling, crst.rainbow_trout, crst.other_species,
           crst.brown_trout_retained, crst.comments, crst.host_did_not_fish
    FROM private.catch_returns_staging_table crst
    WHERE crst.rod_name   = canonical_name
      AND crst.catch_date = p_catch_date
      AND crst.beat       = p_beat
      AND crst.guest      = true
    ORDER BY crst."timestamp" ASC;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_guest_catch_returns_for_reservation(text, text, date, text)
    TO anon, authenticated, service_role;

-- 5. Views
DROP VIEW IF EXISTS private.view_secrep_membername_catchreturns_count_operational_v2;

CREATE OR REPLACE VIEW private.view_reservation_return_status_staging AS
SELECT vrcs.id   AS reservation_id,
       vrcs.date,
       vrcs.cr_name,
       vrcs.name AS booking_name,
       vrcs.beat_id,
       vrcs.beat,
       vrcs.river_order,
       mr.id     AS member_return_id,
       g.guest_returns,
       CASE
           WHEN mr.id IS NOT NULL AND mr.dnf IS TRUE THEN 'dnf'
           WHEN mr.id IS NOT NULL                    THEN 'member_return'
           WHEN g.guest_returns > 0                  THEN 'guest_only'
           ELSE 'missing'
       END AS return_status,
       g.host_did_not_fish
FROM private.view_reservations_confirmed_staging vrcs
CROSS JOIN (SELECT target_start_date, target_end_date FROM private.year_param WHERE id = 1) yp
LEFT JOIN private.catch_returns_staging_table mr
       ON mr.guest = false
      AND mr.rod_name   = vrcs.cr_name
      AND mr.catch_date = vrcs.date
      AND mr.beat       = vrcs.beat
CROSS JOIN LATERAL (
    SELECT count(*) AS guest_returns,
           COALESCE(bool_or(gr.host_did_not_fish), false) AS host_did_not_fish
    FROM private.catch_returns_staging_table gr
    WHERE gr.guest = true
      AND gr.rod_name   = vrcs.cr_name
      AND gr.catch_date = vrcs.date
      AND gr.beat       = vrcs.beat
) g
WHERE vrcs.date >= yp.target_start_date
  AND vrcs.date <= LEAST(yp.target_end_date, CURRENT_DATE - 1);

CREATE VIEW private.view_secrep_membername_catchreturns_count_operational_v2 AS
SELECT s.cr_name,
       count(*)                                                  AS reservations_count,
       count(*) FILTER (WHERE s.return_status = 'member_return') AS member_returns,
       count(*) FILTER (WHERE s.return_status = 'dnf')           AS dnf,
       count(*) FILTER (WHERE s.return_status = 'guest_only')    AS guest_only,
       count(*) FILTER (WHERE s.return_status = 'missing')       AS missing
FROM private.view_reservation_return_status_staging s
GROUP BY s.cr_name
ORDER BY missing DESC, reservations_count DESC, s.cr_name;
