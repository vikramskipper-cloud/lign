import { signInLocal } from './helpers/local-browser-auth.mjs'
// Local synthetic journey: feedback -> exact client verification -> operational reconciliation.
import assert from 'node:assert/strict'
import {
  project,
  owner,
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
} from './brief-reconciliation.mjs'
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.PLAYWRIGHT_CHROMIUM_PATH,
  }),
  contexts = [],
  errors = [],
  base = 'http://127.0.0.1:5179',
  url = `${base}/workspace/${f.wsA}/project/${project}/brief?step=agreement`
const tracker = (p) =>
    p.getByRole('region', { name: 'Brief feedback tracking', exact: true }),
  handoff = (p) =>
    p.getByRole('region', {
      name: 'Agreed requirements activation',
      exact: true,
    }),
  decision = (p) =>
    p.getByRole('region', { name: 'Brief review decision', exact: true })
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
  const team = await login(f.people.owner)
  await handoff(team)
    .getByText('Agreed · requirement handoff complete', { exact: true })
    .waitFor()
  await decision(team)
    .getByRole('button', { name: 'Start a new revision', exact: true })
    .click()
  await decision(team)
    .getByRole('button', { name: 'Review and request agreement', exact: true })
    .click()
  await team
    .getByRole('heading', { name: 'Saved package · revision 4', exact: true })
    .waitFor()
  const clientPage = await login(v.people.client)
  await clientPage
    .getByLabel('Agreement note or changes requested', { exact: true })
    .fill('Please provide twelve seats and clarify the acceptance check.')
  await decision(clientPage)
    .getByRole('button', { name: 'Request changes', exact: true })
    .click()
  await tracker(clientPage)
    .getByRole('article', {
      name: 'Feedback: Please provide twelve seats and clarify the acceptance check.',
      exact: true,
    })
    .waitFor()
  // Use the existing checked save API to prepare several changed item identities.
  document.items = document.items.filter(
    (i) => !['brand-new', 'recreated-new'].includes(i.id),
  )
  document.items.find((i) => i.id === 'change').title = 'Seat twelve'
  document.items.push(make('recreated-again', 'Recreated requirement'))
  await save()
  let previous = ok(
    await owner.rpc('get_brief_requirement_changes', {
      p_project_id: project,
      p_revision_id: (await read()).revisions.find((r) => r.number === 3).id,
    }),
  ).rows.find((r) => r.itemId === 'change').next.id
  ok(
    await owner.rpc('edit_requirement', {
      p_requirement_id: previous,
      p_description: 'Manual operational cost note',
      p_priority: null,
    }),
  )
  await team.reload()
  await tracker(team)
    .getByText('Add a specific feedback item', { exact: true })
    .click()
  await tracker(team)
    .getByLabel('Feedback concerns', { exact: true })
    .selectOption('item')
  await tracker(team)
    .getByLabel('Affected item', { exact: true })
    .selectOption('change')
  await tracker(team)
    .getByLabel('Requested change', { exact: true })
    .fill('Confirm twelve-seat capacity')
  await tracker(team)
    .getByRole('button', { name: 'Add feedback item', exact: true })
    .click()
  const specific = () =>
    tracker(team).getByRole('article', {
      name: 'Feedback: Confirm twelve-seat capacity',
      exact: true,
    })
  await specific()
    .getByRole('button', { name: 'Open affected item', exact: true })
    .click()
  await team.waitForFunction(
    () => document.activeElement?.id === 'item-detail-change',
  )
  await team
    .locator('#item-detail-change')
    .fill('Twelve-seat reception with circulation clearance')
  await team.getByRole('button', { name: 'Save draft', exact: true }).click()
  await team.getByText('All changes saved.', { exact: true }).waitFor()
  await team
    .getByRole('tab', { name: '4. Review and agree', exact: true })
    .click()
  const overall = () =>
    tracker(team).getByRole('article', {
      name: 'Feedback: Please provide twelve seats and clarify the acceptance check.',
      exact: true,
    })
  await overall()
    .getByLabel('Team response', { exact: true })
    .fill('Updated capacity and documented the layout check.')
  await overall()
    .getByRole('button', { name: 'Mark addressed by team', exact: true })
    .click()
  await specific()
    .getByLabel('Team response', { exact: true })
    .fill('The reception now seats twelve with the stated acceptance check.')
  await specific()
    .getByRole('button', { name: 'Mark addressed by team', exact: true })
    .click()
  await tracker(team)
    .getByText('Team responded · awaiting client verification', { exact: true })
    .first()
    .waitFor()
  assert.equal(
    await tracker(team)
      .getByRole('button', { name: /Verify response on revision/ })
      .count(),
    0,
  )
  await decision(team)
    .getByRole('button', { name: 'Review and request agreement', exact: true })
    .click()
  await team
    .getByRole('heading', { name: 'Saved package · revision 5', exact: true })
    .waitFor()
  await clientPage.reload()
  assert.equal(
    await tracker(clientPage)
      .getByRole('button', { name: 'Mark addressed by team', exact: true })
      .count(),
    0,
  )
  for (const body of [
    'Please provide twelve seats and clarify the acceptance check.',
    'Confirm twelve-seat capacity',
  ]) {
    const item = tracker(clientPage).getByRole('article', {
      name: 'Feedback: ' + body,
      exact: true,
    })
    await item
      .getByLabel('Verification or further changes', { exact: true })
      .fill('Reviewed the saved revision and confirmed the response.')
    await item
      .getByRole('button', {
        name: 'Verify response on revision 5',
        exact: true,
      })
      .click()
  }
  await tracker(clientPage)
    .getByText('0 feedback items awaiting resolution · 2 client verified', {
      exact: true,
    })
    .waitFor()
  await tracker(clientPage)
    .getByLabel('Show verified feedback', { exact: true })
    .check()
  await tracker(clientPage)
    .getByText('Feedback history (', { exact: false })
    .first()
    .waitFor()
  await decision(clientPage)
    .getByRole('checkbox', { name: /I agree to this brief revision/ })
    .check()
  await decision(clientPage)
    .getByRole('button', { name: 'Agree this revision', exact: true })
    .click()
  await team.reload()
  await handoff(team)
    .getByRole('button', { name: 'Create draft requirements', exact: true })
    .click()
  await handoff(team)
    .getByRole('article', {
      name: 'Requirement change: Seat twelve',
      exact: true,
    })
    .waitFor()
  assert(
    await decision(team)
      .getByRole('button', { name: 'Start a new revision', exact: true })
      .isDisabled(),
  )
  const changed = handoff(team).getByRole('article', {
    name: 'Requirement change: Seat twelve',
    exact: true,
  })
  await changed.getByText('Manual edits detected.', { exact: false }).waitFor()
  await changed
    .getByRole('checkbox', {
      name: 'I reviewed this change, any manual edits and its linked work.',
      exact: true,
    })
    .check()
  assert(
    await changed
      .getByRole('button', { name: 'Activate replacement', exact: true })
      .isDisabled(),
  )
  await changed
    .getByLabel('Review note (required)', { exact: true })
    .fill('Reviewed the cost note and adopted the client-agreed capacity.')
  await changed
    .getByRole('button', { name: 'Activate replacement', exact: true })
    .click()
  const pendingChange = ok(
    await owner.rpc('get_brief_requirement_changes', {
      p_project_id: project,
      p_revision_id: (await read()).brief.current_revision_id,
    }),
  ).rows.find((r) => r.itemId === 'recreated-again')
  ok(
    await lead.rpc('archive_requirement', {
      p_requirement_id: pendingChange.next.id,
    }),
  )
  await team.reload()
  const recover = handoff(team)
    .getByRole('article', {
      name: 'Requirement change: Recreated requirement',
      exact: true,
    })
    .filter({
      has: team.getByRole('button', {
        name: 'Prepare a fresh draft',
        exact: true,
      }),
    })
  await recover
    .getByLabel('Review note (required)', { exact: true })
    .fill(
      'Prepare a fresh proposal from the agreed brief; preserve the retired draft.',
    )
  await recover
    .getByRole('checkbox', {
      name: 'I reviewed this change, any manual edits and its linked work.',
      exact: true,
    })
    .check()
  await recover
    .getByRole('button', { name: 'Prepare a fresh draft', exact: true })
    .click()
  const added = () =>
    handoff(team)
      .getByRole('article', {
        name: 'Requirement change: Recreated requirement',
        exact: true,
      })
      .filter({
        has: team.getByLabel('Was this recreated from a removed item?', {
          exact: true,
        }),
      })
  await added()
    .getByLabel('Was this recreated from a removed item?', { exact: true })
    .selectOption('recreated-new')
  await added()
    .getByRole('button', { name: 'Match as replacement', exact: true })
    .click()
  const matched = () =>
    handoff(team)
      .getByRole('article', {
        name: 'Requirement change: Recreated requirement',
        exact: true,
      })
      .filter({
        has: team.getByRole('button', {
          name: 'Undo replacement match',
          exact: true,
        }),
      })
  await matched()
    .getByRole('button', { name: 'Undo replacement match', exact: true })
    .click()
  await added()
    .getByLabel('Was this recreated from a removed item?', { exact: true })
    .selectOption('recreated-new')
  await added()
    .getByRole('button', { name: 'Match as replacement', exact: true })
    .click()
  await matched()
    .getByRole('checkbox', {
      name: 'I reviewed this change, any manual edits and its linked work.',
      exact: true,
    })
    .check()
  await matched()
    .getByRole('button', { name: 'Activate replacement', exact: true })
    .click()
  const removed = handoff(team).getByRole('article', {
    name: 'Requirement change: Brand new requirement',
    exact: true,
  })
  await removed
    .getByRole('checkbox', {
      name: 'I reviewed this change, any manual edits and its linked work.',
      exact: true,
    })
    .check()
  assert(
    await removed
      .getByRole('button', { name: 'Confirm retirement', exact: true })
      .isDisabled(),
  )
  await team.screenshot({
    path: 'ops/.tmp/brief-handoff-desktop.png',
    fullPage: true,
  })
  await team.setViewportSize({ width: 390, height: 844 })
  assert(
    await team.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  )
  await team.screenshot({
    path: 'ops/.tmp/brief-handoff-mobile.png',
    fullPage: true,
  })
  const leadPage = await login(f.people.senior)
  const retire = handoff(leadPage).getByRole('article', {
    name: 'Requirement change: Brand new requirement',
    exact: true,
  })
  await retire
    .getByRole('checkbox', {
      name: 'I reviewed this change, any manual edits and its linked work.',
      exact: true,
    })
    .check()
  await retire
    .getByRole('button', { name: 'Confirm retirement', exact: true })
    .click()
  await handoff(leadPage)
    .getByText('Agreed · requirement handoff complete', { exact: true })
    .waitFor()
  await team.reload()
  await decision(team)
    .getByRole('button', { name: 'Start a new revision', exact: true })
    .click({ trial: true })
  assert(
    await decision(team)
      .getByRole('button', { name: 'Start a new revision', exact: true })
      .isEnabled(),
  )
  const history = (await read()).revisions.find((r) => r.number === 4)
  await team.getByLabel('View', { exact: true }).selectOption(history.id)
  assert.equal(await handoff(team).count(), 0)
  assert.equal(await tracker(team).count(), 0)
  const oldReq = ok(
    await service
      .from('requirements')
      .select('status,superseded_by_requirement_id,description')
      .eq('id', previous)
      .single(),
  )
  assert.equal(oldReq.status, 'superseded')
  assert.equal(oldReq.description, 'Manual operational cost note')
  assert(oldReq.superseded_by_requirement_id)
  assert.deepEqual(errors, [])
  console.log(
    'PASS client feedback capture, scoped item navigation, saved team responses, independent exact-revision verification, handoff progress, manual-edit acknowledgement, atomic replacement, reversible matching, retirement capability, immutable history and desktop/mobile',
  )
} catch (e) {
  for (let i = 0; i < contexts.length; i++) {
    const p = contexts[i].pages()[0]
    console.log(
      'Failure',
      i,
      (await p.locator('body').innerText()).slice(-6500),
    )
    await p.screenshot({
      path: `ops/.tmp/brief-handoff-failure-${i}.png`,
      fullPage: true,
    })
  }
  throw e
} finally {
  await browser.close()
}
