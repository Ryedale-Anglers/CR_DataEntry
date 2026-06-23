CREATE OR REPLACE FUNCTION private.append_catch_returns_from_cr_staging_table()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    INSERT INTO private.catch_returns (
        member_name, 
        catch_date, 
        brown_trout, 
        brown_trout_killed, 
        grayling, 
        rainbow_trout, 
        other_species, 
        guest, 
        beats_id, 
        dnf
    )
    SELECT 
        crst.rod_name, 
        crst.catch_date, 
        crst.brown_trout_released, 
        crst.brown_trout_retained, 
        crst.grayling, 
        crst.rainbow_trout, 
        crst.other_species, 
        crst.guest, 
        b.id, 
        crst.dnf
    FROM public.catch_returns_staging_table crst
    INNER JOIN public.beats b ON crst.beat = b.beat
    -- Matches the exact columns and WHERE clause of your partial index:
    ON CONFLICT (member_name, catch_date, beats_id) WHERE (guest = false) DO NOTHING;

END;
$function$
;