-- STORAGE 002 apply
alter table public.files drop constraint files_workspace_checksum_key;
create unique index files_workspace_checksum_key on public.files (workspace_id, checksum_sha256) where status <> 'purged';
comment on index public.files_workspace_checksum_key is 'STORAGE 002 (per STORAGE_ARCHITECTURE.md §7.1): partial unique index; purged rows do not occupy the checksum namespace so re-upload of the same binary after purge is permitted.';

insert into storage.buckets (id, name, public, file_size_limit)
values ('lign-files', 'lign-files', false, 500 * 1024 * 1024)
on conflict (id) do nothing;

create or replace function public.lign_can_download_file(p_file_id uuid, p_workspace_id uuid)
returns boolean language sql stable parallel safe security definer set search_path = ''
as $$
  select exists (select 1 from public.files f where f.id = p_file_id and f.workspace_id = p_workspace_id)
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
revoke all on function public.lign_can_download_file(uuid, uuid) from public;
revoke all on function public.lign_can_download_file(uuid, uuid) from anon;
grant execute on function public.lign_can_download_file(uuid, uuid) to authenticated, service_role;

create or replace function public.lign_can_upload_storage_object(p_object_name text)
returns boolean language sql stable parallel safe security definer set search_path = ''
as $$
  select exists (
    select 1 from public.files f
     where f.storage_ref = p_object_name
       and f.status = 'uploaded'
       and f.uploaded_by_profile_id = (select auth.uid())
  );
$$;
revoke all on function public.lign_can_upload_storage_object(text) from public;
revoke all on function public.lign_can_upload_storage_object(text) from anon;
grant execute on function public.lign_can_upload_storage_object(text) to authenticated, service_role;

drop policy if exists lign_files_select on storage.objects;
create policy lign_files_select on storage.objects as permissive for select to authenticated
  using (
    bucket_id = 'lign-files'
    and exists (
      select 1 from public.files f
       where f.storage_ref = objects.name
         and public.lign_can_download_file(f.id, f.workspace_id)
    )
  );

drop policy if exists lign_files_insert on storage.objects;
create policy lign_files_insert on storage.objects as permissive for insert to authenticated
  with check (
    bucket_id = 'lign-files'
    and public.lign_can_upload_storage_object(name)
  );