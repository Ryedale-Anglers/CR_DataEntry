# Secretary Page: Technical Plan

Implements [SECRETARY_PAGE_SPEC.md](SECRETARY_PAGE_SPEC.md). Draft, 24 November 2026.

## Overview

| Part | What |
|---|---|
| Sign-in | Supabase Auth with email and password. Invite-only. |
| Access list | `private.secretary_users`: the auth users allowed to use the page. |
| Data | New `sec_*` database functions, callable only by signed-in users on the access list. |
| Sending | New edge function `send_catch_return_reminders`. |
| Page | New `secretary.html` on github.io, with local/production detection like `index.html`. |

## 1. Database (one migration)

### Tables (all in `private`)

| Table | Purpose |
|---|---|
| `secretary_users` | `user_id` (references `auth.users`, deleted with the user), `added_at`. |
| `secretary_settings` | A single row: `min_missing` (default 1), `message_text`, `updated_at`, `updated_by`. Shared by all users. |
| `reminder_batches` | One row per send: `id`, `created_at`, `created_by`, `created_by_email`, `season_year`, `min_missing`, `message_text`, counts of sent and failed. |
| `reminder_recipients` | One row per member in a batch: `batch_id`, `cr_name`, `email_address`, `missing_count`, the missing dates and beats as sent, `status` (sent or failed), `error`, `resend_id`. |

These tables follow the existing pattern: RLS enabled with no policies, no grants to `anon` or `authenticated`, and access only through functions.

### Access check

`private.is_secretary()` returns true when `auth.uid()` is in `secretary_users`. Every `sec_*` function calls it first and raises "Not authorised" otherwise.

### Functions (in `public`, granted to `authenticated` only and revoked from `anon`)

| Function | Returns |
|---|---|
| `sec_am_i_secretary()` | Whether the signed-in user is on the access list, so the page can explain a refusal. |
| `sec_get_report()` | The whole report as JSON: season year, period, report version, status-by-member rows from `view_secrep_membername_catchreturns_count_operational_v2`, and members with no reservations from `view_members_without_season_reservations_v2`. |
| `sec_get_reminder_candidates(p_min_missing)` | Members with at least that many **missing** returns, from `view_reservation_return_status_staging`: `cr_name`, `member_name`, missing count, whether they have an email address, and when they were last reminded this season. |
| `sec_get_member_missing(p_cr_name)` | That member's missing dates and beats, used for the email preview. |
| `sec_get_settings()` and `sec_save_settings(p_min_missing, p_message_text)` | The shared threshold and message. |
| `sec_get_reminder_log()` | The current season's batches and recipients, newest first. |

### Functions for the edge function only (granted to `service_role`)

| Function | Purpose |
|---|---|
| `sec_svc_is_secretary(p_user_id)` | Checks the caller is on the access list. |
| `sec_svc_get_recipients(p_min_missing, p_cr_names)` | The ticked members still at or above the threshold and with an email address, with their missing dates and beats. |
| `sec_svc_start_batch(...)` and `sec_svc_finish_batch(p_batch_id, p_results)` | Write the log. Because only the edge function can call these, the log can't be edited from a browser. |

All functions set `search_path`, which avoids adding to the adviser warnings.

### Adding a user

1. Invite the person from the Supabase dashboard, under Authentication, Users, Invite.
2. Add them to the access list with a small admin-only function, for example `private.add_secretary('chair@example.org')`, run from the SQL editor.

## 2. Edge function `send_catch_return_reminders`

- **Caller check:** the function checks the signed-in user's token itself with Supabase Auth (`auth.getUser`), then checks that the user is on the access list. `verify_jwt` is off because the gateway check only understands the legacy keys, and the project uses the new ones.
- **Input:** `min_missing`, the ticked `cr_names`, `message_text` and an optional `preview_cr_name`.
- **Preview:** returns the rendered email for one member without sending anything.
- **Send:**
  1. Recalculates the candidates on the server and keeps only ticked members who are still at or above the threshold and have an email address.
  2. Creates a `reminder_batches` row.
  3. Sends one email per member, then records each result in `reminder_recipients`.
  4. Returns a per-member result to the page.
- **Email content:**
  - **Subject and heading:** "Missing catch returns: <member_name>", using `member_name` exactly as stored, for example "B Pundyke".
  - **Body:** the shared message text with no placeholders, so the greeting is general, such as "Dear Member". Then a table of that member's missing returns (date and beat), then a link to the catch return page.
  - **Escaping:** names and message text are HTML-escaped, as in the history email.
- **Sender:** a no-reply address on the club's verified Resend domain, such as `Ryedale Anglers <no-reply@ryedaleanglers.org.uk>`, with a line saying replies are not read.
- **Delivery:** uses Resend's batch API, which sends up to 100 emails in one request. 25 emails is well within that.

### Fail-safe email routing

The function only uses Resend when the secret `EMAIL_TRANSPORT=resend` is set, and that is set only in production. Without it, as locally, every email goes to the local Mailpit test mailbox. A missing setting can therefore never email real members from a test database. As a second guard, the function refuses to run at all if `EMAIL_TRANSPORT=resend` is set on a local database.

Locally, the stack's own function runtime only loads functions when the stack starts, so a new or changed function needs `supabase_mgr.sh` option 9 (serve edge functions) running.

## 3. Page `secretary.html`

- **Sign-in screen:** email and password, plus "Forgot password?", which emails a reset link.
- **Password links:** reset and invitation links return to the page, which then asks for a new password.
- **Tabs after sign-in:**
  - **Report:** season header, status-by-member table with totals, members with no reservations, and "Download PDF", which uses `window.print()` with a print stylesheet that hides the page controls.
  - **Reminders:**
    - The threshold and message box, loaded from and saved to the shared settings.
    - The member list with checkboxes and "last reminded" dates. Members without an email address can't be ticked.
    - Preview, then Send with a confirmation and per-member results.
  - **Log:** the current season's batches, each expandable to its recipients and results.
  - **Account:** change password, sign out.
- **Password change verification:** Supabase's "secure password change" setting is turned on, and the page always asks for a code emailed to the account's address. Supabase only checks the code when the session is more than about 24 hours old. This was accepted on 24 November 2026; see the spec.
- **Escaping:** all names, messages and comments are inserted as text, never HTML.

## 4. Local setup and testing

1. **Edge functions on the right network:** serve them with `supabase functions serve --network-id local-network`, and add this as an option in `supabase_mgr.sh`.
2. **Local auth settings in `supabase/config.toml`:** site URL and redirect URLs for `http://localhost:8000/secretary.html`, sign-up disabled, and secure password change on. Local auth emails already go to Mailpit at http://127.0.0.1:54324.
3. **Mailpit transport:** the edge function sends local emails to Mailpit's HTTP send API. Check during the build that the local Mailpit version supports it.
4. **Test accounts:** create local users for Brian and a non-secretary user, to check that non-secretaries are refused.
5. **Test checklist:**
   - Sign-in, wrong password, forgotten password, invitation, and password change with the emailed code.
   - A signed-in user who is not on the access list sees no data.
   - Anonymous calls to every `sec_*` function are refused.
   - The report matches the Python PDF for the same database.
   - Threshold changes, unticking, preview, send to Mailpit, and the log.
   - The threshold and message are remembered after signing out and back in.
   - Members without an email address can't be selected.

## 5. Production setup (Brian, in the Supabase dashboard)

These are dashboard settings rather than migrations:

1. **Auth:** disable sign-ups, set the site URL and redirect URL to the github.io `secretary.html`, and turn on secure password change.
2. **Auth email through Resend:** add Resend as the custom SMTP server, using a Resend API key as the password. Optionally, edit the invite and reset email wording.
3. **Edge function secrets:** set `EMAIL_TRANSPORT=resend`. `RESEND_API_KEY` already exists.
4. **Accounts:** invite each person, then add them to the access list.

### Release order

1. `supabase db push --remote`. This is safe on its own because it only adds things.
2. `supabase functions deploy send_catch_return_reminders`.
3. Publish `secretary.html` by merging to `main`.
4. Complete the dashboard setup and invite users.

## Build stages

1. Local fixes: the edge-function network option and local auth config.
2. Database migration, with SQL tests run locally.
3. Page: sign-in, password flows and the report tab.
4. Edge function, Reminders tab and Log tab.
5. Full local test against the checklist, then production release.
