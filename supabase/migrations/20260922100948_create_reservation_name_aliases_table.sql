CREATE TABLE private.reservation_name_aliases (
    booking_name text PRIMARY KEY,   -- exactly as iBookFishing sends it, stored UPPER
    cr_name      text NOT NULL       -- must equal the cr_name in view_member_names
);
