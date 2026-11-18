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
const lead = await login(f.people.senior)
const make = (id, title) => ({
  id,
  kind: 'mandatory',
  title,
  detail: 'Brief detail',
  priority: 'high',
  source: 'client',
  ownerProfileId: f.people.senior.userId,
  acceptance: 'Check the agreed drawing',
  resolution: '',
  appliesTo: 'Whole project',
  areaIds: [],
})
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
    make('keep', 'Keep this'),
    make('change', 'Seat eight'),
    make('retire', 'Retire this'),
    make('retain', 'Retain independently'),
    make('recreated-old', 'Recreated requirement'),
  ],
}
const area = ok(
  await owner.rpc('save_project_area', {
    p_project_id: project,
    p_name: 'Review space',
    p_kind: 'Space',
  }),
)
document.items[0].areaIds = [area]
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
  handoff = async (rev) =>
    ok(
      await owner.rpc('get_brief_requirement_changes', {
        p_project_id: project,
        p_revision_id: rev,
      }),
    ),
  prep = async (rev) =>
    ok(
      await owner.rpc('generate_brief_requirements', {
        p_project_id: project,
        p_revision_id: rev,
      }),
    ),
  apply = async (rev, row, action = 'activate', note = '', actor = owner) =>
    actor.rpc('apply_brief_requirement_change', {
      p_project_id: project,
      p_revision_id: rev,
      p_item_id: row.itemId,
      p_expected_token: row.token,
      p_action: action,
      p_acknowledge: true,
      p_note: note,
    })
const agree = async () => {
  await stage('request_agreement')
  const id = (await read()).brief.current_revision_id
  ok(
    await client.rpc('respond_project_brief', {
      p_project_id: project,
      p_revision_id: id,
      p_decision: 'agreed',
    }),
  )
  return id
}
await save()
const r1 = await agree()
assert.equal(await prep(r1), 5)
assert.equal(await prep(r1), 0)
let h = await handoff(r1)
assert.equal(h.pending, 5)
const old = Object.fromEntries(h.rows.map((r) => [r.itemId, r.next.id]))
ok(
  await owner.rpc('edit_requirement', {
    p_priority: null,
    p_requirement_id: old.keep,
    p_status: 'active',
  }),
)
for (const row of (await handoff(r1)).rows.filter((r) => r.state === 'pending'))
  ok(await apply(r1, row))
assert.equal((await handoff(r1)).pending, 0)
const independent = ok(
  await owner.rpc('create_requirement', {
    p_project_id: project,
    p_workspace_id: f.wsA,
    p_title: 'Independent requirement',
    p_priority: null,
    p_status: 'active',
  }),
)[0].out_requirement_id
await stage('revise')
document.items = document.items.filter(
  (i) => !['retire', 'retain', 'recreated-old'].includes(i.id),
)
document.items.find((i) => i.id === 'change').title = 'Seat ten'
document.items.push(
  make('recreated-new', 'Recreated requirement'),
  make('brand-new', 'Brand new requirement'),
)
await save()
const r2 = await agree()
ok(
  await owner.rpc('edit_requirement', {
    p_priority: null,
    p_requirement_id: old.change,
    p_description: 'Manual operational adjustment',
  }),
)
assert.equal(await prep(r2), 3)
assert.equal(await prep(r2), 0)
h = await handoff(r2)
assert.equal(h.rows.find((r) => r.itemId === 'keep').next.id, old.keep)
assert.equal(h.rows.find((r) => r.itemId === 'keep').state, 'applied')
assert.equal(
  (
    await owner.rpc('transition_project_brief', {
      p_project_id: project,
      p_expected_version: (await read()).brief.edit_version,
      p_action: 'revise',
    })
  ).error?.code,
  '23514',
)
let changed = h.rows.find((r) => r.itemId === 'change')
assert.equal(changed.manualEdits, true)
assert.equal(
  (
    await owner.rpc('supersede_requirement', {
      p_old_requirement_id: old.change,
      p_new_requirement_id: changed.next.id,
    })
  ).error?.code,
  '23514',
)
assert.equal(
  (
    await owner.rpc('edit_requirement', {
      p_priority: null,
      p_requirement_id: changed.next.id,
      p_status: 'active',
    })
  ).error?.code,
  '23514',
)
assert.equal((await apply(r2, changed)).error?.code, '22023')
ok(
  await owner.rpc('edit_requirement', {
    p_priority: null,
    p_requirement_id: old.change,
    p_title: 'Seat eight with manual note',
  }),
)
assert.equal(
  (await apply(r2, changed, 'activate', 'Reviewed manual work')).error?.code,
  'PT409',
)
changed = (await handoff(r2)).rows.find((r) => r.itemId === 'change')
ok(
  await apply(
    r2,
    changed,
    'activate',
    'Reviewed manual work; use the newly agreed ten-seat requirement',
  ),
)
const records = async () =>
  ok(
    await service
      .from('requirements')
      .select('id,status,superseded_by_requirement_id,title,description')
      .eq('project_id', project),
  )
let rows = await records()
assert.equal(rows.find((r) => r.id === old.change).status, 'superseded')
assert.equal(
  rows.find((r) => r.id === old.change).superseded_by_requirement_id,
  changed.next.id,
)
assert.equal(rows.find((r) => r.id === changed.next.id).status, 'active')
assert.equal(
  rows.find((r) => r.id === old.change).description,
  'Manual operational adjustment',
)
h = await handoff(r2)
const added = h.rows.find((r) => r.itemId === 'recreated-new'),
  removed = h.rows.find((r) => r.itemId === 'recreated-old')
ok(
  await owner.rpc('match_brief_requirement_change', {
    p_project_id: project,
    p_revision_id: r2,
    p_new_item_id: added.itemId,
    p_removed_item_id: removed.itemId,
    p_expected_new_token: added.token,
    p_expected_removed_token: removed.token,
  }),
)
h = await handoff(r2)
assert.equal(h.rows.find((r) => r.itemId === 'recreated-old').state, 'matched')
let matchNew = h.rows.find((r) => r.itemId === 'recreated-new'),
  matchOld = h.rows.find((r) => r.itemId === 'recreated-old')
ok(
  await owner.rpc('unmatch_brief_requirement_change', {
    p_project_id: project,
    p_revision_id: r2,
    p_new_item_id: matchNew.itemId,
    p_removed_item_id: matchOld.itemId,
    p_expected_new_token: matchNew.token,
    p_expected_removed_token: matchOld.token,
  }),
)
h = await handoff(r2)
matchNew = h.rows.find((r) => r.itemId === 'recreated-new')
matchOld = h.rows.find((r) => r.itemId === 'recreated-old')
assert.equal(matchNew.kind, 'added')
assert.equal(matchOld.state, 'pending')
ok(
  await owner.rpc('match_brief_requirement_change', {
    p_project_id: project,
    p_revision_id: r2,
    p_new_item_id: matchNew.itemId,
    p_removed_item_id: matchOld.itemId,
    p_expected_new_token: matchNew.token,
    p_expected_removed_token: matchOld.token,
  }),
)
h = await handoff(r2)

ok(
  await apply(
    r2,
    h.rows.find((r) => r.itemId === 'recreated-new'),
  ),
)
h = await handoff(r2)
// Local accepted-proposal fixture preserves the real design-start gate.
const proposal = ok(
  await service
    .from('project_proposals')
    .insert({
      project_id: project,
      workspace_id: f.wsA,
      brief_revision_id: r2,
      document: {},
      respondent_id: participant,
      created_by: f.people.owner.userId,
    })
    .select('id')
    .single(),
).id
const proposalRevision = ok(
  await service
    .from('proposal_revisions')
    .insert({
      proposal_id: proposal,
      project_id: project,
      workspace_id: f.wsA,
      number: 1,
      brief_revision_id: r2,
      document: {},
      snapshot: { requirements: [{ id: old.retire }] },
      respondent_id: participant,
      reviewed_by: f.people.owner.userId,
    })
    .select('id')
    .single(),
).id
ok(
  await service.from('proposal_decisions').insert({
    revision_id: proposalRevision,
    project_id: project,
    decision: 'accepted',
    actor_id: v.people.client.userId,
  }),
)
const asset = ok(
  await service
    .from('design_assets')
    .insert({
      project_id: project,
      workspace_id: f.wsA,
      name: 'Linked design work',
    })
    .select('id')
    .single(),
).id
ok(
  await service.from('requirement_design_assets').insert({
    requirement_id: old.retire,
    design_asset_id: asset,
    project_id: project,
    workspace_id: f.wsA,
  }),
)
h = await handoff(r2)
assert.equal(h.rows.find((r) => r.itemId === 'retire').impact.assets, 1)
assert.equal(
  (
    await apply(
      r2,
      h.rows.find((r) => r.itemId === 'retire'),
      'retire',
      '',
      lead,
    )
  ).error?.code,
  '22023',
)
ok(await lead.rpc('archive_requirement', { p_requirement_id: old.retire }))
h = await handoff(r2)
ok(
  await apply(
    r2,
    h.rows.find((r) => r.itemId === 'retire'),
    'retire',
    'Reviewed linked design work; retire the removed scope and retain its evidence.',
    lead,
  ),
)
ok(
  await apply(
    r2,
    h.rows.find((r) => r.itemId === 'retain'),
    'retain',
    'Retain as an independent operational requirement',
  ),
)
let retiredCandidate = h.rows.find((r) => r.itemId === 'brand-new')
const retiredDraft = retiredCandidate.next.id
ok(
  await owner.rpc('edit_requirement', {
    p_requirement_id: retiredDraft,
    p_priority: null,
    p_owner_profile_id: f.people.junior.userId,
  }),
)
const inactiveOwner = (await handoff(r2)).rows.find(
  (r) => r.itemId === 'brand-new',
)
assert.equal(
  (
    await apply(
      r2,
      inactiveOwner,
      'activate',
      'Reviewed current responsibility',
    )
  ).error?.code,
  '23514',
)
ok(
  await owner.rpc('edit_requirement', {
    p_requirement_id: retiredDraft,
    p_priority: null,
    p_owner_profile_id: f.people.senior.userId,
  }),
)

ok(await lead.rpc('archive_requirement', { p_requirement_id: retiredDraft }))
retiredCandidate = (await handoff(r2)).rows.find(
  (r) => r.itemId === 'brand-new',
)
const rebuilt = ok(
  await owner.rpc('rebuild_brief_requirement_draft', {
    p_project_id: project,
    p_revision_id: r2,
    p_item_id: 'brand-new',
    p_expected_token: retiredCandidate.token,
    p_note: 'Rebuild the independently archived proposal from the agreed brief',
  }),
)
assert.notEqual(rebuilt, retiredDraft)
const rebuiltRow = (await handoff(r2)).rows.find(
  (r) => r.itemId === 'brand-new',
)
const concurrent = await Promise.all([
  apply(r2, rebuiltRow),
  apply(r2, rebuiltRow),
])
concurrent.forEach(ok)
assert.equal(
  ok(
    await service
      .from('requirements')
      .select('status')
      .eq('id', retiredDraft)
      .single(),
  ).status,
  'archived',
)

assert.equal((await handoff(r2)).pending, 0)
rows = await records()
assert.equal(rows.find((r) => r.id === old.retire).status, 'archived')
assert.equal(rows.find((r) => r.id === old.retain).status, 'active')
assert.equal(rows.find((r) => r.id === independent).status, 'active')
assert.equal(
  rows.find((r) => r.id === old['recreated-old']).status,
  'superseded',
)
assert.equal(await prep(r2), 0)
assert.equal(
  (
    await outsider.rpc('get_brief_requirement_changes', {
      p_project_id: project,
      p_revision_id: r2,
    })
  ).error?.code,
  '42501',
)
assert.equal(
  (
    await client.rpc('prepare_brief_requirement_changes', {
      p_project_id: project,
      p_revision_id: r2,
    })
  ).error?.code,
  '42501',
)
assert.equal(
  ok(
    await service
      .from('requirement_design_assets')
      .select('requirement_id')
      .eq('requirement_id', old.retire),
  ).length,
  1,
)
assert.equal(
  (
    await client.rpc('get_brief_requirement_changes', {
      p_project_id: project,
      p_revision_id: r2,
    })
  ).error?.code,
  '42501',
)
assert.deepEqual(
  ok(
    await client
      .from('brief_requirement_changes')
      .select('item_id')
      .eq('project_id', project),
  ),
  [],
)
const count = rows.length
await stage('revise')
await save()
const r3 = await agree()
assert.equal(await prep(r3), 0)
assert.equal((await handoff(r3)).pending, 0)
assert.equal((await records()).length, count)
assert.equal(
  (await handoff(r3)).rows.filter((r) => r.kind === 'removed').length,
  0,
)
console.log(
  'PASS initial draft compatibility, unchanged reuse, replacement atomicity, manual-edit review, stale-token rollback, explicit retire/retain/matching, independent isolation, repeated preparation, access checks and subsequent revision continuity',
)
export {
  project,
  owner,
  client,
  lead,
  service,
  f,
  v,
  ok,
  read,
  stage,
  save,
  document,
  make,
}
