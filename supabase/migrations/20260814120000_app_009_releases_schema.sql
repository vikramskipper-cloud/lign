-- APP 009: Releases product-surface additive schema.
--
-- Frozen sources: Migration 008 (public.releases, public.release_items),
-- AUTH 008 (releases_status_via_rpc + finalize_release/withdraw_release).
--
-- Delivers per APP_009_BACKEND_PROPOSAL §3–§9:
--   * 7 nullable columns on public.releases
--       (release_type, evidence_snapshot, superseded_by_release_id,
--        root_release_id, published_by_profile_id, discarded_at, code)
--   * 1 NULL-permissive CHECK: releases_release_type_check
--   * 3 composite FKs (2 self-FKs on chain columns + 1 cross-table FK
--     to profiles)
--   * 7 additive indexes (I-1 … I-7)
--   * 3 defense-in-depth triggers (chain-immutability, evidence-immutability,
--     type-immutability-when-released) — ALL NON-SECURITY-DEFINER per F-6
--     matching the frozen enforce_release_status_via_rpc precedent.
--
-- All additions are additive-only per APP 009 §21 backwards-compat guarantees.
-- Frozen Migration 008 and AUTH 008 are preserved byte-identically.

------------------------------------------------------------------------------
-- 1. releases: additive nullable columns
------------------------------------------------------------------------------

alter table public.releases
  add column if not exists release_type              text        null,
  add column if not exists evidence_snapshot         jsonb       null,
  add column if not exists superseded_by_release_id  uuid        null,
  add column if not exists root_release_id           uuid        null,
  add column if not exists published_by_profile_id   uuid        null,
  add column if not exists discarded_at              timestamptz null,
  add column if not exists code                      text        null;

comment on column public.releases.release_type is
  'APP 009 §3.1: bounded enum dimension (internal|preview|client|regulatory|final|patch|hotfix). NULL-permissive for legacy rows. Frozen ''channel'' preserved for free-text label. Frozen once status=released via enforce_release_type_immutable_when_released trigger.';
comment on column public.releases.evidence_snapshot is
  'APP 009 §3.2 / §6 / G-7: frozen bundle of approval + review + requirement evidence captured atomically at publish time. Immutable once status in (released, withdrawn) via enforce_release_evidence_immutable trigger.';
comment on column public.releases.superseded_by_release_id is
  'APP 009 §3.3 / §8: forward chain pointer to the release superseding this one. Composite FK to releases(id, project_id, workspace_id) ON DELETE RESTRICT. Exactly-once initialization (NULL -> uuid) via enforce_release_chain_immutable trigger; F-1 asymmetric contract. Chain writer is Wave 4 reserved (create_release_superseding).';
comment on column public.releases.root_release_id is
  'APP 009 §3.4 / §8: chain head pointer for O(1) chain-head lookup. Fully immutable after INSERT via enforce_release_chain_immutable trigger (APP 006 T-CRIT-1). NULL for chain roots; set inline at INSERT for members.';
comment on column public.releases.published_by_profile_id is
  'APP 009 §3.5 / G-37: profile who invoked publish_release / finalize_release, distinct from created_by_profile_id (drafter). ON DELETE SET NULL; frontend falls back to created_by_profile_id.';
comment on column public.releases.discarded_at is
  'APP 009 §3.6 / G-4: soft-discard timestamp for empty drafts. Preserves audit trail (no DELETE policy). Dashboard defaults exclude rows where discarded_at IS NOT NULL.';
comment on column public.releases.code is
  'APP 009 §3.7 / §15.4 / G-21: per-project stable display code (R-NNN). Server-computed at draft creation via pg_advisory_xact_lock(''release_code:''||project_id). Unique per project via releases_project_code_unique_idx. Backs /deep/release/:code.';

------------------------------------------------------------------------------
-- 2. releases: NULL-permissive CHECK constraint (§4.1)
------------------------------------------------------------------------------

alter table public.releases
  add constraint releases_release_type_check
    check (release_type is null or release_type in (
      'internal','preview','client','regulatory','final','patch','hotfix'
    ));

------------------------------------------------------------------------------
-- 3. releases: composite FKs (§5.1–§5.3)
------------------------------------------------------------------------------
-- Chain FKs reuse frozen releases_id_project_workspace_key (Migration 008
-- L108) to enforce same-project chain integrity. ON DELETE RESTRICT keeps
-- chain roots undeletable while members reference them.

alter table public.releases
  add constraint releases_superseded_by_fk
    foreign key (superseded_by_release_id, project_id, workspace_id)
    references public.releases (id, project_id, workspace_id)
    on delete restrict;

alter table public.releases
  add constraint releases_root_release_fk
    foreign key (root_release_id, project_id, workspace_id)
    references public.releases (id, project_id, workspace_id)
    on delete restrict;

-- Publisher attribution FK mirrors frozen created_by_profile_id pattern
-- (Migration 008 L84) — ON DELETE SET NULL preserves the release row.
alter table public.releases
  add constraint releases_published_by_profile_fk
    foreign key (published_by_profile_id)
    references public.profiles (id)
    on delete set null;

------------------------------------------------------------------------------
-- 4. releases: additive indexes (I-1 … I-7)
------------------------------------------------------------------------------

-- I-1 Type-filtered released list (Critical).
create index if not exists releases_project_release_type_released_idx
  on public.releases (project_id, release_type, released_at desc);

-- I-2 "Published by me" view + published_by FK coverage (High).
create index if not exists releases_project_published_by_released_idx
  on public.releases (project_id, published_by_profile_id, released_at desc)
  where published_by_profile_id is not null;

-- I-3 Deep-link resolver + per-project code uniqueness (Critical).
create unique index if not exists releases_project_code_unique_idx
  on public.releases (project_id, code)
  where code is not null;

-- I-4 Chain-head lookup + root FK coverage (High).
create index if not exists releases_root_release_idx
  on public.releases (root_release_id)
  where root_release_id is not null;

-- I-5 Chain-uniqueness invariant per G-10 (at most one release supersedes
--     a given release) + superseded_by FK coverage (High).
create unique index if not exists releases_superseded_by_unique_idx
  on public.releases (superseded_by_release_id)
  where superseded_by_release_id is not null;

-- I-6 Discarded-drafts view (Medium).
create index if not exists releases_project_discarded_at_idx
  on public.releases (project_id, discarded_at)
  where discarded_at is not null;

-- I-7 Metrics: count releases by type x status (Medium).
create index if not exists releases_project_release_type_status_idx
  on public.releases (project_id, release_type, status);

------------------------------------------------------------------------------
-- 5. Trigger: enforce_release_chain_immutable — BEFORE UPDATE (§9.1, F-1)
------------------------------------------------------------------------------
-- Asymmetric write-once contract:
--   - root_release_id: FULLY IMMUTABLE. Any NEW IS DISTINCT FROM OLD raises.
--     (APP 006 T-CRIT-1: value MUST be set inline at INSERT via pre-computed
--     UUID; no post-INSERT UPDATE permitted, including NULL->self.)
--   - superseded_by_release_id: exactly-once initialization. NULL -> uuid
--     permitted (write on prior release from create_release_superseding
--     step 5). uuid -> uuid and uuid -> NULL rejected.
--
-- Row-local; inspects only OLD/NEW of its own row. NOT SECURITY DEFINER
-- per F-6 (matches frozen enforce_release_status_via_rpc at
-- 20260801220000_auth_008_release_rls.sql L38).

create or replace function public.enforce_release_chain_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- root_release_id: fully immutable after INSERT (APP 006 T-CRIT-1).
  if new.root_release_id is distinct from old.root_release_id then
    raise exception 'releases.root_release_id is immutable after INSERT (release_id=%). Chain-init discipline: set root_release_id inline at INSERT via pre-computed UUID.', old.id
      using errcode = '23514';
  end if;

  -- superseded_by_release_id: exactly-once NULL -> uuid initialization.
  if old.superseded_by_release_id is not null
     and new.superseded_by_release_id is distinct from old.superseded_by_release_id then
    if new.superseded_by_release_id is null then
      raise exception 'releases.superseded_by_release_id cannot be cleared once set (release_id=%)', old.id
        using errcode = '23514';
    else
      raise exception 'releases.superseded_by_release_id already set (release_id=%); write-once contract', old.id
        using errcode = '23514';
    end if;
  end if;

  return new;
end $$;

comment on function public.enforce_release_chain_immutable() is
  'APP 009 §9.1 / F-1: asymmetric write-once contract. root_release_id fully immutable after INSERT (APP 006 T-CRIT-1). superseded_by_release_id permits NULL -> uuid exactly once (initial supersession pointer write). NOT SECURITY DEFINER (row-local; matches frozen enforce_release_status_via_rpc non-DEFINER precedent).';

revoke all on function public.enforce_release_chain_immutable() from public;
revoke all on function public.enforce_release_chain_immutable() from anon;
revoke all on function public.enforce_release_chain_immutable() from authenticated;

drop trigger if exists releases_chain_immutable on public.releases;
create trigger releases_chain_immutable
  before update on public.releases
  for each row execute function public.enforce_release_chain_immutable();

------------------------------------------------------------------------------
-- 6. Trigger: enforce_release_evidence_immutable — BEFORE UPDATE (§9.2)
------------------------------------------------------------------------------
-- Once evidence_snapshot is written on a release row transitioning into
-- (released, withdrawn), it cannot be mutated. The publish write is permitted
-- because OLD.status='draft' at the pre-update inspection point.
--
-- Row-local; NOT SECURITY DEFINER per F-6.

create or replace function public.enforce_release_evidence_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.evidence_snapshot is distinct from old.evidence_snapshot
     and old.status in ('released','withdrawn') then
    raise exception 'releases.evidence_snapshot is immutable once release status is % (release_id=%)', old.status, old.id
      using errcode = '23514';
  end if;
  return new;
end $$;

comment on function public.enforce_release_evidence_immutable() is
  'APP 009 §9.2 / §6.3: rejects evidence_snapshot mutation when OLD.status IN (released, withdrawn). Publish path permitted (OLD.status=draft at pre-update). NOT SECURITY DEFINER (row-local).';

revoke all on function public.enforce_release_evidence_immutable() from public;
revoke all on function public.enforce_release_evidence_immutable() from anon;
revoke all on function public.enforce_release_evidence_immutable() from authenticated;

drop trigger if exists releases_evidence_immutable on public.releases;
create trigger releases_evidence_immutable
  before update on public.releases
  for each row execute function public.enforce_release_evidence_immutable();

------------------------------------------------------------------------------
-- 7. Trigger: enforce_release_type_immutable_when_released — BEFORE UPDATE (§9.3)
------------------------------------------------------------------------------
-- Once status='released' or 'withdrawn', release_type is frozen. Publish
-- (which sets release_type in the same atomic UPDATE that flips status to
-- 'released') is permitted because OLD.status='draft' at pre-update time.
--
-- Row-local; NOT SECURITY DEFINER per F-6.

create or replace function public.enforce_release_type_immutable_when_released()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.release_type is distinct from old.release_type
     and old.status in ('released','withdrawn') then
    raise exception 'releases.release_type is immutable once release status is % (release_id=%)', old.status, old.id
      using errcode = '23514';
  end if;
  return new;
end $$;

comment on function public.enforce_release_type_immutable_when_released() is
  'APP 009 §9.3 / §9.7: rejects release_type mutation when OLD.status IN (released, withdrawn). Publish path permitted (OLD.status=draft at pre-update). NOT SECURITY DEFINER (row-local).';

revoke all on function public.enforce_release_type_immutable_when_released() from public;
revoke all on function public.enforce_release_type_immutable_when_released() from anon;
revoke all on function public.enforce_release_type_immutable_when_released() from authenticated;

drop trigger if exists releases_type_immutable_when_released on public.releases;
create trigger releases_type_immutable_when_released
  before update on public.releases
  for each row execute function public.enforce_release_type_immutable_when_released();
