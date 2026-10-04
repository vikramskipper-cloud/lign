-- APP 019 — requirements may be scoped to a collection.
--
-- The first of two slices. This one adds the SCOPE; nesting the spaces
-- themselves is APP 020, and the reason for the split is below.
--
-- WHAT WAS MISSING. list_applicable_requirements had exactly two scopes:
--
--   project-wide = a requirement root linked to NO assets
--   asset-scoped = a requirement root linked to THIS asset
--
-- A requirement governing one room had nowhere correct to live. Project-wide
-- also bound the kitchen; asset-scoped meant a row per element, maintained by
-- hand.
--
-- The hand-maintained version FAILS OPEN, which is the actual defect. Add an
-- element to the room next week and it inherits nothing — the requirement
-- silently stops covering new work, and nothing reports it. For a product whose
-- purpose is proving what was approved against what, a compliance rule that
-- quietly narrows is worse than one that errors.
--
-- Requirements already nested (parent_requirement_id). Spaces had no scope at
-- all. That asymmetry was the whole problem, and it is fixed here without
-- touching the shape of either table.
--
-- WHY SCOPE SHIPS BEFORE NESTING. Scope is the primitive and nesting is the
-- multiplier. Scoping to one room already removes the fail-open behaviour,
-- because position in the collection IS the scope and a new element in that
-- collection is covered by construction. Nesting then lets a scope cascade
-- (Floor 2 -> Living room -> Zone) but adds nothing to the guarantee.
--
-- Everything here is CREATE or CREATE OR REPLACE: no column added, no
-- constraint dropped, no trigger attached to an existing table.
--
-- ONE BEHAVIOUR CHANGE TO NOTE, in a frozen read RPC: out_is_project_wide now
-- means "scoped to NOTHING at all". A requirement scoped to a collection stops
-- reporting as project-wide. Without that, scoping to one room would have left
-- it applying everywhere as well, which is the opposite of the point.

create table public.requirement_collections (
  requirement_id uuid not null,
  collection_id  uuid not null,
  workspace_id   uuid not null,
  project_id     uuid not null,
  created_at     timestamptz not null default now(),
  primary key (requirement_id, collection_id),
  constraint requirement_collections_requirement_fk
    foreign key (requirement_id) references public.requirements (id) on delete cascade,
  -- Composite, so a requirement cannot be scoped to a collection in a different
  -- project. It reuses collections_id_project_workspace_key, which already
  -- exists; a plain FK on collection_id alone would have allowed it.
  constraint requirement_collections_collection_fk
    foreign key (collection_id, project_id, workspace_id)
    references public.collections (id, project_id, workspace_id) on delete cascade
);

comment on table public.requirement_collections is
  'A requirement scoped to a space. Explicit and dated rather than inferred from position, so "scoped to the Living room, by this person, on this date" is a fact the audit trail holds.';

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
-- argument on it: a tail param would have created a second overload reachable
-- from PostgREST, which is the PGRST203 ambiguity that bit create_review, and
-- removing the old signature would have been a destructive statement.
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

  -- Every collection must be in the requirement's own project. The composite FK
  -- would catch this on insert, but a named error beats a constraint name.
  if exists (
    select 1 from unnest(coalesce(p_collection_ids, '{}'::uuid[])) as x(id)
     where not exists (
       select 1 from public.collections c where c.id = x.id and c.project_id = v_pj
     )
  ) then
    raise exception 'set_requirement_collections: a collection is missing or belongs to another project'
      using errcode = '23503';
  end if;

  -- Replace rather than merge, matching set_requirement_applicability: the
  -- caller sends the scope it wants, not a delta.
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

grant execute on function public.set_requirement_collections(uuid, uuid[]) to authenticated;

-- ----------------------------------------------- applicability, third arm ----
--
--   applicable(asset) =
--         project-wide        (root scoped to NO asset AND NO collection)
--       u asset-scoped        (root linked to this asset)
--       u collection-scoped   (root linked to THIS ASSET'S collection)
--
-- When APP 020 nests collections, the only change here is that the third arm
-- matches the asset's collection OR ANY ANCESTOR of it: the `ancestry` CTE
-- below becomes a recursive walk instead of a single row. It is written as a
-- CTE now, rather than inlined into the join, specifically so that swap is one
-- clause and not a rewrite.

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
    -- The spaces this asset belongs to. Exactly one today; its ancestors too
    -- once collections nest. Empty when the asset sits in no collection, which
    -- keeps such assets on precisely the old behaviour.
    ancestry as (
      select v_coll as collection_id where v_coll is not null
    ),
    scoped_root_ids as (
      select distinct requirement_id as root_id from public.requirement_design_assets where design_asset_id = p_design_asset_id
    ),
    collection_root_ids as (
      select distinct rc.requirement_id as root_id
        from public.requirement_collections rc
        join ancestry a on a.collection_id = rc.collection_id
    ),
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

-- --------------------------- the write gate must agree with the read ---------
--
-- This is a BEFORE trigger on version_requirement_assessments: it decides what
-- can be RECORDED, not merely what is listed. Updating the read without
-- updating this would mean the UI offers a requirement and the database then
-- refuses the assessment — the worst possible split, because it looks like a
-- save bug rather than a scope rule.

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

  -- Unscoped stays unscoped: neither kind of link means project-wide, applying
  -- to everything, exactly as before this migration.
  if not v_has_asset_scope and not v_has_coll_scope then
    return new;
  end if;

  if exists (select 1 from public.requirement_design_assets
              where requirement_id = v_effective_req_id and design_asset_id = v_asset_id) then
    return new;
  end if;

  -- Becomes "collection or any ancestor" in APP 020.
  if v_coll is not null and exists (
    select 1 from public.requirement_collections rc
     where rc.requirement_id = v_effective_req_id and rc.collection_id = v_coll
  ) then
    return new;
  end if;

  raise exception 'assessment: requirement % is not applicable to design_asset % (version %)',
    new.requirement_id, v_asset_id, new.asset_version_id using errcode='23514';
end $function$;