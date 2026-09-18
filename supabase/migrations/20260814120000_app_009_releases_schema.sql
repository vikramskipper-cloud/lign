-- APP 009: Releases product-surface additive schema.

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

alter table public.releases
  add constraint releases_release_type_check
    check (release_type is null or release_type in (
      'internal','preview','client','regulatory','final','patch','hotfix'
    ));

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

alter table public.releases
  add constraint releases_published_by_profile_fk
    foreign key (published_by_profile_id)
    references public.profiles (id)
    on delete set null;

create index if not exists releases_project_release_type_released_idx
  on public.releases (project_id, release_type, released_at desc);

create index if not exists releases_project_published_by_released_idx
  on public.releases (project_id, published_by_profile_id, released_at desc)
  where published_by_profile_id is not null;

create unique index if not exists releases_project_code_unique_idx
  on public.releases (project_id, code)
  where code is not null;

create index if not exists releases_root_release_idx
  on public.releases (root_release_id)
  where root_release_id is not null;

create unique index if not exists releases_superseded_by_unique_idx
  on public.releases (superseded_by_release_id)
  where superseded_by_release_id is not null;

create index if not exists releases_project_discarded_at_idx
  on public.releases (project_id, discarded_at)
  where discarded_at is not null;

create index if not exists releases_project_release_type_status_idx
  on public.releases (project_id, release_type, status);

create or replace function public.enforce_release_chain_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.root_release_id is distinct from old.root_release_id then
    raise exception 'releases.root_release_id is immutable after INSERT (release_id=%). Chain-init discipline: set root_release_id inline at INSERT via pre-computed UUID.', old.id
      using errcode = '23514';
  end if;

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
