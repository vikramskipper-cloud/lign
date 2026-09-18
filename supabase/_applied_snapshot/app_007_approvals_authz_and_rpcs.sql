
-- APP 007 (Approvals) — Authorization + RPCs
--
-- Implements the frozen APP 007 backend surface:
--   1. Extends lign_has_capability with approval.veto + approval.expire +
--      approval.supersede (default: lead only for veto/expire; lead+
--      contributor for supersede).
--   2. Write RPCs:
--      - create_approval_draft (F-7.1 chain-init discipline)
--      - send_approval_request
--      - respond_to_approval extended (Option A additive tail; rejects
--        changes_requested at input per F-2.1)
--      - supersede_approval_request (F-1.1 + F-7.1 + F-10.1 disciplines)
--      - cancel_approval extended (mandatory cancellation reason)
--      - expire_approval
--      - add_approver, remove_approver, reassign_approver,
--        set_approver_required, set_approver_veto_power
--   3. Read RPCs:
--      - list_approvals_dashboard, get_approval, get_approval_chain,
--        list_approvals_for_version, get_approval_readiness,
--        get_approval_inbox_count, get_project_approval_metrics,
--        get_workspace_approval_metrics
--   4. set_updated_at trigger on approval_request_approvers (F-7.3)
--
-- All SECURITY DEFINER RPCs use search_path='', REVOKE from public/anon/
-- authenticated, GRANT to authenticated + service_role.

------------------------------------------------------------------------------
-- 1. Extend lign_has_capability with approval.veto + expire + supersede
------------------------------------------------------------------------------

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
  select exists (
    select 1 from public.projects
     where id = p_project_id and workspace_id = p_workspace_id
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

  -- Workspace admin overrides for cancel + expire (§11.3 note)
  if p_capability_key in ('approval.cancel','approval.expire') then
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
      'review.view','review.create','review.coordinate','review.complete','review.reopen',
      'comment.view','comment.create','comment.edit_own','comment.resolve',
      'annotation.view','annotation.create','annotation.resolve',
      'change.view','change.create','change.resolve',
      'decision.view','decision.create',
      'approval.view','approval.request','approval.cancel',
      'approval.veto','approval.expire','approval.supersede',
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
      'review.view','review.create','review.complete','review.reopen',
      'comment.view','comment.create','comment.edit_own','comment.resolve',
      'annotation.view','annotation.create','annotation.resolve',
      'change.view','change.create','change.resolve',
      'decision.view','decision.create',
      'approval.view','approval.request','approval.cancel',
      'approval.supersede',
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
      'review.view','review.participate',
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

------------------------------------------------------------------------------
-- 2. set_updated_at trigger on approval_request_approvers (F-7.3)
------------------------------------------------------------------------------

drop trigger if exists approval_request_approvers_set_updated_at on public.approval_request_approvers;
create trigger approval_request_approvers_set_updated_at
  before update on public.approval_request_approvers
  for each row execute function public.set_updated_at();
