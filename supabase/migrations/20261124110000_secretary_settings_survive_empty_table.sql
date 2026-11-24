-- Secretary page settings: keep working if the single settings row is missing.
--
-- A data-only restore into the local database (sync_prod_to_local.sh, full
-- mode) empties private.secretary_settings when the dump predates the table.
-- sec_save_settings used UPDATE, which then changed nothing, so saving the
-- threshold and message silently did nothing. Saving now creates the row if
-- needed, and reading returns the defaults when it is missing.
--
-- CREATE OR REPLACE keeps the existing grants (authenticated only).

CREATE OR REPLACE FUNCTION public.sec_save_settings(p_min_missing integer, p_message_text text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    PERFORM private.require_secretary();

    INSERT INTO private.secretary_settings (id, min_missing, message_text, updated_at, updated_by)
    VALUES (1, p_min_missing, COALESCE(p_message_text, ''), now(), auth.uid())
    ON CONFLICT (id) DO UPDATE
    SET min_missing  = EXCLUDED.min_missing,
        message_text = EXCLUDED.message_text,
        updated_at   = EXCLUDED.updated_at,
        updated_by   = EXCLUDED.updated_by;
END;
$$;

CREATE OR REPLACE FUNCTION public.sec_get_settings()
RETURNS TABLE (min_missing integer, message_text text,
               updated_at timestamptz, updated_by_email text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    PERFORM private.require_secretary();

    RETURN QUERY
    SELECT COALESCE(s.min_missing, 1), COALESCE(s.message_text, ''), s.updated_at, u.email::text
    FROM (SELECT 1) AS one
    LEFT JOIN private.secretary_settings s ON s.id = 1
    LEFT JOIN auth.users u ON u.id = s.updated_by;
END;
$$;
