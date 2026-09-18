-- Migration 008: releases
--
-- Contents:
--   1. public.releases       — project-scoped bundle of released asset_versions.
--   2. public.release_items  — one asset_version per row within a release.
--   3. DB-boundary triggers:
--      - enforce_release_finalization_prerequisites (BEFORE INSERT OR UPDATE
--        OF status ON releases): rejects transition to 'released' unless
--        every release_items row's version has an approved approval_request.
--        Also requires at least one item (product-preference addition — see
--        §Deviations).
--      - enforce_release_items_parent_draft_mutation (BEFORE INSERT/UPDATE/
--        DELETE ON release_items): rejects mutation when parent release is
--        not in draft. Mirrors the version_files/asset_versions pattern.
--   4. Deferred Decision FK completed: decisions.resulting_release_id
--      → releases(id, workspace_id) using existing covering index from
--      Migration 006.
--   5. RLS enabled on both new tables with NO policies.
--
-- Architectural notes:
--   - A Release is not Current, Latest, Approved, or a publication event.
--     Independence preserved: this migration adds no side effect to
--     design_assets.current_version_id, asset_versions.status, or
--     approval_requests.status.
--   - MVP release lifecycle (STATE_MACHINES.md v1 §15): draft → released
--     → withdrawn. Schema retains reserved values 'scheduled' and
--     'superseded' but MVP does not exercise them. No auto-supersede.
--   - Release approval prerequisite is elevated to DB-boundary per
--     DATABASE_SCHEMA.md v0.3 §9. Enforced by trigger, evaluating
--     approval_requests.status = 'approved' (not by reducing responses).
--   - Empty-release protection is a documented product-preference
--     strengthening beyond the frozen spec: the finalization trigger
--     rejects transition to 'released' when the release has no items.
--     Frozen architecture is silent on this; product preference stated
--     in the Migration 008 instructions. Reported under Deviations.
--   - Release-item mutation is blocked when parent is not draft. The
--     frozen schema (§9) says "application-enforced" but the state
--     machine (§15) implies draft-only. The trigger implements the
--     state-machine strictness for defense-in-depth, consistent with
--     the version_files pattern from Migration 004.
--
-- Composite tenant/project integrity:
--   - releases.project_fk: (project_id, workspace_id) → projects.
--   - release_items.release_fk: (release_id, project_id, workspace_id)
--     → releases. Item's project_id must match release's project.
--   - release_items.version_project_fk: (version_id, project_id) →
--     asset_versions. Version's project must match release's project.
--   - release_items.version_asset_fk: (version_id, design_asset_id) →
--     asset_versions. Sanity: denormalized asset matches version's asset.
--   Together these make cross-project release bundles impossible.
--
-- Decision resulting_release integrity:
--   Composite FK (resulting_release_id, workspace_id) → releases. Requires
--   UNIQUE (id, workspace_id) on releases in addition to the spec-declared
--   (id, project_id, workspace_id). Both composite uniques added.
--
-- Explicit non-goals:
--   - No create_release / add_release_item / remove_release_item /
--     finalize_release / withdraw_release RPCs.
--   - No activity_events, notifications, or scheduling.
--   - No pg_cron / pg_net / Storage buckets.
--   - No RLS policies.
--
-- Historical retention:
--   All FKs use ON DELETE RESTRICT except created_by_profile_id (SET NULL).
--   Released bundles are historical; nothing may cascade-erase them.

------------------------------------------------------------------------------
-- 1. releases (DATABASE_SCHEMA.md v0.3 §3.23)
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

  -- Non-draft/scheduled statuses require released_at.
  constraint releases_released_metadata_check
    check (status not in ('released','superseded','withdrawn') or released_at is not null),

  -- Withdrawn requires withdrawn_at.
  constraint releases_withdrawn_metadata_check
    check (status <> 'withdrawn' or withdrawn_at is not null),

  -- Composite tenant/scope FK: release lives in its project's workspace.
  constraint releases_project_fk
    foreign key (project_id, workspace_id)
    references public.projects (id, workspace_id)
    on delete restrict,

  -- Composite unique targets:
  --   (id, project_id, workspace_id) — for release_items' 3-col composite FK.
  --   (id, workspace_id)             — for decisions.resulting_release_fk.
  constraint releases_id_project_workspace_key unique (id, project_id, workspace_id),
  constraint releases_id_workspace_key         unique (id, workspace_id)
);

comment on table public.releases is
  'Project-scoped bundle of released asset_versions. Release is independent of Current, Latest, Approved, and Published — no side effects on those. Cross-project releases are structurally impossible. DATABASE_SCHEMA.md v0.3 §3.23.';
comment on column public.releases.status is
  'MVP lifecycle: draft → released → withdrawn (per STATE_MACHINES.md v1 §15). Reserved values: scheduled, superseded (no automatic transitions in MVP).';
comment on constraint releases_id_workspace_key on public.releases is
  'Composite unique target for decisions.resulting_release_fk (workspace-scoped decisions cannot include project_id in their composite FK).';

-- FK covering indexes.
create index releases_project_workspace_idx
  on public.releases (project_id, workspace_id);

create index releases_created_by_profile_id_idx
  on public.releases (created_by_profile_id)
  where created_by_profile_id is not null;

-- Spec-required domain query indexes.
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
-- 2. release_items (DATABASE_SCHEMA.md v0.3 §3.24)
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

  -- Composite cross-scope FKs enforcing same-project bundling:
  --   1. release → same project/workspace as this item.
  constraint release_items_release_fk
    foreign key (release_id, project_id, workspace_id)
    references public.releases (id, project_id, workspace_id)
    on delete restrict,

  --   2. version must belong to an asset in this item's project. This makes
  --      cross-project version inclusion structurally impossible.
  constraint release_items_version_project_fk
    foreign key (version_id, project_id)
    references public.asset_versions (id, project_id)
    on delete restrict,

  --   3. denormalized asset must match the version's asset.
  constraint release_items_version_asset_fk
    foreign key (version_id, design_asset_id)
    references public.asset_versions (id, design_asset_id)
    on delete restrict,

  -- A version appears at most once per release. (Same version may be in
  -- different releases historically.)
  constraint release_items_release_version_key    unique (release_id, version_id),

  -- Deterministic ordering per release.
  constraint release_items_release_sort_order_key unique (release_id, sort_order)
);

comment on table public.release_items is
  'One asset_version included in a release. Multiple assets may appear in a single release. Composite FKs make cross-project bundling structurally impossible. Same version may appear in different historical releases; not multiple times in the same release. DATABASE_SCHEMA.md v0.3 §3.24.';

-- FK covering indexes.
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

-- Parent-draft mutation trigger. Consistent with the version_files pattern
-- from Migration 004: release_items may only be inserted/updated/deleted
-- while parent releases.status = 'draft'. SECURITY DEFINER so the parent
-- lookup bypasses RLS.
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
  'DB-boundary trigger: release_items rows may only be inserted/updated/deleted while the parent release is in draft status. SECURITY DEFINER so the internal parent-status lookup bypasses RLS on releases.';

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
-- DB-boundary invariant (DATABASE_SCHEMA.md v0.3 §9): A release may only
-- transition to 'released' if every included version has an approved
-- approval_request. Product-preference addition: the release must contain
-- at least one release_items row (reported under Deviations).
--
-- SECURITY DEFINER because it must read release_items and approval_requests
-- irrespective of the caller's RLS access.
--
-- Fires only when the transition target is 'released' — not on withdraw,
-- supersede, or any other status update.

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
  -- Only enforce on transition TO 'released'.
  if new.status <> 'released' then
    return new;
  end if;

  -- Idempotent already-released state: no re-check.
  if tg_op = 'UPDATE' and old.status = 'released' then
    return new;
  end if;

  -- 1. Empty-release protection (product-preference addition beyond
  --    frozen schema).
  select count(*) into v_item_count
    from public.release_items
    where release_id = new.id;

  if v_item_count = 0 then
    raise exception 'releases cannot transition to released without at least one release_item (release_id=%)', new.id
      using errcode = '23514';
  end if;

  -- 2. Approved-version prerequisite. Approval state is derived from
  --    approval_requests.status = 'approved' (per DATABASE_SCHEMA.md §9),
  --    NOT from ApprovalResponses.
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
  'DB-boundary trigger: rejects releases transition to ''released'' unless (a) the release has at least one release_item [product-preference addition], and (b) every item references a version with an approved approval_request. Approval state derives from approval_requests.status, not from approval_responses. SECURITY DEFINER for cross-table RLS bypass.';

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
-- 4. Complete deferred Decision FK: decisions.resulting_release_id
------------------------------------------------------------------------------
-- Covering index decisions_resulting_release_workspace_idx was preemptively
-- created in Migration 006 as
--   CREATE INDEX decisions_resulting_release_workspace_idx
--     ON public.decisions (resulting_release_id, workspace_id)
--     WHERE resulting_release_id IS NOT NULL;
-- which covers the composite FK exactly.

alter table public.decisions
  add constraint decisions_resulting_release_fk
    foreign key (resulting_release_id, workspace_id)
    references public.releases (id, workspace_id)
    on delete restrict;

comment on constraint decisions_resulting_release_fk on public.decisions is
  'Deferred from Migration 006 — added when the releases table came online. Decisions remain workspace-scoped (no project_id); the composite FK uses releases_id_workspace_key. Decision target XOR is unchanged: resulting_release_id is a cross-reference, not a primary target.';
