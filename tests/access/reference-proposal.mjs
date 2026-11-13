// Isolated reference collaboration -> agreed brief -> reviewed proposal -> acceptance.
import assert from 'node:assert/strict'
import {readFileSync,writeFileSync,chmodSync} from 'node:fs'
import {createRequire} from 'node:module'
import {ensureAgreedBrief} from './agree-brief.mjs'
const require=createRequire(new URL('../../app/package.json',import.meta.url)),{createClient}=require('@supabase/supabase-js')
const config=JSON.parse(readFileSync(new URL('../../ops/.tmp/access-local.json',import.meta.url))),f=JSON.parse(readFileSync(new URL('../../ops/.tmp/leadership-fixture.json',import.meta.url)))
const parsed=new URL(config.API_URL);assert(['localhost','127.0.0.1'].includes(parsed.hostname)&&parsed.port==='58321')
const options={auth:{persistSession:false,autoRefreshToken:false},global:{fetch:(i,o)=>fetch(i,{...o,signal:AbortSignal.timeout(20000)})}}
const service=createClient(config.API_URL,config.SERVICE_ROLE_KEY,options),anon=createClient(config.API_URL,config.ANON_KEY,options)
const ok=r=>{assert.equal(r.error,null,r.error?.message);return r.data},denied=(r,c='42501')=>assert.equal(r.error?.code,c,r.error?.message??'Unexpected success')
async function login(email){const c=createClient(config.API_URL,config.ANON_KEY,options);ok(await c.auth.signInWithPassword({email,password:f.password}));return c}
const lead=await login(f.people.senior.email),owner=await login(f.people.owner.email),team=await login(f.people.junior.email),outsider=await login(f.people.reserve.email),project=f.pA1,stamp=Date.now(),people={}
for(const [name,role] of [['client','approver'],['otherClient','approver'],['consultant','reviewer']]){
 const email=`planning-${name.toLowerCase()}-${stamp}@example.test`,u=ok(await service.auth.admin.createUser({email,password:f.password,email_confirm:true,user_metadata:{display_name:'Planning '+name}})).user,c=await login(email)
 const invite=ok(await lead.rpc('invite_stakeholder',{p_workspace_id:f.wsA,p_project_id:project,p_email:email,p_display_name:'Planning '+name,p_role:role}))[0]
 ok(await c.rpc('claim_stakeholder_invitation',{p_token:invite.out_token}))
 const participant=ok(await service.from('project_participants').select('id').eq('project_id',project).eq('stakeholder_id',invite.out_stakeholder_id).single()).id
 people[name]={email,userId:u.id,participantId:participant,stakeholderId:invite.out_stakeholder_id,c}
}
const client=people.client.c,consultant=people.consultant.c
const area=ok(await lead.rpc('save_project_area',{p_project_id:project,p_name:'Living room'}))
const board=ok(await lead.rpc('save_reference_board',{p_project_id:project,p_title:'Living room direction',p_area_id:area}))
const template=ok(await lead.rpc('save_reference_board',{p_project_id:project,p_title:'Studio visual template',p_kind:'template'}))
const card=ok(await lead.rpc('save_reference_card',{p_board_id:board,p_title:'Warm oak direction',p_description:'Consider the material and colour, not the layout',p_url:'https://example.com/oak'}))
const suggestion=ok(await client.rpc('save_reference_card',{p_board_id:board,p_title:'Client suggested fabric',p_description:'I like this texture'}))
denied(await client.rpc('save_reference_board',{p_project_id:project,p_title:'Escalation'}))
denied(await outsider.rpc('get_reference_boards',{p_project_id:project}))
assert((await anon.rpc('get_reference_boards',{p_project_id:project})).error)
assert.equal(ok(await outsider.from('reference_cards').select('id').eq('project_id',project)).length,0)
assert((await client.from('reference_cards').update({selected_for_brief:true}).eq('id',suggestion)).error)
denied(await client.rpc('save_reference_card',{p_board_id:board,p_card_id:card,p_expected_version:1,p_title:'Overwrite team reference'}))
denied(await client.rpc('set_reference_selection',{p_card_id:suggestion,p_selected:true,p_expected_version:1}))
denied(await lead.rpc('save_reference_card',{p_board_id:board,p_title:'Unsafe URL',p_url:'javascript:alert(1)'}),'22023')
ok(await client.rpc('set_reference_preference',{p_card_id:card,p_choice:'shortlisted',p_note:'Use its warm colour'}))
ok(await consultant.rpc('set_reference_preference',{p_card_id:card,p_choice:'liked',p_note:'Suitable finish'}))
const comment=ok(await client.rpc('add_reference_comment',{p_card_id:card,p_body:'Please retain the existing layout.'}))
denied(await service.from('reference_comments').update({body:'Rewrite history'}).eq('id',comment),'23514')
assert.equal(ok(await lead.rpc('get_reference_board',{p_board_id:board})).cards.find(c=>c.id===card).preferences.length,2)
assert.equal(ok(await owner.rpc('lign_project_ready_for_design',{p_project_id:project})),false)
console.log('PASS team boards and client suggestions, named preferences, comments and explicit team selection; no accidental design approval or unauthorized writes')
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=','base64')
const reserve=async(c,{referenceId=null,proposalId=null,version,name='Reference.png',mime='image/png',bytes=png})=>ok(await c.rpc('reserve_planning_upload',{p_name:name,p_mime:mime,p_size:bytes.length,p_reference_id:referenceId,p_proposal_id:proposalId,p_expected_version:version}))
const upload=async(c,args)=>{const r=await reserve(c,args);ok(await c.storage.from('project-planning').upload(r.path,args.bytes??png,{contentType:args.mime??'image/png',upsert:false}));ok(await c.rpc('finalize_planning_upload',{p_file_id:r.id}));return r}
const file=await upload(client,{referenceId:suggestion,version:1})
const currentCard=async(id,c=lead)=>ok(await c.rpc('get_reference_board',{p_board_id:board})).cards.find(x=>x.id===id)
assert((await outsider.storage.from('project-planning').createSignedUrl(file.path,60)).error)
assert((await lead.storage.from('project-planning').download(file.path)).data)
assert((await client.storage.from('project-planning').upload(file.path,png,{contentType:'image/png',upsert:true})).error)
assert((await client.storage.from('project-planning').remove([file.path])).error||ok(await service.from('planning_files').select('id').eq('id',file.id)).length===1)
denied(await lead.rpc('finalize_planning_upload',{p_file_id:file.id}))
assert(Buffer.from(await ok(await client.storage.from('project-planning').download(file.path)).arrayBuffer()).equals(png))
const bad=await reserve(client,{referenceId:suggestion,version:(await currentCard(suggestion)).editVersion,name:'Wrong size.png',bytes:Buffer.concat([png,Buffer.from('extra')])})
ok(await client.storage.from('project-planning').upload(bad.path,png,{contentType:'image/png'}))
denied(await client.rpc('finalize_planning_upload',{p_file_id:bad.id}),'23514')
ok(await client.storage.from('project-planning').remove([bad.path]));assert((await client.storage.from('project-planning').download(bad.path)).error)

const pending=await reserve(consultant,{referenceId:ok(await consultant.rpc('save_reference_card',{p_board_id:board,p_title:'Consultant material'})),version:1})
ok(await lead.rpc('remove_project_participant',{p_participant_id:people.consultant.participantId}))
assert((await consultant.storage.from('project-planning').upload(pending.path,png,{contentType:'image/png'})).error)
denied(await consultant.rpc('finalize_planning_upload',{p_file_id:pending.id}))
ok(await lead.rpc('set_reference_selection',{p_card_id:suggestion,p_selected:true,p_expected_version:(await currentCard(suggestion)).editVersion}))
const templateCard=ok(await lead.rpc('save_reference_card',{p_board_id:template,p_title:'Template oak',p_url:'https://example.com/template'}))
ok(await lead.rpc('set_reference_preference',{p_card_id:templateCard,p_choice:'liked'}))
const templateFile=await upload(lead,{referenceId:templateCard,version:1})
const copied=ok(await lead.rpc('duplicate_reference_template',{p_board_id:template,p_title:'Copied direction',p_area_id:area}))
const copiedCards=ok(await client.rpc('get_reference_board',{p_board_id:copied})).cards
assert.equal(copiedCards.length,1);assert.equal(copiedCards[0].preferences.length,0);assert.equal(copiedCards[0].selected,false)
assert.equal(copiedCards[0].file.path,templateFile.path)
ok(await lead.rpc('remove_reference_attachment',{p_card_id:copiedCards[0].id,p_expected_version:copiedCards[0].editVersion}))
assert.equal(ok(await lead.rpc('get_reference_board',{p_board_id:template})).cards[0].file.path,templateFile.path)
assert.equal(ok(await lead.rpc('get_reference_board',{p_board_id:copied})).cards[0].file,null)
assert((await client.storage.from('project-planning').download(templateFile.path)).data)
console.log('PASS real private uploads, previews/downloads, overwrite denial, reservation ownership and revocation; reusable project templates start with fresh preferences')
assert.equal(ok(await team.rpc('get_project_proposal',{p_project_id:project})).working,null)
const document={title:'Living room proposal',summary:'A warm, durable reception',scope:'Seating and finishes',budget:'INR 500000, indicative',timing:'Six weeks after acceptance',assumptions:'Existing shell retained',sections:[{id:'concept',title:'Living room concept',concept:'Retain the layout and introduce warm oak',materials:'Oak and linen',areaId:area,areaSnapshot:{path:'Forged area'}}],referenceIds:[suggestion],requirementIds:[]}
denied(await team.rpc('save_project_proposal',{p_project_id:project,p_document:document,p_brief_revision_id:crypto.randomUUID(),p_respondent_id:people.client.participantId,p_expected_version:0}),'23514')
await ensureAgreedBrief(lead,client,project,people.client.participantId)
const brief=ok(await lead.rpc('get_project_brief',{p_project_id:project})),briefRevision=brief.brief.current_revision_id
assert.equal(brief.revisions[0].document.referenceSelection[0].title,'Client suggested fabric')
assert.equal(brief.revisions[0].document.referenceSelection[0].file.path,file.path)
ok(await client.rpc('set_reference_preference',{p_card_id:card,p_choice:'rejected',p_note:'Changed my mind'}))
assert.equal(ok(await owner.rpc('lign_project_ready_for_design',{p_project_id:project})),false)
assert.equal(ok(await owner.rpc('get_project_journey',{p_project_id:project})).briefReady,true)
const save=async(doc=document,c=team)=>c.rpc('save_project_proposal',{p_project_id:project,p_document:doc,p_brief_revision_id:briefRevision,p_respondent_id:people.client.participantId,p_expected_version:ok(await c.rpc('get_project_proposal',{p_project_id:project})).working?.edit_version??0})
ok(await save());let state=ok(await team.rpc('get_project_proposal',{p_project_id:project})),proposalId=state.working.id
assert.equal(state.working.document.sections[0].areaSnapshot.path,'Living room')
assert.equal(ok(await client.rpc('get_project_proposal',{p_project_id:project})).working,null)
assert.equal(ok(await client.from('project_proposals').select('document').eq('project_id',project)).length,0)
denied(await client.rpc('save_project_proposal',{p_project_id:project,p_document:document,p_brief_revision_id:briefRevision,p_respondent_id:people.client.participantId,p_expected_version:state.working.edit_version}))
const proposalBytes=Buffer.from('Proposal revision one. Includes oak and linen.'),proposalFile=await upload(team,{proposalId,version:state.working.edit_version,name:'Proposal.txt',mime:'text/plain',bytes:proposalBytes})
assert((await client.storage.from('project-planning').createSignedUrl(proposalFile.path,60)).error)
assert.equal(ok(await client.from('planning_files').select('id').eq('id',proposalFile.id)).length,0)
state=ok(await team.rpc('get_project_proposal',{p_project_id:project}))
const raced=await Promise.all([1,2].map(()=>team.rpc('save_project_proposal',{p_project_id:project,p_document:document,p_brief_revision_id:briefRevision,p_respondent_id:people.client.participantId,p_expected_version:state.working.edit_version})))
assert.equal(raced.filter(r=>!r.error).length,1);assert.equal(raced.filter(r=>r.error?.code==='PT409').length,1)
const transition=async(action,c=lead)=>c.rpc('transition_project_proposal',{p_project_id:project,p_action:action,p_expected_version:ok(await c.rpc('get_project_proposal',{p_project_id:project})).working.edit_version,p_note:'Internal review completed'})
ok(await transition('submit',team));denied(await save(),'23514')
denied(await team.rpc('reserve_planning_upload',{p_name:'Frozen.txt',p_mime:'text/plain',p_size:4,p_proposal_id:proposalId,p_expected_version:ok(await team.rpc('get_project_proposal',{p_project_id:project})).working.edit_version}))
denied(await client.rpc('transition_project_proposal',{p_project_id:project,p_action:'request_acceptance',p_expected_version:1}))
ok(await transition('request_acceptance'))
state=ok(await client.rpc('get_project_proposal',{p_project_id:project}));let revision=state.currentRevisionId
assert.equal(state.canRespond,true);assert.equal(state.working,null)
const reviewed=ok(await client.rpc('get_proposal_revision',{p_revision_id:revision}));assert.equal(reviewed.snapshot.files[0].path,proposalFile.path)
assert((await client.storage.from('project-planning').download(proposalFile.path)).data)
denied(await service.from('proposal_revisions').update({document:{title:'Rewrite'}}).eq('id',revision),'23514')
denied(await people.otherClient.c.rpc('respond_project_proposal',{p_project_id:project,p_revision_id:revision,p_decision:'accepted'}))
denied(await client.rpc('respond_project_proposal',{p_project_id:project,p_revision_id:revision,p_decision:'changes_requested'}),'22023')
ok(await client.rpc('respond_project_proposal',{p_project_id:project,p_revision_id:revision,p_decision:'changes_requested',p_note:'Increase the seating capacity.'}))
assert.equal(ok(await lead.rpc('lign_project_ready_for_design',{p_project_id:project})),false)
console.log('PASS agreed brief unlocks proposal preparation only; working drafts/files are team-only; review freezes edits and creates an immutable package for the named approver')
ok(await save({...document,summary:'Seating increased to eight'}));state=ok(await team.rpc('get_project_proposal',{p_project_id:project}))
ok(await team.rpc('remove_planning_file',{p_file_id:proposalFile.id,p_expected_version:state.working.edit_version}))
const old=await client.storage.from('project-planning').download(proposalFile.path);assert.equal(await ok(old).text(),proposalBytes.toString())
ok(await transition('submit',team));ok(await transition('request_acceptance'));const next=ok(await client.rpc('get_project_proposal',{p_project_id:project})).currentRevisionId
assert.notEqual(revision,next)
denied(await client.rpc('respond_project_proposal',{p_project_id:project,p_revision_id:revision,p_decision:'accepted'}),'PT409')
const accepted=await Promise.all([1,2].map(()=>client.rpc('respond_project_proposal',{p_project_id:project,p_revision_id:next,p_decision:'accepted',p_note:'Agreed revision two'})))
assert.equal(accepted.filter(r=>!r.error).length,1);assert.equal(accepted.filter(r=>r.error?.code==='PT409').length,1)
assert.equal(ok(await lead.rpc('lign_project_ready_for_design',{p_project_id:project})),true)
const asset=ok(await lead.from('design_assets').insert({project_id:project,workspace_id:f.wsA,name:'Accepted detailed design',created_by_profile_id:f.people.senior.userId}).select('id').single())
ok(await lead.rpc('create_draft_version',{p_project_id:project,p_design_asset_id:asset.id}))
ok(await transition('revise'));assert.equal(ok(await lead.rpc('lign_project_ready_for_design',{p_project_id:project})),true)
assert.equal(ok(await client.rpc('get_proposal_revision',{p_revision_id:revision})).document.summary,'A warm, durable reception')
assert.equal(ok(await client.rpc('get_proposal_revision',{p_revision_id:revision})).snapshot.files[0].path,proposalFile.path)
console.log('PASS changes requested retain reviewed files; stale and duplicate decisions fail; accepted revision unlocks detailed design; later drafts preserve the accepted baseline')
// A dual-role studio owner cannot approve their own authored proposal even
// if another lead conducts the internal review.
const second=f.pA2,reviewer=await login(f.people.leadA.email)
ok(await owner.rpc('add_project_participant',{p_project_id:second,p_workspace_member_id:null,p_stakeholder_id:people.client.stakeholderId,p_role:'approver'}))
const recipient=ok(await service.from('project_participants').select('id').eq('project_id',second).eq('stakeholder_id',people.client.stakeholderId).single()).id
await ensureAgreedBrief(owner,client,second,recipient)
const secondBrief=ok(await owner.rpc('get_project_brief',{p_project_id:second})).revisions.find(r=>r.decision?.decision==='agreed').id
const ownerMember=ok(await service.from('workspace_members').select('id').eq('workspace_id',f.wsA).eq('user_id',f.people.owner.userId).single()).id
ok(await owner.rpc('add_project_participant',{p_project_id:second,p_workspace_member_id:ownerMember,p_stakeholder_id:null,p_role:'approver'}))
const self=ok(await service.from('project_participants').select('id').eq('project_id',second).eq('workspace_member_id',ownerMember).single()).id
const secondDoc={...document,sections:[{id:'second',title:'Second concept',concept:'A checked concept',materials:'As agreed',areaId:null}],referenceIds:[]}
denied(await owner.rpc('save_project_proposal',{p_project_id:second,p_document:{...secondDoc,referenceIds:[suggestion]},p_brief_revision_id:secondBrief,p_respondent_id:self,p_expected_version:0}),'23503')
assert.equal(ok(await owner.rpc('get_project_proposal',{p_project_id:second})).working,null)
ok(await owner.rpc('save_project_proposal',{p_project_id:second,p_document:secondDoc,p_brief_revision_id:secondBrief,p_respondent_id:self,p_expected_version:0}))
let secondState=ok(await owner.rpc('get_project_proposal',{p_project_id:second}))
ok(await owner.rpc('transition_project_proposal',{p_project_id:second,p_expected_version:secondState.working.edit_version,p_action:'submit'}))
secondState=ok(await reviewer.rpc('get_project_proposal',{p_project_id:second}))
denied(await reviewer.rpc('transition_project_proposal',{p_project_id:second,p_expected_version:secondState.working.edit_version,p_action:'request_acceptance'}),'23514')
console.log('PASS file size mismatch and unregistered cleanup; cross-project source rejection rolls back atomically; a dual-role author cannot approve their own proposal')
writeFileSync(new URL('../../ops/.tmp/planning-fixture.json',import.meta.url),JSON.stringify({...f,board,card,suggestion,proposalId,proposalFile,area,people:{...f.people,...Object.fromEntries(Object.entries(people).map(([k,v])=>[k,{email:v.email,userId:v.userId,participantId:v.participantId,stakeholderId:v.stakeholderId}]))}}));chmodSync(new URL('../../ops/.tmp/planning-fixture.json',import.meta.url),0o600)
