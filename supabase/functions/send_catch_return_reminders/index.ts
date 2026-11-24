// Catch return reminder emails, called from secretary.html.
//
// Body: { mode: 'preview' | 'send', min_missing, message_text, cr_names?, preview_cr_name? }
//   preview: returns the rendered email for one member and sends nothing.
//   send:    recalculates the recipients on the server, emails each one only
//            their own missing returns, and records the batch in the log.
//
// Email routing is fail-safe: Resend is used only when the secret
// EMAIL_TRANSPORT=resend is set AND this is not a local database. Otherwise
// every email goes to the local Mailpit test mailbox.
import { createClient } from "@supabase/supabase-js";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const IS_LOCAL = /\/\/(kong|localhost|127\.0\.0\.1|host\.docker\.internal)[:/]/.test(SUPABASE_URL + '/');
const USE_RESEND = Deno.env.get('EMAIL_TRANSPORT') === 'resend';
const MAILPIT_SEND_URL = Deno.env.get('MAILPIT_SEND_URL')
  ?? 'http://supabase_inbucket_CR_DataEntry:8025/api/v1/send';
const FROM_NAME = 'Ryedale Anglers';
const FROM_EMAIL = 'no-reply@ryedaleanglers.org.uk';
const CATCH_RETURN_PAGE = Deno.env.get('CATCH_RETURN_PAGE_URL')
  ?? (IS_LOCAL ? 'http://localhost:8000/index.html' : 'https://ryedale-anglers.github.io/CR_DataEntry/');
const MAX_MESSAGE = 5000;
const MAX_MEMBERS = 300;
const RESEND_BATCH = 100;   // Resend's batch API limit per request

type Recipient = {
  cr_name: string; member_name: string | null; email_address: string;
  missing_count: number; missing_returns: { date: string; beat: string }[];
};
type Result = Recipient & { status: 'sent' | 'failed'; error: string | null; provider_id: string | null };

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const escapeHtml = (value: unknown): string =>
  String(value ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

const longDate = (iso: string) =>
  new Date(iso + 'T00:00:00Z').toLocaleDateString('en-GB',
    { weekday: 'short', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });

// ---------------------------------------------------------------- Email content
function renderEmail(r: Recipient, message: string) {
  const name = r.member_name?.trim() || r.cr_name;
  const subject = `Missing catch returns: ${name}`;
  const paragraphs = message.trim().split(/\n\s*\n/).filter(p => p.trim());

  const th = 'border:1px solid #999;padding:6px 8px;background-color:#4a7c59;color:#fff;text-align:left';
  const td = 'border:1px solid #999;padding:6px 8px';
  const rows = r.missing_returns.map(m =>
    `<tr><td style="${td};white-space:nowrap">${escapeHtml(longDate(m.date))}</td><td style="${td}">${escapeHtml(m.beat)}</td></tr>`).join('');

  const html = `<html><body style="font-family:sans-serif;font-size:0.95em;color:#333">
<h3 style="color:#4a7c59;margin-bottom:4px">Ryedale Anglers Club</h3>
<h4 style="margin-top:0">${escapeHtml(subject)}</h4>
${paragraphs.map(p => `<p style="margin:0 0 12px 0">${escapeHtml(p.trim()).replace(/\n/g, '<br>')}</p>`).join('\n')}
<table style="border-collapse:collapse;font-size:0.9em;margin:8px 0 16px 0">
<thead><tr><th style="${th}">Date</th><th style="${th}">Beat</th></tr></thead>
<tbody>${rows}</tbody>
</table>
<p>Submit your catch returns here: <a href="${escapeHtml(CATCH_RETURN_PAGE)}">${escapeHtml(CATCH_RETURN_PAGE)}</a></p>
<p style="color:#888;font-size:0.8em;margin-top:20px">This email was sent from an address that does not receive replies, so please don't reply to it.</p>
</body></html>`;

  const text = [
    'Ryedale Anglers Club', subject, '',
    ...paragraphs.map(p => p.trim() + '\n'),
    'Missing catch returns:',
    ...r.missing_returns.map(m => `  ${longDate(m.date)}  ${m.beat}`), '',
    `Submit your catch returns here: ${CATCH_RETURN_PAGE}`, '',
    "This email was sent from an address that does not receive replies, so please don't reply to it.",
  ].join('\n');

  return { subject, html, text };
}

// ---------------------------------------------------------------- Transports
async function sendViaMailpit(items: { r: Recipient; mail: ReturnType<typeof renderEmail> }[]): Promise<Result[]> {
  const out: Result[] = [];
  for (const { r, mail } of items) {
    try {
      const resp = await fetch(MAILPIT_SEND_URL, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          From: { Email: FROM_EMAIL, Name: FROM_NAME },
          To: [{ Email: r.email_address, Name: r.member_name ?? r.cr_name }],
          Subject: mail.subject, HTML: mail.html, Text: mail.text,
        }),
      });
      const body = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(`Mailpit ${resp.status}: ${JSON.stringify(body).slice(0, 200)}`);
      out.push({ ...r, status: 'sent', error: null, provider_id: body.ID ?? null });
    } catch (e) {
      out.push({ ...r, status: 'failed', error: e instanceof Error ? e.message : String(e), provider_id: null });
    }
  }
  return out;
}

async function sendViaResend(items: { r: Recipient; mail: ReturnType<typeof renderEmail> }[], batchId: number): Promise<Result[]> {
  const out: Result[] = [];
  for (let i = 0; i < items.length; i += RESEND_BATCH) {
    const chunk = items.slice(i, i + RESEND_BATCH);
    try {
      const resp = await fetch('https://api.resend.com/emails/batch', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')!}`,
          // A retried request for the same batch and chunk can't send twice.
          'Idempotency-Key': `reminders-${batchId}-${i}`,
        },
        body: JSON.stringify(chunk.map(({ r, mail }) => ({
          from: `${FROM_NAME} <${FROM_EMAIL}>`, to: [r.email_address],
          subject: mail.subject, html: mail.html, text: mail.text,
        }))),
      });
      const body = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(`Resend ${resp.status}: ${body.message ?? JSON.stringify(body).slice(0, 200)}`);
      const ids: { id: string }[] = body.data ?? [];
      chunk.forEach(({ r }, k) => out.push({ ...r, status: 'sent', error: null, provider_id: ids[k]?.id ?? null }));
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      chunk.forEach(({ r }) => out.push({ ...r, status: 'failed', error: msg, provider_id: null }));
    }
    if (i + RESEND_BATCH < items.length) await new Promise(res => setTimeout(res, 600));   // Resend rate limit
  }
  return out;
}

// ---------------------------------------------------------------- Handler
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  try {
    if (USE_RESEND && IS_LOCAL) {
      return json({ error: 'EMAIL_TRANSPORT=resend is not allowed on a local database.' }, 500);
    }

    const admin = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false, autoRefreshToken: false } });

    // 1. Who is calling? Checked with Supabase Auth, then against the access list.
    const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
    const { data: userData, error: userError } = token
      ? await admin.auth.getUser(token) : { data: { user: null }, error: null };
    const user = userData?.user;
    if (userError || !user) return json({ error: 'Please sign in again.' }, 401);
    const { data: allowed, error: accessError } = await admin.rpc('sec_svc_is_secretary', { p_user_id: user.id });
    if (accessError) throw new Error(accessError.message);
    if (!allowed) return json({ error: 'Not authorised' }, 403);

    // 2. Check the request.
    const body = await req.json().catch(() => null);
    if (!body || typeof body !== 'object') return json({ error: 'Invalid request.' }, 400);
    const mode = body.mode;
    const minMissing = Number(body.min_missing);
    const message = typeof body.message_text === 'string' ? body.message_text : '';
    if (!['preview', 'send'].includes(mode)) return json({ error: 'Invalid mode.' }, 400);
    if (!Number.isInteger(minMissing) || minMissing < 1 || minMissing > 50) {
      return json({ error: 'The threshold must be a whole number from 1 to 50.' }, 400);
    }
    if (message.length > MAX_MESSAGE) return json({ error: `The message must be ${MAX_MESSAGE} characters or fewer.` }, 400);

    // 3. Preview one member's email.
    if (mode === 'preview') {
      const crName = typeof body.preview_cr_name === 'string' ? body.preview_cr_name : '';
      const { data, error } = await admin.rpc('sec_svc_get_recipients', { p_min_missing: 1, p_cr_names: [crName] });
      if (error) throw new Error(error.message);
      const r = (data as Recipient[])[0];
      if (!r) return json({ error: 'This member has no email address or no missing returns.' }, 404);
      return json({ to: r.email_address, ...renderEmail(r, message), transport: USE_RESEND ? 'resend' : 'mailpit' });
    }

    // 4. Send.
    if (!message.trim()) return json({ error: 'Please enter the message text.' }, 400);
    const names: unknown = body.cr_names;
    if (!Array.isArray(names) || names.length === 0 || names.length > MAX_MEMBERS ||
        !names.every(n => typeof n === 'string' && n.length <= 100)) {
      return json({ error: 'Please tick at least one member.' }, 400);
    }
    // Recalculated here, so only ticked members still at or above the
    // threshold, and with an email address, are sent anything.
    const { data: recData, error: recError } = await admin.rpc('sec_svc_get_recipients',
      { p_min_missing: minMissing, p_cr_names: names });
    if (recError) throw new Error(recError.message);
    const recipients = recData as Recipient[];
    if (!recipients.length) {
      return json({ error: 'None of the ticked members currently need a reminder. Refresh the list and try again.' }, 409);
    }
    const included = new Set(recipients.map(r => r.cr_name.toUpperCase()));
    const skipped = (names as string[]).filter(n => !included.has(n.toUpperCase()));

    const { data: batchId, error: batchError } = await admin.rpc('sec_svc_start_batch', {
      p_user_id: user.id, p_user_email: user.email ?? '', p_min_missing: minMissing, p_message_text: message });
    if (batchError) throw new Error(batchError.message);

    const items = recipients.map(r => ({ r, mail: renderEmail(r, message) }));
    let results: Result[] = [];
    try {
      results = USE_RESEND ? await sendViaResend(items, batchId as number) : await sendViaMailpit(items);
    } finally {
      // Anything not attempted (an unexpected error part-way) is logged as failed.
      const done = new Set(results.map(r => r.cr_name));
      const notTried = recipients.filter(r => !done.has(r.cr_name))
        .map(r => ({ ...r, status: 'failed' as const, error: 'Not sent: the send stopped unexpectedly.', provider_id: null }));
      const { error: finishError } = await admin.rpc('sec_svc_finish_batch',
        { p_batch_id: batchId, p_results: [...results, ...notTried] });
      if (finishError) console.error('Could not record the batch results:', finishError.message);
    }

    return json({
      batch_id: batchId,
      transport: USE_RESEND ? 'resend' : 'mailpit',
      sent: results.filter(r => r.status === 'sent').length,
      failed: results.filter(r => r.status === 'failed').length,
      results: results.map(r => ({ cr_name: r.cr_name, member_name: r.member_name, email_address: r.email_address,
                                   missing_count: r.missing_count, status: r.status, error: r.error })),
      skipped,
    });
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error('send_catch_return_reminders:', msg);
    return json({ error: 'Something went wrong: ' + msg }, 500);
  }
});
