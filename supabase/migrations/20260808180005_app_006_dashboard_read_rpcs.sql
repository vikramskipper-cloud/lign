-- APP 006 RPCs part 6: dashboard reads

create or replace function public.list_reviews_dashboard(
  p_ws_id                   uuid,
  p_proj_id                 uuid    default null,
  p_view                    text    default 'recent',
  p_status_filter           text[]  default null,
  p_owner_ids               uuid[]  default null,
  p_reviewer_profile_ids    uuid[]  default null,
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
  out_round_number                integer,
  out_root_review_id              uuid,
  out_policy                      text,
  out_created_by_profile_id       uuid,
  out_coordinator_profile_id      uuid,
  out_due_at                      timestamptz,
  out_completed_at                timestamptz,
  out_cancelled_at                timestamptz,
  out_created_at                  timestamptz,
  out_updated_at                  timestamptz,
  out_open_reviewer_count         integer,
  out_signed_off_count            integer,
  out_declined_count              integer,
  out_commented_count             integer,
  out_total_reviewer_count        integer,
  out_open_comment_count          integer,
  out_overdue_flag                boolean,
  out_my_slot_status              text
)
language plpgsql security definer set search_path = '' stable
as $$
declare v_caller uuid; v_lim int;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'list_reviews_dashboard: authentication required' using errcode='42501'; end if;
  if p_ws_id is null then raise exception 'list_reviews_dashboard: ws_id required' using errcode='22004'; end if;
  v_lim := greatest(1, least(coalesce(p_limit, 30), 100));

  return query
    with visible as (
      select r.*
        from public.reviews r
       where r.workspace_id = p_ws_id
         and (p_proj_id is null or r.project_id = p_proj_id)
         and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
    ),
    filtered as (
      select v.*
        from visible v
       where (p_status_filter is null or v.status = any(p_status_filter))
         and (p_owner_ids is null or v.created_by_profile_id = any(p_owner_ids))
         and (
           p_reviewer_profile_ids is null
           or exists (
             select 1 from public.review_participants rp
              left join public.workspace_members wm on wm.id = rp.workspace_member_id
              left join public.stakeholders sh on sh.id = rp.stakeholder_id
              where rp.review_id = v.id
                and rp.removed_at is null
                and coalesce(wm.user_id, sh.user_id) = any(p_reviewer_profile_ids)
           )
         )
         and case p_view
           when 'assigned_to_me' then exists (
             select 1 from public.review_participants rp
              left join public.workspace_members wm on wm.id = rp.workspace_member_id
              left join public.stakeholders sh on sh.id = rp.stakeholder_id
              where rp.review_id = v.id
                and rp.removed_at is null
                and rp.status = 'pending'
                and coalesce(wm.user_id, sh.user_id) = v_caller
           ) and v.status in ('open','in_progress','waiting')
           when 'waiting_on_others' then v.created_by_profile_id = v_caller
                                        and v.status in ('open','in_progress','waiting')
           when 'overdue' then v.due_at is not null and v.due_at < now()
                              and v.status in ('open','in_progress','waiting')
           when 'completed' then v.status = 'completed'
                                and (
                                  v.created_by_profile_id = v_caller
                                  or exists (
                                    select 1 from public.review_participants rp
                                     left join public.workspace_members wm on wm.id = rp.workspace_member_id
                                     left join public.stakeholders sh on sh.id = rp.stakeholder_id
                                     where rp.review_id = v.id
                                       and coalesce(wm.user_id, sh.user_id) = v_caller
                                  )
                                )
           when 'bookmarks' then exists (
             select 1 from public.user_bookmarks b
              where b.user_id = v_caller
                and b.subject_kind = 'review'
                and b.subject_id = v.id
           )
           else true
         end
    )
    select
      f.id, f.workspace_id, f.project_id, f.design_asset_id, f.version_id,
      f.title, f.description, f.status, f.round_number, f.root_review_id, f.policy,
      f.created_by_profile_id, f.coordinator_profile_id,
      f.due_at, f.completed_at, f.cancelled_at, f.created_at, f.updated_at,
      (select count(*)::int from public.review_participants
        where review_id = f.id and status = 'pending' and removed_at is null),
      (select count(*)::int from public.review_participants
        where review_id = f.id and status = 'signed_off' and removed_at is null),
      (select count(*)::int from public.review_participants
        where review_id = f.id and status = 'declined' and removed_at is null),
      (select count(*)::int from public.review_participants
        where review_id = f.id and status = 'commented' and removed_at is null),
      (select count(*)::int from public.review_participants
        where review_id = f.id and removed_at is null),
      (select count(*)::int from public.comments
        where target_review_id = f.id
          and parent_comment_id is null
          and resolved_at is null
          and deleted_at is null),
      (f.due_at is not null and f.due_at < now() and f.status in ('open','in_progress','waiting')),
      (select rp.status from public.review_participants rp
        left join public.workspace_members wm on wm.id = rp.workspace_member_id
        left join public.stakeholders sh on sh.id = rp.stakeholder_id
        where rp.review_id = f.id
          and rp.removed_at is null
          and coalesce(wm.user_id, sh.user_id) = v_caller
        limit 1)
    from filtered f
    where (p_cursor_updated_at is null
           or (f.updated_at, f.id) < (p_cursor_updated_at, p_cursor_id))
    order by f.updated_at desc, f.id desc
    limit v_lim;
end $$;
revoke all on function public.list_reviews_dashboard(uuid, uuid, text, text[], uuid[], uuid[], timestamptz, uuid, integer) from public;
revoke all on function public.list_reviews_dashboard(uuid, uuid, text, text[], uuid[], uuid[], timestamptz, uuid, integer) from anon;
grant execute on function public.list_reviews_dashboard(uuid, uuid, text, text[], uuid[], uuid[], timestamptz, uuid, integer) to authenticated, service_role;

create or replace function public.get_review(p_review_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' stable
as $$
declare v_caller uuid; v_row jsonb; v_participants jsonb; v_metrics jsonb;
        v_ws uuid; v_proj uuid; v_asset uuid; v_version uuid;
        v_opened_at timestamptz; v_first_resp_at timestamptz; v_first_comm_at timestamptz;
        v_newer_exists boolean; v_chain jsonb;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_review: authentication required' using errcode='42501'; end if;

  select r.workspace_id, r.project_id, r.design_asset_id, r.version_id
    into v_ws, v_proj, v_asset, v_version
    from public.reviews r where r.id = p_review_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(v_proj, v_ws, 'review.view') then
    raise exception 'get_review: forbidden (review.view)' using errcode='42501';
  end if;

  select to_jsonb(r) into v_row from public.reviews r where r.id = p_review_id;

  select coalesce(jsonb_agg(row_to_jsonb(x)), '[]'::jsonb) into v_participants
  from (
    select rp.id, rp.workspace_member_id, rp.stakeholder_id,
           rp.status, rp.assigned_at, rp.responded_at,
           rp.required, rp.sequence_index, rp.removed_at, rp.removed_reason,
           coalesce(wm_p.display_name, sh_p.display_name, sh.display_name) as display_name,
           coalesce(wm_p.avatar_url, sh_p.avatar_url) as avatar_url,
           coalesce(wm.user_id, sh.user_id) as profile_id,
           case when rp.workspace_member_id is not null then 'member' else 'stakeholder' end as identity
      from public.review_participants rp
      left join public.workspace_members wm on wm.id = rp.workspace_member_id
      left join public.stakeholders sh on sh.id = rp.stakeholder_id
      left join public.profiles wm_p on wm_p.id = wm.user_id
      left join public.profiles sh_p on sh_p.id = sh.user_id
     where rp.review_id = p_review_id
     order by rp.sequence_index asc, rp.assigned_at asc
  ) x;

  select min(ae.occurred_at) into v_opened_at
    from public.activity_events ae
   where ae.subject_kind = 'review' and ae.subject_id = p_review_id
     and ae.event_type = 'review.opened';

  select min(ae.occurred_at) into v_first_resp_at
    from public.activity_events ae
   where ae.subject_kind = 'review_participant'
     and (ae.payload->>'review_id')::uuid = p_review_id
     and ae.event_type = 'review.reviewer_responded';

  select min(c.created_at) into v_first_comm_at
    from public.comments c
   where c.target_review_id = p_review_id and c.deleted_at is null;

  select v_version is not null and exists (
    select 1 from public.asset_versions av2
     where av2.design_asset_id = v_asset
       and av2.status = 'published'
       and av2.published_at > coalesce((select published_at from public.asset_versions where id = v_version), '-infinity'::timestamptz)
  ) into v_newer_exists;

  v_metrics := jsonb_build_object(
    'opened_at', v_opened_at,
    'first_responded_at', v_first_resp_at,
    'first_commented_at', v_first_comm_at,
    'open_comment_count', (
      select count(*) from public.comments
       where target_review_id = p_review_id
         and parent_comment_id is null
         and resolved_at is null
         and deleted_at is null
    ),
    'response_distribution', (
      select jsonb_build_object(
        'signed_off', count(*) filter (where status='signed_off'),
        'commented',  count(*) filter (where status='commented'),
        'declined',   count(*) filter (where status='declined'),
        'pending',    count(*) filter (where status='pending')
      ) from public.review_participants where review_id = p_review_id and removed_at is null
    ),
    'newer_version_exists', v_newer_exists
  );

  select jsonb_build_object(
    'round_number', (v_row->>'round_number')::int,
    'is_latest', not exists (
      select 1 from public.reviews r2
       where r2.parent_review_id = p_review_id
    ),
    'prior_review_id', (v_row->>'parent_review_id')::uuid,
    'next_review_id', (
      select r2.id from public.reviews r2
       where r2.parent_review_id = p_review_id
       limit 1
    )
  ) into v_chain;

  return jsonb_build_object(
    'review', v_row,
    'participants', v_participants,
    'metrics', v_metrics,
    'chain_position', v_chain
  );
end $$;
revoke all on function public.get_review(uuid) from public;
revoke all on function public.get_review(uuid) from anon;
grant execute on function public.get_review(uuid) to authenticated, service_role;

create or replace function public.get_review_chain(p_root_review_id uuid)
returns table (
  out_id                uuid,
  out_round_number      integer,
  out_status            text,
  out_title             text,
  out_created_at        timestamptz,
  out_completed_at      timestamptz,
  out_cancelled_at      timestamptz,
  out_reviewer_count    integer,
  out_signed_off_count  integer,
  out_declined_count    integer
)
language plpgsql security definer set search_path = '' stable
as $$
declare v_caller uuid; v_ws uuid; v_proj uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_review_chain: authentication required' using errcode='42501'; end if;

  select workspace_id, project_id into v_ws, v_proj
    from public.reviews where id = p_root_review_id;
  if v_ws is null then return; end if;
  if not public.lign_has_capability(v_proj, v_ws, 'review.view') then
    raise exception 'get_review_chain: forbidden (review.view)' using errcode='42501';
  end if;

  return query
    select r.id, r.round_number, r.status, r.title,
           r.created_at, r.completed_at, r.cancelled_at,
           (select count(*)::int from public.review_participants
             where review_id = r.id and removed_at is null),
           (select count(*)::int from public.review_participants
             where review_id = r.id and status='signed_off' and removed_at is null),
           (select count(*)::int from public.review_participants
             where review_id = r.id and status='declined' and removed_at is null)
      from public.reviews r
     where r.root_review_id = p_root_review_id or r.id = p_root_review_id
     order by r.round_number asc;
end $$;
revoke all on function public.get_review_chain(uuid) from public;
revoke all on function public.get_review_chain(uuid) from anon;
grant execute on function public.get_review_chain(uuid) to authenticated, service_role;

create or replace function public.get_review_inbox_count(p_ws_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' stable
as $$
declare v_caller uuid; v_assigned int; v_overdue int; v_coord int;
begin
  v_caller := auth.uid();
  if v_caller is null then return jsonb_build_object('assigned_to_me',0,'overdue',0,'coordinating',0); end if;
  if p_ws_id is null then return jsonb_build_object('assigned_to_me',0,'overdue',0,'coordinating',0); end if;

  select count(*) into v_assigned
    from public.reviews r
    join public.review_participants rp on rp.review_id = r.id
    left join public.workspace_members wm on wm.id = rp.workspace_member_id
    left join public.stakeholders sh on sh.id = rp.stakeholder_id
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
     and rp.removed_at is null
     and rp.status = 'pending'
     and r.status in ('open','in_progress','waiting')
     and coalesce(wm.user_id, sh.user_id) = v_caller;

  select count(*) into v_overdue
    from public.reviews r
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
     and r.due_at is not null
     and r.due_at < now()
     and r.status in ('open','in_progress','waiting');

  select count(*) into v_coord
    from public.reviews r
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
     and r.status in ('open','in_progress','waiting')
     and (r.coordinator_profile_id = v_caller or (r.coordinator_profile_id is null and r.created_by_profile_id = v_caller));

  return jsonb_build_object(
    'assigned_to_me', v_assigned,
    'overdue', v_overdue,
    'coordinating', v_coord
  );
end $$;
revoke all on function public.get_review_inbox_count(uuid) from public;
revoke all on function public.get_review_inbox_count(uuid) from anon;
grant execute on function public.get_review_inbox_count(uuid) to authenticated, service_role;

create or replace function public.get_project_review_metrics(p_proj_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' stable
as $$
declare v_ws uuid; v_out int; v_over int;
begin
  select workspace_id into v_ws from public.projects where id = p_proj_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(p_proj_id, v_ws, 'review.view') then
    raise exception 'get_project_review_metrics: forbidden (review.view)' using errcode='42501';
  end if;

  select count(*) into v_out from public.reviews
    where project_id = p_proj_id and status in ('open','in_progress','waiting','ready_for_review');
  select count(*) into v_over from public.reviews
    where project_id = p_proj_id
      and due_at is not null and due_at < now()
      and status in ('open','in_progress','waiting');

  return jsonb_build_object(
    'outstanding_count', v_out,
    'overdue_count', v_over
  );
end $$;
revoke all on function public.get_project_review_metrics(uuid) from public;
revoke all on function public.get_project_review_metrics(uuid) from anon;
grant execute on function public.get_project_review_metrics(uuid) to authenticated, service_role;

create or replace function public.get_workspace_review_metrics(p_ws_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' stable
as $$
declare v_caller uuid; v_out int; v_over int;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_workspace_review_metrics: authentication required' using errcode='42501'; end if;
  if p_ws_id is null then return null; end if;

  select count(*) into v_out from public.reviews r
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
     and r.status in ('open','in_progress','waiting','ready_for_review');

  select count(*) into v_over from public.reviews r
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
     and r.due_at is not null and r.due_at < now()
     and r.status in ('open','in_progress','waiting');

  return jsonb_build_object(
    'outstanding_count', v_out,
    'overdue_count', v_over
  );
end $$;
revoke all on function public.get_workspace_review_metrics(uuid) from public;
revoke all on function public.get_workspace_review_metrics(uuid) from anon;
grant execute on function public.get_workspace_review_metrics(uuid) to authenticated, service_role;
