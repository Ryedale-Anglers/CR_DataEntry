# Local test plan: reservation-first catch return flow

Final local checks before the production cutover, in which:

- `index_supabase.html` replaces `index.html`;
- `etl_reservations_only_to_supabase.py` replaces `etl_catch_returns_and_reservations_to_supabase.py` in the GitHub Action;
- the held migration `20260929120000` goes to production.

Everything here runs against the **local** Supabase only.

Members pick a reservation from their own list, then choose one of three actions:

| Button | Mode | Database function |
|---|---|---|
| Enter Catch Return | a | `submit_catch_return_for_reservation` |
| Fished a Different Beat | b | `submit_catch_return_different_beat` |
| Enter Catch Return for Reservation Not Listed | c | `submit_catch_return_no_reservation` |

---

## 1. Setup

### 1.1 Refresh local from production (recommended)

Run `rac_reports.py` option 6, or `./sync_prod_to_local.sh`. This gives you current production data, but it also removes the `ZZ Test` member and any migrations applied to local by hand. If you skip this step, local already has everything below as of 15 Oct 2026.

### 1.2 Apply the pending migrations, in this order

Local migration tracking is out of date, so apply these with `psql`, not `supabase migration up`:

```bash
cd /home/brian/Documents/github/CR_DataEntry
DB=postgresql://postgres:postgres@localhost:54322/postgres
for f in supabase/.migrations_on_hold/20260929120000_enforce_guest_dnf_rules_and_cascade_delete.sql \
         supabase/migrations/20261015100000_shared_beat_synthetic_and_date_beat_validation.sql \
         supabase/migrations/20261015110000_revoke_anon_season_history_and_exact_surname_match.sql \
         supabase/migrations/20261015120000_create_start_new_season.sql \
         supabase/migrations/20261016100000_season_history_shared_beat_and_season_end.sql; do
  psql "$DB" -v ON_ERROR_STOP=1 -q -f "$f" && echo "applied $f"
done
```

Each file is safe to apply again.

Check they're in place. Expect `t | t | f | t`:

```sql
SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_guest_dnf_mutually_exclusive'),
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_cascade_delete_guest_catches_on_dnf'),
       has_function_privilege('anon', 'public.get_member_season_history(text)', 'EXECUTE'),
       to_regprocedure('private.start_new_season(integer)') IS NOT NULL;
```

### 1.3 Test member and reservations

The test member is `ZZ Test`, and the login surname is `ZZ Test`. The password is the club password: after a refresh, local holds production's club password.

The season is 1 April to 30 September 2026 (`private.year_param`). Every seeded date below is inside it.

```sql
INSERT INTO private.members (cr_name, member_name, email_address, year_of_membership)
VALUES ('ZZ Test', 'Zephyr Test', 'zztest@example.local', 2026)
ON CONFLICT (cr_name, year_of_membership) DO NOTHING;

INSERT INTO private.reservations_confirmed_staging (date, resource, name, cr_name) VALUES
  ('2026-09-01', '02. Abbey Beat',      'Zephyr Test', 'ZZ Test'),  -- A1-A9: own, guest, DNF
  ('2026-09-02', '05. Mill Weir',       'Zephyr Test', 'ZZ Test'),  -- B1: fished a different beat
  ('2026-09-03', '08. Fairyland',       'Zephyr Test', 'ZZ Test'),  -- A10: DNF on a fresh reservation
  ('2026-09-04', '01. Greencliff Beat', 'Zephyr Test', 'ZZ Test'),  -- B2: divert to the shared beat...
  ('2026-09-04', '18. Railway Bridge',  'Zephyr Test', 'ZZ Test'),  -- ...already booked on 18
  ('2026-09-05', '17. Fishing Hut',     'Zephyr Test', 'ZZ Test'),  -- R2: both resources booked
  ('2026-09-05', '18. Railway Bridge',  'Zephyr Test', 'ZZ Test'),
  ('2026-09-07', '18. Railway Bridge',  'Zephyr Test', 'ZZ Test');  -- C4: "not listed" on the shared beat
```

### 1.4 Serve the page

```bash
cd /home/brian/Documents/github/CR_DataEntry && python3 -m http.server 8000
# browse to http://localhost:8000/index_supabase.html
```

Never open the file directly (`file://…`). With no hostname, the page connects to **production**. The badge under the club name must read **LOCAL** (yellow) on every screen.

### 1.5 State query

Run this whenever a test says **Check state**:

```sql
SELECT catch_date, beat, guest, dnf, brown_trout_released AS bt, comments, id
FROM private.catch_returns_staging_table WHERE rod_name = 'ZZ Test'
ORDER BY catch_date, beat, guest, id;

SELECT date, resource, name
FROM private.reservations_confirmed_staging WHERE cr_name = 'ZZ Test'
ORDER BY date, resource;
```

---

## 2. Login

| # | Do | Expect |
|---|---|---|
| L1 | `ZZ Test` and the correct password | Reservation list appears |
| L2 | `ZZ Test` and a wrong password | "Incorrect club password" |
| L3 | `Nobody` and the correct password | "Member surname not recognised" |
| L4 | `%`, then `ZZ_Test`, each with the correct password | Both rejected: wildcards no longer match |
| L5 | `zz test` (lower case) and the correct password | Accepted |

## 3. Reservation list

| # | Check | Expect |
|---|---|---|
| R1 | Order and paging | Newest first. Five rows, then **Show More** reveals the rest. Every row reads "Awaiting Catch Return". |
| R2 | 5 Sep, booked on both 17 and 18 | **One** row: "Fishing Hut & Railway Bridge, 2026-09-05" |
| R3 | Buttons before and after selecting a row | Both buttons disabled until a row is selected |

## 4. Mode a: Enter Catch Return

Work through these in order. They all use the **1 Sep Abbey** reservation except A10.

**A1. Own catch on a fresh reservation.** Select 1 Sep Abbey → **Enter Catch Return**.
- Expect: no "Which Catch Return?" chooser. The heading reads **Enter Your Catch Return** and the catch section **Your Catch Return**. Date and beat are locked, there's no Guest? box, and **Did Not Fish** is shown.
- Enter BT 2 → Submit → review → Confirm.
- Expect: the row reads "Catch Return Logged" and the button label becomes "Edit Your / Add Guest Catch Return".
- Check state: one row, guest false, dnf false, bt 2.

**A2. Edit own catch.** Select 1 Sep → the chooser lists "Your Catch Return — submitted … BT: 2 …" and "+ Add a New Guest Catch". Pick your catch return.
- Expect: the heading reads **Edit Your Catch Return**, the form is pre-filled, there's no guest notice and no Guest? box.
- Change BT to 3 → Confirm.
- Check state: still **one** non-guest row, bt 3.

**A3. Add a guest catch.** Select 1 Sep → **+ Add a New Guest Catch**.
- Expect: the heading reads **Add Guest Catch Return**, with the yellow notice "Adding a catch return for **your guest** on Abbey, 2026-09-01. Your own catch return is not changed." The catch section reads **Guest's Catch**, the button **Submit Guest Catch Return**, and Did Not Fish is **hidden**.
- Enter BT 1 → the review is titled **Review Guest Catch Return** and shows "Guest: Yes" → Confirm.
- Expect: the row shows "1 Guest Catch Logged".

**A4. Edit the guest catch.** Select 1 Sep → the chooser lists the guest catch by its submission time. Pick it.
- Expect: the heading reads **Edit Guest Catch Return**, the notice names the guest catch's submission time, and the form is pre-filled with BT 1. Change BT to 4 → the review shows "Guest: Yes (editing previous entry)" → Confirm.
- Check state: still one guest row, **same id** as before, bt 4.

**A5. Second guest.** Repeat A3 with BT 5.
- Expect: "2 Guest Catches Logged".

**A6. Host marks DNF, which deletes the guest catches.** Select 1 Sep → your catch return → type "test comment" in Observations.
- Tick **Did Not Fish**, then untick it. Expect: the catch numbers come back as they were (BT 3), not zeros.
- Tick **Did Not Fish** again. Expect: the catch section collapses, but **Observations stays visible** with "test comment" in it.
- Submit. Expect: the review shows **"⚠ This will also delete 2 guest catches…"** and "Observations: test comment".
- Confirm.
- Expect: the row reads "Did Not Fish Logged" and has no guest badge.
- Check state: the own row has dnf true, bt 0 and comments "test comment", and there are **no** guest rows.

**A7. No guests after a host DNF.** Select 1 Sep.
- Expect: the chooser offers **only** "Your Catch Return — … Did Not Fish", with the message "Your catch return is marked Did Not Fish, so a guest catch can't be added…". There is no "+ Add a New Guest Catch".

**A8. Undo the DNF.** Pick your catch return → untick Did Not Fish → BT 1 → Confirm.
- Then select 1 Sep again. Expect: "+ Add a New Guest Catch" is offered again.

**A9. Cancel leaves the list unchanged.** Select 1 Sep → **Cancel** in the chooser.
- Expect: you're still on the list with nothing changed. Also check **← Back to Reservations** from the form.

**A10. DNF on a fresh reservation.** Select 3 Sep Fairyland → tick Did Not Fish.
- Expect: the Observations placeholder reads "Reason for not fishing (optional)". Type "river in flood".
- Expect: the review has **no** guest-deletion warning and shows "Observations: river in flood". Confirm.
- Expect: the row reads "Did Not Fish Logged".

## 5. Mode b: Fished a Different Beat

**B1. Normal divert.** Select 2 Sep Mill Weir → **Fished a Different Beat**.
- Expect: the heading reads **Fished a Different Beat** and the notice "Marking Mill Weir on 2026-09-02 as Did Not Fish…". The beat list has **Mill Weir greyed out**, and Did Not Fish and Guest? are hidden.
- Pick Duncombe Park, BT 2 → the review shows "Diverted from: Mill Weir … will be marked Did Not Fish" → Confirm.
- Check state:
  - Mill Weir 2 Sep: dnf true, comment "Auto-marked DNF: member fished a different beat".
  - Duncombe Park 2 Sep: bt 2.
  - A new **Synthetic** reservation on `06. Duncombe Park`.
- Expect the list to show both rows: Mill Weir as DNF and Duncombe Park as Logged.

**B2. Divert onto the shared beat when 18 is already booked.** Select 4 Sep Greencliffe → Fished a Different Beat → Fishing Hut & Railway Bridge, BT 1 → Confirm.
- Check state: Greencliffe 4 Sep is DNF. On 4 Sep there is **no** Synthetic reservation; the existing `18. Railway Bridge` booking covers it.
- Expect: the list shows one Fishing Hut & Railway Bridge row for 4 Sep, Logged.

## 6. Mode c: Reservation Not Listed

**C1. Future dates blocked.** Expect the heading **Reservation Not Listed**. In the date picker, try tomorrow's date.
- Expect: it can't be picked, or Submit is blocked with "Value must be … or earlier".

**C2. Out-of-season dates rejected.** Use 2026-10-05, Abbey, BT 1 → Confirm.
- Expect: "Database error: Catch date 2026-10-05 is outside the season (2026-04-01 to 2026-09-30)".
- Repeat with 2026-03-20: same error.

**C3. Valid date with no booking.** Use 2026-09-10, Upper Harome, BT 3 → Confirm.
- Check state: the catch is recorded, plus a **Synthetic** reservation on `14. Upper Harome`.
- Expect: 10 Sep Upper Harome appears in the list, Logged.
- Then select it → **+ Add a New Guest Catch** → BT 1 → Confirm. Guest catches work on Synthetic reservations too.

**C4. Shared beat that's actually booked.** Use 2026-09-07, Fishing Hut & Railway Bridge, BT 2 → Confirm.
- Check state: **no** Synthetic reservation on 7 Sep; the `18. Railway Bridge` booking covers it.
- Expect: one 7 Sep row, Logged.

**C5. DNF with no booking.** Use 2026-09-11, The Cut, tick Did Not Fish → Confirm.
- Check state: a DNF row, plus a Synthetic reservation on `10. The Cut`.

## 7. Email My Returns YTD

Point the test member at your own address first, so a real email can't go to anyone else:

```sql
UPDATE private.members SET email_address = '<your address>' WHERE cr_name = 'ZZ Test';
```

**E1.** Click **Email My Returns YTD**.
- Expect: "Success! Your catch history has been emailed to you", and an email listing ZZ Test's reservations and catches from sections 4–6.
- This also confirms the email still works now that the history function is restricted to the service role.
- Check the email lists 5 Sep (booked on both 17 and 18) **once** per catch return, and nothing after 30 September.
- If you get a connection error, the local edge runtime may not have the Resend key. Run `supabase functions serve --env-file supabase/functions/.env` in another terminal and try again.

## 8. Server rules the page no longer lets you reach (SQL)

These confirm the database enforces the rules even without the page. Run them as one block in `psql`. Set the password first; the block is rolled back at the end.

```sql
\set pw '<club password>'
BEGIN;
-- S1: guest catch while the host's own return is DNF (3 Sep Fairyland, from A10)
SAVEPOINT s; SELECT public.submit_catch_return_for_reservation(:'pw','ZZ Test','2026-09-03','Fairyland',true,false,1); ROLLBACK TO s;
-- S2: guest catch marked DNF
SAVEPOINT s; SELECT public.submit_catch_return_for_reservation(:'pw','ZZ Test','2026-09-01','Abbey',true,true); ROLLBACK TO s;
-- S3: diverting to the reserved beat itself
SAVEPOINT s; SELECT public.submit_catch_return_different_beat(:'pw','ZZ Test','Abbey','2026-09-01','Abbey'); ROLLBACK TO s;
-- S4: guest and dnf both true, written directly (bypassing the functions)
SAVEPOINT s; UPDATE private.catch_returns_staging_table SET dnf = true WHERE rod_name = 'ZZ Test' AND guest; ROLLBACK TO s;
-- S5: season history as the public (anon) role
SAVEPOINT s; SET LOCAL ROLE anon; SELECT count(*) FROM public.get_member_season_history('%'); ROLLBACK TO s;
ROLLBACK;
```

Expect, in order:
1. "Enter your own catch return (not Did Not Fish)…"
2. "A guest catch return cannot be marked Did Not Fish."
3. "The beat you fished is the beat you reserved…"
4. A violation of `chk_guest_dnf_mutually_exclusive`. This needs at least one guest row, from A8/C3.
5. "permission denied for function get_member_season_history".

## 9. Reservations ETL against local

Both runs contact ibookfishing, but only read from it. They write **only** to local, because of `ETL_ENV=local`.

**T1. A failure exits with an error code.** Point the download at a dead address:

```bash
ETL_ENV=local LOCAL_DB_URL=postgresql://postgres:postgres@localhost:54322/postgres \
IBOOKFISHING_REPORT_PAGE_URL=http://127.0.0.1:9 venv/bin/python etl_reservations_only_to_supabase.py; echo "exit code $?"
```

Expect "Network error…", then "No data received from download.", then **exit code 1**.

**T2. A real run keeps Synthetic reservations.** First remove ZZ Test's seeded bookings. They aren't on ibookfishing, so the ETL would treat them as cancellations:

```sql
DELETE FROM private.reservations_confirmed_staging WHERE cr_name = 'ZZ Test' AND name <> 'Synthetic';
```

Then run the ETL:

```bash
ETL_ENV=local LOCAL_DB_URL=postgresql://postgres:postgres@localhost:54322/postgres \
venv/bin/python etl_reservations_only_to_supabase.py; echo "exit code $?"
```

- Expect "✅ All steps completed." and exit code 0. Any "deleting:" lines should be real cancellations made since the local copy was taken.
- If it stops with "… reservations would be deleted (limit 10)", read the "would delete" list. If those are genuine cancellations, re-run with `ETL_MAX_DELETIONS=50`.
- Check state: the Synthetic reservations from B1, C3 and C5 are **still there**.

## 10. Optional: reports

Run `rac_reports.py` option 2 (in-season compliance) against **local**. ZZ Test's figures should agree with the state query. Return the member to an empty state afterwards (section 11), so it doesn't skew any later local report.

---

## 11. Reset and teardown

**Reset** (keeps the member, ready to re-seed with section 1.3):

```sql
DELETE FROM private.catch_returns_staging_table WHERE rod_name = 'ZZ Test';
DELETE FROM private.reservations_confirmed_staging WHERE cr_name = 'ZZ Test';
```

**Teardown** (when finished):

```sql
DELETE FROM private.catch_returns_staging_table WHERE rod_name = 'ZZ Test';
DELETE FROM private.reservations_confirmed_staging WHERE cr_name = 'ZZ Test';
DELETE FROM private.members WHERE cr_name = 'ZZ Test';
```

## 12. Sign-off

- [ ] Setup check (1.2) returns `t | t | f | t`
- [ ] L1–L5 login
- [ ] R1–R3 reservation list
- [ ] A1–A10 own, guest and DNF flows, including the guest cascade (A6) and the block after a DNF (A7)
- [ ] B1–B2 fished a different beat
- [ ] C1–C5 reservation not listed
- [ ] E1 email
- [ ] S1–S5 server rules
- [ ] T1–T2 ETL
- [ ] Teardown done

Once every box is ticked, the system is ready for the cutover runbook:

1. Run the old ETL one last time.
2. Swap in the new `index.html` and the workflow, and remove `rac_reports.py` option 4.
3. Move the held migration into `migrations/`, then run `supabase db push --include-all`.
4. Merge Develop into main.
5. Run the new GitHub Action once by hand.
