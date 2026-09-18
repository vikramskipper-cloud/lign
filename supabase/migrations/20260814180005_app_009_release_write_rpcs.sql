-- APP 009: create_release_draft, add_release_item, remove_release_item, reorder_release_items, discard_release_draft
create or replace function public.create_release_draft(
  p_project_id uuid, p_name text,
  p_notes text default null, p_channel text default null, p_release_type text default null
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_id uuid; v_next_ord int; v_code text;
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

  perform pg_advisory_xact_lock(hashtext('release_code:' || p_project_id::text));
  select coalesce(max((regexp_match(code, 'R-([0-9]+)'))[1]::int), 0) + 1
    into v_next_ord from public.releases
   where project_id = p_project_id and code is not null;
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
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, p_project_id, now(), 'release.created',
    v_caller, 'user', 'release', v_id, p_name,
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

create or replace function public.add_release_item(
  p_release_id uuid, p_design_asset_id uuid, p_version_id uuid,
  p_notes text default null, p_sort_order integer default null
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_pj uuid; v_status text; v_release_type text;
  v_item_id uuid; v_sort int; v_asset_name text; v_ver_seq int;
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
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_pj, now(), 'release.item_added',
    v_caller, 'user', 'release_item', v_item_id, v_asset_name,
    jsonb_build_object(
      'release_id', p_release_id, 'asset_id', p_design_asset_id, 'asset_name', v_asset_name,
      'version_id', p_version_id, 'version_sequence', v_ver_seq, 'release_type', v_release_type,
      'item_id', v_item_id, 'sort_order', v_sort,
      'notes_snippet', case when p_notes is null then null else substr(p_notes,1,200) end
    ),
    '{}'::jsonb
  );
  return v_item_id;
end $$;
revoke all on function public.add_release_item(uuid, uuid, uuid, text, integer) from public;
revoke all on function public.add_release_item(uuid, uuid, uuid, text, integer) from anon;
grant execute on function public.add_release_item(uuid, uuid, uuid, text, integer) to authenticated, service_role;

create or replace function public.remove_release_item(p_release_id uuid, p_version_id uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_pj uuid; v_status text; v_release_type text;
  v_item_id uuid; v_asset_id uuid;
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
    from public.release_items where release_id = p_release_id and version_id = p_version_id;
  if v_item_id is null then
    raise exception 'remove_release_item: item not found' using errcode='23503';
  end if;
  delete from public.release_items where id = v_item_id;
  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_pj, now(), 'release.item_removed',
    v_caller, 'user', 'release_item', v_item_id, null,
    jsonb_build_object('release_id', p_release_id, 'asset_id', v_asset_id, 'version_id', p_version_id,
                       'release_type', v_release_type, 'item_id', v_item_id),
    '{}'::jsonb
  );
  return v_item_id;
end $$;
revoke all on function public.remove_release_item(uuid, uuid) from public;
revoke all on function public.remove_release_item(uuid, uuid) from anon;
grant execute on function public.remove_release_item(uuid, uuid) to authenticated, service_role;

create or replace function public.reorder_release_items(p_release_id uuid, p_ordered_version_ids uuid[])
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_pj uuid; v_status text; v_expected int; v_actual int;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'reorder_release_items: authentication required' using errcode='42501';
  end if;
  select workspace_id, project_id, status into v_ws, v_pj, v_status
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
  if exists (
    select 1 from unnest(p_ordered_version_ids) v(id)
     where not exists (select 1 from public.release_items
                        where release_id = p_release_id and version_id = v.id)
  ) then
    raise exception 'reorder_release_items: array contains version_id(s) not in release' using errcode='23514';
  end if;
  update public.release_items set sort_order = -sort_order - 1 where release_id = p_release_id;
  update public.release_items ri
     set sort_order = ord.i::int
    from unnest(p_ordered_version_ids) with ordinality as ord(vid, i)
   where ri.release_id = p_release_id and ri.version_id = ord.vid;
  return v_expected;
end $$;
revoke all on function public.reorder_release_items(uuid, uuid[]) from public;
revoke all on function public.reorder_release_items(uuid, uuid[]) from anon;
grant execute on function public.reorder_release_items(uuid, uuid[]) to authenticated, service_role;

create or replace function public.discard_release_draft(p_release_id uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_ws uuid; v_pj uuid; v_status text; v_discarded timestamptz;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'discard_release_draft: authentication required' using errcode='42501';
  end if;
  select workspace_id, project_id, status, discarded_at into v_ws, v_pj, v_status, v_discarded
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
