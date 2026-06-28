CREATE OR REPLACE FUNCTION public.get_private_beats_anon_data()
RETURNS TABLE (
    id          integer,
    beat        text,
    river_order text
)
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT id, beat, river_order
    FROM private.beats
    WHERE id != 18
    ORDER BY river_order ASC;
$$;

GRANT EXECUTE ON FUNCTION public.get_private_beats_anon_data() TO anon;