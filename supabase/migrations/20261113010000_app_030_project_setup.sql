-- APP 030: project client details, race-safe codes and agreed-brief design gate.
-- Client contact records do not create accounts, invitations or access.
alter table public.projects
 add column client_company text,
 add column client_contact_name text,
 add column client_email text,
 add column client_phone text;

create or replace function public.normalize_project_setup()
returns trigger language plpgsql set search_path=''
as $$
begin
 new.code:=nullif(upper(trim(new.code)),'');
 if new.code is not null and new.code !~ '^[A-Z0-9][A-Z0-9-]{0,15}$' then
  raise exception 'Use up to 16 letters, digits or dashes for the project code' using errcode='22023'; end if;
 new.client_company:=nullif(trim(new.client_company),'');
 new.client_contact_name:=nullif(trim(new.client_contact_name),'');
 new.client_email:=nullif(lower(trim(new.client_email)),'');
 new.client_phone:=nullif(trim(new.client_phone),'');
 if length(new.client_company)>200 or length(new.client_contact_name)>200 or length(new.client_email)>254 or length(new.client_phone)>40
 or coalesce(new.client_company,'') ~ '[[:cntrl:]]' or coalesce(new.client_contact_name,'') ~ '[[:cntrl:]]'
 or coalesce(new.client_email,'') ~ '[[:cntrl:]]' or coalesce(new.client_phone,'') ~ '[[:cntrl:]]'
 or (new.client_email is not null and new.client_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$') then
  raise exception 'Check the client contact details and field lengths' using errcode='22023'; end if;
 return new;
end; $$;
create trigger projects_normalize_setup before insert or update on public.projects
 for each row execute function public.normalize_project_setup();
revoke all on function public.normalize_project_setup() from public,anon,authenticated;

-- Fail safely on legacy collisions; never rename another user's project code.
create unique index projects_workspace_code_active_key on public.projects(workspace_id,upper(trim(code)))
 where archived_at is null and nullif(trim(code),'') is not null;

create or replace function public.create_project_with_client(
 p_workspace_id uuid,p_name text,p_code text default null,p_description text default null,
 p_lead_member_id uuid default null,p_client_emails text[] default '{}'::text[],
 p_client_company text default null,p_client_contact_name text default null,
 p_client_email text default null,p_client_phone text default null)
returns table(out_project_id uuid,out_slug text,out_code text,out_invites jsonb)
language plpgsql security definer set search_path=''
as $$
declare v record;
begin
 if not public.lign_has_capability(null,p_workspace_id,'workspace.manage') then
  raise exception 'Workspace administration required' using errcode='42501'; end if;
 -- Serialise this path per workspace, including generated slug allocation.
 perform pg_advisory_xact_lock(hashtextextended(p_workspace_id::text,30));
 select * into v from public.create_project_full(p_workspace_id,p_name,p_code,p_description,p_lead_member_id,p_client_emails);
 update public.projects set client_company=p_client_company,client_contact_name=p_client_contact_name,
  client_email=p_client_email,client_phone=p_client_phone where id=v.out_project_id;
 return query select v.out_project_id,v.out_slug,v.out_code,v.out_invites;
end; $$;

create or replace function public.update_project_details(
 p_project_id uuid,p_name text,p_code text,p_description text,
 p_client_company text,p_client_contact_name text,p_client_email text,p_client_phone text)
returns void language plpgsql security definer set search_path=''
as $$
declare v public.projects%rowtype;
begin
 select * into v from public.projects where id=p_project_id for update;
 if v.id is null or not public.lign_has_capability(v.id,v.workspace_id,'project.edit') then
  raise exception 'Project editing access required' using errcode='42501'; end if;
 if length(trim(coalesce(p_name,''))) not between 1 and 120 or length(coalesce(p_description,''))>280 then
  raise exception 'Check the project name and description lengths' using errcode='22023'; end if;
 update public.projects set name=trim(p_name),code=p_code,description=nullif(trim(p_description),''),
  client_company=p_client_company,client_contact_name=p_client_contact_name,client_email=p_client_email,client_phone=p_client_phone where id=v.id;
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload)
 values(v.workspace_id,v.id,'project.updated',auth.uid(),'user','project',v.id,trim(p_name),'{}'::jsonb);
end; $$;

-- An immutable agreement decision unlocks design work. A later working brief
-- revision does not erase that baseline or freeze ongoing work.
create index project_brief_decisions_project_decision_idx on public.project_brief_decisions(project_id,decision);
create or replace function public.lign_project_ready_for_design(p_project_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.project_brief_decisions d
 join public.project_brief_revisions r on r.id=d.revision_id and r.project_id=d.project_id
 where d.project_id=p_project_id and d.decision='agreed'); $$;

create or replace function public.guard_project_design_start()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if not public.lign_project_ready_for_design(new.project_id) then
  raise exception 'Agree the project brief before starting design work' using errcode='23514'; end if;
 return new;
end; $$;
create trigger design_assets_brief_gate before insert or update on public.design_assets for each row execute function public.guard_project_design_start();
create trigger asset_versions_brief_gate before insert or update on public.asset_versions for each row execute function public.guard_project_design_start();
create trigger reviews_brief_gate before insert or update on public.reviews for each row execute function public.guard_project_design_start();
create trigger approval_requests_brief_gate before insert or update on public.approval_requests for each row execute function public.guard_project_design_start();
create trigger releases_brief_gate before insert or update on public.releases for each row execute function public.guard_project_design_start();
create trigger deliverable_submissions_brief_gate before insert or update on public.deliverable_submissions for each row execute function public.guard_project_design_start();
revoke all on function public.guard_project_design_start() from public,anon,authenticated;
revoke all on function public.create_project_with_client(uuid,text,text,text,uuid,text[],text,text,text,text),public.update_project_details(uuid,text,text,text,text,text,text,text),public.lign_project_ready_for_design(uuid) from public,anon,authenticated;
grant execute on function public.create_project_with_client(uuid,text,text,text,uuid,text[],text,text,text,text),public.update_project_details(uuid,text,text,text,text,text,text,text),public.lign_project_ready_for_design(uuid) to authenticated,service_role;

create or replace function public.lign_has_capability(
  p_project_id uuid,
  p_workspace_id uuid,
  p_capability_key text
)
returns boolean
language plpgsql
stable parallel safe security definer
set search_path = ''
as $$
declare
  v_project_ok boolean;
  v_role       text;
begin
  -- APP 010: notification.view + notification.manage are PERSONAL capabilities
  -- granted to every authenticated user regardless of project scope. Recipient
  -- enforcement lives in the RPC/RLS layer via recipient_profile_id = auth.uid().
  -- Answer these keys BEFORE the project-scope validation so that workspace-scoped
  -- notification reads (which pass project_id = NULL) resolve true.
  if p_capability_key in ('notification.view', 'notification.manage') then
    return auth.uid() is not null;
  end if;

  -- APP 010: 6 RESERVED capability keys — name-only registration; zero grants in v1.
  if p_capability_key in (
    'notification.view_any',
    'notification.announce',
    'notification.ai_prioritize',
    'notification.ai_summarize',
    'notification.ai_digest',
    'notification.preference'
  ) then
    return false;
  end if;

  -- ---------------------------------------------------------------------
  -- APP 013: workspace-scoped access capabilities.
  --
  -- Answered BEFORE the project-scope validation below, because these are
  -- workspace-level concerns and their callers pass p_project_id = NULL.
  -- Same shape as APP 010's notification keys for the same reason.
  --
  -- lign_is_workspace_admin covers role in ('owner','admin') with an active
  -- membership. Owner-only restrictions (granting or revoking the owner role,
  -- removing the last owner) are NOT expressible here -- a capability answers
  -- "may this class of user act", not "may they act on this specific row".
  -- Those invariants live in the RPC bodies.
  -- ---------------------------------------------------------------------
  if p_capability_key in (
    'member.invite',
    'member.remove',
    'member.change_role',
    'stakeholder.invite',
    'stakeholder.revoke',
    'workspace.manage'
  ) then
    return public.lign_is_workspace_admin(p_workspace_id);
  end if;

  -- ---------------------------------------------------------------------
  -- Below is byte-identical to the frozen APP 009 lign_has_capability body
  -- (20260814180000_app_009_releases_authz_and_rpcs.sql L39–161).
  -- ---------------------------------------------------------------------

  select exists (
    select 1
      from public.projects
     where id = p_project_id
       and workspace_id = p_workspace_id
  ) into v_project_ok;

  if not v_project_ok then
    return false;
  end if;

  -- Reads, people, requirements and brief collaboration remain available.
  if p_capability_key = any(array[
    'collection.create','collection.edit','collection.archive',
    'asset.create','asset.edit','asset.archive','asset.set_current',
    'version.upload','version.publish','version.discard_draft',
    'file.upload','file.attach','review.create','review.participate','review.complete','review.coordinate','review.reopen',
    'approval.request','approval.respond','approval.cancel','approval.veto','approval.expire','approval.supersede',
    'release.create','release.finalize','release.withdraw','requirement.assess'
  ]) and not public.lign_project_ready_for_design(p_project_id) then return false; end if;

  if p_capability_key = any (array[
    'project.view','project.edit','project.manage_access','project.archive',
    'collection.view','collection.archive',
    'asset.view','asset.archive',
    'version.view','review.view','comment.view','annotation.view',
    'change.view','decision.view','approval.view','release.view',
    'file.download','activity.view',
    'requirement.view'
  ]) then
    if public.lign_is_workspace_admin(p_workspace_id) then
      return true;
    end if;
  end if;

  v_role := public.lign_project_role(p_project_id);
  if v_role is null then
    return false;
  end if;

  return case v_role
    when 'lead' then p_capability_key = any (array[
      'project.view','project.edit','project.manage_access','project.archive',
      'collection.view','collection.create','collection.edit','collection.archive',
      'asset.view','asset.create','asset.edit','asset.archive','asset.set_current',
      'version.view','version.upload','version.publish','version.discard_draft',
      'review.view','review.create','review.complete',
      'comment.view','comment.create','comment.edit_own','comment.resolve',
      'annotation.view','annotation.create','annotation.resolve',
      'change.view','change.create','change.resolve',
      'decision.view','decision.create',
      'approval.view','approval.request','approval.cancel',
      'release.view','release.create','release.finalize','release.withdraw',
      'file.upload','file.attach','file.download','file.remove_orphaned',
      'activity.view',
      'requirement.view','requirement.create','requirement.edit',
      'requirement.archive','requirement.assess'
    ])
    when 'contributor' then p_capability_key = any (array[
      'project.view',
      'collection.view','collection.create','collection.edit','collection.archive',
      'asset.view','asset.create','asset.edit','asset.archive','asset.set_current',
      'version.view','version.upload','version.publish','version.discard_draft',
      'review.view','review.create','review.complete',
      'comment.view','comment.create','comment.edit_own','comment.resolve',
      'annotation.view','annotation.create','annotation.resolve',
      'change.view','change.create','change.resolve',
      'decision.view','decision.create',
      'approval.view','approval.request','approval.cancel',
      'release.view','release.create',
      'file.upload','file.attach','file.download',
      'activity.view',
      'requirement.view','requirement.create','requirement.edit','requirement.assess'
    ])
    when 'reviewer' then p_capability_key = any (array[
      'project.view',
      'collection.view','asset.view','version.view',
      'review.view','review.participate',
      'comment.view','comment.create','comment.edit_own',
      'annotation.view','annotation.create',
      'change.view','change.create',
      'decision.view',
      'approval.view',
      'release.view',
      'file.download',
      'activity.view',
      'requirement.view','requirement.assess'
    ])
    when 'approver' then p_capability_key = any (array[
      'project.view',
      'collection.view','asset.view','version.view',
      'review.view',
      'comment.view','comment.create','comment.edit_own',
      'annotation.view','annotation.create',
      'change.view','change.create',
      'decision.view',
      'approval.view','approval.respond',
      'release.view',
      'file.download',
      'activity.view',
      'requirement.view','requirement.assess'
    ])
    when 'observer' then p_capability_key = any (array[
      'project.view',
      'collection.view','asset.view','version.view',
      'review.view','comment.view','annotation.view',
      'change.view','decision.view','approval.view','release.view',
      'file.download','activity.view',
      'requirement.view'
    ])
    else false
  end;
end $$;

create or replace function public.lign_can_submit_deliverables(p_project_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.project_participants pp
 join public.projects p on p.id=pp.project_id
 left join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
 left join public.stakeholders s on s.id=pp.stakeholder_id and s.status='active'
 where pp.project_id=p_project_id and pp.role='reviewer' and pp.status='active' and pp.can_submit_deliverables
 and public.lign_project_ready_for_design(p_project_id)
 and coalesce(wm.user_id,s.user_id)=auth.uid() and p.archived_at is null and p.status<>'archived'); $$;
