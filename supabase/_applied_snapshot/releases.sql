-- Migration 008: releases
-- See supabase/migrations/20260729230000_releases.sql for full documentation.

------------------------------------------------------------------------------
-- 1. releases
------------------------------------------------------------------------------

create table public.releases (
  id                       uuid                    primary key default gen_random_uuid(),
  workspace_id             uuid                    not null,
  project_id               uuid                    not null,
  name                     text                    not null,
  notes                    text                    null,
  channel                  text                    null,
  status                   text                    not null default 'draft',
  effective_at             timestamptz             null,
  released_at              timestamptz             null,
  withdrawn_at             timestamptz             null,
  withdrawn_reason         text                    null,
  created_by_profile_id    uuid                    null references public.profiles (id) on delete set null,
  created_at               timestamptz             not null default now(),
  updated_at               timestamptz             not null default now(),

  constraint releases_status_check
    check (status in ('draft','scheduled','released','superseded','withdrawn')),

  constraint releases_released_metadata_check
    check (status not in ('released','superseded','withdrawn') or released_at is not null),

  constraint releases_withdrawn_metadata_check
    check (status <> 'withdrawn' or withdrawn_at is not null),

  constraint releases_project_fk
    foreign key (project_id, workspace_id)
    references public.projects (id, workspace_id)
    on delete restrict,

  constraint releases_id_project_workspace_key unique (id, project_id, workspace_id),
  constraint releases_id_workspace_key         unique (id, workspace_id)
);

comment on table public.releases is
  'Project-scoped bundle of released asset_versions. Independent of Current, Latest, Approved, and Published. DATABASE_SCHEMA.md v0.3 §3.23.';

create index releases_project_workspace_idx
  on public.releases (project_id, workspace_id);

create index releases_created_by_profile_id_idx
  on public.releases (created_by_profile_id)
  where created_by_profile_id is not null;

create index releases_project_status_released_idx
  on public.releases (project_id, status, released_at desc);

create index releases_workspace_status_idx
  on public.releases (workspace_id, status);

drop trigger if exists releases_set_updated_at on public.releases;
create trigger releases_set_updated_at
  before update on public.releases
  for each row execute function public.set_updated_at();

alter table public.releases enable row level security;

------------------------------------------------------------------------------
-- 2. release_items
------------------------------------------------------------------------------

create table public.release_items (
  id                     uuid                    primary key default gen_random_uuid(),
  workspace_id           uuid                    not null,
  project_id             uuid                    not null,
  release_id             uuid                    not null,
  version_id             uuid                    not null,
  design_asset_id        uuid                    not null,
  notes                  text                    null,
  sort_order             integer                 not null default 0,
  created_at             timestamptz             not null default now(),
  updated_at             timestamptz             not null default now(),

  constraint release_items_sort_order_check check (sort_order >= 0),

  constraint release_items_release_fk
    foreign key (release_id, project_id, workspace_id)
    references public.releases (id, project_id, workspace_id)
    on delete restrict,

  constraint release_items_version_project_fk
    foreign key (version_id, project_id)
    references public.asset_versions (id, project_id)
    on delete restrict,

  constraint release_items_version_asset_fk
    foreign key (version_id, design_asset_id)
    references public.asset_versions (id, design_asset_id)
    on delete restrict,

  constraint release_items_release_version_key    unique (release_id, version_id),
  constraint release_items_release_sort_order_key unique (release_id, sort_order)
);

comment on table public.release_items is
  'One asset_version included in a release. Multiple assets per release. Cross-project bundling structurally impossible. DATABASE_SCHEMA.md v0.3 §3.24.';

create index release_items_release_project_workspace_idx
  on public.release_items (release_id, project_id, workspace_id);

create index release_items_version_project_idx
  on public.release_items (version_id, project_id);

create index release_items_version_asset_idx
  on public.release_items (version_id, design_asset_id);

drop trigger if exists release_items_set_updated_at on public.release_items;
create trigger release_items_set_updated_at
  before update on public.release_items
  for each row execute function public.set_updated_at();

alter table public.release_items enable row level security;

create or replace function public.enforce_release_items_parent_draft_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent_id     uuid;
  v_parent_status text;
begin
  if tg_op = 'DELETE' then
    v_parent_id := old.release_id;
  else
    v_parent_id := new.release_id;
  end if;

  select status into v_parent_status
    from public.releases where id = v_parent_id;

  if v_parent_status is null then
    raise exception 'enforce_release_items_parent_draft_mutation: parent release % not found', v_parent_id
      using errcode = '23503';
  end if;

  if v_parent_status is distinct from 'draft' then
    raise exception 'release_items may only be mutated while parent releases.status = ''draft'' (parent status=%)', v_parent_status
      using errcode = '23514';
  end if;

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;

comment on function public.enforce_release_items_parent_draft_mutation() is
  'DB-boundary trigger: release_items rows may only be inserted/updated/deleted while parent release is in draft. SECURITY DEFINER for RLS bypass.';

revoke all on function public.enforce_release_items_parent_draft_mutation() from public;
revoke all on function public.enforce_release_items_parent_draft_mutation() from anon;
revoke all on function public.enforce_release_items_parent_draft_mutation() from authenticated;

drop trigger if exists release_items_parent_draft_mutation on public.release_items;
create trigger release_items_parent_draft_mutation
  before insert or update or delete on public.release_items
  for each row execute function public.enforce_release_items_parent_draft_mutation();

------------------------------------------------------------------------------
-- 3. Release finalization prerequisites trigger
------------------------------------------------------------------------------

create or replace function public.enforce_release_finalization_prerequisites()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item_count       integer;
  v_unapproved_count integer;
begin
  if new.status <> 'released' then
    return new;
  end if;

  if tg_op = 'UPDATE' and old.status = 'released' then
    return new;
  end if;

  select count(*) into v_item_count
    from public.release_items
    where release_id = new.id;

  if v_item_count = 0 then
    raise exception 'releases cannot transition to released without at least one release_item (release_id=%)', new.id
      using errcode = '23514';
  end if;

  select count(*) into v_unapproved_count
    from public.release_items ri
    where ri.release_id = new.id
      and not exists (
        select 1
          from public.approval_requests ar
          where ar.design_asset_id = ri.design_asset_id
            and ar.version_id      = ri.version_id
            and ar.status          = 'approved'
      );

  if v_unapproved_count > 0 then
    raise exception 'releases cannot transition to released: % item(s) reference version(s) without an approved approval_request (release_id=%)',
      v_unapproved_count, new.id
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function public.enforce_release_finalization_prerequisites() is
  'DB-boundary trigger: rejects releases transition to released unless the release has at least one release_item AND every item references a version with approval_requests.status = approved. Approval state from approval_requests, not responses. SECURITY DEFINER for cross-table RLS bypass.';

revoke all on function public.enforce_release_finalization_prerequisites() from public;
revoke all on function public.enforce_release_finalization_prerequisites() from anon;
revoke all on function public.enforce_release_finalization_prerequisites() from authenticated;

drop trigger if exists releases_finalization_prerequisites_insert on public.releases;
create trigger releases_finalization_prerequisites_insert
  before insert on public.releases
  for each row execute function public.enforce_release_finalization_prerequisites();

drop trigger if exists releases_finalization_prerequisites_update on public.releases;
create trigger releases_finalization_prerequisites_update
  before update of status on public.releases
  for each row execute function public.enforce_release_finalization_prerequisites();

------------------------------------------------------------------------------
-- 4. Complete deferred Decision FK
------------------------------------------------------------------------------

alter table public.decisions
  add constraint decisions_resulting_release_fk
    foreign key (resulting_release_id, workspace_id)
    references public.releases (id, workspace_id)
    on delete restrict;

comment on constraint decisions_resulting_release_fk on public.decisions is
  'Deferred from Migration 006 — added when releases came online. Decisions workspace-scoped; composite FK uses releases_id_workspace_key. Decision target XOR unchanged.';