-- Migration 011 (APP 004): version_files write RLS
--
-- Adds RLS UPDATE and DELETE policies to public.version_files so the approved
-- APP 004 draft-mutation UX (change role, rename display_name, drag-reorder
-- sort_order, remove attachment) can be issued directly by authenticated
-- callers.
--
-- Layered defense:
--   * This migration: capability check on 'version.upload' (same key that
--     gates finalize_version_file_upload). Same role preset already has it.
--   * Pre-existing DB-boundary trigger enforce_version_files_parent_draft_mutation
--     (Migration 004): rejects any INSERT/UPDATE/DELETE unless parent
--     asset_versions.status = 'draft'. Preserves the "published versions are
--     immutable" invariant unconditionally.
--
-- Not added:
--   * No INSERT policy — inserts continue to flow through
--     finalize_version_file_upload (STORAGE 003), preserving the
--     dedup/uploaded->active transition and file.attached event emission.
--   * No new capability keys.
--
-- Transaction control: none inline. Supabase migration runner wraps.

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
