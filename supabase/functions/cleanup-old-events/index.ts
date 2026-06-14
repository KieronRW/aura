import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const BUCKET = 'recognition-images'
const DAYS_TO_KEEP = 90

Deno.serve(async () => {
  const client = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  const cutoff = new Date()
  cutoff.setDate(cutoff.getDate() - DAYS_TO_KEEP)
  const cutoffISO = cutoff.toISOString()

  // Defensively remove any storage files still attached to old events
  // (cleanup-old-images handles this at 60 days, but guard against stragglers)
  const { data: eventsWithImages, error: fetchError } = await client
    .from('recognition_events')
    .select('id, image_path')
    .lt('arrived_at', cutoffISO)
    .not('image_path', 'is', null)

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 })
  }

  if (eventsWithImages && eventsWithImages.length > 0) {
    const paths = eventsWithImages.map((e: any) => e.image_path)
    const { error: storageError } = await client.storage
      .from(BUCKET)
      .remove(paths)

    if (storageError) {
      return new Response(JSON.stringify({ error: storageError.message }), { status: 500 })
    }
  }

  // Delete all event rows older than the cutoff
  const { data: deleted, error: deleteError } = await client
    .from('recognition_events')
    .delete()
    .lt('arrived_at', cutoffISO)
    .select('id')

  if (deleteError) {
    return new Response(JSON.stringify({ error: deleteError.message }), { status: 500 })
  }

  return new Response(
    JSON.stringify({ deleted: deleted?.length ?? 0, cutoff: cutoffISO }),
    { status: 200 }
  )
})
