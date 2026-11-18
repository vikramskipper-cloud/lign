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
    p_name: 'Readiness context ' + stamp,
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
      answer: 'Agree a useful design',
    },
    { id: 'deliverables', label: 'Deliverables', help: '', answer: 'Drawings' },
  ],
  items: [
    {
      id: 'need',
      kind: 'mandatory',
      title: 'Durable finish',
      detail: '',
      appliesTo: 'Whole project',
      priority: 'high',
      source: 'client',
      ownerProfileId: '',
      acceptance: '',
      resolution: '',
    },
    {
      id: 'q',
      kind: 'question',
      title: 'Which dimensions?',
      detail: '',
      appliesTo: '',
      priority: 'medium',
      source: 'client',
      ownerProfileId: '',
      acceptance: '',
      resolution: '',
    },
  ],
  references: [],
}
ok(
  await owner.rpc('save_project_brief', {
    p_project_id: project,
    p_document: document,
    p_expected_version: 0,
    p_respondent_participant_id: participant,
  }),
)
const before = (await read()).brief,
  meta = await context()
assert.equal(meta.version, before.edit_version)
assert(meta.defaultOwner)
assert.equal(meta.defaultOwner.role, 'lead')
assert.equal(meta.approver.available, true)
assert.equal(meta.approver.isRequester, false)
assert.equal((await context(client)).approver.isRequester, true)
assert.equal((await context(client)).canRequest, false)
const invitation = await context(owner, pendingParticipant)
assert.equal(invitation.approver.pending, true)
assert.equal(invitation.approver.available, false)
assert.equal(invitation.approver.isRequester, false)
const foreign = ok(
  await service
    .from('project_participants')
    .select('id')
    .neq('project_id', project)
    .eq('role', 'approver')
    .limit(1),
)[0]
assert(foreign)
assert.equal((await context(owner, foreign.id)).approver, null)
assert.equal(
  (await outsider.rpc('get_project_brief_readiness', { p_project_id: project }))
    .error?.code,
  '42501',
)
assert.deepEqual((await read()).brief, before)
// Team review deliberately allows questions and missing acceptance checks.
ok(
  await owner.rpc('transition_project_brief', {
    p_project_id: project,
    p_expected_version: before.edit_version,
    p_action: 'submit',
  }),
)
let state = await read()
assert.equal(state.brief.status, 'submitted')
assert.equal((await context()).canSubmit, false)
assert.equal(
  (
    await owner.rpc('transition_project_brief', {
      p_project_id: project,
      p_expected_version: state.brief.edit_version,
      p_action: 'request_agreement',
    })
  ).error?.code,
  '23514',
)
ok(
  await owner.rpc('transition_project_brief', {
    p_project_id: project,
    p_expected_version: state.brief.edit_version,
    p_action: 'return_to_draft',
  }),
)
state = await read()
document.items[0].acceptance = 'Review material samples'
document.items[1].resolution = 'Use the agreed dimensions'
ok(
  await owner.rpc('save_project_brief', {
    p_project_id: project,
    p_document: document,
    p_expected_version: state.brief.edit_version,
    p_respondent_participant_id: participant,
  }),
)
// The read-only context reports the reference limits used by the actual snapshot operation.
const board = ok(
  await owner.rpc('save_reference_board', {
    p_project_id: project,
    p_title: 'Readiness limits',
  }),
)
ok(
  await owner.rpc('share_reference_board', {
    p_board_id: board,
    p_expected_version: 1,
  }),
)
const inserted = ok(
  await service
    .from('reference_cards')
    .insert(
      Array.from({ length: 101 }, (_, i) => ({
        board_id: board,
        project_id: project,
        workspace_id: f.wsA,
        title: 'Reference ' + i,
        author_id: f.people.owner.userId,
        selected_for_brief: true,
      })),
    )
    .select('id'),
)
assert.equal((await context()).selectedReferenceCount, 101)
assert.match((await context()).referenceError, /100/)
ok(
  await service
    .from('reference_cards')
    .update({ selected_for_brief: false })
    .eq('board_id', board),
)
ok(
  await service
    .from('reference_cards')
    .update({ selected_for_brief: true, description: 'x'.repeat(5000) })
    .in(
      'id',
      inserted.slice(0, 45).map((c) => c.id),
    ),
)
assert.match((await context()).referenceError, /too large/)
ok(
  await service
    .from('reference_cards')
    .update({ selected_for_brief: false, description: '' })
    .eq('board_id', board),
)
ok(
  await service
    .from('reference_cards')
    .update({ selected_for_brief: true })
    .eq('id', inserted[0].id),
)
assert.equal((await context()).referenceError, null)
const automatic = (await context()).defaultOwner
state = await read()
ok(
  await owner.rpc('transition_project_brief', {
    p_project_id: project,
    p_expected_version: state.brief.edit_version,
    p_action: 'request_agreement',
  }),
)
state = await read()
assert.equal(state.revisions[0].document.items[0].ownerProfileId, automatic.id)
assert.equal(state.revisions[0].document.referenceSelection.length, 1)
console.log(
  'PASS read-only metadata, exact automatic assignee, accepted/pending requester identity, cross-project/outsider denial, partial team review, reference count/size checks and actual agreement assignment',
)
