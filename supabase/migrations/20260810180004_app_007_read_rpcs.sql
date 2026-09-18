
------------------------------------------------------------------------------
-- 1. list_approvals_dashboard — paginated dashboard read
------------------------------------------------------------------------------

create or replace function public.list_approvals_dashboard(
  p_ws_id                   uuid,
  p_proj_id                 uuid    default null,
  p_view                    text    default 'recent',
  p_status_filter           text[]  default null,
  p_policy_filter           text[]  default null,
  p_requester_ids           uuid[]  default null,
  p_approver_profile_ids    uuid[]  default null,
  p_cursor_updated_at       timestamptz default null,
  p_cursor_id               uuid    default null,
  p_limit                   integer default 30
)
returns table (
  out_id                          uuid,
  out_workspace_id                uuid,
  out_project_id                  uuid,
  out_design_asset_id             uuid,
  out_version_id                  uuid,
  out_title                       text,
  out_description                 text,
  out_status                      text,
  out_policy                      text,
  out_quorum_min                  integer,
  out_root_approval_request_id    uuid,
  out_supersedes_approval_request_id uuid,
  out_related_review_id           uuid,
  out_created_by_profile_id       uuid,
  out_due_at                      timestamptz,
  out_expires_at                  timestamptz,
  out_sent_at                     timestamptz,
  out_outcome_at                  timestamptz,
  out_created_at                  timestamptz,
  out_updated_at                  timestamptz,
  out_pending_count               integer,
  out_approved_count              integer,
  out_rejected_count              integer,
  out_abstained_count             integer,
  out_total_approver_count        integer,
  out_has_veto_approver           boolean,
  out_overdue_flag                boolean,
  out_my_slot_status              text
)
language plpgsql security definer set search_path = '' stable
as $$
declare v_caller uuid; v_lim int;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'list_approvals_dashboard: authentication required' using errcode='42501'; end if;
  if p_ws_id is null then raise exception 'list_approvals_dashboard: ws_id required' using errcode='22004'; end if;
  v_lim := greatest(1, least(coalesce(p_limit, 30), 100));

  return query
    with visible as (
      select ar.*
        from public.approval_requests ar
       where ar.workspace_id = p_ws_id
         and (p_proj_id is null or ar.project_id = p_proj_id)
         and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
    ),
    filtered as (
      select v.*
        from visible v
       where (p_status_filter is null or v.status = any(p_status_filter))
         and (p_policy_filter is null or v.policy = any(p_policy_filter))
         and (p_requester_ids is null or v.created_by_profile_id = any(p_requester_ids))
         and (
           p_approver_profile_ids is null
           or exists (
             select 1 from public.approval_request_approvers a
              left join public.workspace_members wm on wm.id = a.workspace_member_id
              left join public.stakeholders sh on sh.id = a.stakeholder_id
              where a.approval_request_id = v.id
                and a.removed_at is null
                and coalesce(wm.user_id, sh.user_id) = any(p_approver_profile_ids)
           )
         )
         and case p_view
           when 'awaiting_me' then exists (
             select 1 from public.approval_request_approvers a
              left join public.workspace_members wm on wm.id = a.workspace_member_id
              left join public.stakeholders sh on sh.id = a.stakeholder_id
              left join public.approval_responses r on r.approver_slot_id = a.id
              where a.approval_request_id = v.id
                and a.removed_at is null
                and r.id is null
                and coalesce(wm.user_id, sh.user_id) = v_caller
           ) and v.status in ('pending','in_progress')
           when 'awaiting_others' then v.created_by_profile_id = v_caller
                                        and v.status in ('pending','in_progress')
           when 'approved' then v.status = 'approved'
           when 'rejected' then v.status = 'rejected'
           when 'expired_cancelled' then v.status in ('expired','cancelled')
           when 'bookmarks' then exists (
             select 1 from public.user_bookmarks b
              where b.user_id = v_caller
                and b.subject_kind = 'approval_request'
                and b.subject_id = v.id
           )
           else true
         end
    )
    select
      f.id, f.workspace_id, f.project_id, f.design_asset_id, f.version_id,
      f.title, f.description, f.status, f.policy, f.quorum_min,
      f.root_approval_request_id, f.supersedes_approval_request_id, f.related_review_id,
      f.created_by_profile_id,
      f.due_at, f.expires_at, f.sent_at, f.outcome_at,
      f.created_at, f.updated_at,
      (select count(*)::int from public.approval_request_approvers a
        left join public.approval_responses r on r.approver_slot_id = a.id
        where a.approval_request_id = f.id and a.removed_at is null and r.id is null),
      (select count(*)::int from public.approval_responses r
        where r.approval_request_id = f.id and r.decision = 'approved'),
      (select count(*)::int from public.approval_responses r
        where r.approval_request_id = f.id and r.decision = 'rejected'),
      (select count(*)::int from public.approval_responses r
        where r.approval_request_id = f.id and r.decision = 'abstained'),
      (select count(*)::int from public.approval_request_approvers a
        where a.approval_request_id = f.id and a.removed_at is null),
      (select exists (select 1 from public.approval_request_approvers a
        where a.approval_request_id = f.id and a.removed_at is null and a.veto_power = true)),
      (f.expires_at is not null and f.expires_at < now() and f.status in ('pending','in_progress')),
      (select r.decision from public.approval_request_approvers a
        left join public.workspace_members wm on wm.id = a.workspace_member_id
        left join public.stakeholders sh on sh.id = a.stakeholder_id
        left join public.approval_responses r on r.approver_slot_id = a.id
        where a.approval_request_id = f.id and a.removed_at is null
          and coalesce(wm.user_id, sh.user_id) = v_caller
        limit 1)
    from filtered f
    where (p_cursor_updated_at is null
           or (f.updated_at, f.id) < (p_cursor_updated_at, p_cursor_id))
    order by f.updated_at desc, f.id desc
    limit v_lim;
end $$;

revoke all on function public.list_approvals_dashboard(uuid,uuid,text,text[],text[],uuid[],uuid[],timestamptz,uuid,integer) from public;
revoke all on function public.list_approvals_dashboard(uuid,uuid,text,text[],text[],uuid[],uuid[],timestamptz,uuid,integer) from anon;
revoke all on function public.list_approvals_dashboard(uuid,uuid,text,text[],text[],uuid[],uuid[],timestamptz,uuid,integer) from authenticated;
grant execute on function public.list_approvals_dashboard(uuid,uuid,text,text[],text[],uuid[],uuid[],timestamptz,uuid,integer) to authenticated, service_role;

------------------------------------------------------------------------------
-- 2. get_approval — full Approval Detail read
------------------------------------------------------------------------------

create or replace function public.get_approval(p_approval_request_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' stable
as $$
declare
  v_caller uuid;
  v_ws uuid; v_proj uuid;
  v_row jsonb; v_slots jsonb; v_responses jsonb; v_metrics jsonb; v_chain jsonb;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_approval: authentication required' using errcode='42501'; end if;

  select workspace_id, project_id into v_ws, v_proj
    from public.approval_requests where id = p_approval_request_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(v_proj, v_ws, 'approval.view') then
    raise exception 'get_approval: forbidden (approval.view)' using errcode='42501';
  end if;

  select to_jsonb(ar) into v_row from public.approval_requests ar where ar.id = p_approval_request_id;

  select coalesce(jsonb_agg(row_to_jsonb(x) order by x.sort_order asc, x.created_at asc), '[]'::jsonb) into v_slots
  from (
    select a.id, a.workspace_member_id, a.stakeholder_id,
           a.required, a.veto_power, a.sort_order,
           a.removed_at, a.removed_reason,
           a.created_at, a.updated_at,
           coalesce(wm_p.display_name, sh_p.display_name, sh.display_name) as display_name,
           coalesce(wm_p.avatar_url, sh_p.avatar_url) as avatar_url,
           coalesce(wm.user_id, sh.user_id) as profile_id,
           case when a.workspace_member_id is not null then 'member' else 'stakeholder' end as identity,
           (select jsonb_build_object(
              'id', r.id,
              'decision', r.decision,
              'comment', r.comment,
              'responded_at', r.responded_at,
              'is_veto_cast', r.is_veto_cast
            ) from public.approval_responses r where r.approver_slot_id = a.id) as response
      from public.approval_request_approvers a
      left join public.workspace_members wm on wm.id = a.workspace_member_id
      left join public.stakeholders sh on sh.id = a.stakeholder_id
      left join public.profiles wm_p on wm_p.id = wm.user_id
      left join public.profiles sh_p on sh_p.id = sh.user_id
     where a.approval_request_id = p_approval_request_id
  ) x;

  select coalesce(jsonb_agg(row_to_jsonb(y) order by y.responded_at asc), '[]'::jsonb) into v_responses
  from (
    select r.id, r.approver_slot_id, r.responder_profile_id,
           r.decision, r.comment, r.responded_at, r.is_veto_cast,
           r.decision_metadata
      from public.approval_responses r
     where r.approval_request_id = p_approval_request_id
  ) y;

  v_metrics := jsonb_build_object(
    'response_distribution', (
      select jsonb_build_object(
        'approved',  count(*) filter (where decision='approved'),
        'rejected',  count(*) filter (where decision='rejected'),
        'abstained', count(*) filter (where decision='abstained'),
        'pending',   (select count(*) from public.approval_request_approvers a
                       left join public.approval_responses rr on rr.approver_slot_id = a.id
                       where a.approval_request_id = p_approval_request_id
                         and a.removed_at is null and rr.id is null)
      ) from public.approval_responses where approval_request_id = p_approval_request_id
    ),
    'has_veto_cast', (
      select exists (select 1 from public.approval_responses
        where approval_request_id = p_approval_request_id and is_veto_cast = true)
    ),
    'time_to_first_response', (
      select extract(epoch from (min(r.responded_at) - ar.sent_at))
        from public.approval_responses r
        cross join lateral (select sent_at from public.approval_requests where id = p_approval_request_id) ar
       where r.approval_request_id = p_approval_request_id
    ),
    'time_to_outcome', (
      select extract(epoch from (ar.outcome_at - ar.sent_at))
        from public.approval_requests ar where ar.id = p_approval_request_id
    )
  );

  select jsonb_build_object(
    'root_approval_request_id', (v_row->>'root_approval_request_id')::uuid,
    'is_latest', not exists (
      select 1 from public.approval_requests a2
       where a2.supersedes_approval_request_id = p_approval_request_id
    ),
    'prior_request_id', (v_row->>'supersedes_approval_request_id')::uuid,
    'next_request_id', (
      select a2.id from public.approval_requests a2
       where a2.supersedes_approval_request_id = p_approval_request_id
       limit 1
    )
  ) into v_chain;

  return jsonb_build_object(
    'request', v_row,
    'slots', v_slots,
    'responses', v_responses,
    'metrics', v_metrics,
    'chain_position', v_chain
  );
end $$;

revoke all on function public.get_approval(uuid) from public;
revoke all on function public.get_approval(uuid) from anon;
revoke all on function public.get_approval(uuid) from authenticated;
grant execute on function public.get_approval(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 3. get_approval_chain
------------------------------------------------------------------------------

create or replace function public.get_approval_chain(p_root_approval_request_id uuid)
returns table (
  out_id                uuid,
  out_status            text,
  out_title             text,
  out_policy            text,
  out_supersedes_approval_request_id uuid,
  out_created_at        timestamptz,
  out_outcome_at        timestamptz,
  out_approved_count    integer,
  out_rejected_count    integer,
  out_total_count       integer
)
language plpgsql security definer set search_path = '' stable
as $$
declare v_caller uuid; v_ws uuid; v_proj uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_approval_chain: authentication required' using errcode='42501'; end if;

  select workspace_id, project_id into v_ws, v_proj
    from public.approval_requests where id = p_root_approval_request_id;
  if v_ws is null then return; end if;
  if not public.lign_has_capability(v_proj, v_ws, 'approval.view') then
    raise exception 'get_approval_chain: forbidden (approval.view)' using errcode='42501';
  end if;

  return query
    select ar.id, ar.status, ar.title, ar.policy,
           ar.supersedes_approval_request_id,
           ar.created_at, ar.outcome_at,
           (select count(*)::int from public.approval_responses r
             where r.approval_request_id = ar.id and r.decision='approved'),
           (select count(*)::int from public.approval_responses r
             where r.approval_request_id = ar.id and r.decision='rejected'),
           (select count(*)::int from public.approval_request_approvers a
             where a.approval_request_id = ar.id and a.removed_at is null)
      from public.approval_requests ar
     where ar.root_approval_request_id = p_root_approval_request_id
        or ar.id = p_root_approval_request_id
     order by ar.created_at asc;
end $$;

revoke all on function public.get_approval_chain(uuid) from public;
revoke all on function public.get_approval_chain(uuid) from anon;
revoke all on function public.get_approval_chain(uuid) from authenticated;
grant execute on function public.get_approval_chain(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 4. list_approvals_for_version
------------------------------------------------------------------------------

create or replace function public.list_approvals_for_version(p_version_id uuid)
returns table (
  out_id           uuid,
  out_title        text,
  out_status       text,
  out_policy       text,
  out_created_by_profile_id uuid,
  out_created_at   timestamptz,
  out_outcome_at   timestamptz,
  out_expires_at   timestamptz
)
language plpgsql security definer set search_path = '' stable
as $$
declare v_caller uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'list_approvals_for_version: authentication required' using errcode='42501'; end if;

  return query
    select ar.id, ar.title, ar.status, ar.policy,
           ar.created_by_profile_id, ar.created_at, ar.outcome_at, ar.expires_at
      from public.approval_requests ar
     where ar.version_id = p_version_id
       and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
     order by ar.outcome_at desc nulls first, ar.created_at desc;
end $$;

revoke all on function public.list_approvals_for_version(uuid) from public;
revoke all on function public.list_approvals_for_version(uuid) from anon;
revoke all on function public.list_approvals_for_version(uuid) from authenticated;
grant execute on function public.list_approvals_for_version(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 5. get_approval_readiness — F-3.3 reconciled shape
------------------------------------------------------------------------------

create or replace function public.get_approval_readiness(p_version_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' stable
as $$
declare
  v_caller uuid;
  v_has_approved boolean := false;
  v_latest jsonb := null;
  v_blocking uuid[];
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_approval_readiness: authentication required' using errcode='42501'; end if;

  select exists (
    select 1 from public.approval_requests ar
     where ar.version_id = p_version_id and ar.status = 'approved'
       and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
  ) into v_has_approved;

  select jsonb_build_object(
      'status',      ar.status,
      'outcome_at',  ar.outcome_at,
      'request_id',  ar.id
    ) into v_latest
    from public.approval_requests ar
   where ar.version_id = p_version_id
     and ar.outcome_at is not null
     and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
   order by ar.outcome_at desc
   limit 1;

  select coalesce(array_agg(ar.id), '{}'::uuid[]) into v_blocking
    from public.approval_requests ar
   where ar.version_id = p_version_id
     and ar.status in ('pending','in_progress','rejected')
     and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view');

  return jsonb_build_object(
    'has_approved', v_has_approved,
    'latest_outcome', v_latest,
    'blocking_requests', to_jsonb(v_blocking)
  );
end $$;

revoke all on function public.get_approval_readiness(uuid) from public;
revoke all on function public.get_approval_readiness(uuid) from anon;
revoke all on function public.get_approval_readiness(uuid) from authenticated;
grant execute on function public.get_approval_readiness(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 6. get_approval_inbox_count
------------------------------------------------------------------------------

create or replace function public.get_approval_inbox_count(p_ws_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' stable
as $$
declare v_caller uuid; v_awaiting int; v_expiring int; v_coord int;
begin
  v_caller := auth.uid();
  if v_caller is null then
    return jsonb_build_object('awaiting_my_decision', 0, 'expiring_soon', 0, 'coordinating', 0);
  end if;
  if p_ws_id is null then
    return jsonb_build_object('awaiting_my_decision', 0, 'expiring_soon', 0, 'coordinating', 0);
  end if;

  select count(*) into v_awaiting
    from public.approval_requests ar
    join public.approval_request_approvers a on a.approval_request_id = ar.id
    left join public.workspace_members wm on wm.id = a.workspace_member_id
    left join public.stakeholders sh on sh.id = a.stakeholder_id
    left join public.approval_responses r on r.approver_slot_id = a.id
   where ar.workspace_id = p_ws_id
     and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
     and a.removed_at is null
     and r.id is null
     and ar.status in ('pending','in_progress')
     and coalesce(wm.user_id, sh.user_id) = v_caller;

  select count(*) into v_expiring
    from public.approval_requests ar
   where ar.workspace_id = p_ws_id
     and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
     and ar.expires_at is not null
     and ar.expires_at < (now() + interval '24 hours')
     and ar.status in ('pending','in_progress');

  select count(*) into v_coord
    from public.approval_requests ar
   where ar.workspace_id = p_ws_id
     and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
     and ar.status in ('pending','in_progress')
     and ar.created_by_profile_id = v_caller;

  return jsonb_build_object(
    'awaiting_my_decision', v_awaiting,
    'expiring_soon',        v_expiring,
    'coordinating',         v_coord
  );
end $$;

revoke all on function public.get_approval_inbox_count(uuid) from public;
revoke all on function public.get_approval_inbox_count(uuid) from anon;
revoke all on function public.get_approval_inbox_count(uuid) from authenticated;
grant execute on function public.get_approval_inbox_count(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 7. get_project_approval_metrics / get_workspace_approval_metrics
------------------------------------------------------------------------------

create or replace function public.get_project_approval_metrics(p_proj_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' stable
as $$
declare v_ws uuid; v_out int; v_over int;
begin
  select workspace_id into v_ws from public.projects where id = p_proj_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(p_proj_id, v_ws, 'approval.view') then
    raise exception 'get_project_approval_metrics: forbidden' using errcode='42501';
  end if;

  select count(*) into v_out from public.approval_requests
    where project_id = p_proj_id and status in ('pending','in_progress');
  select count(*) into v_over from public.approval_requests
    where project_id = p_proj_id
      and expires_at is not null and expires_at < now()
      and status in ('pending','in_progress');

  return jsonb_build_object(
    'outstanding_count', v_out,
    'overdue_count',     v_over
  );
end $$;

revoke all on function public.get_project_approval_metrics(uuid) from public;
revoke all on function public.get_project_approval_metrics(uuid) from anon;
revoke all on function public.get_project_approval_metrics(uuid) from authenticated;
grant execute on function public.get_project_approval_metrics(uuid) to authenticated, service_role;

create or replace function public.get_workspace_approval_metrics(p_ws_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' stable
as $$
declare v_caller uuid; v_out int; v_over int;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_workspace_approval_metrics: authentication required' using errcode='42501'; end if;
  if p_ws_id is null then return null; end if;

  select count(*) into v_out from public.approval_requests ar
    where ar.workspace_id = p_ws_id
      and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
      and ar.status in ('pending','in_progress');
  select count(*) into v_over from public.approval_requests ar
    where ar.workspace_id = p_ws_id
      and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
      and ar.expires_at is not null and ar.expires_at < now()
      and ar.status in ('pending','in_progress');

  return jsonb_build_object(
    'outstanding_count', v_out,
    'overdue_count',     v_over
  );
end $$;

revoke all on function public.get_workspace_approval_metrics(uuid) from public;
revoke all on function public.get_workspace_approval_metrics(uuid) from anon;
revoke all on function public.get_workspace_approval_metrics(uuid) from authenticated;
grant execute on function public.get_workspace_approval_metrics(uuid) to authenticated, service_role;
