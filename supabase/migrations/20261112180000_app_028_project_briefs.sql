-- APP 028: collaborative project briefs, immutable agreement revisions,
-- private reference files and idempotent draft requirement generation.
create table public.project_briefs (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null unique, workspace_id uuid not null,
 document jsonb not null, respondent_participant_id uuid references public.project_participants(id),
 status text not null default 'draft' check(status in ('draft','submitted','awaiting_agreement','agreed')),
 edit_version bigint not null default 1, revision_number integer not null default 0,
 current_revision_id uuid, created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 foreign key(project_id,workspace_id) references public.projects(id,workspace_id),
 unique(id,project_id,workspace_id), unique(id,project_id)
);
create table public.project_brief_revisions (
 id uuid primary key default gen_random_uuid(), brief_id uuid not null references public.project_briefs(id),
 project_id uuid not null, workspace_id uuid not null, number integer not null,
 document jsonb not null, attachments jsonb not null,
 respondent_participant_id uuid not null references public.project_participants(id),
 requested_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 foreign key(brief_id,project_id,workspace_id) references public.project_briefs(id,project_id,workspace_id),
 unique(brief_id,number), unique(id,project_id)
);
alter table public.project_briefs add constraint project_briefs_current_revision_fk
 foreign key(current_revision_id) references public.project_brief_revisions(id);
create table public.project_brief_decisions (
 id uuid primary key default gen_random_uuid(), revision_id uuid not null unique references public.project_brief_revisions(id),
 project_id uuid not null references public.projects(id),
 decision text not null check(decision in ('agreed','changes_requested')),
 comment text not null default '', actor_id uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 foreign key(revision_id,project_id) references public.project_brief_revisions(id,project_id)
);
create table public.project_brief_notes (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.projects(id),
 author_id uuid not null references public.profiles(id), body text not null check(length(body) between 1 and 5000),
 created_at timestamptz not null default now()
);
create table public.project_brief_files (
 id uuid primary key default gen_random_uuid(), brief_id uuid not null references public.project_briefs(id),
 project_id uuid not null references public.projects(id), storage_path text not null unique,
 name text not null, size_bytes bigint not null, uploaded_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(), removed_at timestamptz,
 foreign key(brief_id,project_id) references public.project_briefs(id,project_id)
);
create table public.project_brief_requirement_links (
 revision_id uuid not null references public.project_brief_revisions(id), item_id text not null,
 project_id uuid not null references public.projects(id), requirement_id uuid not null references public.requirements(id),
 primary key(revision_id,item_id),
 foreign key(revision_id,project_id) references public.project_brief_revisions(id,project_id),
 foreign key(requirement_id,project_id) references public.requirements(id,project_id)
);
create index project_brief_notes_project_idx on public.project_brief_notes(project_id,created_at);
create index project_brief_files_project_idx on public.project_brief_files(project_id);
create index project_brief_revisions_project_idx on public.project_brief_revisions(project_id,number);

create or replace function public.lign_manage_project_brief(p_project_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.projects p where p.id=p_project_id and p.archived_at is null
 and p.status<>'archived' and public.lign_has_capability(p.id,p.workspace_id,'project.manage_access')); $$;

create or replace function public.lign_brief_respondent_user(p_participant_id uuid,p_project_id uuid)
returns uuid language sql stable security definer set search_path=''
as $$ select coalesce(wm.user_id,s.user_id) from public.project_participants pp
 left join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
 left join public.stakeholders s on s.id=pp.stakeholder_id and s.status='active'
 where pp.id=p_participant_id and pp.project_id=p_project_id and pp.status='active' and pp.role='approver'; $$;

create or replace function public.lign_edit_project_brief(p_project_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.project_briefs b join public.projects p on p.id=b.project_id
 where b.project_id=p_project_id and b.status='draft' and p.archived_at is null and p.status<>'archived'
 and (public.lign_manage_project_brief(p.id) or (auth.uid() is not null
 and public.lign_brief_respondent_user(b.respondent_participant_id,p.id)=auth.uid()
 and public.lign_has_capability(p.id,p.workspace_id,'project.view')))); $$;

alter table public.project_briefs enable row level security;
alter table public.project_brief_revisions enable row level security;
alter table public.project_brief_decisions enable row level security;
alter table public.project_brief_notes enable row level security;
alter table public.project_brief_files enable row level security;
alter table public.project_brief_requirement_links enable row level security;
create policy project_briefs_read on public.project_briefs for select to authenticated using(public.lign_has_capability(project_id,workspace_id,'project.view'));
create policy project_brief_revisions_read on public.project_brief_revisions for select to authenticated using(public.lign_has_capability(project_id,workspace_id,'project.view'));
create policy project_brief_decisions_read on public.project_brief_decisions for select to authenticated using(exists(select 1 from public.projects p where p.id=project_id and public.lign_has_capability(p.id,p.workspace_id,'project.view')));
create policy project_brief_notes_read on public.project_brief_notes for select to authenticated using(exists(select 1 from public.projects p where p.id=project_id and public.lign_has_capability(p.id,p.workspace_id,'project.view')));
create policy project_brief_files_read on public.project_brief_files for select to authenticated using(exists(select 1 from public.projects p where p.id=project_id and public.lign_has_capability(p.id,p.workspace_id,'project.view')));
create policy project_brief_requirement_links_read on public.project_brief_requirement_links for select to authenticated using(exists(select 1 from public.projects p where p.id=project_id and public.lign_has_capability(p.id,p.workspace_id,'project.view')));
revoke all on public.project_briefs,public.project_brief_revisions,public.project_brief_decisions,public.project_brief_notes,public.project_brief_files,public.project_brief_requirement_links from anon,authenticated;
grant select on public.project_briefs,public.project_brief_revisions,public.project_brief_decisions,public.project_brief_notes,public.project_brief_files,public.project_brief_requirement_links to authenticated;

create or replace function public.validate_project_brief_document(p_document jsonb)
returns void language plpgsql security definer set search_path=''
as $fn$
declare v jsonb; v_ids text[]:='{}'; v_owner uuid;
begin
 if jsonb_typeof(p_document) is distinct from 'object' or octet_length(p_document::text)>300000
 or jsonb_typeof(p_document->'fields') is distinct from 'array'
 or jsonb_typeof(p_document->'items') is distinct from 'array'
 or jsonb_typeof(p_document->'references') is distinct from 'array'
 or jsonb_typeof(p_document->'disciplines') is distinct from 'array' then
  raise exception 'Invalid brief document' using errcode='22023'; end if;
 if jsonb_array_length(p_document->'fields')>60 or jsonb_array_length(p_document->'items')>100
 or jsonb_array_length(p_document->'references')>30 or jsonb_array_length(p_document->'disciplines')>6 then
  raise exception 'This brief exceeds the supported number of questions, requirements or references' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(p_document->'disciplines') d where jsonb_typeof(d) is distinct from 'string' or length(d#>>'{}')>60) then
  raise exception 'Choose text discipline labels' using errcode='22023'; end if;
 for v in select value from jsonb_array_elements(p_document->'fields') loop
  if jsonb_typeof(v->'id') is distinct from 'string' or jsonb_typeof(v->'label') is distinct from 'string'
   or (v?'help' and jsonb_typeof(v->'help') is distinct from 'string') or length(coalesce(v->>'help',''))>500
   or coalesce(length(v->>'id'),0) not between 1 and 100 or v->>'id'=any(v_ids)
   or coalesce(length(trim(v->>'label')),0) not between 1 and 200
   or jsonb_typeof(v->'answer') is distinct from 'string' or length(v->>'answer')>10000 then
   raise exception 'Each brief question needs a unique ID, a label and a text answer' using errcode='22023'; end if;
  v_ids:=array_append(v_ids,v->>'id');
 end loop;
 if not ('objective'=any(v_ids) and 'deliverables'=any(v_ids)) then
  raise exception 'Keep the objective and deliverables questions in the brief' using errcode='22023'; end if;
 v_ids:='{}';
 for v in select value from jsonb_array_elements(p_document->'items') loop
  if jsonb_typeof(v->'id') is distinct from 'string' or jsonb_typeof(v->'title') is distinct from 'string'
   or exists(select 1 from jsonb_each(v) e where e.key in ('detail','acceptance','resolution','appliesTo','ownerProfileId') and jsonb_typeof(e.value) not in ('string','null'))
   or coalesce(length(v->>'id'),0) not between 1 and 100 or v->>'id'=any(v_ids)
   or coalesce(length(trim(v->>'title')),0) not between 1 and 200
   or coalesce(v->>'kind','') not in ('mandatory','preference','assumption','question')
   or coalesce(v->>'priority','') not in ('critical','high','medium','low','informational')
   or coalesce(v->>'source','') not in ('client','consultant','internal_team','other')
   or length(coalesce(v->>'detail',''))>5000 or length(coalesce(v->>'acceptance',''))>3000
   or length(coalesce(v->>'resolution',''))>3000 or length(coalesce(v->>'appliesTo',''))>1000 then
   raise exception 'Check the requirement title, kind, priority and source' using errcode='22023'; end if;
  v_owner:=nullif(v->>'ownerProfileId','')::uuid;
  v_ids:=array_append(v_ids,v->>'id');
 end loop;
 for v in select value from jsonb_array_elements(p_document->'references') loop
  if jsonb_typeof(v->'id') is distinct from 'string' or jsonb_typeof(v->'url') is distinct from 'string' or jsonb_typeof(v->'label') is distinct from 'string'
   or coalesce(length(v->>'url'),0)>2000 or coalesce(v->>'url','') !~ '^https?://[^[:space:]]+$'
   or coalesce(length(trim(v->>'label')),0) not between 1 and 200 then
   raise exception 'References need a label and an http or https URL' using errcode='22023'; end if;
 end loop;
end;
$fn$;

create or replace function public.get_project_brief(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_ws uuid; v_b public.project_briefs%rowtype;
begin
 select workspace_id into v_ws from public.projects where id=p_project_id;
 if v_ws is null or not public.lign_has_capability(p_project_id,v_ws,'project.view') then
  raise exception 'Project access required' using errcode='42501'; end if;
 select * into v_b from public.project_briefs where project_id=p_project_id;
 return jsonb_build_object('brief',case when v_b.id is null then null else to_jsonb(v_b) end,
  'canManage',public.lign_manage_project_brief(p_project_id),
  'canEdit',coalesce(public.lign_edit_project_brief(p_project_id),false),
  'canComment',public.lign_has_capability(p_project_id,v_ws,'comment.create'),
  'canGenerate',public.lign_has_capability(p_project_id,v_ws,'requirement.create'),
  'canRespond',coalesce(v_b.status='awaiting_agreement' and public.lign_brief_respondent_user(v_b.respondent_participant_id,p_project_id)=auth.uid(),false),
  'approvers',(select coalesce(jsonb_agg(jsonb_build_object('id',pp.id,'name',coalesce(p.display_name,s.display_name,s.email::text),'pending',s.id is not null and (s.user_id is null or s.status<>'active')) order by coalesce(p.display_name,s.display_name,s.email::text)),'[]'::jsonb)
   from public.project_participants pp left join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
   left join public.profiles p on p.id=wm.user_id left join public.stakeholders s on s.id=pp.stakeholder_id and s.status in ('active','invited')
   where pp.project_id=p_project_id and pp.status='active' and pp.role='approver' and (wm.id is not null or s.id is not null)),
  'owners',(select coalesce(jsonb_agg(jsonb_build_object('id',wm.user_id,'name',p.display_name) order by p.display_name),'[]'::jsonb)
   from public.project_participants pp join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
   join public.profiles p on p.id=wm.user_id where pp.project_id=p_project_id and pp.status='active' and pp.role in ('lead','contributor')),
  'files',(select coalesce(jsonb_agg(to_jsonb(f) order by f.created_at),'[]'::jsonb) from public.project_brief_files f where f.project_id=p_project_id and f.removed_at is null),
  'revisions',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('decision',(select to_jsonb(d)||jsonb_build_object('actorName',p.display_name) from public.project_brief_decisions d join public.profiles p on p.id=d.actor_id where d.revision_id=r.id),
   'generatedCount',(select count(*) from public.project_brief_requirement_links l where l.revision_id=r.id)) order by r.number desc),'[]'::jsonb) from public.project_brief_revisions r where r.project_id=p_project_id),
  'notes',(select coalesce(jsonb_agg(to_jsonb(n)||jsonb_build_object('authorName',p.display_name) order by n.created_at),'[]'::jsonb) from public.project_brief_notes n join public.profiles p on p.id=n.author_id where n.project_id=p_project_id));
end;
$fn$;

create or replace function public.save_project_brief(p_project_id uuid,p_document jsonb,p_expected_version bigint,p_respondent_participant_id uuid default null)
returns bigint language plpgsql security definer set search_path=''
as $fn$
declare v_ws uuid; v_b public.project_briefs%rowtype; v_manager boolean; v_version bigint; v_item jsonb;
begin
 select workspace_id into v_ws from public.projects where id=p_project_id for no key update;
 v_manager:=public.lign_manage_project_brief(p_project_id);
 select * into v_b from public.project_briefs where project_id=p_project_id for update;
 if not coalesce(v_manager,false) and not coalesce(public.lign_edit_project_brief(p_project_id),false) then
  raise exception 'Only project leadership and the assigned brief approver can edit this draft' using errcode='42501'; end if;
 if p_expected_version is null or (v_b.id is null and p_expected_version<>0) or (v_b.id is not null and v_b.edit_version<>p_expected_version) then
  raise exception 'The brief changed. Reload the latest version before saving.' using errcode='PT409'; end if;
 if v_b.id is not null and v_b.status<>'draft' then raise exception 'Start a new draft before editing this brief' using errcode='23514'; end if;
 if not v_manager and p_respondent_participant_id is distinct from v_b.respondent_participant_id then
  raise exception 'Only project leadership can assign the brief approver' using errcode='42501'; end if;
 if p_respondent_participant_id is not null and not exists(select 1 from public.project_participants pp
  left join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
  left join public.stakeholders s on s.id=pp.stakeholder_id and s.status in ('active','invited')
  where pp.id=p_respondent_participant_id and pp.project_id=p_project_id and pp.status='active' and pp.role='approver' and (wm.id is not null or s.id is not null)) then
  raise exception 'Choose an active project approver or invite a client as an approver' using errcode='23514'; end if;
 perform public.validate_project_brief_document(p_document);
 for v_item in select value from jsonb_array_elements(p_document->'items') loop
  if nullif(v_item->>'ownerProfileId','') is not null and not exists(select 1 from public.project_participants pp
   join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
   where pp.project_id=p_project_id and pp.status='active' and pp.role in ('lead','contributor') and wm.user_id=(v_item->>'ownerProfileId')::uuid) then
   raise exception 'Choose a project lead or contributor responsible for this requirement' using errcode='23514'; end if;
 end loop;
 if v_b.id is null then
  insert into public.project_briefs(project_id,workspace_id,document,respondent_participant_id,created_by)
  values(p_project_id,v_ws,p_document,p_respondent_participant_id,auth.uid()) returning edit_version into v_version;
 else
  update public.project_briefs set document=p_document,respondent_participant_id=p_respondent_participant_id,edit_version=edit_version+1,updated_at=now()
   where id=v_b.id returning edit_version into v_version;
 end if;
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label)
 values(v_ws,p_project_id,'brief.saved',auth.uid(),'user','project',p_project_id,'Project brief');
 return v_version;
end;
$fn$;

create or replace function public.transition_project_brief(p_project_id uuid,p_expected_version bigint,p_action text)
returns bigint language plpgsql security definer set search_path=''
as $fn$
declare v_b public.project_briefs%rowtype; v_manager boolean; v_status text; v_item jsonb; v_revision uuid; v_files jsonb; v_owner uuid; v_items jsonb:='[]'::jsonb;
begin
 select * into v_b from public.project_briefs where project_id=p_project_id for update;
 v_manager:=public.lign_manage_project_brief(p_project_id);
 if v_b.id is null or not (v_manager or (p_action='submit' and public.lign_edit_project_brief(p_project_id))) then
  raise exception 'Brief editing or project leadership required' using errcode='42501'; end if;
 if v_b.edit_version is distinct from p_expected_version then raise exception 'The brief changed. Reload before continuing.' using errcode='PT409'; end if;
 if p_action='submit' and v_b.status='draft' then v_status:='submitted';
 elsif p_action='return_to_draft' and v_b.status in ('submitted','awaiting_agreement') then v_status:='draft';
 elsif p_action='revise' and v_b.status='agreed' then v_status:='draft';
 elsif p_action='request_agreement' and v_b.status in ('draft','submitted') then
  if public.lign_brief_respondent_user(v_b.respondent_participant_id,p_project_id) is null then
   raise exception 'Assign a project approver who has accepted their invitation before requesting agreement' using errcode='23514'; end if;
  if public.lign_brief_respondent_user(v_b.respondent_participant_id,p_project_id)=auth.uid() then
   raise exception 'A different project approver must agree the brief you review' using errcode='23514'; end if;
  if not exists(select 1 from jsonb_array_elements(v_b.document->'items') i where i->>'kind' in ('mandatory','preference')) then
   raise exception 'Add at least one requirement or preference before agreement' using errcode='23514'; end if;
  for v_item in select value from jsonb_array_elements(v_b.document->'items') loop
   if v_item->>'kind'='question' and trim(coalesce(v_item->>'resolution',''))='' then
    raise exception 'Resolve open questions before requesting agreement' using errcode='23514'; end if;
   if v_item->>'kind' in ('mandatory','preference') and trim(coalesce(v_item->>'acceptance',''))='' then
    raise exception 'Describe how each requirement or preference will be checked' using errcode='23514'; end if;
   if v_item->>'kind' in ('mandatory','preference') then
    v_owner:=nullif(v_item->>'ownerProfileId','')::uuid;
    if v_owner is null then
     select wm.user_id into v_owner from public.project_participants pp join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
      where pp.project_id=p_project_id and pp.status='active' and pp.role in ('lead','contributor') order by case pp.role when 'lead' then 0 else 1 end,pp.id limit 1;
    end if;
    if v_owner is null or not exists(select 1 from public.project_participants pp join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
      where pp.project_id=p_project_id and pp.status='active' and pp.role in ('lead','contributor') and wm.user_id=v_owner) then
     raise exception 'Assign an active project lead or contributor responsible for each requirement' using errcode='23514'; end if;
    v_item:=jsonb_set(v_item,'{ownerProfileId}',to_jsonb(v_owner::text));
   end if;
   v_items:=v_items||jsonb_build_array(v_item);
  end loop;
  v_b.document:=jsonb_set(v_b.document,'{items}',v_items);
  select coalesce(jsonb_agg(to_jsonb(f) order by f.created_at),'[]'::jsonb) into v_files from public.project_brief_files f where f.brief_id=v_b.id and f.removed_at is null;
  insert into public.project_brief_revisions(brief_id,project_id,workspace_id,number,document,attachments,respondent_participant_id,requested_by)
   values(v_b.id,v_b.project_id,v_b.workspace_id,v_b.revision_number+1,v_b.document,v_files,v_b.respondent_participant_id,auth.uid()) returning id into v_revision;
  v_status:='awaiting_agreement';
 else raise exception 'This action is not available at the current brief stage' using errcode='23514'; end if;
 if p_action in ('submit','request_agreement') then
  if exists(select 1 from jsonb_array_elements(v_b.document->'fields') f where f->>'id' in ('objective','deliverables') and trim(coalesce(f->>'answer',''))='') then
   raise exception 'Describe the project objective and expected deliverables first' using errcode='23514'; end if;
 end if;
 update public.project_briefs set status=v_status,document=v_b.document,edit_version=edit_version+1,updated_at=now(),
  current_revision_id=coalesce(v_revision,current_revision_id),revision_number=revision_number+case when v_revision is null then 0 else 1 end
  where id=v_b.id returning edit_version into v_b.edit_version;
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload)
 values(v_b.workspace_id,p_project_id,'brief.'||p_action,auth.uid(),'user','project',p_project_id,'Project brief',jsonb_build_object('revision_id',v_revision));
 return v_b.edit_version;
end;
$fn$;

create or replace function public.respond_project_brief(p_project_id uuid,p_revision_id uuid,p_decision text,p_comment text default '')
returns void language plpgsql security definer set search_path=''
as $fn$
declare v_b public.project_briefs%rowtype;
begin
 select * into v_b from public.project_briefs where project_id=p_project_id for update;
 if v_b.id is null or not public.lign_has_capability(p_project_id,v_b.workspace_id,'project.view')
  or public.lign_brief_respondent_user(v_b.respondent_participant_id,p_project_id) is distinct from auth.uid() or auth.uid() is null then
  raise exception 'Only the assigned project approver can respond to this brief' using errcode='42501'; end if;
 if not exists(select 1 from public.projects where id=p_project_id and archived_at is null and status<>'archived') then
  raise exception 'Archived projects cannot receive new brief decisions' using errcode='23514'; end if;
 if v_b.status<>'awaiting_agreement' or v_b.current_revision_id is distinct from p_revision_id then
  raise exception 'This agreement request is no longer current. Reload the brief.' using errcode='PT409'; end if;
 if p_decision is null or p_decision not in ('agreed','changes_requested') or length(coalesce(p_comment,''))>5000
  or (p_decision='changes_requested' and trim(coalesce(p_comment,''))='') then
  raise exception 'Choose an agreement decision and describe any changes requested' using errcode='22023'; end if;
 insert into public.project_brief_decisions(revision_id,project_id,decision,comment,actor_id)
 values(p_revision_id,p_project_id,p_decision,coalesce(p_comment,''),auth.uid());
 update public.project_briefs set status=case when p_decision='agreed' then 'agreed' else 'draft' end,edit_version=edit_version+1,updated_at=now() where id=v_b.id;
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload)
 values(v_b.workspace_id,p_project_id,'brief.'||p_decision,auth.uid(),'user','project',p_project_id,'Project brief',jsonb_build_object('revision_id',p_revision_id));
end;
$fn$;

create or replace function public.add_project_brief_note(p_project_id uuid,p_body text)
returns void language plpgsql security definer set search_path=''
as $$
declare v_ws uuid;
begin
 select workspace_id into v_ws from public.projects where id=p_project_id and archived_at is null and status<>'archived';
 if v_ws is null or not public.lign_has_capability(p_project_id,v_ws,'comment.create') then raise exception 'Project commenting permission required' using errcode='42501'; end if;
 insert into public.project_brief_notes(project_id,author_id,body) values(p_project_id,auth.uid(),trim(p_body));
end; $$;

create or replace function public.generate_brief_requirements(p_project_id uuid,p_revision_id uuid)
returns integer language plpgsql security definer set search_path=''
as $fn$
declare v_r public.project_brief_revisions%rowtype; v_item jsonb; v_req uuid; v_owner uuid; v_count integer:=0;
begin
 select * into v_r from public.project_brief_revisions where id=p_revision_id and project_id=p_project_id;
 if v_r.id is null or not public.lign_manage_project_brief(p_project_id)
  or not public.lign_has_capability(p_project_id,v_r.workspace_id,'requirement.create') then
  raise exception 'A project lead with requirement creation permission is required' using errcode='42501'; end if;
 perform 1 from public.projects where id=p_project_id for no key update;
 perform 1 from public.project_briefs where id=v_r.brief_id for update;
 if not exists(select 1 from public.project_brief_decisions where revision_id=p_revision_id and decision='agreed') then
  raise exception 'Agree this brief revision before generating requirements' using errcode='23514'; end if;
 for v_item in select value from jsonb_array_elements(v_r.document->'items') where value->>'kind' in ('mandatory','preference') loop
  if exists(select 1 from public.project_brief_requirement_links where revision_id=p_revision_id and item_id=v_item->>'id') then continue; end if;
  v_owner:=nullif(v_item->>'ownerProfileId','')::uuid;
  if v_owner is null then
   select wm.user_id into v_owner from public.project_participants pp join public.workspace_members wm on wm.id=pp.workspace_member_id
    where pp.project_id=p_project_id and pp.status='active' and wm.status='active' and pp.role in ('lead','contributor') order by case pp.role when 'lead' then 0 else 1 end,pp.id limit 1;
  end if;
  if v_owner is null or not exists(select 1 from public.workspace_members where workspace_id=v_r.workspace_id and user_id=v_owner and status='active') then
   raise exception 'Assign an active internal owner for these requirements before generating drafts' using errcode='23514'; end if;
  select out_requirement_id into v_req from public.create_requirement(
   p_project_id=>p_project_id,p_workspace_id=>v_r.workspace_id,p_title=>v_item->>'title',
   p_description=>concat_ws(E'\n\n',nullif(v_item->>'detail',''),'Kind: '||(v_item->>'kind'),'Applies to: '||coalesce(nullif(v_item->>'appliesTo',''),'Whole project'),'Acceptance: '||(v_item->>'acceptance')),
   p_source_ref=>'Brief revision '||v_r.number||' · item '||(v_item->>'id'),p_status=>'draft',p_priority=>v_item->>'priority',p_source_kind=>v_item->>'source',p_owner_profile_id=>v_owner);
  insert into public.project_brief_requirement_links(revision_id,item_id,project_id,requirement_id) values(p_revision_id,v_item->>'id',p_project_id,v_req);
  v_count:=v_count+1;
 end loop;
 return v_count;
end;
$fn$;

-- Immutable revision content and recorded decisions, including service writes.
create or replace function public.preserve_project_brief_history()
returns trigger language plpgsql set search_path=''
as $$ begin raise exception 'Brief revisions and decisions are immutable' using errcode='23514'; end; $$;
create trigger project_brief_revisions_immutable before update or delete on public.project_brief_revisions for each row execute function public.preserve_project_brief_history();
create trigger project_brief_decisions_immutable before update or delete on public.project_brief_decisions for each row execute function public.preserve_project_brief_history();

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('brief-references','brief-references',false,10485760,array['application/pdf','image/png','image/jpeg','image/webp','text/plain','text/csv','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);
create policy brief_reference_upload on storage.objects for insert to authenticated with check(
 bucket_id='brief-references' and case when split_part(name,'/',1) ~ '^[0-9a-fA-F-]{36}$' then public.lign_edit_project_brief(split_part(name,'/',1)::uuid) else false end);
create policy brief_reference_download on storage.objects for select to authenticated using(
 bucket_id='brief-references' and exists(select 1 from public.project_brief_files f join public.projects p on p.id=f.project_id
  where f.storage_path=storage.objects.name and public.lign_has_capability(p.id,p.workspace_id,'project.view')));
create policy brief_reference_discard_upload on storage.objects for delete to authenticated using(
 bucket_id='brief-references' and owner_id=auth.uid()::text and not exists(select 1 from public.project_brief_files f where f.storage_path=storage.objects.name));

create or replace function public.register_project_brief_file(p_project_id uuid,p_expected_version bigint,p_path text,p_name text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_b public.project_briefs%rowtype; v_size bigint; v_id uuid;
begin
 select * into v_b from public.project_briefs where project_id=p_project_id for update;
 if not coalesce(public.lign_edit_project_brief(p_project_id),false) then raise exception 'Brief editing permission required' using errcode='42501'; end if;
 if v_b.edit_version is distinct from p_expected_version then raise exception 'The brief changed. Save or reload before adding files.' using errcode='PT409'; end if;
 if split_part(p_path,'/',1)<>p_project_id::text or coalesce(length(trim(p_name)),0) not between 1 and 180 then raise exception 'Invalid reference file' using errcode='22023'; end if;
 select (metadata->>'size')::bigint into v_size from storage.objects where bucket_id='brief-references' and name=p_path and owner_id=auth.uid()::text;
 if v_size is null or v_size>10485760 then raise exception 'Upload a reference file of 10 MB or less first' using errcode='23514'; end if;
 insert into public.project_brief_files(brief_id,project_id,storage_path,name,size_bytes,uploaded_by) values(v_b.id,p_project_id,p_path,p_name,v_size,auth.uid()) returning id into v_id;
 update public.project_briefs set edit_version=edit_version+1,updated_at=now() where id=v_b.id;
 return v_id;
end; $$;

create or replace function public.remove_project_brief_file(p_project_id uuid,p_expected_version bigint,p_file_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare v_b public.project_briefs%rowtype;
begin
 select * into v_b from public.project_briefs where project_id=p_project_id for update;
 if not coalesce(public.lign_edit_project_brief(p_project_id),false) then raise exception 'Brief editing permission required' using errcode='42501'; end if;
 if v_b.edit_version is distinct from p_expected_version then raise exception 'The brief changed. Reload before removing files.' using errcode='PT409'; end if;
 update public.project_brief_files set removed_at=now() where id=p_file_id and brief_id=v_b.id and removed_at is null;
 update public.project_briefs set edit_version=edit_version+1,updated_at=now() where id=v_b.id;
end; $$;

-- All writes go through the checked RPCs; helper functions grant no writes.
revoke all on function public.validate_project_brief_document(jsonb),public.preserve_project_brief_history() from public,anon,authenticated;
revoke all on function public.lign_manage_project_brief(uuid),public.lign_brief_respondent_user(uuid,uuid),public.lign_edit_project_brief(uuid),public.get_project_brief(uuid),public.save_project_brief(uuid,jsonb,bigint,uuid),public.transition_project_brief(uuid,bigint,text),public.respond_project_brief(uuid,uuid,text,text),public.add_project_brief_note(uuid,text),public.generate_brief_requirements(uuid,uuid),public.register_project_brief_file(uuid,bigint,text,text),public.remove_project_brief_file(uuid,bigint,uuid) from public,anon;
revoke all on function public.lign_brief_respondent_user(uuid,uuid) from authenticated;
grant execute on function public.lign_manage_project_brief(uuid),public.lign_edit_project_brief(uuid),public.get_project_brief(uuid),public.save_project_brief(uuid,jsonb,bigint,uuid),public.transition_project_brief(uuid,bigint,text),public.respond_project_brief(uuid,uuid,text,text),public.add_project_brief_note(uuid,text),public.generate_brief_requirements(uuid,uuid),public.register_project_brief_file(uuid,bigint,text,text),public.remove_project_brief_file(uuid,bigint,uuid) to authenticated;


-- The brief-to-requirements browser flow exposed an existing dashboard bug:
-- a second SQL statement referenced a CTE from the first statement. Preserve
-- its signature, saved views and permission checks; compute pagination in one
-- statement so generated drafts can be reviewed. Historical files stay frozen.
create or replace function public.list_requirements_dashboard(
  p_ws_id                 uuid,
  p_proj_id               uuid,
  p_view                  text        default 'all_active',
  p_status_filter         text[]      default null,
  p_priority_filter       text[]      default null,
  p_source_filter         text[]      default null,
  p_category_filter       text[]      default null,
  p_scope_filter          text        default null,   -- 'project_wide' | 'asset_scoped' | null
  p_owner_ids             uuid[]      default null,
  p_search                text        default null,
  p_cursor_updated_at     timestamptz default null,
  p_cursor_id             uuid        default null,
  p_limit                 integer     default 50,
  p_saved_view_id         uuid        default null
)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_rows jsonb;
  v_next_cursor jsonb;
  v_effective_view text := coalesce(p_view, 'all_active');
  v_status_filter text[] := p_status_filter;
  v_priority_filter text[] := p_priority_filter;
  v_source_filter text[] := p_source_filter;
  v_category_filter text[] := p_category_filter;
  v_owner_ids uuid[] := p_owner_ids;
  v_search text := p_search;
  v_scope_filter text := p_scope_filter;
  v_saved_payload jsonb;
  v_limit int := greatest(1,least(coalesce(p_limit, 50), 200));
begin
  if v_caller is null then raise exception 'list_requirements_dashboard: authentication required' using errcode='42501'; end if;
  if p_ws_id is null then raise exception 'list_requirements_dashboard: workspace id required' using errcode='22004'; end if;

  -- Resolve saved view (if any) — override the filter set.
  if p_saved_view_id is not null then
    select payload into v_saved_payload
      from public.user_saved_views
     where id = p_saved_view_id
       and user_id = v_caller
       and workspace_id = p_ws_id
       and scope = 'requirements';
    if v_saved_payload is not null then
      v_effective_view    := coalesce(v_saved_payload->>'view', v_effective_view);
      v_status_filter     := case when v_saved_payload ? 'status_filter'    then array(select jsonb_array_elements_text(v_saved_payload->'status_filter'))    else v_status_filter    end;
      v_priority_filter   := case when v_saved_payload ? 'priority_filter'  then array(select jsonb_array_elements_text(v_saved_payload->'priority_filter'))  else v_priority_filter  end;
      v_source_filter     := case when v_saved_payload ? 'source_filter'    then array(select jsonb_array_elements_text(v_saved_payload->'source_filter'))    else v_source_filter    end;
      v_category_filter   := case when v_saved_payload ? 'category_filter'  then array(select jsonb_array_elements_text(v_saved_payload->'category_filter'))  else v_category_filter  end;
      v_scope_filter      := coalesce(v_saved_payload->>'scope_filter', v_scope_filter);
      v_search            := coalesce(v_saved_payload->>'search', v_search);
      v_owner_ids         := case when v_saved_payload ? 'owner_ids'        then (select array_agg(x::uuid) from jsonb_array_elements_text(v_saved_payload->'owner_ids') as x) else v_owner_ids end;
    end if;
  end if;

  -- Interpret magic view names.
  if v_effective_view = 'assigned_to_me' then
    v_owner_ids := array[v_caller];
  end if;
  if v_effective_view = 'archived' then
    v_status_filter := array['archived'];
  elsif v_effective_view = 'superseded' then
    v_status_filter := array['superseded'];
  elsif v_effective_view in ('overdue_critical') then
    v_priority_filter := array['critical'];
  end if;

  -- Authorization: at workspace scope, filter to projects the caller can view.
  -- At project scope, gate at RPC entry.
  if p_proj_id is not null then
    if not public.lign_has_capability(p_proj_id, p_ws_id, 'requirement.view') then
      raise exception 'list_requirements_dashboard: forbidden (requirement.view)' using errcode='42501';
    end if;
  end if;

  with base as (
    select r.*,
           p.name as project_name,
           (select count(*)::int from public.requirement_design_assets rda
              where rda.requirement_id = coalesce(r.parent_requirement_id, r.id))
             as rda_count
      from public.requirements r
      join public.projects p on p.id = r.project_id
     where r.workspace_id = p_ws_id
       and (p_proj_id is null or r.project_id = p_proj_id)
       and (
         p_proj_id is not null
         or public.lign_has_capability(r.project_id, r.workspace_id, 'requirement.view')
       )
       and (v_status_filter is null   or r.status         = any (v_status_filter))
       and (v_priority_filter is null or r.priority       = any (v_priority_filter))
       and (v_source_filter is null   or r.source_kind    = any (v_source_filter))
       and (v_category_filter is null or r.category_kind  = any (v_category_filter))
       and (v_owner_ids is null       or r.owner_profile_id = any (v_owner_ids))
       and (v_search is null or v_search = ''
            or r.code        ilike '%' || v_search || '%'
            or r.title       ilike '%' || v_search || '%'
            or coalesce(r.description, '') ilike '%' || v_search || '%')
       -- Default view: only non-terminal unless user asked otherwise.
       and (
         v_effective_view in ('all','archived','superseded')
         or v_status_filter is not null
         or r.status in ('draft','active')
       )
       and (
         p_cursor_updated_at is null
         or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id)
       )
  ),
  scoped as (
    select * from base
     where (
       v_scope_filter is null
       or (v_scope_filter = 'project_wide' and rda_count = 0)
       or (v_scope_filter = 'asset_scoped' and rda_count > 0)
     )
  ),
  filtered as (
    select * from scoped
     order by updated_at desc, id desc
     limit v_limit + 1
  ),
  page as (
    select * from filtered limit v_limit
  ),
  paged as (
    select b.*,
      jsonb_build_object(
        'scope', case when b.rda_count = 0 then 'project_wide' else 'asset_scoped' end,
        'asset_count', b.rda_count
      ) as applicability_summary,
      (
        with applicable_versions as (
          select av.id as version_id, av.design_asset_id
            from public.asset_versions av
           where av.project_id = b.project_id
             and (b.rda_count = 0
                  or av.design_asset_id in (
                    select design_asset_id from public.requirement_design_assets
                     where requirement_id = coalesce(b.parent_requirement_id, b.id)))
        ),
        latest as (
          select distinct on (design_asset_id) version_id
            from applicable_versions
           order by design_asset_id, version_id desc
        ),
        j as (
          select l.version_id, vra.status
            from latest l
            left join public.version_requirement_assessments vra
                   on vra.asset_version_id = l.version_id
                  and vra.requirement_id   = b.id
        )
        select jsonb_build_object(
                 'applicable_versions_count', count(*)::int,
                 'satisfied_count',           count(*) filter (where status = 'satisfied')::int,
                 'coverage_pct',
                   case when count(*) = 0 then 0
                        else round(100.0 * count(*) filter (where status = 'satisfied')::numeric
                                       / nullif(count(*)::numeric, 0), 2)
                   end,
                 'latest_version_assessed',
                   coalesce(bool_and(status is not null), false)
               ) from j
      ) as assessment_coverage
      from page b
  )
  -- The page and cursor must be read in the same CTE statement.
  select (select coalesce(jsonb_agg(
           jsonb_build_object(
             'requirement_id',       id,
             'code',                 code,
             'title',                title,
             'status',               status,
             'priority',             priority,
             'source_kind',          source_kind,
             'category_kind',        category_kind,
             'owner_profile_id',     owner_profile_id,
             'updated_at',           updated_at,
             'applicability_summary', applicability_summary,
             'assessment_coverage',  assessment_coverage,
             'project_id',           project_id,
             'project_name',         project_name,
             'workspace_id',         workspace_id,
             'due_at',               due_at
           ) order by updated_at desc,id desc
         ), '[]'::jsonb) from paged),
    (select case when count(*)>v_limit then
       (select jsonb_build_object('updated_at',updated_at,'id',id) from page order by updated_at asc,id asc limit 1)
     else null end from filtered)
    into v_rows,v_next_cursor;

  return jsonb_build_object(
    'rows',        v_rows,
    'next_cursor', v_next_cursor
  );
end $$;
