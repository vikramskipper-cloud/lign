-- AUTH 004 addendum: fix set_current_version event vocabulary
--
-- Changes only the event_type literal emitted by public.set_current_version
-- from the non-canonical 'asset.current_version.changed' (dotted) to the
-- EVENT_MODEL.md §4.4 canonical 'asset.current_version_changed' (underscored).
--
-- Signature, authorization, behavior, grants, SECURITY DEFINER config,
-- search_path, current-version validation, transaction GUC, and event payload
-- are preserved exactly.

create or replace function public.set_current_version(p_design_asset_id uuid, p_version_id uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_project_id uuid; v_v_asset uuid; v_v_status text; v_v_seq int; v_prev uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'set_current_version: auth required' using errcode='42501'; end if;
  if p_design_asset_id is null or p_version_id is null then
    raise exception 'set_current_version: ids required' using errcode='22004';
  end if;

  select workspace_id, project_id, current_version_id
    into v_workspace_id, v_project_id, v_prev
    from public.design_assets where id = p_design_asset_id for update;
  if v_workspace_id is null then raise exception 'set_current_version: asset not found' using errcode='23503'; end if;
  if not public.lign_has_capability(v_project_id, v_workspace_id, 'asset.set_current') then
    raise exception 'set_current_version: forbidden (asset.set_current)' using errcode='42501';
  end if;

  select design_asset_id, status, sequence into v_v_asset, v_v_status, v_v_seq
    from public.asset_versions where id = p_version_id;
  if v_v_asset is null then raise exception 'set_current_version: version not found' using errcode='23503'; end if;
  if v_v_asset <> p_design_asset_id then
    raise exception 'set_current_version: version does not belong to asset' using errcode='23514';
  end if;
  if v_v_status <> 'published' then
    raise exception 'set_current_version: version is % (must be published)', v_v_status using errcode='23514';
  end if;

  perform set_config('lign.allow_current_version_write','true', true);
  update public.design_assets set current_version_id = p_version_id where id = p_design_asset_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_workspace_id, v_project_id, now(), 'asset.current_version_changed',
    v_caller, 'user', 'design_asset', p_design_asset_id, 'v'||v_v_seq,
    jsonb_build_object('design_asset_id', p_design_asset_id, 'new_version_id', p_version_id, 'previous_version_id', v_prev, 'sequence', v_v_seq),
    '{}'::jsonb);
  return p_version_id;
end $$;
