-- AUTH 006 addendum: elevate event-emitting trigger functions to
-- SECURITY DEFINER so their INSERTs into public.activity_events do not hit
-- the caller's RLS (activity_events has RLS enabled with no INSERT policy
-- for authenticated — writes are intentionally trigger-only). auth.uid()
-- still resolves to the calling user inside a SECURITY DEFINER function.
--
-- No signature change, no behavioral change beyond the security context.

create or replace function public.emit_change_lifecycle_event()
returns trigger language plpgsql
security definer
set search_path = ''
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
revoke all on function public.emit_change_lifecycle_event() from public;
revoke all on function public.emit_change_lifecycle_event() from anon;

create or replace function public.emit_decision_recorded_event()
returns trigger language plpgsql
security definer
set search_path = ''
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
revoke all on function public.emit_decision_recorded_event() from public;
revoke all on function public.emit_decision_recorded_event() from anon;
