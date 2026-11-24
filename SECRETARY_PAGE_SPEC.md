# Secretary Page: Requirements

Status: agreed, 24 November 2026.

## Purpose

At the end of the 2026 trout season the secretary reminded members about missing catch returns by hand. For each member listed in the in-season compliance report, he logged in to the catch return page as that member, took a screenshot of their reservations and pasted it into an email.

This page replaces that process. A small number of signed-in board members can view the compliance report and send reminder emails in a few clicks.

## Users and access

- **Accounts:** the secretary, Brian, and possibly one or two other board members, such as the chair.
- **Sign-in:** each person has their own email address and password, separate from the club password.
- **Permissions:** all accounts can do everything on the page.
- **Creating accounts:** Brian adds people from the Supabase dashboard by sending them an invitation email. There is no public sign-up.
- **Password management:**
  - **Forgotten password:** a reset link is emailed to the account's address.
  - **Change password:** a signed-in user can change their own password. The page always asks for a code emailed to the account's address. Supabase itself only checks that code when the user signed in more than about 24 hours ago, so within that time the change relies on the signed-in session. Accepted on 24 November 2026: misusing it needs an unlocked, signed-in browser, which could send emails anyway.
  - **Minimum length:** 12 characters, enforced by Supabase as well as the page.

## Functions

### 1. Compliance report

- **Online report:** shows the same content as the in-season compliance report v2:
  - The season and reporting period, from 1 April to yesterday.
  - **Catch return status by member:** reservations, member returns, guest only, did not fish and missing for each member, with totals. Sorted by missing returns, then member name.
  - **Members with no reservations:** member name, CR name and email address. Included as in the PDF, but these members are never emailed.
- **Download PDF:** uses the browser's print-to-PDF, with a print layout styled like the current report. An exact copy of the Typst PDF is not required.

### 2. Reminder emails

- **Who is reminded:** only members with **missing** returns. A guest-only return does not count as missing.
- **Threshold:** the user sets "at least N missing returns". It starts at 1, and the last value used is remembered.
- **Recipient list:**
  - Shows every member at or above the threshold, with their number of missing returns, all ticked by default.
  - The user can untick individual members.
  - Members with no email address are shown but cannot be ticked.
  - The date each member was last reminded is shown.
- **Message text:** typed on the page and remembered between visits.
- **Each email contains:**
  1. A subject and heading of "Missing catch returns: <member name>", using the name as stored, for example "B Pundyke".
  2. The message text, with a general greeting such as "Dear Member". There is no per-member name placeholder, because the members table has no first names.
  3. A table of **only that member's missing returns**, showing the date and beat for each.
  4. A link to the catch return page.
- **No replies:** emails come from a no-reply address and say that replies are not read.
- **Preview:** the user can preview one member's email before sending.
- **Sending:**
  - The user confirms how many emails are about to be sent.
  - The page shows the progress and the result for each member.
  - The server recalculates each recipient's missing returns and checks the threshold again before sending, so the page cannot email anyone outside the rules.

### 3. Email log

- **What is logged:** every batch of emails started from this page, including when it was sent, who started it, the threshold, the message text, and each recipient with their number of missing returns and whether delivery succeeded or failed.
- **What is shown:** the log for the current season.
- **Repeat sends:** not blocked. The log and the "last reminded" dates make them visible.

## Remembered settings

The threshold and message text are stored in the database rather than the browser, so they follow the user to any device. They are shared by all accounts, so one person's last message is the next person's starting point.

## Security

- **Signed-in access only:** report data includes member email addresses, so it is available only to signed-in accounts on the allowed list. The anonymous key used by the public pages cannot read it.
- **Email sending:** the reminder edge function checks the caller is a signed-in, allowed user. The Resend key and service role key stay server-side.
- **Password emails:** sign-in, reset and invitation emails are sent through Resend, because Supabase's built-in email sender is only suitable for testing.

## Hosting

The page is published on github.io with the other pages, for example as `secretary.html`. Like `index.html`, it switches to the local database when run locally.

## Local testing

- **No emails to real members:** the local database holds real member addresses, so locally every email, including password emails, goes to Supabase's local test mailbox (Mailpit) instead of Resend.
- **Local networking fix:** before testing, local edge functions must be able to reach the local database. In November 2026 they could not, because the edge runtime starts on a different Docker network from the rest of the stack.
- **Order:** changes are applied and tested locally before going to production, as with the November security changes.

## Out of scope

- Emails to members with no reservations.
- Changing reservations or catch returns from this page.
- Scheduled or automatic sending. A person always starts each batch.
