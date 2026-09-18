create or replace function public.enforce_release_status_via_rpc()
returns trigger language plpgsql set search_path = ''
as $$
declare v_permit boolean;
begin
  if new.id is distinct from old.id then raise exception 'releases.id immutable' using errcode='23514'; end if;
  if new.workspace_id is distinct from old.workspace_id then raise exception 'releases.workspace_id immutable' using errcode='23514'; end if;
  if new.project_id is distinct from old.project_id then raise exception 'releases.project_id immutable' using errcode='23514'; end if;
  if new.created_by_profile_id is distinct from old.created_by_profile_id then raise exception 'releases.created_by_profile_id immutable' using errcode='23514'; end if;

  v_permit := coalesce(current_setting('lign.allow_release_status_write', true), '') = 'true';
  if new.status is distinct from old.status and not v_permit then
    raise exception 'releases.status may only be changed via finalize_release / withdraw_release RPC' using errcode='42501';
  end if;
  if new.released_at is distinct from old.released_at and not v_permit then
    raise exception 'releases.released_at may only be set via finalize_release RPC' using errcode='42501';
  end if;
  if new.withdrawn_at is distinct from old.withdrawn_at and not v_permit then
    raise exception 'releases.withdrawn_at may only be set via withdraw_release RPC' using errcode='42501';
  end if;
  if new.withdrawn_reason is distinct from old.withdrawn_reason and not v_permit then
    raise exception 'releases.withdrawn_reason may only be set via withdraw_release RPC' using errcode='42501';
  end if;
  return new;
end $$;
drop trigger if exists releases_status_via_rpc on public.releases;
create trigger releases_status_via_rpc before update on public.releases
  for each row execute function public.enforce_release_status_via_rpc();

create or replace function public.finalize_release(p_release_id uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_project_id uuid; v_status text; v_name text; v_channel text; v_item_count int;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'finalize_release: auth required' using errcode='42501'; end if;
  select workspace_id, project_id, status, name, channel into v_workspace_id, v_project_id, v_status, v_name, v_channel
    from public.releases where id = p_release_id for update;
  if v_workspace_id is null then raise exception 'finalize_release: release not found' using errcode='23503'; end if;
  if v_status <> 'draft' then raise exception 'finalize_release: release is % (must be draft)', v_status using errcode='23514'; end if;
  if not public.lign_has_capability(v_project_id, v_workspace_id, 'release.finalize') then
    raise exception 'finalize_release: forbidden (release.finalize)' using errcode='42501';
  end if;
  select count(*) into v_item_count from public.release_items where release_id = p_release_id;
  if v_item_count < 1 then raise exception 'finalize_release: release has no items' using errcode='23514'; end if;
  perform set_config('lign.allow_release_status_write', 'true', true);
  update public.releases set status='released', released_at=now() where id = p_release_id;
  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_workspace_id, v_project_id, now(), 'release.finalized', v_caller, 'user', 'release', p_release_id, v_name,
    jsonb_build_object('name', v_name, 'item_count', v_item_count, 'channel', v_channel), '{}'::jsonb);
  return p_release_id;
end $$;
revoke all on function public.finalize_release(uuid) from public;
revoke all on function public.finalize_release(uuid) from anon;
grant execute on function public.finalize_release(uuid) to authenticated, service_role;

create or replace function public.withdraw_release(p_release_id uuid, p_reason text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_project_id uuid; v_status text; v_name text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'withdraw_release: auth required' using errcode='42501'; end if;
  select workspace_id, project_id, status, name into v_workspace_id, v_project_id, v_status, v_name
    from public.releases where id = p_release_id for update;
  if v_workspace_id is null then raise exception 'withdraw_release: release not found' using errcode='23503'; end if;
  if v_status <> 'released' then raise exception 'withdraw_release: release is % (must be released)', v_status using errcode='23514'; end if;
  if not public.lign_has_capability(v_project_id, v_workspace_id, 'release.withdraw') then
    raise exception 'withdraw_release: forbidden (release.withdraw)' using errcode='42501';
  end if;
  perform set_config('lign.allow_release_status_write', 'true', true);
  update public.releases set status='withdrawn', withdrawn_at=now(), withdrawn_reason=p_reason where id = p_release_id;
  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_workspace_id, v_project_id, now(), 'release.withdrawn', v_caller, 'user', 'release', p_release_id, v_name,
    jsonb_build_object('reason', p_reason), '{}'::jsonb);
  return p_release_id;
end $$;
revoke all on function public.withdraw_release(uuid, text) from public;
revoke all on function public.withdraw_release(uuid, text) from anon;
grant execute on function public.withdraw_release(uuid, text) to authenticated, service_role;

drop policy if exists releases_select on public.releases;
create policy releases_select on public.releases as permissive for select to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'release.view'));

drop policy if exists releases_insert on public.releases;
create policy releases_insert on public.releases as permissive for insert to authenticated
  with check (
    public.lign_has_capability(project_id, workspace_id, 'release.create')
    and created_by_profile_id = (select auth.uid())
    and status = 'draft'
  );

drop policy if exists releases_update on public.releases;
create policy releases_update on public.releases as permissive for update to authenticated
  using      (public.lign_has_capability(project_id, workspace_id, 'release.create'))
  with check (public.lign_has_capability(project_id, workspace_id, 'release.create'));

drop policy if exists release_items_select on public.release_items;
create policy release_items_select on public.release_items as permissive for select to authenticated
  using (exists (select 1 from public.releases r where r.id = release_items.release_id
      and public.lign_has_capability(r.project_id, r.workspace_id, 'release.view')));

drop policy if exists release_items_insert on public.release_items;
create policy release_items_insert on public.release_items as permissive for insert to authenticated
  with check (exists (select 1 from public.releases r where r.id = release_items.release_id
      and public.lign_has_capability(r.project_id, r.workspace_id, 'release.create')));

drop policy if exists release_items_update on public.release_items;
create policy release_items_update on public.release_items as permissive for update to authenticated
  using (exists (select 1 from public.releases r where r.id = release_items.release_id
      and public.lign_has_capability(r.project_id, r.workspace_id, 'release.create')))
  with check (exists (select 1 from public.releases r where r.id = release_items.release_id
      and public.lign_has_capability(r.project_id, r.workspace_id, 'release.create')));

drop policy if exists release_items_delete on public.release_items;
create policy release_items_delete on public.release_items as permissive for delete to authenticated
  using (exists (select 1 from public.releases r where r.id = release_items.release_id
      and public.lign_has_capability(r.project_id, r.workspace_id, 'release.create')));