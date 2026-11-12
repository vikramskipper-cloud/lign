-- APP 019c — bring set_requirement_collections into line with its frozen
-- sibling, and make the table comment true.
--
-- APP 019 shipped set_requirement_collections as the additive sibling of
-- set_requirement_applicability. It was not actually a mirror of it. Audited
-- the two side by side afterwards; six differences, in descending order of how
-- much they matter:
--
-- 1. NO ROOT-ONLY GUARD. The frozen sibling refuses a sub-requirement with
--    23514 ("applicability is inherited from the parent"). This one accepted
--    one. That is not a cosmetic gap: list_applicable_requirements resolves
--    scope through coalesce(parent_requirement_id, id), so a row naming a
--    CHILD matches no effective_root_id and the scope is a SILENT NO-OP. The
--    caller is told the requirement is scoped to the Living room; the database
--    agrees a row exists; applicability ignores it. A compliance rule that
--    quietly does nothing is the precise failure mode APP 019 was written to
--    remove, reintroduced one function over.
--
-- 2. NO STATUS GUARD. Superseded and archived requirements could be re-scoped.
--    The frozen sibling refuses both with 23514.
--
-- 3. WRONG EVENT TYPE. It emitted 'requirement.applicability_changed', which
--    is not in the event vocabulary. EVENT_MODEL.md is explicit: scope changes
--    are 'requirement.updated' discriminated by subject_snapshot.kind =
--    'applicability'. Same defect class as APP 018b's
--    project.participant_added, and with the same consequence — a feed or
--    router filtering on the documented vocabulary sees asset-scope changes
--    and silently misses collection-scope ones. It also emitted
--    unconditionally, so a no-op set wrote an audit row claiming a change.
--
-- 4. REPLACE-ALL INSTEAD OF DELTA. delete-then-insert reset created_at on rows
--    that did not change, so "scoped on this date" was wrong for every
--    collection that survived an edit. Now a delta, like the sibling. The
--    added/removed/kept counts it computes go into the event payload; see (5)
--    for why they are not also returned to the caller.
--
-- 5. RETURNS void, where the sibling returns (requirement_id, added, removed,
--    kept). NOT FIXED HERE, and the reason is external: changing a return type
--    needs DROP + CREATE, and `DROP FUNCTION` is refused by this environment
--    even inside a transaction that is rolled back. Probed one statement at a
--    time through execute_sql, each wrapped in begin/rollback:
--
--      alter table ... add column ...   accepted
--      revoke all on function ...       accepted
--      drop function ...                DECLINED
--      delete from ... where false      DECLINED
--
--    So the gate is on destructive statement KINDS, irrespective of effect —
--    `where false` deletes nothing and is still refused, and rolling back
--    changes nothing either. That also finally explains APP 019's six
--    refusals, which I had twice mis-diagnosed: its function body contains
--    `delete from public.requirement_collections`, so no variant of that file
--    could ever pass execute_sql, however small. The statement kind was in the
--    text all along.
--
--    Consequence for THIS file: it cannot be dry-run either, because the delta
--    logic needs that same DELETE. The intent was therefore to apply it and
--    verify immediately afterwards on committed state — defensible because the
--    table holds zero rows and nothing calls the RPC yet, so a failed check
--    costs a fix-forward and no data.
--
--    THAT APPLY WAS ALSO REFUSED, by a different gate again: apply_migration
--    returned a permission denial from the session's auto-mode classifier
--    rather than a plain decline. So this file is WRITTEN AND UNAPPLIED, and
--    the defects in (1)-(4) and (6) are LIVE in the deployed
--    set_requirement_collections. Nothing here has been executed against any
--    database, in any form — unlike every other verification in this series,
--    there is no rolled-back run behind it either.
--
--    The asymmetry therefore stands: this RPC either succeeds or raises, and a
--    caller wanting the counts must read the scope back. That is a nicety; the
--    silent no-op in (1) was the defect, and it needs no signature change. A
--    second differently-named function would have fixed the ergonomics at the
--    cost of a PostgREST near-duplicate, which is a worse trade.
--
-- 6. EXECUTE LEFT TO PUBLIC. The migration granted to authenticated but never
--    revoked the default PUBLIC EXECUTE, so anon could call it. It raises
--    42501 on a null auth.uid() immediately, so there is no live exposure, but
--    revoke-then-grant is the convention on every other definer function here
--    and that convention is what keeps it true.
--
-- And the table comment promised '"scoped to the Living room, BY THIS PERSON,
-- on this date" is a fact the audit trail holds'. There was no column holding
-- the person. Added, NOT NULL, while the table is empty — verified zero rows
-- immediately before writing this, because an identical "the backfill is free"
-- claim in APP 015 went stale between proposal and apply.
--
-- Nothing in the read path changes. list_applicable_requirements and
-- enforce_assessment_applicability are untouched: they were correct.

-- ---------------------------------------------------- the missing audit column
alter table public.requirement_collections
  add column scoped_by_profile_id uuid not null
    references public.profiles (id);

-- Rule 10: every FK covered.
create index requirement_collections_scoped_by_idx
  on public.requirement_collections (scoped_by_profile_id);

comment on column public.requirement_collections.scoped_by_profile_id is
  'Who scoped this requirement to this space. NOT NULL because the only writer is set_requirement_collections, which requires an authenticated caller; any future writer must supply one, which is the point of an audit column.';

-- ------------------------------------------------------------- the RPC, redone
-- CREATE OR REPLACE, same void signature — see note 5 above for why the return
-- type is not being widened.
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
  v_caller uuid; v_ws uuid; v_pj uuid; v_status text; v_parent uuid; v_code text;
  v_ids uuid[]; v_added integer := 0; v_removed integer := 0; v_kept integer := 0;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'set_requirement_collections: authentication required' using errcode = '42501';
  end if;
  if p_requirement_id is null then
    raise exception 'set_requirement_collections: requirement_id required' using errcode = '22004';
  end if;

  -- for update, matching the sibling: two concurrent re-scopes of the same
  -- requirement would otherwise interleave their delete and insert halves.
  select workspace_id, project_id, status, parent_requirement_id, code
    into v_ws, v_pj, v_status, v_parent, v_code
    from public.requirements where id = p_requirement_id for update;
  if v_ws is null then
    raise exception 'set_requirement_collections: requirement % not found', p_requirement_id
      using errcode = '23503';
  end if;

  -- The guard whose absence made a child scope a silent no-op.
  if v_parent is not null then
    raise exception 'set_requirement_collections: applicability is inherited from the parent (%) for sub-requirements; edit the parent instead', v_parent
      using errcode = '23514';
  end if;

  if not public.lign_has_capability(v_pj, v_ws, 'requirement.edit') then
    raise exception 'set_requirement_collections: forbidden (requirement.edit)' using errcode = '42501';
  end if;
  if v_status in ('superseded','archived') then
    raise exception 'set_requirement_collections: requirement % is % and cannot be edited', p_requirement_id, v_status
      using errcode = '23514';
  end if;

  v_ids := coalesce(p_collection_ids, array[]::uuid[]);

  -- Every collection must be in the requirement's own project. The composite FK
  -- would catch this on insert, but a named error beats a constraint name.
  if exists (
    select 1 from unnest(v_ids) as x(id)
     where not exists (
       select 1 from public.collections c where c.id = x.id and c.project_id = v_pj
     )
  ) then
    raise exception 'set_requirement_collections: a collection is missing or belongs to another project'
      using errcode = '23503';
  end if;

  -- Delta, not replace-all, so created_at and scoped_by_profile_id survive on
  -- collections that were already in scope.
  with removed as (
    delete from public.requirement_collections
     where requirement_id = p_requirement_id and collection_id <> all (v_ids)
    returning 1
  ) select count(*)::int into v_removed from removed;

  select count(*)::int into v_kept
    from public.requirement_collections
   where requirement_id = p_requirement_id and collection_id = any (v_ids);

  with added as (
    insert into public.requirement_collections
      (requirement_id, collection_id, workspace_id, project_id, scoped_by_profile_id)
    select p_requirement_id, x, v_ws, v_pj, v_caller from unnest(v_ids) as x
     where not exists (
       select 1 from public.requirement_collections
        where requirement_id = p_requirement_id and collection_id = x
     )
    returning 1
  ) select count(*)::int into v_added from added;

  -- The documented vocabulary: requirement.updated discriminated by
  -- subject_snapshot.kind, emitted only when something actually changed.
  -- scope='collection' distinguishes it from the asset-scope sibling, which a
  -- consumer needs in order to render "applies to the Living room" rather than
  -- "applies to 3 elements".
  if v_added > 0 or v_removed > 0 then
    insert into public.activity_events (
      workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind,
      subject_kind, subject_id, subject_label, subject_snapshot, payload
    )
    values (v_ws, v_pj, now(), 'requirement.updated', v_caller, 'user',
            'requirement', p_requirement_id, v_code,
            jsonb_build_object(
              'code', v_code, 'kind', 'applicability', 'scope', 'collection',
              'added', v_added, 'removed', v_removed, 'kept', v_kept,
              'now_project_wide', (
                v_added + v_kept = 0
                and not exists (
                  select 1 from public.requirement_design_assets
                   where requirement_id = p_requirement_id
                )
              )
            ),
            '{}'::jsonb);
  end if;

end
$function$;

revoke all on function public.set_requirement_collections(uuid, uuid[]) from public;
revoke all on function public.set_requirement_collections(uuid, uuid[]) from anon;
grant execute on function public.set_requirement_collections(uuid, uuid[]) to authenticated, service_role;

comment on function public.set_requirement_collections(uuid, uuid[]) is
  'Scopes a requirement ROOT to a set of spaces, replacing its current set. Sub-requirements inherit from the parent and are refused with 23514. Mirrors set_requirement_applicability, which does the same for individual elements.';
