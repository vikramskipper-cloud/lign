-- REQUIREMENTS 002: schema + state invariants + RLS (no capability wiring)
--
-- Frozen sources: AUTH 001-009, STORAGE 001-004, REALTIME 001-002.
--
-- Delivers the entire database layer for Requirements per REQUIREMENTS 001:
--   * public.requirements                     — the requirement records
--   * public.requirement_design_assets        — many-to-many applicability
--   * public.version_requirement_assessments  — per-version satisfaction
--   * additive nullable columns:
--       public.changes.requirement_id
--       public.decisions.requirement_id
--
-- Authorization is expressed by referencing five NEW capability keys that
-- REQUIREMENTS 003 will add to lign_has_capability:
--     requirement.view / .create / .edit / .archive / .assess
-- Until 003 lands, these keys resolve to false and the policies are
-- correctly fail-closed for authenticated callers. Postgres/service_role
-- bypass RLS as usual. This preserves the frozen authorization contract:
-- REQUIREMENTS 002 does not touch lign_has_capability, does not introduce
-- new roles, and does not weaken any existing policy.
--
-- No RPCs, no events, no realtime, no storage, no frontend.

------------------------------------------------------------------------------
-- 1. public.requirements
------------------------------------------------------------------------------

create table public.requirements (
  id                            uuid primary key default gen_random_uuid(),
  workspace_id                  uuid not null,
  project_id                    uuid not null,
  parent_requirement_id         uuid null,
  code                          text not null,
  title                         text not null,
  description                   text null,
  category                      text null,
  source                        text null,
  source_ref                    text null,
  status                        text not null default 'draft',
  superseded_by_requirement_id  uuid null,
  archived_at                   timestamptz null,
  created_by_profile_id         uuid null,
  created_at                    timestamptz not null default now(),
  updated_at                    timestamptz not null default now(),

  -- Tenant composite FK: requirement's (project_id, workspace_id) must be a real project.
  constraint requirements_project_fk
    foreign key (project_id, workspace_id)
    references public.projects (id, workspace_id) on delete restrict,

  -- Downstream anchors so children/joins/assessments can enforce tenant + project coherence.
  constraint requirements_id_workspace_key unique (id, workspace_id),
  constraint requirements_id_project_key   unique (id, project_id),

  -- Parent is in the SAME PROJECT as this row.
  constraint requirements_parent_fk
    foreign key (parent_requirement_id, project_id)
    references public.requirements (id, project_id) on delete restrict,

  -- Supersession target is in the SAME PROJECT.
  constraint requirements_superseded_by_fk
    foreign key (superseded_by_requirement_id, project_id)
    references public.requirements (id, project_id) on delete restrict,

  constraint requirements_created_by_fk
    foreign key (created_by_profile_id)
    references public.profiles (id) on delete set null,

  constraint requirements_status_check
    check (status = any (array['draft','active','superseded','archived'])),

  constraint requirements_code_check
    check (length(code) between 1 and 32),

  constraint requirements_title_check
    check (length(title) between 1 and 500),

  -- Cannot supersede self.
  constraint requirements_no_self_supersede
    check (superseded_by_requirement_id is null or superseded_by_requirement_id <> id),

  -- Superseded status <=> pointer present. Prevents dangling metadata.
  constraint requirements_superseded_coherence
    check ((status =  'superseded' and superseded_by_requirement_id is not null)
        or (status <> 'superseded' and superseded_by_requirement_id is null)),

  -- Archived status <=> archived_at set.
  constraint requirements_archived_coherence
    check ((status =  'archived' and archived_at is not null)
        or (status <> 'archived' and archived_at is null))
);

-- Stable human ID uniqueness per project.
create unique index requirements_project_code_key
  on public.requirements (project_id, code);

-- Common list/filter paths.
create index requirements_project_status_idx
  on public.requirements (project_id, status);

-- Hierarchy lookup.
create index requirements_parent_idx
  on public.requirements (parent_requirement_id)
  where parent_requirement_id is not null;

-- Supersession lookup.
create index requirements_superseded_by_idx
  on public.requirements (superseded_by_requirement_id)
  where superseded_by_requirement_id is not null;

-- Tenant / recent-first list.
create index requirements_workspace_idx
  on public.requirements (workspace_id);
create index requirements_project_created_at_idx
  on public.requirements (project_id, created_at desc);

comment on table public.requirements is
  'REQUIREMENTS 002: what a project/design must achieve. Two-level hierarchy via parent_requirement_id. Stable per-project code. Status lifecycle: draft → active → superseded/archived; compliance is per-version (see version_requirement_assessments).';

------------------------------------------------------------------------------
-- 1a. Immutability + hierarchy triggers on requirements
------------------------------------------------------------------------------

-- updated_at bump
create trigger requirements_set_updated_at
  before update on public.requirements
  for each row execute function public.set_updated_at();

-- One-level hierarchy: parent must itself be a root.
create or replace function public.enforce_requirement_hierarchy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent_of_parent uuid;
begin
  if new.parent_requirement_id is null then
    return new;
  end if;
  if new.parent_requirement_id = new.id then
    raise exception 'requirements: parent_requirement_id cannot equal id'
      using errcode='23514';
  end if;
  select parent_requirement_id into v_parent_of_parent
    from public.requirements where id = new.parent_requirement_id;
  if v_parent_of_parent is not null then
    raise exception 'requirements: parent % is itself a sub-requirement; hierarchy is limited to one level',
      new.parent_requirement_id using errcode='23514';
  end if;
  return new;
end $$;

create trigger requirements_enforce_hierarchy
  before insert or update of parent_requirement_id
  on public.requirements
  for each row execute function public.enforce_requirement_hierarchy();

comment on function public.enforce_requirement_hierarchy() is
  'REQUIREMENTS 002: enforces the one-level parent-child rule for requirements. A sub-requirement''s parent must itself be a root (parent_requirement_id IS NULL).';

-- Immutability: code, workspace_id, project_id, parent_requirement_id are structural.
create or replace function public.enforce_requirement_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.workspace_id is distinct from old.workspace_id then
    raise exception 'requirements: workspace_id is immutable' using errcode='23514';
  end if;
  if new.project_id is distinct from old.project_id then
    raise exception 'requirements: project_id is immutable' using errcode='23514';
  end if;
  if new.code is distinct from old.code then
    raise exception 'requirements: code is immutable (create a new requirement or supersede)' using errcode='23514';
  end if;
  if new.parent_requirement_id is distinct from old.parent_requirement_id then
    raise exception 'requirements: parent_requirement_id is immutable (create a new requirement)' using errcode='23514';
  end if;
  return new;
end $$;

create trigger requirements_enforce_immutability
  before update on public.requirements
  for each row execute function public.enforce_requirement_immutability();

comment on function public.enforce_requirement_immutability() is
  'REQUIREMENTS 002: prevents post-creation mutation of code, workspace_id, project_id, and parent_requirement_id. Semantic changes must be recorded via supersession or a Decision.';

------------------------------------------------------------------------------
-- 2. public.requirement_design_assets — applicability join
------------------------------------------------------------------------------
-- Empty for a requirement => project-wide (applies to all design_assets in
-- the project). One or more rows => applies to exactly those design_assets.

create table public.requirement_design_assets (
  requirement_id    uuid not null,
  design_asset_id   uuid not null,
  workspace_id      uuid not null,
  project_id        uuid not null,
  created_at        timestamptz not null default now(),

  primary key (requirement_id, design_asset_id),

  -- Requirement side: workspace + project coherence via two composite FKs
  -- (requirements has UNIQUE(id, workspace_id) and UNIQUE(id, project_id)).
  constraint rda_requirement_ws_fk
    foreign key (requirement_id, workspace_id)
    references public.requirements (id, workspace_id) on delete cascade,
  constraint rda_requirement_project_fk
    foreign key (requirement_id, project_id)
    references public.requirements (id, project_id) on delete cascade,

  -- Design-asset side: enforce workspace + project via the frozen triple
  -- UNIQUE(id, project_id, workspace_id) that design_assets already carries.
  constraint rda_design_asset_triple_fk
    foreign key (design_asset_id, project_id, workspace_id)
    references public.design_assets (id, project_id, workspace_id) on delete cascade
);

create index rda_design_asset_idx
  on public.requirement_design_assets (design_asset_id);
create index rda_project_idx
  on public.requirement_design_assets (project_id);

comment on table public.requirement_design_assets is
  'REQUIREMENTS 002: applicability join. Zero rows for a requirement = project-wide. Presence of rows narrows applicability to exactly those design_assets. Enforces requirement+asset same-project via composite FKs.';

------------------------------------------------------------------------------
-- 3. public.version_requirement_assessments — per-version compliance
------------------------------------------------------------------------------

create table public.version_requirement_assessments (
  id                        uuid primary key default gen_random_uuid(),
  workspace_id              uuid not null,
  project_id                uuid not null,
  asset_version_id          uuid not null,
  requirement_id            uuid not null,
  status                    text not null,
  note                      text null,
  assessed_by_profile_id    uuid null,
  assessed_at               timestamptz not null default now(),
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),

  constraint vra_status_check
    check (status = any (array['satisfied','partial','not_satisfied','not_applicable'])),

  -- Workspace coherence
  constraint vra_version_ws_fk
    foreign key (asset_version_id, workspace_id)
    references public.asset_versions (id, workspace_id) on delete cascade,
  constraint vra_requirement_ws_fk
    foreign key (requirement_id, workspace_id)
    references public.requirements (id, workspace_id) on delete cascade,

  -- Project coherence (version and requirement in SAME project).
  constraint vra_version_project_fk
    foreign key (asset_version_id, project_id)
    references public.asset_versions (id, project_id) on delete cascade,
  constraint vra_requirement_project_fk
    foreign key (requirement_id, project_id)
    references public.requirements (id, project_id) on delete cascade,

  constraint vra_assessor_fk
    foreign key (assessed_by_profile_id)
    references public.profiles (id) on delete set null,

  -- One assessment per (version, requirement); mutable via UPDATE.
  constraint vra_version_requirement_key
    unique (asset_version_id, requirement_id)
);

create index vra_requirement_idx
  on public.version_requirement_assessments (requirement_id);
create index vra_project_status_idx
  on public.version_requirement_assessments (project_id, status);
create index vra_workspace_idx
  on public.version_requirement_assessments (workspace_id);

comment on table public.version_requirement_assessments is
  'REQUIREMENTS 002: records whether a specific asset_version satisfies a specific requirement. Row absence = not_assessed (implicit). Assessment is per-version: v3 satisfying R-012 does not imply v4 satisfies it. Applicability of requirement to the version''s asset is enforced by trigger.';

-- Applicability trigger: assessment target must be applicable.
-- Rules:
--   * If the requirement has no rows in requirement_design_assets → project-wide → OK
--     (composite FKs already guarantee same project as the version).
--   * If it has entries → the version's design_asset must be in that set.
--   * Sub-requirements inherit their parent's applicability (per REQUIREMENTS 001 §6).
create or replace function public.enforce_assessment_applicability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_effective_req_id uuid;
  v_asset_id         uuid;
  v_has_scoped       boolean;
begin
  -- Resolve the effective requirement for applicability (parent, if sub).
  select coalesce(parent_requirement_id, id) into v_effective_req_id
    from public.requirements where id = new.requirement_id;
  if v_effective_req_id is null then
    raise exception 'assessment: requirement % not found', new.requirement_id
      using errcode='23503';
  end if;

  select design_asset_id into v_asset_id
    from public.asset_versions where id = new.asset_version_id;
  if v_asset_id is null then
    raise exception 'assessment: asset_version % not found', new.asset_version_id
      using errcode='23503';
  end if;

  select exists (
    select 1 from public.requirement_design_assets
     where requirement_id = v_effective_req_id
  ) into v_has_scoped;

  if v_has_scoped then
    if not exists (
      select 1 from public.requirement_design_assets
       where requirement_id = v_effective_req_id
         and design_asset_id = v_asset_id
    ) then
      raise exception 'assessment: requirement % is not applicable to design_asset % (version %)',
        new.requirement_id, v_asset_id, new.asset_version_id
        using errcode='23514';
    end if;
  end if;

  return new;
end $$;

create trigger vra_enforce_applicability
  before insert or update of asset_version_id, requirement_id
  on public.version_requirement_assessments
  for each row execute function public.enforce_assessment_applicability();

comment on function public.enforce_assessment_applicability() is
  'REQUIREMENTS 002: gates version_requirement_assessment rows on requirement-to-asset applicability. Sub-requirements inherit parent applicability. Fires on INSERT and on UPDATE of the target FKs.';

-- Immutability: workspace_id, project_id, asset_version_id, requirement_id are structural.
create or replace function public.enforce_assessment_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.workspace_id is distinct from old.workspace_id then
    raise exception 'assessment: workspace_id is immutable' using errcode='23514';
  end if;
  if new.project_id is distinct from old.project_id then
    raise exception 'assessment: project_id is immutable' using errcode='23514';
  end if;
  if new.asset_version_id is distinct from old.asset_version_id then
    raise exception 'assessment: asset_version_id is immutable' using errcode='23514';
  end if;
  if new.requirement_id is distinct from old.requirement_id then
    raise exception 'assessment: requirement_id is immutable' using errcode='23514';
  end if;
  return new;
end $$;

create trigger vra_enforce_immutability
  before update on public.version_requirement_assessments
  for each row execute function public.enforce_assessment_immutability();

create trigger vra_set_updated_at
  before update on public.version_requirement_assessments
  for each row execute function public.set_updated_at();

------------------------------------------------------------------------------
-- 4. Additive nullable columns on frozen tables
------------------------------------------------------------------------------
-- Optional citation of the originating requirement. See REQUIREMENTS 001 §9-10.

alter table public.changes
  add column if not exists requirement_id uuid null;

-- Same workspace AND same project as the change.
alter table public.changes
  add constraint changes_requirement_project_fk
    foreign key (requirement_id, project_id)
    references public.requirements (id, project_id) on delete set null;

create index changes_requirement_idx
  on public.changes (requirement_id)
  where requirement_id is not null;

comment on column public.changes.requirement_id is
  'REQUIREMENTS 002: optional citation of the requirement the change traces to. Enforces same-project via composite FK. ON DELETE SET NULL preserves change history if the requirement is deleted.';

-- decisions has no project_id column (polymorphic targets), so we can only
-- enforce workspace coherence via composite FK. Project coherence is a
-- convention checked in the application layer for MVP.
alter table public.decisions
  add column if not exists requirement_id uuid null;

alter table public.decisions
  add constraint decisions_requirement_ws_fk
    foreign key (requirement_id, workspace_id)
    references public.requirements (id, workspace_id) on delete set null;

create index decisions_requirement_idx
  on public.decisions (requirement_id)
  where requirement_id is not null;

comment on column public.decisions.requirement_id is
  'REQUIREMENTS 002: optional citation of the requirement the decision addresses. Workspace-coherent via composite FK; project coherence is an application-layer convention because decisions has no project_id column. ON DELETE SET NULL preserves decision history.';

------------------------------------------------------------------------------
-- 5. RLS enable
------------------------------------------------------------------------------

alter table public.requirements                     enable row level security;
alter table public.requirement_design_assets        enable row level security;
alter table public.version_requirement_assessments  enable row level security;

------------------------------------------------------------------------------
-- 6. RLS policies
------------------------------------------------------------------------------
-- The five new capability keys (requirement.view / .create / .edit / .archive
-- / .assess) will be wired into lign_has_capability by REQUIREMENTS 003.
-- Until then these predicates evaluate to false for authenticated callers —
-- correct fail-closed behavior. Postgres and service_role continue to bypass.

-- ── requirements ────────────────────────────────────────────────────────────
create policy requirements_select on public.requirements
  as permissive for select to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'requirement.view'));

create policy requirements_insert on public.requirements
  as permissive for insert to authenticated
  with check (public.lign_has_capability(project_id, workspace_id, 'requirement.create'));

-- One UPDATE policy covers edits, status transitions, supersession, and archive.
-- The USING clause gates who may target a row; the WITH CHECK ensures the caller
-- has *some* mutating capability (edit or archive) — the specific transition is
-- validated by triggers / RPCs in REQUIREMENTS 003.
create policy requirements_update on public.requirements
  as permissive for update to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'requirement.view'))
  with check (
    public.lign_has_capability(project_id, workspace_id, 'requirement.edit')
    or public.lign_has_capability(project_id, workspace_id, 'requirement.archive')
  );

-- No DELETE policy → hard delete blocked at RLS level (archive instead).

-- ── requirement_design_assets ───────────────────────────────────────────────
create policy rda_select on public.requirement_design_assets
  as permissive for select to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'requirement.view'));

create policy rda_insert on public.requirement_design_assets
  as permissive for insert to authenticated
  with check (public.lign_has_capability(project_id, workspace_id, 'requirement.edit'));

create policy rda_delete on public.requirement_design_assets
  as permissive for delete to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'requirement.edit'));

-- No UPDATE: applicability rows are (requirement, asset) tuples; change = delete+insert.

-- ── version_requirement_assessments ─────────────────────────────────────────
create policy vra_select on public.version_requirement_assessments
  as permissive for select to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'requirement.view'));

create policy vra_insert on public.version_requirement_assessments
  as permissive for insert to authenticated
  with check (
    public.lign_has_capability(project_id, workspace_id, 'requirement.assess')
    and assessed_by_profile_id = (select auth.uid())
  );

create policy vra_update on public.version_requirement_assessments
  as permissive for update to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'requirement.view'))
  with check (public.lign_has_capability(project_id, workspace_id, 'requirement.assess'));

------------------------------------------------------------------------------
-- 7. Trigger-function EXECUTE lock-down
------------------------------------------------------------------------------
-- These SECURITY DEFINER functions exist only to be fired by their triggers.
-- Exposing them via PostgREST /rpc is pointless and produces advisor findings.

revoke all on function public.enforce_requirement_hierarchy()      from public, anon, authenticated;
revoke all on function public.enforce_requirement_immutability()   from public, anon, authenticated;
revoke all on function public.enforce_assessment_applicability()   from public, anon, authenticated;
revoke all on function public.enforce_assessment_immutability()    from public, anon, authenticated;

-- No DELETE: assessments are historical records; a re-assessment is an UPDATE.
