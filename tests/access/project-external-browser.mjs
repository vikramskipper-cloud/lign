// Local browser verification: never targets hosted services or sends email.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
const { chromium }=await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright')
const require=createRequire(new URL('../../app/package.json',import.meta.url))
const { createClient }=require('@supabase/supabase-js')
const config=JSON.parse(readFileSync(new URL('../../ops/.tmp/access-local.json',import.meta.url)))
const f=JSON.parse(readFileSync(new URL('../../ops/.tmp/leadership-fixture.json',import.meta.url)))
const backend=new URL(config.API_URL)
assert(['localhost','127.0.0.1'].includes(backend.hostname) && backend.port==='58321')
const service=createClient(config.API_URL,config.SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}})
const ok=r=>{assert.equal(r.error,null,r.error?.message);return r.data}
const browser=await chromium.launch({headless:true,executablePath:process.env.PLAYWRIGHT_CHROMIUM_PATH})
const contexts=[],errors=[]
const base='http://127.0.0.1:5179'
const peopleUrl=`${base}/workspace/${f.wsA}/project/${f.pA1}/people`
async function login(email) {
  const c=await browser.newContext();contexts.push(c)
  const p=await c.newPage();p.on('pageerror',e=>errors.push(e.message))
  p.setDefaultTimeout(15_000)
  p.setDefaultNavigationTimeout(20_000)
  await p.goto(base+'/sign-in')
  await p.getByLabel('Work email').fill(email)
  await p.getByLabel('Password',{exact:true}).fill(f.password)
  await p.getByRole('button',{name:'Sign in',exact:true}).click()
  await p.waitForURL(u=>u.pathname!=='/sign-in')
  return p
}
try {
  const lead=await login(f.people.senior.email)
  await lead.goto(peopleUrl)
  await lead.getByRole('button',{name:'Invite external',exact:true}).waitFor()
  console.log('PASS project lead can open the external invitation flow')
  for (const role of ['reviewer','approver']) {
    const email=`browser-${role}-${Date.now()}@example.test`
    ok(await service.auth.admin.createUser({email,password:f.password,email_confirm:true}))
    await lead.getByRole('button',{name:'Invite external',exact:true}).click()
    const d=lead.getByRole('dialog')
    assert.deepEqual(await d.getByLabel('Project role',{exact:true}).locator('option').evaluateAll(o=>o.map(n=>n.value)),['reviewer','approver'])
    await d.getByLabel('Email',{exact:true}).fill(email)
    await d.getByLabel('Name (optional)',{exact:true}).fill(role==='reviewer'?'Structural consultant':'Client representative')
    await d.getByLabel('Project role',{exact:true}).selectOption(role)
    await d.getByRole('button',{name:'Create invite link',exact:true}).click()
    await d.getByRole('heading',{name:'Invitation created',exact:true}).waitFor()
    const link=await d.locator('code').textContent()
    assert(new URL(link).pathname.startsWith('/invite/'))
    await d.getByRole('button',{name:'Done',exact:true}).click()
    await lead.getByText(email,{exact:true}).waitFor()
    const external=await login(email)
    await external.goto(link)
    await external.getByRole('button',{name:'Accept invitation',exact:true}).click()
    await external.getByText("You're in.",{exact:true}).waitFor()
    await external.getByRole('button',{name:'Continue',exact:true}).click()
    await external.getByRole('heading',{name:'Projects',exact:true}).waitFor()
    await external.getByRole('link',{name:/Garden House/}).waitFor()
    assert.equal(await external.getByRole('link',{name:/Courtyard House/}).count(),0)
    await external.goto(peopleUrl)
    await external.getByRole('heading',{name:'Project people',exact:true}).waitFor()
    assert.equal(await external.getByRole('button',{name:'Invite external',exact:true}).count(),0)
    console.log(`PASS project lead creates ${role} invite in browser; recipient accepts and sees only assigned project`)
  }
  const wsLead=await login(f.people.leadA.email)
  await wsLead.goto(peopleUrl)
  await wsLead.getByRole('button',{name:'Invite external',exact:true}).click()
  assert.equal(await wsLead.getByRole('dialog').getByLabel('Project role',{exact:true}).locator('option').count(),5)
  const junior=await login(f.people.junior.email)
  await junior.goto(peopleUrl)
  await junior.getByRole('heading',{name:'Project people',exact:true}).waitFor()
  assert.equal(await junior.getByRole('button',{name:'Invite external',exact:true}).count(),0)
  assert.deepEqual(errors,[])
  console.log('PASS workspace invitation authority preserved; junior architects and external participants have no invite controls; no browser page errors')
} finally { for(const c of contexts) await c.close();await browser.close() }
