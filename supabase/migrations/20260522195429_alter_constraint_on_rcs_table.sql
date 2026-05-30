ALTER TABLE public.reservations_confirmed_staging
  DROP CONSTRAINT uq_reservation_date_cr_name,
  ADD CONSTRAINT uq_reservation_date_cr_name UNIQUE (date, cr_name, resource);