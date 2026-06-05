import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const BUCKET = 'recognition-images'
const DAYS_TO_KEEP = 60

Deno.serve(async () => {
  const client = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  const cutoff = new Date()
  cutoff.setDate(cutoff.getDate() - DAYS_TO_KEEP)
  const cutoffISO = cutoff.toISOString()

  // Get old events with images
  const { data: oldEvents, error: fetchError } = await client
    .from('recognition_events')
    .select('id, image_path')
    .lt('arrived_at', cutoffISO)
    .not('image_path', 'is', null)

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 })
  }

  if (!oldEvents || oldEvents.length === 0) {
    return new Response(JSON.stringify({ deleted: 0 }), { status: 200 })
  }

  // Delete images from storage
  const paths = oldEvents.map((e: any) => e.image_path)
  const { error: storageError } = await client.storage
    .from(BUCKET)
    .remove(paths)

  if (storageError) {
    return new Response(JSON.stringify({ error: storageError.message }), { status: 500 })
  }

  // Clear image_path from events (keep the event record)
  const ids = oldEvents.map((e: any) => e.id)
  await client
    .from('recognition_events')
    .update({ image_path: null })
    .in('id', ids)

  return new Response(
    JSON.stringify({ deleted: paths.length, cutoff: cutoffISO }),
    { status: 200 }
  )
})