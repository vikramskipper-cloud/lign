import { signInLocal } from './helpers/local-browser-auth.mjs'
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
    p_name: 'Consolidated brief review ' + Date.now(),
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
const area = ok(
  await api.rpc('save_project_area', {
    p_project_id: project,
    p_name: 'Original lounge',
    p_kind: 'Space',
  }),
)
document.items[0].areaIds = [area]
document.items.push({
  ...document.items[0],
  id: 'whole-project',
  title: 'Coherent palette',
  kind: 'preference',
  areaIds: [],
})
document.items.push({
  ...document.items[0],
  id: 'resolved',
  kind: 'question',
  title: 'Which dimensions?',
  resolution: 'Use surveyed dimensions',
  areaIds: [],
})
document.items.push({
  ...document.items[0],
  id: 'assumption',
  kind: 'assumption',
  title: 'Retain existing structure',
  areaIds: [],
})
const sharedBoard = ok(
  await api.rpc('save_reference_board', {
    p_project_id: project,
    p_title: 'Client direction',
  }),
)
ok(
  await api.rpc('share_reference_board', {
    p_board_id: sharedBoard,
    p_expected_version: 1,
  }),
)
const privateBoard = ok(
  await api.rpc('save_reference_board', {
    p_project_id: project,
    p_title: 'PRIVATE PREPARATION',
  }),
)
const refs = ok(
  await service
    .from('reference_cards')
    .insert([
      {
        board_id: sharedBoard,
        project_id: project,
        workspace_id: f.wsA,
        title: 'Shared warm palette',
        description: 'Chosen direction',
        author_id: f.people.owner.userId,
        selected_for_brief: true,
      },
      {
        board_id: privateBoard,
        project_id: project,
        workspace_id: f.wsA,
        title: 'PRIVATE SECRET CARD',
        description: 'Internal preparation',
        author_id: f.people.owner.userId,
        selected_for_brief: true,
      },
    ])
    .select('id,board_id'),
)
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
const review = (p) =>
    p.getByRole('region', { name: 'Complete brief package', exact: true }),
  saved = (p) =>
    p.getByRole('region', { name: 'Saved brief package', exact: true }),
  decision = (p) =>
    p.getByRole('region', { name: 'Brief review decision', exact: true }),
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
  await signInLocal(p, base, person.email, f.password)
  await p.goto(url)
  return p
}
try {
  const owner = await login(f.people.owner)
  await review(owner)
    .getByRole('heading', { name: 'Brief package for review', exact: true })
    .waitFor()
  await review(owner)
    .getByText('A comfortable sample area', { exact: true })
    .waitFor()
  await review(owner)
    .getByRole('region', {
      name: 'Requirements for Original lounge',
      exact: true,
    })
    .getByText('Durable finishes', { exact: true })
    .waitFor()
  await review(owner)
    .getByRole('region', { name: 'Requirements for Project-wide', exact: true })
    .getByText('Coherent palette', { exact: true })
    .waitFor()
  await review(owner)
    .getByText('Use surveyed dimensions', { exact: false })
    .waitFor()
  await review(owner)
    .getByRole('heading', { name: 'Shared warm palette', exact: true })
    .waitFor()
  assert.equal(
    await owner.getByText('PRIVATE SECRET CARD', { exact: true }).count(),
    0,
  )
  assert.equal(
    await owner.getByText('PRIVATE PREPARATION', { exact: true }).count(),
    0,
  )
  // Selected-reference failures must be visible and retryable, never shown as an empty package.
  await owner.route('**/rpc/get_reference_direction', (route) =>
    route.fulfill({
      status: 503,
      contentType: 'application/json',
      body: JSON.stringify({
        code: '503',
        message: 'Temporary reference failure',
      }),
    }),
  )
  await owner.reload()
  await review(owner)
    .getByRole('button', { name: 'Retry selected references', exact: true })
    .waitFor()
  await owner.unroute('**/rpc/get_reference_direction')
  await review(owner)
    .getByRole('button', { name: 'Retry selected references', exact: true })
    .click()
  await review(owner)
    .getByRole('heading', { name: 'Shared warm palette', exact: true })
    .waitFor()
  // Edit links go to the existing editor; file upload stays governed by the saved draft.
  await review(owner)
    .getByRole('button', {
      name: 'Edit What should this project achieve?',
      exact: true,
    })
    .click()
  await owner.waitForFunction(
    () => document.activeElement?.id === 'brief-objective',
  )
  await owner
    .locator('#brief-objective')
    .fill('Updated objective before request')
  await owner
    .getByRole('tab', { name: '4. Review and agree', exact: true })
    .click()
  await review(owner)
    .getByText(
      'This preview includes unsaved edits. Save before requesting agreement.',
      { exact: true },
    )
    .waitFor()
  assert(
    await decision(owner)
      .getByRole('button', {
        name: 'Review and request agreement',
        exact: true,
      })
      .isDisabled(),
  )
  await owner.getByRole('button', { name: 'Save draft', exact: true }).click()
  await owner.getByRole('tab', { name: '3. References', exact: true }).click()
  await owner
    .getByLabel('Upload reference file', { exact: true })
    .setInputFiles({
      name: 'Review package.txt',
      mimeType: 'text/plain',
      buffer: Buffer.from('Captured brief material'),
    })
  await owner.getByRole('button', { name: /Review package.txt/ }).waitFor()
  await owner
    .getByRole('tab', { name: '4. Review and agree', exact: true })
    .click()
  await review(owner)
    .getByRole('button', { name: /Review package.txt/ })
    .waitFor()
  await decision(owner)
    .getByRole('button', { name: 'Review and request agreement', exact: true })
    .click()
  await saved(owner)
    .getByRole('heading', { name: 'Saved package · revision 1', exact: true })
    .waitFor()
  const first = (await read()).revisions.find((r) => r.number === 1)
  assert(first)
  // Changing live area names and references cannot alter an already requested package.
  // Local fixture mutation stress-tests snapshot isolation; the normal area RPC
  // correctly locks area changes while a brief request is awaiting agreement.
  ok(
    await service
      .from('project_areas')
      .update({ name: 'Renamed lounge' })
      .eq('id', area),
  )
  ok(
    await service
      .from('reference_cards')
      .update({ title: 'NEW LIVE PALETTE' })
      .eq('id', refs.find((r) => r.board_id === sharedBoard).id),
  )
  await owner.reload()
  await saved(owner)
    .getByRole('region', {
      name: 'Requirements for Original lounge',
      exact: true,
    })
    .waitFor()
  await saved(owner)
    .getByRole('heading', { name: 'Shared warm palette', exact: true })
    .waitFor()
  assert.equal(
    await saved(owner).getByText('NEW LIVE PALETTE', { exact: true }).count(),
    0,
  )
  assert.equal(
    await saved(owner)
      .getByRole('button', { name: /^Edit / })
      .count(),
    0,
  )
  const client = await login(v.people.client),
    viewer = await login(v.people.viewer)
  await saved(client)
    .getByRole('button', { name: /Review package.txt/ })
    .waitFor()
  await saved(viewer).waitFor()
  assert.equal(await decision(viewer).getByRole('button').count(), 0)
  assert.equal(
    await viewer
      .getByRole('checkbox', { name: /I agree to this brief revision/ })
      .count(),
    0,
  )
  assert.equal(
    await viewer.getByText('PRIVATE SECRET CARD', { exact: true }).count(),
    0,
  )
  await client
    .getByLabel('Agreement note or changes requested', { exact: true })
    .fill('Please update the objective and material check.')
  await decision(client)
    .getByRole('button', { name: 'Request changes', exact: true })
    .click()
  await owner.reload()
  await review(owner).waitFor()
  await owner.getByRole('button', { name: 'Update brief', exact: true }).click()
  await owner
    .getByLabel('What should this project achieve?', { exact: true })
    .fill('Revised objective after client feedback')
  await owner.getByRole('button', { name: 'Save draft', exact: true }).click()
  await owner.getByText('All changes saved.', { exact: true }).waitFor()
  await owner
    .getByRole('tab', { name: '4. Review and agree', exact: true })
    .click()
  const comparison = owner.getByRole('group', {
    name: 'Revision comparison',
    exact: true,
  })
  await owner.getByText('Compare revisions', { exact: true }).click()
  await comparison
    .getByText('Please update the objective and material check.', {
      exact: true,
    })
    .waitFor()
  await comparison
    .getByText('Revised objective after client feedback', { exact: false })
    .waitFor()
  await comparison
    .getByRole('heading', { name: 'NEW LIVE PALETTE', exact: true })
    .waitFor()
  assert.equal(
    await comparison.getByText('PRIVATE SECRET CARD', { exact: false }).count(),
    0,
  )
  assert.equal(await comparison.getByText(/No content changes/).count(), 0)
  await owner.screenshot({
    path: 'ops/.tmp/brief-review-desktop.png',
    fullPage: true,
  })
  await owner.setViewportSize({ width: 390, height: 844 })
  assert(
    await owner.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  )
  await owner.screenshot({
    path: 'ops/.tmp/brief-review-mobile.png',
    fullPage: true,
  })
  await owner.setViewportSize({ width: 1440, height: 1000 })
  await decision(owner)
    .getByRole('button', { name: 'Review and request agreement', exact: true })
    .click()
  await saved(owner)
    .getByRole('heading', { name: 'Saved package · revision 2', exact: true })
    .waitFor()
  await client.reload()
  await saved(client)
    .getByText('Revised objective after client feedback', { exact: true })
    .waitFor()
  await decision(client)
    .getByRole('checkbox', { name: /I agree to this brief revision/ })
    .check()
  await decision(client)
    .getByRole('button', { name: 'Agree this revision', exact: true })
    .click()
  await owner.reload()
  await owner
    .getByRole('region', {
      name: 'Agreed requirements activation',
      exact: true,
    })
    .waitFor()
  await owner.getByLabel('View', { exact: true }).selectOption(first.id)
  await saved(owner)
    .getByText('Updated objective before request', { exact: true })
    .waitFor()
  assert.equal(
    await owner
      .getByRole('region', {
        name: 'Agreed requirements activation',
        exact: true,
      })
      .count(),
    0,
  )
  assert.equal(await decision(owner).getByRole('button').count(), 0)
  assert.equal(
    await owner.getByText('Compare revisions', { exact: true }).count(),
    0,
  )
  assert.deepEqual(
    (await read()).revisions.find((r) => r.id === first.id).document,
    first.document,
  )
  assert.deepEqual(errors, [])
  console.log(
    'PASS consolidated grouped package, direct edit focus, file inclusion, shared-only references/error recovery, frozen area/reference snapshots, client/viewer decisions, feedback with comparison, second agreement, read-only historical package and desktop/mobile',
  )
} catch (e) {
  for (let i = 0; i < contexts.length; i++) {
    const p = contexts[i].pages()[0]
    console.log(
      'Failure',
      i,
      (await p.locator('body').innerText()).slice(-5500),
    )
    await p.screenshot({
      path: `ops/.tmp/brief-review-failure-${i}.png`,
      fullPage: true,
    })
  }
  throw e
} finally {
  await browser.close()
}
