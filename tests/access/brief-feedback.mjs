// Local-only: readiness metadata must match the actual transition's identity and default assignment.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
const require = createRequire(
    new URL('../../app/package.json', import.meta.url),
  ),
  { createClient } = require('@supabase/supabase-js')
const cfg = JSON.parse(
    readFileSync(new URL('../../ops/.tmp/access-local.json', import.meta.url)),
  ),
  f = JSON.parse(
    readFileSync(
      new URL('../../ops/.tmp/planning-fixture.json', import.meta.url),
    ),
  ),
  v = JSON.parse(
    readFileSync(
      new URL('../../ops/.tmp/version-sharing-fixture.json', import.meta.url),
    ),
  )
const host = new URL(cfg.API_URL)
assert(
  ['localhost', '127.0.0.1'].includes(host.hostname) && host.port === '58321',
)
const opts = { auth: { persistSession: false, autoRefreshToken: false } },
  service = createClient(cfg.API_URL, cfg.SERVICE_ROLE_KEY, opts),
  ok = (r) => {
    assert.equal(r.error, null, r.error?.message)
    return r.data
  }
async function login(person) {
  const c = createClient(cfg.API_URL, cfg.ANON_KEY, opts)
  ok(
    await c.auth.signInWithPassword({
      email: person.email,
      password: f.password,
    }),
  )
  return c
}
const owner = await login(f.people.owner),
  client = await login(v.people.client),
  outsider = await login(f.people.outsider),
  stamp = Date.now()
const member = ok(
  await service
    .from('workspace_members')
    .select('id')
    .eq('workspace_id', f.wsA)
    .eq('user_id', f.people.senior.userId)
    .single(),
).id
const project = ok(
  await owner.rpc('create_project_with_client', {
    p_workspace_id: f.wsA,
    p_name: 'Reconciliation ' + stamp,
    p_lead_member_id: member,
    p_client_emails: [],
  }),
)[0].out_project_id
ok(
  await owner.rpc('add_project_participant', {
    p_project_id: project,
    p_workspace_member_id: null,
    p_stakeholder_id: v.people.client.sh,
    p_role: 'approver',
  }),
)
const participant = ok(
  await service
    .from('project_participants')
    .select('id')
    .eq('project_id', project)
    .eq('stakeholder_id', v.people.client.sh)
    .single(),
).id
const pending = ok(
  await owner.rpc('invite_project_participant', {
    p_workspace_id: f.wsA,
    p_project_id: project,
    p_email: `readiness-pending-${stamp}@example.test`,
    p_display_name: 'Pending client',
    p_role: 'approver',
  }),
)[0]
const pendingParticipant = ok(
  await service
    .from('project_participants')
    .select('id')
    .eq('project_id', project)
    .eq('stakeholder_id', pending.out_stakeholder_id)
    .single(),
).id
const context = async (actor = owner, id = participant) =>
    ok(
      await actor.rpc('get_project_brief_readiness', {
        p_project_id: project,
        p_respondent_participant_id: id,
      }),
    ),
  read = async () =>
    ok(await owner.rpc('get_project_brief', { p_project_id: project }))
const document = {
  disciplines: [],
  fields: [
    {
      id: 'objective',
      label: 'Objective',
      help: '',
      answer: 'A coherent project',
    },
    { id: 'deliverables', label: 'Deliverables', help: '', answer: 'Drawings' },
  ],
  references: [],
  items: [
    {
      id: 'seating',
      kind: 'mandatory',
      title: 'Seat eight',
      detail: 'Reception',
      priority: 'high',
      source: 'client',
      ownerProfileId: f.people.senior.userId,
      acceptance: 'Count seats',
      resolution: '',
      appliesTo: 'Whole project',
      areaIds: [],
    },
  ],
}
const save = async () =>
    ok(
      await owner.rpc('save_project_brief', {
        p_project_id: project,
        p_document: document,
        p_expected_version: (await read()).brief?.edit_version ?? 0,
        p_respondent_participant_id: participant,
      }),
    ),
  stage = async (action) =>
    ok(
      await owner.rpc('transition_project_brief', {
        p_project_id: project,
        p_expected_version: (await read()).brief.edit_version,
        p_action: action,
      }),
    ),
  feedback = async (actor) =>
    ok(
      await (actor ?? owner).rpc('get_brief_feedback', {
        p_project_id: project,
      }),
    ),
  act = async (actor, item, action, note, revision = null) =>
    actor.rpc('act_on_brief_feedback', {
      p_project_id: project,
      p_feedback_id: item.id,
      p_expected_version: item.version,
      p_action: action,
      p_note: note,
      p_expected_brief_version: (await read()).brief.edit_version,
      p_review_revision_id: revision,
    })
await save()
await stage('request_agreement')
const r1 = (await read()).brief.current_revision_id
ok(
  await client.rpc('respond_project_brief', {
    p_project_id: project,
    p_revision_id: r1,
    p_decision: 'changes_requested',
    p_comment: 'Please provide ten seats.',
  }),
)
let tracked = (await feedback()).rows
assert.equal(tracked.length, 1)
assert.equal(tracked[0].status, 'open')
assert.equal(tracked[0].body, 'Please provide ten seats.')
const id = tracked[0].id
assert.equal(
  (await act(client, tracked[0], 'address', 'I changed it')).error?.code,
  '42501',
)
assert.equal(
  (await act(owner, tracked[0], 'verify', 'Looks good', r1)).error?.code,
  '42501',
)
assert.equal(
  (
    await owner.rpc('add_brief_feedback_item', {
      p_project_id: project,
      p_source_revision_id: r1,
      p_body: 'Invalid target',
      p_target_kind: 'item',
      p_target_id: 'other-project-item',
    })
  ).error?.code,
  '23503',
)
const specific = ok(
  await owner.rpc('add_brief_feedback_item', {
    p_project_id: project,
    p_source_revision_id: r1,
    p_body: 'Check the reception seating',
    p_target_kind: 'item',
    p_target_id: 'seating',
  }),
)
document.items[0].title = 'Seat ten'
await save()
let row = (await feedback()).rows.find((r) => r.id === id)
ok(
  await act(
    owner,
    row,
    'address',
    'Updated the reception layout to ten seats.',
  ),
)
row = (await feedback(client)).rows.find((r) => r.id === id)
assert.equal(row.canVerify, false)
assert.equal(row.stale, false)
assert.equal(row.responseRevisionId, null)
await stage('submit')
assert.equal(
  (await feedback(client)).rows.find((r) => r.id === id).stale,
  false,
  'Status-only review must preserve the response evidence',
)
const privateBoard = ok(
  await owner.rpc('save_reference_board', {
    p_project_id: project,
    p_title: 'Private review context',
  }),
)
ok(
  await service
    .from('reference_cards')
    .insert({
      board_id: privateBoard,
      project_id: project,
      workspace_id: f.wsA,
      title: 'Private selected reference',
      description: 'Internal only',
      author_id: f.people.owner.userId,
      selected_for_brief: true,
    }),
)
assert.equal(
  (await feedback()).rows.find((r) => r.id === id).stale,
  false,
  'Private preparation must not invalidate the shared response',
)
const sharedBoard = ok(
  await owner.rpc('save_reference_board', {
    p_project_id: project,
    p_title: 'Shared review context',
  }),
)
ok(
  await owner.rpc('share_reference_board', {
    p_board_id: sharedBoard,
    p_expected_version: 1,
  }),
)
ok(
  await service
    .from('reference_cards')
    .insert({
      board_id: sharedBoard,
      project_id: project,
      workspace_id: f.wsA,
      title: 'Shared selected reference',
      description: 'Reviewed direction',
      author_id: f.people.owner.userId,
      selected_for_brief: true,
    }),
)
assert.equal(
  (await feedback()).rows.find((r) => r.id === id).stale,
  true,
  'Shared selected reference changes require a refreshed response',
)
row = (await feedback()).rows.find((r) => r.id === id)
ok(
  await act(
    owner,
    row,
    'address',
    'Reviewed the capacity update together with the selected shared reference.',
  ),
)
await stage('request_agreement')
const r2 = (await read()).brief.current_revision_id
row = (await feedback(client)).rows.find((r) => r.id === id)
assert.equal(row.responseRevisionId, r2)
assert.equal(row.canVerify, true)
assert(
  row.events.some(
    (e) => e.action === 'included_in_revision' && e.revisionNumber === 2,
  ),
)
assert.equal(
  (await act(client, row, 'verify', 'Reviewed an old link', r1)).error?.code,
  'PT409',
)
ok(await act(client, row, 'verify', 'Confirmed ten seats on revision 2.', r2))
row = (await feedback()).rows.find((r) => r.id === id)
assert.equal(row.status, 'verified')
assert.equal(row.verifiedNumber, 2)
assert.equal(
  (await act(owner, row, 'address', 'Overwrite client verification')).error
    ?.code,
  '42501',
)
ok(await act(client, row, 'reopen', 'The circulation still needs adjustment.'))
row = (await feedback()).rows.find((r) => r.id === id)
assert.equal(row.status, 'open')
assert(row.events.some((e) => e.action === 'verified'))
await stage('return_to_draft')
document.fields[0].answer = 'Updated circulation'
await save()
ok(await act(owner, row, 'address', 'Adjusted circulation.'))
document.fields[0].answer = 'Another saved change'
await save()
row = (await feedback()).rows.find((r) => r.id === id)
assert.equal(row.stale, true)
await stage('request_agreement')
const r3 = (await read()).brief.current_revision_id
row = (await feedback(client)).rows.find((r) => r.id === id)
assert.equal(row.canVerify, false)
assert.equal(row.responseRevisionId, null)
assert.equal(
  (await act(client, row, 'verify', 'Must fail for stale draft response', r3))
    .error?.code,
  'PT409',
)
ok(
  await act(
    owner,
    row,
    'address',
    'Reviewed the final circulation in revision 3.',
  ),
)
const stale = row
row = (await feedback(client)).rows.find((r) => r.id === id)
assert.equal(row.canVerify, true)
assert.equal(
  (await act(client, stale, 'verify', 'Stale feedback version', r3)).error
    ?.code,
  'PT409',
)
ok(await act(client, row, 'verify', 'Confirmed the revised circulation.', r3))
ok(
  await client.rpc('respond_project_brief', {
    p_project_id: project,
    p_revision_id: r3,
    p_decision: 'agreed',
  }),
)
row = (await feedback()).rows.find((r) => r.id === specific)
assert.equal(
  row.status,
  'open',
  'Overall agreement must not silently verify individual feedback',
)
ok(
  await act(
    owner,
    row,
    'address',
    'Confirmed the specific check in the agreed revision.',
  ),
)
row = (await feedback(client)).rows.find((r) => r.id === specific)
assert.equal(row.canVerify, true)
ok(
  await act(
    client,
    row,
    'verify',
    'Verified after reviewing the agreed package.',
    r3,
  ),
)
assert.equal(
  (await outsider.rpc('get_brief_feedback', { p_project_id: project })).error
    ?.code,
  '42501',
)
assert(
  (
    await client
      .from('brief_feedback_items')
      .update({ status: 'verified' })
      .eq('id', specific)
  ).error,
)
const event = ok(
  await service
    .from('brief_feedback_events')
    .select('id')
    .eq('feedback_id', id)
    .limit(1),
)[0]
assert.equal(
  (
    await service
      .from('brief_feedback_events')
      .update({ note: 'Tamper' })
      .eq('id', event.id)
  ).error?.code,
  '23514',
)
assert.equal(
  (
    await service
      .from('brief_feedback_items')
      .update({ body: 'Tamper' })
      .eq('id', id)
  ).error?.code,
  '23514',
)
console.log(
  'PASS automatic feedback capture, scoped targets, independent team/client roles, saved-draft response binding, stale-draft rejection, exact revision verification, reopen/audit retention, optimistic concurrency, no implicit verification and raw/cross-project access denial',
)
