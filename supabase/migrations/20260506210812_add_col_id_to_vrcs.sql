CREATE OR REPLACE VIEW public.view_reservations_confirmed_staging
AS SELECT rcs.date,
    rcs.cr_name,
    rb.beat_id,
    bt.beat,
    bt.river_order,
    rcs.id
   FROM reservations_confirmed_staging rcs
     JOIN reservation_beats rb ON rb.beat = rcs.resource
     JOIN beats bt ON rb.beat_id = bt.id
  ORDER BY rcs.date;