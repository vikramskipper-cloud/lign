// Isolated browser flow. Requires project-brief.mjs fixtures; never uses hosted data.
import assert from 'node:assert/strict'
import {readFileSync,mkdirSync} from 'node:fs'
import {createRequire} from 'node:module'
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE??'playwright')
const require=createRequire(new URL('../../app/package.json',import.meta.url)),{createClient}=require('@supabase/supabase-js')
const config=JSON.parse(readFileSync(new URL('../../ops/.tmp/access-local.json',import.meta.url))),f=JSON.parse(readFileSync(new URL('../../ops/.tmp/brief-fixture.json',import.meta.url)))
const backend=new URL(config.API_URL);assert(['localhost','127.0.0.1'].includes(backend.hostname)&&backend.port==='58321')
const options={auth:{persistSession:false,autoRefreshToken:false}}
const service=createClient(config.API_URL,config.SERVICE_ROLE_KEY,options),ownerApi=createClient(config.API_URL,config.ANON_KEY,options)
const ok=r=>{assert.equal(r.error,null,r.error?.message);return r.data}
ok(await ownerApi.auth.signInWithPassword({email:f.people.owner.email,password:f.password}))
const browser=await chromium.launch({headless:true,executablePath:process.env.PLAYWRIGHT_CHROMIUM_PATH}),contexts=[],errors=[]
const base='http://127.0.0.1:5179'
async function login(email){const c=await browser.newContext({viewport:{width:1280,height:900}});contexts.push(c);const p=await c.newPage();p.setDefaultTimeout(20000);p.on('pageerror',e=>errors.push(e.message));await p.goto(base+'/sign-in');await p.getByLabel('Work email').fill(email);await p.getByLabel('Password',{exact:true}).fill(f.password);await p.getByRole('button',{name:'Sign in',exact:true}).click();await p.waitForURL(u=>u.pathname!=='/sign-in');return p}
async function save(page,initial=false){const response=page.waitForResponse(r=>r.url().endsWith('/rpc/save_project_brief'));await page.getByRole('button',{name:initial?'Save and start brief':'Save draft',exact:true}).click();assert.equal((await response).status(),200);await page.getByRole('button',{name:'Save draft',exact:true}).waitFor();await page.getByText('Unsaved changes',{exact:true}).waitFor({state:'hidden'})}
try{
 const owner=await login(f.people.owner.email)
 const created=[]
 for(const [industry,question,answer] of [
  ['Interiors','Spaces and activities','Reception for eight visitors and a meeting area.'],
  ['Furniture design','Items, dimensions and fit','A wardrobe fitting a 2200 mm by 600 mm recess.'],
  ['Fashion design','Collection, audience and sizing','A jacket collection using the agreed size chart.'],
 ]){
  await owner.goto(`${base}/workspace/${f.wsA}/overview`)
  await owner.getByRole('button',{name:'New project',exact:true}).click()
  const dialog=owner.getByRole('dialog')
  await dialog.getByLabel('Project name',{exact:true}).fill(`${industry} brief ${Date.now()}`)
  await dialog.getByLabel('Project code').fill(`B${Date.now().toString(36).toUpperCase()}${created.length}`)
  await dialog.getByLabel('Project lead',{exact:true}).selectOption({label:'Studio senior'})
  const creation=owner.waitForResponse(r=>r.url().endsWith('/rpc/create_project_full'))
  await dialog.getByRole('button',{name:'Create project',exact:true}).click()
  const creationResponse=await creation
  assert.equal(creationResponse.status(),200,await creationResponse.text())
  await owner.waitForURL(u=>/\/project\/[^/]+\/brief$/.test(u.pathname))
  const projectId=new URL(owner.url()).pathname.split('/')[4]
  await owner.getByLabel(industry,{exact:true}).check()
  await owner.getByLabel(question,{exact:true}).fill(answer)
  await owner.getByLabel('What should this project achieve?',{exact:true}).fill(`${industry}: an agreed design outcome.`)
  await owner.getByLabel('What should we deliver?',{exact:true}).fill('The agreed designs, specifications and reference samples.')
  if(industry==='Interiors'){
   await owner.getByLabel('Furniture design',{exact:true}).check()
   await owner.getByLabel('Items, dimensions and fit',{exact:true}).fill('Custom reception seating with supplied dimensions.')
  }
  await save(owner,true)
  const state=ok(await ownerApi.rpc('get_project_brief',{p_project_id:projectId}))
  assert(state.brief.document.fields.some(q=>q.answer===answer))
  created.push(projectId)
 }
 console.log('PASS new projects start at the brief; interiors, furniture and fashion share one flow with editable and combinable discipline questions')
 const projectId=created[0],briefUrl=`${base}/workspace/${f.wsA}/project/${projectId}/brief`
 ok(await ownerApi.rpc('add_project_participant',{p_project_id:projectId,p_workspace_member_id:null,p_stakeholder_id:f.clients.client.stakeholderId,p_role:'approver'}))
 await owner.goto(briefUrl)
 await owner.getByRole('tab',{name:'4. Review and agree',exact:true}).click()
 await owner.getByLabel('Client / brief approver',{exact:true}).selectOption({label:'Brief client'})
 await save(owner)
 const client=await login(f.clients.client.email)
 await client.goto(briefUrl)
 await client.getByLabel('What should this project achieve?',{exact:true}).fill('A welcoming reception with seating for eight visitors.')
 await client.getByRole('tab',{name:'2. Clarify requirements',exact:true}).click()
 await client.getByRole('button',{name:'Add an item',exact:true}).click()
 const item=client.getByRole('region',{name:'Brief item 1',exact:true})
 await item.getByLabel('Item title',{exact:true}).fill('Reception seats eight')
 await item.getByLabel('Details',{exact:true}).fill('Allow visitors to wait comfortably.')
 await item.getByLabel('Applies to',{exact:true}).fill('Reception seating')
 await item.getByLabel('How will we check this?',{exact:true}).fill('Count eight seats in the agreed furniture layout.')
 await client.getByRole('tab',{name:'3. References',exact:true}).click()
 await client.getByRole('button',{name:'Add a reference link',exact:true}).click()
 await client.getByLabel('Reference label',{exact:true}).fill('Client inspiration')
 await client.getByLabel('Reference URL',{exact:true}).fill('https://example.com/inspiration')
 await save(client)
 await client.getByLabel('Upload reference file',{exact:true}).setInputFiles({name:'Client reference.txt',mimeType:'text/plain',buffer:Buffer.from('Client supplied reference for the brief.')})
 await client.getByRole('button',{name:/Client reference.txt/}).waitFor()
 await client.getByLabel('Add a clarification note',{exact:true}).fill('Please retain the existing reception desk.')
 await client.getByRole('button',{name:'Post note',exact:true}).click()
 await client.getByText('Please retain the existing reception desk.',{exact:true}).waitFor()
 await client.getByRole('tab',{name:'4. Review and agree',exact:true}).click()
 await client.getByRole('button',{name:'Submit for team review',exact:true}).click()
 await client.getByText('Ready for team review',{exact:true}).waitFor()
 console.log('PASS assigned client completes the brief, records a requirement and reference link, uploads a private file, clarifies and submits')
 await owner.goto(briefUrl)
 await owner.getByRole('tab',{name:'4. Review and agree',exact:true}).click()
 await owner.getByRole('button',{name:'Review and request agreement',exact:true}).click()
 await owner.getByText('Awaiting agreement',{exact:true}).waitFor()
 await client.reload()
 await client.getByRole('tab',{name:'4. Review and agree',exact:true}).click()
 await client.getByLabel('I agree to this brief revision, including its requirements, preferences, assumptions and references.',{exact:true}).check()
 await client.getByRole('button',{name:'Agree this revision',exact:true}).click()
 await client.getByText('Agreed',{exact:true}).first().waitFor()
 await owner.goto(briefUrl)
 await owner.getByRole('tab',{name:'4. Review and agree',exact:true}).click()
 await owner.getByRole('button',{name:'Create draft requirements',exact:true}).click()
 await owner.getByText('1 drafts generated from this revision.',{exact:false}).waitFor()
 await owner.getByRole('link',{name:'Review and activate requirements',exact:true}).click()
 await owner.getByRole('link',{name:/Reception seats eight/}).click()
 await owner.getByRole('button',{name:'Activate requirement',exact:true}).click()
 await owner.getByText('Active',{exact:true}).first().waitFor()
 const rows=ok(await service.from('requirements').select('status').eq('project_id',projectId))
 assert.deepEqual(rows.map(r=>r.status),['active'])
 console.log('PASS leadership reviews, named client agrees an exact revision, and the team generates, reviews and activates the requirement')
 await owner.goto(briefUrl)
 await owner.getByRole('tab',{name:'4. Review and agree',exact:true}).click()
 await owner.getByRole('button',{name:'Start a new revision',exact:true}).click()
 await owner.getByRole('tab',{name:'1. Gather needs',exact:true}).click()
 await owner.getByLabel('What should this project achieve?',{exact:true}).fill('A revised outcome after the first agreement.')
 await save(owner)
 await owner.getByLabel('View',{exact:true}).selectOption({label:'Revision 1 · Agreed'})
 assert.equal(await owner.getByLabel('What should this project achieve?',{exact:true}).inputValue(),'A welcoming reception with seating for eight visitors.')
 assert.equal(await owner.getByLabel('What should this project achieve?',{exact:true}).isDisabled(),true)
 await owner.setViewportSize({width:390,height:844})
 assert(await owner.evaluate(()=>document.documentElement.scrollWidth<=innerWidth))
 mkdirSync('ops/.tmp',{recursive:true})
 await owner.screenshot({path:'ops/.tmp/project-brief-mobile.png',fullPage:true})
 assert.deepEqual(errors,[])
 console.log('PASS earlier agreement is read-only and unchanged after a new draft; mobile layout fits and no browser page errors occur')
}catch(error){
 mkdirSync('ops/.tmp',{recursive:true})
 for(const c of contexts){const p=c.pages()[0];if(p){console.log('Browser failure at',new URL(p.url()).pathname);console.log((await p.locator('body').innerText()).slice(-2200));await p.screenshot({path:'ops/.tmp/project-brief-error.png',fullPage:true})}}
 throw error
}finally{for(const c of contexts)await c.close();await browser.close()}
