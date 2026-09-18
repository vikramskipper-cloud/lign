-- AUTH 006 apply

create or replace function public.lign_resolve_decision_project(
  p_target_design_asset_id uuid, p_target_version_id uuid, p_target_review_id uuid,
  p_target_change_id uuid, p_target_approval_request_id uuid
) returns uuid language sql stable parallel safe security definer set search_path = ''
as $$
  select case
    when p_target_version_id is not null then (select project_id from public.asset_versions where id = p_target_version_id)
    when p_target_review_id is not null then (select project_id from public.reviews where id = p_target_review_id)
    when p_target_change_id is not null then (select project_id from public.changes where id = p_target_change_id)
    when p_target_design_asset_id is not null then (select project_id from public.design_assets where id = p_target_design_asset_id)
    when p_target_approval_request_id is not null then (select project_id from public.approval_requests where id = p_target_approval_request_id)
    else null
  end;
$$;
revoke all on function public.lign_resolve_decision_project(uuid,uuid,uuid,uuid,uuid) from public;
revoke all on function public.lign_resolve_decision_project(uuid,uuid,uuid,uuid,uuid) from anon;
grant execute on function public.lign_resolve_decision_project(uuid,uuid,uuid,uuid,uuid) to authenticated, service_role;

create or replace function public.lign_resolve_comment_target_project(
  p_target_version_id uuid, p_target_review_id uuid, p_target_annotation_id uuid,
  p_target_change_id uuid, p_target_decision_id uuid,
  p_target_design_asset_id uuid, p_target_approval_request_id uuid
) returns uuid language sql stable parallel safe security definer set search_path = ''
as $$
  select case
    when p_target_version_id is not null then (select project_id from public.asset_versions where id = p_target_version_id)
    when p_target_review_id is not null then (select project_id from public.reviews where id = p_target_review_id)
    when p_target_annotation_id is not null then
      (select av.project_id from public.annotations a join public.asset_versions av on av.id = a.asset_version_id where a.id = p_target_annotation_id)
    when p_target_change_id is not null then (select project_id from public.changes where id = p_target_change_id)
    when p_target_design_asset_id is not null then (select project_id from public.design_assets where id = p_target_design_asset_id)
    when p_target_approval_request_id is not null then (select project_id from public.approval_requests where id = p_target_approval_request_id)
    when p_target_decision_id is not null then (
      select public.lign_resolve_decision_project(
        d.target_design_asset_id, d.target_version_id, d.target_review_id,
        d.target_change_id, d.target_approval_request_id)
      from public.decisions d where d.id = p_target_decision_id
    )
    else null
  end;
$$;

create or replace function public.enforce_change_transitions()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.id is distinct from old.id then raise exception 'changes.id immutable' using errcode='23514'; end if;
  if new.workspace_id is distinct from old.workspace_id then raise exception 'changes.workspace_id immutable' using errcode='23514'; end if;
  if new.project_id is distinct from old.project_id then raise exception 'changes.project_id immutable' using errcode='23514'; end if;
  if new.design_asset_id is distinct from old.design_asset_id then raise exception 'changes.design_asset_id immutable' using errcode='23514'; end if;
  if new.created_by_profile_id is distinct from old.created_by_profile_id then raise exception 'changes.created_by_profile_id immutable' using errcode='23514'; end if;

  if old.status in ('accepted','rejected','withdrawn') then
    if new.status is distinct from old.status then
      raise exception 'changes.status: cannot transition from terminal state %', old.status using errcode='23514';
    end if;
    return new;
  end if;

  if old.status = 'proposed' then
    if new.status not in ('proposed','accepted','rejected','withdrawn') then
      raise exception 'changes.status: invalid transition proposed → %', new.status using errcode='23514';
    end if;
    if new.status in ('accepted','rejected') and new.resolved_at is null then
      new.resolved_at := now();
    end if;
    return new;
  end if;

  raise exception 'changes.status: state % is reserved and not supported in MVP', old.status using errcode='23514';
end $$;
drop trigger if exists changes_enforce_transitions on public.changes;
create trigger changes_enforce_transitions
  before update on public.changes
  for each row execute function public.enforce_change_transitions();

create or replace function public.emit_change_lifecycle_event()
returns trigger language plpgsql set search_path = ''
as $$
declare v_caller uuid; v_event text;
begin
  v_caller := auth.uid();
  if tg_op = 'INSERT' then
    insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
    values (new.workspace_id, new.project_id, now(), 'change.created',
      v_caller, case when v_caller is null then 'system' else 'user' end,
      'change', new.id, new.title,
      jsonb_build_object('asset_id', new.design_asset_id, 'title', new.title), '{}'::jsonb);
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status='proposed' and new.status in ('accepted','rejected','withdrawn') then
    v_event := 'change.' || new.status;
    insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
    values (new.workspace_id, new.project_id, now(), v_event,
      v_caller, case when v_caller is null then 'system' else 'user' end,
      'change', new.id, new.title,
      case when new.status='accepted' then jsonb_build_object('title', new.title, 'to_version_id', new.to_version_id) else jsonb_build_object('title', new.title) end,
      '{}'::jsonb);
    return new;
  end if;
  return new;
end $$;
drop trigger if exists changes_lifecycle_events on public.changes;
create trigger changes_lifecycle_events
  after insert or update on public.changes
  for each row execute function public.emit_change_lifecycle_event();

create or replace function public.emit_decision_recorded_event()
returns trigger language plpgsql set search_path = ''
as $$
declare v_caller uuid; v_project_id uuid; v_target_kind text; v_target_id uuid;
begin
  v_caller := auth.uid();
  v_project_id := public.lign_resolve_decision_project(
    new.target_design_asset_id, new.target_version_id, new.target_review_id,
    new.target_change_id, new.target_approval_request_id);
  v_target_kind := case
    when new.target_design_asset_id is not null then 'design_asset'
    when new.target_version_id is not null then 'asset_version'
    when new.target_review_id is not null then 'review'
    when new.target_change_id is not null then 'change'
    when new.target_approval_request_id is not null then 'approval_request'
  end;
  v_target_id := coalesce(new.target_design_asset_id, new.target_version_id, new.target_review_id, new.target_change_id, new.target_approval_request_id);
  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (new.workspace_id, v_project_id, now(), 'decision.recorded',
    v_caller, case when v_caller is null then 'system' else 'user' end,
    'decision', new.id, new.title,
    jsonb_build_object('title', new.title, 'target_kind', v_target_kind, 'target_id', v_target_id),
    '{}'::jsonb);
  return new;
end $$;
drop trigger if exists decisions_recorded_event on public.decisions;
create trigger decisions_recorded_event
  after insert on public.decisions
  for each row execute function public.emit_decision_recorded_event();

drop policy if exists changes_select on public.changes;
create policy changes_select on public.changes as permissive for select to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'change.view'));

drop policy if exists changes_insert on public.changes;
create policy changes_insert on public.changes as permissive for insert to authenticated
  with check (
    public.lign_has_capability(project_id, workspace_id, 'change.create')
    and created_by_profile_id = (select auth.uid())
  );

drop policy if exists changes_update on public.changes;
create policy changes_update on public.changes as permissive for update to authenticated
  using      (public.lign_has_capability(project_id, workspace_id, 'change.resolve'))
  with check (public.lign_has_capability(project_id, workspace_id, 'change.resolve'));

drop policy if exists decisions_select on public.decisions;
create policy decisions_select on public.decisions as permissive for select to authenticated
  using (
    public.lign_has_capability(
      public.lign_resolve_decision_project(target_design_asset_id, target_version_id, target_review_id, target_change_id, target_approval_request_id),
      workspace_id, 'decision.view')
  );

drop policy if exists decisions_insert on public.decisions;
create policy decisions_insert on public.decisions as permissive for insert to authenticated
  with check (
    author_profile_id = (select auth.uid())
    and public.lign_has_capability(
      public.lign_resolve_decision_project(target_design_asset_id, target_version_id, target_review_id, target_change_id, target_approval_request_id),
      workspace_id, 'decision.create')
  );