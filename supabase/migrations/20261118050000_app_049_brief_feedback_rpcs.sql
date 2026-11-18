create or replace function public.preserve_brief_feedback_record()
returns trigger language plpgsql set search_path='' as $$ begin
 if tg_table_name='brief_feedback_events' or tg_op='DELETE' then raise exception 'Feedback history cannot be changed or deleted' using errcode='23514';end if;
 if (new.id,new.project_id,new.source_revision_id,new.target_kind,new.target_id,new.body,new.from_decision,new.created_by,new.created_at) is distinct from (old.id,old.project_id,old.source_revision_id,old.target_kind,old.target_id,old.body,old.from_decision,old.created_by,old.created_at) then raise exception 'The original feedback record is immutable' using errcode='23514';end if;return new;end; $$;
create trigger brief_feedback_record_immutable before update or delete on public.brief_feedback_items for each row execute function public.preserve_brief_feedback_record();
create trigger brief_feedback_events_immutable before update or delete on public.brief_feedback_events for each row execute function public.preserve_brief_feedback_record();

-- Preserve original change requests as tracked overall feedback, including existing beta data.
insert into public.brief_feedback_items(project_id,source_revision_id,body,from_decision,created_by,created_at)
select project_id,revision_id,comment,true,actor_id,created_at from public.project_brief_decisions where decision='changes_requested' on conflict do nothing;
insert into public.brief_feedback_events(feedback_id,project_id,actor_id,action,note,revision_id,created_at)
select id,project_id,created_by,'created',body,source_revision_id,created_at from public.brief_feedback_items where from_decision;

create or replace function public.track_brief_decision_feedback()
returns trigger language plpgsql security definer set search_path='' as $$ declare v_id uuid;begin
 if new.decision='changes_requested' then
 insert into public.brief_feedback_items(project_id,source_revision_id,body,from_decision,created_by) values(new.project_id,new.revision_id,new.comment,true,new.actor_id) returning id into v_id;
 insert into public.brief_feedback_events(feedback_id,project_id,actor_id,action,note,revision_id) values(v_id,new.project_id,new.actor_id,'created',new.comment,new.revision_id);
 end if;return new;end; $$;
create trigger brief_decision_feedback after insert on public.project_brief_decisions for each row execute function public.track_brief_decision_feedback();

create or replace function public.brief_feedback_draft_digest(p_project_id uuid)
returns text language sql stable security definer set search_path='' as $$
 select md5(jsonb_build_object('document',b.document,
 'files',(select jsonb_agg(jsonb_build_object('id',f.id,'path',f.storage_path,'name',f.name,'size',f.size_bytes) order by f.id) from public.project_brief_files f where f.project_id=p_project_id and f.removed_at is null),
 'references',(select jsonb_agg(public.reference_card_snapshot(c.id) order by rb.title,c.id) from public.reference_cards c join public.reference_boards rb on rb.id=c.board_id where c.project_id=p_project_id and c.selected_for_brief and c.archived_at is null and rb.archived_at is null and rb.shared_at is not null))::text)
 from public.project_briefs b where b.project_id=p_project_id; $$;

create or replace function public.bind_brief_feedback_revision()
returns trigger language plpgsql security definer set search_path='' as $$ declare v_digest text;f record;begin
 v_digest:=public.brief_feedback_draft_digest(new.project_id);
 for f in update public.brief_feedback_items set response_revision_id=new.id,edit_version=edit_version+1
 where project_id=new.project_id and status='addressed' and response_revision_id is null and response_content_digest=v_digest returning id,addressed_by loop
 insert into public.brief_feedback_events(feedback_id,project_id,actor_id,action,revision_id) values(f.id,new.project_id,f.addressed_by,'included_in_revision',new.id);
 end loop;return new;end; $$;
create trigger brief_feedback_revision_binding after insert on public.project_brief_revisions for each row execute function public.bind_brief_feedback_revision();

create or replace function public.get_brief_feedback(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$ declare v_ws uuid;v_b public.project_briefs%rowtype;v_team boolean;v_digest text;begin
 select workspace_id into v_ws from public.projects where id=p_project_id;
 if v_ws is null or not public.lign_has_capability(p_project_id,v_ws,'project.view') then raise exception 'Project access required' using errcode='42501';end if;
 select * into v_b from public.project_briefs where project_id=p_project_id;
 v_team:=public.lign_manage_project_brief(p_project_id) or coalesce(public.lign_project_role(p_project_id) in ('lead','contributor'),false);
 v_digest:=public.brief_feedback_draft_digest(p_project_id);
 return jsonb_build_object('canAddress',v_team,'canCreateFor',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'number',r.number) order by r.number desc) from public.project_brief_revisions r join public.project_brief_decisions d on d.revision_id=r.id where r.project_id=p_project_id and d.decision='changes_requested' and (public.lign_manage_project_brief(p_project_id) or d.actor_id=auth.uid())),'[]'::jsonb),'rows',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'sourceRevisionId',f.source_revision_id,'sourceNumber',r.number,'targetKind',f.target_kind,'targetId',f.target_id,'body',f.body,'fromDecision',f.from_decision,'creatorName',p.display_name,'createdAt',f.created_at,
 'status',f.status,'version',f.edit_version,'response',f.response,'addressedBy',a.display_name,'addressedAt',f.addressed_at,'responseRevisionId',f.response_revision_id,'responseNumber',rr.number,'responseEditVersion',f.response_edit_version,
 'verifiedBy',vp.display_name,'verifiedAt',f.verified_at,'verifiedNumber',vr.number,
 'stale',f.status='addressed' and case when f.response_revision_id is not null then f.response_revision_id is distinct from v_b.current_revision_id or v_b.status not in ('awaiting_agreement','agreed') else f.response_content_digest is distinct from v_digest or v_b.status not in ('draft','submitted') end,
 'canVerify',coalesce(f.status='addressed' and d.actor_id=auth.uid() and f.addressed_by is distinct from auth.uid() and f.response_revision_id=v_b.current_revision_id and v_b.status in ('awaiting_agreement','agreed'),false),
 'canReopen',d.actor_id=auth.uid() and f.status<>'open',
 'events',coalesce((select jsonb_agg(jsonb_build_object('action',e.action,'note',e.note,'at',e.created_at,'actorName',ep.display_name,'revisionNumber',er.number) order by e.created_at,e.id) from public.brief_feedback_events e join public.profiles ep on ep.id=e.actor_id left join public.project_brief_revisions er on er.id=e.revision_id where e.feedback_id=f.id),'[]'::jsonb)) order by r.number desc,f.created_at,f.id)
 from public.brief_feedback_items f join public.project_brief_revisions r on r.id=f.source_revision_id join public.project_brief_decisions d on d.revision_id=f.source_revision_id join public.profiles p on p.id=f.created_by left join public.profiles a on a.id=f.addressed_by left join public.profiles vp on vp.id=f.verified_by left join public.project_brief_revisions rr on rr.id=f.response_revision_id left join public.project_brief_revisions vr on vr.id=f.verified_revision_id where f.project_id=p_project_id),'[]'::jsonb));end; $$;

create or replace function public.add_brief_feedback_item(p_project_id uuid,p_source_revision_id uuid,p_body text,p_target_kind text default 'overall',p_target_id text default null)
returns uuid language plpgsql security definer set search_path='' as $$ declare v_r public.project_brief_revisions%rowtype;v_actor uuid;v_id uuid;begin
 perform 1 from public.projects where id=p_project_id and archived_at is null and status<>'archived' for no key update;
 if not found then raise exception 'Archived projects cannot receive feedback updates' using errcode='23514';end if;
 select * into v_r from public.project_brief_revisions where id=p_source_revision_id and project_id=p_project_id;
 select actor_id into v_actor from public.project_brief_decisions where revision_id=p_source_revision_id and decision='changes_requested';
 if v_r.id is null or v_actor is null or not public.lign_has_capability(p_project_id,v_r.workspace_id,'project.view') or not(public.lign_manage_project_brief(p_project_id) or v_actor=auth.uid()) then raise exception 'Feedback author or leadership access required for a change request' using errcode='42501';end if;
 if p_body is null or length(trim(p_body)) not between 1 and 5000 or p_target_kind is null or p_target_kind not in ('overall','field','item','reference') or (p_target_kind='overall' and p_target_id is not null) or (p_target_kind<>'overall' and p_target_id is null) then raise exception 'Choose a valid feedback target and description' using errcode='22023';end if;
 if p_target_kind<>'overall' and not exists(select 1 from jsonb_array_elements(case p_target_kind when 'field' then v_r.document->'fields' when 'item' then v_r.document->'items' else v_r.document->'references' end) x where x->>'id'=p_target_id) then raise exception 'Choose an item from the source revision' using errcode='23503';end if;
 insert into public.brief_feedback_items(project_id,source_revision_id,target_kind,target_id,body,created_by) values(p_project_id,p_source_revision_id,p_target_kind,p_target_id,trim(p_body),auth.uid()) returning id into v_id;
 insert into public.brief_feedback_events(feedback_id,project_id,actor_id,action,note,revision_id) values(v_id,p_project_id,auth.uid(),'created',trim(p_body),p_source_revision_id);
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload) values(v_r.workspace_id,p_project_id,'brief.feedback_created',auth.uid(),'user','project',p_project_id,'Brief feedback',jsonb_build_object('feedback_id',v_id,'revision_id',p_source_revision_id));return v_id;end; $$;

create or replace function public.act_on_brief_feedback(p_project_id uuid,p_feedback_id uuid,p_expected_version bigint,p_action text,p_note text,p_expected_brief_version bigint default null,p_review_revision_id uuid default null)
returns void language plpgsql security definer set search_path='' as $$ declare f public.brief_feedback_items%rowtype;b public.project_briefs%rowtype;v_author uuid;v_team boolean;v_revision uuid;begin
 perform 1 from public.projects where id=p_project_id and archived_at is null and status<>'archived' for no key update;
 if not found then raise exception 'Archived projects cannot receive feedback updates' using errcode='23514';end if;
 select * into b from public.project_briefs where project_id=p_project_id for update;
 if b.id is null or not public.lign_has_capability(p_project_id,b.workspace_id,'project.view') then raise exception 'Project access required' using errcode='42501';end if;
 select * into f from public.brief_feedback_items where id=p_feedback_id and project_id=p_project_id for update;
 if f.id is null then raise exception 'Feedback not found in this project' using errcode='23503';end if;
 if f.edit_version is distinct from p_expected_version then raise exception 'Feedback changed. Reload before continuing.' using errcode='PT409';end if;
 if p_note is null or length(trim(p_note)) not between 1 and 5000 then raise exception 'Record a response or verification note' using errcode='22023';end if;
 select actor_id into v_author from public.project_brief_decisions where revision_id=f.source_revision_id and decision='changes_requested';
 v_team:=public.lign_manage_project_brief(p_project_id) or coalesce(public.lign_project_role(p_project_id) in ('lead','contributor'),false);
 if p_action='address' then
  if not v_team or f.status='verified' then raise exception 'The internal team can address open feedback; client verification must be reopened by the client' using errcode='42501';end if;
  if b.edit_version is distinct from p_expected_brief_version then raise exception 'The brief changed. Save and reload before marking feedback addressed.' using errcode='PT409';end if;
  v_revision:=case when b.status in ('awaiting_agreement','agreed') then b.current_revision_id end;
  update public.brief_feedback_items set status='addressed',response=trim(p_note),addressed_by=auth.uid(),addressed_at=now(),response_edit_version=b.edit_version,response_content_digest=case when v_revision is null then public.brief_feedback_draft_digest(p_project_id) end,response_revision_id=v_revision,verified_by=null,verified_at=null,verified_revision_id=null,edit_version=edit_version+1 where id=f.id;
 elsif p_action='verify' then
  if auth.uid() is distinct from v_author or auth.uid() is not distinct from f.addressed_by then raise exception 'The original client decision-maker must independently verify the response' using errcode='42501';end if;
  if f.status<>'addressed' or f.response_revision_id is null or p_review_revision_id is distinct from f.response_revision_id or f.response_revision_id is distinct from b.current_revision_id or b.status not in ('awaiting_agreement','agreed') then raise exception 'Review the current requested or agreed revision before verifying this response' using errcode='PT409';end if;
  v_revision:=f.response_revision_id;
  update public.brief_feedback_items set status='verified',verified_by=auth.uid(),verified_at=now(),verified_revision_id=v_revision,edit_version=edit_version+1 where id=f.id;
 elsif p_action='reopen' then
  if auth.uid() is distinct from v_author then raise exception 'Only the client who requested these changes can reopen verification' using errcode='42501';end if;
  if f.status='open' then raise exception 'This feedback is already open' using errcode='23514';end if;
  v_revision:=b.current_revision_id;
  update public.brief_feedback_items set status='open',verified_by=null,verified_at=null,verified_revision_id=null,edit_version=edit_version+1 where id=f.id;
 else raise exception 'Choose address, verify or reopen' using errcode='22023';end if;
 insert into public.brief_feedback_events(feedback_id,project_id,actor_id,action,note,revision_id) values(f.id,p_project_id,auth.uid(),case p_action when 'address' then 'addressed' when 'verify' then 'verified' else 'reopened' end,trim(p_note),v_revision);
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload) values(b.workspace_id,p_project_id,'brief.feedback_'||case p_action when 'address' then 'addressed' when 'verify' then 'verified' else 'reopened' end,auth.uid(),'user','project',p_project_id,'Brief feedback',jsonb_build_object('feedback_id',f.id,'revision_id',v_revision));end; $$;

revoke all on function public.preserve_brief_feedback_record(),public.track_brief_decision_feedback(),public.bind_brief_feedback_revision() from public,anon,authenticated;
revoke all on function public.get_brief_feedback(uuid),public.add_brief_feedback_item(uuid,uuid,text,text,text),public.act_on_brief_feedback(uuid,uuid,bigint,text,text,bigint,uuid) from public,anon,authenticated;
grant execute on function public.get_brief_feedback(uuid),public.add_brief_feedback_item(uuid,uuid,text,text,text),public.act_on_brief_feedback(uuid,uuid,bigint,text,text,bigint,uuid) to authenticated,service_role;

revoke all on function public.brief_feedback_draft_digest(uuid) from public,anon,authenticated;
