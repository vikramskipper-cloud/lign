import assert from 'node:assert/strict'
// Local integration runs occasionally receive a gateway 5xx from GoTrue.
// Retry that response once; never retry credentials, permission or product assertions.
export async function signInLocal(page, base, email, password) {
  const url = new URL(base)
  assert(
    ['127.0.0.1', 'localhost'].includes(url.hostname) &&
      url.port === '5179' &&
      url.protocol === 'http:',
  )
  await page.goto(base + '/sign-in')
  await page.getByLabel('Work email').fill(email)
  for (let attempt = 0; attempt < 2; attempt++) {
    await page.getByLabel('Password', { exact: true }).fill(password)
    const response = page.waitForResponse(
      (r) =>
        r.request().method() === 'POST' &&
        r.url().includes('/auth/v1/token?grant_type=password'),
      { timeout: 60000 },
    )
    await page.getByRole('button', { name: 'Sign in', exact: true }).click()
    const status = (await response).status()
    if (status >= 500 && attempt === 0) {
      await page
        .getByRole('alert')
        .filter({ hasText: "Couldn't reach Lign" })
        .waitFor()
      console.log(`Local auth returned ${status}; retrying once`)
      continue
    }
    assert.equal(
      status,
      200,
      'Local authentication must succeed; only one transient server retry is allowed',
    )
    await page.waitForURL((u) => u.pathname !== '/sign-in')
    return
  }
  throw new Error('Local authentication did not recover')
}
