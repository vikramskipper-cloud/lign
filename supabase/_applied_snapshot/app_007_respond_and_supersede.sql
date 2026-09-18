
------------------------------------------------------------------------------
-- 3. respond_to_approval — extended (Option A additive tail)
------------------------------------------------------------------------------
-- The FROZEN 3-arg overload continues to exist unchanged; this REPLACES the
-- frozen body to add p_is_veto_cast + new decision handling. Since the frozen
-- signature is (uuid, text, text), we CREATE OR REPLACE the same signature
-- and preserve every semantic while extending arithmetic to include
-- abstained/veto/policy widening.

create or replace function public.respond_to_approval(
  p_approver_slot_id uuid,
  p_decision         text,
  p_comment          text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  return public.respond_to_approval(p_approver_slot_id, p_decision, p_comment, false);
end $$;

revoke all on function public.respond_to_approval(uuid, text, text) from public;
revoke all on function public.respond_to_approval(uuid, text, text) from anon;
revoke all on function public.respond_to_approval(uuid, text, text) from authenticated;
grant execute on function public.respond_to_approval(uuid, text, text) to authenticated, service_role;

-- Extended 4-arg overload
create or replace function public.respond_to_approval(
  p_approver_slot_id uuid,
  p_decision         text,
  p_comment          text,
  p_is_veto_cast     boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller         uuid;
  v_workspace_id   uuid;
  v_project_id     uuid;
  v_request_id     uuid;
  v_request_status text;
  v_policy         text;
  v_quorum_min     int;
  v_root_id        uuid;
  v_wm_id          uuid;
  v_sh_id          uuid;
  v_slot_user_id   uuid;
  v_slot_veto      boolean;
  v_slot_required  boolean;
  v_slot_sort      int;
  v_response_id    uuid;
  v_total_required int;
  v_approved       int;
  v_rejected       int;
  v_abstained      int;
  v_pending        int;
  v_outcome        text := null;
  v_has_veto_approver boolean;
  v_note_snippet   text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'respond_to_approval: authentication required' using errcode='42501';
  end if;

  -- F-2.1: new entry-point rejects changes_requested
  if p_decision is null or p_decision not in ('approved','rejected','abstained') then
    raise exception 'respond_to_approval: invalid decision % (must be approved|rejected|abstained)', coalesce(p_decision,'(null)') using errcode='22023';
  end if;

  if p_comment is null or length(trim(p_comment)) < 3 or length(p_comment) > 2000 then
    raise exception 'respond_to_approval: comment required (3-2000 chars)' using errcode='22004';
  end if;

  select workspace_id, approval_request_id, workspace_member_id, stakeholder_id,
         veto_power, required, sort_order
    into v_workspace_id, v_request_id, v_wm_id, v_sh_id,
         v_slot_veto, v_slot_required, v_slot_sort
    from public.approval_request_approvers
   where id = p_approver_slot_id;
  if v_workspace_id is null then
    raise exception 'respond_to_approval: slot not found' using errcode='23503';
  end if;

  select project_id, status, policy, quorum_min, root_approval_request_id
    into v_project_id, v_request_status, v_policy, v_quorum_min, v_root_id
    from public.approval_requests
   where id = v_request_id and workspace_id = v_workspace_id
   for update;
  if v_request_status not in ('pending','in_progress') then
    raise exception 'respond_to_approval: request status is % (must be pending|in_progress)', v_request_status using errcode='23514';
  end if;

  if not public.lign_has_capability(v_project_id, v_workspace_id, 'approval.respond') then
    raise exception 'respond_to_approval: forbidden (approval.respond)' using errcode='42501';
  end if;

  if p_is_veto_cast then
    if not v_slot_veto then
      raise exception 'respond_to_approval: slot does not have veto_power' using errcode='23514';
    end if;
    if p_decision <> 'rejected' then
      raise exception 'respond_to_approval: veto cast requires decision=rejected' using errcode='23514';
    end if;
  end if;

  if v_wm_id is not null then
    select user_id into v_slot_user_id from public.workspace_members where id = v_wm_id;
  else
    select user_id into v_slot_user_id from public.stakeholders where id = v_sh_id;
  end if;
  if v_slot_user_id is null then
    raise exception 'respond_to_approval: slot identity is unclaimed' using errcode='42501';
  end if;
  if v_slot_user_id <> v_caller then
    raise exception 'respond_to_approval: caller does not own this slot' using errcode='42501';
  end if;

  -- Sequential policy: require prior slots (by sort_order) to have all been approved
  if v_policy = 'sequential' then
    if exists (
      select 1 from public.approval_request_approvers a
       left join public.approval_responses r on r.approver_slot_id = a.id
       where a.approval_request_id = v_request_id
         and a.removed_at is null
         and a.sort_order < v_slot_sort
         and (r.decision is null or r.decision <> 'approved')
    ) then
      raise exception 'respond_to_approval: sequential policy — prior approvers have not yet approved' using errcode='23514';
    end if;
  end if;

  insert into public.approval_responses (
    workspace_id, approval_request_id, approver_slot_id,
    responder_profile_id, decision, comment, responded_at,
    is_veto_cast
  ) values (
    v_workspace_id, v_request_id, p_approver_slot_id,
    v_caller, p_decision, p_comment, now(),
    coalesce(p_is_veto_cast, false)
  )
  returning id into v_response_id;

  -- Emit approval.responded with extended payload (§11.2)
  v_note_snippet := left(coalesce(p_comment,''), 200);
  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_workspace_id, v_project_id, now(), 'approval.responded',
    v_caller, 'user',
    'approval_response', v_response_id, p_decision,
    jsonb_build_object('request_id', v_request_id, 'decision', p_decision),
    jsonb_build_object(
      'request_id', v_request_id,
      'decision', p_decision,
      'is_veto_cast', coalesce(p_is_veto_cast, false),
      'note_snippet', v_note_snippet,
      'sort_order', v_slot_sort
    )
  );

  -- Auto-transition pending → in_progress on first response
  if v_request_status = 'pending' then
    update public.approval_requests set status = 'in_progress' where id = v_request_id;
    v_request_status := 'in_progress';
  end if;

  -- Compute outcome
  select count(*) filter (where a.required)
    into v_total_required
    from public.approval_request_approvers a
   where a.approval_request_id = v_request_id and a.removed_at is null;

  select
    count(*) filter (where a.required and r.decision = 'approved'),
    count(*) filter (where a.required and r.decision = 'rejected'),
    count(*) filter (where a.required and r.decision = 'abstained'),
    count(*) filter (where a.required and r.decision is null)
    into v_approved, v_rejected, v_abstained, v_pending
    from public.approval_request_approvers a
    left join public.approval_responses r on r.approver_slot_id = a.id
   where a.approval_request_id = v_request_id and a.removed_at is null;

  select exists (
    select 1 from public.approval_request_approvers
     where approval_request_id = v_request_id and removed_at is null and veto_power = true
  ) into v_has_veto_approver;

  -- Veto cast → immediate rejected
  if coalesce(p_is_veto_cast, false) and p_decision = 'rejected' then
    v_outcome := 'rejected';
  elsif v_policy in ('all','unanimous') then
    if v_rejected >= 1 then
      v_outcome := 'rejected';
    elsif v_approved = v_total_required and v_total_required > 0 then
      v_outcome := 'approved';
    end if;
  elsif v_policy in ('any','single') then
    if v_approved >= 1 then
      v_outcome := 'approved';
    elsif (v_approved + v_rejected + v_abstained) = v_total_required and v_approved = 0 then
      v_outcome := 'rejected';
    end if;
  elsif v_policy = 'majority' then
    if v_approved * 2 > v_total_required then
      v_outcome := 'approved';
    elsif v_rejected * 2 >= v_total_required then
      v_outcome := 'rejected';
    end if;
  elsif v_policy = 'quorum' then
    if v_approved >= coalesce(v_quorum_min, 1) then
      v_outcome := 'approved';
    elsif (v_total_required - v_rejected - v_abstained) < coalesce(v_quorum_min, 1) then
      -- Enough non-approvals that quorum can no longer be reached
      v_outcome := 'rejected';
    end if;
  elsif v_policy = 'sequential' then
    if v_rejected >= 1 then
      v_outcome := 'rejected';
    elsif v_approved = v_total_required and v_total_required > 0 then
      v_outcome := 'approved';
    end if;
  end if;

  if v_outcome is not null then
    update public.approval_requests
       set status                   = v_outcome,
           outcome_at               = now(),
           outcome_actor_profile_id = case when p_is_veto_cast then v_caller else null end
     where id = v_request_id;

    insert into public.activity_events (
      workspace_id, project_id, occurred_at, event_type,
      actor_profile_id, actor_kind,
      subject_kind, subject_id, subject_label, subject_snapshot, payload
    ) values (
      v_workspace_id, v_project_id, now(),
      case when v_outcome = 'approved' then 'approval.approved' else 'approval.rejected' end,
      null, 'system',
      'approval_request', v_request_id, v_outcome,
      jsonb_build_object('policy', v_policy),
      jsonb_build_object(
        'outcome_summary', jsonb_build_object(
          'approved_count',  v_approved,
          'rejected_count',  v_rejected,
          'abstained_count', v_abstained,
          'pending_count',   v_pending,
          'veto_cast',       coalesce(p_is_veto_cast, false),
          'policy',          v_policy,
          'quorum_min',      v_quorum_min
        ),
        'outcome_at',                now(),
        'policy',                    v_policy,
        'has_veto_approver',         v_has_veto_approver,
        'root_approval_request_id',  v_root_id,
        'veto_cast',                 coalesce(p_is_veto_cast, false)
      )
    );
  end if;

  return v_response_id;
end $$;

revoke all on function public.respond_to_approval(uuid, text, text, boolean) from public;
revoke all on function public.respond_to_approval(uuid, text, text, boolean) from anon;
revoke all on function public.respond_to_approval(uuid, text, text, boolean) from authenticated;
grant execute on function public.respond_to_approval(uuid, text, text, boolean) to authenticated, service_role;

------------------------------------------------------------------------------
-- 4. supersede_approval_request — F-1.1 + F-7.1 + F-10.1 disciplines
------------------------------------------------------------------------------

create or replace function public.supersede_approval_request(
  p_old_request_id       uuid,
  p_new_target_version_id uuid,
  p_policy               text,
  p_approver_wm_ids      uuid[]      default '{}'::uuid[],
  p_approver_sh_ids      uuid[]      default '{}'::uuid[],
  p_quorum_min           integer     default null,
  p_due_at               timestamptz default null,
  p_expires_at           timestamptz default null,
  p_related_review_id    uuid        default null,
  p_approver_required    boolean[]   default '{}'::boolean[],
  p_approver_veto_power  boolean[]   default '{}'::boolean[],
  p_approver_sort_order  integer[]   default '{}'::integer[],
  p_note                 text        default null,
  p_title                text        default null,
  p_description          text        default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid;
  v_ws uuid; v_proj uuid; v_asset uuid;
  v_old_status text; v_old_root uuid; v_old_title text;
  v_new_id uuid;
  v_v_asset uuid; v_v_status text;
  v_wm_count int := coalesce(array_length(p_approver_wm_ids, 1), 0);
  v_sh_count int := coalesce(array_length(p_approver_sh_ids, 1), 0);
  v_total int;
  v_i int;
  v_wm uuid; v_sh uuid;
  v_required boolean; v_veto boolean; v_sort int;
  v_has_veto boolean := false;
  v_seq_seen int[];
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'supersede_approval_request: authentication required' using errcode='42501';
  end if;
  if p_old_request_id is null or p_new_target_version_id is null then
    raise exception 'supersede_approval_request: ids required' using errcode='22004';
  end if;
  if p_policy is null or p_policy not in ('single','unanimous','majority','quorum','sequential') then
    raise exception 'supersede_approval_request: invalid policy %', coalesce(p_policy,'(null)') using errcode='22023';
  end if;
  if p_policy = 'quorum' and (p_quorum_min is null or p_quorum_min <= 0) then
    raise exception 'supersede_approval_request: quorum_min required and positive when policy=quorum' using errcode='22004';
  end if;

  -- Step 1: SELECT ... FOR UPDATE on the old row
  select workspace_id, project_id, design_asset_id, status, root_approval_request_id, title
    into v_ws, v_proj, v_asset, v_old_status, v_old_root, v_old_title
    from public.approval_requests
   where id = p_old_request_id
   for update;
  if v_ws is null then
    raise exception 'supersede_approval_request: old request not found' using errcode='23503';
  end if;

  if not public.lign_has_capability(v_proj, v_ws, 'approval.supersede') then
    raise exception 'supersede_approval_request: forbidden (approval.supersede)' using errcode='42501';
  end if;

  -- Step 2: F-10.1 — only pending/in_progress may be superseded
  if v_old_status not in ('pending','in_progress') then
    raise exception 'supersede_approval_request: old request is % (must be pending|in_progress; approved is terminal-immutable per F-10.1)', v_old_status using errcode='23514';
  end if;

  -- Validate new target version
  select design_asset_id, status into v_v_asset, v_v_status
    from public.asset_versions where id = p_new_target_version_id;
  if v_v_asset is null then
    raise exception 'supersede_approval_request: new version not found' using errcode='23503';
  end if;
  if v_v_asset <> v_asset then
    raise exception 'supersede_approval_request: new version must belong to the same asset' using errcode='23514';
  end if;
  if v_v_status <> 'published' then
    raise exception 'supersede_approval_request: new version must be published (is %)', v_v_status using errcode='23514';
  end if;

  -- Metadata array validation
  v_total := v_wm_count + v_sh_count;
  if v_total < 1 then
    raise exception 'supersede_approval_request: at least one approver required' using errcode='22004';
  end if;
  if coalesce(array_length(p_approver_required, 1), 0) not in (0, v_total) then
    raise exception 'supersede_approval_request: p_approver_required length mismatch' using errcode='22023';
  end if;
  if coalesce(array_length(p_approver_veto_power, 1), 0) not in (0, v_total) then
    raise exception 'supersede_approval_request: p_approver_veto_power length mismatch' using errcode='22023';
  end if;
  if coalesce(array_length(p_approver_sort_order, 1), 0) not in (0, v_total) then
    raise exception 'supersede_approval_request: p_approver_sort_order length mismatch' using errcode='22023';
  end if;

  -- Veto capability gate
  if coalesce(array_length(p_approver_veto_power, 1), 0) > 0 then
    for v_i in 1..array_length(p_approver_veto_power, 1) loop
      if coalesce(p_approver_veto_power[v_i], false) then
        v_has_veto := true;
        exit;
      end if;
    end loop;
  end if;
  if v_has_veto and not public.lign_has_capability(v_proj, v_ws, 'approval.veto') then
    raise exception 'supersede_approval_request: forbidden (approval.veto)' using errcode='42501';
  end if;

  -- Sequential validation (F-1.2)
  if p_policy = 'sequential' then
    if coalesce(array_length(p_approver_sort_order, 1), 0) = 0 then
      raise exception 'supersede_approval_request: sequential policy requires p_approver_sort_order' using errcode='22023';
    end if;
    v_seq_seen := array[]::int[];
    for v_i in 1..v_total loop
      v_sort := coalesce(p_approver_sort_order[v_i], -1);
      if v_sort < 0 or v_sort >= v_total then
        raise exception 'supersede_approval_request: sequential sort_order must be 0..N-1' using errcode='22023';
      end if;
      if v_sort = any(v_seq_seen) then
        raise exception 'supersede_approval_request: sequential sort_order values must be distinct' using errcode='22023';
      end if;
      v_seq_seen := v_seq_seen || v_sort;
    end loop;
  end if;

  -- Step 3: transition old to superseded FIRST (removes from active-target
  -- partial unique index; F-1.1)
  update public.approval_requests
     set status                   = 'superseded',
         outcome_at               = now(),
         outcome_actor_profile_id = v_caller,
         outcome_note             = p_note
   where id = p_old_request_id;

  -- Step 4-5: pre-compute UUID + INSERT new row with chain columns INLINE (F-7.1)
  v_new_id := gen_random_uuid();

  insert into public.approval_requests (
    id,
    workspace_id, project_id, design_asset_id, version_id,
    policy, status, title, description,
    due_at, quorum_min, expires_at, related_review_id,
    supersedes_approval_request_id, root_approval_request_id,
    created_by_profile_id
  ) values (
    v_new_id,
    v_ws, v_proj, v_asset, p_new_target_version_id,
    p_policy, 'draft', coalesce(p_title, v_old_title), p_description,
    p_due_at, p_quorum_min, p_expires_at, p_related_review_id,
    p_old_request_id, coalesce(v_old_root, p_old_request_id),  -- INLINE
    v_caller
  );

  -- Roster
  for v_i in 1..v_wm_count loop
    v_wm := p_approver_wm_ids[v_i];
    if not exists (
      select 1 from public.workspace_members
       where id = v_wm and workspace_id = v_ws and status = 'active'
    ) then
      raise exception 'supersede_approval_request: workspace_member % not active', v_wm using errcode='23503';
    end if;
    v_required := coalesce(p_approver_required[v_i], true);
    v_veto     := coalesce(p_approver_veto_power[v_i], false);
    v_sort     := coalesce(p_approver_sort_order[v_i], v_i - 1);
    insert into public.approval_request_approvers (
      workspace_id, approval_request_id, workspace_member_id,
      required, veto_power, sort_order
    ) values (v_ws, v_new_id, v_wm, v_required, v_veto, v_sort);
  end loop;
  for v_i in 1..v_sh_count loop
    v_sh := p_approver_sh_ids[v_i];
    if not exists (
      select 1 from public.stakeholders
       where id = v_sh and workspace_id = v_ws and status in ('active','invited')
    ) then
      raise exception 'supersede_approval_request: stakeholder % not in workspace', v_sh using errcode='23503';
    end if;
    v_required := coalesce(p_approver_required[v_wm_count + v_i], true);
    v_veto     := coalesce(p_approver_veto_power[v_wm_count + v_i], false);
    v_sort     := coalesce(p_approver_sort_order[v_wm_count + v_i], v_wm_count + v_i - 1);
    insert into public.approval_request_approvers (
      workspace_id, approval_request_id, stakeholder_id,
      required, veto_power, sort_order
    ) values (v_ws, v_new_id, v_sh, v_required, v_veto, v_sort);
  end loop;

  -- Step 8: emit approval.superseded on old; approval.requested on new
  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_proj, now(), 'approval.superseded',
    v_caller, 'user',
    'approval_request', p_old_request_id, 'superseded',
    jsonb_build_object('title', v_old_title),
    jsonb_build_object(
      'old_request_id', p_old_request_id,
      'new_request_id', v_new_id,
      'root_approval_request_id', coalesce(v_old_root, p_old_request_id),
      'note', p_note
    )
  );

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_proj, now(), 'approval.requested',
    v_caller, 'user',
    'approval_request', v_new_id, coalesce(p_title, v_old_title, 'approval'),
    jsonb_build_object(
      'asset_id',   v_asset,
      'version_id', p_new_target_version_id,
      'policy',     p_policy
    ),
    jsonb_build_object(
      'policy', p_policy,
      'quorum_min', p_quorum_min,
      'expires_at', p_expires_at,
      'related_review_id', p_related_review_id,
      'supersedes_approval_request_id', p_old_request_id,
      'root_approval_request_id', coalesce(v_old_root, p_old_request_id),
      'approver_wm_ids', coalesce(to_jsonb(p_approver_wm_ids), '[]'::jsonb),
      'approver_sh_ids', coalesce(to_jsonb(p_approver_sh_ids), '[]'::jsonb),
      'has_veto_approver', v_has_veto
    )
  );

  return v_new_id;
end $$;

revoke all on function public.supersede_approval_request(uuid,uuid,text,uuid[],uuid[],integer,timestamptz,timestamptz,uuid,boolean[],boolean[],integer[],text,text,text) from public;
revoke all on function public.supersede_approval_request(uuid,uuid,text,uuid[],uuid[],integer,timestamptz,timestamptz,uuid,boolean[],boolean[],integer[],text,text,text) from anon;
revoke all on function public.supersede_approval_request(uuid,uuid,text,uuid[],uuid[],integer,timestamptz,timestamptz,uuid,boolean[],boolean[],integer[],text,text,text) from authenticated;
grant execute on function public.supersede_approval_request(uuid,uuid,text,uuid[],uuid[],integer,timestamptz,timestamptz,uuid,boolean[],boolean[],integer[],text,text,text) to authenticated, service_role;
