-- APP 006 T-CRIT-1 fix (audit-mandated, minimal):
--
-- The chain-immutability trigger (Migration 012) rejects any UPDATE that
-- changes root_review_id, including the NULL → self initialization step
-- previously performed inside create_review. Fix: pre-compute the review id
-- with gen_random_uuid() and INSERT root_review_id = id in a single statement
-- so no post-INSERT UPDATE is required. Trigger, chain model, and API remain
-- untouched.

create or replace function public.create_review(
  p_project_id                 uuid,
  p_design_asset_id            uuid,
  p_version_id                 uuid,
  p_title                      text,
  p_description                text        default null,
  p_reviewer_wm_ids            uuid[]      default '{}'::uuid[],
  p_reviewer_sh_ids            uuid[]      default '{}'::uuid[],
  p_due_at                     timestamptz default null,
  p_open                       boolean     default false,
  p_coordinator_profile_id     uuid        default null,
  p_policy                     text        default 'parallel',
  p_quorum_min                 integer     default null,
  p_require_comments_resolved  boolean     default false,
  p_reviewer_required          boolean[]   default '{}'::boolean[],
  p_reviewer_sequence_index    integer[]   default '{}'::integer[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller       uuid;
  v_workspace_id uuid;
  v_v_asset      uuid;
  v_v_status     text;
  v_da_project   uuid;
  v_review_id    uuid;
  v_wm_id        uuid;
  v_sh_id        uuid;
  v_reviewer_ct  int := 0;
  v_wm_count     int := coalesce(array_length(p_reviewer_wm_ids, 1), 0);
  v_sh_count     int := coalesce(array_length(p_reviewer_sh_ids, 1), 0);
  v_req_count    int := coalesce(array_length(p_reviewer_required, 1), 0);
  v_seq_count    int := coalesce(array_length(p_reviewer_sequence_index, 1), 0);
  v_i            int;
  v_required     boolean;
  v_sequence     int;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'create_review: authentication required' using errcode='42501';
  end if;
  if p_project_id is null or p_design_asset_id is null or p_version_id is null then
    raise exception 'create_review: ids required' using errcode='22004';
  end if;
  if p_title is null or length(trim(p_title))=0 then
    raise exception 'create_review: title required' using errcode='22004';
  end if;
  if p_policy is null or p_policy not in ('parallel','sequential','quorum') then
    raise exception 'create_review: invalid policy %', coalesce(p_policy,'(null)') using errcode='22023';
  end if;
  if p_policy = 'quorum' and (p_quorum_min is null or p_quorum_min <= 0) then
    raise exception 'create_review: quorum_min required and positive when policy=quorum' using errcode='22004';
  end if;
  if v_req_count > 0 and v_req_count <> v_wm_count + v_sh_count then
    raise exception 'create_review: p_reviewer_required length must match total reviewer count' using errcode='22023';
  end if;
  if v_seq_count > 0 and v_seq_count <> v_wm_count + v_sh_count then
    raise exception 'create_review: p_reviewer_sequence_index length must match total reviewer count' using errcode='22023';
  end if;

  select project_id, workspace_id into v_da_project, v_workspace_id
    from public.design_assets where id = p_design_asset_id;
  if v_workspace_id is null then
    raise exception 'create_review: design_asset % not found', p_design_asset_id using errcode='23503';
  end if;
  if v_da_project <> p_project_id then
    raise exception 'create_review: asset does not belong to project %', p_project_id using errcode='23514';
  end if;

  select design_asset_id, status into v_v_asset, v_v_status
    from public.asset_versions where id = p_version_id;
  if v_v_asset is null then
    raise exception 'create_review: version % not found', p_version_id using errcode='23503';
  end if;
  if v_v_asset <> p_design_asset_id then
    raise exception 'create_review: version does not belong to asset' using errcode='23514';
  end if;
  if v_v_status <> 'published' then
    raise exception 'create_review: version must be published (is %)', v_v_status using errcode='23514';
  end if;

  if not public.lign_has_capability(p_project_id, v_workspace_id, 'review.create') then
    raise exception 'create_review: forbidden (review.create)' using errcode='42501';
  end if;

  if p_coordinator_profile_id is not null then
    if not exists (
      select 1
        from public.project_participants pp
        left join public.workspace_members wm on wm.id = pp.workspace_member_id
        left join public.stakeholders sh on sh.id = pp.stakeholder_id
       where pp.project_id = p_project_id
         and pp.status = 'active'
         and (wm.user_id = p_coordinator_profile_id or sh.user_id = p_coordinator_profile_id)
    ) then
      raise exception 'create_review: coordinator % is not an active project participant', p_coordinator_profile_id
        using errcode='23514';
    end if;
  end if;

  -- Pre-compute id so root_review_id = self can be set in a single INSERT
  -- (no post-INSERT UPDATE needed; chain-immutability trigger unaffected).
  v_review_id := gen_random_uuid();

  insert into public.reviews (
    id,
    workspace_id, project_id, design_asset_id, version_id,
    title, description, status, due_at, created_by_profile_id,
    round_number, parent_review_id, root_review_id,
    coordinator_profile_id, policy, quorum_min, require_comments_resolved
  ) values (
    v_review_id,
    v_workspace_id, p_project_id, p_design_asset_id, p_version_id,
    p_title, p_description, 'draft', p_due_at, v_caller,
    1, null, v_review_id,
    p_coordinator_profile_id, p_policy, p_quorum_min, p_require_comments_resolved
  );

  for v_i in 1..v_wm_count loop
    v_wm_id := p_reviewer_wm_ids[v_i];
    if not exists (
      select 1 from public.workspace_members
       where id = v_wm_id and workspace_id = v_workspace_id and status = 'active'
    ) then
      raise exception 'create_review: workspace_member % not found in workspace (active)', v_wm_id using errcode='23503';
    end if;
    v_required := coalesce(p_reviewer_required[v_i], true);
    v_sequence := coalesce(p_reviewer_sequence_index[v_i], 0);
    insert into public.review_participants (
      workspace_id, review_id, workspace_member_id, status, assigned_at,
      required, sequence_index
    )
    values (
      v_workspace_id, v_review_id, v_wm_id, 'pending', now(),
      v_required, v_sequence
    );
    v_reviewer_ct := v_reviewer_ct + 1;
  end loop;

  for v_i in 1..v_sh_count loop
    v_sh_id := p_reviewer_sh_ids[v_i];
    if not exists (
      select 1 from public.stakeholders
       where id = v_sh_id and workspace_id = v_workspace_id and status in ('active','invited')
    ) then
      raise exception 'create_review: stakeholder % not found in workspace', v_sh_id using errcode='23503';
    end if;
    v_required := coalesce(p_reviewer_required[v_wm_count + v_i], true);
    v_sequence := coalesce(p_reviewer_sequence_index[v_wm_count + v_i], 0);
    insert into public.review_participants (
      workspace_id, review_id, stakeholder_id, status, assigned_at,
      required, sequence_index
    )
    values (
      v_workspace_id, v_review_id, v_sh_id, 'pending', now(),
      v_required, v_sequence
    );
    v_reviewer_ct := v_reviewer_ct + 1;
  end loop;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_workspace_id, p_project_id, now(), 'review.created',
    v_caller, 'user',
    'review', v_review_id, p_title,
    jsonb_build_object('title', p_title, 'version_id', p_version_id),
    jsonb_build_object(
      'round_number', 1,
      'root_review_id', v_review_id,
      'coordinator_profile_id', p_coordinator_profile_id,
      'policy', p_policy,
      'quorum_min', p_quorum_min
    )
  );

  if p_open then
    if v_reviewer_ct < 1 then
      raise exception 'create_review: cannot open with zero reviewers' using errcode='23514';
    end if;
    update public.reviews set status = 'open' where id = v_review_id;

    insert into public.activity_events (
      workspace_id, project_id, occurred_at, event_type,
      actor_profile_id, actor_kind,
      subject_kind, subject_id, subject_label, subject_snapshot, payload
    ) values (
      v_workspace_id, p_project_id, now(), 'review.opened',
      v_caller, 'user',
      'review', v_review_id, p_title,
      jsonb_build_object('title', p_title, 'reviewer_count', v_reviewer_ct),
      jsonb_build_object(
        'round_number', 1,
        'roster', jsonb_build_object(
          'wm_ids', to_jsonb(coalesce(p_reviewer_wm_ids, '{}'::uuid[])),
          'sh_ids', to_jsonb(coalesce(p_reviewer_sh_ids, '{}'::uuid[]))
        ),
        'due_at', p_due_at
      )
    );
  end if;

  return v_review_id;
end $$;

revoke all on function public.create_review(
  uuid, uuid, uuid, text, text, uuid[], uuid[], timestamptz, boolean,
  uuid, text, integer, boolean, boolean[], integer[]
) from public;
revoke all on function public.create_review(
  uuid, uuid, uuid, text, text, uuid[], uuid[], timestamptz, boolean,
  uuid, text, integer, boolean, boolean[], integer[]
) from anon;
grant execute on function public.create_review(
  uuid, uuid, uuid, text, text, uuid[], uuid[], timestamptz, boolean,
  uuid, text, integer, boolean, boolean[], integer[]
) to authenticated, service_role;
