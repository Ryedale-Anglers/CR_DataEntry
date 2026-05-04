//import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
//import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
// Replace the old URL or "std/server" imports with these:
//import { serve } from "@std/http";
import { createClient } from "@supabase/supabase-js";
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { surname } = await req.json()
    //console.log(`Searching for: [${surname}]`);

    const url = "http://172.17.0.1:54321" 
    //get the key from a .env file
    //const key = 
    const supabaseAdmin = createClient(url, key)

    const { data: member, error: _memberError } = await supabaseAdmin
      .from('members')
      .select('email_address, cr_name')
      .ilike('cr_name', surname)
      .maybeSingle();

    if (!member) {
      return new Response(JSON.stringify({ error: `No member found` }), { status: 404, headers: corsHeaders });
    }

    const { data: catches, error: _catchError } = await supabaseAdmin
      .from('view_members_reserv_and_cr_history')
      .select('*')
      .ilike('cr_name', surname)
      .order('date', { ascending: false })

    const tableRows = catches?.length
  ? catches.map(row => {
      const catchDue = row.brown_trout === null && row.grayling === null && row.comments === null;
      if (catchDue) {
        return `<tr>
          <td style="white-space: nowrap;">${row.date}</td>
          <td>${row.beat}</td>
          <td colspan="3" style="color: red; font-style: italic;">Catch Return Due...</td>
        </tr>`;
      }
      return `<tr>
        <td style="white-space: nowrap;">${row.date}</td>
        <td>${row.beat}</td>
        <td>${row.brown_trout ?? ''}</td>
        <td>${row.grayling ?? ''}</td>
        <td>${row.comments ?? ''}</td>
      </tr>`;
    }).join('')
  : '<tr><td colspan="5">No records</td></tr>';

const tableStyle = `
  border-collapse: collapse;
  font-size: 0.85em;
  font-family: sans-serif;
  width: 100%;
`;

const thStyle = `
  border: 1px solid #999;
  padding: 6px 8px;
  background-color: #4a7c59;
  color: white;
  font-weight: bold;
  text-align: left;
`;

const headerRow = `
  <thead>
    <tr>
      <th style="${thStyle} white-space: nowrap;">Date</th>
      <th style="${thStyle} min-width: 140px;">Name</th>
      <th style="${thStyle} width: 40px; text-align: center;">Brown Trout</th>
      <th style="${thStyle} width: 40px; text-align: center;">Grayling</th>
      <th style="${thStyle} min-width: 160px;">Comments</th>
    </tr>
  </thead>
`;

// Inject td styles via a <style> block to avoid repetition on every cell
const styleBlock = `
  <style>
    .catches-table td {
      border: 1px solid #999;
      padding: 6px 8px;
      vertical-align: top;
      word-wrap: break-word;
      overflow-wrap: break-word;
    }
    .catches-table td:nth-child(3),
    .catches-table td:nth-child(4) {
      text-align: center;
      width: 40px;
    }
    .catches-table td:nth-child(5) {
      min-width: 160px;
      max-width: 300px;
    }
  </style>
`;

const htmlBody = `
  <html>
    <body>
      ${styleBlock}
      <h3>Reservations & Catch Returns for ${member.cr_name}</h3>
      <table class="catches-table" style="${tableStyle}">
        ${headerRow}
        <tbody>
          ${tableRows}
        </tbody>
      </table>
    </body>
  </html>
`;

    // --- INTERNAL SMTP CONNECT ---
    // --- VERBOSE LOGGING & MAILPIT SEND ---
    const MAILPIT_API_URL = "http://supabase_inbucket_CR_DataEntry:8025/api/v1/send";

    // 1. Log the raw member object again to be 100% sure
    //console.log("[DEBUG] Raw Member Object:", JSON.stringify(member));

    // --- THE FINAL (FOR REAL THIS TIME) PAYLOAD ---
    const emailPayload = {
      From: { 
        Name: "Ryedale Anglers", 
        Email: "records@ryedaleanglers.co.uk" // Changed from Address to Email
      },
      To: [{ 
        Name: member.cr_name || "Member", 
        Email: member.email_address // Already matched to your previous success
      }],
      Subject: "Catch History",
      HTML: htmlBody,
    };

    //console.log(`[DEBUG] Final delivery attempt for: ${member.email_address}`);

    try {
      const apiResponse = await fetch(MAILPIT_API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(emailPayload),
      });

      if (!apiResponse.ok) {
        const errorText = await apiResponse.text();
        throw new Error(`Mailpit rejected: ${errorText}`);
      }

      //console.log("[DEBUG] SUCCESS! Check http://127.0.0.1:54324");

      return new Response(
        JSON.stringify({ message: 'Email delivered to Mailpit' }), 
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      );

} catch (apiErr) {
      const msg = apiErr instanceof Error ? apiErr.message : "Unknown API Error";
      throw new Error(`MAILPIT_API_FAILURE: ${msg}`);
    }

  } catch (error) {
    const errMsg = error instanceof Error ? error.message : String(error);
    console.error("Function Error:", errMsg);
    return new Response(JSON.stringify({ error: errMsg }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})