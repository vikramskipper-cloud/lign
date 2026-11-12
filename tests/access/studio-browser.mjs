// Mutating browser integration test: refuses hosted URLs and uses local fixtures.
import assert from 'node:assert/strict'
import { readFileSync, mkdirSync } from 'node:fs'
import { createRequire } from 'node:module'
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright')
const require = createRequire(new URL('../../app/package.json', import.meta.url))
const { createClient } = require('@supabase/supabase-js')
const config = JSON.parse(readFileSync(new URL('../../ops/.tmp/access-local.json', import.meta.url)))
const f = JSON.parse(readFileSync(new URL('../../ops/.tmp/leadership-fixture.json', import.meta.url)))
const backend = new URL(config.API_URL)
assert(['127.0.0.1','localhost'].includes(backend.hostname) && backend.port==='58321')
const base='http://127.0.0.1:5179'
const options={auth:{persistSession:false,autoRefreshToken:false}}
const service=createClient(config.API_URL,config.SERVICE_ROLE_KEY,options)
const manager=createClient(config.API_URL,config.ANON_KEY,options)
const ok=(r)=>{assert.equal(r.error,null,r.error?.message);return r.data}
ok(await manager.auth.signInWithPassword({email:f.people.manager.email,password:f.password}))
const inheritedWs=ok(await manager.rpc('create_workspace_team',{p_organization_id:f.orgId,p_name:`Inherited Team ${Date.now()}`,p_lead_user_id:f.people.leadB.userId}))
// Reset this local fixture so the team-assignment browser check is repeatable.
const reserveMembership=ok(await service.from('workspace_members').select('id,role').eq('workspace_id',f.wsA).eq('user_id',f.people.reserve.userId).maybeSingle())
if(reserveMembership) {
 assert.equal(reserveMembership.role,'member')
 assert.equal(ok(await service.from('project_participants').select('id').eq('workspace_member_id',reserveMembership.id).eq('status','active')).length,0)
 ok(await service.from('workspace_members').update({status:'removed',removed_at:new Date().toISOString()}).eq('id',reserveMembership.id))
}
const browser=await chromium.launch({headless:true,executablePath:process.env.PLAYWRIGHT_CHROMIUM_PATH})
const errors=[]
const contexts=[]
async function login(key, overview=true) {
 const context=await browser.newContext({viewport:{width:1280,height:900}});contexts.push(context)
 const page=await context.newPage();page.on('pageerror',(e)=>errors.push(e.message))
 await page.goto(base+'/sign-in')
 await page.getByLabel('Work email').fill(f.people[key].email)
 await page.getByLabel('Password',{exact:true}).fill(f.password)
 await page.getByRole('button',{name:'Sign in',exact:true}).click()
 await page.waitForURL((u)=>overview ? /\/overview$/.test(u.pathname) : u.pathname==='/dashboard')
 return page
}
const createProject=async(page,name,leadName)=>{
 await page.getByRole('button',{name:'New project',exact:true}).click()
 const dialog=page.getByRole('dialog').filter({has:page.getByRole('heading',{name:'New project',exact:true})})
 await dialog.getByLabel('Project name',{exact:true}).fill(name)
 await dialog.getByLabel('Project lead',{exact:true}).selectOption({label:leadName})
 await dialog.getByRole('button',{name:'Create project',exact:true}).click()
 await page.waitForURL((u)=>/\/project\/[^/]+\/overview$/.test(u.pathname))
 return new URL(page.url()).pathname.split('/')[4]
}
try {
 const owner=await login('owner')
 assert.equal(new URL(owner.url()).pathname,`/org/${f.orgId}/overview`)
 await owner.getByRole('link',{name:'Garden House',exact:true}).waitFor()
 await owner.getByRole('link',{name:'Office Tower',exact:true}).waitFor()
 console.log('PASS studio owner lands on overview and sees every workspace/project')
 await owner.goto(`${base}/workspace/${inheritedWs}/overview`)
 const inheritedProject=await createProject(owner,`Inherited Commission ${Date.now()}`,'Studio leadB')
 const lead=ok(await service.from('project_participants').select('workspace_member:workspace_members(user_id)').eq('project_id',inheritedProject).eq('role','lead').single())
 assert.equal(lead.workspace_member.user_id,f.people.leadB.userId)
 console.log('PASS inherited studio owner creates a project and selects another lead before having workspace membership')
 await owner.goto(`${base}/org/${f.orgId}/overview`)
 await owner.getByRole('button',{name:'New workspace',exact:true}).click()
 const dialog=owner.getByRole('dialog')
 const workspaceName=`Browser Team ${Date.now()}`
 await dialog.getByLabel('Workspace name',{exact:true}).fill(workspaceName)
 await dialog.getByLabel('Workspace lead',{exact:true}).selectOption(f.people.leadB.userId)
 await dialog.getByLabel('Studio senior',{exact:true}).check()
 await dialog.getByLabel('Studio junior',{exact:true}).check()
 await dialog.getByRole('button',{name:'Create workspace',exact:true}).click()
 await owner.waitForURL((u)=>/^\/workspace\/[^/]+\/overview$/.test(u.pathname))
 const newWs=new URL(owner.url()).pathname.split('/')[2]
 await owner.getByText(/Workspace lead: Studio leadB/).waitFor()
 const projectName=`Browser Villa ${Date.now()}`
 await createProject(owner,projectName,'Studio senior')
 await owner.goto(`${base}/org/${f.orgId}/overview`)
 await owner.getByRole('link',{name:projectName,exact:true}).waitFor()
 assert.equal(ok(await service.from('workspace_members').select('role').eq('workspace_id',newWs).eq('user_id',f.people.owner.userId).single()).role,'owner')
 console.log('PASS owner creates workspace, delegates its lead/team, creates project with senior architect lead, and retains ownership')
 const leadA=await login('leadA')
 assert.equal(new URL(leadA.url()).pathname,`/workspace/${f.wsA}/overview`)
 await leadA.getByRole('link',{name:'Garden House',exact:true}).waitFor()
 await leadA.getByRole('link',{name:'Courtyard House',exact:true}).waitFor()
 assert.equal(await leadA.getByRole('link',{name:'Office Tower',exact:true}).count(),0)
 assert.equal(await leadA.getByRole('link',{name:'Studio overview',exact:true}).count(),0)
 await leadA.getByRole('link',{name:'Manage team',exact:true}).first().click()
 assert.deepEqual(await leadA.locator('#assign-workspace-role option').evaluateAll((o)=>o.map((n)=>n.value)),['member'])
 await leadA.getByLabel('Architect',{exact:true}).selectOption(f.people.reserve.userId)
 await leadA.getByRole('button',{name:'Add to workspace',exact:true}).click()
 await leadA.getByText('Architect added to workspace',{exact:true}).waitFor()
 console.log('PASS workspace lead sees all local projects and adds studio architects without studio-wide leadership controls')
 const junior=await login('junior',false)
 await junior.goto(`${base}/workspace/${f.wsA}/projects`)
 await junior.getByRole('link',{name:/Garden House/}).first().waitFor()
 assert.equal(await junior.getByRole('link',{name:/Courtyard House/}).count(),0)
 assert.equal(await junior.getByRole('link',{name:'Workspace overview',exact:true}).count(),0)
 await junior.goto(`${base}/org/${f.orgId}/overview`)
 await junior.getByRole('heading',{name:'Overview unavailable',exact:true}).waitFor()
 assert.equal(await junior.getByRole('link',{name:'Office Tower',exact:true}).count(),0)
 console.log('PASS junior architect sees assigned work and cannot retrieve studio oversight')
 const senior=await login('senior',false)
 await senior.goto(`${base}/workspace/${f.wsA}/project/${f.pA1}/people`)
 await senior.getByLabel('Role for Studio senior',{exact:true}).selectOption('contributor')
 await senior.getByText('Assign another project lead before removing or changing the last lead.',{exact:true}).waitFor()
 console.log('PASS project lead cannot accidentally demote the last lead through the UI')
 await owner.setViewportSize({width:390,height:844})
 await owner.goto(`${base}/org/${f.orgId}/overview`)
 await owner.getByRole('link',{name:projectName,exact:true}).waitFor()
 assert(await owner.evaluate(()=>document.documentElement.scrollWidth<=innerWidth))
 mkdirSync('ops/.tmp',{recursive:true})
 await owner.screenshot({path:'ops/.tmp/studio-overview-mobile.png',fullPage:true})
 assert.deepEqual(errors,[])
 console.log('PASS mobile oversight layout and no browser page errors')
} finally { for(const c of contexts) await c.close();await browser.close() }
