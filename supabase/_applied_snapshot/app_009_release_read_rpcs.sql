-- APP 009: get_release, get_release_by_code, get_release_chain, get_release_evidence
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
  with recursive chain(id, depth) as (
    select v_root_id, 1
    union all
    select r.id, c.depth + 1
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

create or replace function public.get_release_by_code(
  p_project_id uuid, p_ws_id uuid, p_code text
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not public.lign_has_capability(p_project_id, p_ws_id, 'release.view') then
    raise exception 'get_release_by_code: forbidden (release.view)' using errcode='42501';
  end if;
  select id into v_id from public.releases
   where project_id = p_project_id and workspace_id = p_ws_id and code = p_code;
  if v_id is null then return null; end if;
  return public.get_release(v_id);
end $$;
revoke all on function public.get_release_by_code(uuid, uuid, text) from public;
revoke all on function public.get_release_by_code(uuid, uuid, text) from anon;
grant execute on function public.get_release_by_code(uuid, uuid, text) to authenticated, service_role;

create or replace function public.get_release_chain(p_release_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_r public.releases%rowtype;
  v_root_id uuid;
  v_arr jsonb;
begin
  select * into v_r from public.releases where id = p_release_id;
  if v_r.id is null then return jsonb_build_object('nodes','[]'::jsonb); end if;
  if not public.lign_has_capability(v_r.project_id, v_r.workspace_id, 'release.view') then
    raise exception 'get_release_chain: forbidden (release.view)' using errcode='42501';
  end if;
  v_root_id := coalesce(v_r.root_release_id, v_r.id);
  with recursive walk(id, depth) as (
    select v_root_id, 0
    union all
    select r.id, w.depth + 1
      from walk w join public.releases r on r.superseded_by_release_id = w.id
     where r.project_id = v_r.project_id
  ),
  nodes as (
    select r.id as release_id, r.code, r.name, r.release_type, r.status,
           r.released_at, r.withdrawn_at, w.depth,
           (w.depth = 0) as is_root,
           (r.superseded_by_release_id is null) as is_head
      from walk w join public.releases r on r.id = w.id
  )
  select jsonb_agg(
    jsonb_build_object(
      'release_id', release_id, 'code', code, 'name', name,
      'release_type', release_type, 'status', status,
      'released_at', released_at, 'withdrawn_at', withdrawn_at,
      'is_root', is_root, 'is_head', is_head
    ) order by depth asc)
  into v_arr from nodes;
  return jsonb_build_object('nodes', coalesce(v_arr, '[]'::jsonb));
end $$;
revoke all on function public.get_release_chain(uuid) from public;
revoke all on function public.get_release_chain(uuid) from anon;
grant execute on function public.get_release_chain(uuid) to authenticated, service_role;

create or replace function public.get_release_evidence(p_release_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_r public.releases%rowtype;
  v_delta_arr jsonb;
begin
  select * into v_r from public.releases where id = p_release_id;
  if v_r.id is null then return null; end if;
  if not public.lign_has_capability(v_r.project_id, v_r.workspace_id, 'release.view') then
    raise exception 'get_release_evidence: forbidden (release.view)' using errcode='42501';
  end if;
  with items as (
    select ri.id as release_item_id, ri.design_asset_id, ri.version_id
      from public.release_items ri where ri.release_id = p_release_id
  ),
  computed as (
    select i.release_item_id, i.design_asset_id, i.version_id,
           public.get_approval_readiness(i.version_id) as approval_current,
           public.get_release_readiness_for_version(i.version_id) as requirement_current
      from items i
  )
  select jsonb_agg(jsonb_build_object(
    'release_item_id', release_item_id,
    'design_asset_id', design_asset_id,
    'version_id', version_id,
    'approval_current', approval_current,
    'requirement_current', requirement_current
  )) into v_delta_arr from computed;
  return jsonb_build_object(
    'snapshot', v_r.evidence_snapshot,
    'live_delta', jsonb_build_object('items', coalesce(v_delta_arr, '[]'::jsonb)),
    'has_deltas', (v_r.evidence_snapshot is not null)
  );
end $$;
revoke all on function public.get_release_evidence(uuid) from public;
revoke all on function public.get_release_evidence(uuid) from anon;
grant execute on function public.get_release_evidence(uuid) to authenticated, service_role;
