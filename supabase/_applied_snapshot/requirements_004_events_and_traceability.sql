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
    select coalesce(count(*), 0) + 1 into v_n from public.requirements where project_id = p_project_id and parent_requirement_id is null;
    v_code := 'R-' || lpad(v_n::text, 3, '0');
  else
    select code into v_parent_code from public.requirements where id = p_parent_requirement_id and project_id = p_project_id;
    if v_parent_code is null then raise exception 'create_requirement: parent % not found in project %', p_parent_requirement_id, p_project_id using errcode='23503'; end if;
    select coalesce(count(*), 0) + 1 into v_n from public.requirements where project_id = p_project_id and parent_requirement_id = p_parent_requirement_id;
    v_code := v_parent_code || '.' || v_n::text;
  end if;
  insert into public.requirements (workspace_id, project_id, parent_requirement_id, code, title, description, category, source, source_ref, status, created_by_profile_id)
  values (p_workspace_id, p_project_id, p_parent_requirement_id, v_code, p_title, p_description, p_category, p_source, p_source_ref, p_status, v_caller)
  returning id into v_new_id;
  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (p_workspace_id, p_project_id, now(), 'requirement.created', v_caller, 'user', 'requirement', v_new_id, v_code,
          jsonb_build_object('code', v_code, 'title', p_title, 'parent_requirement_id', p_parent_requirement_id, 'initial_status', p_status), '{}'::jsonb);
  return query select v_new_id, v_code;
end $$;
revoke all on function public.create_requirement(uuid, uuid, text, text, text, text, text, uuid, text) from public;
revoke all on function public.create_requirement(uuid, uuid, text, text, text, text, text, uuid, text) from anon;
grant execute on function public.create_requirement(uuid, uuid, text, text, text, text, text, uuid, text) to authenticated, service_role;

create or replace function public.edit_requirement(
  p_requirement_id uuid, p_title text default null, p_description text default null,
  p_category text default null, p_source text default null, p_source_ref text default null, p_status text default null
) returns table (out_requirement_id uuid, out_updated boolean)
language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_ws uuid; v_pj uuid; v_code text; v_cur_status text;
        v_cur_title text; v_cur_desc text; v_cur_cat text; v_cur_src text; v_cur_ref text;
        v_changed text[] := array[]::text[];
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'edit_requirement: authentication required' using errcode='42501'; end if;
  if p_requirement_id is null then raise exception 'edit_requirement: requirement_id required' using errcode='22004'; end if;
  select workspace_id, project_id, code, status, title, description, category, source, source_ref
    into v_ws, v_pj, v_code, v_cur_status, v_cur_title, v_cur_desc, v_cur_cat, v_cur_src, v_cur_ref
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
  if p_title       is not null and p_title       is distinct from v_cur_title  then v_changed := v_changed || 'title';       end if;
  if p_description is not null and p_description is distinct from v_cur_desc   then v_changed := v_changed || 'description'; end if;
  if p_category    is not null and p_category    is distinct from v_cur_cat    then v_changed := v_changed || 'category';    end if;
  if p_source      is not null and p_source      is distinct from v_cur_src    then v_changed := v_changed || 'source';      end if;
  if p_source_ref  is not null and p_source_ref  is distinct from v_cur_ref    then v_changed := v_changed || 'source_ref';  end if;
  if p_status      is not null and p_status      is distinct from v_cur_status then v_changed := v_changed || 'status';      end if;
  if array_length(v_changed, 1) is null then
    return query select p_requirement_id, false; return;
  end if;
  update public.requirements
     set title=coalesce(p_title,title), description=coalesce(p_description,description),
         category=coalesce(p_category,category), source=coalesce(p_source,source),
         source_ref=coalesce(p_source_ref,source_ref), status=coalesce(p_status,status)
   where id = p_requirement_id;
  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_ws, v_pj, now(), 'requirement.updated', v_caller, 'user', 'requirement', p_requirement_id, v_code,
          jsonb_build_object('code', v_code, 'kind', 'edit', 'changed_fields', to_jsonb(v_changed),
                             'previous_status', case when 'status' = any(v_changed) then v_cur_status else null end,
                             'new_status', case when 'status' = any(v_changed) then p_status else null end),
          '{}'::jsonb);
  return query select p_requirement_id, true;
end $$;
revoke all on function public.edit_requirement(uuid, text, text, text, text, text, text) from public;
revoke all on function public.edit_requirement(uuid, text, text, text, text, text, text) from anon;
grant execute on function public.edit_requirement(uuid, text, text, text, text, text, text) to authenticated, service_role;

create or replace function public.archive_requirement(p_requirement_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_ws uuid; v_pj uuid; v_status text; v_code text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'archive_requirement: authentication required' using errcode='42501'; end if;
  select workspace_id, project_id, status, code into v_ws, v_pj, v_status, v_code
    from public.requirements where id = p_requirement_id for update;
  if v_ws is null then raise exception 'archive_requirement: requirement % not found', p_requirement_id using errcode='23503'; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.archive') then
    raise exception 'archive_requirement: forbidden (requirement.archive)' using errcode='42501';
  end if;
  if v_status = 'archived' then return false; end if;
  if v_status = 'superseded' then raise exception 'archive_requirement: requirement % is superseded and cannot be archived', p_requirement_id using errcode='23514'; end if;
  update public.requirements set status='archived', archived_at=now() where id = p_requirement_id;
  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_ws, v_pj, now(), 'requirement.archived', v_caller, 'user', 'requirement', p_requirement_id, v_code,
          jsonb_build_object('code', v_code, 'previous_status', v_status), '{}'::jsonb);
  return true;
end $$;
revoke all on function public.archive_requirement(uuid) from public;
revoke all on function public.archive_requirement(uuid) from anon;
grant execute on function public.archive_requirement(uuid) to authenticated, service_role;

create or replace function public.supersede_requirement(p_old_requirement_id uuid, p_new_requirement_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid;
        v_old_ws uuid; v_old_pj uuid; v_old_st text; v_old_code text;
        v_new_ws uuid; v_new_pj uuid; v_new_st text; v_new_code text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'supersede_requirement: authentication required' using errcode='42501'; end if;
  if p_old_requirement_id is null or p_new_requirement_id is null then raise exception 'supersede_requirement: both requirement ids required' using errcode='22004'; end if;
  if p_old_requirement_id = p_new_requirement_id then raise exception 'supersede_requirement: cannot supersede a requirement with itself' using errcode='23514'; end if;
  select workspace_id, project_id, status, code into v_old_ws, v_old_pj, v_old_st, v_old_code
    from public.requirements where id = p_old_requirement_id for update;
  if v_old_ws is null then raise exception 'supersede_requirement: requirement % not found', p_old_requirement_id using errcode='23503'; end if;
  select workspace_id, project_id, status, code into v_new_ws, v_new_pj, v_new_st, v_new_code
    from public.requirements where id = p_new_requirement_id for update;
  if v_new_ws is null then raise exception 'supersede_requirement: replacement % not found', p_new_requirement_id using errcode='23503'; end if;
  if v_old_pj <> v_new_pj then raise exception 'supersede_requirement: old and replacement must be in the same project' using errcode='23514'; end if;
  if not public.lign_has_capability(v_old_pj, v_old_ws, 'requirement.edit') then
    raise exception 'supersede_requirement: forbidden (requirement.edit)' using errcode='42501';
  end if;
  if v_old_st in ('superseded','archived') then
    raise exception 'supersede_requirement: requirement % is % and cannot be superseded', p_old_requirement_id, v_old_st using errcode='23514';
  end if;
  if v_new_st not in ('draft','active') then
    raise exception 'supersede_requirement: replacement % must be draft or active (is %)', p_new_requirement_id, v_new_st using errcode='23514';
  end if;
  update public.requirements set status='superseded', superseded_by_requirement_id=p_new_requirement_id where id = p_old_requirement_id;
  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_old_ws, v_old_pj, now(), 'requirement.updated', v_caller, 'user', 'requirement', p_old_requirement_id, v_old_code,
          jsonb_build_object('code', v_old_code, 'kind', 'supersede', 'previous_status', v_old_st, 'new_status', 'superseded',
                             'superseded_by_requirement_id', p_new_requirement_id, 'superseded_by_code', v_new_code),
          '{}'::jsonb);
  return true;
end $$;
revoke all on function public.supersede_requirement(uuid, uuid) from public;
revoke all on function public.supersede_requirement(uuid, uuid) from anon;
grant execute on function public.supersede_requirement(uuid, uuid) to authenticated, service_role;

create or replace function public.set_requirement_applicability(p_requirement_id uuid, p_design_asset_ids uuid[])
returns table (out_requirement_id uuid, out_added integer, out_removed integer, out_kept integer)
language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_ws uuid; v_pj uuid; v_status text; v_parent uuid; v_code text;
        v_ids uuid[]; v_added integer := 0; v_removed integer := 0; v_kept integer := 0;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'set_requirement_applicability: authentication required' using errcode='42501'; end if;
  if p_requirement_id is null then raise exception 'set_requirement_applicability: requirement_id required' using errcode='22004'; end if;
  select workspace_id, project_id, status, parent_requirement_id, code
    into v_ws, v_pj, v_status, v_parent, v_code
    from public.requirements where id = p_requirement_id for update;
  if v_ws is null then raise exception 'set_requirement_applicability: requirement % not found', p_requirement_id using errcode='23503'; end if;
  if v_parent is not null then raise exception 'set_requirement_applicability: applicability is inherited from the parent (%) for sub-requirements; edit the parent instead', v_parent using errcode='23514'; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.edit') then
    raise exception 'set_requirement_applicability: forbidden (requirement.edit)' using errcode='42501';
  end if;
  if v_status in ('superseded','archived') then
    raise exception 'set_requirement_applicability: requirement % is % and cannot be edited', p_requirement_id, v_status using errcode='23514';
  end if;
  v_ids := coalesce(p_design_asset_ids, array[]::uuid[]);
  with removed as (
    delete from public.requirement_design_assets where requirement_id = p_requirement_id and design_asset_id <> all (v_ids) returning 1
  ) select count(*)::int into v_removed from removed;
  select count(*)::int into v_kept from public.requirement_design_assets where requirement_id = p_requirement_id and design_asset_id = any (v_ids);
  with added as (
    insert into public.requirement_design_assets (requirement_id, design_asset_id, workspace_id, project_id)
    select p_requirement_id, x, v_ws, v_pj from unnest(v_ids) as x
     where not exists (select 1 from public.requirement_design_assets where requirement_id = p_requirement_id and design_asset_id = x)
    returning 1
  ) select count(*)::int into v_added from added;
  if v_added > 0 or v_removed > 0 then
    insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
    values (v_ws, v_pj, now(), 'requirement.updated', v_caller, 'user', 'requirement', p_requirement_id, v_code,
            jsonb_build_object('code', v_code, 'kind', 'applicability', 'added', v_added, 'removed', v_removed, 'kept', v_kept, 'now_project_wide', (v_added + v_kept = 0)),
            '{}'::jsonb);
  end if;
  return query select p_requirement_id, v_added, v_removed, v_kept;
end $$;
revoke all on function public.set_requirement_applicability(uuid, uuid[]) from public;
revoke all on function public.set_requirement_applicability(uuid, uuid[]) from anon;
grant execute on function public.set_requirement_applicability(uuid, uuid[]) to authenticated, service_role;

create or replace function public.assess_version_requirement(p_asset_version_id uuid, p_requirement_id uuid, p_status text, p_note text default null)
returns table (out_assessment_id uuid, out_action text)
language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_v_ws uuid; v_v_pj uuid; v_r_ws uuid; v_r_pj uuid; v_r_st text; v_r_code text;
        v_prev_status text; v_id uuid; v_action text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'assess_version_requirement: authentication required' using errcode='42501'; end if;
  if p_asset_version_id is null or p_requirement_id is null then raise exception 'assess_version_requirement: asset_version_id and requirement_id required' using errcode='22004'; end if;
  if p_status not in ('satisfied','partial','not_satisfied','not_applicable') then raise exception 'assess_version_requirement: invalid status %', p_status using errcode='22023'; end if;
  select workspace_id, project_id into v_v_ws, v_v_pj from public.asset_versions where id = p_asset_version_id;
  if v_v_ws is null then raise exception 'assess_version_requirement: asset_version % not found', p_asset_version_id using errcode='23503'; end if;
  select workspace_id, project_id, status, code into v_r_ws, v_r_pj, v_r_st, v_r_code from public.requirements where id = p_requirement_id;
  if v_r_ws is null then raise exception 'assess_version_requirement: requirement % not found', p_requirement_id using errcode='23503'; end if;
  if v_v_ws <> v_r_ws or v_v_pj <> v_r_pj then raise exception 'assess_version_requirement: version and requirement are not in the same project' using errcode='23514'; end if;
  if v_r_st = 'archived' then raise exception 'assess_version_requirement: requirement % is archived; cannot record a new assessment', p_requirement_id using errcode='23514'; end if;
  if not public.lign_has_capability(v_r_pj, v_r_ws, 'requirement.assess') then raise exception 'assess_version_requirement: forbidden (requirement.assess)' using errcode='42501'; end if;
  select status into v_prev_status from public.version_requirement_assessments where asset_version_id = p_asset_version_id and requirement_id = p_requirement_id;
  insert into public.version_requirement_assessments (workspace_id, project_id, asset_version_id, requirement_id, status, note, assessed_by_profile_id, assessed_at)
  values (v_r_ws, v_r_pj, p_asset_version_id, p_requirement_id, p_status, p_note, v_caller, now())
  on conflict (asset_version_id, requirement_id) do update
    set status = excluded.status, note = excluded.note, assessed_by_profile_id = excluded.assessed_by_profile_id, assessed_at = excluded.assessed_at
  returning id, case when xmax::text::int > 0 then 'updated' else 'created' end into v_id, v_action;
  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_r_ws, v_r_pj, now(), 'requirement.assessed', v_caller, 'user', 'version_requirement_assessment', v_id, v_r_code,
          jsonb_build_object('code', v_r_code, 'requirement_id', p_requirement_id, 'asset_version_id', p_asset_version_id, 'status', p_status, 'previous_status', v_prev_status, 'action', v_action),
          '{}'::jsonb);
  return query select v_id, v_action;
end $$;
revoke all on function public.assess_version_requirement(uuid, uuid, text, text) from public;
revoke all on function public.assess_version_requirement(uuid, uuid, text, text) from anon;
grant execute on function public.assess_version_requirement(uuid, uuid, text, text) to authenticated, service_role;

create or replace function public.list_project_requirements(
  p_project_id uuid, p_workspace_id uuid,
  p_include_archived boolean default false, p_include_superseded boolean default true
) returns table (out_requirement_id uuid, out_code text, out_title text, out_description text, out_category text,
                 out_source text, out_source_ref text, out_status text, out_parent_requirement_id uuid,
                 out_superseded_by_requirement_id uuid, out_archived_at timestamptz,
                 out_created_by_profile_id uuid, out_created_at timestamptz, out_updated_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'list_project_requirements: authentication required' using errcode='42501'; end if;
  if not public.lign_has_capability(p_project_id, p_workspace_id, 'requirement.view') then
    raise exception 'list_project_requirements: forbidden (requirement.view)' using errcode='42501';
  end if;
  return query
    select r.id, r.code, r.title, r.description, r.category, r.source, r.source_ref,
           r.status, r.parent_requirement_id, r.superseded_by_requirement_id, r.archived_at,
           r.created_by_profile_id, r.created_at, r.updated_at
      from public.requirements r
     where r.project_id = p_project_id and r.workspace_id = p_workspace_id
       and (p_include_archived   or r.status <> 'archived')
       and (p_include_superseded or r.status <> 'superseded')
     order by coalesce((select code from public.requirements p where p.id = r.parent_requirement_id), r.code),
              r.parent_requirement_id nulls first, r.code;
end $$;
revoke all on function public.list_project_requirements(uuid, uuid, boolean, boolean) from public;
revoke all on function public.list_project_requirements(uuid, uuid, boolean, boolean) from anon;
grant execute on function public.list_project_requirements(uuid, uuid, boolean, boolean) to authenticated, service_role;

create or replace function public.list_applicable_requirements(p_design_asset_id uuid, p_asset_version_id uuid default null)
returns table (out_requirement_id uuid, out_code text, out_title text, out_status text, out_parent_requirement_id uuid,
               out_is_project_wide boolean, out_assessment_status text, out_assessed_at timestamptz, out_assessed_by_profile_id uuid)
language plpgsql stable security definer set search_path = ''
as $$
declare v_ws uuid; v_pj uuid;
begin
  if auth.uid() is null then raise exception 'list_applicable_requirements: authentication required' using errcode='42501'; end if;
  select workspace_id, project_id into v_ws, v_pj from public.design_assets where id = p_design_asset_id;
  if v_ws is null then raise exception 'list_applicable_requirements: design_asset % not found', p_design_asset_id using errcode='23503'; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.view') then
    raise exception 'list_applicable_requirements: forbidden (requirement.view)' using errcode='42501';
  end if;
  if p_asset_version_id is not null then
    perform 1 from public.asset_versions where id = p_asset_version_id and design_asset_id = p_design_asset_id;
    if not found then
      raise exception 'list_applicable_requirements: asset_version % is not part of design_asset %', p_asset_version_id, p_design_asset_id using errcode='23514';
    end if;
  end if;
  return query
    with root_scoped as (
      select r.id, r.code, r.title, r.status, r.parent_requirement_id, coalesce(r.parent_requirement_id, r.id) as effective_root_id
        from public.requirements r where r.project_id = v_pj and r.status in ('draft','active')
    ),
    scoped_root_ids as (
      select distinct requirement_id as root_id from public.requirement_design_assets where design_asset_id = p_design_asset_id
    ),
    all_project_roots as (
      select id from public.requirements where project_id = v_pj and parent_requirement_id is null and status in ('draft','active')
    ),
    root_wide as (
      select id from all_project_roots where id not in (
        select distinct requirement_id from public.requirement_design_assets where requirement_id in (select id from all_project_roots)
      )
    ),
    applicable_root_ids as (
      select id from root_wide union select root_id as id from scoped_root_ids
    )
    select rs.id, rs.code, rs.title, rs.status, rs.parent_requirement_id,
           (rs.effective_root_id in (select id from root_wide)) as is_pw,
           a.status, a.assessed_at, a.assessed_by_profile_id
      from root_scoped rs
      left join public.version_requirement_assessments a
             on a.asset_version_id = p_asset_version_id and a.requirement_id = rs.id
     where rs.effective_root_id in (select id from applicable_root_ids)
     order by rs.code;
end $$;
revoke all on function public.list_applicable_requirements(uuid, uuid) from public;
revoke all on function public.list_applicable_requirements(uuid, uuid) from anon;
grant execute on function public.list_applicable_requirements(uuid, uuid) to authenticated, service_role;

create or replace function public.get_version_assessments(p_asset_version_id uuid)
returns table (out_assessment_id uuid, out_requirement_id uuid, out_code text, out_title text, out_status text,
               out_note text, out_assessed_by_profile_id uuid, out_assessed_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
declare v_ws uuid; v_pj uuid;
begin
  if auth.uid() is null then raise exception 'get_version_assessments: authentication required' using errcode='42501'; end if;
  select workspace_id, project_id into v_ws, v_pj from public.asset_versions where id = p_asset_version_id;
  if v_ws is null then raise exception 'get_version_assessments: asset_version % not found', p_asset_version_id using errcode='23503'; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.view') then
    raise exception 'get_version_assessments: forbidden (requirement.view)' using errcode='42501';
  end if;
  return query
    select a.id, a.requirement_id, r.code, r.title, a.status, a.note, a.assessed_by_profile_id, a.assessed_at
      from public.version_requirement_assessments a
      join public.requirements r on r.id = a.requirement_id
     where a.asset_version_id = p_asset_version_id
     order by r.code;
end $$;
revoke all on function public.get_version_assessments(uuid) from public;
revoke all on function public.get_version_assessments(uuid) from anon;
grant execute on function public.get_version_assessments(uuid) to authenticated, service_role;
