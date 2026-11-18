create or replace function public.brief_requirement_description(p_item jsonb)
returns text language sql immutable set search_path='' as $$
 select concat_ws(E'\n\n',nullif(p_item->>'detail',''),'Kind: '||(p_item->>'kind'),'Applies to: '||coalesce(nullif(p_item->>'appliesTo',''),'Whole project'),'Acceptance: '||(p_item->>'acceptance'),'Areas at agreement: '||coalesce((select string_agg(x->>'path',', ' order by x->>'path') from jsonb_array_elements(coalesce(p_item->'areaSnapshot','[]'::jsonb)) x),'Whole project')); $$;

create or replace function public.brief_requirement_content(p_requirement_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('title',r.title,'description',r.description,'priority',r.priority,'source_kind',r.source_kind,'owner_profile_id',r.owner_profile_id,
 'category',r.category,'source',r.source,'category_kind',r.category_kind,'verification_method',r.verification_method,'due_at',r.due_at,'parent_requirement_id',r.parent_requirement_id,
 'areas',coalesce((select jsonb_agg(a.area_id::text order by a.area_id::text) from public.requirement_areas a where a.requirement_id=r.id),'[]'::jsonb)) from public.requirements r where r.id=p_requirement_id; $$;

create or replace function public.brief_requirement_expected(p_item jsonb)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('title',p_item->>'title','description',public.brief_requirement_description(p_item),'priority',p_item->>'priority','source_kind',p_item->>'source','owner_profile_id',p_item->>'ownerProfileId',
 'category',null,'source',null,'category_kind',null,'verification_method',null,'due_at',null,'parent_requirement_id',null,
 'areas',coalesce((select jsonb_agg(x order by x) from jsonb_array_elements_text(coalesce(p_item->'areaIds','[]'::jsonb)) x),'[]'::jsonb)); $$;

create or replace function public.brief_requirement_impact(p_requirement_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('assets',(select count(*) from public.requirement_design_assets where requirement_id=p_requirement_id),
 'assessments',(select count(*) from public.version_requirement_assessments where requirement_id=p_requirement_id),
 'proposals',(select count(*) from public.proposal_revisions where snapshot->'requirements' @> jsonb_build_array(jsonb_build_object('id',p_requirement_id)))); $$;

create or replace function public.brief_requirement_review_token(p_revision_id uuid,p_item_id text)
returns text language sql stable security definer set search_path='' as $$
 select md5((to_jsonb(c)||jsonb_build_object('previous',to_jsonb(o),'next',to_jsonb(n),
 'oldContent',public.brief_requirement_content(o.id),'newContent',public.brief_requirement_content(n.id),
 'oldImpact',public.brief_requirement_impact(o.id),'newImpact',public.brief_requirement_impact(n.id),
 'links',(select jsonb_agg(to_jsonb(a) order by a.requirement_id,a.design_asset_id) from public.requirement_design_assets a where a.requirement_id in(o.id,n.id)),
 'assessments',(select jsonb_agg(to_jsonb(a) order by a.id) from public.version_requirement_assessments a where a.requirement_id in(o.id,n.id)),
 'proposals',(select jsonb_agg(a.id order by a.id) from public.proposal_revisions a where a.snapshot->'requirements' @> jsonb_build_array(jsonb_build_object('id',o.id)) or a.snapshot->'requirements' @> jsonb_build_array(jsonb_build_object('id',n.id)))))::text)
 from public.brief_requirement_changes c left join public.requirements o on o.id=c.previous_requirement_id left join public.requirements n on n.id=c.requirement_id where c.revision_id=p_revision_id and c.item_id=p_item_id; $$;

create or replace function public.get_brief_requirement_changes(p_project_id uuid,p_revision_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_r public.project_brief_revisions%rowtype;v_can boolean;begin
 select * into v_r from public.project_brief_revisions where id=p_revision_id and project_id=p_project_id;
 if v_r.id is null or not public.lign_has_capability(p_project_id,v_r.workspace_id,'requirement.view') or not(public.lign_manage_project_brief(p_project_id) or coalesce(public.lign_project_role(p_project_id) in ('lead','contributor'),false)) then raise exception 'Requirement viewing access required' using errcode='42501';end if;
 v_can:=public.lign_manage_project_brief(p_project_id) and public.lign_has_capability(p_project_id,v_r.workspace_id,'requirement.create') and public.lign_has_capability(p_project_id,v_r.workspace_id,'requirement.edit');
 return jsonb_build_object('canManage',v_can,'canRetire',public.lign_has_capability(p_project_id,v_r.workspace_id,'requirement.archive'),'current',exists(select 1 from public.project_briefs where project_id=p_project_id and status='agreed' and current_revision_id=p_revision_id),
 'prepared',exists(select 1 from public.brief_requirement_changes where revision_id=p_revision_id),
 'pending',(select count(*) from public.brief_requirement_changes where revision_id=p_revision_id and state='pending'),
 'rows',coalesce((select jsonb_agg(jsonb_build_object('itemId',c.item_id,'kind',c.kind,'state',c.state,'outcome',c.outcome,'note',c.review_note,'appliedAt',c.applied_at,
 'previousItem',c.previous_item,'proposedItem',c.proposed_item,'previous',case when o.id is not null then jsonb_build_object('id',o.id,'code',o.code,'status',o.status,'content',public.brief_requirement_content(o.id)) end,
 'next',case when n.id is not null then jsonb_build_object('id',n.id,'code',n.code,'status',n.status,'content',public.brief_requirement_content(n.id)) end,
 'responsibilityValid',n.id is null or exists(select 1 from public.project_participants pp join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active' where pp.project_id=p_project_id and pp.status='active' and pp.role in ('lead','contributor') and wm.user_id=n.owner_profile_id),
 'manualEdits',(o.id is not null and public.brief_requirement_content(o.id) is distinct from public.brief_requirement_expected(c.previous_item)) or (n.id is not null and c.prepared_content is not null and public.brief_requirement_content(n.id) is distinct from c.prepared_content),
 'impact',public.brief_requirement_impact(o.id),'token',public.brief_requirement_review_token(c.revision_id,c.item_id),'matchedItemId',c.matched_item_id,'matchedFrom',(select m.item_id from public.brief_requirement_changes m where m.revision_id=c.revision_id and m.state='matched' and m.matched_item_id=c.item_id))
 order by case c.state when 'pending' then 0 else 1 end,c.kind,c.item_id)
 from public.brief_requirement_changes c left join public.requirements o on o.id=c.previous_requirement_id left join public.requirements n on n.id=c.requirement_id where c.revision_id=p_revision_id),'[]'::jsonb));
end; $$;

create or replace function public.prepare_brief_requirement_changes(p_project_id uuid,p_revision_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare v_r public.project_brief_revisions%rowtype;v_item jsonb;v_old record;v_req uuid;v_count integer:=0;v_kind text;v_status text;begin
 perform 1 from public.projects where id=p_project_id for no key update;
 select * into v_r from public.project_brief_revisions where id=p_revision_id and project_id=p_project_id;
 perform 1 from public.project_briefs where project_id=p_project_id and status='agreed' and current_revision_id=p_revision_id for update;
 if not found or v_r.id is null or not public.lign_manage_project_brief(p_project_id) or not public.lign_has_capability(p_project_id,v_r.workspace_id,'requirement.create') or not public.lign_has_capability(p_project_id,v_r.workspace_id,'requirement.edit') then raise exception 'Current agreed brief and requirement leadership required' using errcode='42501';end if;
 if not exists(select 1 from public.project_brief_decisions where revision_id=p_revision_id and decision='agreed') then raise exception 'Agree this brief first' using errcode='23514';end if;
 if exists(select 1 from public.brief_requirement_changes where project_id=p_project_id and revision_id<>p_revision_id and state='pending') then raise exception 'Complete the earlier requirement handoff first' using errcode='23514';end if;
 for v_item in select value from jsonb_array_elements(v_r.document->'items') where value->>'kind' in ('mandatory','preference') loop
  if exists(select 1 from public.brief_requirement_changes where revision_id=p_revision_id and item_id=v_item->>'id') then continue;end if;
  select l.requirement_id,i.value as item into v_old from public.project_brief_requirement_links l join public.project_brief_revisions r on r.id=l.revision_id
   cross join lateral jsonb_array_elements(r.document->'items') i where l.project_id=p_project_id and r.number<v_r.number and l.item_id=v_item->>'id' and i.value->>'id'=l.item_id order by r.number desc limit 1;
  v_kind:=case when v_old.requirement_id is null then 'added' when public.brief_requirement_expected(v_item)=public.brief_requirement_expected(v_old.item) then 'unchanged' else 'changed' end;
  select requirement_id into v_req from public.project_brief_requirement_links where revision_id=p_revision_id and item_id=v_item->>'id';
  if v_req is null and v_kind='unchanged' and exists(select 1 from public.requirements where id=v_old.requirement_id and status in ('draft','active')) then v_req:=v_old.requirement_id;end if;
  if v_req is null then
   if not exists(select 1 from public.project_participants pp join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active' where pp.project_id=p_project_id and pp.status='active' and pp.role in ('lead','contributor') and wm.user_id=(v_item->>'ownerProfileId')::uuid) then raise exception 'A recorded responsible person is no longer active in this project; revise the brief assignment first' using errcode='23514';end if;
   select out_requirement_id into v_req from public.create_requirement(p_project_id=>p_project_id,p_workspace_id=>v_r.workspace_id,p_title=>v_item->>'title',p_description=>public.brief_requirement_description(v_item),p_source_ref=>'Brief revision '||v_r.number||' · item '||(v_item->>'id'),p_status=>'draft',p_priority=>v_item->>'priority',p_source_kind=>v_item->>'source',p_owner_profile_id=>(v_item->>'ownerProfileId')::uuid);
   insert into public.requirement_areas(requirement_id,area_id,project_id,workspace_id) select v_req,x::uuid,p_project_id,v_r.workspace_id from jsonb_array_elements_text(coalesce(v_item->'areaIds','[]'::jsonb)) x;
   v_count:=v_count+1;
  end if;
  if v_kind='unchanged' and v_req<>v_old.requirement_id then v_kind:='changed';end if;
  insert into public.project_brief_requirement_links(revision_id,item_id,project_id,requirement_id) values(p_revision_id,v_item->>'id',p_project_id,v_req) on conflict do nothing;
  select status into v_status from public.requirements where id=v_req;
  insert into public.brief_requirement_changes(revision_id,item_id,project_id,kind,previous_requirement_id,requirement_id,previous_item,proposed_item,prepared_content,state,outcome,applied_by,applied_at)
  values(p_revision_id,v_item->>'id',p_project_id,v_kind,v_old.requirement_id,v_req,v_old.item,v_item,public.brief_requirement_expected(v_item),
   case when v_status='active' and ((v_old.requirement_id is null and public.brief_requirement_content(v_req)=public.brief_requirement_expected(v_item)) or (v_req=v_old.requirement_id and public.brief_requirement_content(v_req)=public.brief_requirement_expected(v_old.item))) then 'applied' else 'pending' end,
   case when v_status='active' and v_old.requirement_id is null and public.brief_requirement_content(v_req)=public.brief_requirement_expected(v_item) then 'activated' when v_status='active' and v_req=v_old.requirement_id and public.brief_requirement_content(v_req)=public.brief_requirement_expected(v_old.item) then 'reused' end,
   case when v_status='active' and ((v_old.requirement_id is null and public.brief_requirement_content(v_req)=public.brief_requirement_expected(v_item)) or (v_req=v_old.requirement_id and public.brief_requirement_content(v_req)=public.brief_requirement_expected(v_old.item))) then auth.uid() end,
   case when v_status='active' and ((v_old.requirement_id is null and public.brief_requirement_content(v_req)=public.brief_requirement_expected(v_item)) or (v_req=v_old.requirement_id and public.brief_requirement_content(v_req)=public.brief_requirement_expected(v_old.item))) then now() end);
 end loop;
 for v_old in select distinct on(l.item_id) l.item_id,l.requirement_id,i.value as item,r.number from public.project_brief_requirement_links l join public.project_brief_revisions r on r.id=l.revision_id cross join lateral jsonb_array_elements(r.document->'items') i
 where l.project_id=p_project_id and r.number<v_r.number and i.value->>'id'=l.item_id order by l.item_id,r.number desc loop
  if exists(select 1 from jsonb_array_elements(v_r.document->'items') i where i->>'id'=v_old.item_id and i->>'kind' in ('mandatory','preference')) or exists(select 1 from public.brief_requirement_changes where revision_id=p_revision_id and item_id=v_old.item_id) then continue;end if;
  if not exists(select 1 from public.requirements where id=v_old.requirement_id and status in ('draft','active')) or exists(select 1 from public.brief_requirement_changes c join public.project_brief_revisions r on r.id=c.revision_id where c.previous_requirement_id=v_old.requirement_id and c.kind='removed' and c.state='applied' and r.number<v_r.number) then continue;end if;
  insert into public.brief_requirement_changes(revision_id,item_id,project_id,kind,previous_requirement_id,previous_item) values(p_revision_id,v_old.item_id,p_project_id,'removed',v_old.requirement_id,v_old.item);
 end loop;
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload) values(v_r.workspace_id,p_project_id,'brief.requirements_prepared',auth.uid(),'user','project',p_project_id,'Brief requirement handoff',jsonb_build_object('revision_id',p_revision_id));
 return v_count;
end; $$;

-- Preserve the established generation entry point and first-agreement draft flow.
create or replace function public.generate_brief_requirements(p_project_id uuid,p_revision_id uuid)
returns integer language sql security definer set search_path='' as $$ select public.prepare_brief_requirement_changes(p_project_id,p_revision_id); $$;

create or replace function public.apply_brief_requirement_change(p_project_id uuid,p_revision_id uuid,p_item_id text,p_expected_token text,p_action text,p_acknowledge boolean default false,p_note text default '')
returns void language plpgsql security definer set search_path='' as $$
declare c public.brief_requirement_changes%rowtype;v_ws uuid;v_old public.requirements%rowtype;v_new public.requirements%rowtype;v_manual boolean;v_impact jsonb;begin
 perform 1 from public.projects where id=p_project_id for no key update;
 select workspace_id into v_ws from public.project_briefs where project_id=p_project_id and current_revision_id=p_revision_id and status='agreed' for update;
 if v_ws is null or not public.lign_manage_project_brief(p_project_id) or not public.lign_has_capability(p_project_id,v_ws,'requirement.edit') then raise exception 'Current agreed brief and requirement leadership required' using errcode='42501';end if;
 select * into c from public.brief_requirement_changes where revision_id=p_revision_id and item_id=p_item_id and project_id=p_project_id for update;
 if c.revision_id is null then raise exception 'Prepare this requirement change first' using errcode='23503';end if;
 if c.state<>'pending' then return;end if;
 perform 1 from public.requirements where id in(c.previous_requirement_id,c.requirement_id) order by id for update;
 if public.brief_requirement_review_token(p_revision_id,p_item_id) is distinct from p_expected_token then raise exception 'Requirements or linked work changed. Reload and review again.' using errcode='PT409';end if;
 select * into v_old from public.requirements where id=c.previous_requirement_id;select * into v_new from public.requirements where id=c.requirement_id;
 v_manual:=(v_old.id is not null and public.brief_requirement_content(v_old.id) is distinct from public.brief_requirement_expected(c.previous_item)) or (v_new.id is not null and c.prepared_content is distinct from public.brief_requirement_content(v_new.id));
 v_impact:=public.brief_requirement_impact(v_old.id);
 if not coalesce(p_acknowledge,false) then raise exception 'Confirm review of this change and any manual edits or linked work' using errcode='23514';end if;
 if length(trim(coalesce(p_note,'')))>3000 or ((v_manual or (v_impact->>'assets')::int+(v_impact->>'assessments')::int+(v_impact->>'proposals')::int>0 or p_action in ('retain','restore') or v_old.status in ('archived','superseded')) and length(trim(coalesce(p_note,'')))=0) then raise exception 'Record a review note for manual edits, linked work or retained requirements' using errcode='22023';end if;
 if c.kind='removed' then
  if p_action not in ('retire','retain') or p_action is null then raise exception 'Confirm retirement or retain independently' using errcode='22023';end if;
  if p_action='retire' and not public.lign_has_capability(p_project_id,v_ws,'requirement.archive') then raise exception 'Requirement archiving access required' using errcode='42501';end if;
  if v_old.status not in ('active','draft') and not(v_old.status='archived' and p_action='retire') and not(v_old.status='superseded' and p_action='retain') then raise exception 'Confirm the existing retirement or retain the independently managed replacement lineage' using errcode='23514';end if;
  update public.brief_requirement_changes set state='applied',outcome=case p_action when 'retire' then 'retired' else 'retained' end,review_note=case when length(trim(coalesce(p_note,'')))=0 then review_note else concat_ws(E'\n\n',nullif(review_note,''),'Reviewed by '||coalesce((select display_name from public.profiles where id=auth.uid()),'Project leadership')||' · '||now()::text||E'\n'||trim(p_note)) end,applied_by=auth.uid(),applied_at=now() where revision_id=p_revision_id and item_id=p_item_id;
  if p_action='retire' and v_old.status in ('active','draft') then perform public.archive_requirement(v_old.id);end if;
 else
  if not exists(select 1 from public.project_participants pp join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active' where pp.project_id=p_project_id and pp.status='active' and pp.role in ('lead','contributor') and wm.user_id=v_new.owner_profile_id) then raise exception 'Assign an active project lead or contributor to this proposed requirement before activation' using errcode='23514';end if;
  if p_action not in ('activate','restore') or p_action is null or v_new.status not in ('draft','active') then raise exception 'Choose a current proposed requirement to activate' using errcode='23514';end if;
  if c.previous_requirement_id is distinct from c.requirement_id and v_old.id is not null and v_old.status not in ('draft','active') and p_action<>'restore' then raise exception 'The source requirement was archived or superseded independently. Resolve its lineage before applying this replacement.' using errcode='23514';end if;
  update public.brief_requirement_changes set state='applied',outcome=case when requirement_id=previous_requirement_id then 'reused' else 'activated' end,review_note=case when length(trim(coalesce(p_note,'')))=0 then review_note else concat_ws(E'\n\n',nullif(review_note,''),'Reviewed by '||coalesce((select display_name from public.profiles where id=auth.uid()),'Project leadership')||' · '||now()::text||E'\n'||trim(p_note)) end,applied_by=auth.uid(),applied_at=now() where revision_id=p_revision_id and item_id=p_item_id;
  if v_new.status='draft' then perform public.edit_requirement(p_requirement_id=>v_new.id,p_status=>'active',p_priority=>null);end if;
  if v_old.id is not null and v_old.id<>v_new.id and v_old.status in ('draft','active') then perform public.supersede_requirement(v_old.id,v_new.id);end if;
 end if;
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload) values(v_ws,p_project_id,'brief.requirement_change_applied',auth.uid(),'user','project',p_project_id,'Brief requirement change',jsonb_build_object('revision_id',p_revision_id,'item_id',p_item_id,'action',p_action));
end; $$;

create or replace function public.match_brief_requirement_change(p_project_id uuid,p_revision_id uuid,p_new_item_id text,p_removed_item_id text,p_expected_new_token text,p_expected_removed_token text)
returns void language plpgsql security definer set search_path='' as $$
declare a public.brief_requirement_changes%rowtype;b public.brief_requirement_changes%rowtype;v_ws uuid;begin
 perform 1 from public.projects where id=p_project_id for no key update;
 select workspace_id into v_ws from public.project_briefs where project_id=p_project_id and current_revision_id=p_revision_id and status='agreed' for update;
 if v_ws is null or not public.lign_manage_project_brief(p_project_id) or not public.lign_has_capability(p_project_id,v_ws,'requirement.edit') then raise exception 'Current agreed brief and leadership required' using errcode='42501';end if;
 perform 1 from public.brief_requirement_changes where revision_id=p_revision_id and item_id in(p_new_item_id,p_removed_item_id) order by item_id for update;
 select * into a from public.brief_requirement_changes where revision_id=p_revision_id and item_id=p_new_item_id and project_id=p_project_id;
 select * into b from public.brief_requirement_changes where revision_id=p_revision_id and item_id=p_removed_item_id and project_id=p_project_id;
 if a.kind<>'added' or b.kind<>'removed' or a.state<>'pending' or b.state<>'pending' or a.item_id is null or b.item_id is null then raise exception 'Choose a pending new item and a pending removed item' using errcode='23514';end if;
 if public.brief_requirement_review_token(p_revision_id,p_new_item_id) is distinct from p_expected_new_token or public.brief_requirement_review_token(p_revision_id,p_removed_item_id) is distinct from p_expected_removed_token then raise exception 'Changes have moved on. Reload before matching.' using errcode='PT409';end if;
 if not exists(select 1 from public.requirements where id=a.requirement_id and status='draft') then raise exception 'Only an unactivated new draft can be matched' using errcode='23514';end if;
 update public.brief_requirement_changes set state='matched',outcome='matched',matched_item_id=p_new_item_id,applied_by=auth.uid(),applied_at=now() where revision_id=p_revision_id and item_id=p_removed_item_id;
 update public.brief_requirement_changes set kind='changed',previous_requirement_id=b.previous_requirement_id,previous_item=b.previous_item where revision_id=p_revision_id and item_id=p_new_item_id;
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload) values(v_ws,p_project_id,'brief.requirement_change_matched',auth.uid(),'user','project',p_project_id,'Brief requirement match',jsonb_build_object('revision_id',p_revision_id,'new_item_id',p_new_item_id,'removed_item_id',p_removed_item_id));
end; $$;

create or replace function public.unmatch_brief_requirement_change(p_project_id uuid,p_revision_id uuid,p_new_item_id text,p_removed_item_id text,p_expected_new_token text,p_expected_removed_token text)
returns void language plpgsql security definer set search_path='' as $$
declare a public.brief_requirement_changes%rowtype;b public.brief_requirement_changes%rowtype;v_ws uuid;begin
 perform 1 from public.projects where id=p_project_id for no key update;
 select workspace_id into v_ws from public.project_briefs where project_id=p_project_id and current_revision_id=p_revision_id and status='agreed' for update;
 if v_ws is null or not public.lign_manage_project_brief(p_project_id) or not public.lign_has_capability(p_project_id,v_ws,'requirement.edit') then raise exception 'Current agreed brief and leadership required' using errcode='42501';end if;
 perform 1 from public.brief_requirement_changes where revision_id=p_revision_id and item_id in(p_new_item_id,p_removed_item_id) order by item_id for update;
 select * into a from public.brief_requirement_changes where revision_id=p_revision_id and item_id=p_new_item_id and project_id=p_project_id;
 select * into b from public.brief_requirement_changes where revision_id=p_revision_id and item_id=p_removed_item_id and project_id=p_project_id;
 if a.item_id is null or b.item_id is null or a.state<>'pending' or b.state<>'matched' or b.matched_item_id<>a.item_id then raise exception 'Only an unapplied replacement match can be undone' using errcode='23514';end if;
 if public.brief_requirement_review_token(p_revision_id,p_new_item_id) is distinct from p_expected_new_token or public.brief_requirement_review_token(p_revision_id,p_removed_item_id) is distinct from p_expected_removed_token then raise exception 'Changes have moved on. Reload before undoing this match.' using errcode='PT409';end if;
 update public.brief_requirement_changes set kind='added',previous_requirement_id=null,previous_item=null where revision_id=p_revision_id and item_id=p_new_item_id;
 update public.brief_requirement_changes set state='pending',outcome=null,matched_item_id=null,applied_by=null,applied_at=null where revision_id=p_revision_id and item_id=p_removed_item_id;
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload) values(v_ws,p_project_id,'brief.requirement_change_matched',auth.uid(),'user','project',p_project_id,'Brief requirement match undone',jsonb_build_object('revision_id',p_revision_id,'new_item_id',p_new_item_id,'removed_item_id',p_removed_item_id,'undone',true));
end; $$;

create or replace function public.rebuild_brief_requirement_draft(p_project_id uuid,p_revision_id uuid,p_item_id text,p_expected_token text,p_note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.brief_requirement_changes%rowtype;v_ws uuid;v_req uuid;v_number integer;begin
 perform 1 from public.projects where id=p_project_id for no key update;
 select workspace_id into v_ws from public.project_briefs where project_id=p_project_id and status='agreed' and current_revision_id=p_revision_id for update;
 if v_ws is null or not public.lign_manage_project_brief(p_project_id) or not public.lign_has_capability(p_project_id,v_ws,'requirement.create') or not public.lign_has_capability(p_project_id,v_ws,'requirement.edit') then raise exception 'Current agreed brief and requirement leadership required' using errcode='42501';end if;
 select * into c from public.brief_requirement_changes where revision_id=p_revision_id and item_id=p_item_id and project_id=p_project_id for update;
 if c.revision_id is null or c.state<>'pending' or c.proposed_item is null or not exists(select 1 from public.requirements where id=c.requirement_id and status in ('archived','superseded')) then raise exception 'Only an independently retired proposed draft can be rebuilt' using errcode='23514';end if;
 perform 1 from public.requirements where id=c.requirement_id for update;
 if public.brief_requirement_review_token(p_revision_id,p_item_id) is distinct from p_expected_token then raise exception 'The proposed requirement changed. Reload before rebuilding.' using errcode='PT409';end if;
 if p_note is null or length(trim(p_note)) not between 1 and 3000 then raise exception 'Explain why this draft should be prepared again' using errcode='22023';end if;
 if not exists(select 1 from public.project_participants pp join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active' where pp.project_id=p_project_id and pp.status='active' and pp.role in ('lead','contributor') and wm.user_id=(c.proposed_item->>'ownerProfileId')::uuid) then raise exception 'Restore active project responsibility before rebuilding this draft' using errcode='23514';end if;
 select number into v_number from public.project_brief_revisions where id=p_revision_id;
 select out_requirement_id into v_req from public.create_requirement(p_project_id=>p_project_id,p_workspace_id=>v_ws,p_title=>c.proposed_item->>'title',p_description=>public.brief_requirement_description(c.proposed_item),p_source_ref=>'Brief revision '||v_number||' · item '||c.item_id,p_status=>'draft',p_priority=>c.proposed_item->>'priority',p_source_kind=>c.proposed_item->>'source',p_owner_profile_id=>(c.proposed_item->>'ownerProfileId')::uuid);
 insert into public.requirement_areas(requirement_id,area_id,project_id,workspace_id) select v_req,x::uuid,p_project_id,v_ws from jsonb_array_elements_text(coalesce(c.proposed_item->'areaIds','[]'::jsonb)) x;
 update public.brief_requirement_changes set requirement_id=v_req,prepared_content=public.brief_requirement_expected(c.proposed_item),review_note=concat_ws(E'\n\n',nullif(review_note,''),'Draft rebuilt by '||coalesce((select display_name from public.profiles where id=auth.uid()),'Project leadership')||' · '||now()::text||E'\n'||trim(p_note)) where revision_id=p_revision_id and item_id=p_item_id;
 update public.project_brief_requirement_links set requirement_id=v_req where revision_id=p_revision_id and item_id=p_item_id;
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload) values(v_ws,p_project_id,'brief.requirements_prepared',auth.uid(),'user','project',p_project_id,'Brief requirement draft rebuilt',jsonb_build_object('revision_id',p_revision_id,'item_id',p_item_id,'previous_draft_id',c.requirement_id,'new_draft_id',v_req));
 return v_req;
end; $$;

create or replace function public.guard_brief_requirement_activation()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='superseded' and exists(select 1 from public.brief_requirement_changes c where c.previous_requirement_id=old.id and c.requirement_id=new.superseded_by_requirement_id and c.state='pending') then raise exception 'Apply this replacement through the brief requirement handoff' using errcode='23514';end if;
 if new.status='active' and old.status<>'active' and exists(select 1 from public.brief_requirement_changes c where c.requirement_id=new.id and c.state='pending' and (c.previous_requirement_id is not null or public.brief_requirement_content(old.id) is distinct from c.prepared_content or (to_jsonb(new)-'status'-'updated_at') is distinct from (to_jsonb(old)-'status'-'updated_at'))) then raise exception 'Review and apply this replacement from the brief requirement handoff' using errcode='23514';end if;
 if new.status='active' and old.status<>'active' and exists(select 1 from public.brief_requirement_changes where requirement_id=new.id and state='pending') and not exists(select 1 from public.project_participants pp join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active' where pp.project_id=new.project_id and pp.status='active' and pp.role in ('lead','contributor') and wm.user_id=new.owner_profile_id) then raise exception 'Assign active project responsibility before activation' using errcode='23514';end if;
 if new.status='active' and old.status<>'active' then update public.brief_requirement_changes set state='applied',outcome='activated',applied_by=auth.uid(),applied_at=now() where requirement_id=new.id and previous_requirement_id is null and state='pending';end if;
 return new;
end; $$;
create trigger brief_requirement_activation_guard before update of status on public.requirements for each row execute function public.guard_brief_requirement_activation();

create or replace function public.guard_pending_brief_handoff()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.status='agreed' and new.status='draft' and exists(select 1 from public.brief_requirement_changes where project_id=old.project_id and state='pending') then raise exception 'Complete the pending requirement handoff before starting another brief revision' using errcode='23514';end if;return new;end; $$;
create trigger brief_pending_handoff_guard before update of status on public.project_briefs for each row execute function public.guard_pending_brief_handoff();

revoke all on function public.brief_requirement_description(jsonb),public.brief_requirement_content(uuid),public.brief_requirement_expected(jsonb),public.brief_requirement_impact(uuid),public.brief_requirement_review_token(uuid,text),public.guard_brief_requirement_activation(),public.guard_pending_brief_handoff() from public,anon,authenticated;
revoke all on function public.get_brief_requirement_changes(uuid,uuid),public.prepare_brief_requirement_changes(uuid,uuid),public.generate_brief_requirements(uuid,uuid),public.apply_brief_requirement_change(uuid,uuid,text,text,text,boolean,text),public.match_brief_requirement_change(uuid,uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.get_brief_requirement_changes(uuid,uuid),public.prepare_brief_requirement_changes(uuid,uuid),public.generate_brief_requirements(uuid,uuid),public.apply_brief_requirement_change(uuid,uuid,text,text,text,boolean,text),public.match_brief_requirement_change(uuid,uuid,text,text,text,text) to authenticated,service_role;

revoke all on function public.unmatch_brief_requirement_change(uuid,uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.unmatch_brief_requirement_change(uuid,uuid,text,text,text,text) to authenticated,service_role;

revoke all on function public.rebuild_brief_requirement_draft(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.rebuild_brief_requirement_draft(uuid,uuid,text,text,text) to authenticated,service_role;
