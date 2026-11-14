// Local-only browser checks: create -> client details -> brief -> agreement -> design.
import assert from 'node:assert/strict'
import {ensureAcceptedProposal} from './agree-brief.mjs'
import {readFileSync,mkdirSync} from 'node:fs'
import {createRequire} from 'node:module'
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE??'playwright')
const require=createRequire(new URL('../../app/package.json',import.meta.url)),{createClient}=require('@supabase/supabase-js')
const config=JSON.parse(readFileSync(new URL('../../ops/.tmp/access-local.json',import.meta.url))),f=JSON.parse(readFileSync(new URL('../../ops/.tmp/leadership-fixture.json',import.meta.url)))
const url=new URL(config.API_URL);assert(['localhost','127.0.0.1'].includes(url.hostname)&&url.port==='58321')
const opts={auth:{persistSession:false,autoRefreshToken:false}},service=createClient(config.API_URL,config.SERVICE_ROLE_KEY,opts),api=createClient(config.API_URL,config.ANON_KEY,opts)
const ok=r=>{assert.equal(r.error,null,r.error?.message);return r.data};ok(await api.auth.signInWithPassword({email:f.people.owner.email,password:f.password}))
const browser=await chromium.launch({headless:true,executablePath:process.env.PLAYWRIGHT_CHROMIUM_PATH}),contexts=[],errors=[],base='http://127.0.0.1:5179'
async function login(email){const c=await browser.newContext({viewport:{width:1280,height:900}});contexts.push(c);const p=await c.newPage();p.setDefaultTimeout(25000);p.on('pageerror',e=>errors.push(e.message));await p.goto(base+'/sign-in');await p.getByLabel('Work email').fill(email);await p.getByLabel('Password',{exact:true}).fill(f.password);await p.getByRole('button',{name:'Sign in',exact:true}).click();await p.waitForURL(u=>u.pathname!=='/sign-in');return p}
async function rpcClick(page,rpc,button){const response=page.waitForResponse(r=>r.url().endsWith('/rpc/'+rpc));await page.getByRole('button',{name:button,exact:true}).click();assert((await response).ok());await page.getByText('Unsaved changes',{exact:true}).waitFor({state:'hidden'})}
try{
 const owner=await login(f.people.owner.email),stamp=Date.now(),name='Project setup browser '+stamp
 await owner.goto(`${base}/workspace/${f.wsA}/projects`);await owner.getByRole('button',{name:'New project',exact:true}).first().click()
 const dialog=owner.getByRole('dialog');await dialog.getByLabel('Project name',{exact:true}).fill(name)
 await dialog.getByLabel('Project code',{exact:true}).fill('B'+String(stamp).slice(-10))
 await dialog.getByLabel('Client company',{exact:true}).fill('Example design client')
 await dialog.getByLabel('Client contact name',{exact:true}).fill('Taylor Client')
 await dialog.getByLabel('Client contact email',{exact:true}).fill('taylor@example.test')
 await dialog.getByLabel('Client contact phone',{exact:true}).fill('+91 9999999999')
 await dialog.getByRole('button',{name:'Create project',exact:true}).click();await owner.waitForURL(u=>u.pathname.endsWith('/brief'))
 const id=new URL(owner.url()).pathname.split('/project/')[1].split('/')[0],project=`${base}/workspace/${f.wsA}/project/${id}`
 await owner.getByRole('heading',{name:'Project brief',exact:true}).waitFor()
 for(const section of ['designs','deliverables','reviews','approvals','releases']){await owner.goto(project+'/'+section);await owner.getByRole('heading',{name:'Agree the brief before design work',exact:true}).waitFor();await owner.getByRole('link',{name:'Open project brief',exact:true}).waitFor()}
 await owner.goto(project+'/people');await owner.getByRole('heading',{name:'Project people',exact:true}).waitFor()
 await owner.goto(project+'/overview');await owner.getByText('Taylor Client',{exact:true}).waitFor();await owner.getByRole('button',{name:'Project actions',exact:true}).click();await owner.getByRole('menuitem',{name:'Edit project',exact:true}).click()
 const edit=owner.getByRole('dialog');await edit.getByLabel('Client company',{exact:true}).fill('Updated client company');await edit.getByRole('button',{name:'Save changes',exact:true}).click();await edit.waitFor({state:'hidden'});await owner.getByText('Updated client company',{exact:true}).waitFor()
 assert.equal(ok(await service.from('projects').select('client_email').eq('id',id).single()).client_email,'taylor@example.test')
 const junior=ok(await service.from('workspace_members').select('id').eq('workspace_id',f.wsA).eq('user_id',f.people.junior.userId).single())
 ok(await api.rpc('add_project_participant',{p_project_id:id,p_workspace_member_id:junior.id,p_stakeholder_id:null,p_role:'approver'}))
 console.log('PASS create saves client details and opens the brief; direct design routes are gated; People and client edits remain available')
 await owner.goto(project+'/brief');await owner.getByLabel('What should this project achieve?',{exact:true}).fill('Create an agreed product design')
 await owner.getByLabel('What should we deliver?',{exact:true}).fill('Drawings, specifications and a sample')
 await owner.getByRole('tab',{name:'2. Clarify requirements',exact:true}).click();await owner.getByRole('button',{name:'Add an item',exact:true}).click()
 const item=owner.getByRole('region',{name:'Brief item 1',exact:true});await item.getByLabel('Item title',{exact:true}).fill('Sample quality');await item.getByLabel('How will we check this?',{exact:true}).fill('Client accepts the sample')
 await owner.getByRole('tab',{name:'4. Review and agree',exact:true}).click();await owner.getByLabel('Client / brief approver',{exact:true}).selectOption({label:'Studio junior'})
 await rpcClick(owner,'save_project_brief','Save and start brief');await rpcClick(owner,'transition_project_brief','Review and request agreement')
 await owner.getByRole('link',{name:'Design',exact:true}).click();await owner.getByRole('link',{name:'Design assets',exact:true}).click();await owner.getByRole('heading',{name:'Agree the brief before design work',exact:true}).waitFor()
 const client=await login(f.people.junior.email);await client.goto(project+'/brief?step=agreement');await client.getByLabel('I agree to this brief revision, including its requirements, preferences, assumptions and references.',{exact:true}).check();await rpcClick(client,'respond_project_brief','Agree this revision')
 await owner.getByRole('heading',{name:'Accept the proposal before detailed design',exact:true}).waitFor()
 const approverApi=createClient(config.API_URL,config.ANON_KEY,opts);ok(await approverApi.auth.signInWithPassword({email:f.people.junior.email,password:f.password}));const assigned=ok(await service.from('project_participants').select('id').eq('project_id',id).eq('workspace_member_id',junior.id).single()).id;const reviewApi=createClient(config.API_URL,config.ANON_KEY,opts);ok(await reviewApi.auth.signInWithPassword({email:f.people.leadA.email,password:f.password}));await ensureAcceptedProposal(api,approverApi,id,assigned,reviewApi)
 await owner.getByRole('button',{name:'New asset',exact:true}).first().waitFor();assert.equal(await owner.getByRole('heading',{name:'Agree the brief before design work',exact:true}).count(),0)
 await owner.goto(project+'/brief?step=agreement');await rpcClick(owner,'transition_project_brief','Start a new revision');await owner.goto(project+'/designs');await owner.getByRole('button',{name:'New asset',exact:true}).first().waitFor()
 console.log('PASS actual brief gathering, independent agreement, proposal acceptance and design unlock; revising the brief preserves the agreed baseline')
 await owner.goto(`${base}/workspace/${f.wsA}/projects`);await owner.setViewportSize({width:390,height:844});await owner.getByRole('button',{name:'New project',exact:true}).first().click();await owner.getByLabel('Client contact email',{exact:true}).waitFor();assert(await owner.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));mkdirSync('ops/.tmp',{recursive:true});await owner.screenshot({path:'ops/.tmp/project-setup-mobile.png',fullPage:true});assert.deepEqual(errors,[])
 console.log('PASS mobile creation form fits and no browser page errors')
}catch(err){mkdirSync('ops/.tmp',{recursive:true});for(let i=0;i<contexts.length;i++){const p=contexts[i].pages()[0];if(p){console.log((await p.locator('body').innerText()).slice(-1800));await p.screenshot({path:`ops/.tmp/project-setup-error-${i}.png`,fullPage:true})}}throw err}finally{await browser.close()}
