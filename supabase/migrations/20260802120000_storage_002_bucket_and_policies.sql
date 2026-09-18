-- STORAGE 002: bucket + authorization boundary
--
-- 1. Narrow V1 amendment: replace files_workspace_checksum_key with a partial
--    unique index that excludes purged rows, per STORAGE_ARCHITECTURE.md §7.1.
-- 2. Create the private bucket lign-files (500 MB per-object limit).
-- 3. Install two SECURITY DEFINER helpers used by storage.objects policies.
-- 4. Install storage.objects SELECT + INSERT policies scoped to lign-files.
--    No UPDATE / no DELETE policies (immutability).
--
-- No RPCs, no application code, no changes to publish_version /
-- discard_draft_version / create_draft_version / set_current_version /
-- attach_file_to_version (those belong to STORAGE 003).

------------------------------------------------------------------------------
-- 1. Post-purge uniqueness amendment
------------------------------------------------------------------------------
-- Drops the table-level UNIQUE constraint and replaces it with a partial
-- UNIQUE INDEX of the same name so that purged files no longer occupy the
-- unique namespace. Applied atomically inside this migration transaction.

alter table public.files
  drop constraint files_workspace_checksum_key;

create unique index files_workspace_checksum_key
  on public.files (workspace_id, checksum_sha256)
  where status <> 'purged';

comment on index public.files_workspace_checksum_key is
  'STORAGE 002 (per STORAGE_ARCHITECTURE.md §7.1): partial unique index; purged rows do not occupy the checksum namespace so re-upload of the same binary after purge is permitted.';

------------------------------------------------------------------------------
-- 2. Bucket
------------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit)
values ('lign-files', 'lign-files', false, 500 * 1024 * 1024)
on conflict (id) do nothing;

------------------------------------------------------------------------------
-- 3a. lign_can_download_file — SELECT authorization helper
------------------------------------------------------------------------------

create or replace function public.lign_can_download_file(
  p_file_id uuid,
  p_workspace_id uuid
) returns boolean
language sql
stable
parallel safe
security definer
set search_path = ''
as $$
  -- Coherence gate: the file must actually belong to the claimed workspace.
  select exists (
    select 1 from public.files f
     where f.id = p_file_id and f.workspace_id = p_workspace_id
  )
  and (
    public.lign_is_workspace_admin(p_workspace_id)
    or exists (
      select 1
        from public.version_files vf
        join public.asset_versions av on av.id = vf.asset_version_id
       where vf.file_id = p_file_id
         and public.lign_has_capability(av.project_id, av.workspace_id, 'file.download')
    )
  );
$$;

comment on function public.lign_can_download_file(uuid, uuid) is
  'STORAGE 002: download authorization for a File. Mirrors the frozen files SELECT rule (workspace admin OR version_files→asset_versions with file.download). SECURITY DEFINER + search_path='''' avoids RLS cascade through public.files/version_files/asset_versions and preserves recursion safety. Called from storage.objects SELECT policy for lign-files.';

revoke all on function public.lign_can_download_file(uuid, uuid) from public;
revoke all on function public.lign_can_download_file(uuid, uuid) from anon;
grant execute on function public.lign_can_download_file(uuid, uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 3b. lign_can_upload_storage_object — INSERT reservation authorization helper
------------------------------------------------------------------------------
-- Required because a reserved files row (status='uploaded', no version_files
-- yet) is invisible to the reserving caller under public.files SELECT RLS —
-- the storage.objects INSERT policy cannot evaluate the reservation without
-- a DEFINER bypass. Scope is strictly narrower than the download helper.

create or replace function public.lign_can_upload_storage_object(
  p_object_name text
) returns boolean
language sql
stable
parallel safe
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.files f
     where f.storage_ref = p_object_name
       and f.status = 'uploaded'
       and f.uploaded_by_profile_id = (select auth.uid())
  );
$$;

comment on function public.lign_can_upload_storage_object(text) is
  'STORAGE 002: upload-reservation authorization for storage.objects INSERT. Requires a matching files row with storage_ref=name, status=''uploaded'', and uploaded_by_profile_id = auth.uid(). SECURITY DEFINER because reserved files are invisible to the caller under public.files SELECT RLS until finalize.';

revoke all on function public.lign_can_upload_storage_object(text) from public;
revoke all on function public.lign_can_upload_storage_object(text) from anon;
grant execute on function public.lign_can_upload_storage_object(text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 4. storage.objects policies (scoped to bucket lign-files)
------------------------------------------------------------------------------

drop policy if exists lign_files_select on storage.objects;
create policy lign_files_select on storage.objects
  as permissive
  for select
  to authenticated
  using (
    bucket_id = 'lign-files'
    and exists (
      select 1
        from public.files f
       where f.storage_ref = objects.name
         and public.lign_can_download_file(f.id, f.workspace_id)
    )
  );

drop policy if exists lign_files_insert on storage.objects;
create policy lign_files_insert on storage.objects
  as permissive
  for insert
  to authenticated
  with check (
    bucket_id = 'lign-files'
    and public.lign_can_upload_storage_object(name)
  );

-- No UPDATE policy → no authenticated overwrite / metadata mutation.
-- No DELETE policy → only service_role can delete (STORAGE 004 purge path).
