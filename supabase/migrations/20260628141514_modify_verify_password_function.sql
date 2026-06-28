CREATE OR REPLACE FUNCTION public.verify_club_password(entered_password text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    correct BOOLEAN;
BEGIN
    SELECT (value_hash = crypt(entered_password, value_hash))
    INTO correct
    FROM private.club_settings
    WHERE key = 'shared_catch_password';
    
    RETURN COALESCE(correct, FALSE);
END;
$function$
;