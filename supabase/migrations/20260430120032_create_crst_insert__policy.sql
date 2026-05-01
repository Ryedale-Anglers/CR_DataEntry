CREATE POLICY "Allow public insert on CRST and Verify member before insert"
ON public.catch_returns_staging_table
FOR INSERT 
TO anon 
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.members
    WHERE members.cr_name ILIKE rod_name
  )
);

ALTER TABLE public.catch_returns_staging_table 
ALTER COLUMN timestamp SET DEFAULT now();