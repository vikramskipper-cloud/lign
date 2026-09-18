-- AUTH 004

create or replace function public.enforce_current_version_via_rpc()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.current_version_id is distinct from old.current_version_id then
    if coalesce(current_setting('lign.allow_current_version_write', true), '') <> 'true' then
      raise exception 'design_assets.current_version_id is set_current_version RPC only (asset %)', old.id
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists design_assets_current_version_rpc_only on public.design_assets;
create trigger design_assets_current_version_rpc_only
  before update on public.design_assets
  for each row execute function public.enforce_current_version_via_rpc();

create or replace function public.create_draft_version(
  p_project_id uuid, p_design_asset_id uuid,
  p_label text default null, p_notes text default null
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_project_id uuid; v_next_seq int; v_version_id uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'create_draft_version: auth required' using errcode='42501'; end if;
  if p_project_id is null or p_design_asset_id is null then
    raise exception 'create_draft_version: ids required' using errcode='22004';
  end if;

  select workspace_id, project_id into v_workspace_id, v_project_id
    from public.design_assets where id = p_design_asset_id for update;
  if v_workspace_id is null then
    raise exception 'create_draft_version: asset % not found', p_design_asset_id using errcode='23503';
  end if;
  if v_project_id <> p_project_id then
    raise exception 'create_draft_version: asset does not belong to project %', p_project_id using errcode='23514';
  end if;
  if not public.lign_has_capability(v_project_id, v_workspace_id, 'version.upload') then
    raise exception 'create_draft_version: forbidden (version.upload)' using errcode='42501';
  end if;

  select coalesce(max(sequence),0)+1 into v_next_seq
    from public.asset_versions where design_asset_id = p_design_asset_id;

  insert into public.asset_versions (workspace_id, project_id, design_asset_id, sequence, label, notes, status)
  values (v_workspace_id, v_project_id, p_design_asset_id, v_next_seq, p_label, p_notes, 'draft')
  returning id into v_version_id;
  return v_version_id;
end $$;
revoke all on function public.create_draft_version(uuid,uuid,text,text) from public;
revoke all on function public.create_draft_version(uuid,uuid,text,text) from anon;
grant execute on function public.create_draft_version(uuid,uuid,text,text) to authenticated, service_role;

create or replace function public.attach_file_to_version(
  p_asset_version_id uuid, p_checksum_hex text, p_mime_type text,
  p_size_bytes bigint, p_storage_ref text,
  p_display_name text default null, p_role text default 'primary',
  p_sort_order integer default null
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_project_id uuid; v_status text; v_checksum bytea; v_file_id uuid; v_sort int; v_vf_id uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'attach_file_to_version: auth required' using errcode='42501'; end if;
  if p_asset_version_id is null then raise exception 'attach_file_to_version: asset_version_id required' using errcode='22004'; end if;
  if p_checksum_hex is null or length(p_checksum_hex) <> 64 then
    raise exception 'attach_file_to_version: checksum_hex must be 64-char sha256 hex' using errcode='22023';
  end if;
  if p_mime_type is null or length(trim(p_mime_type))=0 then raise exception 'attach_file_to_version: mime_type required' using errcode='22004'; end if;
  if p_size_bytes is null or p_size_bytes<0 then raise exception 'attach_file_to_version: size_bytes required nonneg' using errcode='22023'; end if;
  if p_storage_ref is null or length(trim(p_storage_ref))=0 then raise exception 'attach_file_to_version: storage_ref required' using errcode='22004'; end if;
  if p_role is null or p_role not in ('primary','reference','spec','source','export','other') then
    raise exception 'attach_file_to_version: invalid role %', coalesce(p_role,'(null)') using errcode='22023';
  end if;

  select workspace_id, project_id, status into v_workspace_id, v_project_id, v_status
    from public.asset_versions where id = p_asset_version_id for update;
  if v_workspace_id is null then
    raise exception 'attach_file_to_version: version % not found', p_asset_version_id using errcode='23503';
  end if;
  if v_status <> 'draft' then
    raise exception 'attach_file_to_version: version % is % (must be draft)', p_asset_version_id, v_status using errcode='23514';
  end if;
  if not (public.lign_has_capability(v_project_id, v_workspace_id, 'version.upload')
      and public.lign_has_capability(v_project_id, v_workspace_id, 'file.attach')) then
    raise exception 'attach_file_to_version: forbidden (version.upload+file.attach)' using errcode='42501';
  end if;

  v_checksum := decode(p_checksum_hex, 'hex');
  select id into v_file_id from public.files where workspace_id = v_workspace_id and checksum_sha256 = v_checksum;
  if v_file_id is null then
    insert into public.files (workspace_id, checksum_sha256, mime_type, size_bytes, storage_ref, uploaded_by_profile_id, status)
    values (v_workspace_id, v_checksum, p_mime_type, p_size_bytes, p_storage_ref, v_caller, 'active')
    returning id into v_file_id;
  end if;

  if p_sort_order is not null then
    v_sort := p_sort_order;
  else
    select coalesce(max(sort_order), -1) + 1 into v_sort
      from public.version_files where asset_version_id = p_asset_version_id;
  end if;

  insert into public.version_files (workspace_id, asset_version_id, file_id, display_name, role, sort_order)
  values (v_workspace_id, p_asset_version_id, v_file_id, p_display_name, p_role, v_sort)
  returning id into v_vf_id;
  return v_vf_id;
end $$;
revoke all on function public.attach_file_to_version(uuid,text,text,bigint,text,text,text,integer) from public;
revoke all on function public.attach_file_to_version(uuid,text,text,bigint,text,text,text,integer) from anon;
grant execute on function public.attach_file_to_version(uuid,text,text,bigint,text,text,text,integer) to authenticated, service_role;

create or replace function public.publish_version(p_asset_version_id uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_project_id uuid; v_design_asset_id uuid; v_status text; v_seq int;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'publish_version: auth required' using errcode='42501'; end if;
  select workspace_id, project_id, design_asset_id, status, sequence
    into v_workspace_id, v_project_id, v_design_asset_id, v_status, v_seq
    from public.asset_versions where id = p_asset_version_id for update;
  if v_workspace_id is null then raise exception 'publish_version: version not found' using errcode='23503'; end if;
  if v_status <> 'draft' then raise exception 'publish_version: version is % (must be draft)', v_status using errcode='23514'; end if;
  if not public.lign_has_capability(v_project_id, v_workspace_id, 'version.publish') then
    raise exception 'publish_version: forbidden (version.publish)' using errcode='42501';
  end if;

  update public.asset_versions
     set status='published', published_at=now(), published_by_profile_id=v_caller
   where id = p_asset_version_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_workspace_id, v_project_id, now(), 'version.published',
    v_caller, 'user', 'asset_version', p_asset_version_id, 'v'||v_seq,
    jsonb_build_object('design_asset_id', v_design_asset_id, 'sequence', v_seq), '{}'::jsonb);
  return p_asset_version_id;
end $$;
revoke all on function public.publish_version(uuid) from public;
revoke all on function public.publish_version(uuid) from anon;
grant execute on function public.publish_version(uuid) to authenticated, service_role;

create or replace function public.discard_draft_version(p_asset_version_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_project_id uuid; v_status text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'discard_draft_version: auth required' using errcode='42501'; end if;
  select workspace_id, project_id, status into v_workspace_id, v_project_id, v_status
    from public.asset_versions where id = p_asset_version_id for update;
  if v_workspace_id is null then raise exception 'discard_draft_version: version not found' using errcode='23503'; end if;
  if v_status <> 'draft' then raise exception 'discard_draft_version: version is % (must be draft)', v_status using errcode='23514'; end if;
  if not public.lign_has_capability(v_project_id, v_workspace_id, 'version.discard_draft') then
    raise exception 'discard_draft_version: forbidden (version.discard_draft)' using errcode='42501';
  end if;
  delete from public.version_files where asset_version_id = p_asset_version_id;
  delete from public.asset_versions where id = p_asset_version_id;
end $$;
revoke all on function public.discard_draft_version(uuid) from public;
revoke all on function public.discard_draft_version(uuid) from anon;
grant execute on function public.discard_draft_version(uuid) to authenticated, service_role;

create or replace function public.set_current_version(p_design_asset_id uuid, p_version_id uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_project_id uuid; v_v_asset uuid; v_v_status text; v_v_seq int; v_prev uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'set_current_version: auth required' using errcode='42501'; end if;
  if p_design_asset_id is null or p_version_id is null then
    raise exception 'set_current_version: ids required' using errcode='22004';
  end if;

  select workspace_id, project_id, current_version_id
    into v_workspace_id, v_project_id, v_prev
    from public.design_assets where id = p_design_asset_id for update;
  if v_workspace_id is null then raise exception 'set_current_version: asset not found' using errcode='23503'; end if;
  if not public.lign_has_capability(v_project_id, v_workspace_id, 'asset.set_current') then
    raise exception 'set_current_version: forbidden (asset.set_current)' using errcode='42501';
  end if;

  select design_asset_id, status, sequence into v_v_asset, v_v_status, v_v_seq
    from public.asset_versions where id = p_version_id;
  if v_v_asset is null then raise exception 'set_current_version: version not found' using errcode='23503'; end if;
  if v_v_asset <> p_design_asset_id then
    raise exception 'set_current_version: version does not belong to asset' using errcode='23514';
  end if;
  if v_v_status <> 'published' then
    raise exception 'set_current_version: version is % (must be published)', v_v_status using errcode='23514';
  end if;

  perform set_config('lign.allow_current_version_write','true', true);
  update public.design_assets set current_version_id = p_version_id where id = p_design_asset_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_workspace_id, v_project_id, now(), 'asset.current_version.changed',
    v_caller, 'user', 'design_asset', p_design_asset_id, 'v'||v_v_seq,
    jsonb_build_object('design_asset_id', p_design_asset_id, 'new_version_id', p_version_id, 'previous_version_id', v_prev, 'sequence', v_v_seq),
    '{}'::jsonb);
  return p_version_id;
end $$;
revoke all on function public.set_current_version(uuid,uuid) from public;
revoke all on function public.set_current_version(uuid,uuid) from anon;
grant execute on function public.set_current_version(uuid,uuid) to authenticated, service_role;

drop policy if exists design_assets_select on public.design_assets;
create policy design_assets_select on public.design_assets
  as permissive for select to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'asset.view'));

drop policy if exists design_assets_insert on public.design_assets;
create policy design_assets_insert on public.design_assets
  as permissive for insert to authenticated
  with check (public.lign_has_capability(project_id, workspace_id, 'asset.create')
              and created_by_profile_id = (select auth.uid()));

drop policy if exists design_assets_update on public.design_assets;
create policy design_assets_update on public.design_assets
  as permissive for update to authenticated
  using      (public.lign_has_capability(project_id, workspace_id, 'asset.edit'))
  with check (public.lign_has_capability(project_id, workspace_id, 'asset.edit'));

drop policy if exists asset_versions_select on public.asset_versions;
create policy asset_versions_select on public.asset_versions
  as permissive for select to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'version.view'));

drop policy if exists files_select on public.files;
create policy files_select on public.files
  as permissive for select to authenticated
  using (
    public.lign_is_workspace_admin(workspace_id)
    or exists (
      select 1 from public.version_files vf
      join public.asset_versions av on av.id = vf.asset_version_id
      where vf.file_id = files.id
        and public.lign_has_capability(av.project_id, av.workspace_id, 'file.download')
    )
  );

drop policy if exists version_files_select on public.version_files;
create policy version_files_select on public.version_files
  as permissive for select to authenticated
  using (
    exists (
      select 1 from public.asset_versions av
      where av.id = version_files.asset_version_id
        and public.lign_has_capability(av.project_id, av.workspace_id, 'version.view')
    )
  );