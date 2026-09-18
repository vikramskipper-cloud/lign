-- APP 009: Releases product-surface authz + RPCs (Migration B).
--
-- Frozen sources preserved byte-identically:
--   * Migration 008 (public.releases, public.release_items schema)
--   * AUTH 008 (releases_status_via_rpc trigger, finalize_release, withdraw_release,
--              RLS policies on releases/release_items)
--   * AUTH 001 (lign_has_capability role map)
--   * APP 007 (get_approval_readiness) and APP 008 (get_release_readiness_for_version)
--     consumed read-only.
--
-- Delivers per APP_009_BACKEND_PROPOSAL §10, §11, §13, §14:
--   * lign_has_capability extended additively with 6 reserved capability names
--     (release.schedule, release.supersede, release.ai_suggest, release.ai_classify,
--      release.audit_export, release.recall) — NAME-ONLY registration, zero role grants.
--     Frozen 4 keys and role grants preserved byte-identically.
--   * 14 read RPCs (§13.1–§13.14).
--   * 6 new write RPCs (create_release_draft, add_release_item, remove_release_item,
--     reorder_release_items, discard_release_draft, publish_release).
--   * 2 frozen write RPCs extended via CREATE OR REPLACE single-function
--     default-tail params per F-2 (no dual overloads):
--       finalize_release(uuid, text default null)      -- adds p_release_type
--       withdraw_release(uuid, text, boolean default false) -- adds p_admin_override
--     Frozen positional calls bind unchanged.
--   * F-4: finalize_release ALWAYS captures evidence (no p_capture_evidence bypass).
--   * L-1: publish_release / finalize_release issue a single atomic UPDATE that
--     transitions status, sets evidence, records publisher, and folds release_type
--     in one shot (one updated_at bump per publish).
--   * L-2: list_release_activity uses concrete subject_kind predicate.
--
-- All RPCs: SECURITY DEFINER, SET search_path = '', REVOKE from public/anon,
-- GRANT EXECUTE to authenticated, service_role.

------------------------------------------------------------------------------
-- 1. lign_has_capability — additively register 6 reserved release.* names.
------------------------------------------------------------------------------
-- Preserves every frozen key + role mapping byte-identically. The reserved
-- keys evaluate to false for every role (zero grants) in v1.

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
      -- APP 009 reserved (name-only; NOT granted to any role):
      -- 'release.schedule','release.supersede','release.ai_suggest',
      -- 'release.ai_classify','release.audit_export','release.recall'
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
  'AUTH capability primer. Extended by REQUIREMENTS 003 with 5 requirement.* keys. APP 008 reserves requirement.ai_suggest/ai_classify/import/auto_assess by name only (no role grants). APP 009 reserves release.schedule/supersede/ai_suggest/ai_classify/audit_export/recall by name only (no role grants).';

------------------------------------------------------------------------------
-- 2. get_release — Release Detail read (§13.1)
------------------------------------------------------------------------------

create or replace function public.get_release(p_release_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_r          public.releases%rowtype;
  v_item_count int;
  v_chain_len  int;
  v_chain_pos  int;
  v_root_id    uuid;
begin
  select * into v_r from public.releases where id = p_release_id;
  if v_r.id is null then
    return null;
  end if;
  if not public.lign_has_capability(v_r.project_id, v_r.workspace_id, 'release.view') then
    raise exception 'get_release: forbidden (release.view)' using errcode='42501';
  end if;

  select count(*) into v_item_count from public.release_items where release_id = p_release_id;

  v_root_id := coalesce(v_r.root_release_id, v_r.id);
  with recursive chain(id, prev_id, depth) as (
    select v_root_id, null::uuid, 1
    union all
    select r.id, c.id, c.depth + 1
      from chain c
      join public.releases r on r.superseded_by_release_id = c.id
     where r.project_id = v_r.project_id
  )
  select count(*)::int into v_chain_len from chain;

  with recursive chain(id, depth) as (
    select v_root_id, 1
    union all
    select r.id, c.depth + 1
      from chain c
      join public.releases r on r.superseded_by_release_id = c.id
     where r.project_id = v_r.project_id
  )
  select depth into v_chain_pos from chain where id = v_r.id;

  return jsonb_build_object(
    'id', v_r.id,
    'workspace_id', v_r.workspace_id,
    'project_id', v_r.project_id,
    'name', v_r.name,
    'notes', v_r.notes,
    'channel', v_r.channel,
    'release_type', v_r.release_type,
    'status', v_r.status,
    'code', v_r.code,
    'effective_at', v_r.effective_at,
    'released_at', v_r.released_at,
    'withdrawn_at', v_r.withdrawn_at,
    'withdrawn_reason', v_r.withdrawn_reason,
    'created_by_profile_id', v_r.created_by_profile_id,
    'published_by_profile_id', v_r.published_by_profile_id,
    'created_at', v_r.created_at,
    'updated_at', v_r.updated_at,
    'discarded_at', v_r.discarded_at,
    'superseded_by_release_id', v_r.superseded_by_release_id,
    'root_release_id', v_r.root_release_id,
    'item_count', v_item_count,
    'chain_length', v_chain_len,
    'chain_position', coalesce(v_chain_pos, 1)
  );
end $$;

revoke all on function public.get_release(uuid) from public;
revoke all on function public.get_release(uuid) from anon;
grant execute on function public.get_release(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 3. get_release_by_code — Deep-link resolver (§13.2)
------------------------------------------------------------------------------

create or replace function public.get_release_by_code(
  p_project_id uuid,
  p_ws_id uuid,
  p_code text
)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if not public.lign_has_capability(p_project_id, p_ws_id, 'release.view') then
    raise exception 'get_release_by_code: forbidden (release.view)' using errcode='42501';
  end if;
  select id into v_id
    from public.releases
   where project_id = p_project_id
     and workspace_id = p_ws_id
     and code = p_code;
  if v_id is null then
    return null;
  end if;
  return public.get_release(v_id);
end $$;

revoke all on function public.get_release_by_code(uuid, uuid, text) from public;
revoke all on function public.get_release_by_code(uuid, uuid, text) from anon;
grant execute on function public.get_release_by_code(uuid, uuid, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 4. get_release_chain — Supersession chain root->head (§13.3)
------------------------------------------------------------------------------

create or replace function public.get_release_chain(p_release_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_r       public.releases%rowtype;
  v_root_id uuid;
  v_arr     jsonb;
begin
  select * into v_r from public.releases where id = p_release_id;
  if v_r.id is null then
    return jsonb_build_object('nodes', '[]'::jsonb);
  end if;
  if not public.lign_has_capability(v_r.project_id, v_r.workspace_id, 'release.view') then
    raise exception 'get_release_chain: forbidden (release.view)' using errcode='42501';
  end if;

  v_root_id := coalesce(v_r.root_release_id, v_r.id);

  with recursive walk(id, superseded_by_release_id, depth) as (
    select v_root_id, null::uuid, 0
    union all
    select r.id, r.superseded_by_release_id, w.depth + 1
      from walk w
      join public.releases r on r.superseded_by_release_id = w.id
     where r.project_id = v_r.project_id
  ),
  nodes as (
    select r.id as release_id,
           r.code,
           r.name,
           r.release_type,
           r.status,
           r.released_at,
           r.withdrawn_at,
           w.depth,
           (w.depth = 0) as is_root,
           (r.superseded_by_release_id is null) as is_head
      from walk w
      join public.releases r on r.id = w.id
  )
  select jsonb_agg(
           jsonb_build_object(
             'release_id', release_id,
             'code', code,
             'name', name,
             'release_type', release_type,
             'status', status,
             'released_at', released_at,
             'withdrawn_at', withdrawn_at,
             'is_root', is_root,
             'is_head', is_head
           ) order by depth asc
         )
    into v_arr
    from nodes;

  return jsonb_build_object('nodes', coalesce(v_arr, '[]'::jsonb));
end $$;

revoke all on function public.get_release_chain(uuid) from public;
revoke all on function public.get_release_chain(uuid) from anon;
grant execute on function public.get_release_chain(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 5. get_release_evidence — Evidence tab (§13.4)
------------------------------------------------------------------------------

create or replace function public.get_release_evidence(p_release_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_r         public.releases%rowtype;
  v_delta_arr jsonb;
begin
  select * into v_r from public.releases where id = p_release_id;
  if v_r.id is null then
    return null;
  end if;
  if not public.lign_has_capability(v_r.project_id, v_r.workspace_id, 'release.view') then
    raise exception 'get_release_evidence: forbidden (release.view)' using errcode='42501';
  end if;

  -- Compute per-item live_delta (or live re-computation if no snapshot).
  with items as (
    select ri.id            as release_item_id,
           ri.design_asset_id,
           ri.version_id as version_id
      from public.release_items ri
     where ri.release_id = p_release_id
  ),
  computed as (
    select i.release_item_id,
           i.design_asset_id,
           i.version_id,
           public.get_approval_readiness(i.version_id)          as approval_current,
           public.get_release_readiness_for_version(i.version_id) as requirement_current
      from items i
  )
  select jsonb_agg(
           jsonb_build_object(
             'release_item_id', release_item_id,
             'design_asset_id', design_asset_id,
             'version_id', version_id,
             'approval_current', approval_current,
             'requirement_current', requirement_current
           )
         )
    into v_delta_arr
    from computed;

  return jsonb_build_object(
    'snapshot', v_r.evidence_snapshot,
    'live_delta', jsonb_build_object('items', coalesce(v_delta_arr, '[]'::jsonb)),
    'has_deltas', (v_r.evidence_snapshot is not null)
  );
end $$;

revoke all on function public.get_release_evidence(uuid) from public;
revoke all on function public.get_release_evidence(uuid) from anon;
grant execute on function public.get_release_evidence(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 6. get_release_comparison — Comparison tab (§13.5)
------------------------------------------------------------------------------

create or replace function public.get_release_comparison(
  p_release_id uuid,
  p_compare_to_release_id uuid default null
)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_this     public.releases%rowtype;
  v_other    public.releases%rowtype;
  v_other_id uuid;
  v_this_json jsonb;
  v_other_json jsonb;
  v_added   jsonb;
  v_removed jsonb;
  v_changed jsonb;
begin
  select * into v_this from public.releases where id = p_release_id;
  if v_this.id is null then
    return null;
  end if;
  if not public.lign_has_capability(v_this.project_id, v_this.workspace_id, 'release.view') then
    raise exception 'get_release_comparison: forbidden (release.view)' using errcode='42501';
  end if;

  v_other_id := p_compare_to_release_id;
  if v_other_id is null then
    -- Default: one step back in chain (the release this one supersedes).
    select id into v_other_id
      from public.releases
     where superseded_by_release_id = v_this.id
       and project_id = v_this.project_id
     limit 1;
  end if;

  if v_other_id is not null then
    select * into v_other from public.releases where id = v_other_id;
    if v_other.id is null then
      v_other_id := null;
    elsif v_other.project_id <> v_this.project_id then
      raise exception 'get_release_comparison: releases must be same project' using errcode='23514';
    end if;
  end if;

  v_this_json  := public.get_release(v_this.id);
  v_other_json := case when v_other_id is not null then public.get_release(v_other_id) else null end;

  with this_items as (
    select design_asset_id, version_id
      from public.release_items where release_id = v_this.id
  ),
  other_items as (
    select design_asset_id, version_id
      from public.release_items where release_id = coalesce(v_other_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ),
  added as (
    select ti.design_asset_id, ti.version_id
      from this_items ti
     where not exists (select 1 from other_items oi where oi.design_asset_id = ti.design_asset_id)
  ),
  removed as (
    select oi.design_asset_id, oi.version_id
      from other_items oi
     where not exists (select 1 from this_items ti where ti.design_asset_id = oi.design_asset_id)
  ),
  changed as (
    select ti.design_asset_id, ti.version_id as this_version_id, oi.version_id as compare_version_id
      from this_items ti
      join other_items oi on oi.design_asset_id = ti.design_asset_id
     where ti.version_id <> oi.version_id
  )
  select
    (select coalesce(jsonb_agg(jsonb_build_object('design_asset_id', design_asset_id, 'version_id', version_id)), '[]'::jsonb) from added),
    (select coalesce(jsonb_agg(jsonb_build_object('design_asset_id', design_asset_id, 'version_id', version_id)), '[]'::jsonb) from removed),
    (select coalesce(jsonb_agg(jsonb_build_object('design_asset_id', design_asset_id, 'this_version_id', this_version_id, 'compare_version_id', compare_version_id)), '[]'::jsonb) from changed)
    into v_added, v_removed, v_changed;

  return jsonb_build_object(
    'this_release', v_this_json,
    'compare_to', v_other_json,
    'item_diff', jsonb_build_object(
      'added', v_added,
      'removed', v_removed,
      'changed_version', v_changed
    )
  );
end $$;

revoke all on function public.get_release_comparison(uuid, uuid) from public;
revoke all on function public.get_release_comparison(uuid, uuid) from anon;
grant execute on function public.get_release_comparison(uuid, uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 7. list_release_activity — History tab (§13.6, per L-2 concrete filter)
------------------------------------------------------------------------------

create or replace function public.list_release_activity(
  p_release_id uuid,
  p_cursor_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 25
)
returns table (
  out_id uuid,
  out_event_type text,
  out_occurred_at timestamptz,
  out_actor_profile_id uuid,
  out_subject_kind text,
  out_subject_id uuid,
  out_subject_label text,
  out_subject_snapshot jsonb,
  out_payload jsonb
)
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_ws uuid;
  v_pj uuid;
begin
  select workspace_id, project_id into v_ws, v_pj from public.releases where id = p_release_id;
  if v_ws is null then
    return;
  end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.view') then
    raise exception 'list_release_activity: forbidden (release.view)' using errcode='42501';
  end if;

  return query
    select ae.id,
           ae.event_type,
           ae.occurred_at,
           ae.actor_profile_id,
           ae.subject_kind,
           ae.subject_id,
           ae.subject_label,
           ae.subject_snapshot,
           ae.payload
      from public.activity_events ae
     where ae.workspace_id = v_ws
       and (
             (ae.subject_kind = 'release' and ae.subject_id = p_release_id)
          or (ae.subject_kind = 'release_item'
              and ae.subject_id in (select id from public.release_items where release_id = p_release_id))
       )
       and (p_cursor_at is null
            or ae.occurred_at < p_cursor_at
            or (ae.occurred_at = p_cursor_at and ae.id < coalesce(p_cursor_id, '00000000-0000-0000-0000-000000000000'::uuid)))
     order by ae.occurred_at desc, ae.id desc
     limit greatest(1, least(coalesce(p_limit, 25), 200));
end $$;

revoke all on function public.list_release_activity(uuid, timestamptz, uuid, integer) from public;
revoke all on function public.list_release_activity(uuid, timestamptz, uuid, integer) from anon;
grant execute on function public.list_release_activity(uuid, timestamptz, uuid, integer) to authenticated, service_role;

------------------------------------------------------------------------------
-- 8. list_release_items — Overview/composer body (§13.7)
------------------------------------------------------------------------------

create or replace function public.list_release_items(p_release_id uuid)
returns table (
  out_release_item_id uuid,
  out_design_asset_id uuid,
  out_design_asset_name text,
  out_version_id uuid,
  out_version_sequence integer,
  out_version_published_at timestamptz,
  out_notes text,
  out_sort_order integer,
  out_approval_state jsonb,
  out_requirement_readiness_summary jsonb
)
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_ws uuid;
  v_pj uuid;
begin
  select workspace_id, project_id into v_ws, v_pj from public.releases where id = p_release_id;
  if v_ws is null then
    return;
  end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.view') then
    raise exception 'list_release_items: forbidden (release.view)' using errcode='42501';
  end if;

  return query
    select ri.id,
           ri.design_asset_id,
           da.name,
           ri.version_id,
           av.sequence,
           av.published_at,
           ri.notes,
           ri.sort_order,
           public.get_approval_readiness(ri.version_id),
           public.get_release_readiness_for_version(ri.version_id)
      from public.release_items ri
      join public.design_assets  da on da.id = ri.design_asset_id
      join public.asset_versions av on av.id = ri.version_id
     where ri.release_id = p_release_id
     order by ri.sort_order asc, ri.created_at asc;
end $$;

revoke all on function public.list_release_items(uuid) from public;
revoke all on function public.list_release_items(uuid) from anon;
grant execute on function public.list_release_items(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 9. list_releases_dashboard — Paginated dashboard read (§13.8)
------------------------------------------------------------------------------

create or replace function public.list_releases_dashboard(
  p_ws_id uuid,
  p_proj_id uuid default null,
  p_view text default 'all',
  p_status_filter text[] default null,
  p_release_type_filter text[] default null,
  p_published_by_ids uuid[] default null,
  p_search text default null,
  p_include_discarded boolean default false,
  p_cursor_released_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 25,
  p_saved_view_id uuid default null
)
returns table (
  out_release_id uuid,
  out_workspace_id uuid,
  out_project_id uuid,
  out_project_name text,
  out_code text,
  out_name text,
  out_release_type text,
  out_status text,
  out_channel text,
  out_released_at timestamptz,
  out_withdrawn_at timestamptz,
  out_discarded_at timestamptz,
  out_created_by_profile_id uuid,
  out_published_by_profile_id uuid,
  out_created_at timestamptz,
  out_updated_at timestamptz,
  out_item_count integer,
  out_next_cursor_at timestamptz,
  out_next_cursor_id uuid
)
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_caller uuid;
  v_saved  jsonb;
  v_view   text := coalesce(p_view, 'all');
  v_lim    integer := greatest(1, least(coalesce(p_limit, 25), 200));
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'list_releases_dashboard: authentication required' using errcode='42501';
  end if;

  if p_proj_id is not null then
    if not public.lign_has_capability(p_proj_id, p_ws_id, 'release.view') then
      raise exception 'list_releases_dashboard: forbidden (release.view)' using errcode='42501';
    end if;
  end if;

  if p_saved_view_id is not null then
    select payload into v_saved
      from public.user_saved_views
     where id = p_saved_view_id and workspace_id = p_ws_id and profile_id = v_caller;
    if v_saved is null then
      raise exception 'list_releases_dashboard: saved view not found' using errcode='23503';
    end if;
  end if;

  return query
    select r.id                       as out_release_id,
           r.workspace_id             as out_workspace_id,
           r.project_id               as out_project_id,
           p.name                     as out_project_name,
           r.code                     as out_code,
           r.name                     as out_name,
           r.release_type             as out_release_type,
           r.status                   as out_status,
           r.channel                  as out_channel,
           r.released_at              as out_released_at,
           r.withdrawn_at             as out_withdrawn_at,
           r.discarded_at             as out_discarded_at,
           r.created_by_profile_id    as out_created_by_profile_id,
           r.published_by_profile_id  as out_published_by_profile_id,
           r.created_at               as out_created_at,
           r.updated_at               as out_updated_at,
           (select count(*)::int from public.release_items ri where ri.release_id = r.id) as out_item_count,
           r.released_at              as out_next_cursor_at,
           r.id                       as out_next_cursor_id
      from public.releases r
      join public.projects p on p.id = r.project_id
     where r.workspace_id = p_ws_id
       and (p_proj_id is null or r.project_id = p_proj_id)
       and (p_proj_id is not null or public.lign_has_capability(r.project_id, r.workspace_id, 'release.view'))
       and (v_view <> 'draft'          or r.status = 'draft')
       and (v_view <> 'released'       or r.status = 'released')
       and (v_view <> 'withdrawn'      or r.status = 'withdrawn')
       and (v_view <> 'discarded'      or r.discarded_at is not null)
       and (v_view <> 'published_by_me' or r.published_by_profile_id = v_caller)
       and (p_include_discarded or v_view = 'discarded' or r.discarded_at is null)
       and (p_status_filter is null or r.status = any (p_status_filter))
       and (p_release_type_filter is null or r.release_type = any (p_release_type_filter))
       and (p_published_by_ids is null or r.published_by_profile_id = any (p_published_by_ids))
       and (p_search is null
            or r.name ilike '%' || p_search || '%'
            or (r.code is not null and r.code ilike '%' || p_search || '%'))
       and (p_cursor_released_at is null
            or (r.released_at is not null and (r.released_at < p_cursor_released_at
                or (r.released_at = p_cursor_released_at and r.id < coalesce(p_cursor_id, '00000000-0000-0000-0000-000000000000'::uuid))))
            or (r.released_at is null and p_cursor_released_at is null))
     order by r.released_at desc nulls last, r.id desc
     limit v_lim;
end $$;

revoke all on function public.list_releases_dashboard(
  uuid, uuid, text, text[], text[], uuid[], text, boolean, timestamptz, uuid, integer, uuid
) from public;
revoke all on function public.list_releases_dashboard(
  uuid, uuid, text, text[], text[], uuid[], text, boolean, timestamptz, uuid, integer, uuid
) from anon;
grant execute on function public.list_releases_dashboard(
  uuid, uuid, text, text[], text[], uuid[], text, boolean, timestamptz, uuid, integer, uuid
) to authenticated, service_role;

------------------------------------------------------------------------------
-- 10. get_release_inbox_count — NavRail badge (§13.9)
------------------------------------------------------------------------------

create or replace function public.get_release_inbox_count(p_ws_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_released_30d int;
  v_draft int;
  v_per_project jsonb;
begin
  if auth.uid() is null then
    raise exception 'get_release_inbox_count: authentication required' using errcode='42501';
  end if;

  select coalesce(sum(case when r.status='released' and r.released_at >= (now() - interval '30 days') then 1 else 0 end), 0)::int,
         coalesce(sum(case when r.status='draft' and r.discarded_at is null then 1 else 0 end), 0)::int
    into v_released_30d, v_draft
    from public.releases r
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'release.view');

  with per as (
    select r.project_id,
           sum(case when r.status='released' and r.released_at >= (now() - interval '30 days') then 1 else 0 end)::int as released_trailing_30d
      from public.releases r
     where r.workspace_id = p_ws_id
       and public.lign_has_capability(r.project_id, r.workspace_id, 'release.view')
     group by r.project_id
  )
  select jsonb_agg(jsonb_build_object('project_id', project_id, 'released_trailing_30d', released_trailing_30d))
    into v_per_project
    from per;

  return jsonb_build_object(
    'workspace_released_trailing_30d', v_released_30d,
    'workspace_draft_count', v_draft,
    'per_project', coalesce(v_per_project, '[]'::jsonb)
  );
end $$;

revoke all on function public.get_release_inbox_count(uuid) from public;
revoke all on function public.get_release_inbox_count(uuid) from anon;
grant execute on function public.get_release_inbox_count(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 11. get_project_release_metrics — Project metrics strip (§13.10)
------------------------------------------------------------------------------

create or replace function public.get_project_release_metrics(p_project_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_ws uuid;
  v_result jsonb;
begin
  select workspace_id into v_ws from public.projects where id = p_project_id;
  if v_ws is null then
    return null;
  end if;
  if not public.lign_has_capability(p_project_id, v_ws, 'release.view') then
    raise exception 'get_project_release_metrics: forbidden (release.view)' using errcode='42501';
  end if;

  select jsonb_build_object(
    'total_draft', coalesce(sum(case when status='draft' then 1 else 0 end), 0)::int,
    'total_released', coalesce(sum(case when status='released' then 1 else 0 end), 0)::int,
    'total_withdrawn', coalesce(sum(case when status='withdrawn' then 1 else 0 end), 0)::int,
    'released_trailing_30d', coalesce(sum(case when status='released' and released_at >= (now() - interval '30 days') then 1 else 0 end), 0)::int,
    'released_trailing_90d', coalesce(sum(case when status='released' and released_at >= (now() - interval '90 days') then 1 else 0 end), 0)::int,
    'by_type', jsonb_build_object(
      'internal',   coalesce(sum(case when release_type='internal' then 1 else 0 end), 0)::int,
      'preview',    coalesce(sum(case when release_type='preview' then 1 else 0 end), 0)::int,
      'client',     coalesce(sum(case when release_type='client' then 1 else 0 end), 0)::int,
      'regulatory', coalesce(sum(case when release_type='regulatory' then 1 else 0 end), 0)::int,
      'final',      coalesce(sum(case when release_type='final' then 1 else 0 end), 0)::int,
      'patch',      coalesce(sum(case when release_type='patch' then 1 else 0 end), 0)::int,
      'hotfix',     coalesce(sum(case when release_type='hotfix' then 1 else 0 end), 0)::int
    ),
    'chain_head_count', coalesce(sum(case when superseded_by_release_id is null and status='released' then 1 else 0 end), 0)::int,
    'discarded_count', coalesce(sum(case when discarded_at is not null then 1 else 0 end), 0)::int
  ) into v_result
  from public.releases
  where project_id = p_project_id;

  return v_result;
end $$;

revoke all on function public.get_project_release_metrics(uuid) from public;
revoke all on function public.get_project_release_metrics(uuid) from anon;
grant execute on function public.get_project_release_metrics(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 12. get_workspace_release_metrics — Workspace metrics strip (§13.11)
------------------------------------------------------------------------------

create or replace function public.get_workspace_release_metrics(p_ws_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_top5   jsonb;
begin
  if auth.uid() is null then
    raise exception 'get_workspace_release_metrics: authentication required' using errcode='42501';
  end if;

  select jsonb_build_object(
    'total_draft', coalesce(sum(case when status='draft' then 1 else 0 end), 0)::int,
    'total_released', coalesce(sum(case when status='released' then 1 else 0 end), 0)::int,
    'total_withdrawn', coalesce(sum(case when status='withdrawn' then 1 else 0 end), 0)::int,
    'released_trailing_30d', coalesce(sum(case when status='released' and released_at >= (now() - interval '30 days') then 1 else 0 end), 0)::int,
    'released_trailing_90d', coalesce(sum(case when status='released' and released_at >= (now() - interval '90 days') then 1 else 0 end), 0)::int,
    'by_type', jsonb_build_object(
      'internal',   coalesce(sum(case when release_type='internal' then 1 else 0 end), 0)::int,
      'preview',    coalesce(sum(case when release_type='preview' then 1 else 0 end), 0)::int,
      'client',     coalesce(sum(case when release_type='client' then 1 else 0 end), 0)::int,
      'regulatory', coalesce(sum(case when release_type='regulatory' then 1 else 0 end), 0)::int,
      'final',      coalesce(sum(case when release_type='final' then 1 else 0 end), 0)::int,
      'patch',      coalesce(sum(case when release_type='patch' then 1 else 0 end), 0)::int,
      'hotfix',     coalesce(sum(case when release_type='hotfix' then 1 else 0 end), 0)::int
    ),
    'chain_head_count', coalesce(sum(case when superseded_by_release_id is null and status='released' then 1 else 0 end), 0)::int,
    'discarded_count', coalesce(sum(case when discarded_at is not null then 1 else 0 end), 0)::int
  ) into v_result
  from public.releases r
  where r.workspace_id = p_ws_id
    and public.lign_has_capability(r.project_id, r.workspace_id, 'release.view');

  with per as (
    select r.project_id,
           sum(case when r.status='released' and r.released_at >= (now() - interval '30 days') then 1 else 0 end)::int as released_trailing_30d
      from public.releases r
     where r.workspace_id = p_ws_id
       and public.lign_has_capability(r.project_id, r.workspace_id, 'release.view')
     group by r.project_id
     order by released_trailing_30d desc
     limit 5
  )
  select jsonb_agg(jsonb_build_object('project_id', project_id, 'released_trailing_30d', released_trailing_30d))
    into v_top5
    from per;

  return v_result || jsonb_build_object('per_project_top5', coalesce(v_top5, '[]'::jsonb));
end $$;

revoke all on function public.get_workspace_release_metrics(uuid) from public;
revoke all on function public.get_workspace_release_metrics(uuid) from anon;
grant execute on function public.get_workspace_release_metrics(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 13. list_releases_for_asset (§13.12)
------------------------------------------------------------------------------

create or replace function public.list_releases_for_asset(p_design_asset_id uuid)
returns table (
  out_release_id uuid,
  out_code text,
  out_name text,
  out_release_type text,
  out_status text,
  out_released_at timestamptz,
  out_version_id uuid,
  out_version_sequence integer
)
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_ws uuid;
  v_pj uuid;
begin
  select workspace_id, project_id into v_ws, v_pj from public.design_assets where id = p_design_asset_id;
  if v_ws is null then
    return;
  end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.view') then
    raise exception 'list_releases_for_asset: forbidden (release.view)' using errcode='42501';
  end if;

  return query
    select r.id, r.code, r.name, r.release_type, r.status, r.released_at,
           ri.version_id, av.sequence
      from public.release_items ri
      join public.releases      r  on r.id = ri.release_id
      join public.asset_versions av on av.id = ri.version_id
     where ri.design_asset_id = p_design_asset_id
     order by r.released_at desc nulls last, r.id desc;
end $$;

revoke all on function public.list_releases_for_asset(uuid) from public;
revoke all on function public.list_releases_for_asset(uuid) from anon;
grant execute on function public.list_releases_for_asset(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 14. list_releases_for_version (§13.13)
------------------------------------------------------------------------------

create or replace function public.list_releases_for_version(p_version_id uuid)
returns table (
  out_release_id uuid,
  out_code text,
  out_name text,
  out_release_type text,
  out_status text,
  out_released_at timestamptz,
  out_version_id uuid,
  out_version_sequence integer
)
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_ws uuid;
  v_pj uuid;
begin
  select workspace_id, project_id into v_ws, v_pj from public.asset_versions where id = p_version_id;
  if v_ws is null then
    return;
  end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.view') then
    raise exception 'list_releases_for_version: forbidden (release.view)' using errcode='42501';
  end if;

  return query
    select r.id, r.code, r.name, r.release_type, r.status, r.released_at,
           ri.version_id, av.sequence
      from public.release_items ri
      join public.releases      r  on r.id = ri.release_id
      join public.asset_versions av on av.id = ri.version_id
     where ri.version_id = p_version_id
     order by r.released_at desc nulls last, r.id desc;
end $$;

revoke all on function public.list_releases_for_version(uuid) from public;
revoke all on function public.list_releases_for_version(uuid) from anon;
grant execute on function public.list_releases_for_version(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 15. get_release_readiness_for_publish — Publish preflight (§13.14)
------------------------------------------------------------------------------

create or replace function public.get_release_readiness_for_publish(
  p_design_asset_id uuid,
  p_version_id uuid,
  p_release_type text
)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_ws uuid;
  v_pj uuid;
  v_approval jsonb;
  v_req jsonb;
  v_review_count int;
  v_blockers jsonb := '[]'::jsonb;
  v_can boolean := true;
begin
  select workspace_id, project_id into v_ws, v_pj from public.design_assets where id = p_design_asset_id;
  if v_ws is null then
    return jsonb_build_object('can_publish', false,
      'blocking_conditions', jsonb_build_array(jsonb_build_object('code','asset_not_found','message','Design asset not found','source','evidence')),
      'approval_evidence', null, 'requirement_evidence', null, 'review_evidence', null);
  end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.view') then
    raise exception 'get_release_readiness_for_publish: forbidden (release.view)' using errcode='42501';
  end if;

  v_approval := public.get_approval_readiness(p_version_id);
  v_req      := public.get_release_readiness_for_version(p_version_id);

  select count(*)::int into v_review_count
    from public.reviews rv
   where rv.version_id = p_version_id and rv.status = 'completed';

  if v_approval is null or coalesce((v_approval->>'has_approved')::boolean, false) is not true then
    v_can := false;
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code','no_approved_request',
      'message','No approved approval request for this version.',
      'source','approval'));
  end if;

  if p_release_type in ('regulatory','final') then
    if v_req is not null and coalesce((v_req->>'critical_unsatisfied_count')::int, 0) > 0 then
      v_can := false;
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'code','critical_requirements_unsatisfied',
        'message','Regulatory / final releases require zero critical unsatisfied requirements.',
        'source','requirement'));
    end if;
    if v_req is not null and coalesce((v_req->>'critical_unassessed_count')::int, 0) > 0 then
      v_can := false;
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'code','critical_requirements_unassessed',
        'message','Regulatory / final releases require zero critical unassessed requirements.',
        'source','requirement'));
    end if;
  elsif p_release_type = 'client' then
    if v_req is not null and coalesce((v_req->>'critical_unsatisfied_count')::int, 0) > 0 then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'code','client_release_has_critical_unsat',
        'message','Client release has critical unsatisfied requirements (soft warning).',
        'source','requirement'));
    end if;
  end if;

  return jsonb_build_object(
    'can_publish', v_can,
    'blocking_conditions', v_blockers,
    'approval_evidence', v_approval,
    'requirement_evidence', v_req,
    'review_evidence', jsonb_build_object('completed_review_count', v_review_count)
  );
end $$;

revoke all on function public.get_release_readiness_for_publish(uuid, uuid, text) from public;
revoke all on function public.get_release_readiness_for_publish(uuid, uuid, text) from anon;
grant execute on function public.get_release_readiness_for_publish(uuid, uuid, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 16. create_release_draft — write RPC (§14.1)
------------------------------------------------------------------------------

create or replace function public.create_release_draft(
  p_project_id uuid,
  p_name text,
  p_notes text default null,
  p_channel text default null,
  p_release_type text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid;
  v_ws uuid;
  v_id uuid;
  v_next_ord int;
  v_code text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'create_release_draft: authentication required' using errcode='42501';
  end if;

  select workspace_id into v_ws from public.projects where id = p_project_id;
  if v_ws is null then
    raise exception 'create_release_draft: project not found' using errcode='23503';
  end if;
  if not public.lign_has_capability(p_project_id, v_ws, 'release.create') then
    raise exception 'create_release_draft: forbidden (release.create)' using errcode='42501';
  end if;

  if p_release_type is not null and p_release_type not in
    ('internal','preview','client','regulatory','final','patch','hotfix') then
    raise exception 'create_release_draft: invalid release_type %', p_release_type using errcode='23514';
  end if;

  -- Advisory-lock ordinal (R-NNN) — per-project.
  perform pg_advisory_xact_lock(hashtext('release_code:' || p_project_id::text));
  select coalesce(max((regexp_match(code, 'R-([0-9]+)'))[1]::int), 0) + 1
    into v_next_ord
    from public.releases
   where project_id = p_project_id
     and code is not null;
  v_code := 'R-' || lpad(v_next_ord::text, 3, '0');

  v_id := gen_random_uuid();

  insert into public.releases (
    id, workspace_id, project_id, name, notes, channel, status,
    created_by_profile_id, release_type, code
  ) values (
    v_id, v_ws, p_project_id, p_name, p_notes, p_channel, 'draft',
    v_caller, p_release_type, v_code
  );

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, p_project_id, now(), 'release.created',
    v_caller, 'user',
    'release', v_id, p_name,
    jsonb_build_object(
      'name', p_name,
      'release_type', p_release_type,
      'code', v_code,
      'created_by_profile_id', v_caller,
      'channel', p_channel
    ),
    '{}'::jsonb
  );

  return v_id;
end $$;

revoke all on function public.create_release_draft(uuid, text, text, text, text) from public;
revoke all on function public.create_release_draft(uuid, text, text, text, text) from anon;
grant execute on function public.create_release_draft(uuid, text, text, text, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 17. add_release_item — write RPC (§14.2)
------------------------------------------------------------------------------

create or replace function public.add_release_item(
  p_release_id uuid,
  p_design_asset_id uuid,
  p_version_id uuid,
  p_notes text default null,
  p_sort_order integer default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid;
  v_ws uuid;
  v_pj uuid;
  v_status text;
  v_release_type text;
  v_item_id uuid;
  v_sort int;
  v_asset_name text;
  v_ver_seq int;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'add_release_item: authentication required' using errcode='42501';
  end if;
  select workspace_id, project_id, status, release_type
    into v_ws, v_pj, v_status, v_release_type
    from public.releases where id = p_release_id for update;
  if v_ws is null then
    raise exception 'add_release_item: release not found' using errcode='23503';
  end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.create') then
    raise exception 'add_release_item: forbidden (release.create)' using errcode='42501';
  end if;
  if v_status <> 'draft' then
    raise exception 'add_release_item: parent release is % (must be draft)', v_status using errcode='23514';
  end if;

  if p_sort_order is null then
    select coalesce(max(sort_order), 0) + 1 into v_sort
      from public.release_items where release_id = p_release_id;
  else
    v_sort := p_sort_order;
  end if;

  v_item_id := gen_random_uuid();
  insert into public.release_items (
    id, workspace_id, release_id, design_asset_id, version_id, sort_order, notes
  ) values (
    v_item_id, v_ws, p_release_id, p_design_asset_id, p_version_id, v_sort, p_notes
  );

  select name into v_asset_name from public.design_assets where id = p_design_asset_id;
  select sequence into v_ver_seq from public.asset_versions where id = p_version_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_pj, now(), 'release.item_added',
    v_caller, 'user',
    'release_item', v_item_id, v_asset_name,
    jsonb_build_object(
      'release_id', p_release_id,
      'asset_id', p_design_asset_id,
      'asset_name', v_asset_name,
      'version_id', p_version_id,
      'version_sequence', v_ver_seq,
      'release_type', v_release_type,
      'item_id', v_item_id,
      'sort_order', v_sort,
      'notes_snippet', case when p_notes is null then null else substr(p_notes, 1, 200) end
    ),
    '{}'::jsonb
  );

  return v_item_id;
end $$;

revoke all on function public.add_release_item(uuid, uuid, uuid, text, integer) from public;
revoke all on function public.add_release_item(uuid, uuid, uuid, text, integer) from anon;
grant execute on function public.add_release_item(uuid, uuid, uuid, text, integer) to authenticated, service_role;

------------------------------------------------------------------------------
-- 18. remove_release_item — write RPC (§14.3)
------------------------------------------------------------------------------

create or replace function public.remove_release_item(
  p_release_id uuid,
  p_version_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid;
  v_ws uuid;
  v_pj uuid;
  v_status text;
  v_release_type text;
  v_item_id uuid;
  v_asset_id uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'remove_release_item: authentication required' using errcode='42501';
  end if;
  select workspace_id, project_id, status, release_type
    into v_ws, v_pj, v_status, v_release_type
    from public.releases where id = p_release_id for update;
  if v_ws is null then
    raise exception 'remove_release_item: release not found' using errcode='23503';
  end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.create') then
    raise exception 'remove_release_item: forbidden (release.create)' using errcode='42501';
  end if;
  if v_status <> 'draft' then
    raise exception 'remove_release_item: parent release is % (must be draft)', v_status using errcode='23514';
  end if;

  select id, design_asset_id into v_item_id, v_asset_id
    from public.release_items
   where release_id = p_release_id and version_id = p_version_id;
  if v_item_id is null then
    raise exception 'remove_release_item: item not found' using errcode='23503';
  end if;

  delete from public.release_items where id = v_item_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_pj, now(), 'release.item_removed',
    v_caller, 'user',
    'release_item', v_item_id, null,
    jsonb_build_object(
      'release_id', p_release_id,
      'asset_id', v_asset_id,
      'version_id', p_version_id,
      'release_type', v_release_type,
      'item_id', v_item_id
    ),
    '{}'::jsonb
  );

  return v_item_id;
end $$;

revoke all on function public.remove_release_item(uuid, uuid) from public;
revoke all on function public.remove_release_item(uuid, uuid) from anon;
grant execute on function public.remove_release_item(uuid, uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 19. reorder_release_items — write RPC (§14.7)
------------------------------------------------------------------------------

create or replace function public.reorder_release_items(
  p_release_id uuid,
  p_ordered_version_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid;
  v_ws uuid;
  v_pj uuid;
  v_status text;
  v_expected int;
  v_actual int;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'reorder_release_items: authentication required' using errcode='42501';
  end if;
  select workspace_id, project_id, status
    into v_ws, v_pj, v_status
    from public.releases where id = p_release_id for update;
  if v_ws is null then
    raise exception 'reorder_release_items: release not found' using errcode='23503';
  end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.create') then
    raise exception 'reorder_release_items: forbidden (release.create)' using errcode='42501';
  end if;
  if v_status <> 'draft' then
    raise exception 'reorder_release_items: parent release is % (must be draft)', v_status using errcode='23514';
  end if;

  v_expected := coalesce(array_length(p_ordered_version_ids, 1), 0);
  select count(*) into v_actual from public.release_items where release_id = p_release_id;
  if v_expected <> v_actual then
    raise exception 'reorder_release_items: array length % does not match item count %', v_expected, v_actual using errcode='23514';
  end if;

  -- Verify each version_id is actually an item of this release.
  if exists (
    select 1 from unnest(p_ordered_version_ids) v(id)
     where not exists (
       select 1 from public.release_items
        where release_id = p_release_id and version_id = v.id
     )
  ) then
    raise exception 'reorder_release_items: array contains version_id(s) not in release' using errcode='23514';
  end if;

  -- Two-phase: bump to negative range first (avoid unique-key collision on sort_order).
  update public.release_items set sort_order = -sort_order - 1
   where release_id = p_release_id;

  -- Rewrite sort_order using array ordinality.
  update public.release_items ri
     set sort_order = ord.i::int
    from unnest(p_ordered_version_ids) with ordinality as ord(vid, i)
   where ri.release_id = p_release_id and ri.version_id = ord.vid;

  return v_expected;
end $$;

revoke all on function public.reorder_release_items(uuid, uuid[]) from public;
revoke all on function public.reorder_release_items(uuid, uuid[]) from anon;
grant execute on function public.reorder_release_items(uuid, uuid[]) to authenticated, service_role;

------------------------------------------------------------------------------
-- 20. discard_release_draft — write RPC (§14.6)
------------------------------------------------------------------------------

create or replace function public.discard_release_draft(p_release_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid;
  v_ws uuid;
  v_pj uuid;
  v_status text;
  v_discarded timestamptz;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'discard_release_draft: authentication required' using errcode='42501';
  end if;
  select workspace_id, project_id, status, discarded_at
    into v_ws, v_pj, v_status, v_discarded
    from public.releases where id = p_release_id for update;
  if v_ws is null then
    raise exception 'discard_release_draft: release not found' using errcode='23503';
  end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.create') then
    raise exception 'discard_release_draft: forbidden (release.create)' using errcode='42501';
  end if;
  if v_status <> 'draft' then
    raise exception 'discard_release_draft: release is % (must be draft)', v_status using errcode='23514';
  end if;
  if v_discarded is not null then
    raise exception 'discard_release_draft: release already discarded' using errcode='23514';
  end if;

  update public.releases set discarded_at = now() where id = p_release_id;
  return p_release_id;
end $$;

revoke all on function public.discard_release_draft(uuid) from public;
revoke all on function public.discard_release_draft(uuid) from anon;
grant execute on function public.discard_release_draft(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 21. publish_release — write RPC wrapper (§14.4, L-1 single atomic UPDATE)
------------------------------------------------------------------------------
-- Layers per-release-type policy on top of the frozen finalize invariants.
-- Captures evidence snapshot before flipping status. Single atomic UPDATE
-- transitions status + evidence + publisher + release_type in one statement.

create or replace function public.publish_release(
  p_release_id uuid,
  p_release_type text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid;
  v_ws uuid;
  v_pj uuid;
  v_status text;
  v_name text;
  v_channel text;
  v_current_type text;
  v_effective_type text;
  v_item_count int;
  v_snapshot jsonb;
  v_items_arr jsonb;
  v_approved_ids jsonb;
  v_review_count int;
  v_readiness record;
  v_req_readiness jsonb;
  v_blockers jsonb;
  v_can boolean;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'publish_release: authentication required' using errcode='42501';
  end if;

  select workspace_id, project_id, status, name, channel, release_type
    into v_ws, v_pj, v_status, v_name, v_channel, v_current_type
    from public.releases where id = p_release_id for update;
  if v_ws is null then
    raise exception 'publish_release: release not found' using errcode='23503';
  end if;
  if v_status <> 'draft' then
    raise exception 'publish_release: release is % (must be draft)', v_status using errcode='23514';
  end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.finalize') then
    raise exception 'publish_release: forbidden (release.finalize)' using errcode='42501';
  end if;

  v_effective_type := coalesce(p_release_type, v_current_type);
  if v_effective_type is not null and v_effective_type not in
    ('internal','preview','client','regulatory','final','patch','hotfix') then
    raise exception 'publish_release: invalid release_type %', v_effective_type using errcode='23514';
  end if;

  select count(*) into v_item_count from public.release_items where release_id = p_release_id;
  if v_item_count < 1 then
    raise exception 'publish_release: release has no items' using errcode='23514';
  end if;

  -- Per-item readiness preflight (advisory in RPC layer; DB trigger is authoritative).
  for v_readiness in
    select public.get_release_readiness_for_publish(ri.design_asset_id, ri.version_id, v_effective_type) as rd
      from public.release_items ri
     where ri.release_id = p_release_id
  loop
    v_can := coalesce((v_readiness.rd->>'can_publish')::boolean, false);
    v_blockers := v_readiness.rd->'blocking_conditions';
    if not v_can then
      raise exception 'publish_release: readiness check failed: %', v_blockers::text using errcode='23514';
    end if;
  end loop;

  -- Build evidence snapshot per §3.2 shape.
  with items as (
    select ri.id as release_item_id,
           ri.design_asset_id,
           da.name as design_asset_name,
           ri.version_id as version_id,
           av.sequence as version_sequence,
           av.published_at   as version_published_at,
           ri.notes
      from public.release_items ri
      join public.design_assets  da on da.id = ri.design_asset_id
      join public.asset_versions av on av.id = ri.version_id
     where ri.release_id = p_release_id
  ),
  enriched as (
    select i.*,
           public.get_approval_readiness(i.version_id) as approval,
           public.get_release_readiness_for_version(i.version_id) as req_readiness,
           (select array_agg(rv.id)::uuid[]
              from public.reviews rv
             where rv.version_id = i.version_id) as review_ids,
           (select count(*) from public.reviews rv
             where rv.version_id = i.version_id and rv.status = 'completed') as completed_review_count
      from items i
  )
  select jsonb_agg(
           jsonb_build_object(
             'release_item_id', release_item_id,
             'design_asset_id', design_asset_id,
             'design_asset_name', design_asset_name,
             'version_id', version_id,
             'version_sequence', version_sequence,
             'version_published_at', version_published_at,
             'approval_request_id', (approval->'latest_outcome'->>'request_id')::uuid,
             'approval_outcome', approval->'latest_outcome',
             'approval_outcome_at', (approval->'latest_outcome'->>'outcome_at')::timestamptz,
             'requirement_readiness', req_readiness,
             'review_ids', coalesce(to_jsonb(review_ids), '[]'::jsonb),
             'completed_review_count', completed_review_count
           )
         )
    into v_items_arr
    from enriched;

  select coalesce(jsonb_agg(distinct (public.get_approval_readiness(ri.version_id)->'latest_outcome'->>'request_id')::uuid)
                    filter (where (public.get_approval_readiness(ri.version_id)->'latest_outcome'->>'request_id') is not null),
                  '[]'::jsonb),
         coalesce(sum((select count(*) from public.reviews rv where rv.version_id = ri.version_id and rv.status='completed'))::int, 0)
    into v_approved_ids, v_review_count
    from public.release_items ri
   where ri.release_id = p_release_id;

  select public.get_release_readiness_for_version(ri.version_id)
    into v_req_readiness
    from public.release_items ri
   where ri.release_id = p_release_id
   limit 1;

  v_snapshot := jsonb_build_object(
    'version', '1',
    'captured_at', now(),
    'published_by_profile_id', v_caller,
    'release_type', v_effective_type,
    'channel', v_channel,
    'items', coalesce(v_items_arr, '[]'::jsonb),
    'approval_request_ids', coalesce(v_approved_ids, '[]'::jsonb)
  );

  -- L-1: single atomic transition UPDATE (one updated_at bump).
  perform set_config('lign.allow_release_status_write', 'true', true);
  update public.releases
     set status = 'released',
         released_at = now(),
         published_by_profile_id = v_caller,
         evidence_snapshot = v_snapshot,
         release_type = v_effective_type
   where id = p_release_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_pj, now(), 'release.finalized',
    v_caller, 'user',
    'release', p_release_id, v_name,
    jsonb_build_object(
      'name', v_name,
      'item_count', v_item_count,
      'channel', v_channel,
      'release_type', v_effective_type,
      'published_by_profile_id', v_caller,
      'approved_request_ids', coalesce(v_approved_ids, '[]'::jsonb),
      'requirement_readiness', v_req_readiness,
      'review_count', v_review_count,
      'superseded_prior_release_id', null
    ),
    '{}'::jsonb
  );

  return p_release_id;
end $$;

revoke all on function public.publish_release(uuid, text) from public;
revoke all on function public.publish_release(uuid, text) from anon;
grant execute on function public.publish_release(uuid, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 22. finalize_release — CREATE OR REPLACE single-function extension (§14.5, F-2, F-4)
------------------------------------------------------------------------------
-- Frozen positional 1-arg call binds unchanged (p_release_type defaults NULL).
-- F-4: Evidence capture ALWAYS performed (no bypass parameter).
-- L-1: Single atomic UPDATE per publish.

create or replace function public.finalize_release(
  p_release_id uuid,
  p_release_type text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid;
  v_ws uuid;
  v_pj uuid;
  v_status text;
  v_name text;
  v_channel text;
  v_current_type text;
  v_effective_type text;
  v_item_count int;
  v_snapshot jsonb;
  v_items_arr jsonb;
  v_approved_ids jsonb;
  v_review_count int;
  v_req_readiness jsonb;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'finalize_release: authentication required' using errcode='42501';
  end if;

  select workspace_id, project_id, status, name, channel, release_type
    into v_ws, v_pj, v_status, v_name, v_channel, v_current_type
    from public.releases where id = p_release_id for update;
  if v_ws is null then
    raise exception 'finalize_release: release not found' using errcode='23503';
  end if;
  if v_status <> 'draft' then
    raise exception 'finalize_release: release is % (must be draft)', v_status using errcode='23514';
  end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.finalize') then
    raise exception 'finalize_release: forbidden (release.finalize)' using errcode='42501';
  end if;

  v_effective_type := coalesce(p_release_type, v_current_type);
  if v_effective_type is not null and v_effective_type not in
    ('internal','preview','client','regulatory','final','patch','hotfix') then
    raise exception 'finalize_release: invalid release_type %', v_effective_type using errcode='23514';
  end if;

  select count(*) into v_item_count from public.release_items where release_id = p_release_id;
  if v_item_count < 1 then
    raise exception 'finalize_release: release has no items' using errcode='23514';
  end if;

  -- F-4: always capture evidence.
  with items as (
    select ri.id as release_item_id,
           ri.design_asset_id,
           da.name as design_asset_name,
           ri.version_id as version_id,
           av.sequence as version_sequence,
           av.published_at   as version_published_at,
           ri.notes
      from public.release_items ri
      join public.design_assets  da on da.id = ri.design_asset_id
      join public.asset_versions av on av.id = ri.version_id
     where ri.release_id = p_release_id
  ),
  enriched as (
    select i.*,
           public.get_approval_readiness(i.version_id) as approval,
           public.get_release_readiness_for_version(i.version_id) as req_readiness,
           (select array_agg(rv.id)::uuid[]
              from public.reviews rv where rv.version_id = i.version_id) as review_ids,
           (select count(*) from public.reviews rv
             where rv.version_id = i.version_id and rv.status = 'completed') as completed_review_count
      from items i
  )
  select jsonb_agg(
           jsonb_build_object(
             'release_item_id', release_item_id,
             'design_asset_id', design_asset_id,
             'design_asset_name', design_asset_name,
             'version_id', version_id,
             'version_sequence', version_sequence,
             'version_published_at', version_published_at,
             'approval_request_id', (approval->'latest_outcome'->>'request_id')::uuid,
             'approval_outcome', approval->'latest_outcome',
             'approval_outcome_at', (approval->'latest_outcome'->>'outcome_at')::timestamptz,
             'requirement_readiness', req_readiness,
             'review_ids', coalesce(to_jsonb(review_ids), '[]'::jsonb),
             'completed_review_count', completed_review_count
           )
         )
    into v_items_arr
    from enriched;

  select coalesce(jsonb_agg(distinct (public.get_approval_readiness(ri.version_id)->'latest_outcome'->>'request_id')::uuid)
                    filter (where (public.get_approval_readiness(ri.version_id)->'latest_outcome'->>'request_id') is not null),
                  '[]'::jsonb),
         coalesce(sum((select count(*) from public.reviews rv where rv.version_id = ri.version_id and rv.status='completed'))::int, 0)
    into v_approved_ids, v_review_count
    from public.release_items ri
   where ri.release_id = p_release_id;

  select public.get_release_readiness_for_version(ri.version_id)
    into v_req_readiness
    from public.release_items ri
   where ri.release_id = p_release_id
   limit 1;

  v_snapshot := jsonb_build_object(
    'version', '1',
    'captured_at', now(),
    'published_by_profile_id', v_caller,
    'release_type', v_effective_type,
    'channel', v_channel,
    'items', coalesce(v_items_arr, '[]'::jsonb),
    'approval_request_ids', coalesce(v_approved_ids, '[]'::jsonb)
  );

  -- L-1: single atomic UPDATE.
  perform set_config('lign.allow_release_status_write', 'true', true);
  update public.releases
     set status = 'released',
         released_at = now(),
         published_by_profile_id = v_caller,
         evidence_snapshot = v_snapshot,
         release_type = v_effective_type
   where id = p_release_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_pj, now(), 'release.finalized',
    v_caller, 'user',
    'release', p_release_id, v_name,
    jsonb_build_object(
      'name', v_name,
      'item_count', v_item_count,
      'channel', v_channel,
      'release_type', v_effective_type,
      'published_by_profile_id', v_caller,
      'approved_request_ids', coalesce(v_approved_ids, '[]'::jsonb),
      'requirement_readiness', v_req_readiness,
      'review_count', v_review_count,
      'superseded_prior_release_id', null
    ),
    '{}'::jsonb
  );

  return p_release_id;
end $$;

comment on function public.finalize_release(uuid, text) is
  'APP 009 §14.5 / F-2 / F-4: single-function CREATE OR REPLACE extension of frozen finalize_release(uuid). Adds p_release_type tail param (default null). Evidence capture is ALWAYS performed (F-4). Frozen positional 1-arg call binds unchanged.';

revoke all on function public.finalize_release(uuid, text) from public;
revoke all on function public.finalize_release(uuid, text) from anon;
grant execute on function public.finalize_release(uuid, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 23. withdraw_release — CREATE OR REPLACE single-function extension (§14.8, F-2)
------------------------------------------------------------------------------
-- Frozen positional 2-arg call binds unchanged (p_admin_override defaults false).
-- p_admin_override captured in payload only in v1; Wave 4 may branch on it.

create or replace function public.withdraw_release(
  p_release_id uuid,
  p_reason text default null,
  p_admin_override boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller       uuid;
  v_ws           uuid;
  v_pj           uuid;
  v_status       text;
  v_name         text;
  v_release_type text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'withdraw_release: authentication required' using errcode='42501';
  end if;

  select workspace_id, project_id, status, name, release_type
    into v_ws, v_pj, v_status, v_name, v_release_type
    from public.releases
   where id = p_release_id
   for update;
  if v_ws is null then
    raise exception 'withdraw_release: release not found' using errcode='23503';
  end if;
  if v_status <> 'released' then
    raise exception 'withdraw_release: release is % (must be released)', v_status using errcode='23514';
  end if;

  if not public.lign_has_capability(v_pj, v_ws, 'release.withdraw') then
    raise exception 'withdraw_release: forbidden (release.withdraw)' using errcode='42501';
  end if;

  perform set_config('lign.allow_release_status_write', 'true', true);
  update public.releases
     set status           = 'withdrawn',
         withdrawn_at     = now(),
         withdrawn_reason = p_reason
   where id = p_release_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_pj, now(), 'release.withdrawn',
    v_caller, 'user',
    'release', p_release_id, v_name,
    jsonb_build_object(
      'reason', p_reason,
      'release_type', v_release_type,
      'withdrawn_by_profile_id', v_caller,
      'admin_override', p_admin_override
    ),
    '{}'::jsonb
  );

  return p_release_id;
end $$;

comment on function public.withdraw_release(uuid, text, boolean) is
  'APP 009 §14.8 / F-2: single-function CREATE OR REPLACE extension of frozen withdraw_release(uuid, text). Adds p_admin_override tail param (default false). In v1 payload captures the flag; event name unchanged. Frozen positional 2-arg call binds unchanged.';

revoke all on function public.withdraw_release(uuid, text, boolean) from public;
revoke all on function public.withdraw_release(uuid, text, boolean) from anon;
grant execute on function public.withdraw_release(uuid, text, boolean) to authenticated, service_role;

------------------------------------------------------------------------------
-- 24. F-2 enforcement: drop frozen finalize_release(uuid) and withdraw_release(uuid, text)
------------------------------------------------------------------------------
-- The frozen AUTH 008 CREATE OR REPLACE calls created (uuid) / (uuid, text) overloads.
-- Because Postgres treats different parameter counts as distinct signatures,
-- CREATE OR REPLACE on the extended forms above left the frozen overloads in place.
-- F-2 requires exactly ONE function per name (no dual overloads) so that named-argument
-- callers like `finalize_release(p_release_id => X)` do not raise "function is not unique".
-- Drop the shorter signatures now; the extended forms carry byte-compatible defaults,
-- so both the frozen positional 1-arg and 2-arg call sites continue to bind unchanged
-- to the extended single-function signatures.
--
-- AUTH 008 migration file is preserved BYTE-IDENTICAL; the DROPs here rely on the
-- ordering guarantee that Migration B runs after AUTH 008 was already applied.

drop function if exists public.finalize_release(uuid);
drop function if exists public.withdraw_release(uuid, text);

