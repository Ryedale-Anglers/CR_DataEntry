-- 2. Create a policy that allows anonymous read access
CREATE POLICY "Allow public read access" 
ON reservations_confirmed_staging 
FOR SELECT 
TO anon 
USING (true);

create or replace view "public"."view_reservations_confirmed_staging" as  
SELECT rcs.date,
    rcs.cr_name,
    rb.beat_id,
    bt.beat,
    bt.river_order
   FROM ((public.reservations_confirmed_staging rcs
     JOIN public.reservation_beats rb ON ((rb.beat = rcs.resource)))
     JOIN public.beats bt ON ((rb.beat_id = bt.id)))
  ORDER BY rcs.date;