alter table public.files
  add column if not exists purge_reserved_at timestamptz,
  add column if not exists purge_reserved_by text;

comment on column public.files.purge_reserved_at is
  'STORAGE 004: set by claim_file_for_purge to atomically reserve an orphaned File for in-flight physical deletion. While non-null the row is excluded from the checksum partial unique index and from start_version_file_upload''s orphan-reclaim dispatch, preventing an orphaned → uploaded reclaim from racing the Storage HTTP DELETE. Cleared by release_purge_claim on worker abort; preserved through mark_file_purged for audit.';

comment on column public.files.purge_reserved_by is
  'STORAGE 004: opaque identifier of the purge worker/operator that holds the current reservation.';

drop index if exists public.files_workspace_checksum_key;
create unique index files_workspace_checksum_key
  on public.files (workspace_id, checksum_sha256)
  where status <> 'purged' and purge_reserved_at is null;

comment on index public.files_workspace_checksum_key is
  'STORAGE 004 amendment of STORAGE 002 §7.1: partial unique index excludes both purged rows AND rows reserved for physical deletion so a same-checksum re-upload can proceed while an orphaned predecessor is being purged.';

create or replace function public.start_version_file_upload(
  p_asset_version_id uuid,
  p_checksum_hex     text,
  p_mime_type        text,
  p_size_bytes       bigint
)
returns table (
  out_file_id     uuid,
  out_action      text,
  out_bucket      text,
  out_object_path text,
  out_size_bytes  bigint,
  out_mime_type   text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller            uuid;
  v_workspace_id      uuid;
  v_project_id        uuid;
  v_version_status    text;
  v_checksum          bytea;
  v_new_file_id       uuid;
  v_new_storage_ref   text;
  v_existing_id       uuid;
  v_existing_status   text;
  v_existing_uploader uuid;
  v_existing_ref      text;
  v_action            text;
  v_return_file_id    uuid;
  v_return_ref        text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'start_version_file_upload: authentication required' using errcode='42501'; end if;
  if p_asset_version_id is null then raise exception 'start_version_file_upload: asset_version_id required' using errcode='22004'; end if;
  if p_checksum_hex is null or length(p_checksum_hex) <> 64 then raise exception 'start_version_file_upload: checksum_hex must be 64-char sha256 hex' using errcode='22023'; end if;
  if p_mime_type is null or length(trim(p_mime_type))=0 then raise exception 'start_version_file_upload: mime_type required' using errcode='22004'; end if;
  if p_size_bytes is null or p_size_bytes <= 0 then raise exception 'start_version_file_upload: size_bytes must be > 0' using errcode='22023'; end if;
  if p_size_bytes > 500 * 1024 * 1024 then raise exception 'start_version_file_upload: size_bytes exceeds 500 MB limit' using errcode='22023'; end if;
  if lower(trim(p_mime_type)) = any (array[
    'application/x-msdownload','application/x-msdos-program',
    'application/x-executable','application/x-sh',
    'application/x-shellscript','text/x-shellscript'
  ]) then raise exception 'start_version_file_upload: mime_type % is denied', p_mime_type using errcode='22023'; end if;

  select workspace_id, project_id, status into v_workspace_id, v_project_id, v_version_status
    from public.asset_versions where id = p_asset_version_id;
  if v_workspace_id is null then raise exception 'start_version_file_upload: asset_version not found' using errcode='23503'; end if;
  if v_version_status <> 'draft' then raise exception 'start_version_file_upload: version is % (must be draft)', v_version_status using errcode='23514'; end if;

  if not (
        public.lign_has_capability(v_project_id, v_workspace_id, 'version.upload')
    and public.lign_has_capability(v_project_id, v_workspace_id, 'file.attach')
  ) then raise exception 'start_version_file_upload: forbidden (version.upload + file.attach)' using errcode='42501'; end if;

  v_checksum := decode(p_checksum_hex, 'hex');
  v_new_file_id := gen_random_uuid();
  v_new_storage_ref := v_workspace_id::text || '/' || v_new_file_id::text;

  insert into public.files (
    id, workspace_id, checksum_sha256, mime_type, size_bytes,
    storage_ref, uploaded_by_profile_id, status
  ) values (
    v_new_file_id, v_workspace_id, v_checksum, p_mime_type, p_size_bytes,
    v_new_storage_ref, v_caller, 'uploaded'
  )
  on conflict (workspace_id, checksum_sha256)
    where status <> 'purged' and purge_reserved_at is null
    do nothing
  returning id, storage_ref into v_return_file_id, v_return_ref;

  if v_return_file_id is not null then
    v_action := 'upload_required';
  else
    select id, status, uploaded_by_profile_id, storage_ref
      into v_existing_id, v_existing_status, v_existing_uploader, v_existing_ref
      from public.files
     where workspace_id = v_workspace_id
       and checksum_sha256 = v_checksum
       and status <> 'purged'
       and purge_reserved_at is null
     for update;

    if v_existing_status = 'active' then v_action := 'reused';
    elsif v_existing_status = 'uploaded' then
      if v_existing_uploader = v_caller then v_action := 'upload_required';
      else v_action := 'in_progress'; end if;
    elsif v_existing_status = 'orphaned' then
      update public.files
         set status='uploaded', orphaned_at=null, uploaded_by_profile_id=v_caller
       where id = v_existing_id;
      v_action := 'reclaimed';
    else raise exception 'start_version_file_upload: unexpected existing file status %', v_existing_status using errcode='XX000'; end if;

    v_return_file_id := v_existing_id;
    v_return_ref     := v_existing_ref;
  end if;

  return query select v_return_file_id, v_action, 'lign-files'::text, v_return_ref, p_size_bytes, p_mime_type;
end $$;

revoke all on function public.start_version_file_upload(uuid, text, text, bigint) from public;
revoke all on function public.start_version_file_upload(uuid, text, text, bigint) from anon;
grant execute on function public.start_version_file_upload(uuid, text, text, bigint) to authenticated, service_role;

create or replace function public.sweep_stale_uploads()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare v_count integer;
begin
  with candidates as (
    select f.id from public.files f
     where f.status = 'uploaded'
       and f.created_at < now() - interval '24 hours'
       and f.purge_reserved_at is null
       and not exists (select 1 from public.version_files vf where vf.file_id = f.id)
     for update skip locked
  ),
  updated as (
    update public.files f set status='orphaned', orphaned_at=now()
      from candidates c where f.id = c.id returning f.id
  )
  select count(*)::int into v_count from updated;
  return v_count;
end $$;

revoke all on function public.sweep_stale_uploads() from public;
revoke all on function public.sweep_stale_uploads() from anon;
revoke all on function public.sweep_stale_uploads() from authenticated;
grant execute on function public.sweep_stale_uploads() to service_role;

create or replace function public.list_purgeable_files(p_limit integer default 100)
returns table (file_id uuid, workspace_id uuid, storage_ref text)
language sql stable security definer set search_path = ''
as $$
  select f.id, f.workspace_id, f.storage_ref
    from public.files f
   where f.status = 'orphaned'
     and f.orphaned_at is not null
     and f.orphaned_at <= now() - interval '30 days'
     and f.purge_reserved_at is null
     and not exists (select 1 from public.version_files vf where vf.file_id = f.id)
   order by f.orphaned_at
   limit greatest(0, coalesce(p_limit, 100));
$$;

revoke all on function public.list_purgeable_files(integer) from public;
revoke all on function public.list_purgeable_files(integer) from anon;
revoke all on function public.list_purgeable_files(integer) from authenticated;
grant execute on function public.list_purgeable_files(integer) to service_role;

create or replace function public.claim_file_for_purge(p_file_id uuid, p_worker text default 'system')
returns table (file_id uuid, workspace_id uuid, bucket text, storage_ref text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_workspace_id uuid; v_status text; v_orphaned_at timestamptz;
  v_storage_ref text; v_reserved_at timestamptz;
  v_expected_ref text; v_refcount integer;
begin
  if p_file_id is null then raise exception 'claim_file_for_purge: file_id required' using errcode='22004'; end if;
  select workspace_id, status, orphaned_at, storage_ref, purge_reserved_at
    into v_workspace_id, v_status, v_orphaned_at, v_storage_ref, v_reserved_at
    from public.files where id = p_file_id for update;
  if v_workspace_id is null then raise exception 'claim_file_for_purge: file % not found', p_file_id using errcode='23503'; end if;
  if v_status <> 'orphaned' then raise exception 'claim_file_for_purge: file % is % (must be orphaned)', p_file_id, v_status using errcode='23514'; end if;
  if v_orphaned_at is null or v_orphaned_at > now() - interval '30 days' then
    raise exception 'claim_file_for_purge: file % has not reached 30-day retention (orphaned_at=%)', p_file_id, v_orphaned_at using errcode='23514';
  end if;
  if v_reserved_at is not null then raise exception 'claim_file_for_purge: file % is already reserved (since %)', p_file_id, v_reserved_at using errcode='23514'; end if;
  v_expected_ref := v_workspace_id::text || '/' || p_file_id::text;
  if v_storage_ref is distinct from v_expected_ref then raise exception 'claim_file_for_purge: file % has non-canonical storage_ref %', p_file_id, v_storage_ref using errcode='23514'; end if;
  select count(*) into v_refcount from public.version_files where file_id = p_file_id;
  if v_refcount > 0 then raise exception 'claim_file_for_purge: file % has % version_files reference(s)', p_file_id, v_refcount using errcode='23514'; end if;

  update public.files set purge_reserved_at=now(), purge_reserved_by=coalesce(nullif(trim(p_worker),''), 'system') where id = p_file_id;
  return query select p_file_id, v_workspace_id, 'lign-files'::text, v_storage_ref;
end $$;

revoke all on function public.claim_file_for_purge(uuid, text) from public;
revoke all on function public.claim_file_for_purge(uuid, text) from anon;
revoke all on function public.claim_file_for_purge(uuid, text) from authenticated;
grant execute on function public.claim_file_for_purge(uuid, text) to service_role;

create or replace function public.release_purge_claim(p_file_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_status text; v_reserved_at timestamptz;
begin
  if p_file_id is null then raise exception 'release_purge_claim: file_id required' using errcode='22004'; end if;
  select status, purge_reserved_at into v_status, v_reserved_at from public.files where id = p_file_id for update;
  if v_status is null then raise exception 'release_purge_claim: file % not found', p_file_id using errcode='23503'; end if;
  if v_status = 'purged' then raise exception 'release_purge_claim: file % is already purged (cannot release)', p_file_id using errcode='23514'; end if;
  if v_reserved_at is null then return; end if;
  update public.files set purge_reserved_at=null, purge_reserved_by=null where id = p_file_id;
end $$;

revoke all on function public.release_purge_claim(uuid) from public;
revoke all on function public.release_purge_claim(uuid) from anon;
revoke all on function public.release_purge_claim(uuid) from authenticated;
grant execute on function public.release_purge_claim(uuid) to service_role;

create or replace function public.mark_file_purged(p_file_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare
  v_workspace_id uuid; v_status text; v_orphaned_at timestamptz;
  v_storage_ref text; v_reserved_at timestamptz; v_checksum bytea;
  v_expected_ref text; v_refcount integer;
begin
  if p_file_id is null then raise exception 'mark_file_purged: file_id required' using errcode='22004'; end if;
  select workspace_id, status, orphaned_at, storage_ref, purge_reserved_at, checksum_sha256
    into v_workspace_id, v_status, v_orphaned_at, v_storage_ref, v_reserved_at, v_checksum
    from public.files where id = p_file_id for update;
  if v_workspace_id is null then raise exception 'mark_file_purged: file % not found', p_file_id using errcode='23503'; end if;
  if v_status = 'purged' then return false; end if;
  if v_status <> 'orphaned' then raise exception 'mark_file_purged: file % is % (must be orphaned)', p_file_id, v_status using errcode='23514'; end if;
  if v_orphaned_at is null or v_orphaned_at > now() - interval '30 days' then raise exception 'mark_file_purged: file % has not reached 30-day retention', p_file_id using errcode='23514'; end if;
  if v_reserved_at is null then raise exception 'mark_file_purged: file % is not claim-reserved (call claim_file_for_purge first)', p_file_id using errcode='23514'; end if;
  v_expected_ref := v_workspace_id::text || '/' || p_file_id::text;
  if v_storage_ref is distinct from v_expected_ref then raise exception 'mark_file_purged: file % has non-canonical storage_ref %', p_file_id, v_storage_ref using errcode='23514'; end if;
  select count(*) into v_refcount from public.version_files where file_id = p_file_id;
  if v_refcount > 0 then raise exception 'mark_file_purged: file % has % version_files reference(s)', p_file_id, v_refcount using errcode='23514'; end if;

  update public.files set status='purged', purged_at=now() where id = p_file_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_workspace_id, null, now(), 'file.purged',
    null, 'system', 'file', p_file_id, null,
    jsonb_build_object('file_id', p_file_id, 'checksum_sha256', encode(v_checksum,'hex'), 'storage_ref', v_storage_ref),
    '{}'::jsonb
  );
  return true;
end $$;

revoke all on function public.mark_file_purged(uuid) from public;
revoke all on function public.mark_file_purged(uuid) from anon;
revoke all on function public.mark_file_purged(uuid) from authenticated;
grant execute on function public.mark_file_purged(uuid) to service_role;
