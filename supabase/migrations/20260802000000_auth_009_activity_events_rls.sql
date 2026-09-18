drop policy if exists activity_events_select on public.activity_events;
create policy activity_events_select on public.activity_events
  as permissive
  for select
  to authenticated
  using (
    public.lign_is_workspace_admin(workspace_id)
    or (
      project_id is not null
      and public.lign_has_capability(project_id, workspace_id, 'activity.view')
    )
  );