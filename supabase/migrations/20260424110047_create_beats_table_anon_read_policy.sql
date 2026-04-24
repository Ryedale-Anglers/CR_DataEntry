-- 2. Create the policy to allow read-only access for anonymous users
CREATE POLICY "Allow anon read access to beats" 
ON "public"."beats"
FOR SELECT 
TO anon 
USING (true);