drop view public.view_member_reservations_activity;
CREATE OR REPLACE VIEW public.view_member_reservations_activity AS 
SELECT 
    m.cr_name,
    m.member_name, -- Added this to the selection for grouping
    -- Count reservations: Only if they aren't marked as "Did Not Fish"
    COUNT(r.id) FILTER (WHERE c.dnf IS DISTINCT FROM TRUE) as total_reservations,
    -- Count valid catches: Not DNF and Not a Guest
    COUNT(c.id) FILTER (
        WHERE c.dnf IS DISTINCT FROM TRUE 
        AND c.guest IS DISTINCT FROM TRUE
    ) as total_valid_catches
FROM public.view_member_names m
LEFT JOIN view_reservations_confirmed_staging r ON m.cr_name = r.cr_name
LEFT JOIN catch_returns_staging_table c ON r.cr_name = c.rod_name AND r.date = c.catch_date
GROUP BY 
    m.cr_name, 
    m.member_name -- Must include this to use it in ORDER BY
ORDER BY 
    total_reservations DESC, -- Using alias directly (no function wrapper)
    split_part(m.member_name, ' ', array_length(regexp_split_to_array(m.member_name, '\s+'), 1)), 
    regexp_replace(m.member_name, '\s+\S+$', '');