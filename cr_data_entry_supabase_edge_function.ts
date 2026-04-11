import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req) => {
  const { member_name, activity_date, club_secret } = await req.json()

  // 1. Initialize Supabase
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  // 2. The "Member List" Check (The replica of your Google Sheet check)
  const { data: member, error: memberError } = await supabase
    .from('members_list')
    .select('id')
    .eq('name', member_name)
    .maybeSingle() // Returns null if not found, instead of an error

  if (!member) {
    return new Response(
      JSON.stringify({ error: "Sorry, that name isn't on the official member list." }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    )
  }

  // 3. If they passed the check, Insert the new record
  const { error: insertError } = await supabase
    .from('activity_log')
    .insert([{ member_id: member.id, activity_date }])

  if (insertError) {
    return new Response(insertError.message, { status: 500 })
  }

  return new Response(JSON.stringify({ success: true }), {
    headers: { "Content-Type": "application/json" },
  })
})