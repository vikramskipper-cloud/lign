// Read-only hosted browser smoke check. Requires Playwright and a browser.
// Blocks production POST requests; never submits applicant or account data.
import assert from 'node:assert/strict'
import { mkdirSync } from 'node:fs'
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright')
const origin = process.env.ACCESS_SMOKE_URL ?? 'https://lignv11.vercel.app'
assert(origin && /^https:\/\/lignv11(?:-[a-z0-9-]+)?\.vercel\.app$/.test(origin))
const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_PATH })
const context = await browser.newContext({ viewport: { width: 1280, height: 900 } })
let writes = 0
await context.route('https://hsfporioghapwghrvvzd.supabase.co/**', async (route) => {
  if (route.request().method() === 'POST') { writes++; await route.abort(); return }
  await route.continue()
})
const page = await context.newPage()
const errors = []
page.on('pageerror', (error) => errors.push(error.message))
try {
  await page.goto(`${origin}/sign-in`)
  await page.getByRole('button', { name: 'Sign in', exact: true }).waitFor()
  await page.getByRole('link', { name: 'request access', exact: true }).click()
  for (const label of ['Full name', 'Work email', 'Phone', 'Company', 'Your role', 'Team size']) {
    await page.getByLabel(label, { exact: true }).waitFor()
  }
  await page.getByRole('button', { name: 'Request access', exact: true }).click()
  await page.getByRole('alert').filter({ hasText: 'Tell us your name.' }).waitFor()
  console.log('PASS sign-in → request access, all six fields, required-field validation')
  for (const path of ['/sign-up', '/signup']) {
    await page.goto(origin + path)
    await page.waitForURL((url) => url.pathname === '/request-access')
    await page.getByRole('heading', { name: 'Request access', exact: true }).waitFor()
  }
  console.log('PASS both public signup routes redirect to request access')
  await page.goto(`${origin}/set-password`)
  await page.getByRole('heading', { name: 'Set your password', exact: true }).waitFor()
  await page.getByRole('alert').filter({ hasText: 'This link has expired' }).waitFor()
  assert.equal(await page.getByLabel('New password', { exact: true }).count(), 0)
  console.log('PASS password setup refuses a missing activation token')
  await page.goto(`${origin}/access-requests`)
  await page.waitForURL((url) => url.pathname === '/sign-in')
  console.log('PASS anonymous visitors cannot open admin review')
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto(`${origin}/request-access`)
  await page.getByLabel('Company', { exact: true }).waitFor()
  assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth))
  mkdirSync('ops/.tmp', { recursive: true })
  await page.screenshot({ path: 'ops/.tmp/production-request-access.png', fullPage: true })
  assert.deepEqual(errors, [])
  assert.equal(writes, 0)
  console.log('PASS mobile layout, no page errors, no production data writes')
} finally { await browser.close() }
