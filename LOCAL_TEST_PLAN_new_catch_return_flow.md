# Test plan: new direct-to-Supabase catch return flow (local dev)

Covers the transition from the old batch ETL (`etl_catch_returns_and_reservations_to_supabase.py`)
to the new flow: `index_supabase.html` → Postgres RPCs → `private.catch_returns_staging_table` /
`private.reservations_confirmed_staging`, with reservations still synced by
`etl_reservations_only_to_supabase.py`.

## ⚠️ Before you start: local vs production

`index_supabase.html` picks its Supabase target from `window.location.hostname`. If you open the
file directly (`file:///.../index_supabase.html`), the hostname is **empty**, which fails every
`isLocal` check and silently points the page at **production**. Always serve it over HTTP:

```bash
cd /home/brian/Documents/github/CR_DataEntry
python3 -m http.server 8000
# then browse to http://localhost:8000/index_supabase.html
```

Confirm the badge under the club name reads **LOCAL** (yellow) before entering any test data.

## Fixture already in place

- Local Supabase is running (`supabase status`).
- Local club password confirmed as `1846`.
- Test member inserted: `cr_name = 'ZZ Test'`, `year_of_membership = 2026` (id 655). Use this for
  every scenario below so test data never mixes with real members. Login surname: `ZZ Test`.
  Inserted with:
  ```sql
  INSERT INTO private.members (cr_name, member_name, email_address, year_of_membership)
  VALUES ('ZZ Test', 'Zephyr Test', 'zztest@example.local', 2026)
  ON CONFLICT (cr_name, year_of_membership) DO NOTHING;
  ```
- Season window (`private.year_param`): 2026-04-01 to 2026-09-30.

**Reset between test passes** — clears the transient test data (catch returns + reservations)
but keeps the `ZZ Test` member row in place, so you can run TC1–TC9 again from a clean slate
without re-creating the fixture:

```sql
DELETE FROM private.catch_returns_staging_table WHERE rod_name = 'ZZ Test';
DELETE FROM private.reservations_confirmed_staging WHERE cr_name = 'ZZ Test';
```

**Full teardown** — only once you're completely finished with this test plan. This also removes
the member row, so TC1 onward won't work again until it's re-inserted:

```sql
DELETE FROM private.catch_returns_staging_table WHERE rod_name = 'ZZ Test';
DELETE FROM private.reservations_confirmed_staging WHERE cr_name = 'ZZ Test';
DELETE FROM private.members WHERE cr_name = 'ZZ Test' AND year_of_membership = 2026;
```

If you've already run the full teardown and want to test again, re-create the fixture first:

```sql
INSERT INTO private.members (cr_name, member_name, email_address, year_of_membership)
VALUES ('ZZ Test', 'Zephyr Test', 'zztest@example.local', 2026)
ON CONFLICT (cr_name, year_of_membership) DO NOTHING;
```

---

## Issues found during review — all three fixed, TC8/TC9/TC3a/TC3b confirm the fixes hold

### Finding 1 (medium, fixed): editing/overwriting your own catch return spuriously re-triggers "No Reservation Found"

`get_outstanding_reservations` excludes any reservation that already has a matching
`catch_returns_staging_table` row (any dnf value) for that member/date/beat. That's correct for
finding *unfulfilled* reservations, but the client also uses this same list to decide whether the
date/beat just entered is an "exact match" to a real reservation. Once a catch return already
exists for a reservation (i.e. you're editing/overwriting), that reservation drops off the list,
so `exactMatch` is always `null` on a re-submit — even though the original match was legitimate.
Reproduced in **TC8** below. Effect is a confusing extra prompt on every edit; worst case is an
unnecessary duplicate `Synthetic` row (harmless, deduped by `ON CONFLICT DO NOTHING`) or the member
picking the wrong item from the list.

### Finding 2 (high, fixed): a `Synthetic` reservation collides with the real one once it syncs, breaking the whole daily reservation ETL

Confirmed directly against the local DB:

```
ERROR:  duplicate key value violates unique constraint "uq_priv_reservation_date_cr_name"
DETAIL:  Key (date, cr_name, resource)=(2026-07-20, TESTMEMBER, 02. Abbey Beat) already exists.
```

Sequence: a member submits a catch return for a reservation made too recently to have synced yet
→ `insert_catch_return` creates a `Synthetic` placeholder row (`date, resource, name='Synthetic',
cr_name`). Later, `etl_reservations_only_to_supabase.py` downloads the now-real reservation and
inserts it with `cr_name = NULL` (fine, NULL never collides). But
`match_and_update_reservation_names` then tries to `UPDATE ... SET cr_name = 'X'` on that new row —
and that collides with the `Synthetic` row already sitting on the same
`(date, cr_name, resource)` key. Because both statements run inside one `engine.begin()`
transaction, this exception rolls back **the entire day's reservation sync**, not just this one
row — and it will keep failing on every subsequent run until someone manually deletes/fixes the
colliding `Synthetic` row. This is exactly the "last-minute reservation" scenario you were
already worried about earlier. Reproduced in **TC9** below (pure SQL, no UI needed).

### Finding 3 (medium, fixed): self-declared DNF had no reservation validation at all

Found while reviewing TC3, not during initial testing. The DNF checkbox is a genuinely new
capability — grepping every old HTML/JS file in this repo for "dnf" turns up nothing outside
`index_supabase.html`. Historically DNF was *only* ever computed automatically
(`insert_dnf_for_beat_mismatch`) when a real reservation existed but the catch return went to a
different beat — never a freeform member claim. The original implementation of the new DNF
checkbox skipped reservation matching entirely (`if (!isGuest && !isDnf)` gated the whole
resolution block), so a member could submit a DNF for a beat/date they'd never reserved. Fixed by
adding a DNF-specific resolution path that requires a real reservation match, offers a picker
against the member's actual outstanding reservations if the typed beat/date doesn't match, and
blocks the submission outright if the member has no reservations at all to mark as not fished
(deliberately no "I had no reservation" escape valve, unlike the non-DNF flow). See **TC3**,
**TC3a**, **TC3b**.

---

## Happy-path scenarios

### TC1 — Non-guest, exact reservation match
```sql
INSERT INTO private.reservations_confirmed_staging (date, resource, name, cr_name)
VALUES ('2026-07-25', '02. Abbey Beat', 'ZZ Test', 'ZZ Test');
```
UI: login `ZZ Test` / `1846` → Date `2026-07-25`, Beat `Abbey`, not guest, not DNF, enter some
catch numbers → Submit.
**Expect:** goes straight to the review modal — no duplicate dialog, no reservation dialog.
Confirm.
**Verify:**
```sql
SELECT * FROM private.catch_returns_staging_table
WHERE rod_name='ZZ Test' AND catch_date='2026-07-25' AND beat='Abbey';
```
One row, values match, `dnf=false`, `guest=false`.

### TC2 — Guest catch return
UI: check **Guest?**, use a date/beat with no reservation at all (e.g. `2026-07-26` / `Mill Weir`)
→ Submit.
**Expect:** no duplicate check, no reservation dialog (both are skipped for guests) — straight to
review.
**Verify:** row inserted with `guest=true`. Submit a second guest entry for the *same*
date/beat/name — it should **not** be blocked (the unique index only applies when `guest=false`).

### TC3 — Self-declared DNF, exact reservation match
Setup:
```sql
INSERT INTO private.reservations_confirmed_staging (date, resource, name, cr_name)
VALUES ('2026-07-26', '01. Greencliff Beat', 'ZZ Test', 'ZZ Test');
```
UI: check **Did Not Fish**, date `2026-07-26`, beat `Greencliffe` (matches the reservation above)
→ Submit.
**Expect:** straight to review → confirm. A DNF against a real reservation needs no extra dialog.
**Verify:** row with `dnf=true`, all catch numbers 0, `beat='Greencliffe'`.

### TC3a — Self-declared DNF, no reservation at all this season
UI: check **Did Not Fish**, pick a beat/date with no reservation at all for this member (e.g.
`2026-07-26` / `Sewage Farm`) → Submit.
**Expect:** "Which Reservation?" dialog appears with a radio list containing exactly **one**
option — **"I'm sure I reserved this — not synced yet"** — plus Cancel. Note the DNF dialog does
*not* offer "I did not have a reservation for this" at all — that wording would contradict
submitting a DNF in the first place. Select the radio, **Continue**.
**Expect after Continue:** straight to review → confirm.
**Verify:**
```sql
SELECT * FROM private.catch_returns_staging_table WHERE rod_name='ZZ Test' AND beat='Sewage Farm';
SELECT * FROM private.reservations_confirmed_staging WHERE cr_name='ZZ Test' AND date='2026-07-26';
```
One catch return row (`dnf=true`), and a new `Synthetic` reservation row for the same date/beat —
selecting the option self-attests a reservation the system doesn't know about yet and creates a
Synthetic placeholder to back the DNF, rather than leaving the DNF with nothing behind it at all.

### TC3b — Self-declared DNF, wrong beat/date typed but the real reservation is listed
Reuse the TC3 Greencliffe/2026-07-26 reservation if still outstanding (otherwise seed a fresh one,
e.g. `2026-07-29` / `03. Hollins Wood`).
UI: check **Did Not Fish**, type a *different*, unreserved beat/date (e.g. `2026-07-29` /
`Duncombe Park`) → Submit.
**Expect:** "Which Reservation?" dialog lists the real outstanding reservation(s) *plus*
"I'm sure I reserved this — not synced yet" as one more radio option — select the **real**
reservation, Continue.
**Expect after Continue:** form corrects to the chosen beat/date and proceeds to review showing
the corrected values, not what was originally typed.
**Verify:** catch return row exists for the *chosen* reservation's beat/date with `dnf=true`, not
for the originally-typed beat/date. No Synthetic row created (a real reservation already existed).

### TC3c — Self-declared DNF, other reservations exist but none apply (self-attested)
Same setup as TC3b (a real outstanding reservation exists for something else).
UI: check **Did Not Fish**, type a *third*, unrelated beat/date that has no reservation at all →
Submit.
**Expect:** dialog lists the real reservation(s) plus "I'm sure I reserved this — not synced yet" —
select the **self-attest** option this time, Continue.
**Expect after Continue:** straight to review for the *originally typed* beat/date → confirm.
**Verify:** catch return row for the originally-typed beat/date (`dnf=true`); new `Synthetic`
reservation row for that same beat/date; the other real reservation from setup is untouched and
still outstanding.

### TC4 — No reservation at all this season → Synthetic created
UI: non-guest, non-DNF, date `2026-07-27`, beat `Greencliffe` → Submit.
**Expect:** "No Matching Reservation" dialog with a radio list containing exactly **two**
options — "I did not have a reservation for this" (genuine walk-up, no booking ever made) and
"I'm sure I reserved this — not synced yet" (booking exists but hasn't synced) — plus Cancel.
Unlike the DNF dialog, the non-DNF flow keeps both, since either is a legitimate real-world case
for a normal catch. Select **"I did not have a reservation for this"**, Continue → review →
confirm.
**Verify:**
```sql
SELECT * FROM private.reservations_confirmed_staging
WHERE cr_name='ZZ Test' AND date='2026-07-27';
```
New row, `name='Synthetic'`, resource mapped from Greencliffe.

### TC4a — Same as TC4, but via the "not synced yet" option
UI: non-guest, non-DNF, date `2026-07-27`, beat `Duncombe Park` (fresh beat/date, no reservation)
→ Submit → dialog appears → this time select **"I'm sure I reserved this — not synced yet"**,
Continue → review → confirm.
**Expect/Verify:** identical outcome to TC4 (Synthetic row created) — this option resolves through
the same code path as "I did not have a reservation for this," just with different wording for the
member's benefit; confirming here that both labels genuinely produce the same result.

### TC5 — Other outstanding reservations exist, but none match → self-attest
Setup:
```sql
INSERT INTO private.reservations_confirmed_staging (date, resource, name, cr_name)
VALUES ('2026-07-28', '08. Fairyland', 'ZZ Test', 'ZZ Test');
```
UI: non-guest, non-DNF, date `2026-08-01`, beat `Duncombe Park` (unrelated to the Fairyland
reservation) → Submit.
**Expect:** "No Matching Reservation" dialog lists the Fairyland/2026-07-28 reservation *plus*
both self-attest options — select either one, Continue → review → confirm.
**Verify:** Synthetic row created for Duncombe Park/2026-08-01; Fairyland/2026-07-28 reservation
still shows up in `get_outstanding_reservations` afterward (untouched).

### TC5a — Fulfilled reservations must not appear in the picker list
`get_outstanding_reservations` excludes any reservation that already has a matching catch return
(this is what Finding 1 and TC3b's "if still outstanding" caveat both lean on) — this test makes
that exclusion an explicit, deliberate assertion rather than an incidental side effect of test
ordering. Both the DNF and non-DNF pickers call this same RPC, so proving it once here covers both.

Setup — one reservation that's already fulfilled, one that's genuinely outstanding:
```sql
INSERT INTO private.reservations_confirmed_staging (date, resource, name, cr_name)
VALUES ('2026-08-10', '16. Lower Harome', 'ZZ Test', 'ZZ Test'),
       ('2026-08-11', '08. Fairyland', 'ZZ Test', 'ZZ Test');

INSERT INTO private.catch_returns_staging_table
    (timestamp, rod_name, catch_date, beat, dnf, guest, brown_trout_released, grayling, rainbow_trout, other_species, brown_trout_retained, comments)
VALUES (now()::text, 'ZZ Test', '2026-08-10', 'Lower Harome', false, false, 1, 0, 0, 0, 0, 'fulfills Lower Harome for TC5a');
```
UI: non-guest, non-DNF, date `2026-08-12`, beat `Duncombe Park` (unrelated to either reservation
above) → Submit.
**Expect:** "No Matching Reservation" dialog's radio list contains **only** Fairyland/2026-08-11
(the outstanding one) alongside the two self-attest options — **Lower Harome/2026-08-10 must not
appear**, since it already has a catch return against it.
**Verify:** if Lower Harome shows up in the list, that's a regression — `get_outstanding_reservations`
should be excluding it. No DB verification needed beyond confirming the dialog contents visually;
cancel out of the dialog once confirmed rather than completing the submission.

### TC6 — Mistyped entry, corrected to the real reservation
Reuse the still-unused Fairyland/2026-07-28 reservation from TC5.
UI: non-guest, non-DNF, date `2026-07-28` but beat `Duncombe Park` (wrong beat, right date) →
Submit. Dialog lists Fairyland/2026-07-28 plus the self-attest option → select **Fairyland**,
Continue → "Did You Mean This?" → **Yes, correct my entry**.
**Expect:** form's beat field flips to Fairyland, resolution re-runs from scratch, now finds an
exact match → straight to review showing **Fairyland**, not Duncombe Park → confirm.
**Verify:** catch return row exists for Fairyland/2026-07-28; no Synthetic row created; no
Duncombe Park row at all.

### TC7 — Wrong-beat correction (fished elsewhere, reserved beat auto-DNF'd)
Setup:
```sql
INSERT INTO private.reservations_confirmed_staging (date, resource, name, cr_name)
VALUES ('2026-08-02', '03. Hollins Wood', 'ZZ Test', 'ZZ Test');
```
UI: non-guest, non-DNF, date `2026-08-02`, beat `Duncombe Park` (a real beat, but not the one
reserved) → Submit. Dialog lists Hollins Wood/2026-08-02 plus the self-attest option → select
**Hollins Wood**, Continue → "Did You Mean This?" → **No, I fished something else**.
**Expect:** proceeds to review for the *originally entered* Duncombe Park/2026-08-02 → confirm.
**Verify:**
```sql
SELECT rod_name, catch_date, beat, dnf, comments FROM private.catch_returns_staging_table
WHERE rod_name='ZZ Test' AND catch_date='2026-08-02';
```
Two rows: Duncombe Park (`dnf=false`, real catch data) and Hollins Wood (`dnf=true`,
`comments='Auto-marked DNF: member fished a different beat/date'`). Also confirm a Synthetic
reservation now exists for Duncombe Park/2026-08-02.

### TC8 — Overwrite own record (reproduces Finding 1)
Reuse TC1's Abbey/2026-07-25 record.
UI: submit again for the same date/beat with different catch numbers.
**Expect (per current design intent):** "Existing Record Found" dialog → Overwrite → straight to
review.
**Actual (bug):** immediately after Overwrite, a "No Reservation Found" / "No Matching
Reservation" dialog appears too, even though this reservation was already resolved in TC1. Safe to
click through either option — worst case is a redundant `Synthetic` row (deduped) — but note this
confirms Finding 1. Verify the catch numbers were updated via:
```sql
SELECT * FROM private.catch_returns_staging_table
WHERE rod_name='ZZ Test' AND catch_date='2026-07-25' AND beat='Abbey';
```
Still exactly one row (UPSERT via `ON CONFLICT ... DO UPDATE`), with the new numbers.

### TC9 — Synthetic/real reservation collision (reproduces Finding 2, SQL only)
No UI needed — this is the same repro already run during review:
```sql
BEGIN;
INSERT INTO private.reservations_confirmed_staging (date, resource, name, cr_name)
VALUES ('2026-08-05', '02. Abbey Beat', 'Synthetic', 'ZZ Test');

INSERT INTO private.reservations_confirmed_staging (date, resource, name, cr_name)
VALUES ('2026-08-05', '02. Abbey Beat', 'Zz Test', NULL);

UPDATE private.reservations_confirmed_staging
SET cr_name = 'ZZ Test'
WHERE date = '2026-08-05' AND resource = '02. Abbey Beat' AND name = 'Zz Test';
ROLLBACK;
```
**Expect:** the `UPDATE` fails with `duplicate key value violates unique constraint
"uq_priv_reservation_date_cr_name"`. That confirms Finding 2 — this is what would happen for real
the next time `etl_reservations_only_to_supabase.py` runs after a same-day Synthetic reservation
was created for a booking that hadn't synced yet.

Optional deeper check: point `etl_reservations_only_to_supabase.py` at `LOCAL_DB_URL` instead of
`CLOUD_DB_URL` (temporarily, in `.env` or a copy of it) after leaving TC4's real Synthetic row in
place with a colliding real reservation seeded, and run the script for real to see the Python-level
exception and confirm the whole run aborts.

---

## After testing

All three findings are fixed locally (migration `20260725120000_fix_reservation_match_ux_and_collision.sql`
plus the ETL and `index_supabase.html` changes). Once TC1–TC9 (including TC3a/TC3b, TC8, TC9) all
pass against the local DB, remaining before production cutover:
- Push the migration to production.
- Switch the scheduled ETL job from `etl_catch_returns_and_reservations_to_supabase.py` to
  `etl_reservations_only_to_supabase.py` (see [[project_etl_scheduling]] / the systemd timer) —
  must happen at or before cutover, not after, per the earlier discussion.
