-- APP 009: get_release_comparison, list_release_activity, list_release_items
create or replace function public.get_release_comparison(
  p_release_id uuid, p_compare_to_release_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_this public.releases%rowtype;
  v_other public.releases%rowtype;
  v_other_id uuid;
  v_this_json jsonb;
  v_other_json jsonb;
  v_added jsonb;
  v_removed jsonb;
  v_changed jsonb;
begin
  select * into v_this from public.releases where id = p_release_id;
  if v_this.id is null then return null; end if;
  if not public.lign_has_capability(v_this.project_id, v_this.workspace_id, 'release.view') then
    raise exception 'get_release_comparison: forbidden (release.view)' using errcode='42501';
  end if;
  v_other_id := p_compare_to_release_id;
  if v_other_id is null then
    select id into v_other_id from public.releases
     where superseded_by_release_id = v_this.id and project_id = v_this.project_id limit 1;
  end if;
  if v_other_id is not null then
    select * into v_other from public.releases where id = v_other_id;
    if v_other.id is null then v_other_id := null;
    elsif v_other.project_id <> v_this.project_id then
      raise exception 'get_release_comparison: releases must be same project' using errcode='23514';
    end if;
  end if;
  v_this_json := public.get_release(v_this.id);
  v_other_json := case when v_other_id is not null then public.get_release(v_other_id) else null end;
  with this_items as (
    select design_asset_id, version_id from public.release_items where release_id = v_this.id
  ),
  other_items as (
    select design_asset_id, version_id from public.release_items
     where release_id = coalesce(v_other_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ),
  added as (
    select ti.design_asset_id, ti.version_id from this_items ti
     where not exists (select 1 from other_items oi where oi.design_asset_id = ti.design_asset_id)
  ),
  removed as (
    select oi.design_asset_id, oi.version_id from other_items oi
     where not exists (select 1 from this_items ti where ti.design_asset_id = oi.design_asset_id)
  ),
  changed as (
    select ti.design_asset_id, ti.version_id as this_version_id, oi.version_id as compare_version_id
      from this_items ti join other_items oi on oi.design_asset_id = ti.design_asset_id
     where ti.version_id <> oi.version_id
  )
  select
    (select coalesce(jsonb_agg(jsonb_build_object('design_asset_id',design_asset_id,'version_id',version_id)),'[]'::jsonb) from added),
    (select coalesce(jsonb_agg(jsonb_build_object('design_asset_id',design_asset_id,'version_id',version_id)),'[]'::jsonb) from removed),
    (select coalesce(jsonb_agg(jsonb_build_object('design_asset_id',design_asset_id,'this_version_id',this_version_id,'compare_version_id',compare_version_id)),'[]'::jsonb) from changed)
    into v_added, v_removed, v_changed;
  return jsonb_build_object(
    'this_release', v_this_json,
    'compare_to', v_other_json,
    'item_diff', jsonb_build_object('added', v_added, 'removed', v_removed, 'changed_version', v_changed)
  );
end $$;
revoke all on function public.get_release_comparison(uuid, uuid) from public;
revoke all on function public.get_release_comparison(uuid, uuid) from anon;
grant execute on function public.get_release_comparison(uuid, uuid) to authenticated, service_role;

create or replace function public.list_release_activity(
  p_release_id uuid,
  p_cursor_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 25
) returns table (
  out_id uuid, out_event_type text, out_occurred_at timestamptz,
  out_actor_profile_id uuid, out_subject_kind text, out_subject_id uuid,
  out_subject_label text, out_subject_snapshot jsonb, out_payload jsonb
) language plpgsql stable security definer set search_path = ''
as $$
declare v_ws uuid; v_pj uuid;
begin
  select workspace_id, project_id into v_ws, v_pj from public.releases where id = p_release_id;
  if v_ws is null then return; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.view') then
    raise exception 'list_release_activity: forbidden (release.view)' using errcode='42501';
  end if;
  return query
    select ae.id, ae.event_type, ae.occurred_at, ae.actor_profile_id,
           ae.subject_kind, ae.subject_id, ae.subject_label, ae.subject_snapshot, ae.payload
      from public.activity_events ae
     where ae.workspace_id = v_ws
       and ((ae.subject_kind = 'release' and ae.subject_id = p_release_id)
         or (ae.subject_kind = 'release_item'
             and ae.subject_id in (select id from public.release_items where release_id = p_release_id)))
       and (p_cursor_at is null
            or ae.occurred_at < p_cursor_at
            or (ae.occurred_at = p_cursor_at and ae.id < coalesce(p_cursor_id,'00000000-0000-0000-0000-000000000000'::uuid)))
     order by ae.occurred_at desc, ae.id desc
     limit greatest(1, least(coalesce(p_limit, 25), 200));
end $$;
revoke all on function public.list_release_activity(uuid, timestamptz, uuid, integer) from public;
revoke all on function public.list_release_activity(uuid, timestamptz, uuid, integer) from anon;
grant execute on function public.list_release_activity(uuid, timestamptz, uuid, integer) to authenticated, service_role;

create or replace function public.list_release_items(p_release_id uuid)
returns table (
  out_release_item_id uuid, out_design_asset_id uuid, out_design_asset_name text,
  out_version_id uuid, out_version_sequence integer, out_version_published_at timestamptz,
  out_notes text, out_sort_order integer,
  out_approval_state jsonb, out_requirement_readiness_summary jsonb
) language plpgsql stable security definer set search_path = ''
as $$
declare v_ws uuid; v_pj uuid;
begin
  select workspace_id, project_id into v_ws, v_pj from public.releases where id = p_release_id;
  if v_ws is null then return; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.view') then
    raise exception 'list_release_items: forbidden (release.view)' using errcode='42501';
  end if;
  return query
    select ri.id, ri.design_asset_id, da.name, ri.version_id, av.sequence,
           av.published_at, ri.notes, ri.sort_order,
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
