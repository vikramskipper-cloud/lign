-- APP 013 wave 1a — capability vocabulary for People & Access.
--
-- Additive, single-function CREATE OR REPLACE (cheatsheet rule 9). Six new
-- workspace-scoped keys are answered BEFORE the project-scope validation,
-- because they are workspace-level concerns whose callers pass
-- p_project_id = NULL -- the same shape APP 010 used for its notification keys.
--
-- EVERYTHING BELOW THE APP 013 BLOCK IS BYTE-IDENTICAL to the frozen APP 010
-- body; this was produced by programmatic insertion, not retyping, and the
-- unchanged remainder was asserted equal before the file was written.
--
-- These keys answer "may this CLASS of user act". They deliberately cannot
-- express "may they act on this specific row" -- the owner-only and
-- last-owner rules are row-relative and live in the RPC bodies (wave 1b).

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
