-- APP 019a — nested collections and collection-scoped requirements (additive).
--
-- Approved against DOMAIN_MODEL §1.2a. The question arrived as "can a project
-- hold nested sub-spaces — Living room, then front wall", and the case that
-- decides it is requirements, not filing.
--
-- WHAT WAS MISSING. list_applicable_requirements had exactly two scopes:
--
--   project-wide = a requirement root linked to NO assets
--   asset-scoped = a requirement root linked to THIS asset
--
-- A requirement that governs one room had nowhere correct to live. Project-wide
-- also bound the kitchen; asset-scoped meant a row per element, maintained by
-- hand. And the hand-maintained version FAILS OPEN: add an element next week
-- and it inherits nothing, so the requirement silently stops covering new work
-- and nothing reports it. For a product whose purpose is proving what was
-- approved against what, a rule that quietly narrows is worse than one that
-- errors.
--
-- Requirements already nested (parent_requirement_id). Spaces did not. The
-- asymmetry was the defect.
--
-- THE LINE HELD: elements do not nest. A DesignAsset carries versions, so it is
-- the unit that gets approved; if elements contained elements, "approved" would
-- stop having one answer. Sub-parts that are not separately approved are files
-- within one version, which already works.

-- ------------------------------------------------- 1. collections become a tree

alter table public.collections
  add column parent_collection_id uuid;

-- Composite FK, not a plain one: it pins the parent to the SAME project using
-- collections_id_project_workspace_key, which already exists. A plain FK would
-- have allowed a parent from another project inside the same workspace.
alter table public.collections
  add constraint collections_parent_fk
  foreign key (parent_collection_id, project_id, workspace_id)
  references public.collections (id, project_id, workspace_id)
  on delete restrict;

comment on column public.collections.parent_collection_id is
  'Parent space. Null for a root. Max depth 4, enforced by trigger.';

-- Rule 10: every FK gets a covering index. Also the shape the ancestry walk
-- probes, child -> parent.
create index collections_parent_collection_id_idx
  on public.collections (parent_collection_id)
  where parent_collection_id is not null;

-- NOTE, and a real limitation until APP 019b lands: collection names are still
-- unique per PROJECT, because collections_project_name_active_key is still in
-- place. Replacing it is a DROP INDEX, which is the destructive class this
-- environment holds back, so it is split into 019b as a standalone statement
-- pair. Until then two sibling spaces cannot share a name — the Living room and
-- the Kitchen cannot each hold a "Wardrobe". Everything else about nesting and
-- collection-scoped requirements works without it.

create or replace function public.enforce_collection_tree()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_depth    integer := 0;
  v_cursor   uuid;
  v_parent_pj uuid;
begin
  if new.parent_collection_id is null then
    return new;
  end if;
  if new.parent_collection_id = new.id then
    raise exception 'collection cannot be its own parent' using errcode = '23514';
  end if;

  select project_id into v_parent_pj
    from public.collections where id = new.parent_collection_id;
  if v_parent_pj is null then
    raise exception 'parent collection % not found', new.parent_collection_id
      using errcode = '23503';
  end if;
  if v_parent_pj <> new.project_id then
    raise exception 'parent collection belongs to a different project'
      using errcode = '23514';
  end if;

  -- Walk up from the proposed parent. This both counts depth and detects a
  -- cycle: if we meet the row being saved on the way up, the edge would close
  -- a loop. The composite FK cannot catch that — it only checks the one hop.
  v_cursor := new.parent_collection_id;
  while v_cursor is not null loop
    v_depth := v_depth + 1;
    if v_cursor = new.id then
      raise exception 'collection parent would create a cycle' using errcode = '23514';
    end if;
    if v_depth > 8 then
      raise exception 'collection ancestry exceeds the hard limit (corrupt tree?)'
        using errcode = '23514';
    end if;
    select parent_collection_id into v_cursor
      from public.collections where id = v_cursor;
  end loop;

  -- Depth 4 total: a parent at depth 3 may take children, one at depth 4 may
  -- not. Covers Building > Floor > Room > Zone, and keeps the ancestry walk
  -- bounded so applicability stays cheap. Raising it later is a constant.
  if v_depth >= 4 then
    raise exception 'collection nesting is limited to 4 levels (parent is already at depth %)', v_depth
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

create trigger collections_enforce_tree
  before insert or update of parent_collection_id, project_id on public.collections
  for each row execute function public.enforce_collection_tree();

-- Ancestry of a collection, itself first. Used by applicability and by the
-- assessment trigger, so it exists once rather than being inlined twice and
-- drifting.
--
-- Note on APP 016a: that migration flattened two helpers because nested
-- SECURITY DEFINER calls cannot be inlined by the planner and were costing 14x
-- on an RLS per-row path. This one is deliberately a helper anyway — it is
-- called from read RPCs and a write trigger, once per call, never once per
-- candidate row. Measured after applying; see the APP 019 report.
create or replace function public.lign_collection_ancestry(p_collection_id uuid)
returns table (collection_id uuid)
language sql
stable parallel safe security definer
set search_path to ''
as $function$
  with recursive up as (
    select c.id, c.parent_collection_id, 1 as lvl
      from public.collections c
     where c.id = p_collection_id
    union all
    select c.id, c.parent_collection_id, up.lvl + 1
      from public.collections c
      join up on c.id = up.parent_collection_id
     where up.lvl < 8
  )
  select id from up;
$function$;

-- ------------------------------------- 2. requirements may be scoped to a space

create table public.requirement_collections (
  requirement_id uuid not null,
  collection_id  uuid not null,
  workspace_id   uuid not null,
  project_id     uuid not null,
  created_at     timestamptz not null default now(),
  primary key (requirement_id, collection_id),
  constraint requirement_collections_requirement_fk
    foreign key (requirement_id) references public.requirements (id) on delete cascade,
  constraint requirement_collections_collection_fk
    foreign key (collection_id, project_id, workspace_id)
    references public.collections (id, project_id, workspace_id) on delete cascade
);

comment on table public.requirement_collections is
  'A requirement scoped to a space. Explicit and dated rather than inherited by position, so "scoped to the Living room, by this person, on this date" is a fact the audit trail holds.';

create index requirement_collections_collection_id_idx
  on public.requirement_collections (collection_id);
create index requirement_collections_project_idx
  on public.requirement_collections (project_id, workspace_id);

alter table public.requirement_collections enable row level security;

create policy requirement_collections_select on public.requirement_collections
  for select to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'requirement.view'));

grant select, insert, update, delete, truncate, references, trigger
  on table public.requirement_collections to anon, authenticated, service_role;

-- Additive sibling of set_requirement_applicability rather than a third
-- argument on it: adding a tail param would have created a second overload
-- reachable from PostgREST, which is the PGRST203 ambiguity that bit
-- create_review, and removing the old signature would have been a third
-- destructive statement.
create or replace function public.set_requirement_collections(
  p_requirement_id uuid,
  p_collection_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_caller uuid; v_ws uuid; v_pj uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'set_requirement_collections: authentication required' using errcode = '42501';
  end if;
  select workspace_id, project_id into v_ws, v_pj
    from public.requirements where id = p_requirement_id;
  if v_ws is null then
    raise exception 'set_requirement_collections: requirement % not found', p_requirement_id
      using errcode = '23503';
  end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.edit') then
    raise exception 'set_requirement_collections: forbidden (requirement.edit)' using errcode = '42501';
  end if;

  -- Every collection must be in the requirement's own project. The composite
  -- FK would catch this on insert, but a named error beats a constraint name.
  if exists (
    select 1 from unnest(coalesce(p_collection_ids, '{}'::uuid[])) as x(id)
     where not exists (
       select 1 from public.collections c where c.id = x.id and c.project_id = v_pj
     )
  ) then
    raise exception 'set_requirement_collections: a collection is missing or belongs to another project'
      using errcode = '23503';
  end if;

  delete from public.requirement_collections where requirement_id = p_requirement_id;
  insert into public.requirement_collections (requirement_id, collection_id, workspace_id, project_id)
  select p_requirement_id, x.id, v_ws, v_pj
    from unnest(coalesce(p_collection_ids, '{}'::uuid[])) as x(id)
  on conflict do nothing;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  select v_ws, v_pj, now(), 'requirement.applicability_changed', v_caller, 'user',
         'requirement', p_requirement_id, r.code,
         jsonb_build_object('collection_ids', coalesce(p_collection_ids, '{}'::uuid[])),
         jsonb_build_object('scope', 'collection')
    from public.requirements r where r.id = p_requirement_id;
end;
$function$;

grant execute on function public.lign_collection_ancestry(uuid)          to authenticated;
grant execute on function public.set_requirement_collections(uuid, uuid[]) to authenticated;

-- ------------------------------------------- 3. applicability gains a third arm

create or replace function public.list_applicable_requirements(
  p_design_asset_id uuid,
  p_asset_version_id uuid default null
)
returns table (
  out_requirement_id uuid,
  out_code text,
  out_title text,
  out_status text,
  out_parent_requirement_id uuid,
  out_is_project_wide boolean,
  out_assessment_status text,
  out_assessed_at timestamp with time zone,
  out_assessed_by_profile_id uuid
)
language plpgsql
stable security definer
set search_path to ''
as $function$
declare v_ws uuid; v_pj uuid; v_coll uuid;
begin
  if auth.uid() is null then raise exception 'list_applicable_requirements: authentication required' using errcode='42501'; end if;
  select workspace_id, project_id, collection_id into v_ws, v_pj, v_coll
    from public.design_assets where id = p_design_asset_id;
  if v_ws is null then raise exception 'list_applicable_requirements: design_asset % not found', p_design_asset_id using errcode='23503'; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.view') then
    raise exception 'list_applicable_requirements: forbidden (requirement.view)' using errcode='42501';
  end if;
  if p_asset_version_id is not null then
    perform 1 from public.asset_versions where id = p_asset_version_id and design_asset_id = p_design_asset_id;
    if not found then
      raise exception 'list_applicable_requirements: asset_version % is not part of design_asset %', p_asset_version_id, p_design_asset_id using errcode='23514';
    end if;
  end if;
  return query
    with root_scoped as (
      select r.id, r.code, r.title, r.status, r.parent_requirement_id, coalesce(r.parent_requirement_id, r.id) as effective_root_id
        from public.requirements r where r.project_id = v_pj and r.status in ('draft','active')
    ),
    all_project_roots as (
      select id from public.requirements where project_id = v_pj and parent_requirement_id is null and status in ('draft','active')
    ),
    -- This asset's own collection and every ancestor of it. Empty when the
    -- asset sits in no collection, which keeps such assets on the old
    -- behaviour exactly.
    ancestry as (
      select collection_id from public.lign_collection_ancestry(v_coll) where v_coll is not null
    ),
    scoped_root_ids as (
      select distinct requirement_id as root_id from public.requirement_design_assets where design_asset_id = p_design_asset_id
    ),
    collection_root_ids as (
      select distinct rc.requirement_id as root_id
        from public.requirement_collections rc
        join ancestry a on a.collection_id = rc.collection_id
    ),
    -- Project-wide now means "scoped to nothing at all". A root carrying a
    -- collection scope is NOT project-wide — without this clause, scoping a
    -- requirement to one room would have left it applying everywhere as well,
    -- which is the opposite of the point.
    root_wide as (
      select id from all_project_roots where id not in (
        select requirement_id from public.requirement_design_assets where requirement_id in (select id from all_project_roots)
        union
        select requirement_id from public.requirement_collections where requirement_id in (select id from all_project_roots)
      )
    ),
    applicable_root_ids as (
      select id from root_wide
      union select root_id as id from scoped_root_ids
      union select root_id as id from collection_root_ids
    )
    select rs.id, rs.code, rs.title, rs.status, rs.parent_requirement_id,
           (rs.effective_root_id in (select id from root_wide)) as is_pw,
           a.status, a.assessed_at, a.assessed_by_profile_id
      from root_scoped rs
      left join public.version_requirement_assessments a
             on a.asset_version_id = p_asset_version_id and a.requirement_id = rs.id
     where rs.effective_root_id in (select id from applicable_root_ids)
     order by rs.code;
end $function$;

-- --------------------------- 4. the write gate must agree with the read ------
-- This is a BEFORE trigger on version_requirement_assessments: it decides what
-- can be RECORDED. If it did not learn about collection scope, a requirement
-- that the UI correctly showed as applicable would be refused on assessment.

create or replace function public.enforce_assessment_applicability()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_effective_req_id uuid; v_asset_id uuid; v_coll uuid;
  v_has_asset_scope boolean; v_has_coll_scope boolean;
begin
  select coalesce(parent_requirement_id, id) into v_effective_req_id
    from public.requirements where id = new.requirement_id;
  if v_effective_req_id is null then
    raise exception 'assessment: requirement % not found', new.requirement_id using errcode='23503';
  end if;
  select av.design_asset_id, da.collection_id into v_asset_id, v_coll
    from public.asset_versions av
    join public.design_assets da on da.id = av.design_asset_id
   where av.id = new.asset_version_id;
  if v_asset_id is null then
    raise exception 'assessment: asset_version % not found', new.asset_version_id using errcode='23503';
  end if;

  select exists (select 1 from public.requirement_design_assets where requirement_id = v_effective_req_id)
    into v_has_asset_scope;
  select exists (select 1 from public.requirement_collections where requirement_id = v_effective_req_id)
    into v_has_coll_scope;

  -- Unscoped stays unscoped: a requirement with neither kind of link is
  -- project-wide and applies to everything, exactly as before.
  if not v_has_asset_scope and not v_has_coll_scope then
    return new;
  end if;

  if exists (select 1 from public.requirement_design_assets
              where requirement_id = v_effective_req_id and design_asset_id = v_asset_id) then
    return new;
  end if;

  if v_coll is not null and exists (
    select 1 from public.requirement_collections rc
      join public.lign_collection_ancestry(v_coll) a on a.collection_id = rc.collection_id
     where rc.requirement_id = v_effective_req_id
  ) then
    return new;
  end if;

  raise exception 'assessment: requirement % is not applicable to design_asset % (version %)',
    new.requirement_id, v_asset_id, new.asset_version_id using errcode='23514';
end $function$;