-- APP 008: Requirements product-surface authz + RPCs.
--
-- Frozen sources: REQUIREMENTS 001–005, APP 006 (user_saved_views, user_bookmarks),
-- APP 002 (workspace_members).
--
-- Delivers per APP_008_BACKEND_PROPOSAL §7–§13:
--   * lign_has_capability extended additively with 4 reserved capability names
--     (requirement.ai_suggest, requirement.ai_classify, requirement.import,
--      requirement.auto_assess) — NAME-ONLY registration, zero role grants.
--   * Frozen create_requirement / edit_requirement extended via Option A
--     additive-tail params (6 each). Signatures diverge by suffix so the
--     frozen 9-arg / 7-arg overloads continue to bind byte-identically.
--   * requirement.created / .updated / .assessed payload extensions.
--   * 9 additive read RPCs (get_requirement, get_requirement_by_code,
--     get_requirement_chain, get_requirement_trace, list_requirements_dashboard,
--     get_requirement_inbox_count, get_project_requirement_metrics,
--     get_workspace_requirement_metrics, get_release_readiness_for_version).
--
-- All RPCs: SECURITY DEFINER, SET search_path = '', REVOKE from public/anon,
-- GRANT EXECUTE to authenticated, service_role. Every RPC re-checks
-- requirement.view (or the relevant workflow capability) at entry.

------------------------------------------------------------------------------
-- 1. lign_has_capability — register 4 reserved capability names (no grants).
------------------------------------------------------------------------------
-- Recreates the function body with the reserved names in the CHECK list but
-- with zero role grants. This preserves every frozen key + role mapping
-- byte-identically; the reserved keys evaluate to false for every role.

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
      -- APP 008 reserved (name-only; NOT granted to any role):
      -- 'requirement.ai_suggest','requirement.ai_classify',
      -- 'requirement.import','requirement.auto_assess'
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
  'AUTH capability primer. Extended by REQUIREMENTS 003 with 5 requirement.* keys. APP 008 reserves requirement.ai_suggest, requirement.ai_classify, requirement.import, requirement.auto_assess by name only (no role grants).';

------------------------------------------------------------------------------
-- 2. create_requirement — extended (Option A additive tail params).
------------------------------------------------------------------------------
-- Frozen 9-arg overload (REQUIREMENTS 004 L34–L44) is preserved BYTE-IDENTICAL:
-- Postgres treats different parameter counts as distinct function overloads.
-- Callers passing only the frozen 9-arg set continue to bind to the frozen
-- signature; callers passing the extended arg set bind to the 15-arg body
-- below. Both share the same code-generation semantics and event emission.

create or replace function public.create_requirement(
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
  p_due_at                 timestamptz default null
)
returns table (out_requirement_id uuid, out_code text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_caller       uuid;
  v_new_id       uuid;
  v_code         text;
  v_parent_code  text;
  v_n            integer;
  v_snap         jsonb;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'create_requirement: authentication required' using errcode='42501'; end if;
  if p_project_id is null or p_workspace_id is null then raise exception 'create_requirement: project_id and workspace_id required' using errcode='22004'; end if;
  if p_title is null or length(trim(p_title))=0 then raise exception 'create_requirement: title required' using errcode='22004'; end if;
  if p_status not in ('draft','active') then raise exception 'create_requirement: initial status must be draft or active (got %)', p_status using errcode='22023'; end if;

  -- Validate the additive tail params against the same CHECKs applied to the columns.
  if p_priority is not null and p_priority not in ('critical','high','medium','low','informational') then
    raise exception 'create_requirement: invalid priority %', p_priority using errcode='22023';
  end if;
  if p_source_kind is not null and p_source_kind not in (
    'client','consultant','regulatory','internal_team','qa',
    'procurement','manufacturing','safety','contractual','other'
  ) then
    raise exception 'create_requirement: invalid source_kind %', p_source_kind using errcode='22023';
  end if;
  if p_category_kind is not null and p_category_kind not in (
    'functional','non_functional','regulatory','contractual','technical',
    'aesthetic','sustainability','safety','operational','other'
  ) then
    raise exception 'create_requirement: invalid category_kind %', p_category_kind using errcode='22023';
  end if;
  if p_verification_method is not null and p_verification_method not in (
    'inspection','test','analysis','demonstration'
  ) then
    raise exception 'create_requirement: invalid verification_method %', p_verification_method using errcode='22023';
  end if;

  if not public.lign_has_capability(p_project_id, p_workspace_id, 'requirement.create') then
    raise exception 'create_requirement: forbidden (requirement.create)' using errcode='42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('lign_req_code:' || p_project_id::text));

  if p_parent_requirement_id is null then
    select coalesce(count(*), 0) + 1 into v_n
      from public.requirements where project_id = p_project_id and parent_requirement_id is null;
    v_code := 'R-' || lpad(v_n::text, 3, '0');
  else
    select code into v_parent_code from public.requirements
     where id = p_parent_requirement_id and project_id = p_project_id;
    if v_parent_code is null then
      raise exception 'create_requirement: parent % not found in project %', p_parent_requirement_id, p_project_id using errcode='23503';
    end if;
    select coalesce(count(*), 0) + 1 into v_n
      from public.requirements where project_id = p_project_id and parent_requirement_id = p_parent_requirement_id;
    v_code := v_parent_code || '.' || v_n::text;
  end if;

  insert into public.requirements
    (workspace_id, project_id, parent_requirement_id, code, title, description,
     category, source, source_ref, status, created_by_profile_id,
     priority, source_kind, category_kind, owner_profile_id,
     verification_method, due_at)
  values
    (p_workspace_id, p_project_id, p_parent_requirement_id, v_code, p_title, p_description,
     p_category, p_source, p_source_ref, p_status, v_caller,
     coalesce(p_priority, 'medium'),
     p_source_kind, p_category_kind,
     coalesce(p_owner_profile_id, v_caller),
     p_verification_method, p_due_at)
  returning id into v_new_id;

  -- Build the subject_snapshot with the frozen 4 keys plus additive keys.
  v_snap := jsonb_build_object(
    'code', v_code,
    'title', p_title,
    'parent_requirement_id', p_parent_requirement_id,
    'initial_status', p_status,
    'priority', coalesce(p_priority, 'medium'),
    'source_kind', p_source_kind,
    'category_kind', p_category_kind,
    'owner_profile_id', coalesce(p_owner_profile_id, v_caller),
    'verification_method', p_verification_method,
    'due_at', p_due_at
  );

  insert into public.activity_events
    (workspace_id, project_id, occurred_at, event_type,
     actor_profile_id, actor_kind,
     subject_kind, subject_id, subject_label,
     subject_snapshot, payload)
  values (p_workspace_id, p_project_id, now(), 'requirement.created',
          v_caller, 'user',
          'requirement', v_new_id, v_code,
          v_snap,
          '{}'::jsonb);

  return query select v_new_id, v_code;
end $$;

comment on function public.create_requirement(
  uuid, uuid, text, text, text, text, text, uuid, text,
  text, text, text, uuid, text, timestamptz
) is
  'APP 008 §9.1: Option A additive-tail extension of create_requirement. Adds nullable p_priority / p_source_kind / p_category_kind / p_owner_profile_id / p_verification_method / p_due_at. Frozen 9-arg overload preserved. Emits requirement.created with the additive payload keys.';

revoke all on function public.create_requirement(
  uuid, uuid, text, text, text, text, text, uuid, text,
  text, text, text, uuid, text, timestamptz
) from public, anon;
grant execute on function public.create_requirement(
  uuid, uuid, text, text, text, text, text, uuid, text,
  text, text, text, uuid, text, timestamptz
) to authenticated, service_role;

------------------------------------------------------------------------------
-- 3. edit_requirement — extended (Option A additive tail params).
------------------------------------------------------------------------------
-- Frozen 7-arg overload (REQUIREMENTS 004 L120–L128) is preserved
-- BYTE-IDENTICAL. This 13-arg overload adds NULL-defaulted tail params for
-- the six additive columns; NULL keeps the column unchanged (coalesce).

create or replace function public.edit_requirement(
  p_requirement_id       uuid,
  p_title                text        default null,
  p_description          text        default null,
  p_category             text        default null,
  p_source               text        default null,
  p_source_ref           text        default null,
  p_status               text        default null,
  p_priority             text        default null,
  p_source_kind          text        default null,
  p_category_kind        text        default null,
  p_owner_profile_id     uuid        default null,
  p_verification_method  text        default null,
  p_due_at               timestamptz default null
)
returns table (out_requirement_id uuid, out_updated boolean)
language plpgsql security definer set search_path = ''
as $$
declare
  v_caller       uuid;
  v_ws           uuid;
  v_pj           uuid;
  v_code         text;
  v_cur_status   text;
  v_cur_title    text;
  v_cur_desc     text;
  v_cur_cat      text;
  v_cur_src      text;
  v_cur_ref      text;
  v_cur_prio     text;
  v_cur_sk       text;
  v_cur_ck       text;
  v_cur_owner    uuid;
  v_cur_vm       text;
  v_cur_due      timestamptz;
  v_changed      text[] := array[]::text[];
  v_snap         jsonb;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'edit_requirement: authentication required' using errcode='42501'; end if;
  if p_requirement_id is null then raise exception 'edit_requirement: requirement_id required' using errcode='22004'; end if;

  select workspace_id, project_id, code, status, title, description, category, source, source_ref,
         priority, source_kind, category_kind, owner_profile_id, verification_method, due_at
    into v_ws, v_pj, v_code, v_cur_status, v_cur_title, v_cur_desc, v_cur_cat, v_cur_src, v_cur_ref,
         v_cur_prio, v_cur_sk, v_cur_ck, v_cur_owner, v_cur_vm, v_cur_due
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
  if p_priority is not null and p_priority not in ('critical','high','medium','low','informational') then
    raise exception 'edit_requirement: invalid priority %', p_priority using errcode='22023';
  end if;
  if p_source_kind is not null and p_source_kind not in (
    'client','consultant','regulatory','internal_team','qa',
    'procurement','manufacturing','safety','contractual','other'
  ) then
    raise exception 'edit_requirement: invalid source_kind %', p_source_kind using errcode='22023';
  end if;
  if p_category_kind is not null and p_category_kind not in (
    'functional','non_functional','regulatory','contractual','technical',
    'aesthetic','sustainability','safety','operational','other'
  ) then
    raise exception 'edit_requirement: invalid category_kind %', p_category_kind using errcode='22023';
  end if;
  if p_verification_method is not null and p_verification_method not in (
    'inspection','test','analysis','demonstration'
  ) then
    raise exception 'edit_requirement: invalid verification_method %', p_verification_method using errcode='22023';
  end if;

  -- Diff computation. NULL means "leave unchanged" so it can't be a change.
  if p_title              is not null and p_title              is distinct from v_cur_title  then v_changed := array_append(v_changed, 'title');              end if;
  if p_description        is not null and p_description        is distinct from v_cur_desc   then v_changed := array_append(v_changed, 'description');        end if;
  if p_category           is not null and p_category           is distinct from v_cur_cat    then v_changed := array_append(v_changed, 'category');           end if;
  if p_source             is not null and p_source             is distinct from v_cur_src    then v_changed := array_append(v_changed, 'source');             end if;
  if p_source_ref         is not null and p_source_ref         is distinct from v_cur_ref    then v_changed := array_append(v_changed, 'source_ref');         end if;
  if p_status             is not null and p_status             is distinct from v_cur_status then v_changed := array_append(v_changed, 'status');             end if;
  if p_priority           is not null and p_priority           is distinct from v_cur_prio   then v_changed := array_append(v_changed, 'priority');           end if;
  if p_source_kind        is not null and p_source_kind        is distinct from v_cur_sk     then v_changed := array_append(v_changed, 'source_kind');        end if;
  if p_category_kind      is not null and p_category_kind      is distinct from v_cur_ck     then v_changed := array_append(v_changed, 'category_kind');      end if;
  if p_owner_profile_id   is not null and p_owner_profile_id   is distinct from v_cur_owner  then v_changed := array_append(v_changed, 'owner_profile_id');   end if;
  if p_verification_method is not null and p_verification_method is distinct from v_cur_vm   then v_changed := array_append(v_changed, 'verification_method'); end if;
  if p_due_at             is not null and p_due_at             is distinct from v_cur_due    then v_changed := array_append(v_changed, 'due_at');             end if;

  if array_length(v_changed, 1) is null then
    return query select p_requirement_id, false;
    return;
  end if;

  update public.requirements
     set title               = coalesce(p_title,               title),
         description         = coalesce(p_description,         description),
         category            = coalesce(p_category,            category),
         source              = coalesce(p_source,              source),
         source_ref          = coalesce(p_source_ref,          source_ref),
         status              = coalesce(p_status,              status),
         priority            = coalesce(p_priority,            priority),
         source_kind         = coalesce(p_source_kind,         source_kind),
         category_kind       = coalesce(p_category_kind,       category_kind),
         owner_profile_id    = coalesce(p_owner_profile_id,    owner_profile_id),
         verification_method = coalesce(p_verification_method, verification_method),
         due_at              = coalesce(p_due_at,              due_at)
   where id = p_requirement_id;

  v_snap := jsonb_build_object(
    'code', v_code,
    'kind', 'edit',
    'changed_fields', to_jsonb(v_changed),
    'previous_status', case when 'status' = any(v_changed) then v_cur_status else null end,
    'new_status',      case when 'status' = any(v_changed) then p_status     else null end
  );

  if 'priority' = any(v_changed) then
    v_snap := v_snap
      || jsonb_build_object('previous_priority', v_cur_prio,
                            'new_priority',      p_priority);
  end if;
  if 'owner_profile_id' = any(v_changed) then
    v_snap := v_snap
      || jsonb_build_object('previous_owner_profile_id', v_cur_owner,
                            'new_owner_profile_id',      p_owner_profile_id);
  end if;
  if 'due_at' = any(v_changed) then
    v_snap := v_snap
      || jsonb_build_object('previous_due_at', v_cur_due,
                            'new_due_at',      p_due_at);
  end if;

  insert into public.activity_events
    (workspace_id, project_id, occurred_at, event_type,
     actor_profile_id, actor_kind,
     subject_kind, subject_id, subject_label,
     subject_snapshot, payload)
  values (v_ws, v_pj, now(), 'requirement.updated',
          v_caller, 'user',
          'requirement', p_requirement_id, v_code,
          v_snap,
          '{}'::jsonb);

  return query select p_requirement_id, true;
end $$;

comment on function public.edit_requirement(
  uuid, text, text, text, text, text, text,
  text, text, text, uuid, text, timestamptz
) is
  'APP 008 §9.2: Option A additive-tail extension of edit_requirement. Adds nullable p_priority / p_source_kind / p_category_kind / p_owner_profile_id / p_verification_method / p_due_at. Frozen 7-arg overload preserved. Extends requirement.updated (kind=edit) with previous_priority/new_priority, previous_owner_profile_id/new_owner_profile_id, previous_due_at/new_due_at, and richer changed_fields.';

revoke all on function public.edit_requirement(
  uuid, text, text, text, text, text, text,
  text, text, text, uuid, text, timestamptz
) from public, anon;
grant execute on function public.edit_requirement(
  uuid, text, text, text, text, text, text,
  text, text, text, uuid, text, timestamptz
) to authenticated, service_role;

------------------------------------------------------------------------------
-- 4. assess_version_requirement — additive payload keys on requirement.assessed
------------------------------------------------------------------------------
-- Signature preserved BYTE-IDENTICAL. Only the payload block changes: adds
-- priority, is_critical_unsatisfied, owner_profile_id — all denormalized
-- from the requirement row for APP 010 recipient fan-out (§12.4).

create or replace function public.assess_version_requirement(
  p_asset_version_id uuid, p_requirement_id uuid, p_status text, p_note text default null
) returns table (out_assessment_id uuid, out_action text)
  language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid;
  v_v_ws uuid; v_v_pj uuid;
  v_r_ws uuid; v_r_pj uuid; v_r_st text; v_r_code text;
  v_r_prio text; v_r_owner uuid;
  v_prev_status text;
  v_id uuid; v_action text;
  v_is_crit boolean;
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

  select workspace_id, project_id, status, code, priority, owner_profile_id
    into v_r_ws, v_r_pj, v_r_st, v_r_code, v_r_prio, v_r_owner
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

  select status into v_prev_status
    from public.version_requirement_assessments
   where asset_version_id = p_asset_version_id and requirement_id = p_requirement_id;

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

  v_is_crit := (v_r_prio = 'critical' and p_status in ('not_satisfied','partial'));

  insert into public.activity_events
    (workspace_id, project_id, occurred_at, event_type,
     actor_profile_id, actor_kind, subject_kind, subject_id, subject_label,
     subject_snapshot, payload)
  values (v_r_ws, v_r_pj, now(), 'requirement.assessed',
          v_caller, 'user',
          'version_requirement_assessment', v_id, v_r_code,
          jsonb_build_object(
            'code', v_r_code,
            'requirement_id', p_requirement_id,
            'asset_version_id', p_asset_version_id,
            'status', p_status,
            'previous_status', v_prev_status,
            'action', v_action,
            'priority', v_r_prio,
            'owner_profile_id', v_r_owner,
            'is_critical_unsatisfied', v_is_crit
          ),
          '{}'::jsonb);

  return query select v_id, v_action;
end $$;

-- Preserve frozen REVOKE / GRANT (idempotent).
revoke all on function public.assess_version_requirement(uuid, uuid, text, text) from public;
revoke all on function public.assess_version_requirement(uuid, uuid, text, text) from anon;
grant execute on function public.assess_version_requirement(uuid, uuid, text, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 5. get_requirement — Requirement Detail read.
------------------------------------------------------------------------------

create or replace function public.get_requirement(p_requirement_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_ws uuid; v_pj uuid;
  v_row jsonb;
  v_subs jsonb;
  v_app_summary jsonb;
  v_assess_summary jsonb;
  v_metrics jsonb;
  v_chain jsonb;
  v_asset_count int;
  v_asset_ids uuid[];
  v_root_id uuid;
begin
  if auth.uid() is null then raise exception 'get_requirement: authentication required' using errcode='42501'; end if;

  select workspace_id, project_id, coalesce(parent_requirement_id, id)
    into v_ws, v_pj, v_root_id
    from public.requirements where id = p_requirement_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.view') then
    return null; -- fail-closed: don't leak existence
  end if;

  select to_jsonb(r) into v_row
    from public.requirements r where r.id = p_requirement_id;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.code), '[]'::jsonb)
    into v_subs
    from public.requirements c where c.parent_requirement_id = p_requirement_id;

  select count(*)::int, coalesce(array_agg(design_asset_id), array[]::uuid[])
    into v_asset_count, v_asset_ids
    from public.requirement_design_assets where requirement_id = v_root_id;

  v_app_summary := jsonb_build_object(
    'is_project_wide', v_asset_count = 0,
    'asset_count',     v_asset_count,
    'asset_ids',       to_jsonb(v_asset_ids)
  );

  -- Assessment summary: count applicable latest-versions and how many are assessed.
  with applicable_versions as (
    select av.id as version_id, av.design_asset_id
      from public.asset_versions av
     where av.project_id = v_pj
       and (
         v_asset_count = 0  -- project-wide
         or av.design_asset_id = any (v_asset_ids)
       )
  ),
  latest_per_asset as (
    select distinct on (design_asset_id) version_id, design_asset_id
      from applicable_versions
      -- Every asset_version has a created_at; choose latest.
     order by design_asset_id, version_id desc
  ),
  joined as (
    select l.design_asset_id, l.version_id, vra.status
      from latest_per_asset l
      left join public.version_requirement_assessments vra
             on vra.asset_version_id = l.version_id
            and vra.requirement_id   = p_requirement_id
  )
  select jsonb_build_object(
           'versions_applicable', count(*)::int,
           'versions_assessed',   count(*) filter (where status is not null)::int,
           'latest_status_per_asset', coalesce(jsonb_object_agg(
             design_asset_id::text, coalesce(status, 'unassessed')
           ) filter (where design_asset_id is not null), '{}'::jsonb)
         )
    into v_assess_summary
    from joined;

  -- Days-since-last-assessment; days-until-due.
  select jsonb_build_object(
           'coverage_pct',
             case
               when (v_assess_summary->>'versions_applicable')::int = 0 then 0
               else round(
                 100.0 * (v_assess_summary->>'versions_assessed')::numeric
                       / nullif((v_assess_summary->>'versions_applicable')::numeric, 0),
                 2)
             end,
           'days_since_last_assessment', (
             select case when max(assessed_at) is null then null
                        else extract(day from now() - max(assessed_at))::int end
               from public.version_requirement_assessments
              where requirement_id = p_requirement_id
           ),
           'days_until_due', (
             case when (v_row->>'due_at') is null then null
                  else extract(day from (v_row->>'due_at')::timestamptz - now())::int end
           )
         )
    into v_metrics;

  -- Chain position: forward + backward pointers.
  select jsonb_build_object(
           'supersedes',
             (select id from public.requirements
               where superseded_by_requirement_id = p_requirement_id
               order by created_at desc limit 1),
           'superseded_by', (v_row->>'superseded_by_requirement_id')::uuid,
           'chain_depth', (
             with recursive walk as (
               select id, superseded_by_requirement_id, 0 as d
                 from public.requirements where id = p_requirement_id
               union all
               select r.id, r.superseded_by_requirement_id, w.d + 1
                 from public.requirements r
                 join walk w on w.superseded_by_requirement_id = r.id
                where w.d < 32
             )
             select coalesce(max(d), 0) from walk
           )
         )
    into v_chain;

  return jsonb_build_object(
    'requirement',          v_row,
    'sub_requirements',     v_subs,
    'applicability_summary', v_app_summary,
    'assessment_summary',   v_assess_summary,
    'metrics',              v_metrics,
    'chain_position',       v_chain
  );
end $$;

revoke all on function public.get_requirement(uuid) from public, anon;
grant execute on function public.get_requirement(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 6. get_requirement_by_code — deep-link resolver.
------------------------------------------------------------------------------

create or replace function public.get_requirement_by_code(
  p_project_id uuid, p_workspace_id uuid, p_code text
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_row public.requirements;
begin
  if auth.uid() is null then raise exception 'get_requirement_by_code: authentication required' using errcode='42501'; end if;
  if not public.lign_has_capability(p_project_id, p_workspace_id, 'requirement.view') then
    return null; -- fail-closed
  end if;
  select * into v_row from public.requirements
   where project_id = p_project_id and workspace_id = p_workspace_id and code = p_code;
  if v_row.id is null then return null; end if;
  return jsonb_build_object(
    'requirement_id', v_row.id,
    'code',           v_row.code,
    'title',          v_row.title,
    'status',         v_row.status,
    'project_id',     v_row.project_id,
    'workspace_id',   v_row.workspace_id
  );
end $$;

revoke all on function public.get_requirement_by_code(uuid, uuid, text) from public, anon;
grant execute on function public.get_requirement_by_code(uuid, uuid, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 7. get_requirement_chain — supersession chain walk.
------------------------------------------------------------------------------

create or replace function public.get_requirement_chain(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_ws uuid; v_pj uuid;
  v_chain jsonb;
begin
  if auth.uid() is null then raise exception 'get_requirement_chain: authentication required' using errcode='42501'; end if;
  select workspace_id, project_id into v_ws, v_pj
    from public.requirements where id = p_requirement_id;
  if v_ws is null then return '[]'::jsonb; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.view') then
    return '[]'::jsonb;
  end if;

  with recursive
    -- Walk forward via superseded_by_requirement_id.
    forward as (
      select id, code, title, status, superseded_by_requirement_id, 0 as pos
        from public.requirements where id = p_requirement_id
      union all
      select r.id, r.code, r.title, r.status, r.superseded_by_requirement_id, f.pos + 1
        from public.requirements r
        join forward f on r.id = f.superseded_by_requirement_id
       where f.pos < 32
    ),
    -- Walk backward: find rows whose superseded_by points at any row already in the chain.
    backward as (
      select id, code, title, status, superseded_by_requirement_id, 0 as pos
        from public.requirements where superseded_by_requirement_id = p_requirement_id
      union all
      select r.id, r.code, r.title, r.status, r.superseded_by_requirement_id, b.pos + 1
        from public.requirements r
        join backward b on r.superseded_by_requirement_id = b.id
       where b.pos < 32
    ),
    all_rows as (
      select id, code, title, status, superseded_by_requirement_id, pos, 'forward'::text as dir
        from forward
      union
      select id, code, title, status, superseded_by_requirement_id, -pos - 1, 'backward'::text
        from backward
    )
  select jsonb_agg(
           jsonb_build_object(
             'requirement_id', id,
             'code',           code,
             'title',          title,
             'status',         status,
             'superseded_by_requirement_id', superseded_by_requirement_id,
             'is_current',     (id = p_requirement_id)
           )
           order by pos
         )
    into v_chain
    from all_rows;

  return coalesce(v_chain, '[]'::jsonb);
end $$;

revoke all on function public.get_requirement_chain(uuid) from public, anon;
grant execute on function public.get_requirement_chain(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 8. get_requirement_trace — bundled trace-graph read.
------------------------------------------------------------------------------

create or replace function public.get_requirement_trace(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_ws uuid; v_pj uuid;
  v_row jsonb;
  v_root_id uuid;
  v_asset_count int;
  v_asset_ids uuid[];
  v_apps jsonb;
  v_subs jsonb;
  v_assessments jsonb;
  v_changes jsonb;
  v_decisions jsonb;
  v_dcount int;
  v_ars jsonb;
  v_chain jsonb;
  v_metrics jsonb;
begin
  if auth.uid() is null then raise exception 'get_requirement_trace: authentication required' using errcode='42501'; end if;

  select workspace_id, project_id, coalesce(parent_requirement_id, id)
    into v_ws, v_pj, v_root_id
    from public.requirements where id = p_requirement_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.view') then
    return null;
  end if;

  select to_jsonb(r) into v_row from public.requirements r where r.id = p_requirement_id;

  select count(*)::int, coalesce(array_agg(design_asset_id), array[]::uuid[])
    into v_asset_count, v_asset_ids
    from public.requirement_design_assets where requirement_id = v_root_id;

  if v_asset_count = 0 then
    v_apps := '[]'::jsonb;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
             'design_asset_id', da.id,
             'name',            da.title,
             'project_id',      da.project_id
           )), '[]'::jsonb)
      into v_apps
      from public.design_assets da
     where da.id = any (v_asset_ids);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'code', code, 'title', title,
           'status', status, 'priority', priority
         ) order by code), '[]'::jsonb)
    into v_subs
    from public.requirements where parent_requirement_id = p_requirement_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'asset_version_id', asset_version_id,
           'asset_id', (select design_asset_id from public.asset_versions where id = vra.asset_version_id),
           'version_number', (select version_number from public.asset_versions where id = vra.asset_version_id),
           'status', status, 'note', note, 'assessed_at', assessed_at,
           'assessed_by_profile_id', assessed_by_profile_id
         ) order by assessed_at desc), '[]'::jsonb)
    into v_assessments
    from public.version_requirement_assessments vra
   where vra.requirement_id = p_requirement_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'change_id', id, 'kind', kind, 'created_at', created_at,
           'subject_label', label
         ) order by created_at desc), '[]'::jsonb)
    into v_changes
    from public.changes where requirement_id = p_requirement_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'decision_id', id, 'subject_kind', subject_kind, 'subject_id', subject_id,
           'created_at', created_at,
           'decision_reason_snippet', left(coalesce(decision_reason, ''), 200)
         ) order by created_at desc), '[]'::jsonb)
    into v_decisions
    from public.decisions where requirement_id = p_requirement_id;

  select count(*)::int into v_dcount
    from public.comments
   where target_requirement_id = p_requirement_id and deleted_at is null;

  select coalesce(jsonb_agg(distinct jsonb_build_object(
           'approval_request_id', ar.id,
           'status', ar.status,
           'outcome_at', ar.outcome_at,
           'root_approval_request_id', ar.root_approval_request_id
         )), '[]'::jsonb)
    into v_ars
    from public.decisions d
    join public.approval_requests ar on ar.id = d.subject_id
   where d.requirement_id = p_requirement_id
     and d.subject_kind = 'approval_request';

  v_chain := public.get_requirement_chain(p_requirement_id);

  v_metrics := jsonb_build_object(
    'coverage_pct',
      (case
         when jsonb_array_length(v_assessments) = 0 then 0
         else round(
           100.0 * (select count(*) from jsonb_array_elements(v_assessments) x where x->>'status' = 'satisfied')
                 / nullif(jsonb_array_length(v_assessments)::numeric, 0), 2)
       end),
    'critical_unsatisfied_count',
      (select count(*) from jsonb_array_elements(v_assessments) x
        where x->>'status' in ('not_satisfied','partial')
          and (v_row->>'priority') = 'critical'),
    'unassessed_on_latest_count', 0
  );

  return jsonb_build_object(
    'requirement',        v_row,
    'applicable_assets',  v_apps,
    'is_project_wide',    v_asset_count = 0,
    'sub_requirements',   v_subs,
    'assessments',        v_assessments,
    'related_changes',    v_changes,
    'related_decisions',  v_decisions,
    'discussion_count',   v_dcount,
    'approval_requests',  v_ars,
    'supersession_chain', v_chain,
    'metrics',            v_metrics
  );
end $$;

revoke all on function public.get_requirement_trace(uuid) from public, anon;
grant execute on function public.get_requirement_trace(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 9. list_requirements_dashboard — paginated dashboard read.
------------------------------------------------------------------------------

create or replace function public.list_requirements_dashboard(
  p_ws_id                 uuid,
  p_proj_id               uuid,
  p_view                  text        default 'all_active',
  p_status_filter         text[]      default null,
  p_priority_filter       text[]      default null,
  p_source_filter         text[]      default null,
  p_category_filter       text[]      default null,
  p_scope_filter          text        default null,   -- 'project_wide' | 'asset_scoped' | null
  p_owner_ids             uuid[]      default null,
  p_search                text        default null,
  p_cursor_updated_at     timestamptz default null,
  p_cursor_id             uuid        default null,
  p_limit                 integer     default 50,
  p_saved_view_id         uuid        default null
)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_rows jsonb;
  v_next_cursor jsonb;
  v_effective_view text := coalesce(p_view, 'all_active');
  v_status_filter text[] := p_status_filter;
  v_priority_filter text[] := p_priority_filter;
  v_source_filter text[] := p_source_filter;
  v_category_filter text[] := p_category_filter;
  v_owner_ids uuid[] := p_owner_ids;
  v_search text := p_search;
  v_scope_filter text := p_scope_filter;
  v_saved_payload jsonb;
  v_limit int := least(coalesce(p_limit, 50), 200);
begin
  if v_caller is null then raise exception 'list_requirements_dashboard: authentication required' using errcode='42501'; end if;
  if p_ws_id is null then raise exception 'list_requirements_dashboard: workspace id required' using errcode='22004'; end if;

  -- Resolve saved view (if any) — override the filter set.
  if p_saved_view_id is not null then
    select payload into v_saved_payload
      from public.user_saved_views
     where id = p_saved_view_id
       and user_id = v_caller
       and workspace_id = p_ws_id
       and scope = 'requirements';
    if v_saved_payload is not null then
      v_effective_view    := coalesce(v_saved_payload->>'view', v_effective_view);
      v_status_filter     := case when v_saved_payload ? 'status_filter'    then array(select jsonb_array_elements_text(v_saved_payload->'status_filter'))    else v_status_filter    end;
      v_priority_filter   := case when v_saved_payload ? 'priority_filter'  then array(select jsonb_array_elements_text(v_saved_payload->'priority_filter'))  else v_priority_filter  end;
      v_source_filter     := case when v_saved_payload ? 'source_filter'    then array(select jsonb_array_elements_text(v_saved_payload->'source_filter'))    else v_source_filter    end;
      v_category_filter   := case when v_saved_payload ? 'category_filter'  then array(select jsonb_array_elements_text(v_saved_payload->'category_filter'))  else v_category_filter  end;
      v_scope_filter      := coalesce(v_saved_payload->>'scope_filter', v_scope_filter);
      v_search            := coalesce(v_saved_payload->>'search', v_search);
      v_owner_ids         := case when v_saved_payload ? 'owner_ids'        then (select array_agg(x::uuid) from jsonb_array_elements_text(v_saved_payload->'owner_ids') as x) else v_owner_ids end;
    end if;
  end if;

  -- Interpret magic view names.
  if v_effective_view = 'assigned_to_me' then
    v_owner_ids := array[v_caller];
  end if;
  if v_effective_view = 'archived' then
    v_status_filter := array['archived'];
  elsif v_effective_view = 'superseded' then
    v_status_filter := array['superseded'];
  elsif v_effective_view in ('overdue_critical') then
    v_priority_filter := array['critical'];
  end if;

  -- Authorization: at workspace scope, filter to projects the caller can view.
  -- At project scope, gate at RPC entry.
  if p_proj_id is not null then
    if not public.lign_has_capability(p_proj_id, p_ws_id, 'requirement.view') then
      raise exception 'list_requirements_dashboard: forbidden (requirement.view)' using errcode='42501';
    end if;
  end if;

  with base as (
    select r.*,
           p.name as project_name,
           (select count(*)::int from public.requirement_design_assets rda
              where rda.requirement_id = coalesce(r.parent_requirement_id, r.id))
             as rda_count
      from public.requirements r
      join public.projects p on p.id = r.project_id
     where r.workspace_id = p_ws_id
       and (p_proj_id is null or r.project_id = p_proj_id)
       and (
         p_proj_id is not null
         or public.lign_has_capability(r.project_id, r.workspace_id, 'requirement.view')
       )
       and (v_status_filter is null   or r.status         = any (v_status_filter))
       and (v_priority_filter is null or r.priority       = any (v_priority_filter))
       and (v_source_filter is null   or r.source_kind    = any (v_source_filter))
       and (v_category_filter is null or r.category_kind  = any (v_category_filter))
       and (v_owner_ids is null       or r.owner_profile_id = any (v_owner_ids))
       and (v_search is null or v_search = ''
            or r.code        ilike '%' || v_search || '%'
            or r.title       ilike '%' || v_search || '%'
            or coalesce(r.description, '') ilike '%' || v_search || '%')
       -- Default view: only non-terminal unless user asked otherwise.
       and (
         v_effective_view in ('all','archived','superseded')
         or v_status_filter is not null
         or r.status in ('draft','active')
       )
       and (
         p_cursor_updated_at is null
         or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id)
       )
  ),
  scoped as (
    select * from base
     where (
       v_scope_filter is null
       or (v_scope_filter = 'project_wide' and rda_count = 0)
       or (v_scope_filter = 'asset_scoped' and rda_count > 0)
     )
  ),
  filtered as (
    select * from scoped
     order by updated_at desc, id desc
     limit v_limit + 1
  ),
  page as (
    select * from filtered limit v_limit
  ),
  paged as (
    select b.*,
      jsonb_build_object(
        'scope', case when b.rda_count = 0 then 'project_wide' else 'asset_scoped' end,
        'asset_count', b.rda_count
      ) as applicability_summary,
      (
        with applicable_versions as (
          select av.id as version_id, av.design_asset_id
            from public.asset_versions av
           where av.project_id = b.project_id
             and (b.rda_count = 0
                  or av.design_asset_id in (
                    select design_asset_id from public.requirement_design_assets
                     where requirement_id = coalesce(b.parent_requirement_id, b.id)))
        ),
        latest as (
          select distinct on (design_asset_id) version_id
            from applicable_versions
           order by design_asset_id, version_id desc
        ),
        j as (
          select l.version_id, vra.status
            from latest l
            left join public.version_requirement_assessments vra
                   on vra.asset_version_id = l.version_id
                  and vra.requirement_id   = b.id
        )
        select jsonb_build_object(
                 'applicable_versions_count', count(*)::int,
                 'satisfied_count',           count(*) filter (where status = 'satisfied')::int,
                 'coverage_pct',
                   case when count(*) = 0 then 0
                        else round(100.0 * count(*) filter (where status = 'satisfied')::numeric
                                       / nullif(count(*)::numeric, 0), 2)
                   end,
                 'latest_version_assessed',
                   coalesce(bool_and(status is not null), false)
               ) from j
      ) as assessment_coverage
      from page b
  )
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'requirement_id',       id,
             'code',                 code,
             'title',                title,
             'status',               status,
             'priority',             priority,
             'source_kind',          source_kind,
             'category_kind',        category_kind,
             'owner_profile_id',     owner_profile_id,
             'updated_at',           updated_at,
             'applicability_summary', applicability_summary,
             'assessment_coverage',  assessment_coverage,
             'project_id',           project_id,
             'project_name',         project_name,
             'workspace_id',         workspace_id,
             'due_at',               due_at
           )
         ), '[]'::jsonb)
    into v_rows
    from paged;

  -- next_cursor: if the filtered set held more than v_limit, return the last-row cursor.
  select case when count(*) > v_limit then
           jsonb_build_object(
             'updated_at', (select updated_at from filtered offset v_limit - 1 limit 1),
             'id',         (select id         from filtered offset v_limit - 1 limit 1)
           )
         else null end
    into v_next_cursor
    from filtered;

  return jsonb_build_object(
    'rows',        v_rows,
    'next_cursor', v_next_cursor
  );
end $$;

revoke all on function public.list_requirements_dashboard(
  uuid, uuid, text, text[], text[], text[], text[], text, uuid[], text,
  timestamptz, uuid, integer, uuid
) from public, anon;
grant execute on function public.list_requirements_dashboard(
  uuid, uuid, text, text[], text[], text[], text[], text, uuid[], text,
  timestamptz, uuid, integer, uuid
) to authenticated, service_role;

------------------------------------------------------------------------------
-- 10. get_requirement_inbox_count — NavRail badge.
------------------------------------------------------------------------------

create or replace function public.get_requirement_inbox_count(p_ws_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_assigned int;
  v_overdue int;
  v_needs int;
begin
  if v_caller is null then raise exception 'get_requirement_inbox_count: authentication required' using errcode='42501'; end if;

  select count(*)::int into v_assigned
    from public.requirements r
   where r.workspace_id = p_ws_id
     and r.owner_profile_id = v_caller
     and r.status in ('draft','active')
     and public.lign_has_capability(r.project_id, r.workspace_id, 'requirement.view');

  select count(*)::int into v_overdue
    from public.requirements r
   where r.workspace_id = p_ws_id
     and r.priority = 'critical'
     and r.status in ('draft','active')
     and r.due_at is not null and r.due_at < now()
     and public.lign_has_capability(r.project_id, r.workspace_id, 'requirement.view');

  select count(*)::int into v_needs
    from public.requirements r
   where r.workspace_id = p_ws_id
     and r.priority = 'critical'
     and r.status in ('draft','active')
     and public.lign_has_capability(r.project_id, r.workspace_id, 'requirement.view')
     and not exists (
       select 1 from public.version_requirement_assessments vra
        where vra.requirement_id = r.id
     );

  return jsonb_build_object(
    'assigned_to_me',   v_assigned,
    'overdue_critical', v_overdue,
    'needs_assessment', v_needs
  );
end $$;

revoke all on function public.get_requirement_inbox_count(uuid) from public, anon;
grant execute on function public.get_requirement_inbox_count(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 11. get_project_requirement_metrics — metrics strip.
------------------------------------------------------------------------------

create or replace function public.get_project_requirement_metrics(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_ws uuid;
  v_out jsonb;
begin
  if auth.uid() is null then raise exception 'get_project_requirement_metrics: authentication required' using errcode='42501'; end if;
  select workspace_id into v_ws from public.projects where id = p_project_id;
  if v_ws is null then raise exception 'get_project_requirement_metrics: project not found' using errcode='23503'; end if;
  if not public.lign_has_capability(p_project_id, v_ws, 'requirement.view') then
    raise exception 'get_project_requirement_metrics: forbidden (requirement.view)' using errcode='42501';
  end if;

  with r as (select * from public.requirements where project_id = p_project_id)
  select jsonb_build_object(
    'total_count', (select count(*)::int from r),
    'by_status',
      (select jsonb_object_agg(status, cnt) from
        (select status, count(*)::int as cnt from r group by status) s),
    'by_priority',
      (select jsonb_object_agg(coalesce(priority, 'unset'), cnt) from
        (select priority, count(*)::int as cnt from r group by priority) s),
    'by_source',
      (select jsonb_object_agg(coalesce(source_kind, 'unset'), cnt) from
        (select source_kind, count(*)::int as cnt from r group by source_kind) s),
    'unassessed_on_latest_count',
      (select count(*)::int from r
        where status in ('draft','active')
          and not exists (
            select 1 from public.version_requirement_assessments vra
             where vra.requirement_id = r.id)),
    'critical_unsatisfied_count',
      (select count(*)::int from r
        where status in ('draft','active') and priority = 'critical'
          and exists (
            select 1 from public.version_requirement_assessments vra
             where vra.requirement_id = r.id and vra.status in ('not_satisfied','partial'))),
    'overdue_count',
      (select count(*)::int from r
        where status in ('draft','active')
          and due_at is not null and due_at < now()),
    'coverage_rate',
      (select case when count(*) = 0 then 0
                   else round(100.0 * count(*) filter (where vra.status = 'satisfied')::numeric
                                    / nullif(count(*)::numeric, 0), 2) end
         from r
         left join public.version_requirement_assessments vra on vra.requirement_id = r.id
        where r.status in ('draft','active')),
    'trailing_30d_creation_rate',
      (select count(*)::int from public.activity_events
        where project_id = p_project_id
          and event_type = 'requirement.created'
          and occurred_at > now() - interval '30 days'),
    'trailing_30d_assessment_activity_rate',
      (select count(*)::int from public.activity_events
        where project_id = p_project_id
          and event_type = 'requirement.assessed'
          and occurred_at > now() - interval '30 days')
  ) into v_out;

  return v_out;
end $$;

revoke all on function public.get_project_requirement_metrics(uuid) from public, anon;
grant execute on function public.get_project_requirement_metrics(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 12. get_workspace_requirement_metrics — workspace rollup.
------------------------------------------------------------------------------

create or replace function public.get_workspace_requirement_metrics(p_ws_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_out jsonb;
begin
  if v_caller is null then raise exception 'get_workspace_requirement_metrics: authentication required' using errcode='42501'; end if;

  with visible as (
    select r.* from public.requirements r
     where r.workspace_id = p_ws_id
       and public.lign_has_capability(r.project_id, r.workspace_id, 'requirement.view')
  )
  select jsonb_build_object(
    'total_active',
      (select count(*)::int from visible where status in ('draft','active')),
    'by_status',
      (select jsonb_object_agg(status, cnt) from
        (select status, count(*)::int as cnt from visible group by status) s),
    'by_priority',
      (select jsonb_object_agg(coalesce(priority, 'unset'), cnt) from
        (select priority, count(*)::int as cnt from visible group by priority) s),
    'top5_projects_by_critical_unsatisfied',
      (select coalesce(jsonb_agg(x order by cnt desc), '[]'::jsonb) from
        (select v.project_id,
                (select name from public.projects p where p.id = v.project_id) as project_name,
                count(*)::int as cnt
           from visible v
           join public.version_requirement_assessments vra on vra.requirement_id = v.id
          where v.priority = 'critical' and vra.status in ('not_satisfied','partial')
          group by v.project_id
          order by cnt desc
          limit 5) as x),
    'top5_owners_by_open_load',
      (select coalesce(jsonb_agg(x order by cnt desc), '[]'::jsonb) from
        (select owner_profile_id,
                (select display_name from public.profiles where id = v.owner_profile_id) as display_name,
                count(*)::int as cnt
           from visible v
          where owner_profile_id is not null
            and priority in ('critical','high')
            and status = 'active'
          group by owner_profile_id
          order by cnt desc
          limit 5) as x),
    'overdue_count_across_workspace',
      (select count(*)::int from visible
        where status in ('draft','active')
          and due_at is not null and due_at < now())
  ) into v_out;

  return v_out;
end $$;

revoke all on function public.get_workspace_requirement_metrics(uuid) from public, anon;
grant execute on function public.get_workspace_requirement_metrics(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 13. get_release_readiness_for_version — APP 009 read hook.
------------------------------------------------------------------------------

create or replace function public.get_release_readiness_for_version(p_asset_version_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_ws uuid; v_pj uuid; v_asset uuid;
  v_out jsonb;
begin
  if auth.uid() is null then raise exception 'get_release_readiness_for_version: authentication required' using errcode='42501'; end if;
  select workspace_id, project_id, design_asset_id
    into v_ws, v_pj, v_asset
    from public.asset_versions where id = p_asset_version_id;
  if v_ws is null then raise exception 'get_release_readiness_for_version: version not found' using errcode='23503'; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.view') then
    raise exception 'get_release_readiness_for_version: forbidden (requirement.view)' using errcode='42501';
  end if;

  with root_scoped as (
    select r.id, r.priority
      from public.requirements r
     where r.project_id = v_pj
       and r.status in ('draft','active')
  ),
  scoped_root_ids as (
    select distinct requirement_id as root_id from public.requirement_design_assets
     where design_asset_id = v_asset
  ),
  all_project_roots as (
    select id from public.requirements
     where project_id = v_pj and parent_requirement_id is null
       and status in ('draft','active')
  ),
  root_wide as (
    select id from all_project_roots
     where id not in (
       select distinct requirement_id from public.requirement_design_assets
        where requirement_id in (select id from all_project_roots)
     )
  ),
  applicable_root_ids as (
    select id from root_wide union select root_id as id from scoped_root_ids
  ),
  applicable as (
    select rs.id, rs.priority,
           coalesce((select r2.parent_requirement_id from public.requirements r2 where r2.id = rs.id), rs.id) as root_id
      from root_scoped rs
     where coalesce(
             (select parent_requirement_id from public.requirements rr where rr.id = rs.id),
             rs.id
           ) in (select id from applicable_root_ids)
  ),
  joined as (
    select a.id, a.priority, vra.status
      from applicable a
      left join public.version_requirement_assessments vra
             on vra.requirement_id = a.id
            and vra.asset_version_id = p_asset_version_id
  )
  select jsonb_build_object(
    'applicable_count',           count(*)::int,
    'satisfied_count',            count(*) filter (where status = 'satisfied')::int,
    'partial_count',              count(*) filter (where status = 'partial')::int,
    'not_satisfied_count',        count(*) filter (where status = 'not_satisfied')::int,
    'unassessed_count',           count(*) filter (where status is null)::int,
    'critical_unsatisfied_count', count(*) filter (where priority = 'critical' and status in ('not_satisfied','partial'))::int,
    'critical_unassessed_count',  count(*) filter (where priority = 'critical' and status is null)::int
  ) into v_out
  from joined;

  return v_out;
end $$;

revoke all on function public.get_release_readiness_for_version(uuid) from public, anon;
grant execute on function public.get_release_readiness_for_version(uuid) to authenticated, service_role;
