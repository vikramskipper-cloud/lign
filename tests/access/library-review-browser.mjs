// Local browser: browse -> contribution -> review -> approved retrieval/import.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright')
const f = JSON.parse(
    readFileSync(
      new URL('../../ops/.tmp/planning-fixture.json', import.meta.url),
    ),
  ),
  base = 'http://127.0.0.1:5179',
  library = `${base}/org/${f.orgId}/library`,
  stamp = Date.now(),
  title = `Member review ${stamp}`
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
const dialog = (p) => p.getByRole('dialog')
try {
  const author = await login(f.people.reserve)
  await author.goto(library)
  await author.getByRole('heading', { name: 'Library', exact: true }).waitFor()
  assert.equal(new URL(author.url()).searchParams.get('collection'), null)
  await author
    .getByRole('button', { name: '+ New collection', exact: true })
    .click()
  await dialog(author)
    .getByLabel('Collection title', { exact: true })
    .fill(title)
  await dialog(author)
    .getByLabel('Collection category', { exact: true })
    .selectOption('materials_products')
  await dialog(author)
    .getByText('Description and tags (optional)', { exact: true })
    .click()
  await dialog(author).getByLabel('Tags', { exact: true }).fill('timber, calm')
  author.once('dialog', (d) => d.dismiss())
  await dialog(author)
    .getByRole('button', { name: 'Close', exact: true })
    .click()
  assert.equal(
    await dialog(author)
      .getByLabel('Collection title', { exact: true })
      .inputValue(),
    title,
  )
  await dialog(author)
    .getByRole('button', { name: 'Continue to add content', exact: true })
    .click()
  await author.getByRole('heading', { name: title, exact: true }).waitFor()
  const id = new URL(author.url()).searchParams.get('collection')
  assert(id)
  await author.goto(`${library}?collection=${id}&mode=working`)
  await author.getByRole('button', { name: 'Add files', exact: true }).click()
  const png = Buffer.from(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      'base64',
    ),
    fileName = `Material-${stamp}.png`,
    pdfName = `Drawing-${stamp}.pdf`
  await dialog(author)
    .getByLabel('Choose files', { exact: true })
    .setInputFiles([
      { name: fileName, mimeType: 'image/png', buffer: png },
      {
        name: pdfName,
        mimeType: 'application/pdf',
        buffer: Buffer.from('%PDF-1.4\n%%EOF'),
      },
    ])
  let fail = true
  const saves = {}
  await author.route('**/rpc/save_library_item', async (route) => {
    const body = route.request().postDataJSON()
    saves[body.p_title] = (saves[body.p_title] ?? 0) + 1
    if (fail && body.p_title === `Drawing-${stamp}`) {
      fail = false
      await route.fulfill({
        status: 400,
        contentType: 'application/json',
        body: JSON.stringify({
          code: '22023',
          message: 'Simulated file registration failure',
        }),
      })
    } else await route.continue()
  })
  await dialog(author)
    .getByRole('button', { name: 'Add 2 files', exact: true })
    .click()
  await dialog(author)
    .getByRole('button', { name: 'Retry failed files', exact: true })
    .waitFor()
  await dialog(author)
    .getByRole('button', { name: 'Retry failed files', exact: true })
    .click()
  await dialog(author)
    .getByText('All 2 files added.', { exact: true })
    .waitFor()
  await dialog(author)
    .getByRole('button', { name: 'Done', exact: true })
    .click()
  assert.equal(saves[`Material-${stamp}`], 1)
  assert.equal(saves[`Drawing-${stamp}`], 2)
  await author.unroute('**/rpc/save_library_item')
  await author.getByRole('button', { name: 'Add a link', exact: true }).click()
  await dialog(author)
    .getByLabel('Item title', { exact: true })
    .fill('Member material palette')
  await dialog(author)
    .getByLabel('Item details', { exact: true })
    .fill('A calm warm direction')
  await dialog(author)
    .getByLabel('Source URL', { exact: true })
    .fill('https://example.com/palette-' + stamp)
  await dialog(author)
    .getByRole('button', { name: 'Add item', exact: true })
    .click()
  await author
    .getByRole('heading', { name: 'Member material palette', exact: true })
    .waitFor()
  await author
    .getByLabel('Content format', { exact: true })
    .selectOption('documents')
  await author
    .getByRole('heading', { name: `Drawing-${stamp}`, exact: true })
    .waitFor()
  assert.equal(
    await author
      .getByRole('heading', { name: `Material-${stamp}`, exact: true })
      .count(),
    0,
  )
  await author.getByLabel('Content format', { exact: true }).selectOption('all')
  await author.getByRole('button', { name: 'List', exact: true }).click()
  await author
    .getByText('Preview & download · ' + fileName, { exact: true })
    .click()
  await author.getByRole('img', { name: fileName, exact: true }).waitFor()
  await author
    .getByText('Preview & download · ' + fileName, { exact: true })
    .click()
  await author.getByRole('button', { name: 'Mood board', exact: true }).click()
  assert.equal(new URL(author.url()).searchParams.get('layout'), 'moodboard')
  await author.getByRole('img', { name: fileName, exact: true }).waitFor()
  await author.reload()
  await author
    .getByRole('button', { name: 'Mood board', exact: true, pressed: true })
    .waitFor()
  // Closing a dirty editor and navigating away both preserve edits when declined.
  await author
    .getByRole('button', { name: 'Collection settings', exact: true })
    .click()
  await dialog(author)
    .getByLabel('Description', { exact: true })
    .fill('Unsaved description')
  author.once('dialog', (d) => d.dismiss())
  await author.keyboard.press('Escape')
  assert.equal(
    await dialog(author)
      .getByLabel('Description', { exact: true })
      .inputValue(),
    'Unsaved description',
  )
  author.once('dialog', (d) => d.accept())
  await dialog(author)
    .getByRole('button', { name: 'Cancel', exact: true })
    .click()
  const lead = await login(f.people.senior)
  await lead.goto(library)
  await lead
    .getByLabel('Search the library', { exact: true })
    .fill(String(stamp))
  await lead
    .getByRole('heading', { name: 'No matching collections', exact: true })
    .waitFor()
  await author.screenshot({
    path: 'ops/.tmp/library-content-desktop.png',
    fullPage: true,
  })
  await author.setViewportSize({ width: 390, height: 844 })
  assert(
    await author.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  )
  await author.screenshot({
    path: 'ops/.tmp/library-content-mobile.png',
    fullPage: true,
  })
  await author.setViewportSize({ width: 1440, height: 1000 })
  await author
    .getByRole('button', { name: 'Submit for review', exact: true })
    .click()
  await author
    .getByRole('button', { name: 'Withdraw submission', exact: true })
    .waitFor()
  assert.equal(
    await author
      .getByRole('button', { name: 'Approve & publish', exact: true })
      .count(),
    0,
  )
  assert.equal(
    await author
      .getByRole('button', { name: 'Edit item', exact: true })
      .count(),
    0,
  )
  const owner = await login(f.people.owner)
  await owner.goto(library)
  await owner.getByRole('button', { name: /^Review queue / }).click()
  await owner
    .getByLabel('Search the library', { exact: true })
    .fill(String(stamp))
  await owner
    .getByRole('button', { name: `Open ${title}`, exact: true })
    .click()
  await owner
    .getByLabel('Review feedback', { exact: true })
    .fill('Please explain the timber source.')
  await owner
    .getByRole('button', { name: 'Request changes', exact: true })
    .click()
  await owner
    .getByRole('button', { name: 'Submit for review', exact: true })
    .waitFor()
  await author.reload()
  await author
    .getByText('Please explain the timber source.', { exact: false })
    .first()
    .waitFor()
  const card = author.locator('article').filter({
    has: author.getByRole('heading', {
      name: 'Member material palette',
      exact: true,
    }),
  })
  await card.getByRole('button', { name: 'Edit item', exact: true }).click()
  await dialog(author)
    .getByLabel('Item details', { exact: true })
    .fill('Timber from a sustainable source.')
  await dialog(author)
    .getByRole('button', { name: 'Save item', exact: true })
    .click()
  await author
    .getByRole('button', { name: 'Submit for review', exact: true })
    .click()
  await author
    .getByRole('button', { name: 'Withdraw submission', exact: true })
    .waitFor()
  await owner.reload()
  await owner
    .getByRole('button', { name: 'Approve & publish', exact: true })
    .click()
  await owner
    .getByRole('button', { name: 'Start a revision', exact: true })
    .waitFor()
  await lead.reload()
  await lead.getByLabel('Search the library', { exact: true }).fill(fileName)
  await lead
    .getByRole('button', { name: new RegExp(`Material-${stamp}.*${fileName}`) })
    .click()
  await lead
    .getByRole('heading', { name: `Material-${stamp}`, exact: true })
    .waitFor()
  assert.equal(
    await lead.getByRole('button', { name: 'Edit item', exact: true }).count(),
    0,
  )
  assert(new URL(lead.url()).searchParams.get('item'))
  await author.reload()
  await author
    .getByRole('button', { name: 'Start a revision', exact: true })
    .click()
  await author
    .locator('article')
    .filter({
      has: author.getByRole('heading', {
        name: 'Member material palette',
        exact: true,
      }),
    })
    .getByRole('button', { name: 'Edit item', exact: true })
    .click()
  await dialog(author)
    .getByLabel('Item title', { exact: true })
    .fill('Pending new palette')
  await dialog(author)
    .getByRole('button', { name: 'Save item', exact: true })
    .click()
  await author
    .getByRole('heading', { name: 'Pending new palette', exact: true })
    .waitFor()
  await author
    .getByLabel('Collection view', { exact: true })
    .selectOption('published')
  await author
    .getByRole('heading', { name: 'Member material palette', exact: true })
    .waitFor()
  assert.equal(
    await author
      .getByRole('button', { name: 'Approve & publish', exact: true })
      .count(),
    0,
  )
  await author
    .getByRole('button', { name: 'Back to Library', exact: true })
    .click()
  await author.getByRole('button', { name: /^Published library / }).click()
  await author
    .getByLabel('Search the library', { exact: true })
    .fill(String(stamp))
  await author
    .getByRole('button', { name: `Open ${title}`, exact: true })
    .waitFor()
  await author
    .getByRole('button', { name: 'Materials & products', exact: false })
    .click()
  await author.getByLabel('Tag', { exact: true }).selectOption('timber')
  await author
    .getByRole('button', { name: `Open ${title}`, exact: true })
    .waitFor()
  await author.screenshot({
    path: 'ops/.tmp/library-catalog-desktop.png',
    fullPage: true,
  })
  await author.setViewportSize({ width: 390, height: 844 })
  assert(
    await author.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  )
  await author.screenshot({
    path: 'ops/.tmp/library-catalog-mobile.png',
    fullPage: true,
  })
  await lead.goto(`${base}/workspace/${f.wsA}/project/${f.pA1}/references`)
  await lead.getByText('Add from organisation library', { exact: true }).click()
  const importer = lead.locator('details').filter({
    has: lead.getByText('Add from organisation library', { exact: true }),
  })
  await importer.getByLabel('Find library collection').fill(title)
  await importer.getByLabel('Collection to use').selectOption(id)
  await importer
    .getByLabel('Project board title')
    .fill(`Approved import ${stamp}`)
  await importer
    .getByRole('button', { name: 'Use collection in project', exact: true })
    .click()
  await lead
    .getByRole('heading', { name: 'Member material palette', exact: true })
    .waitFor()
  assert.equal(
    await lead
      .getByRole('heading', { name: 'Pending new palette', exact: true })
      .count(),
    0,
  )
  await lead
    .getByRole('button', { name: 'Share with client', exact: true })
    .click()
  await lead
    .getByRole('button', { name: 'Copy client review link', exact: true })
    .waitFor()
  assert.deepEqual(errors, [])
  console.log(
    'PASS collection browse/type/tag search, draft privacy, guarded forms, batch upload partial retry, formats/layout, owner review/resubmission/publication, approved item search/deep link, revision-safe import and mobile',
  )
} catch (e) {
  for (let i = 0; i < contexts.length; i++) {
    const p = contexts[i].pages()[0]
    console.log(
      'Failure context',
      i,
      new URL(p.url()).pathname,
      (await p.locator('body').innerText()).slice(-2800),
    )
    await p.screenshot({
      path: `ops/.tmp/library-review-error-${i}.png`,
      fullPage: true,
    })
  }
  throw e
} finally {
  await browser.close()
}
