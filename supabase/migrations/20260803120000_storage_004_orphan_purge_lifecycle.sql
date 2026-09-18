-- STORAGE 004: orphan retention + physical purge lifecycle
--
-- Frozen sources: STORAGE 001/002/003.
--
-- Delivers the minimum DB surface that a controlled service-role purge worker
-- needs to safely finish the File lifecycle:
--
--     uploaded ──(24h + 0 vf refs, sweep)──▶ orphaned
--     active   ──(discard_draft_version, STORAGE 003)──▶ orphaned
--     orphaned ──(start_version_file_upload reclaim, STORAGE 003)──▶ uploaded
--     orphaned ──(30d + 0 vf refs, claim → Storage DELETE → mark_purged)──▶ purged
--
-- New RPCs (all SECURITY DEFINER, search_path='', GRANTed to service_role only):
--   * sweep_stale_uploads()                        — DB-only transition
--   * list_purgeable_files(p_limit int)            — enumerate eligibility
--   * claim_file_for_purge(p_file_id, p_worker)    — atomic claim reservation
--   * release_purge_claim(p_file_id)               — abort path
--   * mark_file_purged(p_file_id)                  — final transition + event
--
-- The physical Storage DELETE itself remains OUT of Postgres and is performed
-- by a documented service-role operator script (see STORAGE_ARCHITECTURE.md
-- §11 / STORAGE_004_OPERATOR.md) via the Supabase Storage HTTP API. No cron,
-- no Edge Function scheduling, no user-triggered purge path.
--
-- =========================================================================
-- RACE-SAFE RECLAMATION AMENDMENT (STORAGE 002 §7.1 + STORAGE 003 dispatch)
-- =========================================================================
-- Adds files.purge_reserved_at + purge_reserved_by columns and narrows the
-- partial unique index and the start_version_file_upload dispatch to exclude
-- rows currently reserved for physical deletion. This prevents a caller from
-- reclaiming an orphaned File whose Storage object is mid-delete, which would
-- otherwise leave an active File pointing at a deleted object.
--
-- Impact on frozen migrations:
--   * STORAGE 002 partial unique index: WHERE predicate widened.
--   * STORAGE 003 start_version_file_upload: one additional predicate in the
--     SELECT FOR UPDATE fall-through branch.
-- No other frozen surface is touched. Both are documented as the minimum
-- structural mechanism the frozen race requires (per user brief §8).

------------------------------------------------------------------------------
-- 1. Claim reservation columns
------------------------------------------------------------------------------

alter table public.files
  add column if not exists purge_reserved_at timestamptz,
  add column if not exists purge_reserved_by text;

comment on column public.files.purge_reserved_at is
  'STORAGE 004: set by claim_file_for_purge to atomically reserve an orphaned File for in-flight physical deletion. While non-null the row is excluded from the checksum partial unique index and from start_version_file_upload''s orphan-reclaim dispatch, preventing an orphaned → uploaded reclaim from racing the Storage HTTP DELETE. Cleared by release_purge_claim on worker abort; preserved through mark_file_purged for audit.';

comment on column public.files.purge_reserved_by is
  'STORAGE 004: opaque identifier of the purge worker/operator that holds the current reservation. Free-form text so that shell scripts, Edge Functions, or human operators can leave a legible trace.';

------------------------------------------------------------------------------
-- 2. Rebuild partial unique index
------------------------------------------------------------------------------

drop index if exists public.files_workspace_checksum_key;
create unique index files_workspace_checksum_key
  on public.files (workspace_id, checksum_sha256)
  where status <> 'purged' and purge_reserved_at is null;

comment on index public.files_workspace_checksum_key is
  'STORAGE 004 amendment of STORAGE 002 §7.1: partial unique index excludes both purged rows AND rows reserved for physical deletion so that a same-checksum re-upload can proceed with a fresh File identity while an orphaned predecessor is being purged.';

------------------------------------------------------------------------------
-- 3. start_version_file_upload — exclude reserved rows from reclaim
------------------------------------------------------------------------------
-- Only the SELECT FOR UPDATE WHERE clause is amended. All other behavior is
-- preserved verbatim from STORAGE 003 (out_-prefixed OUT columns).

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
    'application/x-msdownload','application/x-msdos-program',
    'application/x-executable','application/x-sh',
    'application/x-shellscript','text/x-shellscript'
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
    -- STORAGE 004: also exclude rows reserved for physical deletion; otherwise
    -- an orphaned-reclaim could race the Storage HTTP DELETE and produce an
    -- active File whose object no longer exists.
    select id, status, uploaded_by_profile_id, storage_ref
      into v_existing_id, v_existing_status, v_existing_uploader, v_existing_ref
      from public.files
     where workspace_id = v_workspace_id
       and checksum_sha256 = v_checksum
       and status <> 'purged'
       and purge_reserved_at is null
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
  'STORAGE 003 (STORAGE 004 amended): creates a File reservation or dispatches dedup. Rows currently reserved for physical purge (purge_reserved_at IS NOT NULL) are excluded from the orphan-reclaim path so an orphaned → uploaded reclaim cannot race an in-flight Storage HTTP DELETE.';

revoke all on function public.start_version_file_upload(uuid, text, text, bigint) from public;
revoke all on function public.start_version_file_upload(uuid, text, text, bigint) from anon;
grant execute on function public.start_version_file_upload(uuid, text, text, bigint) to authenticated, service_role;

------------------------------------------------------------------------------
-- 4. sweep_stale_uploads — uploaded (>24h, 0 vf refs) → orphaned
------------------------------------------------------------------------------
-- Idempotent, service_role only. Does not touch active / already-orphaned /
-- purged / reserved rows. Does not touch uploads younger than 24h. Emits no
-- event (file.orphaned is explicitly deferred in EVENT_MODEL §4.14).

create or replace function public.sweep_stale_uploads()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  with candidates as (
    select f.id
      from public.files f
     where f.status = 'uploaded'
       and f.created_at < now() - interval '24 hours'
       and f.purge_reserved_at is null
       and not exists (select 1 from public.version_files vf where vf.file_id = f.id)
     for update skip locked
  ),
  updated as (
    update public.files f
       set status = 'orphaned',
           orphaned_at = now()
      from candidates c
     where f.id = c.id
    returning f.id
  )
  select count(*)::int into v_count from updated;
  return v_count;
end $$;

comment on function public.sweep_stale_uploads() is
  'STORAGE 004: transitions abandoned reservations (uploaded, >24h old, 0 version_files refs, not purge-reserved) to orphaned. Idempotent. service_role only. Emits no event — file.orphaned is deferred per EVENT_MODEL §4.14.';

revoke all on function public.sweep_stale_uploads() from public;
revoke all on function public.sweep_stale_uploads() from anon;
revoke all on function public.sweep_stale_uploads() from authenticated;
grant execute on function public.sweep_stale_uploads() to service_role;

------------------------------------------------------------------------------
-- 5. list_purgeable_files — enumerate eligibility
------------------------------------------------------------------------------
-- Returns only the fields the worker needs (file_id, workspace_id, storage_ref).
-- service_role only. Does not include reserved rows (those are already claimed).

create or replace function public.list_purgeable_files(
  p_limit integer default 100
)
returns table (
  out_file_id      uuid,
  out_workspace_id uuid,
  out_storage_ref  text
)
language sql
stable
security definer
set search_path = ''
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
  'STORAGE 004: enumerates orphaned Files whose 30-day retention has elapsed and that are not currently claim-reserved. Returns only file_id, workspace_id, and canonical storage_ref. service_role only.';

revoke all on function public.list_purgeable_files(integer) from public;
revoke all on function public.list_purgeable_files(integer) from anon;
revoke all on function public.list_purgeable_files(integer) from authenticated;
grant execute on function public.list_purgeable_files(integer) to service_role;

------------------------------------------------------------------------------
-- 6. claim_file_for_purge — atomic reservation
------------------------------------------------------------------------------
-- Verifies eligibility under SELECT FOR UPDATE and sets purge_reserved_at
-- atomically. Returns the exact canonical storage_ref the worker must delete;
-- the worker MUST NOT construct paths from caller input.

create or replace function public.claim_file_for_purge(
  p_file_id uuid,
  p_worker  text default 'system'
)
returns table (
  out_file_id      uuid,
  out_workspace_id uuid,
  out_bucket       text,
  out_storage_ref  text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_workspace_id  uuid;
  v_status        text;
  v_orphaned_at   timestamptz;
  v_storage_ref   text;
  v_reserved_at   timestamptz;
  v_expected_ref  text;
  v_refcount      integer;
begin
  if p_file_id is null then
    raise exception 'claim_file_for_purge: file_id required' using errcode='22004';
  end if;

  select f.workspace_id, f.status, f.orphaned_at, f.storage_ref, f.purge_reserved_at
    into v_workspace_id, v_status, v_orphaned_at, v_storage_ref, v_reserved_at
    from public.files f where f.id = p_file_id for update;
  if v_workspace_id is null then
    raise exception 'claim_file_for_purge: file % not found', p_file_id using errcode='23503';
  end if;
  if v_status <> 'orphaned' then
    raise exception 'claim_file_for_purge: file % is % (must be orphaned)', p_file_id, v_status using errcode='23514';
  end if;
  if v_orphaned_at is null or v_orphaned_at > now() - interval '30 days' then
    raise exception 'claim_file_for_purge: file % has not reached 30-day retention (orphaned_at=%)', p_file_id, v_orphaned_at using errcode='23514';
  end if;
  if v_reserved_at is not null then
    raise exception 'claim_file_for_purge: file % is already reserved (since %)', p_file_id, v_reserved_at using errcode='23514';
  end if;

  v_expected_ref := v_workspace_id::text || '/' || p_file_id::text;
  if v_storage_ref is distinct from v_expected_ref then
    raise exception 'claim_file_for_purge: file % has non-canonical storage_ref %', p_file_id, v_storage_ref using errcode='23514';
  end if;

  select count(*) into v_refcount from public.version_files where file_id = p_file_id;
  if v_refcount > 0 then
    raise exception 'claim_file_for_purge: file % has % version_files reference(s)', p_file_id, v_refcount using errcode='23514';
  end if;

  update public.files
     set purge_reserved_at = now(),
         purge_reserved_by = coalesce(nullif(trim(p_worker), ''), 'system')
   where id = p_file_id;

  return query
    select p_file_id, v_workspace_id, 'lign-files'::text, v_storage_ref;
end $$;

comment on function public.claim_file_for_purge(uuid, text) is
  'STORAGE 004: atomically reserves an eligible orphaned File for physical deletion. Fails closed for wrong status, unmet retention, existing reservation, non-canonical storage_ref, or any live version_files reference. Returns the exact canonical (bucket, storage_ref) that the worker must delete — the worker must NEVER build paths from caller input. service_role only.';

revoke all on function public.claim_file_for_purge(uuid, text) from public;
revoke all on function public.claim_file_for_purge(uuid, text) from anon;
revoke all on function public.claim_file_for_purge(uuid, text) from authenticated;
grant execute on function public.claim_file_for_purge(uuid, text) to service_role;

------------------------------------------------------------------------------
-- 7. release_purge_claim — release reservation on worker abort
------------------------------------------------------------------------------
-- Intended ONLY when the Storage HTTP DELETE failed (5xx / network) and the
-- object was NOT deleted. If DELETE succeeded (200 or 404), the worker MUST
-- follow through to mark_file_purged; releasing after successful deletion
-- would allow re-upload dedup to a File whose object no longer exists.

create or replace function public.release_purge_claim(
  p_file_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_workspace_id uuid;
  v_status       text;
  v_reserved_at  timestamptz;
  v_checksum     bytea;
  v_conflict     boolean;
begin
  if p_file_id is null then
    raise exception 'release_purge_claim: file_id required' using errcode='22004';
  end if;

  select workspace_id, status, purge_reserved_at, checksum_sha256
    into v_workspace_id, v_status, v_reserved_at, v_checksum
    from public.files where id = p_file_id for update;
  if v_status is null then
    raise exception 'release_purge_claim: file % not found', p_file_id using errcode='23503';
  end if;
  if v_status = 'purged' then
    raise exception 'release_purge_claim: file % is already purged (cannot release)', p_file_id using errcode='23514';
  end if;
  if v_reserved_at is null then
    -- Nothing to release; idempotent no-op.
    return;
  end if;

  -- STORAGE 004 race guard: if a fresh row for the same (workspace, checksum)
  -- was created via start_version_file_upload's partial-index-bypass while
  -- this row was reserved, clearing the reservation would violate
  -- files_workspace_checksum_key. In that case the reserved row is stranded
  -- and the operator must complete the physical DELETE and call
  -- mark_file_purged (purged rows are excluded from the index).
  select exists (
    select 1 from public.files f2
     where f2.workspace_id     = v_workspace_id
       and f2.checksum_sha256  = v_checksum
       and f2.id <> p_file_id
       and f2.status <> 'purged'
       and f2.purge_reserved_at is null
  ) into v_conflict;

  if v_conflict then
    raise exception 'release_purge_claim: cannot release file % — another non-purged File exists for the same checksum (reclaim raced during in-flight purge). Complete the Storage HTTP DELETE and call mark_file_purged instead.', p_file_id using errcode='23514';
  end if;

  update public.files
     set purge_reserved_at = null,
         purge_reserved_by = null
   where id = p_file_id;
end $$;

comment on function public.release_purge_claim(uuid) is
  'STORAGE 004: releases a claim reservation so the File is again available for orphan reclaim. Idempotent no-op for already-unreserved files. Fails closed if another non-purged File exists for the same (workspace, checksum) — the reserved row is stranded and the operator must complete the physical DELETE + mark_file_purged instead. service_role only.';

revoke all on function public.release_purge_claim(uuid) from public;
revoke all on function public.release_purge_claim(uuid) from anon;
revoke all on function public.release_purge_claim(uuid) from authenticated;
grant execute on function public.release_purge_claim(uuid) to service_role;

------------------------------------------------------------------------------
-- 8. mark_file_purged — final transition + canonical file.purged event
------------------------------------------------------------------------------
-- Called after the Storage HTTP DELETE succeeded (or returned 404 — treated
-- as an already-satisfied deletion, §7 of the STORAGE 004 brief).
--
-- Re-verifies every purge invariant before flipping status. Idempotent for
-- already-purged Files.

create or replace function public.mark_file_purged(
  p_file_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_workspace_id  uuid;
  v_status        text;
  v_orphaned_at   timestamptz;
  v_storage_ref   text;
  v_reserved_at   timestamptz;
  v_checksum      bytea;
  v_expected_ref  text;
  v_refcount      integer;
begin
  if p_file_id is null then
    raise exception 'mark_file_purged: file_id required' using errcode='22004';
  end if;

  select workspace_id, status, orphaned_at, storage_ref, purge_reserved_at, checksum_sha256
    into v_workspace_id, v_status, v_orphaned_at, v_storage_ref, v_reserved_at, v_checksum
    from public.files where id = p_file_id for update;
  if v_workspace_id is null then
    raise exception 'mark_file_purged: file % not found', p_file_id using errcode='23503';
  end if;

  -- Idempotent success for already-purged
  if v_status = 'purged' then
    return false;
  end if;

  if v_status <> 'orphaned' then
    raise exception 'mark_file_purged: file % is % (must be orphaned)', p_file_id, v_status using errcode='23514';
  end if;
  if v_orphaned_at is null or v_orphaned_at > now() - interval '30 days' then
    raise exception 'mark_file_purged: file % has not reached 30-day retention', p_file_id using errcode='23514';
  end if;
  if v_reserved_at is null then
    raise exception 'mark_file_purged: file % is not claim-reserved (call claim_file_for_purge first)', p_file_id using errcode='23514';
  end if;
  v_expected_ref := v_workspace_id::text || '/' || p_file_id::text;
  if v_storage_ref is distinct from v_expected_ref then
    raise exception 'mark_file_purged: file % has non-canonical storage_ref %', p_file_id, v_storage_ref using errcode='23514';
  end if;
  select count(*) into v_refcount from public.version_files where file_id = p_file_id;
  if v_refcount > 0 then
    raise exception 'mark_file_purged: file % has % version_files reference(s)', p_file_id, v_refcount using errcode='23514';
  end if;

  update public.files
     set status = 'purged',
         purged_at = now()
   where id = p_file_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_workspace_id, null, now(), 'file.purged',
    null, 'system',
    'file', p_file_id, null,
    jsonb_build_object('file_id', p_file_id, 'checksum_sha256', encode(v_checksum,'hex'), 'storage_ref', v_storage_ref),
    '{}'::jsonb
  );

  return true;
end $$;

comment on function public.mark_file_purged(uuid) is
  'STORAGE 004: transitions a physically-deleted File to purged and emits the canonical file.purged event (system actor, per EVENT_MODEL §4.6). Re-verifies every purge invariant (status=orphaned, 30-day retention, claim-reserved, canonical storage_ref, zero version_files refs) before mutating state. Idempotent (returns false) for already-purged Files. Preserves purge_reserved_at/by for audit. service_role only.';

revoke all on function public.mark_file_purged(uuid) from public;
revoke all on function public.mark_file_purged(uuid) from anon;
revoke all on function public.mark_file_purged(uuid) from authenticated;
grant execute on function public.mark_file_purged(uuid) to service_role;
