// Local integration: one organisation catalogue across workspaces, scoped project publication.
import assert from 'node:assert/strict'
import {readFileSync,writeFileSync,chmodSync} from 'node:fs'
import {createRequire} from 'node:module'
const require=createRequire(new URL('../../app/package.json',import.meta.url)),{createClient}=require('@supabase/supabase-js')
const config=JSON.parse(readFileSync(new URL('../../ops/.tmp/access-local.json',import.meta.url))),f=JSON.parse(readFileSync(new URL('../../ops/.tmp/planning-fixture.json',import.meta.url)))
const url=new URL(config.API_URL);assert(['localhost','127.0.0.1'].includes(url.hostname)&&url.port==='58321')
const opts={auth:{persistSession:false,autoRefreshToken:false}},service=createClient(config.API_URL,config.SERVICE_ROLE_KEY,opts),anon=createClient(config.API_URL,config.ANON_KEY,opts)
const ok=r=>{assert.equal(r.error,null,r.error?.message);return r.data},deny=(r,code='42501')=>assert.equal(r.error?.code,code,r.error?.message??'Unexpected success')
async function login(person){const c=createClient(config.API_URL,config.ANON_KEY,opts);ok(await c.auth.signInWithPassword({email:person.email,password:f.password}));return c}
const owner=await login(f.people.owner),member=await login(f.people.reserve),lead=await login(f.people.senior),client=await login(f.people.client),stamp=Date.now()
const version=async id=>ok(await owner.rpc('get_organization_library',{p_organization_id:f.orgId})).collections.find(c=>c.id===id).edit_version
const transition=async(id,action)=>ok(await owner.rpc('transition_library_collection',{p_collection_id:id,p_expected_version:await version(id),p_action:action}))
const publish=async id=>{await transition(id,'submit');await transition(id,'publish')}
const collection=ok(await owner.rpc('save_library_collection',{p_organization_id:f.orgId,p_title:`Shared material directions ${stamp}`,p_kind:'template',p_description:'Reusable across residential and commercial projects'}))
assert(!ok(await member.rpc('get_organization_library',{p_organization_id:f.orgId})).collections.some(c=>c.id===collection))
assert(ok(await member.rpc('save_library_collection',{p_organization_id:f.orgId,p_title:'Member draft',p_kind:'template'})))
deny(await client.rpc('get_organization_library',{p_organization_id:f.orgId}));assert.equal(ok(await client.from('library_collections').select('id')).length,0)
assert((await anon.rpc('get_organization_library',{p_organization_id:f.orgId})).error)
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=','base64')
async function upload(name='Oak.png'){const r=ok(await owner.rpc('reserve_library_upload',{p_organization_id:f.orgId,p_name:name,p_mime:'image/png',p_size:png.length}));ok(await owner.storage.from('organization-library').upload(r.path,png,{contentType:'image/png',upsert:false}));assert((await client.storage.from('organization-library').download(r.path)).error);ok(await owner.rpc('finalize_library_upload',{p_file_id:r.id}));return r}
const file=await upload(),secret=await upload('Unshared.png')
assert((await owner.storage.from('organization-library').upload(file.path,png,{contentType:'image/png',upsert:true})).error)
await owner.storage.from('organization-library').remove([file.path]);assert((await owner.storage.from('organization-library').download(file.path)).data)
const item=ok(await owner.rpc('save_library_item',{p_collection_id:collection,p_title:'Natural oak',p_description:'Warm texture',p_url:'https://example.com/oak',p_file_id:file.id}))
deny(await client.rpc('get_library_items',{p_collection_id:collection}));deny(await member.rpc('save_library_item',{p_collection_id:collection,p_title:'No'}))
deny(await owner.rpc('save_library_item',{p_collection_id:collection,p_title:'Bad URL',p_url:'javascript:alert(1)'}),'23514')
deny(await owner.rpc('save_library_item',{p_collection_id:collection,p_id:item,p_title:'Stale',p_expected_version:0}),'PT409')
await publish(collection)
const importBoard=async(c,project,title)=>ok(await c.rpc('import_library_collection',{p_collection_id:collection,p_project_id:project,p_title:title}))
const boardA=await importBoard(lead,f.pA1,'Library import residential'),boardB=await importBoard(owner,f.pB1,'Library import commercial')
const cards=async(c,id)=>ok(await c.rpc('get_reference_board',{p_board_id:id})).cards
const a=(await cards(client,boardA))[0],b=(await cards(owner,boardB))[0]
assert.equal(a.title,'Natural oak');assert.equal(b.file.id,file.id);assert.equal(a.file.bucket,'organization-library');assert.equal(a.preferences.length,0);assert.equal(a.selected,false);assert.equal(a.commentCount,0)
assert(Buffer.from(await ok(await client.storage.from('organization-library').download(file.path)).arrayBuffer()).equals(png))
assert((await client.storage.from('organization-library').download(secret.path)).error)
deny(await client.rpc('import_library_collection',{p_collection_id:collection,p_project_id:f.pA1,p_title:'Denied'}));deny(await member.rpc('import_library_collection',{p_collection_id:collection,p_project_id:f.pA1,p_title:'Denied'}))
// Synthetic second tenant; fixture setup uses service role, permissions are tested as a real user.
const otherOrg=ok(await service.from('organizations').insert({name:`Library isolation ${stamp}`,slug:`library-isolation-${stamp}`}).select('id').single()).id
ok(await service.from('organization_members').insert({organization_id:otherOrg,user_id:f.people.owner.userId,role:'owner',status:'active'}))
const otherWs=ok(await owner.rpc('create_workspace_team',{p_organization_id:otherOrg,p_name:'Other studio',p_lead_user_id:f.people.owner.userId,p_member_user_ids:[]}))
const otherProject=ok(await owner.rpc('create_project_full',{p_workspace_id:otherWs,p_name:'Other organisation',p_client_emails:[]}))
const otherId=(Array.isArray(otherProject)?otherProject[0]:otherProject).out_project_id
deny(await owner.rpc('import_library_collection',{p_collection_id:collection,p_project_id:otherId,p_title:'Cross org'}))
console.log('PASS shared catalogue across two workspaces; member drafts with admin approval; guest and cross-tenant denials; private files published only to selected projects')
await transition(collection,'revise')
const next=await upload('Replacement.png')
ok(await owner.rpc('save_library_item',{p_collection_id:collection,p_id:item,p_expected_version:1,p_title:'Updated source',p_file_id:next.id}))
assert.equal((await cards(client,boardA))[0].title,'Natural oak');assert.equal((await cards(client,boardA))[0].file.id,file.id)
assert((await client.storage.from('organization-library').download(next.path)).error)
ok(await lead.rpc('set_reference_preference',{p_card_id:a.id,p_choice:'liked'}));assert.equal((await cards(owner,boardB))[0].preferences.length,0)
ok(await owner.rpc('save_library_collection',{p_organization_id:f.orgId,p_id:collection,p_title:'Archived source',p_kind:'template',p_expected_version:await version(collection),p_archive:true}))
deny(await lead.rpc('import_library_collection',{p_collection_id:collection,p_project_id:f.pA1,p_title:'Archived'}))
assert((await client.storage.from('organization-library').download(file.path)).data)
ok(await lead.rpc('remove_reference_attachment',{p_card_id:a.id,p_expected_version:a.editVersion}));assert.equal((await cards(client,boardA))[0].file,null);assert.equal((await cards(owner,boardB))[0].file.id,file.id)
// History publication survives a working-card detach.
assert((await client.storage.from('organization-library').download(file.path)).data)
assert((await client.rpc('library_file_snapshot',{p_file_id:secret.id})).error)
console.log('PASS independent project copies, source edits/archive, immutable shared bytes, card-specific detach and retained historical access')
const demo=ok(await owner.rpc('save_library_collection',{p_organization_id:f.orgId,p_title:`Studio essentials ${stamp}`,p_kind:'references',p_description:'A shared collection for the demo'}))
ok(await owner.rpc('save_library_item',{p_collection_id:demo,p_title:'Timber palette',p_description:'A warm natural finish',p_file_id:next.id,p_url:'https://example.com/timber'}))
await publish(demo)
const path=new URL('../../ops/.tmp/library-fixture.json',import.meta.url);writeFileSync(path,JSON.stringify({org:f.orgId,collection:demo,project:f.pA1,workspace:f.wsA}));chmodSync(path,0o600)
