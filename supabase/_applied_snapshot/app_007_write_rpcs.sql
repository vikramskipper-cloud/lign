
-- APP 007 Write RPCs

------------------------------------------------------------------------------
-- 1. create_approval_draft — F-7.1 chain-init discipline
------------------------------------------------------------------------------

create or replace function public.create_approval_draft(
  p_project_id            uuid,
  p_design_asset_id       uuid,
  p_version_id            uuid,
  p_policy                text,
  p_approver_wm_ids       uuid[]      default '{}'::uuid[],
  p_approver_sh_ids       uuid[]      default '{}'::uuid[],
  p_title                 text        default null,
  p_description           text        default null,
  p_due_at                timestamptz default null,
  p_quorum_min            integer     default null,
  p_expires_at            timestamptz default null,
  p_related_review_id     uuid        default null,
  p_approver_required     boolean[]   default '{}'::boolean[],
  p_approver_veto_power   boolean[]   default '{}'::boolean[],
  p_approver_sort_order   integer[]   default '{}'::integer[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller         uuid;
  v_workspace_id   uuid;
  v_da_project     uuid;
  v_v_asset        uuid;
  v_v_status       text;
  v_request_id     uuid;
  v_wm_count       int := coalesce(array_length(p_approver_wm_ids, 1), 0);
  v_sh_count       int := coalesce(array_length(p_approver_sh_ids, 1), 0);
  v_total          int;
  v_req_count      int := coalesce(array_length(p_approver_required, 1), 0);
  v_veto_count     int := coalesce(array_length(p_approver_veto_power, 1), 0);
  v_sort_count     int := coalesce(array_length(p_approver_sort_order, 1), 0);
  v_i              int;
  v_wm_id          uuid;
  v_sh_id          uuid;
  v_required       boolean;
  v_veto           boolean;
  v_sort           int;
  v_has_veto       boolean := false;
  v_review_ws      uuid;
  v_seq_seen       int[];
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'create_approval_draft: authentication required' using errcode='42501';
  end if;
  if p_project_id is null or p_design_asset_id is null or p_version_id is null then
    raise exception 'create_approval_draft: ids required' using errcode='22004';
  end if;
  if p_policy is null or p_policy not in ('single','unanimous','majority','quorum','sequential') then
    raise exception 'create_approval_draft: invalid policy %', coalesce(p_policy,'(null)') using errcode='22023';
  end if;
  if p_policy = 'quorum' and (p_quorum_min is null or p_quorum_min <= 0) then
    raise exception 'create_approval_draft: quorum_min required and positive when policy=quorum' using errcode='22004';
  end if;

  v_total := v_wm_count + v_sh_count;
  if v_req_count > 0 and v_req_count <> v_total then
    raise exception 'create_approval_draft: p_approver_required length must match total approver count' using errcode='22023';
  end if;
  if v_veto_count > 0 and v_veto_count <> v_total then
    raise exception 'create_approval_draft: p_approver_veto_power length must match total approver count' using errcode='22023';
  end if;
  if v_sort_count > 0 and v_sort_count <> v_total then
    raise exception 'create_approval_draft: p_approver_sort_order length must match total approver count' using errcode='22023';
  end if;

  select workspace_id, project_id into v_workspace_id, v_da_project
    from public.design_assets where id = p_design_asset_id;
  if v_workspace_id is null then
    raise exception 'create_approval_draft: design_asset not found' using errcode='23503';
  end if;
  if v_da_project <> p_project_id then
    raise exception 'create_approval_draft: asset does not belong to project' using errcode='23514';
  end if;

  select design_asset_id, status into v_v_asset, v_v_status
    from public.asset_versions where id = p_version_id;
  if v_v_asset is null then
    raise exception 'create_approval_draft: version not found' using errcode='23503';
  end if;
  if v_v_asset <> p_design_asset_id then
    raise exception 'create_approval_draft: version does not belong to asset' using errcode='23514';
  end if;
  if v_v_status <> 'published' then
    raise exception 'create_approval_draft: version must be published (is %)', v_v_status using errcode='23514';
  end if;

  if not public.lign_has_capability(p_project_id, v_workspace_id, 'approval.request') then
    raise exception 'create_approval_draft: forbidden (approval.request)' using errcode='42501';
  end if;

  -- Validate related_review_id (informational, but must match workspace if set)
  if p_related_review_id is not null then
    select workspace_id into v_review_ws
      from public.reviews where id = p_related_review_id;
    if v_review_ws is null or v_review_ws <> v_workspace_id then
      raise exception 'create_approval_draft: related_review not in same workspace' using errcode='23514';
    end if;
  end if;

  -- Check for veto-power approvers and gate on approval.veto capability
  if v_veto_count > 0 then
    for v_i in 1..v_veto_count loop
      if coalesce(p_approver_veto_power[v_i], false) then
        v_has_veto := true;
        exit;
      end if;
    end loop;
  end if;
  if v_has_veto and not public.lign_has_capability(p_project_id, v_workspace_id, 'approval.veto') then
    raise exception 'create_approval_draft: forbidden (approval.veto) — cannot assign veto-power approvers' using errcode='42501';
  end if;

  -- Sequential-policy sort_order validation (F-1.2): distinct 0..N-1
  if p_policy = 'sequential' and v_total > 0 then
    if v_sort_count = 0 then
      raise exception 'create_approval_draft: sequential policy requires p_approver_sort_order' using errcode='22023';
    end if;
    v_seq_seen := array[]::int[];
    for v_i in 1..v_sort_count loop
      v_sort := coalesce(p_approver_sort_order[v_i], -1);
      if v_sort < 0 or v_sort >= v_total then
        raise exception 'create_approval_draft: sequential sort_order must be 0..N-1 (got %)', v_sort using errcode='22023';
      end if;
      if v_sort = any(v_seq_seen) then
        raise exception 'create_approval_draft: sequential sort_order values must be distinct (duplicate %)', v_sort using errcode='22023';
      end if;
      v_seq_seen := v_seq_seen || v_sort;
    end loop;
  end if;

  -- F-7.1 chain-init discipline: pre-compute UUID; insert root=self inline
  v_request_id := gen_random_uuid();

  insert into public.approval_requests (
    id,
    workspace_id, project_id, design_asset_id, version_id,
    policy, status, title, description, due_at,
    quorum_min, expires_at, related_review_id,
    supersedes_approval_request_id, root_approval_request_id,
    created_by_profile_id
  ) values (
    v_request_id,
    v_workspace_id, p_project_id, p_design_asset_id, p_version_id,
    p_policy, 'draft', p_title, p_description, p_due_at,
    p_quorum_min, p_expires_at, p_related_review_id,
    null, v_request_id,           -- chain root: supersedes=NULL, root=self INLINE
    v_caller
  );

  -- Roster: workspace_member approvers first, then stakeholders (F-3.1)
  for v_i in 1..v_wm_count loop
    v_wm_id := p_approver_wm_ids[v_i];
    if not exists (
      select 1 from public.workspace_members
       where id = v_wm_id and workspace_id = v_workspace_id and status = 'active'
    ) then
      raise exception 'create_approval_draft: workspace_member % not active', v_wm_id using errcode='23503';
    end if;
    v_required := coalesce(p_approver_required[v_i], true);
    v_veto     := coalesce(p_approver_veto_power[v_i], false);
    v_sort     := coalesce(p_approver_sort_order[v_i], v_i - 1);
    insert into public.approval_request_approvers (
      workspace_id, approval_request_id, workspace_member_id,
      required, veto_power, sort_order
    ) values (
      v_workspace_id, v_request_id, v_wm_id,
      v_required, v_veto, v_sort
    );
  end loop;
  for v_i in 1..v_sh_count loop
    v_sh_id := p_approver_sh_ids[v_i];
    if not exists (
      select 1 from public.stakeholders
       where id = v_sh_id and workspace_id = v_workspace_id and status in ('active','invited')
    ) then
      raise exception 'create_approval_draft: stakeholder % not in workspace', v_sh_id using errcode='23503';
    end if;
    v_required := coalesce(p_approver_required[v_wm_count + v_i], true);
    v_veto     := coalesce(p_approver_veto_power[v_wm_count + v_i], false);
    v_sort     := coalesce(p_approver_sort_order[v_wm_count + v_i], v_wm_count + v_i - 1);
    insert into public.approval_request_approvers (
      workspace_id, approval_request_id, stakeholder_id,
      required, veto_power, sort_order
    ) values (
      v_workspace_id, v_request_id, v_sh_id,
      v_required, v_veto, v_sort
    );
  end loop;

  -- Emit approval.requested with extended payload (§11.1)
  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_workspace_id, p_project_id, now(), 'approval.requested',
    v_caller, 'user',
    'approval_request', v_request_id, coalesce(p_title, 'approval'),
    jsonb_build_object(
      'asset_id',   p_design_asset_id,
      'version_id', p_version_id,
      'policy',     p_policy
    ),
    jsonb_build_object(
      'policy',                          p_policy,
      'quorum_min',                      p_quorum_min,
      'expires_at',                      p_expires_at,
      'related_review_id',               p_related_review_id,
      'supersedes_approval_request_id',  null,
      'root_approval_request_id',        v_request_id,
      'approver_wm_ids',                 coalesce(to_jsonb(p_approver_wm_ids), '[]'::jsonb),
      'approver_sh_ids',                 coalesce(to_jsonb(p_approver_sh_ids), '[]'::jsonb),
      'has_veto_approver',               v_has_veto
    )
  );

  return v_request_id;
end $$;

revoke all on function public.create_approval_draft(uuid,uuid,uuid,text,uuid[],uuid[],text,text,timestamptz,integer,timestamptz,uuid,boolean[],boolean[],integer[]) from public;
revoke all on function public.create_approval_draft(uuid,uuid,uuid,text,uuid[],uuid[],text,text,timestamptz,integer,timestamptz,uuid,boolean[],boolean[],integer[]) from anon;
revoke all on function public.create_approval_draft(uuid,uuid,uuid,text,uuid[],uuid[],text,text,timestamptz,integer,timestamptz,uuid,boolean[],boolean[],integer[]) from authenticated;
grant execute on function public.create_approval_draft(uuid,uuid,uuid,text,uuid[],uuid[],text,text,timestamptz,integer,timestamptz,uuid,boolean[],boolean[],integer[]) to authenticated, service_role;

------------------------------------------------------------------------------
-- 2. send_approval_request — draft → pending
------------------------------------------------------------------------------

create or replace function public.send_approval_request(
  p_approval_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid;
  v_ws uuid; v_proj uuid; v_status text; v_policy text;
  v_title text; v_expires_at timestamptz;
  v_approver_count int;
  v_wm_ids jsonb; v_sh_ids jsonb;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'send_approval_request: authentication required' using errcode='42501';
  end if;
  if p_approval_request_id is null then
    raise exception 'send_approval_request: id required' using errcode='22004';
  end if;

  select workspace_id, project_id, status, policy, title, expires_at
    into v_ws, v_proj, v_status, v_policy, v_title, v_expires_at
    from public.approval_requests
   where id = p_approval_request_id
   for update;
  if v_ws is null then
    raise exception 'send_approval_request: not found' using errcode='23503';
  end if;
  if v_status <> 'draft' then
    raise exception 'send_approval_request: status is % (must be draft)', v_status using errcode='23514';
  end if;

  if not public.lign_has_capability(v_proj, v_ws, 'approval.request') then
    raise exception 'send_approval_request: forbidden (approval.request)' using errcode='42501';
  end if;

  select count(*) into v_approver_count
    from public.approval_request_approvers
   where approval_request_id = p_approval_request_id and removed_at is null;
  if v_approver_count < 1 then
    raise exception 'send_approval_request: at least one approver required' using errcode='23514';
  end if;

  -- Uniqueness: partial-unique index approval_requests_active_target_key
  -- covers (design_asset_id, version_id) where status in (pending, in_progress).
  -- Transitioning to pending here will trip that if another active request exists.
  update public.approval_requests
     set status = 'pending', sent_at = now()
   where id = p_approval_request_id;

  select coalesce(jsonb_agg(workspace_member_id) filter (where workspace_member_id is not null), '[]'::jsonb),
         coalesce(jsonb_agg(stakeholder_id) filter (where stakeholder_id is not null), '[]'::jsonb)
    into v_wm_ids, v_sh_ids
    from public.approval_request_approvers
   where approval_request_id = p_approval_request_id and removed_at is null;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_proj, now(), 'approval.sent',
    v_caller, 'user',
    'approval_request', p_approval_request_id, coalesce(v_title, 'approval'),
    jsonb_build_object('policy', v_policy),
    jsonb_build_object(
      'approval_request_id', p_approval_request_id,
      'roster', jsonb_build_object('wm_ids', v_wm_ids, 'sh_ids', v_sh_ids),
      'expires_at', v_expires_at,
      'policy', v_policy
    )
  );

  return p_approval_request_id;
end $$;

revoke all on function public.send_approval_request(uuid) from public;
revoke all on function public.send_approval_request(uuid) from anon;
revoke all on function public.send_approval_request(uuid) from authenticated;
grant execute on function public.send_approval_request(uuid) to authenticated, service_role;
