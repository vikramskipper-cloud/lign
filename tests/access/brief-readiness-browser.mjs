// Local-only: next actions follow role, current request and immutable revision identity.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
const { chromium } = await import(
    process.env.PLAYWRIGHT_MODULE ?? 'playwright'
  ),
  require = createRequire(new URL('../../app/package.json', import.meta.url)),
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
  api = createClient(cfg.API_URL, cfg.ANON_KEY, opts),
  ok = (r) => {
    assert.equal(r.error, null, r.error?.message)
    return r.data
  }
ok(
  await api.auth.signInWithPassword({
    email: f.people.owner.email,
    password: f.password,
  }),
)
const member = async (person) =>
  ok(
    await service
      .from('workspace_members')
      .select('id')
      .eq('workspace_id', f.wsA)
      .eq('user_id', person.userId)
      .single(),
  ).id
const project = ok(
  await api.rpc('create_project_with_client', {
    p_workspace_id: f.wsA,
    p_name: 'Brief readiness screen ' + Date.now(),
    p_lead_member_id: await member(f.people.senior),
    p_client_emails: [],
  }),
)[0].out_project_id
for (const [person, role] of [
  [v.people.client, 'approver'],
  [v.people.viewer, 'observer'],
])
  ok(
    await api.rpc('add_project_participant', {
      p_project_id: project,
      p_workspace_member_id: null,
      p_stakeholder_id: person.sh,
      p_role: role,
    }),
  )
ok(
  await api.rpc('add_project_participant', {
    p_project_id: project,
    p_workspace_member_id: await member(f.people.junior),
    p_stakeholder_id: null,
    p_role: 'contributor',
  }),
)
const respondent = ok(
  await service
    .from('project_participants')
    .select('id')
    .eq('project_id', project)
    .eq('stakeholder_id', v.people.client.sh)
    .single(),
).id
const document = {
  disciplines: [],
  fields: [
    {
      id: 'objective',
      label: 'What should this project achieve?',
      help: '',
      answer: 'A comfortable sample area',
    },
    {
      id: 'deliverables',
      label: 'What should we deliver?',
      help: '',
      answer: 'Drawings and specifications',
    },
    {
      id: 'scope',
      label: 'What is included and excluded?',
      help: '',
      answer: '',
    },
  ],
  items: [
    {
      id: 'quality',
      kind: 'mandatory',
      title: 'Durable finishes',
      detail: 'Use suitable finishes',
      appliesTo: 'Whole project',
      priority: 'high',
      source: 'client',
      ownerProfileId: '',
      acceptance: '',
      resolution: '',
    },
  ],
  references: [],
}
document.items.push({
  ...document.items[0],
  id: 'open-question',
  kind: 'question',
  title: 'Which dimensions?',
  acceptance: '',
})
ok(
  await api.rpc('save_project_brief', {
    p_project_id: project,
    p_document: document,
    p_expected_version: 0,
    p_respondent_participant_id: respondent,
  }),
)
const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.PLAYWRIGHT_CHROMIUM_PATH,
  }),
  contexts = [],
  errors = [],
  base = 'http://127.0.0.1:5179',
  url = `${base}/workspace/${f.wsA}/project/${project}/brief?step=agreement`
const panel = (p) =>
    p.getByRole('region', { name: 'Brief readiness', exact: true }),
  request = (p) =>
    p.getByRole('button', {
      name: 'Review and request agreement',
      exact: true,
    }),
  agreement = async (p) => {
    await p
      .getByRole('tab', { name: '4. Review and agree', exact: true })
      .click()
  },
  read = async () =>
    ok(await api.rpc('get_project_brief', { p_project_id: project }))
async function login(person) {
  const c = await browser.newContext({
    viewport: { width: 1440, height: 1000 },
  })
  contexts.push(c)
  const p = await c.newPage()
  p.setDefaultTimeout(45000)
  p.on('pageerror', (e) => errors.push(e.message))
  await p.goto(base + '/sign-in')
  await p.getByLabel('Work email').fill(person.email)
  await p.getByLabel('Password', { exact: true }).fill(f.password)
  await p.getByRole('button', { name: 'Sign in', exact: true }).click()
  await p.waitForURL((u) => u.pathname !== '/sign-in')
  await p.goto(url)
  return p
}
try {
  const owner = await login(f.people.owner)
  await panel(owner)
    .getByText('1 requirement or preference needs an acceptance check', {
      exact: true,
    })
    .waitFor()
  await panel(owner)
    .getByText('1 question needs an answer', { exact: true })
    .waitFor()
  await panel(owner)
    .getByRole('complementary', {
      name: 'Automatic responsibility',
      exact: true,
    })
    .waitFor()
    .catch(() => {})
  const metadata = ok(
    await api.rpc('get_project_brief_readiness', {
      p_project_id: project,
      p_respondent_participant_id: respondent,
    }),
  )
  await panel(owner)
    .getByText(new RegExp(metadata.defaultOwner.name))
    .first()
    .waitFor()
  assert(await request(owner).isDisabled())
  assert(
    await owner
      .getByRole('button', { name: 'Submit for team review', exact: true })
      .isEnabled(),
  )
  await owner.screenshot({
    path: 'ops/.tmp/brief-readiness-desktop.png',
    fullPage: true,
  })
  await owner.setViewportSize({ width: 390, height: 844 })
  assert(
    await owner.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  )
  await owner.screenshot({
    path: 'ops/.tmp/brief-readiness-mobile.png',
    fullPage: true,
  })
  await owner.setViewportSize({ width: 1440, height: 1000 })
  // Team review remains possible with unresolved details; leadership can return it to editing.
  await owner
    .getByRole('button', { name: 'Submit for team review', exact: true })
    .click()
  await panel(owner)
    .getByRole('button', {
      name: 'Return to draft to make changes',
      exact: true,
    })
    .click()
  await panel(owner)
    .getByRole('button', { name: /Add check: Durable finishes/ })
    .click()
  await owner.waitForFunction(
    () => document.activeElement?.id === 'item-acceptance-quality',
  )
  await owner
    .locator('#item-acceptance-quality')
    .fill('Review material samples')
  // A target must still work after the requirements list was filtered away.
  await owner
    .getByLabel('Find an item', { exact: true })
    .fill('no matching items')
  await agreement(owner)
  await panel(owner)
    .getByRole('button', { name: /Resolve: Which dimensions/ })
    .click()
  await owner.waitForFunction(
    () => document.activeElement?.id === 'item-resolution-open-question',
  )
  assert.equal(
    await owner.getByLabel('Find an item', { exact: true }).inputValue(),
    '',
  )
  await owner
    .locator('#item-resolution-open-question')
    .fill('Use the surveyed dimensions')
  await agreement(owner)
  await panel(owner)
    .getByRole('button', { name: 'Save latest changes', exact: true })
    .click()
  await panel(owner)
    .getByRole('status')
    .filter({ hasText: 'Ready to request agreement' })
    .waitFor()
  assert(await request(owner).isEnabled())
  await panel(owner)
    .getByRole('region', { name: 'Optional improvements', exact: true })
    .waitFor()
  // An unavailable RPC fails closed and exposes a retry, while team review stays available.
  await owner.route('**/rpc/get_project_brief_readiness', (route) =>
    route.fulfill({
      status: 503,
      contentType: 'application/json',
      body: JSON.stringify({
        code: '503',
        message: 'Temporary readiness failure',
      }),
    }),
  )
  await owner.reload()
  await panel(owner)
    .getByText('Could not verify agreement details', { exact: true })
    .waitFor()
  assert(await request(owner).isDisabled())
  assert(
    await owner
      .getByRole('button', { name: 'Submit for team review', exact: true })
      .isEnabled(),
  )
  await owner.unroute('**/rpc/get_project_brief_readiness')
  await panel(owner)
    .getByRole('button', { name: 'Retry checks', exact: true })
    .click()
  await panel(owner)
    .getByRole('status')
    .filter({ hasText: 'Ready to request agreement' })
    .waitFor()
  // Pending invitations are visible with a precise next action.
  const invitation = ok(
    await api.rpc('invite_project_participant', {
      p_workspace_id: f.wsA,
      p_project_id: project,
      p_email: `readiness-ui-${Date.now()}@example.test`,
      p_display_name: 'Pending UI client',
      p_role: 'approver',
    }),
  )
  const pending = ok(
    await service
      .from('project_participants')
      .select('id')
      .eq('project_id', project)
      .eq('stakeholder_id', invitation[0].out_stakeholder_id)
      .single(),
  ).id
  await owner.reload()
  await owner
    .getByLabel('Client / brief approver', { exact: true })
    .selectOption(pending)
  await panel(owner)
    .getByText('Pending UI client has an invitation pending', { exact: true })
    .waitFor()
  await panel(owner)
    .getByText(
      'The invitation must be accepted before leadership can request agreement.',
      { exact: true },
    )
    .waitFor()
  assert(await request(owner).isDisabled())
  await owner
    .getByLabel('Client / brief approver', { exact: true })
    .selectOption(respondent)
  await panel(owner)
    .getByRole('button', { name: 'Save latest changes', exact: true })
    .click()
  await panel(owner)
    .getByRole('status')
    .filter({ hasText: 'Ready to request agreement' })
    .waitFor()
  // Viewers cannot alter content or approvers; the client being the respondent is valid for leadership.
  const client = await login(v.people.client),
    viewer = await login(v.people.viewer)
  await panel(client)
    .getByRole('status')
    .filter({ hasText: 'Ready for leadership to request agreement' })
    .waitFor()
  assert.equal(
    await panel(client)
      .getByRole('button', { name: 'Review approver assignment', exact: true })
      .count(),
    0,
  )
  await panel(viewer)
    .getByRole('status')
    .filter({ hasText: 'Ready for leadership to request agreement' })
    .waitFor()
  assert.equal(await panel(viewer).getByRole('button').count(), 0)
  // Existing saved content can change while another editor has local changes.
  await panel(owner)
    .getByRole('button', { name: 'Add scope boundaries', exact: true })
    .click()
  await owner.locator('#brief-scope').fill('UNSAVED LOCAL SCOPE')
  let state = await read()
  const changed = structuredClone(state.brief.document)
  changed.fields[0].answer = 'Newer server objective'
  ok(
    await api.rpc('save_project_brief', {
      p_project_id: project,
      p_document: changed,
      p_expected_version: state.brief.edit_version,
      p_respondent_participant_id: respondent,
    }),
  )
  await agreement(owner)
  await owner.bringToFront()
  await owner.evaluate(() => {
    window.dispatchEvent(new Event('visibilitychange'))
    window.dispatchEvent(new Event('focus'))
    document.dispatchEvent(new Event('visibilitychange'))
  })
  await panel(owner)
    .getByRole('button', { name: 'Load latest brief', exact: true })
    .waitFor()
  assert(await request(owner).isDisabled())
  owner.once('dialog', (d) => d.dismiss())
  await panel(owner)
    .getByRole('button', { name: 'Load latest brief', exact: true })
    .click()
  await owner.getByRole('tab', { name: '1. Gather needs', exact: true }).click()
  assert.equal(
    await owner.locator('#brief-scope').inputValue(),
    'UNSAVED LOCAL SCOPE',
  )
  await agreement(owner)
  owner.once('dialog', (d) => d.accept())
  await panel(owner)
    .getByRole('button', { name: 'Load latest brief', exact: true })
    .click()
  await panel(owner)
    .getByRole('status')
    .filter({ hasText: 'Ready to request agreement' })
    .waitFor()
  await request(owner).click()
  await owner
    .getByRole('region', { name: 'Saved brief package', exact: true })
    .getByRole('heading', { name: 'Saved package · revision 1', exact: true })
    .waitFor()
  assert.equal(await panel(owner).count(), 0)
  state = await read()
  const snapshot = state.revisions[0]
  assert.equal(
    snapshot.document.items[0].ownerProfileId,
    metadata.defaultOwner.id,
  )
  await client.reload()
  await client
    .getByRole('checkbox', { name: /I agree to this brief revision/ })
    .check()
  await client
    .getByRole('button', { name: 'Agree this revision', exact: true })
    .click()
  await client
    .getByRole('region', { name: 'Saved brief package', exact: true })
    .waitFor()
  await owner.reload()
  await owner
    .getByRole('button', { name: 'Start a new revision', exact: true })
    .click()
  await panel(owner).waitFor()
  await owner.getByLabel('View', { exact: true }).selectOption(snapshot.id)
  await owner
    .getByRole('region', { name: 'Saved brief package', exact: true })
    .waitFor()
  assert.equal(await panel(owner).count(), 0)
  assert.deepEqual(
    (await read()).revisions.find((r) => r.id === snapshot.id).document,
    snapshot.document,
  )
  assert.deepEqual(errors, [])
  console.log(
    'PASS partial team review, direct focus through filters, live edits/save, automatic assignee, metadata error/retry, pending invitation, role-specific actions, stale-edit confirmation, immutable requested/agreed/history and desktop/mobile',
  )
} catch (e) {
  for (let i = 0; i < contexts.length; i++) {
    const p = contexts[i].pages()[0]
    console.log(
      'Failure',
      i,
      (await p.locator('body').innerText()).slice(-5000),
    )
    await p.screenshot({
      path: `ops/.tmp/brief-readiness-failure-${i}.png`,
      fullPage: true,
    })
  }
  throw e
} finally {
  await browser.close()
}
