import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async () => {
  const client = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  const now = new Date().toISOString()

  // Find active visitors whose expected_until has passed
  const { data: expired, error: fetchError } = await client
    .from('visitors')
    .select('id')
    .eq('is_active', true)
    .not('expected_until', 'is', null)
    .lt('expected_until', now)

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 })
  }

  if (!expired || expired.length === 0) {
    return new Response(JSON.stringify({ expired: 0 }), { status: 200 })
  }

  const ids = expired.map((v: any) => v.id)
  const { error: updateError } = await client
    .from('visitors')
    .update({ is_active: false })
    .in('id', ids)

  if (updateError) {
    return new Response(JSON.stringify({ error: updateError.message }), { status: 500 })
  }

  return new Response(
    JSON.stringify({ expired: ids.length }),
    { status: 200 }
  )
})
