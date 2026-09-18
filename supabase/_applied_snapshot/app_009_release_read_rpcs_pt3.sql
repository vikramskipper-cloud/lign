-- APP 009: list_releases_dashboard, get_release_inbox_count, metrics, per-asset/version, publish preflight
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
) returns table (
  out_release_id uuid, out_workspace_id uuid, out_project_id uuid, out_project_name text,
  out_code text, out_name text, out_release_type text, out_status text, out_channel text,
  out_released_at timestamptz, out_withdrawn_at timestamptz, out_discarded_at timestamptz,
  out_created_by_profile_id uuid, out_published_by_profile_id uuid,
  out_created_at timestamptz, out_updated_at timestamptz, out_item_count integer,
  out_next_cursor_at timestamptz, out_next_cursor_id uuid
) language plpgsql stable security definer set search_path = ''
as $$
declare
  v_caller uuid;
  v_saved jsonb;
  v_view text := coalesce(p_view, 'all');
  v_lim integer := greatest(1, least(coalesce(p_limit, 25), 200));
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
    select payload into v_saved from public.user_saved_views
     where id = p_saved_view_id and workspace_id = p_ws_id and profile_id = v_caller;
    if v_saved is null then
      raise exception 'list_releases_dashboard: saved view not found' using errcode='23503';
    end if;
  end if;
  return query
    select r.id, r.workspace_id, r.project_id, p.name,
           r.code, r.name, r.release_type, r.status, r.channel,
           r.released_at, r.withdrawn_at, r.discarded_at,
           r.created_by_profile_id, r.published_by_profile_id,
           r.created_at, r.updated_at,
           (select count(*)::int from public.release_items ri where ri.release_id = r.id),
           r.released_at, r.id
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
                or (r.released_at = p_cursor_released_at and r.id < coalesce(p_cursor_id,'00000000-0000-0000-0000-000000000000'::uuid)))))
     order by r.released_at desc nulls last, r.id desc
     limit v_lim;
end $$;
revoke all on function public.list_releases_dashboard(uuid, uuid, text, text[], text[], uuid[], text, boolean, timestamptz, uuid, integer, uuid) from public;
revoke all on function public.list_releases_dashboard(uuid, uuid, text, text[], text[], uuid[], text, boolean, timestamptz, uuid, integer, uuid) from anon;
grant execute on function public.list_releases_dashboard(uuid, uuid, text, text[], text[], uuid[], text, boolean, timestamptz, uuid, integer, uuid) to authenticated, service_role;

create or replace function public.get_release_inbox_count(p_ws_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_r30 int; v_dr int; v_per jsonb;
begin
  if auth.uid() is null then
    raise exception 'get_release_inbox_count: authentication required' using errcode='42501';
  end if;
  select coalesce(sum(case when r.status='released' and r.released_at >= (now() - interval '30 days') then 1 else 0 end),0)::int,
         coalesce(sum(case when r.status='draft' and r.discarded_at is null then 1 else 0 end),0)::int
    into v_r30, v_dr
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
    into v_per from per;
  return jsonb_build_object(
    'workspace_released_trailing_30d', v_r30,
    'workspace_draft_count', v_dr,
    'per_project', coalesce(v_per, '[]'::jsonb)
  );
end $$;
revoke all on function public.get_release_inbox_count(uuid) from public;
revoke all on function public.get_release_inbox_count(uuid) from anon;
grant execute on function public.get_release_inbox_count(uuid) to authenticated, service_role;

create or replace function public.get_project_release_metrics(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_ws uuid; v_result jsonb;
begin
  select workspace_id into v_ws from public.projects where id = p_project_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(p_project_id, v_ws, 'release.view') then
    raise exception 'get_project_release_metrics: forbidden (release.view)' using errcode='42501';
  end if;
  select jsonb_build_object(
    'total_draft', coalesce(sum(case when status='draft' then 1 else 0 end),0)::int,
    'total_released', coalesce(sum(case when status='released' then 1 else 0 end),0)::int,
    'total_withdrawn', coalesce(sum(case when status='withdrawn' then 1 else 0 end),0)::int,
    'released_trailing_30d', coalesce(sum(case when status='released' and released_at >= (now() - interval '30 days') then 1 else 0 end),0)::int,
    'released_trailing_90d', coalesce(sum(case when status='released' and released_at >= (now() - interval '90 days') then 1 else 0 end),0)::int,
    'by_type', jsonb_build_object(
      'internal',   coalesce(sum(case when release_type='internal' then 1 else 0 end),0)::int,
      'preview',    coalesce(sum(case when release_type='preview' then 1 else 0 end),0)::int,
      'client',     coalesce(sum(case when release_type='client' then 1 else 0 end),0)::int,
      'regulatory', coalesce(sum(case when release_type='regulatory' then 1 else 0 end),0)::int,
      'final',      coalesce(sum(case when release_type='final' then 1 else 0 end),0)::int,
      'patch',      coalesce(sum(case when release_type='patch' then 1 else 0 end),0)::int,
      'hotfix',     coalesce(sum(case when release_type='hotfix' then 1 else 0 end),0)::int
    ),
    'chain_head_count', coalesce(sum(case when superseded_by_release_id is null and status='released' then 1 else 0 end),0)::int,
    'discarded_count', coalesce(sum(case when discarded_at is not null then 1 else 0 end),0)::int
  ) into v_result from public.releases where project_id = p_project_id;
  return v_result;
end $$;
revoke all on function public.get_project_release_metrics(uuid) from public;
revoke all on function public.get_project_release_metrics(uuid) from anon;
grant execute on function public.get_project_release_metrics(uuid) to authenticated, service_role;

create or replace function public.get_workspace_release_metrics(p_ws_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_result jsonb; v_top5 jsonb;
begin
  if auth.uid() is null then
    raise exception 'get_workspace_release_metrics: authentication required' using errcode='42501';
  end if;
  select jsonb_build_object(
    'total_draft', coalesce(sum(case when status='draft' then 1 else 0 end),0)::int,
    'total_released', coalesce(sum(case when status='released' then 1 else 0 end),0)::int,
    'total_withdrawn', coalesce(sum(case when status='withdrawn' then 1 else 0 end),0)::int,
    'released_trailing_30d', coalesce(sum(case when status='released' and released_at >= (now() - interval '30 days') then 1 else 0 end),0)::int,
    'released_trailing_90d', coalesce(sum(case when status='released' and released_at >= (now() - interval '90 days') then 1 else 0 end),0)::int,
    'by_type', jsonb_build_object(
      'internal',   coalesce(sum(case when release_type='internal' then 1 else 0 end),0)::int,
      'preview',    coalesce(sum(case when release_type='preview' then 1 else 0 end),0)::int,
      'client',     coalesce(sum(case when release_type='client' then 1 else 0 end),0)::int,
      'regulatory', coalesce(sum(case when release_type='regulatory' then 1 else 0 end),0)::int,
      'final',      coalesce(sum(case when release_type='final' then 1 else 0 end),0)::int,
      'patch',      coalesce(sum(case when release_type='patch' then 1 else 0 end),0)::int,
      'hotfix',     coalesce(sum(case when release_type='hotfix' then 1 else 0 end),0)::int
    ),
    'chain_head_count', coalesce(sum(case when superseded_by_release_id is null and status='released' then 1 else 0 end),0)::int,
    'discarded_count', coalesce(sum(case when discarded_at is not null then 1 else 0 end),0)::int
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
    into v_top5 from per;
  return v_result || jsonb_build_object('per_project_top5', coalesce(v_top5, '[]'::jsonb));
end $$;
revoke all on function public.get_workspace_release_metrics(uuid) from public;
revoke all on function public.get_workspace_release_metrics(uuid) from anon;
grant execute on function public.get_workspace_release_metrics(uuid) to authenticated, service_role;
