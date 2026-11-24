-- Secretary page (SECRETARY_PAGE_SPEC.md, SECRETARY_PAGE_TECH_PLAN.md):
-- access list, shared settings, reminder email log and the functions the
-- page and the send_catch_return_reminders edge function call.
--
-- Access model
--   * sec_* functions: signed-in users on private.secretary_users only.
--   * sec_svc_* functions: service role only (the edge function). The email
--     log can therefore only be written by the edge function.
--   * private.add_secretary / remove_secretary: SQL editor (postgres) only.
-- Every function is SECURITY DEFINER with an empty search_path and fully
-- qualified names.

-- ---------------------------------------------------------------- Tables

CREATE TABLE private.secretary_users (
    user_id  uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    added_at timestamptz NOT NULL DEFAULT now()
);

-- One shared row: the last threshold and message text used by anyone.
CREATE TABLE private.secretary_settings (
    id           integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    min_missing  integer NOT NULL DEFAULT 1 CHECK (min_missing BETWEEN 1 AND 50),
    message_text text    NOT NULL DEFAULT '' CHECK (length(message_text) <= 5000),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    updated_by   uuid REFERENCES auth.users (id) ON DELETE SET NULL
);
INSERT INTO private.secretary_settings (id) VALUES (1);

CREATE TABLE private.reminder_batches (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    created_at       timestamptz NOT NULL DEFAULT now(),
    created_by       uuid REFERENCES auth.users (id) ON DELETE SET NULL,
    created_by_email text    NOT NULL,   -- kept even if the account is deleted
    season_year      integer NOT NULL,
    min_missing      integer NOT NULL,
    message_text     text    NOT NULL,
    completed_at     timestamptz,
    sent_count       integer NOT NULL DEFAULT 0,
    failed_count     integer NOT NULL DEFAULT 0
);

CREATE TABLE private.reminder_recipients (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id        bigint  NOT NULL REFERENCES private.reminder_batches (id) ON DELETE CASCADE,
    cr_name         text    NOT NULL,
    member_name     text,
    email_address   text    NOT NULL,
    missing_count   integer NOT NULL,
    missing_returns jsonb   NOT NULL,    -- [{date, beat}] exactly as listed in the email
    status          text    NOT NULL CHECK (status IN ('sent', 'failed')),
    error           text,
    provider_id     text,                -- Resend (or Mailpit) message id
    recorded_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX reminder_recipients_batch_idx   ON private.reminder_recipients (batch_id);
CREATE INDEX reminder_recipients_cr_name_idx ON private.reminder_recipients (upper(cr_name));

-- Same pattern as the other private tables: RLS on, no policies, no direct
-- access for API roles. Everything goes through the functions below.
ALTER TABLE private.secretary_users     ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.secretary_settings  ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reminder_batches    ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.reminder_recipients ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.secretary_users, private.secretary_settings,
              private.reminder_batches, private.reminder_recipients
    FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------- Internal helpers

CREATE FUNCTION private.is_secretary()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
    SELECT EXISTS (SELECT 1 FROM private.secretary_users WHERE user_id = auth.uid());
$$;

CREATE FUNCTION private.require_secretary()
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF NOT private.is_secretary() THEN
        RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501';
    END IF;
END;
$$;

-- Members with at least p_min_missing missing returns this season, with
-- their missing dates and beats. "Missing" is return_status = 'missing'
-- only (guest-only returns do not count), as in the compliance report.
CREATE FUNCTION private.reminder_candidates(p_min_missing integer)
RETURNS TABLE (cr_name text, member_name text, email_address text,
               missing_count integer, missing_returns jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
    SELECT s.cr_name,
           m.member_name,
           NULLIF(trim(m.email_address), ''),
           count(*)::integer,
           jsonb_agg(jsonb_build_object('date', s.date, 'beat', s.beat) ORDER BY s.date, s.beat)
    FROM private.view_reservation_return_status_staging s
    CROSS JOIN (SELECT target_year FROM private.year_param WHERE id = 1) yp
    LEFT JOIN private.members m
           ON upper(m.cr_name) = upper(s.cr_name)
          AND m.year_of_membership = yp.target_year
    WHERE s.return_status = 'missing'
    GROUP BY s.cr_name, m.member_name, m.email_address
    HAVING count(*) >= GREATEST(COALESCE(p_min_missing, 1), 1);
$$;

-- Run from the SQL editor after inviting the person from the dashboard.
CREATE FUNCTION private.add_secretary(p_email text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_user_id uuid;
BEGIN
    SELECT id INTO v_user_id FROM auth.users WHERE lower(email) = lower(trim(p_email));
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No account for %. Invite them from the dashboard first.', p_email;
    END IF;
    INSERT INTO private.secretary_users (user_id) VALUES (v_user_id) ON CONFLICT DO NOTHING;
    RETURN p_email || ' can now use the secretary page';
END;
$$;

CREATE FUNCTION private.remove_secretary(p_email text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    DELETE FROM private.secretary_users su
    USING auth.users u
    WHERE su.user_id = u.id AND lower(u.email) = lower(trim(p_email));
    RETURN p_email || ' removed from the secretary page (the account itself still exists)';
END;
$$;

-- ------------------------------------------- Page functions (sec_*)

CREATE FUNCTION public.sec_am_i_secretary()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
    SELECT private.is_secretary();
$$;

-- The in-season compliance report v2 as JSON: header, status by member and
-- members with no reservations, matching generate_in_season_compliance_report_v2.py.
CREATE FUNCTION public.sec_get_report()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    v_year    integer;
    v_start   date;
    v_end     date;
    v_version text;
BEGIN
    PERFORM private.require_secretary();

    SELECT target_year, target_start_date, LEAST(target_end_date, CURRENT_DATE - 1)
    INTO v_year, v_start, v_end
    FROM private.year_param WHERE id = 1;

    SELECT report_version INTO v_version
    FROM public.report_versions
    WHERE report_year = v_year::text AND report_type = 'SEC_OPER_V2'
    ORDER BY report_version DESC
    LIMIT 1;

    RETURN jsonb_build_object(
        'season_year',    v_year,
        'period_start',   v_start,
        'period_end',     v_end,
        'report_version', COALESCE(v_version, '1.0'),
        'status_by_member', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'cr_name', v.cr_name, 'reservations_count', v.reservations_count,
                       'member_returns', v.member_returns, 'guest_only', v.guest_only,
                       'dnf', v.dnf, 'missing', v.missing)
                   ORDER BY v.missing DESC, v.reservations_count DESC, v.cr_name)
            FROM private.view_secrep_membername_catchreturns_count_operational_v2 v), '[]'::jsonb),
        'no_reservations', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'member_name', n.member_name, 'cr_name', n.cr_name,
                       'email_address', n.email_address)
                   -- Same surname ordering as the view.
                   ORDER BY upper(CASE
                                      WHEN trim(n.member_name) ~ '^\S\.?\s'
                                          THEN regexp_replace(trim(n.member_name), '^(\S\.?\s+)+', '')
                                      ELSE regexp_replace(trim(n.member_name), '^.*\s', '')
                                  END),
                            n.member_name)
            FROM private.view_members_without_season_reservations_v2 n), '[]'::jsonb)
    );
END;
$$;

CREATE FUNCTION public.sec_get_reminder_candidates(p_min_missing integer)
RETURNS TABLE (cr_name text, member_name text, has_email boolean,
               missing_count integer, last_reminded_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    PERFORM private.require_secretary();

    RETURN QUERY
    SELECT c.cr_name,
           c.member_name,
           c.email_address IS NOT NULL,
           c.missing_count,
           (SELECT max(r.recorded_at)
            FROM private.reminder_recipients r
            JOIN private.reminder_batches b ON b.id = r.batch_id
            WHERE upper(r.cr_name) = upper(c.cr_name)
              AND r.status = 'sent'
              AND b.season_year = (SELECT target_year FROM private.year_param WHERE id = 1))
    FROM private.reminder_candidates(p_min_missing) c
    ORDER BY c.missing_count DESC, c.cr_name;
END;
$$;

-- One member's missing returns, for the email preview.
CREATE FUNCTION public.sec_get_member_missing(p_cr_name text)
RETURNS TABLE (catch_date date, beat text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    PERFORM private.require_secretary();

    RETURN QUERY
    SELECT s.date, s.beat
    FROM private.view_reservation_return_status_staging s
    WHERE upper(s.cr_name) = upper(p_cr_name)
      AND s.return_status = 'missing'
    ORDER BY s.date, s.beat;
END;
$$;

CREATE FUNCTION public.sec_get_settings()
RETURNS TABLE (min_missing integer, message_text text,
               updated_at timestamptz, updated_by_email text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    PERFORM private.require_secretary();

    RETURN QUERY
    SELECT s.min_missing, s.message_text, s.updated_at, u.email::text
    FROM private.secretary_settings s
    LEFT JOIN auth.users u ON u.id = s.updated_by
    WHERE s.id = 1;
END;
$$;

CREATE FUNCTION public.sec_save_settings(p_min_missing integer, p_message_text text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    PERFORM private.require_secretary();

    UPDATE private.secretary_settings
    SET min_missing  = p_min_missing,
        message_text = COALESCE(p_message_text, ''),
        updated_at   = now(),
        updated_by   = auth.uid()
    WHERE id = 1;
END;
$$;

-- The current season's batches, newest first, each with its recipients.
CREATE FUNCTION public.sec_get_reminder_log()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    PERFORM private.require_secretary();

    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                   'id', b.id, 'created_at', b.created_at,
                   'created_by_email', b.created_by_email,
                   'min_missing', b.min_missing, 'message_text', b.message_text,
                   'completed_at', b.completed_at,
                   'sent_count', b.sent_count, 'failed_count', b.failed_count,
                   'recipients', COALESCE((
                       SELECT jsonb_agg(jsonb_build_object(
                                  'cr_name', r.cr_name, 'member_name', r.member_name,
                                  'email_address', r.email_address,
                                  'missing_count', r.missing_count,
                                  'status', r.status, 'error', r.error)
                              ORDER BY r.member_name, r.cr_name)
                       FROM private.reminder_recipients r
                       WHERE r.batch_id = b.id), '[]'::jsonb))
               ORDER BY b.created_at DESC)
        FROM private.reminder_batches b
        WHERE b.season_year = (SELECT target_year FROM private.year_param WHERE id = 1)
    ), '[]'::jsonb);
END;
$$;

-- --------------------------- Edge function functions (sec_svc_*), service role

CREATE FUNCTION public.sec_svc_is_secretary(p_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
    SELECT EXISTS (SELECT 1 FROM private.secretary_users WHERE user_id = p_user_id);
$$;

-- Recalculated server-side at send time: only ticked members who are still
-- at or above the threshold and have an email address.
CREATE FUNCTION public.sec_svc_get_recipients(p_min_missing integer, p_cr_names text[])
RETURNS TABLE (cr_name text, member_name text, email_address text,
               missing_count integer, missing_returns jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
    SELECT c.cr_name, c.member_name, c.email_address, c.missing_count, c.missing_returns
    FROM private.reminder_candidates(p_min_missing) c
    WHERE c.email_address IS NOT NULL
      AND upper(c.cr_name) IN (SELECT upper(x) FROM unnest(p_cr_names) AS x)
    ORDER BY c.member_name, c.cr_name;
$$;

CREATE FUNCTION public.sec_svc_start_batch(p_user_id uuid, p_user_email text,
                                           p_min_missing integer, p_message_text text)
RETURNS bigint
LANGUAGE sql SECURITY DEFINER SET search_path = ''
AS $$
    INSERT INTO private.reminder_batches
        (created_by, created_by_email, season_year, min_missing, message_text)
    SELECT p_user_id, p_user_email, yp.target_year, p_min_missing, COALESCE(p_message_text, '')
    FROM private.year_param yp WHERE yp.id = 1
    RETURNING id;
$$;

-- p_results: [{cr_name, member_name, email_address, missing_count,
--              missing_returns, status, error, provider_id}]
CREATE FUNCTION public.sec_svc_finish_batch(p_batch_id bigint, p_results jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    INSERT INTO private.reminder_recipients
        (batch_id, cr_name, member_name, email_address, missing_count,
         missing_returns, status, error, provider_id)
    SELECT p_batch_id, r.cr_name, r.member_name, r.email_address, r.missing_count,
           COALESCE(r.missing_returns, '[]'::jsonb), r.status, r.error, r.provider_id
    FROM jsonb_to_recordset(p_results) AS r(
        cr_name text, member_name text, email_address text, missing_count integer,
        missing_returns jsonb, status text, error text, provider_id text);

    UPDATE private.reminder_batches b
    SET completed_at = now(),
        sent_count   = (SELECT count(*) FROM private.reminder_recipients
                        WHERE batch_id = b.id AND status = 'sent'),
        failed_count = (SELECT count(*) FROM private.reminder_recipients
                        WHERE batch_id = b.id AND status = 'failed')
    WHERE b.id = p_batch_id;
END;
$$;

-- ------------------------------------------------------------------ Grants
-- New functions are executable by PUBLIC (and, in Supabase, anon and
-- authenticated) by default, so revoke first, then grant what each needs.

REVOKE ALL ON FUNCTION
    private.is_secretary(), private.require_secretary(),
    private.reminder_candidates(integer),
    private.add_secretary(text), private.remove_secretary(text),
    public.sec_am_i_secretary(), public.sec_get_report(),
    public.sec_get_reminder_candidates(integer), public.sec_get_member_missing(text),
    public.sec_get_settings(), public.sec_save_settings(integer, text),
    public.sec_get_reminder_log(),
    public.sec_svc_is_secretary(uuid), public.sec_svc_get_recipients(integer, text[]),
    public.sec_svc_start_batch(uuid, text, integer, text),
    public.sec_svc_finish_batch(bigint, jsonb)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.sec_am_i_secretary(), public.sec_get_report(),
    public.sec_get_reminder_candidates(integer), public.sec_get_member_missing(text),
    public.sec_get_settings(), public.sec_save_settings(integer, text),
    public.sec_get_reminder_log()
TO authenticated;

GRANT EXECUTE ON FUNCTION
    public.sec_svc_is_secretary(uuid), public.sec_svc_get_recipients(integer, text[]),
    public.sec_svc_start_batch(uuid, text, integer, text),
    public.sec_svc_finish_batch(bigint, jsonb)
TO service_role;
