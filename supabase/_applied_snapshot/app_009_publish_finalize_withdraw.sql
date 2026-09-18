-- APP 009: publish_release + CREATE OR REPLACE-extended finalize_release / withdraw_release
create or replace function public.publish_release(p_release_id uuid, p_release_type text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_pj uuid; v_status text; v_name text; v_channel text;
  v_current_type text; v_effective_type text; v_item_count int;
  v_snapshot jsonb; v_items_arr jsonb; v_approved_ids jsonb;
  v_review_count int; v_readiness record; v_req_readiness jsonb;
  v_blockers jsonb; v_can boolean;
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

  for v_readiness in
    select public.get_release_readiness_for_publish(ri.design_asset_id, ri.version_id, v_effective_type) as rd
      from public.release_items ri where ri.release_id = p_release_id
  loop
    v_can := coalesce((v_readiness.rd->>'can_publish')::boolean, false);
    v_blockers := v_readiness.rd->'blocking_conditions';
    if not v_can then
      raise exception 'publish_release: readiness check failed: %', v_blockers::text using errcode='23514';
    end if;
  end loop;

  with items as (
    select ri.id as release_item_id, ri.design_asset_id, da.name as design_asset_name,
           ri.version_id, av.sequence as version_sequence, av.published_at as version_published_at
      from public.release_items ri
      join public.design_assets  da on da.id = ri.design_asset_id
      join public.asset_versions av on av.id = ri.version_id
     where ri.release_id = p_release_id
  ),
  enriched as (
    select i.*,
           public.get_approval_readiness(i.version_id) as approval,
           public.get_release_readiness_for_version(i.version_id) as req_readiness,
           (select array_agg(rv.id)::uuid[] from public.reviews rv where rv.version_id = i.version_id) as review_ids,
           (select count(*) from public.reviews rv
             where rv.version_id = i.version_id and rv.status = 'completed') as completed_review_count
      from items i
  )
  select jsonb_agg(jsonb_build_object(
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
  )) into v_items_arr from enriched;

  select coalesce(jsonb_agg(distinct (public.get_approval_readiness(ri.version_id)->'latest_outcome'->>'request_id')::uuid)
                    filter (where (public.get_approval_readiness(ri.version_id)->'latest_outcome'->>'request_id') is not null),
                  '[]'::jsonb),
         coalesce(sum((select count(*) from public.reviews rv where rv.version_id = ri.version_id and rv.status='completed'))::int, 0)
    into v_approved_ids, v_review_count
    from public.release_items ri where ri.release_id = p_release_id;

  select public.get_release_readiness_for_version(ri.version_id) into v_req_readiness
    from public.release_items ri where ri.release_id = p_release_id limit 1;

  v_snapshot := jsonb_build_object(
    'version', '1',
    'captured_at', now(),
    'published_by_profile_id', v_caller,
    'release_type', v_effective_type,
    'channel', v_channel,
    'items', coalesce(v_items_arr, '[]'::jsonb),
    'approval_request_ids', coalesce(v_approved_ids, '[]'::jsonb)
  );

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
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_pj, now(), 'release.finalized',
    v_caller, 'user', 'release', p_release_id, v_name,
    jsonb_build_object(
      'name', v_name, 'item_count', v_item_count, 'channel', v_channel,
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

-- CREATE OR REPLACE-extended finalize_release (F-2, F-4, L-1)
create or replace function public.finalize_release(p_release_id uuid, p_release_type text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_pj uuid; v_status text; v_name text; v_channel text;
  v_current_type text; v_effective_type text; v_item_count int;
  v_snapshot jsonb; v_items_arr jsonb; v_approved_ids jsonb;
  v_review_count int; v_req_readiness jsonb;
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

  with items as (
    select ri.id as release_item_id, ri.design_asset_id, da.name as design_asset_name,
           ri.version_id, av.sequence as version_sequence, av.published_at as version_published_at
      from public.release_items ri
      join public.design_assets  da on da.id = ri.design_asset_id
      join public.asset_versions av on av.id = ri.version_id
     where ri.release_id = p_release_id
  ),
  enriched as (
    select i.*,
           public.get_approval_readiness(i.version_id) as approval,
           public.get_release_readiness_for_version(i.version_id) as req_readiness,
           (select array_agg(rv.id)::uuid[] from public.reviews rv where rv.version_id = i.version_id) as review_ids,
           (select count(*) from public.reviews rv
             where rv.version_id = i.version_id and rv.status = 'completed') as completed_review_count
      from items i
  )
  select jsonb_agg(jsonb_build_object(
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
  )) into v_items_arr from enriched;

  select coalesce(jsonb_agg(distinct (public.get_approval_readiness(ri.version_id)->'latest_outcome'->>'request_id')::uuid)
                    filter (where (public.get_approval_readiness(ri.version_id)->'latest_outcome'->>'request_id') is not null),
                  '[]'::jsonb),
         coalesce(sum((select count(*) from public.reviews rv where rv.version_id = ri.version_id and rv.status='completed'))::int, 0)
    into v_approved_ids, v_review_count
    from public.release_items ri where ri.release_id = p_release_id;

  select public.get_release_readiness_for_version(ri.version_id) into v_req_readiness
    from public.release_items ri where ri.release_id = p_release_id limit 1;

  v_snapshot := jsonb_build_object(
    'version', '1',
    'captured_at', now(),
    'published_by_profile_id', v_caller,
    'release_type', v_effective_type,
    'channel', v_channel,
    'items', coalesce(v_items_arr, '[]'::jsonb),
    'approval_request_ids', coalesce(v_approved_ids, '[]'::jsonb)
  );

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
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_pj, now(), 'release.finalized',
    v_caller, 'user', 'release', p_release_id, v_name,
    jsonb_build_object(
      'name', v_name, 'item_count', v_item_count, 'channel', v_channel,
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

-- CREATE OR REPLACE-extended withdraw_release (F-2)
create or replace function public.withdraw_release(
  p_release_id uuid, p_reason text default null, p_admin_override boolean default false
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_ws uuid; v_pj uuid; v_status text; v_name text; v_release_type text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'withdraw_release: authentication required' using errcode='42501';
  end if;
  select workspace_id, project_id, status, name, release_type
    into v_ws, v_pj, v_status, v_name, v_release_type
    from public.releases where id = p_release_id for update;
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
     set status = 'withdrawn', withdrawn_at = now(), withdrawn_reason = p_reason
   where id = p_release_id;
  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_pj, now(), 'release.withdrawn',
    v_caller, 'user', 'release', p_release_id, v_name,
    jsonb_build_object('reason', p_reason, 'release_type', v_release_type,
                       'withdrawn_by_profile_id', v_caller, 'admin_override', p_admin_override),
    '{}'::jsonb
  );
  return p_release_id;
end $$;
comment on function public.withdraw_release(uuid, text, boolean) is
  'APP 009 §14.8 / F-2: single-function CREATE OR REPLACE extension of frozen withdraw_release(uuid, text). Adds p_admin_override tail param (default false). Frozen positional 2-arg call binds unchanged.';
revoke all on function public.withdraw_release(uuid, text, boolean) from public;
revoke all on function public.withdraw_release(uuid, text, boolean) from anon;
grant execute on function public.withdraw_release(uuid, text, boolean) to authenticated, service_role;
