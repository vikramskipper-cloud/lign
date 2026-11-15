-- APP 037: permission-aware summaries shared by project, workspace and studio homes.
-- Summary reads and existing recipient-scoped mark-read behavior; no change to decision permissions.
create or replace function public.get_project_overview(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare
 p public.projects%rowtype; b public.project_briefs%rowtype; proposal public.project_proposals%rowtype;
 team boolean; manage boolean; brief_ready boolean; design_ready boolean; base text;
 actions jsonb := '[]'; shared jsonb; activity jsonb; lead_names text; respondent text; act boolean;
begin
 select * into p from public.projects where id=p_project_id;
 if auth.uid() is null or p.id is null or not public.lign_has_capability(p.id,p.workspace_id,'project.view') then
  raise exception 'Project access required' using errcode='42501'; end if;
 team:=public.lign_design_team(p.id); manage:=team and public.lign_manage_project_brief(p.id);
 brief_ready:=public.lign_project_has_agreed_brief(p.id); design_ready:=public.lign_project_ready_for_design(p.id);
 base:='/workspace/'||p.workspace_id||'/project/'||p.id||'/';
 select string_agg(coalesce(pr.display_name,sh.display_name,sh.email::text),', ' order by pp.id) into lead_names
 from public.project_participants pp left join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
 left join public.stakeholders sh on sh.id=pp.stakeholder_id and sh.status='active'
 left join public.profiles pr on pr.id=coalesce(wm.user_id,sh.user_id)
 where pp.project_id=p.id and pp.status='active' and pp.role='lead';
 select * into b from public.project_briefs where project_id=p.id;
 select * into proposal from public.project_proposals where project_id=p.id;
 if p.archived_at is null and p.status<>'archived' then
  -- Unpublished brief/proposal work is surfaced to the internal team only.
  -- Named respondents see only their own pending decision/edit opportunity.
  if not brief_ready or b.status in ('submitted','awaiting_agreement') then
   act:=coalesce(public.lign_brief_respondent_user(b.respondent_participant_id,p.id)=auth.uid(),false);
   if team or (act and b.status in ('draft','awaiting_agreement')) then
    select coalesce(pr.display_name,sh.display_name,sh.email::text) into respondent from public.project_participants pp
    left join public.workspace_members wm on wm.id=pp.workspace_member_id left join public.stakeholders sh on sh.id=pp.stakeholder_id
    left join public.profiles pr on pr.id=coalesce(wm.user_id,sh.user_id) where pp.id=b.respondent_participant_id;
    actions:=actions||jsonb_build_array(jsonb_build_object('id','brief-'||p.id,'kind','brief',
     'title',case b.status when 'awaiting_agreement' then 'Agree the project brief' when 'submitted' then 'Review the brief and request agreement' else 'Gather requirements and references' end,
     'to',base||'brief','responsible',case when b.status='awaiting_agreement' then coalesce(respondent,'Assigned approver') else coalesce(lead_names,'Project leadership') end,
     'canAct',case when b.status='awaiting_agreement' then act when b.status='submitted' then manage else manage or coalesce(public.lign_edit_project_brief(p.id),false) end,
     'audience',case when b.status='awaiting_agreement' then 'client' else 'team' end,'since',coalesce(b.updated_at,p.created_at),'dueAt',null));
   end if;
  end if;
  if brief_ready and (not design_ready or proposal.status in ('submitted','awaiting_acceptance')) then
   act:=coalesce(proposal.status='awaiting_acceptance' and public.lign_can_read_proposal_revision(proposal.current_revision_id)
     and public.lign_brief_respondent_user(proposal.respondent_id,p.id)=auth.uid()
     and exists(select 1 from public.proposal_revisions r where r.id=proposal.current_revision_id and r.reviewed_by<>auth.uid()),false);
   if team or act then
    select coalesce(pr.display_name,sh.display_name,sh.email::text) into respondent from public.project_participants pp
    left join public.workspace_members wm on wm.id=pp.workspace_member_id left join public.stakeholders sh on sh.id=pp.stakeholder_id
    left join public.profiles pr on pr.id=coalesce(wm.user_id,sh.user_id) where pp.id=proposal.respondent_id;
    actions:=actions||jsonb_build_array(jsonb_build_object('id','proposal-'||p.id,'kind','proposal',
     'title',case proposal.status when 'awaiting_acceptance' then 'Accept the design proposal' when 'submitted' then 'Review the proposal before sending to client' else 'Prepare the design proposal' end,
     'to',base||'proposal','responsible',case proposal.status when 'awaiting_acceptance' then coalesce(respondent,'Assigned approver') when 'submitted' then 'A different project or studio leader' else coalesce(lead_names,'Project team') end,
     'canAct',case proposal.status when 'awaiting_acceptance' then act when 'submitted' then manage and proposal.created_by<>auth.uid() else public.lign_prepare_proposal(p.id) end,
     'audience',case when proposal.status='awaiting_acceptance' then 'client' else 'team' end,'since',coalesce(proposal.updated_at,b.updated_at,p.created_at),'dueAt',null));
   end if;
  end if;
  if team and design_ready then
   select actions||coalesce(jsonb_agg(jsonb_build_object('id','version-'||v.id,'kind','internal_signoff',
    'title',case when ds.stage='submitted' then 'Review consultant submission' else case r.stage when 'submitted' then 'Internal sign-off' when 'approved' then 'Publish approved design' else 'Address internal feedback' end end||' · '||a.name||' · v'||v.sequence,
    'to',case when ds.id is not null then base||'deliverable/'||ds.id else base||'asset/'||a.id||'/v/'||v.id end,'responsible',case r.stage when 'submitted' then 'A different project or studio leader' when 'approved' then coalesce(lead_names,'Project leadership') else coalesce(pr.display_name,'Version author') end,
    'canAct',case r.stage when 'submitted' then manage and r.author_id is distinct from auth.uid() and not exists(select 1 from public.version_files vf join public.files f on f.id=vf.file_id where vf.asset_version_id=v.id and f.uploaded_by_profile_id=auth.uid()) when 'approved' then manage or public.lign_has_capability(p.id,p.workspace_id,'version.publish') else (case when ds.id is not null then ds.author_id=auth.uid() and public.lign_can_submit_deliverables(p.id) else r.author_id=auth.uid() or manage end) and public.lign_has_capability(p.id,p.workspace_id,'version.upload') end,
    'audience','team','since',coalesce(case when r.stage='submitted' then r.submitted_at else r.reviewed_at end,v.created_at),'dueAt',null) order by r.submitted_at nulls last),'[]'::jsonb) into actions
   from public.design_version_reviews r join public.asset_versions v on v.id=r.version_id join public.design_assets a on a.id=v.design_asset_id
   left join public.profiles pr on pr.id=r.author_id
   left join public.deliverable_submissions ds on ds.asset_version_id=v.id and ds.stage<>'accepted'
   where v.project_id=p.id and v.status='draft' and a.archived_at is null and (ds.id is null or ds.stage in ('submitted','changes_requested')) and r.stage in ('submitted','approved','changes_requested');
  end if;
  if not team and public.lign_can_submit_deliverables(p.id) then
   select actions||coalesce(jsonb_agg(jsonb_build_object('id','submission-'||s.id,'kind','submission',
    'title',case s.stage when 'submitted' then 'Submission awaiting internal sign-off' when 'changes_requested' then 'Address submission feedback' else 'Prepare your submission' end||' · '||s.title,
    'to',base||'deliverable/'||s.id,'responsible',case when s.stage='submitted' then 'Project leadership' else 'You' end,
    'canAct',s.stage<>'submitted','audience','team','since',s.updated_at,'dueAt',null)),'[]'::jsonb) into actions
   from public.deliverable_submissions s where s.project_id=p.id and s.author_id=auth.uid() and s.stage in ('draft','changes_requested','submitted') and public.lign_can_read_design_version(s.asset_version_id);
  end if;
  -- Pending formal requests include only rosters visible under APP 036.
  select actions||coalesce(jsonb_agg(jsonb_build_object('id','review-'||r.id,'kind','review','title','Design review · '||r.title,
   'to',base||'review/'||r.id,'responsible',case when not team then 'Assigned reviewers' else coalesce((select string_agg(coalesce(pr.display_name,sh.display_name,sh.email::text),', ' order by rp.id)
     from public.review_participants rp left join public.workspace_members wm on wm.id=rp.workspace_member_id left join public.stakeholders sh on sh.id=rp.stakeholder_id left join public.profiles pr on pr.id=coalesce(wm.user_id,sh.user_id)
     where rp.review_id=r.id and rp.removed_at is null and rp.responded_at is null),'Assigned reviewers') end,
   'canAct',public.lign_has_capability(p.id,p.workspace_id,'review.participate') and exists(select 1 from public.review_participants rp left join public.workspace_members wm on wm.id=rp.workspace_member_id and wm.status='active' left join public.stakeholders sh on sh.id=rp.stakeholder_id and sh.status='active' where rp.review_id=r.id and rp.removed_at is null and rp.responded_at is null and coalesce(wm.user_id,sh.user_id)=auth.uid()),
   'audience','reviewers','since',r.created_at,'dueAt',r.due_at) order by r.created_at),'[]'::jsonb) into actions
  from public.vp_read_reviews r where r.project_id=p.id and r.status in ('open','in_progress','waiting');
  select actions||coalesce(jsonb_agg(jsonb_build_object('id','approval-'||r.id,'kind','approval','title','Design approval · '||coalesce(r.title,'Approval request'),
   'to',base||'approval/'||r.id,'responsible',case when not team then 'Assigned approvers' else coalesce((select string_agg(coalesce(pr.display_name,sh.display_name,sh.email::text),', ' order by rp.id)
     from public.approval_request_approvers rp left join public.workspace_members wm on wm.id=rp.workspace_member_id left join public.stakeholders sh on sh.id=rp.stakeholder_id left join public.profiles pr on pr.id=coalesce(wm.user_id,sh.user_id)
     where rp.approval_request_id=r.id and rp.removed_at is null and not exists(select 1 from public.approval_responses ar where ar.approver_slot_id=rp.id)),'Assigned approvers') end,
   'canAct',public.lign_has_capability(p.id,p.workspace_id,'approval.respond') and exists(select 1 from public.approval_request_approvers rp left join public.workspace_members wm on wm.id=rp.workspace_member_id and wm.status='active' left join public.stakeholders sh on sh.id=rp.stakeholder_id and sh.status='active' where rp.approval_request_id=r.id and rp.removed_at is null and coalesce(wm.user_id,sh.user_id)=auth.uid() and not exists(select 1 from public.approval_responses ar where ar.approver_slot_id=rp.id) and (r.policy<>'sequential' or not exists(select 1 from public.approval_request_approvers prior left join public.approval_responses answer on answer.approver_slot_id=prior.id where prior.approval_request_id=r.id and prior.removed_at is null and prior.sort_order<rp.sort_order and (answer.decision is null or answer.decision<>'approved')))),
   'audience','client','since',coalesce(r.sent_at,r.created_at),'dueAt',r.due_at) order by r.created_at),'[]'::jsonb) into actions
  from public.vp_read_approval_requests r where r.project_id=p.id and r.status in ('pending','in_progress');
 end if;
 -- An external recipient sees their own shared revisions, never the team's working list or other recipients.
 select coalesce(jsonb_agg(x.item order by x.at desc),'[]'::jsonb) into shared from (
  select max(s.shared_at) at,jsonb_build_object('id',v.id,'name',a.name,'revision',v.sequence,'to',base||'asset/'||a.id||'/v/'||v.id,
   'decisionStatus',(select ar.status from public.vp_read_approval_requests ar where ar.version_id=v.id order by ar.created_at desc limit 1),'at',max(s.shared_at),'recipients',case when manage then string_agg(distinct coalesce(pr.display_name,sh.display_name,sh.email::text),', ') else null end) item
  from public.design_version_shares s join public.asset_versions v on v.id=s.version_id join public.design_assets a on a.id=v.design_asset_id
  join public.project_participants pp on pp.id=s.participant_id and pp.status='active'
  left join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active' left join public.stakeholders sh on sh.id=pp.stakeholder_id and sh.status in ('active','invited')
  left join public.profiles pr on pr.id=coalesce(wm.user_id,sh.user_id)
  where v.project_id=p.id and s.revoked_at is null and public.lign_can_read_design_version(v.id)
   and (team or public.lign_design_participant_user(pp.id,p.id)=auth.uid())
  group by v.id,a.id order by max(s.shared_at) desc limit 6
 )x;
 select coalesce(jsonb_agg(x.item order by x.at desc),'[]'::jsonb) into activity from (
  select e.occurred_at at,jsonb_build_object('id',e.id,'eventType',e.event_type,'subject',e.subject_label,'actor',coalesce(pr.display_name,'System'),'at',e.occurred_at) item
  from public.vp_read_activity_events e left join public.profiles pr on pr.id=e.actor_profile_id where e.project_id=p.id
   and e.event_type !~ '(attached|presence|participant_access|participant_removed)'
  order by e.occurred_at desc limit 5
 )x;
 return jsonb_build_object('projectId',p.id,'workspaceId',p.workspace_id,'internal',team,'lead',coalesce(lead_names,'Not assigned'),
  'phase',case when design_ready then 'Detailed design' when brief_ready then 'Design proposal' else 'Requirements & references' end,
  'briefReady',brief_ready,'designReady',design_ready,'actions',actions,'shared',shared,'activity',activity,
  'accepted',jsonb_build_object('brief',brief_ready,'proposal',design_ready,
   'briefRevision',(select jsonb_build_object('id',r.id,'number',r.number) from public.project_brief_revisions r join public.project_brief_decisions d on d.revision_id=r.id where r.project_id=p.id and d.decision='agreed' order by r.number desc limit 1),
   'proposalRevision',(select jsonb_build_object('id',r.id,'number',r.number) from public.vp_read_proposal_revisions r join public.vp_read_proposal_decisions d on d.revision_id=r.id where r.project_id=p.id and d.decision='accepted' order by r.number desc limit 1)));
end; $$;

create or replace function public.get_overview_hub(p_organization_id uuid,p_workspace_id uuid default null,p_personal boolean default false)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare projects jsonb;workspaces jsonb;library jsonb;
begin
 if auth.uid() is null or p_personal is null then raise exception 'Authentication required' using errcode='42501';end if;
 if p_workspace_id is not null and not exists(select 1 from public.workspaces w where w.id=p_workspace_id and w.organization_id=p_organization_id and w.status='active') then raise exception 'Workspace does not belong to this organisation' using errcode='42501';end if;
 if not p_personal then
  if not coalesce(case when p_workspace_id is null then public.lign_is_org_admin(p_organization_id) else public.lign_is_workspace_admin(p_workspace_id) end,false) then raise exception 'Leadership access required' using errcode='42501';end if;
 elsif not (public.lign_is_org_member(p_organization_id) or exists(select 1 from public.workspaces w join public.projects p on p.workspace_id=w.id where w.organization_id=p_organization_id and w.status='active' and public.lign_has_capability(p.id,w.id,'project.view'))) then raise exception 'Organisation access required' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'code',p.code,'status',p.status,'workspaceId',w.id,'workspaceName',w.name,'summary',public.get_project_overview(p.id)) order by p.name),'[]'::jsonb) into projects
 from public.projects p join public.workspaces w on w.id=p.workspace_id where w.organization_id=p_organization_id and w.status='active' and p.archived_at is null and p.status<>'archived'
 and (p_workspace_id is null or w.id=p_workspace_id) and public.lign_has_capability(p.id,w.id,'project.view');
 select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,'lead',
  (select string_agg(pr.display_name,', ' order by pr.display_name) from public.workspace_members wm join public.profiles pr on pr.id=wm.user_id where wm.workspace_id=w.id and wm.status='active' and wm.role in ('owner','admin'))
 ) order by w.name),'[]'::jsonb) into workspaces from public.workspaces w where w.organization_id=p_organization_id and w.status='active' and (p_workspace_id is null or w.id=p_workspace_id)
 and (public.lign_is_org_admin(p_organization_id) or public.lign_has_capability(null,w.id,'workspace.view'));
 select coalesce(jsonb_agg(jsonb_build_object('id','library-'||c.id,'kind','library','title','Review library submission · '||c.title,'to','/org/'||p_organization_id||'/library?collection='||c.id,'responsible','Organisation owner or admin','canAct',true,'audience','team','since',coalesce((select max(e.created_at) from public.library_review_events e where e.collection_id=c.id and e.action='submit'),c.created_at),'dueAt',null) order by c.created_at),'[]'::jsonb) into library
 from public.library_collections c where c.organization_id=p_organization_id and c.status='in_review' and c.archived_at is null and public.lign_is_org_admin(p_organization_id) and p_workspace_id is null;
 return jsonb_build_object('organizationId',p_organization_id,'organizationName',(select name from public.organizations where id=p_organization_id),'projects',projects,'workspaces',workspaces,'library',library);
end; $$;

-- Cursor pagination and all existing inbox filters apply across the selected organisation.
create or replace function public.list_organization_notifications(p_organization_id uuid,p_workspace_id uuid default null,p_tab text default 'all',p_filters jsonb default '{}',p_before timestamptz default null,p_before_id uuid default null,p_limit integer default 30)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare result jsonb;begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 50 or p_tab is null or p_tab not in ('all','unread','mentions','assigned','governance','archived') then raise exception 'Invalid inbox options' using errcode='22023';end if;
 if p_workspace_id is not null and not exists(select 1 from public.workspaces w where w.id=p_workspace_id and w.organization_id=p_organization_id and w.status='active') then raise exception 'Workspace scope mismatch' using errcode='42501';end if;
 with visible as materialized (
  select n.* from public.vp_read_notifications n join public.workspaces w on w.id=n.workspace_id
  where w.organization_id=p_organization_id and w.status='active' and n.recipient_profile_id=auth.uid()
   and (p_workspace_id is null or w.id=p_workspace_id) and public.lign_has_capability(null,w.id,'notification.view')
 ), base as (
  select * from visible n where (p_tab='archived' or n.dismissed_at is null)
   and (case when p_tab='archived' then n.archived_at is not null else n.archived_at is null end)
   and (p_tab<>'unread' or n.read_at is null) and (p_tab<>'mentions' or n.category='mentions')
   and (p_tab<>'assigned' or n.category='assigned_to_me') and (p_tab<>'governance' or n.category='governance_state_change')
   and (coalesce(jsonb_array_length(p_filters->'category'),0)=0 or p_filters->'category' ? n.category)
   and (coalesce(jsonb_array_length(p_filters->'priority'),0)=0 or p_filters->'priority' ? n.priority)
   and (coalesce(jsonb_array_length(p_filters->'source'),0)=0 or p_filters->'source' ? split_part(n.event_type,'.',1))
   and (nullif(p_filters->>'dateFrom','') is null or n.created_at>=(p_filters->>'dateFrom')::timestamptz)
   and (nullif(p_filters->>'dateTo','') is null or n.created_at<=(p_filters->>'dateTo')::timestamptz)
 ), page as (select * from base where p_before is null or (created_at,id)<(p_before,p_before_id) order by created_at desc,id desc limit p_limit+1), capped as (select * from page order by created_at desc,id desc limit p_limit)
 select jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(c) order by c.created_at desc,c.id desc),'[]'::jsonb) from capped c),
  'has_more',(select count(*)>p_limit from page),'next_cursor',case when (select count(*)>p_limit from page) then (select jsonb_build_object('created_at',created_at,'id',id) from capped order by created_at,id limit 1) else null end,
  'facets',jsonb_build_object('total_count',(select count(*) from base),'unread_count',(select count(*) from visible where dismissed_at is null and archived_at is null and read_at is null),'by_category','{}'::jsonb,'by_priority','{}'::jsonb)) into result;
 return result;
end; $$;
revoke all on function public.get_project_overview(uuid),public.get_overview_hub(uuid,uuid,boolean),public.list_organization_notifications(uuid,uuid,text,jsonb,timestamptz,uuid,integer) from public,anon,authenticated;
grant execute on function public.get_project_overview(uuid),public.get_overview_hub(uuid,uuid,boolean),public.list_organization_notifications(uuid,uuid,text,jsonb,timestamptz,uuid,integer) to authenticated,service_role;

create or replace function public.mark_organization_notifications_read(p_organization_id uuid,p_workspace_id uuid default null)
returns integer language plpgsql security definer set search_path=''
as $$ declare w record; total integer:=0;begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501';end if;
 for w in select id from public.workspaces where organization_id=p_organization_id and status='active' and (p_workspace_id is null or id=p_workspace_id) and public.lign_has_capability(null,id,'notification.manage') loop
  total:=total+public.mark_all_notifications_read(w.id,null);
 end loop;
 return total;
end; $$;
revoke all on function public.mark_organization_notifications_read(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mark_organization_notifications_read(uuid,uuid) to authenticated,service_role;
