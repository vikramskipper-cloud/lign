// APP 011 G-6 / Freeze Index §6.2 — payload sufficiency probe.
//
// The mapping in src/features/realtime/handlers.ts reads specific foreign-key
// columns out of each realtime payload. Schema nullability says those columns
// are NOT NULL, but that is not the same question: Realtime delivers rows
// RLS-filtered per subscriber, so a payload is only what THIS subscriber may
// SELECT. This probe answers the real question by subscribing as a normal
// authenticated user and inspecting what actually arrives.
//
// Runs against the LOCAL stack, never production. Nothing here writes to
// hsfporioghapwghrvvzd.
//
//   node tests/realtime/payload_shape_probe.mjs
//
// Exit 0 = every column the handlers read was present in a live payload.

import ws from 'ws'
import { createClient } from '@supabase/supabase-js'

const URL = process.env.LIGN_LOCAL_URL
const ANON = process.env.LIGN_LOCAL_ANON
const EMAIL = process.env.LIGN_PROBE_EMAIL ?? 'p_lead@lign.test'
const PASSWORD = process.env.LIGN_PROBE_PASSWORD ?? 'LignProbe!2026'

if (!URL || !ANON) {
  console.error('set LIGN_LOCAL_URL and LIGN_LOCAL_ANON (see `supabase status`)')
  process.exit(2)
}

// Fixture ids from storage_003_test_fixtures (present in the local replay).
const WS_ONE = 'a0000000-0000-0000-0000-000000000001'
const PROJ_ONE = 'd1000000-0000-0000-0000-000000000001'
const ASSET1 = '11000000-0000-0000-0000-000000000001'
const V_DRAFT = '21000000-0000-0000-0000-000000000001'
const V_PUBLISHED = '21000000-0000-0000-0000-000000000009'   // v6-published in the fixtures
const WM_REVIEWER = 'b1000000-0000-0000-0000-000000000004'   // P Reviewer's workspace_members row

// Columns handlers.ts reads, per table.
const REQUIRED = {
  comments: ['workspace_id', 'target_version_id'],
  annotations: ['workspace_id', 'asset_version_id'],
  asset_versions: ['workspace_id', 'id', 'design_asset_id', 'project_id'],
  design_assets: ['workspace_id', 'id', 'project_id'],
  reviews: ['workspace_id', 'id', 'project_id', 'version_id'],
  review_participants: ['workspace_id', 'review_id'],
  notifications: ['workspace_id', 'recipient_profile_id'],
}

const TABLES = Object.keys(REQUIRED)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

// Realtime needs a moment after container start before it streams WAL. Probing
// immediately produced two false negatives before this wait was added; without
// it this probe is a flake generator, which is worse than no probe.
async function waitForRealtime(timeoutMs = 60000) {
  const start = Date.now()
  while (Date.now() - start < timeoutMs) {
    try {
      const r = await fetch(`${URL}/realtime/v1/api/ping`, { headers: { apikey: ANON } })
      if (r.ok) { await sleep(2000); return }
    } catch {}
    await sleep(1000)
  }
  console.warn('realtime ping never succeeded; continuing anyway')
}

const client = createClient(URL, ANON, {
  auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  realtime: { params: { eventsPerSecond: 30 }, transport: ws },
})

await waitForRealtime()

const { data: auth, error: authErr } = await client.auth.signInWithPassword({
  email: EMAIL, password: PASSWORD,
})
if (authErr) { console.error('sign-in failed:', authErr.message); process.exit(2) }
const token = auth.session.access_token
const profileId = auth.user.id
console.log(`signed in as ${EMAIL}`)

const received = []
// Second identity. The notification router excludes the actor
// (APP 010 self-exclusion), so p_lead never receives a notification for its own
// write. Observing that payload requires a distinct recipient.
const recipient = createClient(URL, ANON, {
  auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  realtime: { params: { eventsPerSecond: 30 }, transport: ws },
})
const { data: rAuth, error: rErr } = await recipient.auth.signInWithPassword({
  email: 'p_reviewer@lign.test', password: PASSWORD,
})
if (rErr) { console.error('recipient sign-in failed:', rErr.message); process.exit(2) }
const recipientId = rAuth.user.id
const notifChannel = recipient.channel(`probe-notif-${Date.now()}`)
notifChannel.on('postgres_changes',
  { event: 'INSERT', schema: 'public', table: 'notifications',
    filter: `recipient_profile_id=eq.${recipientId}` },
  (p) => received.push({ table: 'notifications', event: p.eventType, row: p.new ?? {} }))
await new Promise((resolve, reject) => {
  notifChannel.subscribe((s, err) => {
    if (s === 'SUBSCRIBED') resolve()
    else if (['CHANNEL_ERROR','TIMED_OUT','CLOSED'].includes(s))
      reject(new Error(`notif ${s} ${err?.message ?? ''}`))
  })
  setTimeout(() => reject(new Error('notif subscribe timed out')), 20000)
})
console.log('recipient subscribed to notifications as p_reviewer@lign.test')

const channel = client.channel(`probe-${Date.now()}`)
for (const table of TABLES) {
  for (const event of ['INSERT', 'UPDATE']) {
    channel.on('postgres_changes',
      { event, schema: 'public', table, filter: `workspace_id=eq.${WS_ONE}` },
      (p) => received.push({ table, event: p.eventType, row: p.new ?? {} }))
  }
}
await new Promise((resolve, reject) => {
  channel.subscribe((status, err) => {
    if (status === 'SUBSCRIBED') resolve()
    else if (['CHANNEL_ERROR', 'TIMED_OUT', 'CLOSED'].includes(status))
      reject(new Error(`${status} ${err?.message ?? ''}`))
  })
  setTimeout(() => reject(new Error('subscribe timed out')), 20000)
})
console.log(`subscribed to ${TABLES.length} tables x {INSERT,UPDATE}`)

const post = (path, body) =>
  fetch(`${URL}/rest/v1/${path}`, {
    method: 'POST',
    headers: {
      apikey: ANON, Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json', Prefer: 'return=representation',
    },
    body: JSON.stringify(body),
  }).then(async (r) => ({ status: r.status, body: await r.text() }))

const writes = []
writes.push(['comments', await post('comments', {
  workspace_id: WS_ONE, body: `APP 011 probe ${Date.now()}`,
  author_profile_id: profileId, target_version_id: V_DRAFT,
})])
writes.push(['annotations', await post('annotations', {
  workspace_id: WS_ONE, asset_version_id: V_DRAFT, version_file_id: null,
  author_profile_id: profileId, anchor_kind: 'point', position: { x: 0.5, y: 0.5 },
})])
// reviews + review_participants (+ a notification, via the activity_events
// router) come from the create_review RPC rather than a raw insert: those
// tables are RPC-only by design, so a direct INSERT would be an unrealistic
// path and would be rejected by RLS anyway.
writes.push(['create_review (rpc)', await post('rpc/create_review', {
  p_project_id: PROJ_ONE,
  p_design_asset_id: ASSET1,
  p_version_id: V_PUBLISHED,
  p_title: `APP 011 probe review ${Date.now()}`,
  p_description: 'payload shape probe',
  p_reviewer_wm_ids: [WM_REVIEWER],
  p_reviewer_sh_ids: [],
  p_due_at: null,
  p_open: true,
  // All 15 args are required to disambiguate: two create_review overloads
  // exist (9-arg and 15-arg) and PostgREST returns PGRST203 for a 9-arg call.
  // The app already passes all 15, so this mirrors the real call path.
  p_coordinator_profile_id: null,
  p_policy: 'parallel',
  p_quorum_min: null,
  p_require_comments_resolved: false,
  p_reviewer_required: [true],
  p_reviewer_sequence_index: [0],
})])

writes.push(['design_assets', await post('design_assets', {
  workspace_id: WS_ONE, project_id: 'd1000000-0000-0000-0000-000000000001',
  name: `APP 011 probe asset ${Date.now()}`, created_by_profile_id: profileId,
})])

for (const [t, r] of writes) {
  console.log(`  write ${t}: HTTP ${r.status}${r.status >= 300 ? ' ' + r.body.slice(0, 160) : ''}`)
}

await sleep(4000)
await client.removeChannel(channel)
await recipient.removeChannel(notifChannel)

console.log(`\nreceived ${received.length} realtime events`)
let failures = 0
const seen = new Set()
for (const ev of received) {
  seen.add(ev.table)
  const missing = (REQUIRED[ev.table] ?? []).filter((c) => !(c in ev.row))
  const nulls = (REQUIRED[ev.table] ?? []).filter((c) => c in ev.row && ev.row[c] === null)
  const cols = Object.keys(ev.row).length
  if (missing.length) { failures++; console.log(`  FAIL ${ev.table} ${ev.event}: missing ${missing.join(', ')}`) }
  else console.log(`  ok   ${ev.table} ${ev.event}: ${cols} cols, all required present${nulls.length ? ` (null: ${nulls.join(', ')})` : ''}`)
}
const never = TABLES.filter((t) => !seen.has(t) && ['comments','annotations','design_assets','reviews','notifications'].includes(t))
for (const t of never) { failures++; console.log(`  FAIL ${t}: wrote a row but no event arrived`) }

console.log('\n' + '-'.repeat(56))
if (failures === 0) {
  console.log('RESULT: PASS — every column handlers.ts reads was present in a live payload.')
  process.exit(0)
}
console.log(`RESULT: FAIL — ${failures} problem(s)`)
process.exit(1)
