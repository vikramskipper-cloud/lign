// Local-only customer journey: first useful collection -> saved draft -> resume -> review -> publication.
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
  },
  stamp = Date.now()
ok(
  await api.auth.signInWithPassword({
    email: f.people.reserve.email,
    password: f.password,
  }),
)
const org = ok(
  await service
    .from('organizations')
    .insert({ name: 'Library setup ' + stamp, slug: 'library-setup-' + stamp })
    .select('id')
    .single(),
).id
for (const [person, role] of [
  [f.people.owner, 'owner'],
  [f.people.reserve, 'member'],
  [f.people.senior, 'member'],
])
  ok(
    await service.from('organization_members').insert({
      organization_id: org,
      user_id: person.userId,
      role,
      status: 'active',
    }),
  )
const base = 'http://127.0.0.1:5179',
  url = `${base}/org/${org}/library`,
  title = 'Useful timber finishes ' + stamp,
  browser = await chromium.launch({
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
const dialog = (p) => p.getByRole('dialog'),
  list = async () =>
    ok(await api.rpc('get_organization_library', { p_organization_id: org }))
      .collections
try {
  const author = await login(f.people.reserve)
  await author.goto(url)
  await author
    .getByRole('button', { name: '+ New collection', exact: true })
    .click()
  for (const [category, example] of [
    ['inspiration', 'Calm natural palettes'],
    ['materials_products', 'Warm timber finishes'],
    ['details_solutions', 'Proven connection details'],
    ['templates_guides', 'Design review checklist'],
  ]) {
    await dialog(author)
      .getByLabel('Collection category', { exact: true })
      .selectOption(category)
    await dialog(author)
      .getByRole('complementary', { name: 'Collection example' })
      .getByText(example, { exact: true })
      .waitFor()
  }
  await dialog(author)
    .getByLabel('Collection category', { exact: true })
    .selectOption('materials_products')
  await dialog(author)
    .getByRole('button', { name: 'Use example name', exact: true })
    .click()
  assert.equal(
    await dialog(author)
      .getByLabel('Collection title', { exact: true })
      .inputValue(),
    'Warm timber finishes',
  )
  assert.equal((await list()).length, 0)
  await dialog(author)
    .getByLabel('Collection title', { exact: true })
    .fill(title)
  await author.screenshot({
    path: 'ops/.tmp/library-setup-name-desktop.png',
    fullPage: true,
  })
  await author.setViewportSize({ width: 390, height: 844 })
  assert(
    await author.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  )
  await author.screenshot({
    path: 'ops/.tmp/library-setup-name-mobile.png',
    fullPage: true,
  })
  await author.setViewportSize({ width: 1440, height: 1000 })
  await dialog(author)
    .getByRole('button', { name: 'Save draft & exit', exact: true })
    .click()
  await author
    .getByRole('button', { name: `Open ${title}`, exact: true })
    .waitFor()
  const first = (await list()).find((c) => c.title === title)
  assert(first)
  assert.equal(first.itemCount, 0)
  assert.equal(first.status, 'draft')
  await author.reload()
  await author
    .getByRole('button', { name: 'Resume collection', exact: true })
    .click()
  await author
    .getByRole('heading', { name: 'Add useful content', exact: true })
    .waitFor()
  assert.equal(new URL(author.url()).searchParams.get('setup'), 'content')
  assert(
    await author
      .getByRole('button', { name: 'Continue to check & submit', exact: true })
      .isDisabled(),
  )
  assert.equal(
    await author
      .getByRole('button', { name: 'Submit for review', exact: true })
      .count(),
    0,
  )
  // Focused note editor requires real content and protects it from accidental dismissal.
  await author
    .getByRole('button', { name: 'Write a note', exact: true })
    .click()
  await dialog(author)
    .getByLabel('Item title', { exact: true })
    .fill('Where to use these finishes')
  await dialog(author)
    .getByRole('button', { name: 'Add item', exact: true })
    .click()
  assert.equal(
    ok(await api.rpc('get_library_draft_items', { p_collection_id: first.id }))
      .length,
    0,
  )
  await dialog(author)
    .getByLabel('Item details', { exact: true })
    .fill(
      'Use in dry indoor areas. Confirm care requirements with the supplier.',
    )
  author.once('dialog', (d) => d.dismiss())
  await dialog(author)
    .getByRole('button', { name: 'Close', exact: true })
    .click()
  assert.match(
    await dialog(author)
      .getByLabel('Item details', { exact: true })
      .inputValue(),
    /dry indoor/,
  )
  await dialog(author)
    .getByRole('button', { name: 'Add item', exact: true })
    .click()
  await author
    .getByRole('heading', { name: 'Where to use these finishes', exact: true })
    .waitFor()
  // Link entry requires a URL; a failed save keeps the customer's typed details.
  await author.getByRole('button', { name: 'Add a link', exact: true }).click()
  await dialog(author)
    .getByLabel('Item title', { exact: true })
    .fill('Supplier care instructions')
  await dialog(author)
    .getByRole('button', { name: 'Add item', exact: true })
    .click()
  assert.equal(
    ok(await api.rpc('get_library_draft_items', { p_collection_id: first.id }))
      .length,
    1,
  )
  await dialog(author)
    .getByLabel('Source URL', { exact: true })
    .fill('https://example.com/timber-care')
  let fail = true
  await author.route('**/rpc/save_library_item', async (route) => {
    if (fail) {
      fail = false
      await route.fulfill({
        status: 400,
        contentType: 'application/json',
        body: JSON.stringify({
          code: '22023',
          message: 'Temporary save failure',
        }),
      })
    } else await route.continue()
  })
  await dialog(author)
    .getByRole('button', { name: 'Add item', exact: true })
    .click()
  await dialog(author).getByRole('alert').waitFor()
  assert.equal(
    await dialog(author).getByLabel('Source URL', { exact: true }).inputValue(),
    'https://example.com/timber-care',
  )
  await dialog(author)
    .getByRole('button', { name: 'Add item', exact: true })
    .click()
  await author
    .getByRole('heading', { name: 'Supplier care instructions', exact: true })
    .waitFor()
  await author.unroute('**/rpc/save_library_item')
  await author.getByRole('button', { name: 'Add files', exact: true }).click()
  await dialog(author)
    .getByLabel('Choose files', { exact: true })
    .setInputFiles({
      name: 'Timber swatch.png',
      mimeType: 'image/png',
      buffer: Buffer.from(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
        'base64',
      ),
    })
  await dialog(author)
    .getByRole('button', { name: 'Add 1 files', exact: true })
    .click()
  await dialog(author)
    .getByRole('button', { name: 'Done', exact: true })
    .click()
  await author
    .getByRole('heading', { name: 'Timber swatch', exact: true })
    .waitFor()
  await author
    .getByRole('button', { name: 'Save draft & finish later', exact: true })
    .click()
  await author
    .getByRole('button', { name: `Open ${title}`, exact: true })
    .waitFor()
  await author.goto(url)
  await author
    .getByRole('button', { name: 'View unfinished collections', exact: true })
    .click()
  await author
    .getByRole('button', { name: 'Resume collection', exact: true })
    .click()
  await author
    .getByRole('heading', { name: 'Supplier care instructions', exact: true })
    .waitFor()
  const reader = await login(f.people.senior)
  await reader.goto(`${url}?collection=${first.id}&mode=working&setup=review`)
  await reader
    .getByRole('heading', { name: 'Collection unavailable', exact: true })
    .waitFor()
  await author
    .getByLabel('Content format', { exact: true })
    .selectOption('notes')
  assert.equal(
    await author
      .getByRole('heading', { name: 'Timber swatch', exact: true })
      .count(),
    0,
  )
  await author
    .getByRole('button', { name: 'Continue to check & submit', exact: true })
    .click()
  await author
    .getByRole('heading', { name: 'Timber swatch', exact: true })
    .waitFor()
  await author
    .getByRole('heading', { name: 'Supplier care instructions', exact: true })
    .waitFor()
  await author
    .getByRole('heading', {
      name: 'Check your collection before submitting',
      exact: true,
    })
    .waitFor()
  assert.equal(
    await author
      .getByRole('button', { name: 'Edit item', exact: true })
      .count(),
    0,
  )
  await author
    .getByRole('button', { name: 'Add description', exact: true })
    .click()
  await dialog(author)
    .getByLabel('Description', { exact: true })
    .fill('Choose and maintain warm timber finishes for indoor projects.')
  await dialog(author)
    .getByLabel('Tags', { exact: true })
    .fill('timber, indoor')
  await dialog(author)
    .getByRole('button', { name: 'Save collection', exact: true })
    .click()
  await author
    .getByRole('heading', {
      name: 'Check your collection before submitting',
      exact: true,
    })
    .waitFor()
  await author.screenshot({
    path: 'ops/.tmp/library-setup-review-desktop.png',
    fullPage: true,
  })
  await author.setViewportSize({ width: 390, height: 844 })
  assert(
    await author.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  )
  await author.screenshot({
    path: 'ops/.tmp/library-setup-review-mobile.png',
    fullPage: true,
  })
  await author.setViewportSize({ width: 1440, height: 1000 })
  // Submission failure stays on review, and the retry uses the same saved collection.
  let reject = true
  await author.route('**/rpc/transition_library_collection', async (route) => {
    if (reject) {
      reject = false
      await route.fulfill({
        status: 400,
        contentType: 'application/json',
        body: JSON.stringify({
          code: 'PT409',
          message: 'Temporary review conflict',
        }),
      })
    } else await route.continue()
  })
  await author
    .getByRole('button', { name: 'Submit for review', exact: true })
    .click()
  await author.getByRole('alert').waitFor()
  assert.equal(new URL(author.url()).searchParams.get('setup'), 'review')
  assert.equal((await list()).find((c) => c.id === first.id).status, 'draft')
  await author
    .getByRole('button', { name: 'Submit for review', exact: true })
    .click()
  await author
    .getByRole('heading', {
      name: 'Waiting for organisation admin approval',
      exact: true,
    })
    .waitFor()
  await author.unroute('**/rpc/transition_library_collection')
  assert.equal(
    await author
      .getByRole('button', { name: 'Edit item', exact: true })
      .count(),
    0,
  )
  const owner = await login(f.people.owner)
  await owner.goto(`${url}?collection=${first.id}&mode=working`)
  await owner
    .getByLabel('Review feedback', { exact: true })
    .fill('Please verify the source.')
  await owner
    .getByRole('button', { name: 'Request changes', exact: true })
    .click()
  await owner
    .getByRole('button', { name: 'Submit for review', exact: true })
    .waitFor()
  await author.reload()
  await author
    .getByRole('button', { name: 'Back to content', exact: true })
    .click()
  await author
    .getByText('Please verify the source.', { exact: false })
    .first()
    .waitFor()
  await author
    .getByRole('button', { name: 'Continue to check & submit', exact: true })
    .click()
  await author
    .getByRole('button', { name: 'Submit for review', exact: true })
    .click()
  await author
    .getByRole('heading', {
      name: 'Waiting for organisation admin approval',
      exact: true,
    })
    .waitFor()
  await owner.reload()
  await owner
    .getByRole('button', { name: 'Approve & publish', exact: true })
    .click()
  await owner
    .getByRole('button', { name: 'Start a revision', exact: true })
    .waitFor()
  await author.reload()
  await author
    .getByRole('heading', { name: 'Published and ready to reuse', exact: true })
    .waitFor()
  await author
    .getByRole('link', {
      name: 'Choose a workspace and project →',
      exact: true,
    })
    .waitFor()
  await author
    .getByRole('button', { name: 'View published library', exact: true })
    .click()
  await author
    .getByRole('button', { name: `Open ${title}`, exact: true })
    .waitFor()
  // Continue creates a draft and lands directly on step two; the empty draft is resumable.
  await author
    .getByRole('button', { name: '+ New collection', exact: true })
    .click()
  await dialog(author)
    .getByLabel('Collection title', { exact: true })
    .fill('Next collection ' + stamp)
  await dialog(author)
    .getByRole('button', { name: 'Continue to add content', exact: true })
    .click()
  await author
    .getByRole('heading', { name: 'Add useful content', exact: true })
    .waitFor()
  assert.equal((await list()).length, 2)
  assert.equal(
    (await list()).find((c) => c.title === 'Next collection ' + stamp)
      .itemCount,
    0,
  )
  assert.deepEqual(errors, [])
  console.log(
    'PASS category examples, draft exit/resume, required note/link content, failed-save retention, file upload, review guidance/editing, failed submission retry, changes requested, publishing/reuse guidance and desktop/mobile',
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
      path: `ops/.tmp/library-setup-failure-${i}.png`,
      fullPage: true,
    })
  }
  throw e
} finally {
  await browser.close()
}
