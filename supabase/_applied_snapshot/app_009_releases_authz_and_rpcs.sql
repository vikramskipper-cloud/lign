-- APP 009 Migration B — Part 1: lign_has_capability + read RPCs 1-4
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

comment on function public.lign_has_capability(uuid, uuid, text) is
  'AUTH capability primer. APP 008 reserves requirement.ai_suggest/ai_classify/import/auto_assess by name only (no role grants). APP 009 reserves release.schedule/supersede/ai_suggest/ai_classify/audit_export/recall by name only (no role grants).';
