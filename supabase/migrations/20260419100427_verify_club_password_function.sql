CREATE OR REPLACE FUNCTION verify_club_password(entered_password TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    correct BOOLEAN;
BEGIN
    SELECT (value_hash = crypt(entered_password, value_hash))
    INTO correct
    FROM club_settings
    WHERE key = 'shared_catch_password';
    
    RETURN COALESCE(correct, FALSE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;