-- Fixes from the November 2026 security adviser review.
--
-- DEPLOY ORDER FOR PRODUCTION: publish index.html first, because this migration
-- drops validate_member_surname, which the previous login page calls.
--
-- 1. get_member_info_for_email returns a member's email address. Its only
--    caller is the send_Res_CR_history_email edge function, which uses the
--    service role, so the public roles lose access.
--
-- 2. validate_member_surname let anyone with the public key test whether a
--    surname belongs to a current member, without the club password. Login now
--    uses get_member_reservations, which checks the password first.
--
-- 3. Catch return comments are public, so they may no longer contain web links
--    or HTML tags. A lone "<" or ">" is still allowed (e.g. "<1lb"). The
--    pages and email also escape comments when displaying them.
--
-- 4. private.members had a leftover anon read policy and full table privileges
--    for authenticated. Neither is needed: access is through SECURITY DEFINER
--    functions and the service role.

REVOKE EXECUTE ON FUNCTION public.get_member_info_for_email(text, text)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_member_info_for_email(text, text) TO service_role;

DROP FUNCTION public.validate_member_surname(text);

-- Keep this pattern in step with COMMENT_LINK_PATTERN in index.html.
ALTER TABLE private.catch_returns_staging_table
    ADD CONSTRAINT chk_comments_no_links_or_html CHECK (
        comments IS NULL
        OR comments !~* '[a-z][a-z0-9+.-]*://|\mwww\.|<[a-z/!?]|\m[a-z0-9-]+\.(com|org|net|uk|io|info|biz|ru|xyz|ly)\M'
    );

DROP POLICY "Allow anon read access to members table" ON private.members;
REVOKE ALL ON TABLE private.members FROM anon, authenticated;
