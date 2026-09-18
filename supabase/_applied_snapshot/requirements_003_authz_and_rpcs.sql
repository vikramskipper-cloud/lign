create or replace function public.lign_has_capability(
  p_project_id uuid, p_workspace_id uuid, p_capability_key text
) returns boolean
  language plpgsql stable parallel safe security definer set search_path = ''
as $$
declare v_project_ok boolean; v_role text;
begin
  select exists (select 1 from public.projects where id=p_project_id and workspace_id=p_workspace_id) into v_project_ok;
  if not v_project_ok then return false; end if;

  if p_capability_key = any (array[
    'project.view','project.edit','project.manage_access','project.archive',
    'collection.view','collection.archive','asset.view','asset.archive',
    'version.view','review.view','comment.view','annotation.view',
    'change.view','decision.view','approval.view','release.view',
    'file.download','activity.view',
    'requirement.view'
  ]) then
    if public.lign_is_workspace_admin(p_workspace_id) then return true; end if;
  end if;

  v_role := public.lign_project_role(p_project_id);
  if v_role is null then return false; end if;

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
      'requirement.view','requirement.create','requirement.edit','requirement.archive','requirement.assess'
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
      'project.view','collection.view','asset.view','version.view',
      'review.view','review.participate',
      'comment.view','comment.create','comment.edit_own',
      'annotation.view','annotation.create',
      'change.view','change.create','decision.view','approval.view','release.view',
      'file.download','activity.view',
      'requirement.view','requirement.assess'
    ])
    when 'approver' then p_capability_key = any (array[
      'project.view','collection.view','asset.view','version.view',
      'review.view','comment.view','comment.create','comment.edit_own',
      'annotation.view','annotation.create',
      'change.view','change.create','decision.view',
      'approval.view','approval.respond','release.view',
      'file.download','activity.view',
      'requirement.view','requirement.assess'
    ])
    when 'observer' then p_capability_key = any (array[
      'project.view','collection.view','asset.view','version.view',
      'review.view','comment.view','annotation.view',
      'change.view','decision.view','approval.view','release.view',
      'file.download','activity.view',
      'requirement.view'
    ])
    else false
  end;
end $$;

create or replace function public.create_requirement(
  p_project_id uuid, p_workspace_id uuid, p_title text,
  p_description text default null, p_category text default null,
  p_source text default null, p_source_ref text default null,
  p_parent_requirement_id uuid default null, p_status text default 'draft'
) returns table (out_requirement_id uuid, out_code text)
  language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_new_id uuid; v_code text; v_parent_code text; v_n integer;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'create_requirement: authentication required' using errcode='42501'; end if;
  if p_project_id is null or p_workspace_id is null then raise exception 'create_requirement: project_id and workspace_id required' using errcode='22004'; end if;
  if p_title is null or length(trim(p_title))=0 then raise exception 'create_requirement: title required' using errcode='22004'; end if;
  if p_status not in ('draft','active') then raise exception 'create_requirement: initial status must be draft or active (got %)', p_status using errcode='22023'; end if;
  if not public.lign_has_capability(p_project_id, p_workspace_id, 'requirement.create') then
    raise exception 'create_requirement: forbidden (requirement.create)' using errcode='42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('lign_req_code:' || p_project_id::text));

  if p_parent_requirement_id is null then
    select coalesce(count(*), 0) + 1 into v_n from public.requirements
     where project_id = p_project_id and parent_requirement_id is null;
    v_code := 'R-' || lpad(v_n::text, 3, '0');
  else
    select code into v_parent_code from public.requirements
     where id = p_parent_requirement_id and project_id = p_project_id;
    if v_parent_code is null then
      raise exception 'create_requirement: parent % not found in project %', p_parent_requirement_id, p_project_id using errcode='23503';
    end if;
    select coalesce(count(*), 0) + 1 into v_n from public.requirements
     where project_id = p_project_id and parent_requirement_id = p_parent_requirement_id;
    v_code := v_parent_code || '.' || v_n::text;
  end if;

  insert into public.requirements
    (workspace_id, project_id, parent_requirement_id, code, title, description,
     category, source, source_ref, status, created_by_profile_id)
  values (p_workspace_id, p_project_id, p_parent_requirement_id, v_code, p_title, p_description,
          p_category, p_source, p_source_ref, p_status, v_caller)
  returning id into v_new_id;

  return query select v_new_id, v_code;
end $$;

revoke all on function public.create_requirement(uuid, uuid, text, text, text, text, text, uuid, text) from public;
revoke all on function public.create_requirement(uuid, uuid, text, text, text, text, text, uuid, text) from anon;
grant execute on function public.create_requirement(uuid, uuid, text, text, text, text, text, uuid, text) to authenticated, service_role;

create or replace function public.edit_requirement(
  p_requirement_id uuid,
  p_title text default null, p_description text default null,
  p_category text default null, p_source text default null,
  p_source_ref text default null, p_status text default null
) returns table (out_requirement_id uuid, out_updated boolean)
  language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_ws uuid; v_pj uuid; v_cur_status text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'edit_requirement: authentication required' using errcode='42501'; end if;
  if p_requirement_id is null then raise exception 'edit_requirement: requirement_id required' using errcode='22004'; end if;

  select workspace_id, project_id, status into v_ws, v_pj, v_cur_status
    from public.requirements where id = p_requirement_id for update;
  if v_ws is null then raise exception 'edit_requirement: requirement % not found', p_requirement_id using errcode='23503'; end if;

  if not public.lign_has_capability(v_pj, v_ws, 'requirement.edit') then
    raise exception 'edit_requirement: forbidden (requirement.edit)' using errcode='42501';
  end if;
  if v_cur_status in ('superseded','archived') then
    raise exception 'edit_requirement: requirement % is % and cannot be edited', p_requirement_id, v_cur_status using errcode='23514';
  end if;
  if p_status is not null and p_status not in ('draft','active') then
    raise exception 'edit_requirement: status transition to % not allowed here (use archive_requirement or supersede_requirement)', p_status using errcode='22023';
  end if;
  if p_title is not null and length(trim(p_title)) = 0 then
    raise exception 'edit_requirement: title cannot be blank' using errcode='22023';
  end if;

  update public.requirements
     set title       = coalesce(p_title,       title),
         description = coalesce(p_description, description),
         category    = coalesce(p_category,    category),
         source      = coalesce(p_source,      source),
         source_ref  = coalesce(p_source_ref,  source_ref),
         status      = coalesce(p_status,      status)
   where id = p_requirement_id;

  return query select p_requirement_id, true;
end $$;

revoke all on function public.edit_requirement(uuid, text, text, text, text, text, text) from public;
revoke all on function public.edit_requirement(uuid, text, text, text, text, text, text) from anon;
grant execute on function public.edit_requirement(uuid, text, text, text, text, text, text) to authenticated, service_role;

create or replace function public.archive_requirement(p_requirement_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_ws uuid; v_pj uuid; v_status text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'archive_requirement: authentication required' using errcode='42501'; end if;
  select workspace_id, project_id, status into v_ws, v_pj, v_status
    from public.requirements where id = p_requirement_id for update;
  if v_ws is null then raise exception 'archive_requirement: requirement % not found', p_requirement_id using errcode='23503'; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.archive') then
    raise exception 'archive_requirement: forbidden (requirement.archive)' using errcode='42501';
  end if;
  if v_status = 'archived' then return false; end if;
  if v_status = 'superseded' then
    raise exception 'archive_requirement: requirement % is superseded and cannot be archived', p_requirement_id using errcode='23514';
  end if;
  update public.requirements set status='archived', archived_at=now() where id = p_requirement_id;
  return true;
end $$;

revoke all on function public.archive_requirement(uuid) from public;
revoke all on function public.archive_requirement(uuid) from anon;
grant execute on function public.archive_requirement(uuid) to authenticated, service_role;

create or replace function public.supersede_requirement(p_old_requirement_id uuid, p_new_requirement_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid;
        v_old_ws uuid; v_old_pj uuid; v_old_st text;
        v_new_ws uuid; v_new_pj uuid; v_new_st text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'supersede_requirement: authentication required' using errcode='42501'; end if;
  if p_old_requirement_id is null or p_new_requirement_id is null then
    raise exception 'supersede_requirement: both requirement ids required' using errcode='22004'; end if;
  if p_old_requirement_id = p_new_requirement_id then
    raise exception 'supersede_requirement: cannot supersede a requirement with itself' using errcode='23514'; end if;

  select workspace_id, project_id, status into v_old_ws, v_old_pj, v_old_st
    from public.requirements where id = p_old_requirement_id for update;
  if v_old_ws is null then raise exception 'supersede_requirement: requirement % not found', p_old_requirement_id using errcode='23503'; end if;

  select workspace_id, project_id, status into v_new_ws, v_new_pj, v_new_st
    from public.requirements where id = p_new_requirement_id for update;
  if v_new_ws is null then raise exception 'supersede_requirement: replacement % not found', p_new_requirement_id using errcode='23503'; end if;

  if v_old_pj <> v_new_pj then
    raise exception 'supersede_requirement: old and replacement must be in the same project' using errcode='23514';
  end if;
  if not public.lign_has_capability(v_old_pj, v_old_ws, 'requirement.edit') then
    raise exception 'supersede_requirement: forbidden (requirement.edit)' using errcode='42501';
  end if;
  if v_old_st in ('superseded','archived') then
    raise exception 'supersede_requirement: requirement % is % and cannot be superseded', p_old_requirement_id, v_old_st using errcode='23514';
  end if;
  if v_new_st not in ('draft','active') then
    raise exception 'supersede_requirement: replacement % must be draft or active (is %)', p_new_requirement_id, v_new_st using errcode='23514';
  end if;

  update public.requirements
     set status='superseded', superseded_by_requirement_id=p_new_requirement_id
   where id = p_old_requirement_id;
  return true;
end $$;

revoke all on function public.supersede_requirement(uuid, uuid) from public;
revoke all on function public.supersede_requirement(uuid, uuid) from anon;
grant execute on function public.supersede_requirement(uuid, uuid) to authenticated, service_role;

create or replace function public.set_requirement_applicability(
  p_requirement_id uuid, p_design_asset_ids uuid[]
) returns table (out_requirement_id uuid, out_added integer, out_removed integer, out_kept integer)
  language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_ws uuid; v_pj uuid; v_status text; v_parent uuid;
        v_ids uuid[]; v_added integer := 0; v_removed integer := 0; v_kept integer := 0;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'set_requirement_applicability: authentication required' using errcode='42501'; end if;
  if p_requirement_id is null then raise exception 'set_requirement_applicability: requirement_id required' using errcode='22004'; end if;

  select workspace_id, project_id, status, parent_requirement_id
    into v_ws, v_pj, v_status, v_parent
    from public.requirements where id = p_requirement_id for update;
  if v_ws is null then raise exception 'set_requirement_applicability: requirement % not found', p_requirement_id using errcode='23503'; end if;
  if v_parent is not null then
    raise exception 'set_requirement_applicability: applicability is inherited from the parent (%) for sub-requirements; edit the parent instead', v_parent using errcode='23514';
  end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.edit') then
    raise exception 'set_requirement_applicability: forbidden (requirement.edit)' using errcode='42501';
  end if;
  if v_status in ('superseded','archived') then
    raise exception 'set_requirement_applicability: requirement % is % and cannot be edited', p_requirement_id, v_status using errcode='23514';
  end if;

  v_ids := coalesce(p_design_asset_ids, array[]::uuid[]);

  with removed as (
    delete from public.requirement_design_assets
     where requirement_id = p_requirement_id and design_asset_id <> all (v_ids)
    returning 1
  ) select count(*)::int into v_removed from removed;

  select count(*)::int into v_kept
    from public.requirement_design_assets
   where requirement_id = p_requirement_id and design_asset_id = any (v_ids);

  with added as (
    insert into public.requirement_design_assets
      (requirement_id, design_asset_id, workspace_id, project_id)
    select p_requirement_id, x, v_ws, v_pj from unnest(v_ids) as x
     where not exists (
       select 1 from public.requirement_design_assets
        where requirement_id = p_requirement_id and design_asset_id = x
     )
    returning 1
  ) select count(*)::int into v_added from added;

  return query select p_requirement_id, v_added, v_removed, v_kept;
end $$;

revoke all on function public.set_requirement_applicability(uuid, uuid[]) from public;
revoke all on function public.set_requirement_applicability(uuid, uuid[]) from anon;
grant execute on function public.set_requirement_applicability(uuid, uuid[]) to authenticated, service_role;

create or replace function public.assess_version_requirement(
  p_asset_version_id uuid, p_requirement_id uuid, p_status text, p_note text default null
) returns table (out_assessment_id uuid, out_action text)
  language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid;
        v_v_ws uuid; v_v_pj uuid;
        v_r_ws uuid; v_r_pj uuid; v_r_st text;
        v_id uuid; v_action text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'assess_version_requirement: authentication required' using errcode='42501'; end if;
  if p_asset_version_id is null or p_requirement_id is null then
    raise exception 'assess_version_requirement: asset_version_id and requirement_id required' using errcode='22004';
  end if;
  if p_status not in ('satisfied','partial','not_satisfied','not_applicable') then
    raise exception 'assess_version_requirement: invalid status %', p_status using errcode='22023';
  end if;

  select workspace_id, project_id into v_v_ws, v_v_pj
    from public.asset_versions where id = p_asset_version_id;
  if v_v_ws is null then raise exception 'assess_version_requirement: asset_version % not found', p_asset_version_id using errcode='23503'; end if;

  select workspace_id, project_id, status into v_r_ws, v_r_pj, v_r_st
    from public.requirements where id = p_requirement_id;
  if v_r_ws is null then raise exception 'assess_version_requirement: requirement % not found', p_requirement_id using errcode='23503'; end if;

  if v_v_ws <> v_r_ws or v_v_pj <> v_r_pj then
    raise exception 'assess_version_requirement: version and requirement are not in the same project' using errcode='23514';
  end if;
  if v_r_st = 'archived' then
    raise exception 'assess_version_requirement: requirement % is archived; cannot record a new assessment', p_requirement_id using errcode='23514';
  end if;
  if not public.lign_has_capability(v_r_pj, v_r_ws, 'requirement.assess') then
    raise exception 'assess_version_requirement: forbidden (requirement.assess)' using errcode='42501';
  end if;

  insert into public.version_requirement_assessments
    (workspace_id, project_id, asset_version_id, requirement_id, status, note,
     assessed_by_profile_id, assessed_at)
  values (v_r_ws, v_r_pj, p_asset_version_id, p_requirement_id, p_status, p_note,
          v_caller, now())
  on conflict (asset_version_id, requirement_id) do update
    set status = excluded.status,
        note   = excluded.note,
        assessed_by_profile_id = excluded.assessed_by_profile_id,
        assessed_at = excluded.assessed_at
  returning id, case when xmax::text::int > 0 then 'updated' else 'created' end
    into v_id, v_action;

  return query select v_id, v_action;
end $$;

revoke all on function public.assess_version_requirement(uuid, uuid, text, text) from public;
revoke all on function public.assess_version_requirement(uuid, uuid, text, text) from anon;
grant execute on function public.assess_version_requirement(uuid, uuid, text, text) to authenticated, service_role;
