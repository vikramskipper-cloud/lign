-- AUTH 006: change_decision_rls
--
-- RLS for public.changes and public.decisions per §7 Group G.
-- Plus:
--   - lign_resolve_decision_project helper (project resolution for the 5-way
--     decision target).
--   - lign_resolve_comment_target_project update: decision-targeted comments
--     now resolve through the decision's typed target (AUTH 005 fail-closed
--     hole closed).
--   - enforce_change_transitions trigger (STATE_MACHINES.md §12 MVP: only
--     proposed → accepted|rejected|withdrawn; terminal is immutable status;
--     identity/project/asset immutable; auto-sets resolved_at on
--     accepted/rejected).
--   - emit_change_lifecycle_event trigger: canonical change.created,
--     change.accepted, change.rejected, change.withdrawn (EVENT_MODEL §4.9).
--   - emit_decision_recorded_event trigger: canonical decision.recorded
--     (EVENT_MODEL §4.10).
--
-- Not modified:
--   - Existing decisions_immutable, decisions_no_delete triggers (V1 lock).
--   - Any other function/policy/trigger.
--   - Frozen architecture docs.
--
-- Deferred (not required for AUTH 006 to function):
--   - supersede_decision RPC for setting supersedes_decision_id after
--     creation. Supersession at INSERT time works (immutability trigger
--     only guards UPDATE, not INSERT). No UPDATE policy on decisions
--     means client-side mid-life supersession is not enabled in MVP.

------------------------------------------------------------------------------
-- 1. lign_resolve_decision_project — NEW helper (DEFINER)
------------------------------------------------------------------------------

create or replace function public.lign_resolve_decision_project(
  p_target_design_asset_id     uuid,
  p_target_version_id          uuid,
  p_target_review_id           uuid,
  p_target_change_id           uuid,
  p_target_approval_request_id uuid
)
returns uuid
language sql
stable
parallel safe
security definer
set search_path = ''
as $$
  select case
    when p_target_version_id is not null then
      (select project_id from public.asset_versions where id = p_target_version_id)
    when p_target_review_id is not null then
      (select project_id from public.reviews where id = p_target_review_id)
    when p_target_change_id is not null then
      (select project_id from public.changes where id = p_target_change_id)
    when p_target_design_asset_id is not null then
      (select project_id from public.design_assets where id = p_target_design_asset_id)
    when p_target_approval_request_id is not null then
      (select project_id from public.approval_requests where id = p_target_approval_request_id)
    else null
  end;
$$;

comment on function public.lign_resolve_decision_project(uuid,uuid,uuid,uuid,uuid) is
  'Resolves the project_id from a decision''s 5-way typed target. All 5 target kinds are project-scoped. SECURITY DEFINER bypasses target-table RLS.';

revoke all on function public.lign_resolve_decision_project(uuid,uuid,uuid,uuid,uuid) from public;
revoke all on function public.lign_resolve_decision_project(uuid,uuid,uuid,uuid,uuid) from anon;
grant execute on function public.lign_resolve_decision_project(uuid,uuid,uuid,uuid,uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 2. lign_resolve_comment_target_project — UPDATED
------------------------------------------------------------------------------
-- Only change: decision-target case now resolves via lign_resolve_decision_project.
-- No signature change; no other target-kind semantics changed.

create or replace function public.lign_resolve_comment_target_project(
  p_target_version_id          uuid,
  p_target_review_id           uuid,
  p_target_annotation_id       uuid,
  p_target_change_id           uuid,
  p_target_decision_id         uuid,
  p_target_design_asset_id     uuid,
  p_target_approval_request_id uuid
)
returns uuid
language sql
stable
parallel safe
security definer
set search_path = ''
as $$
  select case
    when p_target_version_id is not null then
      (select project_id from public.asset_versions where id = p_target_version_id)
    when p_target_review_id is not null then
      (select project_id from public.reviews where id = p_target_review_id)
    when p_target_annotation_id is not null then
      (select av.project_id
         from public.annotations a
         join public.asset_versions av on av.id = a.asset_version_id
        where a.id = p_target_annotation_id)
    when p_target_change_id is not null then
      (select project_id from public.changes where id = p_target_change_id)
    when p_target_design_asset_id is not null then
      (select project_id from public.design_assets where id = p_target_design_asset_id)
    when p_target_approval_request_id is not null then
      (select project_id from public.approval_requests where id = p_target_approval_request_id)
    when p_target_decision_id is not null then
      (select public.lign_resolve_decision_project(
        d.target_design_asset_id, d.target_version_id, d.target_review_id,
        d.target_change_id, d.target_approval_request_id)
       from public.decisions d where d.id = p_target_decision_id)
    else null
  end;
$$;

------------------------------------------------------------------------------
-- 3. enforce_change_transitions — BEFORE UPDATE trigger on changes
------------------------------------------------------------------------------
-- - Blocks id/workspace_id/project_id/design_asset_id/created_by_profile_id
--   mutation (immutable identity/scope).
-- - Terminal states (accepted, rejected, withdrawn) are status-immutable but
--   allow other field updates (e.g., linking to_version_id on accepted per
--   STATE_MACHINES §12 D6).
-- - From proposed: only proposed → accepted|rejected|withdrawn.
-- - under_review / implemented are reserved (MVP does not use them).
-- - Auto-sets resolved_at when transitioning to accepted/rejected if unset.

create or replace function public.enforce_change_transitions()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id is distinct from old.id then
    raise exception 'changes.id is immutable' using errcode='23514';
  end if;
  if new.workspace_id is distinct from old.workspace_id then
    raise exception 'changes.workspace_id is immutable' using errcode='23514';
  end if;
  if new.project_id is distinct from old.project_id then
    raise exception 'changes.project_id is immutable' using errcode='23514';
  end if;
  if new.design_asset_id is distinct from old.design_asset_id then
    raise exception 'changes.design_asset_id is immutable' using errcode='23514';
  end if;
  if new.created_by_profile_id is distinct from old.created_by_profile_id then
    raise exception 'changes.created_by_profile_id is immutable' using errcode='23514';
  end if;

  if old.status in ('accepted','rejected','withdrawn') then
    if new.status is distinct from old.status then
      raise exception 'changes.status: cannot transition from terminal state %', old.status
        using errcode='23514';
    end if;
    return new;
  end if;

  if old.status = 'proposed' then
    if new.status not in ('proposed','accepted','rejected','withdrawn') then
      raise exception 'changes.status: invalid transition proposed → %', new.status
        using errcode='23514';
    end if;
    if new.status in ('accepted','rejected') and new.resolved_at is null then
      new.resolved_at := now();
    end if;
    return new;
  end if;

  raise exception 'changes.status: state % is reserved and not supported in MVP', old.status
    using errcode='23514';
end $$;

drop trigger if exists changes_enforce_transitions on public.changes;
create trigger changes_enforce_transitions
  before update on public.changes
  for each row execute function public.enforce_change_transitions();

------------------------------------------------------------------------------
-- 4. emit_change_lifecycle_event — AFTER INSERT/UPDATE trigger on changes
------------------------------------------------------------------------------
-- Emits canonical events from EVENT_MODEL §4.9 vocabulary:
--   INSERT (∅ → proposed)   → change.created
--   UPDATE (proposed → accepted|rejected|withdrawn) → change.accepted/rejected/withdrawn

create or replace function public.emit_change_lifecycle_event()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_caller uuid;
  v_event  text;
begin
  v_caller := auth.uid();

  if tg_op = 'INSERT' then
    insert into public.activity_events (
      workspace_id, project_id, occurred_at, event_type,
      actor_profile_id, actor_kind,
      subject_kind, subject_id, subject_label, subject_snapshot, payload
    ) values (
      new.workspace_id, new.project_id, now(), 'change.created',
      v_caller, case when v_caller is null then 'system' else 'user' end,
      'change', new.id, new.title,
      jsonb_build_object('asset_id', new.design_asset_id, 'title', new.title),
      '{}'::jsonb
    );
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.status = 'proposed'
     and new.status in ('accepted','rejected','withdrawn')
  then
    v_event := 'change.' || new.status;
    insert into public.activity_events (
      workspace_id, project_id, occurred_at, event_type,
      actor_profile_id, actor_kind,
      subject_kind, subject_id, subject_label, subject_snapshot, payload
    ) values (
      new.workspace_id, new.project_id, now(), v_event,
      v_caller, case when v_caller is null then 'system' else 'user' end,
      'change', new.id, new.title,
      case when new.status = 'accepted'
        then jsonb_build_object('title', new.title, 'to_version_id', new.to_version_id)
        else jsonb_build_object('title', new.title)
      end,
      '{}'::jsonb
    );
    return new;
  end if;

  return new;
end $$;

drop trigger if exists changes_lifecycle_events on public.changes;
create trigger changes_lifecycle_events
  after insert or update on public.changes
  for each row execute function public.emit_change_lifecycle_event();

------------------------------------------------------------------------------
-- 5. emit_decision_recorded_event — AFTER INSERT trigger on decisions
------------------------------------------------------------------------------
-- Emits canonical decision.recorded per EVENT_MODEL §4.10. The event's
-- project scope is derived from the decision's typed target.

create or replace function public.emit_decision_recorded_event()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_caller      uuid;
  v_project_id  uuid;
  v_target_kind text;
  v_target_id   uuid;
begin
  v_caller := auth.uid();
  v_project_id := public.lign_resolve_decision_project(
    new.target_design_asset_id, new.target_version_id, new.target_review_id,
    new.target_change_id, new.target_approval_request_id);

  v_target_kind := case
    when new.target_design_asset_id     is not null then 'design_asset'
    when new.target_version_id          is not null then 'asset_version'
    when new.target_review_id           is not null then 'review'
    when new.target_change_id           is not null then 'change'
    when new.target_approval_request_id is not null then 'approval_request'
  end;
  v_target_id := coalesce(
    new.target_design_asset_id, new.target_version_id, new.target_review_id,
    new.target_change_id, new.target_approval_request_id);

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    new.workspace_id, v_project_id, now(), 'decision.recorded',
    v_caller, case when v_caller is null then 'system' else 'user' end,
    'decision', new.id, new.title,
    jsonb_build_object('title', new.title, 'target_kind', v_target_kind, 'target_id', v_target_id),
    '{}'::jsonb
  );

  return new;
end $$;

drop trigger if exists decisions_recorded_event on public.decisions;
create trigger decisions_recorded_event
  after insert on public.decisions
  for each row execute function public.emit_decision_recorded_event();

------------------------------------------------------------------------------
-- 6. changes policies
------------------------------------------------------------------------------

drop policy if exists changes_select on public.changes;
create policy changes_select on public.changes
  as permissive for select to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'change.view'));

drop policy if exists changes_insert on public.changes;
create policy changes_insert on public.changes
  as permissive for insert to authenticated
  with check (
    public.lign_has_capability(project_id, workspace_id, 'change.create')
    and created_by_profile_id = (select auth.uid())
  );

drop policy if exists changes_update on public.changes;
create policy changes_update on public.changes
  as permissive for update to authenticated
  using      (public.lign_has_capability(project_id, workspace_id, 'change.resolve'))
  with check (public.lign_has_capability(project_id, workspace_id, 'change.resolve'));

-- No DELETE policy.

------------------------------------------------------------------------------
-- 7. decisions policies
------------------------------------------------------------------------------

drop policy if exists decisions_select on public.decisions;
create policy decisions_select on public.decisions
  as permissive for select to authenticated
  using (
    public.lign_has_capability(
      public.lign_resolve_decision_project(
        target_design_asset_id, target_version_id, target_review_id,
        target_change_id, target_approval_request_id),
      workspace_id,
      'decision.view'
    )
  );

drop policy if exists decisions_insert on public.decisions;
create policy decisions_insert on public.decisions
  as permissive for insert to authenticated
  with check (
    author_profile_id = (select auth.uid())
    and public.lign_has_capability(
      public.lign_resolve_decision_project(
        target_design_asset_id, target_version_id, target_review_id,
        target_change_id, target_approval_request_id),
      workspace_id,
      'decision.create'
    )
  );

-- No UPDATE policy: existing decisions_immutable trigger enforces content
-- immutability but the RLS gate means direct client UPDATE has no path.
-- Supersession at INSERT time is supported via supersedes_decision_id column;
-- mid-life supersession requires a future RPC (out of AUTH 006 scope).
-- No DELETE policy: existing decisions_no_delete trigger is belt-and-suspenders.
