-- AUTH 005 (apply)

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
    else null
  end;
$$;
revoke all on function public.lign_resolve_comment_target_project(uuid,uuid,uuid,uuid,uuid,uuid,uuid) from public;
revoke all on function public.lign_resolve_comment_target_project(uuid,uuid,uuid,uuid,uuid,uuid,uuid) from anon;
grant execute on function public.lign_resolve_comment_target_project(uuid,uuid,uuid,uuid,uuid,uuid,uuid) to authenticated, service_role;

create or replace function public.enforce_comment_write_gate()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.id is distinct from old.id then raise exception 'comments.id immutable' using errcode='23514'; end if;
  if new.workspace_id is distinct from old.workspace_id then raise exception 'comments.workspace_id immutable' using errcode='23514'; end if;
  if new.author_profile_id is distinct from old.author_profile_id then raise exception 'comments.author_profile_id immutable' using errcode='23514'; end if;
  if new.parent_comment_id is distinct from old.parent_comment_id then raise exception 'comments.parent_comment_id immutable' using errcode='23514'; end if;
  if new.target_version_id is distinct from old.target_version_id
     or new.target_review_id is distinct from old.target_review_id
     or new.target_annotation_id is distinct from old.target_annotation_id
     or new.target_change_id is distinct from old.target_change_id
     or new.target_decision_id is distinct from old.target_decision_id
     or new.target_design_asset_id is distinct from old.target_design_asset_id
     or new.target_approval_request_id is distinct from old.target_approval_request_id
  then raise exception 'comments.target immutable' using errcode='23514'; end if;
  if new.created_at is distinct from old.created_at then raise exception 'comments.created_at immutable' using errcode='23514'; end if;
  if new.body is distinct from old.body then
    if coalesce(current_setting('lign.allow_comment_body_write', true), '') <> 'true' then
      raise exception 'comments.body may only be modified via edit_own_comment RPC (id=%)', old.id using errcode='42501';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists comments_write_gate on public.comments;
create trigger comments_write_gate before update on public.comments
  for each row execute function public.enforce_comment_write_gate();

create or replace function public.enforce_annotation_meta_immutable()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.id is distinct from old.id then raise exception 'annotations.id immutable' using errcode='23514'; end if;
  if new.workspace_id is distinct from old.workspace_id then raise exception 'annotations.workspace_id immutable' using errcode='23514'; end if;
  if new.author_profile_id is distinct from old.author_profile_id then raise exception 'annotations.author_profile_id immutable' using errcode='23514'; end if;
  return new;
end $$;
drop trigger if exists annotations_meta_immutable on public.annotations;
create trigger annotations_meta_immutable before update on public.annotations
  for each row execute function public.enforce_annotation_meta_immutable();

create or replace function public.create_review(
  p_project_id uuid, p_design_asset_id uuid, p_version_id uuid,
  p_title text, p_description text default null,
  p_reviewer_wm_ids uuid[] default '{}'::uuid[],
  p_reviewer_sh_ids uuid[] default '{}'::uuid[],
  p_due_at timestamptz default null, p_open boolean default false
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_v_asset uuid; v_v_status text;
        v_da_project uuid; v_review_id uuid; v_wm_id uuid; v_sh_id uuid; v_reviewer_ct int := 0;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'create_review: auth required' using errcode='42501'; end if;
  if p_project_id is null or p_design_asset_id is null or p_version_id is null then
    raise exception 'create_review: ids required' using errcode='22004';
  end if;
  if p_title is null or length(trim(p_title))=0 then raise exception 'create_review: title required' using errcode='22004'; end if;

  select project_id, workspace_id into v_da_project, v_workspace_id
    from public.design_assets where id = p_design_asset_id;
  if v_workspace_id is null then raise exception 'create_review: asset not found' using errcode='23503'; end if;
  if v_da_project <> p_project_id then raise exception 'create_review: asset does not belong to project' using errcode='23514'; end if;

  select design_asset_id, status into v_v_asset, v_v_status
    from public.asset_versions where id = p_version_id;
  if v_v_asset is null then raise exception 'create_review: version not found' using errcode='23503'; end if;
  if v_v_asset <> p_design_asset_id then raise exception 'create_review: version does not belong to asset' using errcode='23514'; end if;
  if v_v_status <> 'published' then raise exception 'create_review: version must be published' using errcode='23514'; end if;

  if not public.lign_has_capability(p_project_id, v_workspace_id, 'review.create') then
    raise exception 'create_review: forbidden (review.create)' using errcode='42501';
  end if;

  insert into public.reviews (workspace_id, project_id, design_asset_id, version_id, title, description, status, due_at, created_by_profile_id)
  values (v_workspace_id, p_project_id, p_design_asset_id, p_version_id, p_title, p_description, 'draft', p_due_at, v_caller)
  returning id into v_review_id;

  foreach v_wm_id in array coalesce(p_reviewer_wm_ids, '{}'::uuid[]) loop
    if not exists (select 1 from public.workspace_members where id = v_wm_id and workspace_id = v_workspace_id and status = 'active') then
      raise exception 'create_review: workspace_member % not found in workspace (active)', v_wm_id using errcode='23503';
    end if;
    insert into public.review_participants (workspace_id, review_id, workspace_member_id, status, assigned_at)
    values (v_workspace_id, v_review_id, v_wm_id, 'pending', now());
    v_reviewer_ct := v_reviewer_ct + 1;
  end loop;

  foreach v_sh_id in array coalesce(p_reviewer_sh_ids, '{}'::uuid[]) loop
    if not exists (select 1 from public.stakeholders where id = v_sh_id and workspace_id = v_workspace_id and status in ('active','invited')) then
      raise exception 'create_review: stakeholder % not found in workspace', v_sh_id using errcode='23503';
    end if;
    insert into public.review_participants (workspace_id, review_id, stakeholder_id, status, assigned_at)
    values (v_workspace_id, v_review_id, v_sh_id, 'pending', now());
    v_reviewer_ct := v_reviewer_ct + 1;
  end loop;

  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_workspace_id, p_project_id, now(), 'review.created', v_caller, 'user', 'review', v_review_id, p_title, jsonb_build_object('title', p_title, 'version_id', p_version_id), '{}'::jsonb);

  if p_open then
    if v_reviewer_ct < 1 then raise exception 'create_review: cannot open with zero reviewers' using errcode='23514'; end if;
    update public.reviews set status = 'open' where id = v_review_id;
    insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
    values (v_workspace_id, p_project_id, now(), 'review.opened', v_caller, 'user', 'review', v_review_id, p_title, jsonb_build_object('title', p_title, 'reviewer_count', v_reviewer_ct), '{}'::jsonb);
  end if;
  return v_review_id;
end $$;
revoke all on function public.create_review(uuid,uuid,uuid,text,text,uuid[],uuid[],timestamptz,boolean) from public;
revoke all on function public.create_review(uuid,uuid,uuid,text,text,uuid[],uuid[],timestamptz,boolean) from anon;
grant execute on function public.create_review(uuid,uuid,uuid,text,text,uuid[],uuid[],timestamptz,boolean) to authenticated, service_role;

create or replace function public.respond_to_review(p_review_id uuid, p_response text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_project_id uuid; v_r_status text; v_pp_id uuid; v_pp_status text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'respond_to_review: auth required' using errcode='42501'; end if;
  if p_response not in ('commented','signed_off','declined') then raise exception 'respond_to_review: invalid response' using errcode='22023'; end if;

  select workspace_id, project_id, status into v_workspace_id, v_project_id, v_r_status
    from public.reviews where id = p_review_id for update;
  if v_workspace_id is null then raise exception 'respond_to_review: review not found' using errcode='23503'; end if;
  if v_r_status not in ('open','in_progress') then raise exception 'respond_to_review: review is % (must be open/in_progress)', v_r_status using errcode='23514'; end if;

  select rp.id, rp.status into v_pp_id, v_pp_status
    from public.review_participants rp
    left join public.workspace_members wm on wm.id = rp.workspace_member_id and wm.status = 'active'
    left join public.stakeholders sh on sh.id = rp.stakeholder_id and sh.status = 'active'
   where rp.review_id = p_review_id
     and (wm.user_id = v_caller or sh.user_id = v_caller);
  if v_pp_id is null then raise exception 'respond_to_review: caller is not an assigned reviewer' using errcode='42501'; end if;
  if v_pp_status <> 'pending' then raise exception 'respond_to_review: reviewer slot already responded (%)', v_pp_status using errcode='23514'; end if;

  update public.review_participants set status = p_response, responded_at = now() where id = v_pp_id;
  if v_r_status = 'open' then update public.reviews set status = 'in_progress' where id = p_review_id; end if;

  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_workspace_id, v_project_id, now(), 'review.reviewer_responded', v_caller, 'user', 'review_participant', v_pp_id, p_response, jsonb_build_object('review_id', p_review_id, 'reviewer_status', p_response), '{}'::jsonb);
  return v_pp_id;
end $$;
revoke all on function public.respond_to_review(uuid, text) from public;
revoke all on function public.respond_to_review(uuid, text) from anon;
grant execute on function public.respond_to_review(uuid, text) to authenticated, service_role;

create or replace function public.complete_review(p_review_id uuid, p_terminal text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_project_id uuid; v_r_status text; v_title text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'complete_review: auth required' using errcode='42501'; end if;
  if p_terminal not in ('completed','cancelled') then raise exception 'complete_review: invalid terminal' using errcode='22023'; end if;

  select workspace_id, project_id, status, title into v_workspace_id, v_project_id, v_r_status, v_title
    from public.reviews where id = p_review_id for update;
  if v_workspace_id is null then raise exception 'complete_review: review not found' using errcode='23503'; end if;
  if v_r_status not in ('draft','open','in_progress') then raise exception 'complete_review: review is % (already terminal)', v_r_status using errcode='23514'; end if;
  if not public.lign_has_capability(v_project_id, v_workspace_id, 'review.complete') then
    raise exception 'complete_review: forbidden (review.complete)' using errcode='42501';
  end if;

  if p_terminal = 'completed' then
    update public.reviews set status='completed', completed_at=now() where id = p_review_id;
  else
    update public.reviews set status='cancelled', cancelled_at=now() where id = p_review_id;
  end if;

  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_workspace_id, v_project_id, now(),
    case when p_terminal='completed' then 'review.completed' else 'review.cancelled' end,
    v_caller, 'user', 'review', p_review_id, v_title, jsonb_build_object('title', v_title, 'terminal', p_terminal), '{}'::jsonb);
  return p_review_id;
end $$;
revoke all on function public.complete_review(uuid, text) from public;
revoke all on function public.complete_review(uuid, text) from anon;
grant execute on function public.complete_review(uuid, text) to authenticated, service_role;

create or replace function public.edit_own_comment(p_comment_id uuid, p_new_body text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_author uuid; v_old_body text; v_deleted_at timestamptz;
        v_target_review_id uuid; v_target_v_id uuid; v_target_a_id uuid; v_target_c_id uuid;
        v_target_d_id uuid; v_target_da_id uuid; v_target_ar_id uuid;
        v_project_id uuid; v_review_status text; v_next_revision int; v_edit_id uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'edit_own_comment: auth required' using errcode='42501'; end if;
  if p_new_body is null or length(p_new_body) = 0 then raise exception 'edit_own_comment: body required' using errcode='22004'; end if;

  select workspace_id, author_profile_id, body, deleted_at,
         target_version_id, target_review_id, target_annotation_id,
         target_change_id, target_decision_id, target_design_asset_id, target_approval_request_id
    into v_workspace_id, v_author, v_old_body, v_deleted_at,
         v_target_v_id, v_target_review_id, v_target_a_id,
         v_target_c_id, v_target_d_id, v_target_da_id, v_target_ar_id
    from public.comments where id = p_comment_id for update;
  if v_workspace_id is null then raise exception 'edit_own_comment: comment not found' using errcode='23503'; end if;
  if v_author <> v_caller then raise exception 'edit_own_comment: not the author' using errcode='42501'; end if;
  if v_deleted_at is not null then raise exception 'edit_own_comment: comment soft-deleted' using errcode='23514'; end if;

  v_project_id := public.lign_resolve_comment_target_project(
    v_target_v_id, v_target_review_id, v_target_a_id, v_target_c_id, v_target_d_id, v_target_da_id, v_target_ar_id);
  if v_project_id is null then raise exception 'edit_own_comment: target has no project scope' using errcode='42501'; end if;
  if not public.lign_has_capability(v_project_id, v_workspace_id, 'comment.edit_own') then
    raise exception 'edit_own_comment: forbidden (comment.edit_own)' using errcode='42501';
  end if;

  if v_target_review_id is not null then
    select status into v_review_status from public.reviews where id = v_target_review_id;
    if v_review_status in ('completed','cancelled') then
      raise exception 'edit_own_comment: containing review is % (edits denied)', v_review_status using errcode='42501';
    end if;
  end if;

  if v_old_body = p_new_body then return p_comment_id; end if;

  select coalesce(max(revision), 0) + 1 into v_next_revision
    from public.comment_edits where comment_id = p_comment_id;

  insert into public.comment_edits (workspace_id, comment_id, revision, previous_body, edited_by_profile_id, edited_at)
  values (v_workspace_id, p_comment_id, v_next_revision, v_old_body, v_caller, now())
  returning id into v_edit_id;

  perform set_config('lign.allow_comment_body_write', 'true', true);
  update public.comments set body = p_new_body where id = p_comment_id;

  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_workspace_id, v_project_id, now(), 'comment.edited', v_caller, 'user', 'comment', p_comment_id, 'rev '||v_next_revision, jsonb_build_object('revision', v_next_revision), '{}'::jsonb);
  return p_comment_id;
end $$;
revoke all on function public.edit_own_comment(uuid, text) from public;
revoke all on function public.edit_own_comment(uuid, text) from anon;
grant execute on function public.edit_own_comment(uuid, text) to authenticated, service_role;

drop policy if exists reviews_select on public.reviews;
create policy reviews_select on public.reviews as permissive for select to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'review.view'));

drop policy if exists review_participants_select on public.review_participants;
create policy review_participants_select on public.review_participants as permissive for select to authenticated
  using (
    exists (select 1 from public.reviews r
      where r.id = review_participants.review_id
        and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view'))
  );

drop policy if exists comments_select on public.comments;
create policy comments_select on public.comments as permissive for select to authenticated
  using (
    public.lign_has_capability(
      public.lign_resolve_comment_target_project(target_version_id, target_review_id, target_annotation_id, target_change_id, target_decision_id, target_design_asset_id, target_approval_request_id),
      workspace_id, 'comment.view')
  );

drop policy if exists comments_insert on public.comments;
create policy comments_insert on public.comments as permissive for insert to authenticated
  with check (
    author_profile_id = (select auth.uid())
    and public.lign_has_capability(
      public.lign_resolve_comment_target_project(target_version_id, target_review_id, target_annotation_id, target_change_id, target_decision_id, target_design_asset_id, target_approval_request_id),
      workspace_id, 'comment.create')
  );

drop policy if exists comments_update on public.comments;
create policy comments_update on public.comments as permissive for update to authenticated
  using (
    public.lign_has_capability(
      public.lign_resolve_comment_target_project(target_version_id, target_review_id, target_annotation_id, target_change_id, target_decision_id, target_design_asset_id, target_approval_request_id),
      workspace_id, 'comment.view')
  )
  with check (
    public.lign_has_capability(
      public.lign_resolve_comment_target_project(target_version_id, target_review_id, target_annotation_id, target_change_id, target_decision_id, target_design_asset_id, target_approval_request_id),
      workspace_id, 'comment.resolve')
    or (
      author_profile_id = (select auth.uid())
      and public.lign_has_capability(
        public.lign_resolve_comment_target_project(target_version_id, target_review_id, target_annotation_id, target_change_id, target_decision_id, target_design_asset_id, target_approval_request_id),
        workspace_id, 'comment.edit_own')
    )
  );

drop policy if exists comment_edits_select on public.comment_edits;
create policy comment_edits_select on public.comment_edits as permissive for select to authenticated
  using (
    exists (select 1 from public.comments c
      where c.id = comment_edits.comment_id
        and public.lign_has_capability(
          public.lign_resolve_comment_target_project(c.target_version_id, c.target_review_id, c.target_annotation_id, c.target_change_id, c.target_decision_id, c.target_design_asset_id, c.target_approval_request_id),
          c.workspace_id, 'comment.view'))
  );

drop policy if exists annotations_select on public.annotations;
create policy annotations_select on public.annotations as permissive for select to authenticated
  using (
    public.lign_has_capability(
      (select project_id from public.asset_versions where id = annotations.asset_version_id),
      workspace_id, 'annotation.view')
  );

drop policy if exists annotations_insert on public.annotations;
create policy annotations_insert on public.annotations as permissive for insert to authenticated
  with check (
    author_profile_id = (select auth.uid())
    and public.lign_has_capability(
      (select project_id from public.asset_versions where id = asset_version_id),
      workspace_id, 'annotation.create')
  );

drop policy if exists annotations_update on public.annotations;
create policy annotations_update on public.annotations as permissive for update to authenticated
  using (
    public.lign_has_capability(
      (select project_id from public.asset_versions where id = annotations.asset_version_id),
      workspace_id, 'annotation.resolve')
  )
  with check (
    public.lign_has_capability(
      (select project_id from public.asset_versions where id = annotations.asset_version_id),
      workspace_id, 'annotation.resolve')
  );