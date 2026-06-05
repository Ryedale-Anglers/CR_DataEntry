-- Drop the trigger first
DROP TRIGGER trg_check_reservation_on_catch_insert 
ON public.catch_returns_staging_table;

-- Then drop the function
DROP FUNCTION public.check_and_insert_reservation();