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
  constraint requirements_project_fk
    foreign key (project_id, workspace_id)
    references public.projects (id, workspace_id) on delete restrict,
  constraint requirements_id_workspace_key unique (id, workspace_id),
  constraint requirements_id_project_key   unique (id, project_id),
  constraint requirements_parent_fk
    foreign key (parent_requirement_id, project_id)
    references public.requirements (id, project_id) on delete restrict,
  constraint requirements_superseded_by_fk
    foreign key (superseded_by_requirement_id, project_id)
    references public.requirements (id, project_id) on delete restrict,
  constraint requirements_created_by_fk
    foreign key (created_by_profile_id)
    references public.profiles (id) on delete set null,
  constraint requirements_status_check
    check (status = any (array['draft','active','superseded','archived'])),
  constraint requirements_code_check check (length(code) between 1 and 32),
  constraint requirements_title_check check (length(title) between 1 and 500),
  constraint requirements_no_self_supersede
    check (superseded_by_requirement_id is null or superseded_by_requirement_id <> id),
  constraint requirements_superseded_coherence
    check ((status =  'superseded' and superseded_by_requirement_id is not null)
        or (status <> 'superseded' and superseded_by_requirement_id is null)),
  constraint requirements_archived_coherence
    check ((status =  'archived' and archived_at is not null)
        or (status <> 'archived' and archived_at is null))
);

create unique index requirements_project_code_key on public.requirements (project_id, code);
create index requirements_project_status_idx on public.requirements (project_id, status);
create index requirements_parent_idx on public.requirements (parent_requirement_id) where parent_requirement_id is not null;
create index requirements_superseded_by_idx on public.requirements (superseded_by_requirement_id) where superseded_by_requirement_id is not null;
create index requirements_workspace_idx on public.requirements (workspace_id);
create index requirements_project_created_at_idx on public.requirements (project_id, created_at desc);

create trigger requirements_set_updated_at before update on public.requirements
  for each row execute function public.set_updated_at();

create or replace function public.enforce_requirement_hierarchy()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_parent_of_parent uuid;
begin
  if new.parent_requirement_id is null then return new; end if;
  if new.parent_requirement_id = new.id then
    raise exception 'requirements: parent_requirement_id cannot equal id' using errcode='23514';
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
  before insert or update of parent_requirement_id on public.requirements
  for each row execute function public.enforce_requirement_hierarchy();

create or replace function public.enforce_requirement_immutability()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.workspace_id is distinct from old.workspace_id then
    raise exception 'requirements: workspace_id is immutable' using errcode='23514'; end if;
  if new.project_id is distinct from old.project_id then
    raise exception 'requirements: project_id is immutable' using errcode='23514'; end if;
  if new.code is distinct from old.code then
    raise exception 'requirements: code is immutable (create a new requirement or supersede)' using errcode='23514'; end if;
  if new.parent_requirement_id is distinct from old.parent_requirement_id then
    raise exception 'requirements: parent_requirement_id is immutable (create a new requirement)' using errcode='23514'; end if;
  return new;
end $$;

create trigger requirements_enforce_immutability before update on public.requirements
  for each row execute function public.enforce_requirement_immutability();

create table public.requirement_design_assets (
  requirement_id    uuid not null,
  design_asset_id   uuid not null,
  workspace_id      uuid not null,
  project_id        uuid not null,
  created_at        timestamptz not null default now(),
  primary key (requirement_id, design_asset_id),
  constraint rda_requirement_ws_fk
    foreign key (requirement_id, workspace_id)
    references public.requirements (id, workspace_id) on delete cascade,
  constraint rda_requirement_project_fk
    foreign key (requirement_id, project_id)
    references public.requirements (id, project_id) on delete cascade,
  constraint rda_design_asset_triple_fk
    foreign key (design_asset_id, project_id, workspace_id)
    references public.design_assets (id, project_id, workspace_id) on delete cascade
);

create index rda_design_asset_idx on public.requirement_design_assets (design_asset_id);
create index rda_project_idx on public.requirement_design_assets (project_id);

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
  constraint vra_version_ws_fk
    foreign key (asset_version_id, workspace_id)
    references public.asset_versions (id, workspace_id) on delete cascade,
  constraint vra_requirement_ws_fk
    foreign key (requirement_id, workspace_id)
    references public.requirements (id, workspace_id) on delete cascade,
  constraint vra_version_project_fk
    foreign key (asset_version_id, project_id)
    references public.asset_versions (id, project_id) on delete cascade,
  constraint vra_requirement_project_fk
    foreign key (requirement_id, project_id)
    references public.requirements (id, project_id) on delete cascade,
  constraint vra_assessor_fk
    foreign key (assessed_by_profile_id)
    references public.profiles (id) on delete set null,
  constraint vra_version_requirement_key unique (asset_version_id, requirement_id)
);

create index vra_requirement_idx on public.version_requirement_assessments (requirement_id);
create index vra_project_status_idx on public.version_requirement_assessments (project_id, status);
create index vra_workspace_idx on public.version_requirement_assessments (workspace_id);

create or replace function public.enforce_assessment_applicability()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_effective_req_id uuid; v_asset_id uuid; v_has_scoped boolean;
begin
  select coalesce(parent_requirement_id, id) into v_effective_req_id
    from public.requirements where id = new.requirement_id;
  if v_effective_req_id is null then
    raise exception 'assessment: requirement % not found', new.requirement_id using errcode='23503';
  end if;
  select design_asset_id into v_asset_id
    from public.asset_versions where id = new.asset_version_id;
  if v_asset_id is null then
    raise exception 'assessment: asset_version % not found', new.asset_version_id using errcode='23503';
  end if;
  select exists (select 1 from public.requirement_design_assets where requirement_id = v_effective_req_id)
    into v_has_scoped;
  if v_has_scoped then
    if not exists (select 1 from public.requirement_design_assets
                   where requirement_id = v_effective_req_id and design_asset_id = v_asset_id) then
      raise exception 'assessment: requirement % is not applicable to design_asset % (version %)',
        new.requirement_id, v_asset_id, new.asset_version_id using errcode='23514';
    end if;
  end if;
  return new;
end $$;

create trigger vra_enforce_applicability
  before insert or update of asset_version_id, requirement_id
  on public.version_requirement_assessments
  for each row execute function public.enforce_assessment_applicability();

create or replace function public.enforce_assessment_immutability()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.workspace_id is distinct from old.workspace_id then
    raise exception 'assessment: workspace_id is immutable' using errcode='23514'; end if;
  if new.project_id is distinct from old.project_id then
    raise exception 'assessment: project_id is immutable' using errcode='23514'; end if;
  if new.asset_version_id is distinct from old.asset_version_id then
    raise exception 'assessment: asset_version_id is immutable' using errcode='23514'; end if;
  if new.requirement_id is distinct from old.requirement_id then
    raise exception 'assessment: requirement_id is immutable' using errcode='23514'; end if;
  return new;
end $$;

create trigger vra_enforce_immutability before update on public.version_requirement_assessments
  for each row execute function public.enforce_assessment_immutability();

create trigger vra_set_updated_at before update on public.version_requirement_assessments
  for each row execute function public.set_updated_at();

alter table public.changes add column if not exists requirement_id uuid null;
alter table public.changes add constraint changes_requirement_project_fk
  foreign key (requirement_id, project_id) references public.requirements (id, project_id) on delete set null;
create index changes_requirement_idx on public.changes (requirement_id) where requirement_id is not null;

alter table public.decisions add column if not exists requirement_id uuid null;
alter table public.decisions add constraint decisions_requirement_ws_fk
  foreign key (requirement_id, workspace_id) references public.requirements (id, workspace_id) on delete set null;
create index decisions_requirement_idx on public.decisions (requirement_id) where requirement_id is not null;

alter table public.requirements                     enable row level security;
alter table public.requirement_design_assets        enable row level security;
alter table public.version_requirement_assessments  enable row level security;

create policy requirements_select on public.requirements
  as permissive for select to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'requirement.view'));
create policy requirements_insert on public.requirements
  as permissive for insert to authenticated
  with check (public.lign_has_capability(project_id, workspace_id, 'requirement.create'));
create policy requirements_update on public.requirements
  as permissive for update to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'requirement.view'))
  with check (public.lign_has_capability(project_id, workspace_id, 'requirement.edit')
           or public.lign_has_capability(project_id, workspace_id, 'requirement.archive'));

create policy rda_select on public.requirement_design_assets
  as permissive for select to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'requirement.view'));
create policy rda_insert on public.requirement_design_assets
  as permissive for insert to authenticated
  with check (public.lign_has_capability(project_id, workspace_id, 'requirement.edit'));
create policy rda_delete on public.requirement_design_assets
  as permissive for delete to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'requirement.edit'));

create policy vra_select on public.version_requirement_assessments
  as permissive for select to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'requirement.view'));
create policy vra_insert on public.version_requirement_assessments
  as permissive for insert to authenticated
  with check (public.lign_has_capability(project_id, workspace_id, 'requirement.assess')
              and assessed_by_profile_id = (select auth.uid()));
create policy vra_update on public.version_requirement_assessments
  as permissive for update to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'requirement.view'))
  with check (public.lign_has_capability(project_id, workspace_id, 'requirement.assess'));
