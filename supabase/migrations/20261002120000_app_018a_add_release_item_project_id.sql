-- APP 018a — add_release_item never supplied project_id.
--
-- Found by walking the post-creation flow as an actual project lead under a
-- real JWT, rather than by reading the code.
--
-- release_items.project_id is NOT NULL and the insert never supplied it: the
-- column list named seven columns and that was not one of them, so EVERY call
-- died on 23502. A release could be drafted, named and published, but no
-- version could ever be put inside one — and a release is what a client is
-- finally issued, so the end of the loop was unreachable. Pre-existing since
-- APP 009.
--
-- The fix is one column. v_pj was already selected from the parent release and
-- already used twice below — for the capability check and for the activity
-- event. It simply never reached the insert. Nothing else changes.

create or replace function public.add_release_item(
  p_release_id      uuid,
  p_design_asset_id uuid,
  p_version_id      uuid,
  p_notes           text    default null,
  p_sort_order      integer default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_caller uuid; v_ws uuid; v_pj uuid; v_status text; v_release_type text;
  v_item_id uuid; v_sort int; v_asset_name text; v_ver_seq int;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'add_release_item: authentication required' using errcode='42501';
  end if;
  select workspace_id, project_id, status, release_type
    into v_ws, v_pj, v_status, v_release_type
    from public.releases where id = p_release_id for update;
  if v_ws is null then
    raise exception 'add_release_item: release not found' using errcode='23503';
  end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.create') then
    raise exception 'add_release_item: forbidden (release.create)' using errcode='42501';
  end if;
  if v_status <> 'draft' then
    raise exception 'add_release_item: parent release is % (must be draft)', v_status using errcode='23514';
  end if;

  if p_sort_order is null then
    select coalesce(max(sort_order), 0) + 1 into v_sort
      from public.release_items where release_id = p_release_id;
  else
    v_sort := p_sort_order;
  end if;

  v_item_id := gen_random_uuid();
  -- project_id added. It was the only omission; v_pj has been in scope from the
  -- select above since APP 009 and was already used twice below.
  insert into public.release_items (
    id, workspace_id, project_id, release_id, design_asset_id, version_id, sort_order, notes
  ) values (
    v_item_id, v_ws, v_pj, p_release_id, p_design_asset_id, p_version_id, v_sort, p_notes
  );

  select name into v_asset_name from public.design_assets where id = p_design_asset_id;
  select sequence into v_ver_seq from public.asset_versions where id = p_version_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_pj, now(), 'release.item_added',
    v_caller, 'user', 'release_item', v_item_id, v_asset_name,
    jsonb_build_object(
      'release_id', p_release_id, 'asset_id', p_design_asset_id, 'asset_name', v_asset_name,
      'version_id', p_version_id, 'version_sequence', v_ver_seq, 'release_type', v_release_type,
      'item_id', v_item_id, 'sort_order', v_sort,
      'notes_snippet', case when p_notes is null then null else substr(p_notes,1,200) end
    ),
    '{}'::jsonb
  );
  return v_item_id;
end $function$;