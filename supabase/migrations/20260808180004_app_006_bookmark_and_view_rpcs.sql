-- APP 006 RPCs part 5: bookmarks + saved views

create or replace function public.toggle_bookmark(
  p_subject_kind text,
  p_subject_id   uuid,
  p_workspace_id uuid
)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_existing uuid; v_bookmarked boolean;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'toggle_bookmark: authentication required' using errcode='42501'; end if;
  if p_subject_kind is null or p_subject_id is null or p_workspace_id is null then
    raise exception 'toggle_bookmark: all params required' using errcode='22004';
  end if;
  if not public.lign_is_workspace_member(p_workspace_id) then
    raise exception 'toggle_bookmark: not a workspace member' using errcode='42501';
  end if;

  select id into v_existing from public.user_bookmarks
   where user_id = v_caller and subject_kind = p_subject_kind and subject_id = p_subject_id;

  if v_existing is not null then
    delete from public.user_bookmarks where id = v_existing;
    v_bookmarked := false;
  else
    insert into public.user_bookmarks (user_id, workspace_id, subject_kind, subject_id)
    values (v_caller, p_workspace_id, p_subject_kind, p_subject_id);
    v_bookmarked := true;
  end if;
  return v_bookmarked;
end $$;
revoke all on function public.toggle_bookmark(text, uuid, uuid) from public;
revoke all on function public.toggle_bookmark(text, uuid, uuid) from anon;
grant execute on function public.toggle_bookmark(text, uuid, uuid) to authenticated, service_role;

create or replace function public.save_dashboard_view(
  p_view_id      uuid,
  p_workspace_id uuid,
  p_scope        text,
  p_name         text,
  p_definition   jsonb,
  p_visibility   text default 'private'
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_id uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'save_dashboard_view: authentication required' using errcode='42501'; end if;
  if p_workspace_id is null or p_scope is null or p_name is null or p_definition is null then
    raise exception 'save_dashboard_view: workspace_id, scope, name, definition required' using errcode='22004';
  end if;
  if p_visibility is null or p_visibility <> 'private' then
    raise exception 'save_dashboard_view: v1 enforces visibility=private only' using errcode='22023';
  end if;
  if not public.lign_is_workspace_member(p_workspace_id) then
    raise exception 'save_dashboard_view: not a workspace member' using errcode='42501';
  end if;

  if p_view_id is null then
    insert into public.user_saved_views (user_id, workspace_id, scope, name, definition, visibility)
    values (v_caller, p_workspace_id, p_scope, p_name, p_definition, 'private')
    returning id into v_id;
  else
    update public.user_saved_views
       set name = p_name, definition = p_definition
     where id = p_view_id and user_id = v_caller
    returning id into v_id;
    if v_id is null then
      raise exception 'save_dashboard_view: view not found or not owned by caller' using errcode='23503';
    end if;
  end if;
  return v_id;
end $$;
revoke all on function public.save_dashboard_view(uuid, uuid, text, text, jsonb, text) from public;
revoke all on function public.save_dashboard_view(uuid, uuid, text, text, jsonb, text) from anon;
grant execute on function public.save_dashboard_view(uuid, uuid, text, text, jsonb, text) to authenticated, service_role;

create or replace function public.delete_dashboard_view(p_view_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_count int;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'delete_dashboard_view: authentication required' using errcode='42501'; end if;
  delete from public.user_saved_views where id = p_view_id and user_id = v_caller;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception 'delete_dashboard_view: view not found or not owned by caller' using errcode='23503';
  end if;
end $$;
revoke all on function public.delete_dashboard_view(uuid) from public;
revoke all on function public.delete_dashboard_view(uuid) from anon;
grant execute on function public.delete_dashboard_view(uuid) to authenticated, service_role;
