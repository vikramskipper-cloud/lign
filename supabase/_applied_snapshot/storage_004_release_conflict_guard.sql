create or replace function public.release_purge_claim(p_file_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_workspace_id uuid; v_status text; v_reserved_at timestamptz;
  v_checksum bytea; v_conflict boolean;
begin
  if p_file_id is null then raise exception 'release_purge_claim: file_id required' using errcode='22004'; end if;
  select workspace_id, status, purge_reserved_at, checksum_sha256
    into v_workspace_id, v_status, v_reserved_at, v_checksum
    from public.files where id = p_file_id for update;
  if v_status is null then raise exception 'release_purge_claim: file % not found', p_file_id using errcode='23503'; end if;
  if v_status = 'purged' then raise exception 'release_purge_claim: file % is already purged (cannot release)', p_file_id using errcode='23514'; end if;
  if v_reserved_at is null then return; end if;

  -- STORAGE 004 race guard: if a fresh row for the same (workspace, checksum)
  -- was created while this row was reserved (start_version_file_upload's
  -- partial-index-bypass path), clearing the reservation here would violate
  -- files_workspace_checksum_key. In that case the reserved row is stranded
  -- and the operator must complete the physical DELETE and call
  -- mark_file_purged instead (purged rows are excluded from the index).
  select exists (
    select 1 from public.files f2
     where f2.workspace_id  = v_workspace_id
       and f2.checksum_sha256 = v_checksum
       and f2.id <> p_file_id
       and f2.status <> 'purged'
       and f2.purge_reserved_at is null
  ) into v_conflict;

  if v_conflict then
    raise exception 'release_purge_claim: cannot release file % — another non-purged File exists for the same checksum (reclaim raced during in-flight purge). Complete the Storage HTTP DELETE and call mark_file_purged instead.', p_file_id using errcode='23514';
  end if;

  update public.files set purge_reserved_at=null, purge_reserved_by=null where id = p_file_id;
end $$;
comment on function public.release_purge_claim(uuid) is
  'STORAGE 004: releases a claim reservation so the File is again available for orphan reclaim. Idempotent no-op on already-unreserved files. Fails closed if another non-purged File exists for the same (workspace, checksum) — the reserved row is stranded and the operator must complete the physical DELETE + mark_file_purged instead. service_role only.';
revoke all on function public.release_purge_claim(uuid) from public;
revoke all on function public.release_purge_claim(uuid) from anon;
revoke all on function public.release_purge_claim(uuid) from authenticated;
grant execute on function public.release_purge_claim(uuid) to service_role;