# Cutover runbook: new catch return form and reservations-only ETL

Planned for Saturday 17 October 2026, before 12:00.

**Goes live:**
- `index.html` becomes the reservation-first form (developed as `index_supabase.html`).
- The nightly GitHub Action runs `etl_reservations_only_to_supabase.py`.
- Six database migrations are applied to production.

**Already prepared on Develop:**
- commit `26919b8`: the `index.html` swap, the redirect, the workflow change, the held migration moved into `migrations/`;
- the removal of the old pages;
- `rac_reports.py` changes, on RAC_ReportProduction's `Develop` branch.

**The one rule:** once the new form is live, the **old ETL must never run again**. It empties the catch returns table and reloads it from the Google Sheet, which deletes everything entered through the new form.

---

## Part 1: Recreate the GitHub repo (tonight, or first thing before Part 2)

The backup is in `~/Documents/github/backups/CR_DataEntry_20261016/`: a mirror clone, `pull_requests.json` and `settings.txt`. It **contains the club password**, so keep it private and never push it.

1. **Delete** `Ryedale-Anglers/CR_DataEntry`.
   - First check no workflow run is in progress on the Actions tab.
   - Go to <https://github.com/Ryedale-Anglers/CR_DataEntry/settings>, stay on **General**, and scroll to the red **Danger Zone** at the bottom.
   - Click **Delete this repository**, then:
     - click **I want to delete this repository**;
     - click **I have read and understand these effects**;
     - type `Ryedale-Anglers/CR_DataEntry` and click **Delete this repository**.
   - GitHub may ask you to confirm your identity (password, 2FA or passkey).
   - Deleting needs owner or admin rights in the organisation. If the button is missing, you don't have them.
   - The site stops working until step 5 below.
2. **Create** the empty repository.
   - Go to <https://github.com/new> (or **+** → **New repository**) and fill in:
     - **Owner:** **Ryedale-Anglers** (not your personal account);
     - **Name:** `CR_DataEntry` (exact capitalisation);
     - **Visibility:** **Public** (Pages needs it on the free plan);
     - **Template:** none; **README:** off; **.gitignore:** None; **License:** None. The repo must be completely empty.
   - Click **Create repository**, and ignore the "Quick setup" instructions.
3. **Push both branches** (`main` first, so it becomes the default branch):
   ```bash
   cd ~/Documents/github/CR_DataEntry
   git push origin main
   git push origin Develop
   ```
   `main` still holds the old form and old ETL, so nothing changes for members yet.
4. **Re-add all six Actions secrets.** `GOOGLE_SHEETS_ID` is still needed for the old ETL's final run. The `CLOUD_DB_URL` secret takes the **pooler** address, because GitHub's runners have no IPv6. This sets them from `.env` without showing any value, then lists them:
   ```bash
   cd ~/Documents/github/CR_DataEntry && venv/bin/python scripts/set_github_secrets.py
   ```
   To add them by hand instead: Settings → Secrets and variables → Actions → **New repository secret**, once for each of the six.
5. **Turn Pages back on:** Settings → **Pages** → Build and deployment → Source: **Deploy from a branch** → Branch **main**, folder **/ (root)** → **Save**. After a minute or two it shows "Your site is live at …".
6. **Check the Action works:** Actions tab (if a banner asks, enable workflows) → Nightly ETL Job → Run workflow (branch `main`). This is still the old ETL, so it's just a normal nightly load. It must finish green, which proves the secrets are right.
7. **Check the site:** <https://ryedale-anglers.github.io/CR_DataEntry/> shows the **old** form.

If step 6 fails, re-check the secrets, especially that `CLOUD_DB_URL` is the pooler address. Don't start Part 2 until it's green.

---

## Part 2: Cutover (morning, finish before 12:00)

### Before starting
- [ ] Last night's 02:17 run succeeded: `gh run list -R Ryedale-Anglers/CR_DataEntry --workflow schedule.yml --limit 3`
- [ ] The working folder is on `Develop` and clean: `git status`

### Step 1: final run of the old ETL
Actions → Nightly ETL Job → **Run workflow** on `main`. Wait for it to finish green, and note the time. This loads the last catch returns from the Google Sheet.

Keep the gap between this step and Step 3 short. Anything submitted on the old form in between lands in the Google Sheet only (see Step 5).

### Step 2: apply the six migrations
```bash
cd ~/Documents/github/CR_DataEntry
supabase db push --dry-run --include-all
```
Expect exactly these six:
- `20260929120000` (guest/DNF rules, the held one)
- `20261015100000`
- `20261015110000`
- `20261015120000`
- `20261016100000`
- `20261016110000`

Then apply them:
```bash
supabase db push --include-all
```

Check in Supabase Studio (SQL editor) on production. Expect `t | t | f | t`:
```sql
SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_guest_dnf_mutually_exclusive'),
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_cascade_delete_guest_catches_on_dnf'),
       has_function_privilege('anon', 'public.get_member_season_history(text)', 'EXECUTE'),
       to_regprocedure('private.start_new_season(integer)') IS NOT NULL;
```

### Step 3: merge Develop into main (goes live)
```bash
gh pr create -R Ryedale-Anglers/CR_DataEntry --base main --head Develop \
  --title "Cutover: new catch return form and reservations-only ETL" \
  --body "Replaces index.html with the reservation-first form and switches the nightly Action to etl_reservations_only_to_supabase.py."
gh pr merge -R Ryedale-Anglers/CR_DataEntry --merge
```
Then watch Actions → **pages-build-deployment** finish (1–2 minutes).

### Step 4: check the live site
Hard-refresh with Ctrl+Shift+R.
- [ ] <https://ryedale-anglers.github.io/CR_DataEntry/> shows the **new** login, with a green **PRODUCTION** badge.
- [ ] `…/index_supabase.html` redirects to `index.html`.
- [ ] `…/catchreturntest.html` and `…/rac_member_cr_comments.html` return 404.

### Step 5: shut off the old Google Sheet path
- [ ] In Google Apps Script, open the old form's script → Deploy → Manage deployments → **Archive** the web app deployment. Old copies of the form open in browsers can then no longer submit.
- [ ] Look at the Google Sheet for entries timestamped **after** the Step 1 run. Re-enter any through the new form (or ask the member to).

### Step 6: run the new ETL once by hand
Actions → Nightly ETL Job → Run workflow on `main`. The log should show `etl_reservations_only_to_supabase.py`, "reconciled successfully", and "✅ All steps completed", and the run should finish green. A few "deleting:" lines are fine: they're cancellations. If it stops with "… would be deleted (limit 10)", read the list before going any further.

### Step 7: smoke test in production, with your own membership
- [ ] Log in. Your season's reservations are listed, newest first.
- [ ] Email My Returns YTD: the email arrives and lists your season once per booking.
- [ ] Only submit a catch return if it's a genuine one. There's no test member in production.

### Step 8: tell members
The same web address and the same club password. They now pick a reservation from their list, and there are buttons for "Fished a Different Beat" and "Reservation Not Listed".

### Afterwards
- [ ] Delete the `GOOGLE_SHEETS_ID` secret (no longer used).
- [ ] Next morning, check the 02:17 run of the new ETL succeeded.
- [ ] RAC_ReportProduction: merge its `Develop` into `main` (option 4 now runs the new ETL; option 7 is new). Until then, **don't use option 4 on main**.
- [ ] Keep the local systemd ETL timer **disabled**. GitHub Actions is the only scheduler.

The old ETL script (`etl_catch_returns_and_reservations_to_supabase.py`) is deleted as part of the cutover, so it can't be run by mistake. It remains in git history. To recover a copy for reference (never to run against production):
```bash
cd ~/Documents/github/CR_DataEntry
git show "$(git log --diff-filter=D --format=%h -1 -- etl_catch_returns_and_reservations_to_supabase.py)^:etl_catch_returns_and_reservations_to_supabase.py" > etl_catch_returns_and_reservations_to_supabase.py
```

---

## If something goes wrong after Step 3

- **The form misbehaves:** restore only the old form by putting the previous `index.html` back on `main`:
  ```bash
  git checkout main && git pull
  git checkout main~1 -- index.html   # the old Google Sheet form
  git commit -m "Temporarily restore old form" && git push origin main
  ```
  Then re-deploy the Apps Script web app so the old form can submit again.
- **Never** switch the workflow back to `etl_catch_returns_and_reservations_to_supabase.py`, and never run it, after Step 3. Keep the new ETL running in any rollback.
- **The migrations need undoing:** don't. They only add rules and functions, and the old form doesn't use the database directly. Leave them in place and fix forward.
