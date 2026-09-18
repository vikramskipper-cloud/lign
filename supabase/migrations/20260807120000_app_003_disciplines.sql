-- Migration 010 (APP 003): disciplines
--
-- Adds the lightweight Discipline concept per the frozen APP 003 architecture
-- update:
--   1. public.disciplines — project-scoped, industry-neutral classification of
--      "what kind of design" an asset is (Architecture / Interiors / MEP /
--      UI/UX / Branding / …). Project-defined, not hardcoded.
--   2. public.design_assets.discipline_id — nullable FK to disciplines,
--      composite-tenanted to the same (project_id, workspace_id) as the
--      asset. Nullable per approved decision D11 (v0 does not force NOT NULL;
--      UI enforces "please pick one" in Create Asset). ON DELETE RESTRICT so
--      "MEP" being deleted while assets belong to it can't happen silently —
--      archive is the escape hatch.
--   3. RLS on disciplines: SELECT gated by 'project.view',
--      INSERT/UPDATE gated by 'project.edit'. **No new capability keys** —
--      the lightweight tier deliberately reuses project.* rather than adding
--      discipline.* to the frozen capability catalog.
--
-- Explicit non-goals (per approved APP 003 §11):
--   - No hierarchy, no color/icon, no per-discipline ACL, no workflow.
--   - No DELETE policy; archive via status='archived'.
--   - No auto-migration of existing rows (nullable column; no backfill).
--   - No cross-project discipline library / templates.
--   - No favorites, star, or asset_stars table.
--
-- Historical-retention posture:
--   - disciplines.created_by_profile_id → profiles(id) ON DELETE SET NULL.
--   - design_assets.discipline_id → disciplines(id) ON DELETE RESTRICT
--     (composite FK enforces same project + workspace).
--
-- Transaction control: none inline. Supabase migration runner wraps.

------------------------------------------------------------------------------
-- 1. disciplines
------------------------------------------------------------------------------

create table public.disciplines (
  id                     uuid                    primary key default gen_random_uuid(),
  workspace_id           uuid                    not null,
  project_id             uuid                    not null,
  name                   text                    not null,
  description            text                    null,
  sort_order             integer                 not null default 0,
  status                 text                    not null default 'active',
  created_by_profile_id  uuid                    null references public.profiles (id) on delete set null,
  archived_at            timestamptz             null,
  created_at             timestamptz             not null default now(),
  updated_at             timestamptz             not null default now(),

  constraint disciplines_status_check check (status in ('active','archived')),

  -- Composite tenant/scope FK: a discipline cannot reference a project in a
  -- different workspace. Structurally enforced.
  constraint disciplines_project_fk
    foreign key (project_id, workspace_id)
    references public.projects (id, workspace_id)
    on delete restrict,

  -- Composite FK target for design_assets:
  --   (discipline_id, project_id, workspace_id)
  --   → disciplines(id, project_id, workspace_id) ON DELETE RESTRICT
  constraint disciplines_id_project_workspace_key
    unique (id, project_id, workspace_id)
);

comment on table public.disciplines is
  'Lightweight, project-defined classification of "what kind of design" an asset is (Architecture, Interiors, MEP, UI/UX, Branding, …). Separate from collections. No hierarchy. No dedicated capability keys — CRUD gated by project.edit. APP 003 §1.5.';
comment on constraint disciplines_project_fk on public.disciplines is
  'Composite tenant/scope FK: a discipline cannot reference a project in a different workspace.';

-- Active-name uniqueness within a project (case-insensitive via LOWER
-- expression index). Mirrors the collections pattern.
create unique index disciplines_project_name_active_key
  on public.disciplines (project_id, lower(name))
  where status = 'active';

create index disciplines_project_sort_idx
  on public.disciplines (project_id, sort_order);

drop trigger if exists disciplines_set_updated_at on public.disciplines;
create trigger disciplines_set_updated_at
  before update on public.disciplines
  for each row execute function public.set_updated_at();

alter table public.disciplines enable row level security;

------------------------------------------------------------------------------
-- 2. design_assets.discipline_id
------------------------------------------------------------------------------
-- Nullable per D11. Composite FK enforces same-project scope.

alter table public.design_assets
  add column if not exists discipline_id uuid null;

alter table public.design_assets
  drop constraint if exists design_assets_discipline_fk;
alter table public.design_assets
  add constraint design_assets_discipline_fk
    foreign key (discipline_id, project_id, workspace_id)
    references public.disciplines (id, project_id, workspace_id)
    on delete restrict;

comment on column public.design_assets.discipline_id is
  'Optional (v0 nullable per D11) FK to a discipline in the same project. Composite FK enforces same (project_id, workspace_id). ON DELETE RESTRICT: archive the discipline instead.';

create index if not exists design_assets_discipline_idx
  on public.design_assets (discipline_id)
  where discipline_id is not null;

------------------------------------------------------------------------------
-- 3. disciplines RLS policies
------------------------------------------------------------------------------
-- Deliberately reuses project.view / project.edit rather than introducing
-- discipline.* capability keys.

drop policy if exists disciplines_select on public.disciplines;
create policy disciplines_select on public.disciplines
  as permissive
  for select
  to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'project.view'));

drop policy if exists disciplines_insert on public.disciplines;
create policy disciplines_insert on public.disciplines
  as permissive
  for insert
  to authenticated
  with check (
    public.lign_has_capability(project_id, workspace_id, 'project.edit')
    and created_by_profile_id = (select auth.uid())
  );

drop policy if exists disciplines_update on public.disciplines;
create policy disciplines_update on public.disciplines
  as permissive
  for update
  to authenticated
  using      (public.lign_has_capability(project_id, workspace_id, 'project.edit'))
  with check (public.lign_has_capability(project_id, workspace_id, 'project.edit'));

-- No DELETE policy. Archive via status='archived'.
