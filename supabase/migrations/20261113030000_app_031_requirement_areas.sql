-- APP 031: project -> spaces/groups -> zones/components, independent of design assets.
create table public.project_areas (
 id uuid primary key default gen_random_uuid(),project_id uuid not null,workspace_id uuid not null,
 parent_area_id uuid,name text not null check(length(trim(name)) between 1 and 160),
 kind text not null default 'Space' check(length(trim(kind)) between 1 and 60),
 description text not null default '' check(length(description)<=2000),archived_at timestamptz,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(id,project_id,workspace_id),
 foreign key(project_id,workspace_id) references public.projects(id,workspace_id),
 foreign key(parent_area_id,project_id,workspace_id) references public.project_areas(id,project_id,workspace_id)
);
create index project_areas_project_idx on public.project_areas(project_id,workspace_id);
create index project_areas_parent_idx on public.project_areas(parent_area_id,project_id,workspace_id);
create unique index project_areas_root_name_key on public.project_areas(project_id,lower(trim(name))) where parent_area_id is null and archived_at is null;
create unique index project_areas_child_name_key on public.project_areas(parent_area_id,lower(trim(name))) where parent_area_id is not null and archived_at is null;
create table public.requirement_areas (
 requirement_id uuid not null,area_id uuid not null,project_id uuid not null,workspace_id uuid not null,
 primary key(requirement_id,area_id),
 foreign key(requirement_id,project_id) references public.requirements(id,project_id),
 foreign key(area_id,project_id,workspace_id) references public.project_areas(id,project_id,workspace_id),
 foreign key(project_id,workspace_id) references public.projects(id,workspace_id)
);
create index requirement_areas_requirement_idx on public.requirement_areas(requirement_id,project_id);
create index requirement_areas_area_idx on public.requirement_areas(area_id,project_id,workspace_id);
create index requirement_areas_project_idx on public.requirement_areas(project_id,workspace_id);
alter table public.project_areas enable row level security;
alter table public.requirement_areas enable row level security;
create policy project_areas_read on public.project_areas for select to authenticated using(public.lign_has_capability(project_id,workspace_id,'project.view'));
create policy requirement_areas_read on public.requirement_areas for select to authenticated using(public.lign_has_capability(project_id,workspace_id,'requirement.view'));
revoke all on public.project_areas,public.requirement_areas from anon,authenticated;
grant select on public.project_areas,public.requirement_areas to authenticated;

create or replace function public.preserve_project_area_parent()
returns trigger language plpgsql set search_path=''
as $$ begin
 if (new.id,new.project_id,new.workspace_id,new.parent_area_id) is distinct from (old.id,old.project_id,old.workspace_id,old.parent_area_id) then
 raise exception 'Area hierarchy cannot be moved; create a new area instead' using errcode='23514'; end if;
 return new; end; $$;
create trigger project_areas_parent_immutable before update on public.project_areas for each row execute function public.preserve_project_area_parent();
revoke all on function public.preserve_project_area_parent() from public,anon,authenticated;

create or replace function public.project_area_paths(p_project_id uuid)
returns table(id uuid,parent_area_id uuid,path text,kind text,depth integer,ancestor_ids uuid[],archived boolean)
language sql stable security definer set search_path=''
as $$ with recursive tree as (
 select a.id,a.parent_area_id,a.name as path,a.kind,1 as depth,array[a.id] as ancestor_ids,a.archived_at is not null as archived
 from public.project_areas a where a.project_id=p_project_id and a.parent_area_id is null
 union all
 select a.id,a.parent_area_id,t.path||' / '||a.name,a.kind,t.depth+1,t.ancestor_ids||a.id,a.archived_at is not null
 from public.project_areas a join tree t on a.parent_area_id=t.id where a.project_id=p_project_id and t.depth<8
 ) select * from tree; $$;
revoke all on function public.project_area_paths(uuid) from public,anon,authenticated;

create or replace function public.assert_project_area_editable(p_project_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_ws uuid; begin
 select workspace_id into v_ws from public.projects where id=p_project_id for no key update;
 if v_ws is null or not public.lign_manage_project_brief(p_project_id) then raise exception 'Project leadership required' using errcode='42501'; end if;
 if exists(select 1 from public.project_briefs where project_id=p_project_id and status<>'draft') then
 raise exception 'Start a new brief draft before changing spaces or zones' using errcode='23514'; end if;
 return v_ws; end; $$;
revoke all on function public.assert_project_area_editable(uuid) from public,anon,authenticated;

create or replace function public.save_project_area(p_project_id uuid,p_name text,p_kind text default 'Space',p_description text default '',p_parent_id uuid default null,p_area_id uuid default null)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_ws uuid;v_id uuid;v_depth integer; begin
 v_ws:=public.assert_project_area_editable(p_project_id);
 if p_name is null or length(trim(p_name)) not between 1 and 160 or p_kind is null or length(trim(p_kind)) not between 1 and 60
 or p_description is null or length(p_description)>2000 or p_name~'[[:cntrl:]]' or p_kind~'[[:cntrl:]]' then
 raise exception 'Check the area name, label and description' using errcode='22023'; end if;
 if p_parent_id is not null then
 select depth into v_depth from public.project_area_paths(p_project_id) where id=p_parent_id and not archived;
 if v_depth is null then raise exception 'Choose an active parent in this project' using errcode='23503'; end if;
 if v_depth>=8 then raise exception 'Use at most eight area levels' using errcode='23514'; end if;
 end if;
 if p_area_id is null then
 insert into public.project_areas(project_id,workspace_id,parent_area_id,name,kind,description)
 values(p_project_id,v_ws,p_parent_id,trim(p_name),trim(p_kind),trim(p_description)) returning id into v_id;
 else
 update public.project_areas set name=trim(p_name),kind=trim(p_kind),description=trim(p_description),updated_at=now()
 where id=p_area_id and project_id=p_project_id and archived_at is null and parent_area_id is not distinct from p_parent_id returning id into v_id;
 if v_id is null then raise exception 'Active area not found or parent changed' using errcode='23503'; end if;
 end if;
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload)
 values(v_ws,p_project_id,'project.updated',auth.uid(),'user','project',p_project_id,trim(p_name),jsonb_build_object('changed_fields',array['areas'],'area_id',v_id));
 return v_id; end; $$;

create or replace function public.archive_project_area(p_area_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ declare v public.project_areas%rowtype; begin
 select * into v from public.project_areas where id=p_area_id;
 if v.id is null then raise exception 'Area not found' using errcode='23503'; end if;
 perform public.assert_project_area_editable(v.project_id);
 if exists(select 1 from public.project_areas where parent_area_id=v.id and archived_at is null)
 or exists(select 1 from public.requirement_areas ra join public.requirements r on r.id=ra.requirement_id where ra.area_id=v.id and r.status in ('draft','active'))
 or exists(select 1 from public.project_briefs b cross join lateral jsonb_array_elements(b.document->'items') i where b.project_id=v.project_id and coalesce(i->'areaIds','[]'::jsonb)?v.id::text) then
 raise exception 'Remove active child areas and requirement assignments before archiving this area' using errcode='23514'; end if;
 update public.project_areas set archived_at=now(),updated_at=now() where id=v.id and archived_at is null;
 if found then insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload)
 values(v.workspace_id,v.project_id,'project.updated',auth.uid(),'user','project',v.project_id,v.name,jsonb_build_object('changed_fields',array['areas'],'archived_area_id',v.id)); end if;
 end; $$;

create or replace function public.get_project_areas(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v_ws uuid; begin
 select workspace_id into v_ws from public.projects where id=p_project_id;
 if v_ws is null or not public.lign_has_capability(p_project_id,v_ws,'project.view') then raise exception 'Project access required' using errcode='42501'; end if;
 return jsonb_build_object('canManage',public.lign_manage_project_brief(p_project_id) and not exists(select 1 from public.project_briefs where project_id=p_project_id and status<>'draft'),
 'areas',(select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('name',a.name,'description',a.description) order by lower(t.path),t.id),'[]'::jsonb) from public.project_area_paths(p_project_id) t join public.project_areas a on a.id=t.id));
 end; $$;

create or replace function public.set_requirement_areas(p_requirement_id uuid,p_area_ids uuid[])
returns void language plpgsql security definer set search_path=''
as $$ declare v public.requirements%rowtype;v_old uuid[];v_ids uuid[]; begin
 select * into v from public.requirements where id=p_requirement_id;
 perform 1 from public.projects where id=v.project_id for no key update;
 select * into v from public.requirements where id=p_requirement_id for update;
 if v.id is null or not public.lign_has_capability(v.project_id,v.workspace_id,'requirement.edit')
 or not exists(select 1 from public.projects where id=v.project_id and archived_at is null and status<>'archived') then
 raise exception 'Requirement editing access required' using errcode='42501'; end if;
 if v.status not in ('draft','active') or v.parent_requirement_id is not null then raise exception 'Edit the active root requirement; children inherit its areas' using errcode='23514'; end if;
 if p_area_ids is null or cardinality(p_area_ids)>100 or array_position(p_area_ids,null) is not null then raise exception 'Choose at most 100 areas' using errcode='22023'; end if;
 select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_ids from unnest(p_area_ids) x;
 if exists(select 1 from unnest(v_ids) x where not exists(select 1 from public.project_areas where id=x and project_id=v.project_id and archived_at is null)) then
 raise exception 'Choose active areas in this project' using errcode='23503'; end if;
 select coalesce(array_agg(area_id order by area_id),'{}'::uuid[]) into v_old from public.requirement_areas where requirement_id=v.id;
 if v_ids=v_old then return; end if;
 delete from public.requirement_areas where requirement_id=v.id;
 insert into public.requirement_areas(requirement_id,area_id,project_id,workspace_id) select v.id,x,v.project_id,v.workspace_id from unnest(v_ids) x;
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,subject_snapshot,payload)
 values(v.workspace_id,v.project_id,'requirement.updated',auth.uid(),'user','requirement',v.id,v.title,jsonb_build_object('kind','edit','changed_fields',array['areas']),jsonb_build_object('previous_area_ids',v_old,'area_ids',v_ids));
 end; $$;

create or replace function public.get_requirement_areas(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v public.requirements%rowtype;begin
 select * into v from public.requirements where id=p_requirement_id;
 if v.id is null or not public.lign_has_capability(v.project_id,v.workspace_id,'requirement.view') then raise exception 'Requirement access required' using errcode='42501'; end if;
 return jsonb_build_object('inherited',v.parent_requirement_id is not null,'canEdit',v.parent_requirement_id is null and v.status in ('draft','active') and public.lign_has_capability(v.project_id,v.workspace_id,'requirement.edit') and exists(select 1 from public.projects where id=v.project_id and archived_at is null and status<>'archived'),
 'areas',(select coalesce(jsonb_agg(to_jsonb(p) order by p.path),'[]'::jsonb) from public.requirement_areas ra join public.project_area_paths(v.project_id) p on p.id=ra.area_id where ra.requirement_id=coalesce(v.parent_requirement_id,v.id)));
 end; $$;

create or replace function public.list_area_requirements(p_project_id uuid,p_area_id uuid default null,p_project_only boolean default false,p_include_descendants boolean default true,p_statuses text[] default array['draft','active'],p_limit integer default 50,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v_ws uuid;v_result jsonb;begin
 select workspace_id into v_ws from public.projects where id=p_project_id;
 if v_ws is null or not public.lign_has_capability(p_project_id,v_ws,'requirement.view') then raise exception 'Requirement viewing access required' using errcode='42501'; end if;
 if p_limit is null or p_limit not between 1 and 100 or p_statuses is null or not(p_statuses<@array['draft','active','archived','superseded']) then raise exception 'Invalid requirement filters' using errcode='22023'; end if;
 if p_area_id is not null and not exists(select 1 from public.project_areas where id=p_area_id and project_id=p_project_id) then raise exception 'Area not found in this project' using errcode='23503'; end if;
 with paths as materialized(select * from public.project_area_paths(p_project_id)), relevant as (
 select a.id from paths a cross join paths selected where selected.id=p_area_id
 and (a.id=any(selected.ancestor_ids) or (p_include_descendants and p_area_id=any(a.ancestor_ids)))
 ), page as (
 select r.id,r.code,r.title,r.status,r.parent_requirement_id,
 (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'path',a.path,'archived',a.archived) order by a.path),'[]'::jsonb) from public.requirement_areas ra join paths a on a.id=ra.area_id where ra.requirement_id=coalesce(r.parent_requirement_id,r.id)) as areas
 from public.requirements r where r.project_id=p_project_id and r.status=any(p_statuses) and (p_after is null or r.id>p_after)
 and (not p_project_only or not exists(select 1 from public.requirement_areas ra where ra.requirement_id=coalesce(r.parent_requirement_id,r.id)))
 and (p_area_id is null or not exists(select 1 from public.requirement_areas ra where ra.requirement_id=coalesce(r.parent_requirement_id,r.id))
 or exists(select 1 from public.requirement_areas ra join relevant a on a.id=ra.area_id where ra.requirement_id=coalesce(r.parent_requirement_id,r.id)))
 order by r.id limit p_limit+1)
 select jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) from(select * from page order by id limit p_limit)x),
 'nextCursor',case when (select count(*) from page)>p_limit then (select id from page order by id offset p_limit-1 limit 1) else null end) into v_result;
 return v_result;end; $$;

create or replace function public.enrich_project_brief_areas(p_project_id uuid,p_document jsonb)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v jsonb;v_ids uuid[];v_items jsonb:='[]';v_snapshot jsonb;begin
 for v in select value from jsonb_array_elements(p_document->'items') loop
 if jsonb_typeof(coalesce(v->'areaIds','[]'::jsonb))<>'array' then raise exception 'Choose an array of area IDs' using errcode='22023'; end if;
 if jsonb_array_length(coalesce(v->'areaIds','[]'::jsonb))>100 or exists(select 1 from jsonb_array_elements(coalesce(v->'areaIds','[]'::jsonb)) x where jsonb_typeof(x)<>'string' or (x#>>'{}')!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
 raise exception 'Choose at most 100 valid areas' using errcode='22023'; end if;
 select coalesce(array_agg(distinct x::uuid),'{}'::uuid[]) into v_ids from jsonb_array_elements_text(coalesce(v->'areaIds','[]'::jsonb)) x;
 if exists(select 1 from unnest(v_ids) x where not exists(select 1 from public.project_areas where id=x and project_id=p_project_id and archived_at is null)) then raise exception 'Choose active areas in this project' using errcode='23503'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'path',path,'kind',kind) order by path),'[]'::jsonb) into v_snapshot from public.project_area_paths(p_project_id) where id=any(v_ids);
 v:=jsonb_set(jsonb_set(v,'{areaIds}',to_jsonb(v_ids)),'{areaSnapshot}',v_snapshot);
 v_items:=v_items||jsonb_build_array(v);
 end loop;
 return jsonb_set(p_document,'{items}',v_items);end; $$;
revoke all on function public.enrich_project_brief_areas(uuid,jsonb) from public,anon,authenticated;

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
 p_document:=public.enrich_project_brief_areas(p_project_id,p_document);
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
 perform 1 from public.projects where id=p_project_id for no key update;
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
  v_b.document:=public.enrich_project_brief_areas(p_project_id,jsonb_set(v_b.document,'{items}',v_items));
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
   p_description=>concat_ws(E'\n\n',nullif(v_item->>'detail',''),'Kind: '||(v_item->>'kind'),'Applies to: '||coalesce(nullif(v_item->>'appliesTo',''),'Whole project'),'Acceptance: '||(v_item->>'acceptance'),'Areas at agreement: '||coalesce((select string_agg(x->>'path',', ' order by x->>'path') from jsonb_array_elements(coalesce(v_item->'areaSnapshot','[]'::jsonb)) x),'Whole project')),
   p_source_ref=>'Brief revision '||v_r.number||' · item '||(v_item->>'id'),p_status=>'draft',p_priority=>v_item->>'priority',p_source_kind=>v_item->>'source',p_owner_profile_id=>v_owner);
  insert into public.requirement_areas(requirement_id,area_id,project_id,workspace_id)
  select v_req,x::uuid,p_project_id,v_r.workspace_id from jsonb_array_elements_text(coalesce(v_item->'areaIds','[]'::jsonb)) x;
  insert into public.project_brief_requirement_links(revision_id,item_id,project_id,requirement_id) values(p_revision_id,v_item->>'id',p_project_id,v_req);
  v_count:=v_count+1;
 end loop;
 return v_count;
end;
$fn$;

create or replace function public.create_requirement_with_areas(
  p_project_id             uuid,
  p_workspace_id           uuid,
  p_title                  text,
  p_description            text        default null,
  p_category               text        default null,
  p_source                 text        default null,
  p_source_ref             text        default null,
  p_parent_requirement_id  uuid        default null,
  p_status                 text        default 'draft',
  p_priority               text        default null,
  p_source_kind            text        default null,
  p_category_kind          text        default null,
  p_owner_profile_id       uuid        default null,
  p_verification_method    text        default null,
  p_due_at                 timestamptz default null,
  p_area_ids uuid[] default '{}'::uuid[]
)
returns table(out_requirement_id uuid,out_code text)
language plpgsql security definer set search_path=''
as $$ declare v record;begin
 if not public.lign_has_capability(p_project_id,p_workspace_id,'requirement.create') then raise exception 'Requirement creation access required' using errcode='42501'; end if;
 perform 1 from public.projects where id=p_project_id for no key update;
 select * into v from public.create_requirement(p_project_id,p_workspace_id,p_title,p_description,p_category,p_source,p_source_ref,p_parent_requirement_id,p_status,p_priority,p_source_kind,p_category_kind,p_owner_profile_id,p_verification_method,p_due_at);
 if p_parent_requirement_id is null then perform public.set_requirement_areas(v.out_requirement_id,p_area_ids);
 elsif cardinality(p_area_ids)>0 then raise exception 'Sub-requirements inherit their parent areas' using errcode='23514'; end if;
 return query select v.out_requirement_id,v.out_code;
 end; $$;

revoke all on function public.save_project_area(uuid,text,text,text,uuid,uuid),public.archive_project_area(uuid),public.get_project_areas(uuid),public.set_requirement_areas(uuid,uuid[]),public.get_requirement_areas(uuid),public.list_area_requirements(uuid,uuid,boolean,boolean,text[],integer,uuid),public.create_requirement_with_areas(uuid,uuid,text,text,text,text,text,uuid,text,text,text,text,uuid,text,timestamptz,uuid[]) from public,anon,authenticated;
grant execute on function public.save_project_area(uuid,text,text,text,uuid,uuid),public.archive_project_area(uuid),public.get_project_areas(uuid),public.set_requirement_areas(uuid,uuid[]),public.get_requirement_areas(uuid),public.list_area_requirements(uuid,uuid,boolean,boolean,text[],integer,uuid),public.create_requirement_with_areas(uuid,uuid,text,text,text,text,text,uuid,text,text,text,text,uuid,text,timestamptz,uuid[]) to authenticated,service_role;
