import { createClient } from "@supabase/supabase-js";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { surname, clubPassword } = await req.json();

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Step 1: validate password + surname, get member email and canonical name
    const { data: memberRows, error: memberError } = await supabaseAdmin
      .rpc('get_member_info_for_email', {
        p_surname:  surname,
        p_password: clubPassword,
      });

    if (memberError) {
      const msg = memberError.message ?? '';
      if (msg.includes('Invalid club password')) {
        return new Response(JSON.stringify({ error: 'Incorrect club password' }), {
          status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }
      throw new Error(msg);
    }

    if (!memberRows || memberRows.length === 0) {
      return new Response(JSON.stringify({ error: 'Member surname not recognised' }), {
        status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const { email_address, cr_name } = memberRows[0];

    // Step 2: fetch season history (reservations + catch returns)
    const { data: history, error: historyError } = await supabaseAdmin
      .rpc('get_member_season_history', { p_surname: surname });

    if (historyError) throw new Error(historyError.message);

    // --- Build email HTML ---

    const thStyle = [
      'border: 1px solid #999',
      'padding: 6px 8px',
      'background-color: #4a7c59',
      'color: white',
      'font-weight: bold',
      'text-align: left',
    ].join(';');

    const tdStyle = [
      'border: 1px solid #999',
      'padding: 6px 8px',
      'vertical-align: top',
    ].join(';');

    const tdCentreStyle = tdStyle + ';text-align:center';

    const headerRow = `
      <tr>
        <th style="${thStyle};white-space:nowrap">Date</th>
        <th style="${thStyle};min-width:140px">Beat</th>
        <th style="${thStyle};width:60px;text-align:center">BT Released</th>
        <th style="${thStyle};width:60px;text-align:center">Grayling</th>
        <th style="${thStyle};min-width:160px">Comments</th>
      </tr>`;

    const tableRows = (history && history.length > 0)
      ? history.map((row: {
          res_date: string;
          beat: string;
          bt_released: number | null;
          grayling: number | null;
          comments: string | null;
          dnf: boolean | null;
          guest: boolean | null;
        }) => {
          const dateStr = row.res_date;
          const beat = row.beat ?? '';
          const guestLabel = row.guest ? ' <em style="color:#888;font-size:0.85em">(guest)</em>' : '';

          if (row.dnf === true) {
            return `<tr>
              <td style="${tdStyle};white-space:nowrap">${dateStr}</td>
              <td style="${tdStyle}">${beat}${guestLabel}</td>
              <td colspan="3" style="${tdStyle};color:#888;font-style:italic">Did Not Fish</td>
            </tr>`;
          }

          const noCatchReturn = row.bt_released === null && row.grayling === null && row.comments === null;
          if (noCatchReturn) {
            return `<tr>
              <td style="${tdStyle};white-space:nowrap">${dateStr}</td>
              <td style="${tdStyle}">${beat}${guestLabel}</td>
              <td colspan="3" style="${tdStyle};color:red;font-style:italic">Catch Return Due...</td>
            </tr>`;
          }

          return `<tr>
            <td style="${tdStyle};white-space:nowrap">${dateStr}</td>
            <td style="${tdStyle}">${beat}${guestLabel}</td>
            <td style="${tdCentreStyle}">${row.bt_released ?? 0}</td>
            <td style="${tdCentreStyle}">${row.grayling ?? 0}</td>
            <td style="${tdStyle}">${row.comments ?? ''}</td>
          </tr>`;
        }).join('')
      : `<tr><td colspan="5" style="${tdStyle}">No reservations found for this season.</td></tr>`;

    const htmlBody = `
      <html>
        <body style="font-family:sans-serif;font-size:0.9em">
          <h3 style="color:#4a7c59">Ryedale Anglers Club</h3>
          <h4>Reservations &amp; Catch Returns — ${cr_name}</h4>
          <table style="border-collapse:collapse;width:100%;font-size:0.85em">
            <thead>${headerRow}</thead>
            <tbody>${tableRows}</tbody>
          </table>
          <p style="color:#888;font-size:0.8em;margin-top:16px">
            This email was generated on request. Catch returns highlighted in red are outstanding.
          </p>
        </body>
      </html>`;

    // --- Send via Resend ---
    // TODO: update 'from' to your verified sender once set up in Resend dashboard
    //       e.g. "Ryedale Anglers <secretary@ryedaleanglers.co.uk>"
    //       or   "Ryedale Anglers <yourname@gmail.com>"  (after Gmail address is verified in Resend)
    const emailPayload = {
      from: "Ryedale Anglers <onboarding@resend.dev>",
      // TODO: switch to email_address once 'from' sender is verified
      to: ["delivered@resend.dev"],
      // to: [email_address],
      subject: `RAC Reservations & Catch Returns — ${cr_name}`,
      html: htmlBody,
    };

    const apiResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${Deno.env.get("RESEND_API_KEY")!}`,
      },
      body: JSON.stringify(emailPayload),
    });

    if (!apiResponse.ok) {
      const errorText = await apiResponse.text();
      throw new Error(`Resend rejected: ${errorText}`);
    }

    return new Response(
      JSON.stringify({ message: `Email sent to ${email_address}` }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    );

  } catch (error) {
    const errMsg = error instanceof Error ? error.message : String(error);
    console.error("Function error:", errMsg);
    return new Response(JSON.stringify({ error: errMsg }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    });
  }
});
