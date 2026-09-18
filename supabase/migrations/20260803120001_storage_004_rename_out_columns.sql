drop function if exists public.list_purgeable_files(integer);
drop function if exists public.claim_file_for_purge(uuid, text);

create or replace function public.list_purgeable_files(p_limit integer default 100)
returns table (out_file_id uuid, out_workspace_id uuid, out_storage_ref text)
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
comment on function public.list_purgeable_files(integer) is
  'STORAGE 004: enumerates orphaned Files whose 30-day retention has elapsed and that are not currently claim-reserved. OUT columns out_-prefixed to avoid PL/pgSQL column-name collision. service_role only.';
revoke all on function public.list_purgeable_files(integer) from public;
revoke all on function public.list_purgeable_files(integer) from anon;
revoke all on function public.list_purgeable_files(integer) from authenticated;
grant execute on function public.list_purgeable_files(integer) to service_role;

create or replace function public.claim_file_for_purge(p_file_id uuid, p_worker text default 'system')
returns table (out_file_id uuid, out_workspace_id uuid, out_bucket text, out_storage_ref text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_workspace_id uuid; v_status text; v_orphaned_at timestamptz;
  v_storage_ref text; v_reserved_at timestamptz;
  v_expected_ref text; v_refcount integer;
begin
  if p_file_id is null then raise exception 'claim_file_for_purge: file_id required' using errcode='22004'; end if;
  select f.workspace_id, f.status, f.orphaned_at, f.storage_ref, f.purge_reserved_at
    into v_workspace_id, v_status, v_orphaned_at, v_storage_ref, v_reserved_at
    from public.files f where f.id = p_file_id for update;
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
comment on function public.claim_file_for_purge(uuid, text) is
  'STORAGE 004: atomically reserves an eligible orphaned File for physical deletion. OUT columns out_-prefixed. service_role only.';
revoke all on function public.claim_file_for_purge(uuid, text) from public;
revoke all on function public.claim_file_for_purge(uuid, text) from anon;
revoke all on function public.claim_file_for_purge(uuid, text) from authenticated;
grant execute on function public.claim_file_for_purge(uuid, text) to service_role;