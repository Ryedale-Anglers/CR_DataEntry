-- Create a table for club settings
CREATE TABLE club_settings (
    id SERIAL PRIMARY KEY,
    key TEXT UNIQUE NOT NULL,
    value_hash TEXT NOT NULL
);

-- Insert your shared password (pre-hashed using pgcrypto)
-- This example uses 'fishing2024' as the password
CREATE EXTENSION IF NOT EXISTS pgcrypto;

INSERT INTO club_settings (key, value_hash)
VALUES (
    'shared_catch_password', 
    extensions.crypt('CHANGE_ME' /* placeholder - set the real password with an UPDATE, never commit it */, extensions.gen_salt('bf'))
);