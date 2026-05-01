-- 2. Create the policy to allow read-only access for anonymous users
CREATE POLICY "Allow anon read access to members table" 
ON "public"."members"
FOR SELECT 
TO anon 
USING (true);