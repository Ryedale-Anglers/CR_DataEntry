-- Closes a gap found while reviewing the guest-catch-return edit flow in
-- index_supabase.html: nothing stopped a guest catch return from being
-- marked Did Not Fish, or from being entered before the host member's own
-- catch return existed for that reservation. Enforcing these server-side
-- (rather than only in the client) means every entry point - the current
-- submit_catch_return_for_reservation RPC, the legacy insert_catch_return
-- RPC still granted to anon, and any future direct write - is covered, not
-- just whichever client happens to be in use.
--
-- Three rules, enforced here:
--   a) A catch return cannot have guest = true and dnf = true together.
--   b) A NEW guest catch return cannot be entered until the host member's
--      own (non-guest) catch return already exists for that reservation.
--   c) Marking the host member's own catch return as DNF (insert or edit)
--      deletes any guest catch returns already logged against that same
--      reservation - a guest can't have fished a beat the host didn't.

-- 0. Clean up any existing rows that would violate the new CHECK constraint
-- below. Shouldn't exist under normal use, but the client-side bug this
-- migration is a response to could have produced a guest+dnf=true row
-- before now (a DNF tick made during a guest edit silently reset "Guest?"
-- to false client-side before submission, so in practice no such row was
-- ever sent - this is a safety net, not an expected no-op).
UPDATE private.catch_returns_staging_table
SET dnf = false
WHERE guest = true AND dnf = true;

-- 1. Rule (a): guest and dnf are mutually exclusive, enforced at the table
-- level so it holds regardless of which function/path writes the row.
ALTER TABLE private.catch_returns_staging_table
DROP CONSTRAINT IF EXISTS chk_guest_dnf_mutually_exclusive;

ALTER TABLE private.catch_returns_staging_table
ADD CONSTRAINT chk_guest_dnf_mutually_exclusive CHECK (NOT (guest AND dnf));

-- 2. Rule (c): whenever a non-guest row is inserted/updated as DNF, delete
-- any guest rows logged against that same rod_name/catch_date/beat. A
-- table-level trigger (rather than duplicating this in every submit_*
-- function) means it also covers the legacy insert_catch_return RPC and any
-- other write path, present or future.
CREATE OR REPLACE FUNCTION private.cascade_delete_guest_catches_on_dnf()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
    IF NEW.guest = false AND NEW.dnf = true THEN
        DELETE FROM private.catch_returns_staging_table
        WHERE rod_name   = NEW.rod_name
          AND catch_date = NEW.catch_date
          AND beat       = NEW.beat
          AND guest      = true;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_cascade_delete_guest_catches_on_dnf ON private.catch_returns_staging_table;

CREATE TRIGGER trg_cascade_delete_guest_catches_on_dnf
AFTER INSERT OR UPDATE ON private.catch_returns_staging_table
FOR EACH ROW
EXECUTE FUNCTION private.cascade_delete_guest_catches_on_dnf();

-- 3. Rule (a) + (b): friendly, early rejection in the client-facing RPC
-- (the CHECK constraint and trigger above are the real backstop - these
-- give a clear error message instead of a raw constraint-violation string).
-- Signature is unchanged from the 20260802103000 migration, so CREATE OR
-- REPLACE is sufficient here.
CREATE OR REPLACE FUNCTION public.submit_catch_return_for_reservation(
    p_password     text,
    p_surname      text,
    p_catch_date   date,
    p_beat         text,
    p_guest        boolean DEFAULT false,
    p_dnf          boolean DEFAULT false,
    p_bt_released  integer DEFAULT 0,
    p_grayling     integer DEFAULT 0,
    p_rainbow      integer DEFAULT 0,
    p_other        integer DEFAULT 0,
    p_bt_retained  integer DEFAULT 0,
    p_comments     text DEFAULT ''::text,
    p_id           integer DEFAULT NULL
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
    v_own_cr_exists      boolean;
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
    WHERE cr_name ILIKE p_surname
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

    -- Rule (b): a NEW guest catch return (p_id IS NULL - editing an existing
    -- one by id is unaffected) can't be entered until the host member's own
    -- catch return already exists for this reservation.
    IF p_guest AND p_id IS NULL THEN
        SELECT EXISTS (
            SELECT 1
            FROM private.catch_returns_staging_table
            WHERE rod_name   = canonical_name
              AND catch_date = p_catch_date
              AND beat       = p_beat
              AND guest      = false
        ) INTO v_own_cr_exists;

        IF NOT v_own_cr_exists THEN
            RAISE EXCEPTION 'Enter your own catch return for this reservation before adding one for a guest.';
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
        brown_trout_retained, comments
    ) VALUES (
        NOW()::text, canonical_name, p_catch_date, p_beat, p_dnf, p_guest,
        p_bt_released, p_grayling, p_rainbow, p_other, p_bt_retained, p_comments
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

GRANT EXECUTE ON FUNCTION public.submit_catch_return_for_reservation(text, text, date, text, boolean, boolean, integer, integer, integer, integer, integer, text, integer) TO anon;
