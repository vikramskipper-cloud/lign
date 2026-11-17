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
    p_name: 'Brief agreement status ' + Date.now(),
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
      answer: 'The sample area',
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
      ownerProfileId: f.people.senior.userId,
      acceptance: 'Review material samples',
      resolution: '',
    },
  ],
  references: [],
}
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
  url = `${base}/workspace/${f.wsA}/project/${project}/brief?step=agreement`,
  status = (p) =>
    p.getByRole('region', {
      name: 'Brief status and next action',
      exact: true,
    }),
  read = async () =>
    ok(await api.rpc('get_project_brief', { p_project_id: project }))
async function login(person) {
  const c = await browser.newContext({
    viewport: { width: 1440, height: 1000 },
  })
  contexts.push(c)
  const p = await c.newPage()
  p.setDefaultTimeout(25000)
  p.on('pageerror', (e) => errors.push(e.message))
  await p.goto(base + '/sign-in')
  await p.getByLabel('Work email').fill(person.email)
  await p.getByLabel('Password', { exact: true }).fill(f.password)
  await p.getByRole('button', { name: 'Sign in', exact: true }).click()
  await p.waitForURL((u) => u.pathname !== '/sign-in')
  return p
}
async function refreshData(p) {
  await p.bringToFront()
  await p.evaluate(() => {
    window.dispatchEvent(new Event('visibilitychange'))
    document.dispatchEvent(new Event('visibilitychange'))
    window.dispatchEvent(new Event('focus'))
  })
}
try {
  const owner = await login(f.people.owner)
  await owner.goto(url)
  await status(owner)
    .getByRole('heading', {
      name: 'Your team is preparing the brief',
      exact: true,
    })
    .waitFor()
  await status(owner)
    .getByRole('button', { name: 'Review brief', exact: true })
    .click()
  await owner
    .getByRole('tab', { name: '1. Gather needs', selected: true })
    .waitFor()
  assert.equal((await read()).brief.status, 'draft')
  await owner
    .getByRole('tab', { name: '4. Review and agree', exact: true })
    .click()
  const client = await login(v.people.client)
  await client.goto(url)
  await status(client)
    .getByRole('button', { name: 'Continue editing', exact: true })
    .click()
  await client
    .getByLabel('What should this project achieve?', { exact: true })
    .fill('UNSAVED CLIENT EDIT')
  const viewer = await login(v.people.viewer)
  await viewer.goto(url)
  await status(viewer)
    .getByRole('heading', {
      name: 'Your team is preparing the brief',
      exact: true,
    })
    .waitFor()
  assert.equal(await status(viewer).getByRole('button').count(), 0)
  await owner
    .getByRole('button', { name: 'Submit for team review', exact: true })
    .click()
  await status(owner)
    .getByRole('heading', {
      name: 'Waiting for project leadership to review',
      exact: true,
    })
    .waitFor()
  await owner
    .getByRole('button', { name: 'Review and request agreement', exact: true })
    .click()
  await status(owner)
    .getByRole('button', { name: 'Copy agreement link', exact: true })
    .waitFor()
  assert.equal(
    await owner
      .getByRole('button', { name: 'Copy agreement link', exact: true })
      .count(),
    1,
  )
  // The newly requested revision must not be confused with unsaved local client edits.
  await refreshData(client)
  await client
    .getByRole('tab', { name: '4. Review and agree', exact: true })
    .click()
  await status(client)
    .getByRole('button', { name: 'Review this revision', exact: true })
    .waitFor()
  await client
    .getByRole('checkbox', { name: /I agree to this brief revision/ })
    .check()
  assert(
    await client
      .getByRole('button', { name: 'Agree this revision', exact: true })
      .isDisabled(),
  )
  client.once('dialog', (d) => d.dismiss())
  await status(client)
    .getByRole('button', { name: 'Review this revision', exact: true })
    .click()
  await status(client)
    .getByText('You have unsaved edits.', { exact: false })
    .waitFor()
  client.once('dialog', (d) => d.accept())
  await status(client)
    .getByRole('button', { name: 'Review this revision', exact: true })
    .click()
  await client
    .getByRole('tab', { name: '1. Gather needs', selected: true })
    .waitFor()
  await client
    .getByText('A comfortable sample area', { exact: true })
    .first()
    .waitFor()
  assert.equal(
    (await read()).brief.document.fields[0].answer,
    'A comfortable sample area',
  )
  await client
    .getByRole('tab', { name: '4. Review and agree', exact: true })
    .click()
  await client
    .getByLabel('Agreement note or changes requested', { exact: true })
    .fill('Keep the palette; revise the dimensions.')
  await client
    .getByRole('button', { name: 'Request changes', exact: true })
    .click()
  await owner.reload()
  await status(owner)
    .getByText('Keep the palette; revise the dimensions.', { exact: true })
    .waitFor()
  await status(owner)
    .getByRole('button', { name: 'Update brief', exact: true })
    .click()
  await owner
    .getByLabel('What should this project achieve?', { exact: true })
    .fill('An updated comfortable sample area')
  await owner.getByRole('button', { name: 'Save draft', exact: true }).click()
  await owner.getByText('All changes saved.', { exact: true }).waitFor()
  await owner
    .getByRole('tab', { name: '4. Review and agree', exact: true })
    .click()
  await owner
    .getByRole('button', { name: 'Review and request agreement', exact: true })
    .click()
  await status(owner)
    .getByText('Saved revision 2 · awaiting agreement', { exact: true })
    .waitFor()
  const state = await read(),
    old = state.revisions.find((r) => r.number === 1),
    current = state.revisions.find((r) => r.number === 2)
  assert(old && current)
  await client.goto(url + `&revision=${old.id}`)
  const historical = client.getByRole('region', {
    name: 'Saved revision status',
    exact: true,
  })
  await historical
    .getByRole('heading', { name: 'Viewing a previous revision', exact: true })
    .waitFor()
  assert.equal(
    await client
      .getByRole('button', { name: 'Agree this revision', exact: true })
      .count(),
    0,
  )
  await historical
    .getByRole('button', { name: 'Return to current brief', exact: true })
    .click()
  assert.equal(new URL(client.url()).searchParams.get('revision'), null)
  await status(client)
    .getByRole('button', { name: 'Review this revision', exact: true })
    .waitFor()
  await client.reload()
  await status(client)
    .getByRole('button', { name: 'Review this revision', exact: true })
    .waitFor()
  await client
    .getByRole('checkbox', { name: /I agree to this brief revision/ })
    .check()
  await client
    .getByRole('button', { name: 'Agree this revision', exact: true })
    .click()
  await status(client)
    .getByRole('heading', { name: 'Revision 2 was agreed', exact: true })
    .waitFor()
  assert.equal(
    await status(client)
      .getByRole('link', { name: 'Continue to Design proposal', exact: true })
      .count(),
    0,
  )
  await status(client)
    .getByRole('button', { name: 'View agreed brief', exact: true })
    .click()
  await client
    .getByRole('region', { name: 'Saved revision status', exact: true })
    .getByRole('heading', { name: 'Viewing a saved revision', exact: true })
    .waitFor()
  // An access-check failure must not produce an optimistic proposal-preparation action.
  await owner.route('**/rpc/lign_prepare_proposal', (route) =>
    route.fulfill({
      status: 503,
      contentType: 'application/json',
      body: JSON.stringify({
        code: '503',
        message: 'Temporary access-check failure',
      }),
    }),
  )
  await owner.reload()
  await status(owner)
    .getByText('Could not check proposal access.', { exact: false })
    .waitFor()
  assert.equal(
    await status(owner)
      .getByRole('link', { name: 'Continue to Design proposal', exact: true })
      .count(),
    0,
  )
  await owner.unroute('**/rpc/lign_prepare_proposal')
  await status(owner)
    .getByRole('button', { name: 'Retry', exact: true })
    .click()
  await status(owner)
    .getByRole('link', { name: 'Continue to Design proposal', exact: true })
    .waitFor()
  await owner.screenshot({
    path: 'ops/.tmp/brief-status-agreed-desktop.png',
    fullPage: true,
  })
  await owner.setViewportSize({ width: 390, height: 844 })
  assert(
    await owner.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  )
  await owner.screenshot({
    path: 'ops/.tmp/brief-status-agreed-mobile.png',
    fullPage: true,
  })
  await owner.setViewportSize({ width: 1440, height: 1000 })
  const contributor = await login(f.people.junior)
  await contributor.goto(url)
  await status(contributor)
    .getByRole('link', { name: 'Continue to Design proposal', exact: true })
    .waitFor()
  await viewer.reload()
  await status(viewer)
    .getByRole('button', { name: 'View agreed brief', exact: true })
    .waitFor()
  assert.equal(
    await status(viewer)
      .getByRole('link', { name: 'Continue to Design proposal', exact: true })
      .count(),
    0,
  )
  await owner
    .getByRole('button', { name: 'Start a new revision', exact: true })
    .click()
  await status(owner)
    .getByText('Working draft · based on revision 2', { exact: true })
    .waitFor()
  assert.equal(
    await status(owner)
      .getByRole('link', { name: 'Continue to Design proposal', exact: true })
      .count(),
    0,
  )
  await owner.getByLabel('View', { exact: true }).selectOption(current.id)
  await owner
    .getByRole('region', { name: 'Saved revision status', exact: true })
    .getByRole('heading', { name: 'Viewing a previous revision', exact: true })
    .waitFor()
  assert.deepEqual(
    (await read()).revisions.find((r) => r.id === current.id).document,
    current.document,
  )
  assert.deepEqual(errors, [])
  console.log(
    'PASS role-specific draft/review/response actions, current saved recipient, unsaved-client review safety, changes requested, historical return/refresh, authoritative proposal access/error recovery, agreed baseline preservation and desktop/mobile',
  )
} catch (e) {
  for (let i = 0; i < contexts.length; i++) {
    const p = contexts[i].pages()[0]
    console.log(
      'Failure',
      i,
      new URL(p.url()).pathname,
      (await p.locator('body').innerText()).slice(-3500),
    )
    await p.screenshot({
      path: `ops/.tmp/brief-status-failure-${i}.png`,
      fullPage: true,
    })
  }
  throw e
} finally {
  await browser.close()
}
