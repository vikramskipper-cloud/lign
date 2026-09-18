-- Migration 011 (APP 004): version_files write RLS
-- See /supabase/migrations/20260807180000_app_004_version_files_write_rls.sql for full documentation.

drop policy if exists version_files_update on public.version_files;
create policy version_files_update on public.version_files
  as permissive
  for update
  to authenticated
  using (
    exists (
      select 1
        from public.asset_versions av
       where av.id = version_files.asset_version_id
         and public.lign_has_capability(av.project_id, av.workspace_id, 'version.upload')
    )
  )
  with check (
    exists (
      select 1
        from public.asset_versions av
       where av.id = version_files.asset_version_id
         and public.lign_has_capability(av.project_id, av.workspace_id, 'version.upload')
    )
  );

drop policy if exists version_files_delete on public.version_files;
create policy version_files_delete on public.version_files
  as permissive
  for delete
  to authenticated
  using (
    exists (
      select 1
        from public.asset_versions av
       where av.id = version_files.asset_version_id
         and public.lign_has_capability(av.project_id, av.workspace_id, 'version.upload')
    )
  );
