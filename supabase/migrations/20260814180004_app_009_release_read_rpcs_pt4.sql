-- APP 009: list_releases_for_asset, list_releases_for_version, get_release_readiness_for_publish
create or replace function public.list_releases_for_asset(p_design_asset_id uuid)
returns table (
  out_release_id uuid, out_code text, out_name text, out_release_type text, out_status text,
  out_released_at timestamptz, out_version_id uuid, out_version_sequence integer
) language plpgsql stable security definer set search_path = ''
as $$
declare v_ws uuid; v_pj uuid;
begin
  select workspace_id, project_id into v_ws, v_pj from public.design_assets where id = p_design_asset_id;
  if v_ws is null then return; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.view') then
    raise exception 'list_releases_for_asset: forbidden (release.view)' using errcode='42501';
  end if;
  return query
    select r.id, r.code, r.name, r.release_type, r.status, r.released_at,
           ri.version_id, av.sequence
      from public.release_items ri
      join public.releases r  on r.id = ri.release_id
      join public.asset_versions av on av.id = ri.version_id
     where ri.design_asset_id = p_design_asset_id
     order by r.released_at desc nulls last, r.id desc;
end $$;
revoke all on function public.list_releases_for_asset(uuid) from public;
revoke all on function public.list_releases_for_asset(uuid) from anon;
grant execute on function public.list_releases_for_asset(uuid) to authenticated, service_role;

create or replace function public.list_releases_for_version(p_version_id uuid)
returns table (
  out_release_id uuid, out_code text, out_name text, out_release_type text, out_status text,
  out_released_at timestamptz, out_version_id uuid, out_version_sequence integer
) language plpgsql stable security definer set search_path = ''
as $$
declare v_ws uuid; v_pj uuid;
begin
  select workspace_id, project_id into v_ws, v_pj from public.asset_versions where id = p_version_id;
  if v_ws is null then return; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.view') then
    raise exception 'list_releases_for_version: forbidden (release.view)' using errcode='42501';
  end if;
  return query
    select r.id, r.code, r.name, r.release_type, r.status, r.released_at,
           ri.version_id, av.sequence
      from public.release_items ri
      join public.releases r  on r.id = ri.release_id
      join public.asset_versions av on av.id = ri.version_id
     where ri.version_id = p_version_id
     order by r.released_at desc nulls last, r.id desc;
end $$;
revoke all on function public.list_releases_for_version(uuid) from public;
revoke all on function public.list_releases_for_version(uuid) from anon;
grant execute on function public.list_releases_for_version(uuid) to authenticated, service_role;

create or replace function public.get_release_readiness_for_publish(
  p_design_asset_id uuid, p_version_id uuid, p_release_type text
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_ws uuid; v_pj uuid; v_approval jsonb; v_req jsonb;
  v_review_count int; v_blockers jsonb := '[]'::jsonb; v_can boolean := true;
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
  v_req := public.get_release_readiness_for_version(p_version_id);
  select count(*)::int into v_review_count
    from public.reviews rv where rv.version_id = p_version_id and rv.status = 'completed';
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
