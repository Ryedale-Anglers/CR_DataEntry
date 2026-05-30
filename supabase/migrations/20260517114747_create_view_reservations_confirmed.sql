create view view_reservations_confirmed as 
select rc.date, m.cr_name, b.beat, b.beat_short  from reservations_confirmed rc
inner join private.members m on rc.members_id = m.id
inner join beats b on rc.beats_id = b.id
order by date asc