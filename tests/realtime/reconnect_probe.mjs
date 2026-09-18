// APP 011 §7.2 — does the reconnect sweep ever actually run?
//
// RealtimeProvider performs a full cache invalidation on every SUBSCRIBED
// *after the first*, because Postgres Changes has no replay and anything missed
// while the socket was down is gone permanently. That whole design rests on one
// unverified assumption:
//
//   supabase-js re-fires the subscribe callback with 'SUBSCRIBED' after the
//   connection drops and recovers.
//
// If it does not, the sweep never runs, and realtime is silently and
// indefinitely staler than the polling it replaced. This probe kills the
// realtime container mid-subscription and watches what the client reports.
//
// Local only.  node tests/realtime/reconnect_probe.mjs

import { execSync } from 'node:child_process'
import ws from 'ws'
import { createClient } from '@supabase/supabase-js'

const URL = process.env.LIGN_LOCAL_URL
const ANON = process.env.LIGN_LOCAL_ANON
const CONTAINER = 'supabase_realtime_lign_v1.1'
const WS_ONE = 'a0000000-0000-0000-0000-000000000001'
if (!URL || !ANON) { console.error('set LIGN_LOCAL_URL / LIGN_LOCAL_ANON'); process.exit(2) }

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const client = createClient(URL, ANON, {
  auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  realtime: { params: { eventsPerSecond: 30 }, transport: ws },
})
const { error } = await client.auth.signInWithPassword({
  email: 'p_lead@lign.test', password: 'LignProbe!2026',
})
if (error) { console.error('sign-in failed:', error.message); process.exit(2) }

const statuses = []
const channel = client.channel(`reconnect-${Date.now()}`)
channel.on('postgres_changes',
  { event: 'INSERT', schema: 'public', table: 'comments', filter: `workspace_id=eq.${WS_ONE}` },
  () => {})

channel.subscribe((s) => {
  statuses.push({ at: Date.now(), status: s })
  console.log(`  [${new Date().toISOString().slice(11, 19)}] ${s}`)
})

console.log('waiting for first SUBSCRIBED...')
const t0 = Date.now()
while (!statuses.some((s) => s.status === 'SUBSCRIBED') && Date.now() - t0 < 30000) await sleep(250)
if (!statuses.some((s) => s.status === 'SUBSCRIBED')) {
  console.error('never subscribed'); process.exit(1)
}
const firstCount = statuses.filter((s) => s.status === 'SUBSCRIBED').length
console.log(`first connect OK (SUBSCRIBED x${firstCount})`)

console.log(`\nkilling ${CONTAINER} to force a real disconnect...`)
execSync(`docker stop ${CONTAINER}`, { stdio: 'ignore' })
await sleep(8000)
console.log('restarting it...')
execSync(`docker start ${CONTAINER}`, { stdio: 'ignore' })

console.log('waiting up to 90s for the client to recover...')
const t1 = Date.now()
while (Date.now() - t1 < 90000) {
  if (statuses.filter((s) => s.status === 'SUBSCRIBED').length > firstCount) break
  await sleep(500)
}

const resubscribes = statuses.filter((s) => s.status === 'SUBSCRIBED').length - firstCount
const sawDrop = statuses.some((s) => ['CHANNEL_ERROR', 'CLOSED', 'TIMED_OUT'].includes(s.status))
await client.removeChannel(channel)

console.log('\n' + '-'.repeat(58))
console.log(`status sequence: ${statuses.map((s) => s.status).join(' -> ')}`)
console.log(`drop observed by client: ${sawDrop}`)
console.log(`SUBSCRIBED re-fires after recovery: ${resubscribes}`)
if (resubscribes > 0) {
  console.log('RESULT: PASS — the §7.2 reconnect sweep will fire.')
  process.exit(0)
}
console.log('RESULT: FAIL — SUBSCRIBED did not re-fire; the sweep would never run')
console.log('         and realtime would be permanently staler than polling.')
process.exit(1)
