// Local team -> shared client input -> selected direction, with private discussion retention.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright')
const f = JSON.parse(
    readFileSync(
      new URL('../../ops/.tmp/planning-fixture.json', import.meta.url),
    ),
  ),
  r = JSON.parse(
    readFileSync(
      new URL('../../ops/.tmp/reference-sharing-fixture.json', import.meta.url),
    ),
  ),
  base = 'http://127.0.0.1:5179',
  project = `${base}/workspace/${r.workspace}/project/${r.project}`,
  stamp = Date.now()
assert.equal(new URL(base).hostname, '127.0.0.1')
const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.PLAYWRIGHT_CHROMIUM_PATH,
  }),
  contexts = [],
  errors = []
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
try {
  const owner = await login(f.people.owner)
  await owner.goto(project + '/references?stage=team')
  await owner.getByText('Create a reference board', { exact: true }).click()
  await owner
    .getByLabel('Board title', { exact: true })
    .fill('Team draft ' + stamp)
  await owner.getByRole('button', { name: 'Create board', exact: true }).click()
  await owner
    .getByRole('heading', { name: 'Team draft ' + stamp, exact: true })
    .waitFor()
  const board = new URL(owner.url()).searchParams.get('board')
  assert(board)
  await owner.getByText('Suggest or add a reference', { exact: true }).click()
  await owner
    .getByLabel('New reference title', { exact: true })
    .fill('Private visual ' + stamp)
  await owner.waitForFunction(
    () =>
      Array.from(document.querySelectorAll('button')).find(
        (b) => b.textContent?.trim() === 'Share with client',
      )?.disabled === true,
  )
  await owner
    .getByLabel('Why this reference?', { exact: true })
    .fill('Use the palette, not the layout.')
  await owner
    .getByRole('button', { name: 'Add reference', exact: true })
    .click()
  const card = owner.getByRole('article', {
    name: 'Private visual ' + stamp,
    exact: true,
  })
  await card.waitFor()
  assert.equal(
    await card
      .getByRole('button', { name: 'Include in brief', exact: true })
      .count(),
    0,
  )
  await card.getByRole('button', { name: /Comments/ }).click()
  await card
    .getByLabel('Reference comment', { exact: true })
    .fill('Private preparation discussion ' + stamp)
  await card.getByRole('button', { name: 'Post comment', exact: true }).click()
  await card
    .getByText('Private preparation discussion ' + stamp, { exact: true })
    .waitFor()
  const client = await login(r.client)
  await client.goto(project + `/references?board=${board}`)
  await client
    .getByText('This board is unavailable in this view.', { exact: true })
    .waitFor()
  assert.equal(
    await client
      .getByRole('button', { name: 'Team preparation', exact: true })
      .count(),
    0,
  )
  assert.equal(
    await client
      .getByRole('article', { name: 'Private visual ' + stamp, exact: true })
      .count(),
    0,
  )
  // Only the explicit sharing action opens the board to the client.
  await owner
    .getByRole('button', { name: 'Share with client', exact: true })
    .click()
  await owner
    .getByRole('button', { name: 'Copy client review link', exact: true })
    .waitFor()
  await client.reload()
  await client
    .getByRole('article', { name: 'Private visual ' + stamp, exact: true })
    .waitFor()
  const clientCard = client.getByRole('article', {
    name: 'Private visual ' + stamp,
    exact: true,
  })
  await clientCard.getByRole('button', { name: /Comments/ }).click()
  assert.equal(
    await client
      .getByText('Private preparation discussion ' + stamp, { exact: true })
      .count(),
    0,
  )
  await clientCard
    .getByLabel('Your preference note', { exact: true })
    .fill('Use the warm colour')
  await clientCard
    .getByRole('button', { name: 'Shortlist', exact: true })
    .click()
  await clientCard
    .getByRole('button', { name: 'Shortlist', pressed: true, exact: true })
    .waitFor()
  assert.equal(
    await clientCard
      .getByRole('button', { name: 'Include in brief', exact: true })
      .count(),
    0,
  )
  await client
    .getByRole('button', { name: 'Add your references', exact: true })
    .click()
  await client
    .getByRole('heading', { name: 'Client suggestions', exact: true })
    .waitFor()
  await client
    .getByLabel('New reference title', { exact: true })
    .fill('Client inspiration ' + stamp)
  await client
    .getByLabel('Why this reference?', { exact: true })
    .fill('I like the material texture')
  await client
    .getByRole('button', { name: 'Add reference', exact: true })
    .click()
  await client
    .getByRole('article', { name: 'Client inspiration ' + stamp, exact: true })
    .waitFor()
  await client.screenshot({
    path: 'ops/.tmp/reference-sharing-client-desktop.png',
    fullPage: true,
  })
  await client.setViewportSize({ width: 390, height: 844 })
  assert(
    await client.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  )
  await client.screenshot({
    path: 'ops/.tmp/reference-sharing-client-mobile.png',
    fullPage: true,
  })
  await owner.goto(project + `/references?board=${board}&stage=shared`)
  const sharedCard = owner.getByRole('article', {
    name: 'Private visual ' + stamp,
    exact: true,
  })
  await sharedCard
    .getByRole('button', { name: 'Include in brief', exact: true })
    .click()
  await sharedCard
    .getByRole('button', { name: 'Remove from brief', exact: true })
    .waitFor()
  await owner
    .getByRole('button', { name: 'Brief direction', exact: true })
    .click()
  await owner
    .getByRole('article', { name: 'Private visual ' + stamp, exact: true })
    .waitFor()
  assert.equal(
    await owner
      .getByText('Private preparation discussion ' + stamp, { exact: true })
      .count(),
    0,
  )
  await owner.screenshot({
    path: 'ops/.tmp/reference-sharing-direction-desktop.png',
    fullPage: true,
  })
  await owner
    .getByRole('link', { name: 'Continue to review and agree →', exact: true })
    .waitFor()
  const viewer = await login(r.viewer)
  await viewer.goto(project + `/references?board=${board}&stage=shared`)
  await viewer
    .getByRole('article', { name: 'Private visual ' + stamp, exact: true })
    .waitFor()
  assert.equal(
    await viewer
      .getByRole('button', { name: 'Add your references', exact: true })
      .count(),
    0,
  )
  assert.equal(
    await viewer
      .getByRole('button', { name: 'Shortlist', exact: true })
      .count(),
    0,
  )
  await owner.goto(project + '/brief?step=references')
  await owner
    .getByRole('heading', { name: 'References for the brief', exact: true })
    .waitFor()
  await owner
    .getByRole('button', { name: 'Continue to review & agree', exact: true })
    .waitFor()
  assert.deepEqual(errors, [])
  console.log(
    'PASS private team preparation, guarded sharing, internal comment retention, client shortlist/suggestions, lead-only brief selection, selected direction, viewer restrictions, brief navigation and desktop/mobile',
  )
} catch (e) {
  for (let i = 0; i < contexts.length; i++) {
    const p = contexts[i].pages()[0]
    console.log(
      'Failure',
      i,
      new URL(p.url()).pathname,
      (await p.locator('body').innerText()).slice(-3200),
    )
    await p.screenshot({
      path: `ops/.tmp/reference-sharing-failure-${i}.png`,
      fullPage: true,
    })
  }
  throw e
} finally {
  await browser.close()
}
