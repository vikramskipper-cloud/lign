-- STORAGE 003: upload / finalize / File lifecycle workflow
--
-- Frozen sources: STORAGE 001/002, AUTH 001-009.
--
-- Delivers:
--   * start_version_file_upload  — reservation, race-safe dedup dispatch
--   * finalize_version_file_upload  — verify Storage object + attach VersionFile
--   * publish_version  — hardened: rejects if any attachment is not active
--   * discard_draft_version  — orphan-aware: transitions unreferenced Files
--     to orphaned, never physically deletes
--   * attach_file_to_version  — dropped (client-supplied storage_ref path)
--
-- No physical purge. No stale-upload sweep. No Edge Function. No cron.
-- Those belong to STORAGE 004.
--
-- Event vocabulary: canonical `file.attached` from EVENT_MODEL.md §4.6.
-- No new event names. `file.uploaded` and `file.orphaned` are explicitly
-- deferred (§4.14) and NOT emitted here.

------------------------------------------------------------------------------
-- 1. Drop the unsafe RPC
------------------------------------------------------------------------------

drop function if exists public.attach_file_to_version(uuid, text, text, bigint, text, text, text, integer);

------------------------------------------------------------------------------
-- 2. start_version_file_upload
------------------------------------------------------------------------------

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
  v_caller           uuid;
  v_workspace_id     uuid;
  v_project_id       uuid;
  v_version_status   text;
  v_checksum         bytea;
  v_new_file_id      uuid;
  v_new_storage_ref  text;
  v_existing_id      uuid;
  v_existing_status  text;
  v_existing_uploader uuid;
  v_existing_ref     text;
  v_action           text;
  v_return_file_id   uuid;
  v_return_ref       text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'start_version_file_upload: authentication required' using errcode='42501';
  end if;

  if p_asset_version_id is null then
    raise exception 'start_version_file_upload: asset_version_id required' using errcode='22004';
  end if;
  if p_checksum_hex is null or length(p_checksum_hex) <> 64 then
    raise exception 'start_version_file_upload: checksum_hex must be 64-char sha256 hex' using errcode='22023';
  end if;
  if p_mime_type is null or length(trim(p_mime_type))=0 then
    raise exception 'start_version_file_upload: mime_type required' using errcode='22004';
  end if;
  if p_size_bytes is null or p_size_bytes <= 0 then
    raise exception 'start_version_file_upload: size_bytes must be > 0' using errcode='22023';
  end if;
  if p_size_bytes > 500 * 1024 * 1024 then
    raise exception 'start_version_file_upload: size_bytes exceeds 500 MB limit' using errcode='22023';
  end if;
  if lower(trim(p_mime_type)) = any (array[
    'application/x-msdownload',
    'application/x-msdos-program',
    'application/x-executable',
    'application/x-sh',
    'application/x-shellscript',
    'text/x-shellscript'
  ]) then
    raise exception 'start_version_file_upload: mime_type % is denied', p_mime_type using errcode='22023';
  end if;

  select workspace_id, project_id, status
    into v_workspace_id, v_project_id, v_version_status
    from public.asset_versions where id = p_asset_version_id;
  if v_workspace_id is null then
    raise exception 'start_version_file_upload: asset_version not found' using errcode='23503';
  end if;
  if v_version_status <> 'draft' then
    raise exception 'start_version_file_upload: version is % (must be draft)', v_version_status using errcode='23514';
  end if;

  if not (
        public.lign_has_capability(v_project_id, v_workspace_id, 'version.upload')
    and public.lign_has_capability(v_project_id, v_workspace_id, 'file.attach')
  ) then
    raise exception 'start_version_file_upload: forbidden (version.upload + file.attach)' using errcode='42501';
  end if;

  v_checksum := decode(p_checksum_hex, 'hex');
  v_new_file_id := gen_random_uuid();
  v_new_storage_ref := v_workspace_id::text || '/' || v_new_file_id::text;

  -- Race-safe dedup: try to insert a fresh reservation. Partial unique index
  -- on (workspace_id, checksum_sha256) WHERE status <> 'purged' is authoritative.
  insert into public.files (
    id, workspace_id, checksum_sha256, mime_type, size_bytes,
    storage_ref, uploaded_by_profile_id, status
  ) values (
    v_new_file_id, v_workspace_id, v_checksum, p_mime_type, p_size_bytes,
    v_new_storage_ref, v_caller, 'uploaded'
  )
  on conflict (workspace_id, checksum_sha256) where status <> 'purged' do nothing
  returning id, storage_ref into v_return_file_id, v_return_ref;

  if v_return_file_id is not null then
    v_action := 'upload_required';
  else
    -- Existing non-purged row; dispatch on its status
    select id, status, uploaded_by_profile_id, storage_ref
      into v_existing_id, v_existing_status, v_existing_uploader, v_existing_ref
      from public.files
     where workspace_id = v_workspace_id
       and checksum_sha256 = v_checksum
       and status <> 'purged'
     for update;

    if v_existing_status = 'active' then
      v_action := 'reused';
    elsif v_existing_status = 'uploaded' then
      if v_existing_uploader = v_caller then
        v_action := 'upload_required';
      else
        v_action := 'in_progress';
      end if;
    elsif v_existing_status = 'orphaned' then
      update public.files
         set status = 'uploaded',
             orphaned_at = null,
             uploaded_by_profile_id = v_caller
       where id = v_existing_id;
      v_action := 'reclaimed';
    else
      raise exception 'start_version_file_upload: unexpected existing file status %', v_existing_status using errcode='XX000';
    end if;

    v_return_file_id := v_existing_id;
    v_return_ref     := v_existing_ref;
  end if;

  return query
    select v_return_file_id, v_action, 'lign-files'::text, v_return_ref, p_size_bytes, p_mime_type;
end $$;

comment on function public.start_version_file_upload(uuid, text, text, bigint) is
  'STORAGE 003: creates a File reservation (or dispatches dedup). Never accepts client-supplied workspace/project/storage_ref/uploaded_by. Returns action: upload_required | reused | in_progress | reclaimed. OUT columns are out_-prefixed to avoid PL/pgSQL variable collision with table column names.';

revoke all on function public.start_version_file_upload(uuid, text, text, bigint) from public;
revoke all on function public.start_version_file_upload(uuid, text, text, bigint) from anon;
grant execute on function public.start_version_file_upload(uuid, text, text, bigint) to authenticated, service_role;

------------------------------------------------------------------------------
-- 3. finalize_version_file_upload
------------------------------------------------------------------------------

create or replace function public.finalize_version_file_upload(
  p_file_id          uuid,
  p_asset_version_id uuid,
  p_display_name     text default null,
  p_role             text default 'primary',
  p_sort_order       integer default null
)
returns table (
  out_file_id          uuid,
  out_version_files_id uuid,
  out_action           text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller           uuid;
  v_f_workspace_id   uuid;
  v_f_status         text;
  v_f_size_bytes     bigint;
  v_f_storage_ref    text;
  v_v_workspace_id   uuid;
  v_v_project_id     uuid;
  v_v_status         text;
  v_expected_ref     text;
  v_object_metadata  jsonb;
  v_object_size      bigint;
  v_vf_id            uuid;
  v_sort             integer;
  v_action           text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'finalize_version_file_upload: authentication required' using errcode='42501';
  end if;
  if p_file_id is null or p_asset_version_id is null then
    raise exception 'finalize_version_file_upload: file_id and asset_version_id required' using errcode='22004';
  end if;
  if p_role is null or p_role not in ('primary','reference','spec','source','export','other') then
    raise exception 'finalize_version_file_upload: invalid role %', coalesce(p_role,'(null)') using errcode='22023';
  end if;

  -- Lock the file row
  select workspace_id, status, size_bytes, storage_ref
    into v_f_workspace_id, v_f_status, v_f_size_bytes, v_f_storage_ref
    from public.files where id = p_file_id for update;
  if v_f_workspace_id is null then
    raise exception 'finalize_version_file_upload: file % not found', p_file_id using errcode='23503';
  end if;
  if v_f_status not in ('uploaded','active') then
    raise exception 'finalize_version_file_upload: file % is % (must be uploaded or active)', p_file_id, v_f_status using errcode='23514';
  end if;

  -- Load the version (also with lock to serialize concurrent attach + publish)
  select workspace_id, project_id, status
    into v_v_workspace_id, v_v_project_id, v_v_status
    from public.asset_versions where id = p_asset_version_id for update;
  if v_v_workspace_id is null then
    raise exception 'finalize_version_file_upload: asset_version % not found', p_asset_version_id using errcode='23503';
  end if;
  if v_v_status <> 'draft' then
    raise exception 'finalize_version_file_upload: version is % (must be draft)', v_v_status using errcode='23514';
  end if;

  -- Cross-workspace coherence
  if v_f_workspace_id <> v_v_workspace_id then
    raise exception 'finalize_version_file_upload: file/version workspace mismatch' using errcode='23514';
  end if;

  -- Re-authorize
  if not (
        public.lign_has_capability(v_v_project_id, v_v_workspace_id, 'version.upload')
    and public.lign_has_capability(v_v_project_id, v_v_workspace_id, 'file.attach')
  ) then
    raise exception 'finalize_version_file_upload: forbidden (version.upload + file.attach)' using errcode='42501';
  end if;

  -- Verify canonical storage_ref shape: '{workspace_id}/{file_id}'
  v_expected_ref := v_f_workspace_id::text || '/' || p_file_id::text;
  if v_f_storage_ref is distinct from v_expected_ref then
    raise exception 'finalize_version_file_upload: storage_ref % does not match canonical form', v_f_storage_ref using errcode='23514';
  end if;

  -- Verify storage.objects presence
  select metadata into v_object_metadata
    from storage.objects
   where bucket_id = 'lign-files' and name = v_expected_ref;
  if not found then
    raise exception 'finalize_version_file_upload: storage object missing at % (upload not completed)', v_expected_ref using errcode='23514';
  end if;

  -- Verify size (best-effort: only if metadata carries a size value)
  v_object_size := nullif(v_object_metadata->>'size','')::bigint;
  if v_object_size is not null and v_object_size <> v_f_size_bytes then
    raise exception 'finalize_version_file_upload: storage object size % does not match declared %', v_object_size, v_f_size_bytes using errcode='23514';
  end if;

  -- Transition uploaded -> active (no-op if already active for reuse path)
  if v_f_status = 'uploaded' then
    update public.files set status = 'active' where id = p_file_id;
  end if;

  -- Resolve sort_order
  if p_sort_order is not null then
    v_sort := p_sort_order;
  else
    select coalesce(max(sort_order),-1)+1 into v_sort
      from public.version_files where asset_version_id = p_asset_version_id;
  end if;

  -- Idempotent version_files insert on (asset_version_id, file_id) UNIQUE
  insert into public.version_files (
    workspace_id, asset_version_id, file_id, display_name, role, sort_order
  ) values (
    v_v_workspace_id, p_asset_version_id, p_file_id, p_display_name, p_role, v_sort
  )
  on conflict (asset_version_id, file_id) do nothing
  returning id into v_vf_id;

  if v_vf_id is null then
    -- Already attached; idempotent success — return existing row info
    select id into v_vf_id from public.version_files
     where asset_version_id = p_asset_version_id and file_id = p_file_id;
    v_action := 'already_attached';
  else
    v_action := 'attached';

    -- Emit canonical file.attached event (EVENT_MODEL §4.6) only on new attach
    insert into public.activity_events (
      workspace_id, project_id, occurred_at, event_type,
      actor_profile_id, actor_kind,
      subject_kind, subject_id, subject_label, subject_snapshot, payload
    ) values (
      v_v_workspace_id, v_v_project_id, now(), 'file.attached',
      v_caller, 'user',
      'version_file', v_vf_id, coalesce(p_display_name, ''),
      jsonb_build_object('file_id', p_file_id, 'asset_version_id', p_asset_version_id, 'role', p_role),
      '{}'::jsonb
    );
  end if;

  return query select p_file_id, v_vf_id, v_action;
end $$;

comment on function public.finalize_version_file_upload(uuid, uuid, text, text, integer) is
  'STORAGE 003: verifies Storage object presence + size, promotes uploaded->active, atomically creates version_files. Idempotent per (asset_version_id, file_id). Emits canonical file.attached event on new attach. OUT columns out_-prefixed to avoid PL/pgSQL name collision with table columns.';

revoke all on function public.finalize_version_file_upload(uuid, uuid, text, text, integer) from public;
revoke all on function public.finalize_version_file_upload(uuid, uuid, text, text, integer) from anon;
grant execute on function public.finalize_version_file_upload(uuid, uuid, text, text, integer) to authenticated, service_role;

------------------------------------------------------------------------------
-- 4. publish_version hardening
------------------------------------------------------------------------------
-- Adds a defensive check: reject publication if any version_files attachment
-- references a File whose status is not 'active'. All other behavior is
-- preserved verbatim from AUTH 004.

create or replace function public.publish_version(p_asset_version_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller           uuid;
  v_workspace_id     uuid;
  v_project_id       uuid;
  v_design_asset_id  uuid;
  v_status           text;
  v_seq              integer;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'publish_version: auth required' using errcode='42501'; end if;

  select workspace_id, project_id, design_asset_id, status, sequence
    into v_workspace_id, v_project_id, v_design_asset_id, v_status, v_seq
    from public.asset_versions
   where id = p_asset_version_id
   for update;
  if v_workspace_id is null then raise exception 'publish_version: version not found' using errcode='23503'; end if;
  if v_status <> 'draft' then raise exception 'publish_version: version is % (must be draft)', v_status using errcode='23514'; end if;

  if not public.lign_has_capability(v_project_id, v_workspace_id, 'version.publish') then
    raise exception 'publish_version: forbidden (version.publish)' using errcode='42501';
  end if;

  -- STORAGE 003 hardening: every attachment must reference an active File.
  if exists (
    select 1 from public.version_files vf
    join public.files f on f.id = vf.file_id
    where vf.asset_version_id = p_asset_version_id
      and f.status <> 'active'
  ) then
    raise exception 'publish_version: version has non-active file attachments' using errcode='23514';
  end if;

  update public.asset_versions
     set status='published', published_at=now(), published_by_profile_id=v_caller
   where id = p_asset_version_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_workspace_id, v_project_id, now(), 'version.published',
    v_caller, 'user', 'asset_version', p_asset_version_id, 'v'||v_seq,
    jsonb_build_object('design_asset_id', v_design_asset_id, 'sequence', v_seq), '{}'::jsonb
  );

  return p_asset_version_id;
end $$;

revoke all on function public.publish_version(uuid) from public;
revoke all on function public.publish_version(uuid) from anon;
grant execute on function public.publish_version(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 5. discard_draft_version orphan handling
------------------------------------------------------------------------------
-- Collects affected file_ids, deletes version_files + draft, then for each
-- File with zero remaining references transitions active -> orphaned.
-- Never orphans a still-referenced or non-active File. No physical delete.

create or replace function public.discard_draft_version(p_asset_version_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller       uuid;
  v_workspace_id uuid;
  v_project_id   uuid;
  v_status       text;
  v_file_ids     uuid[];
  v_fid          uuid;
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

  -- STORAGE 003: collect affected file_ids before deletion
  select array_agg(distinct file_id) into v_file_ids
    from public.version_files where asset_version_id = p_asset_version_id;

  delete from public.version_files where asset_version_id = p_asset_version_id;
  delete from public.asset_versions where id = p_asset_version_id;

  -- Orphan handling: for each affected File, if zero references remain
  -- AND status is currently 'active', transition to 'orphaned'.
  if v_file_ids is not null then
    foreach v_fid in array v_file_ids loop
      if not exists (select 1 from public.version_files where file_id = v_fid) then
        update public.files
           set status = 'orphaned', orphaned_at = now()
         where id = v_fid and status = 'active';
      end if;
    end loop;
  end if;
end $$;

revoke all on function public.discard_draft_version(uuid) from public;
revoke all on function public.discard_draft_version(uuid) from anon;
grant execute on function public.discard_draft_version(uuid) to authenticated, service_role;
