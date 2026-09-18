-- AUTH 009: activity_events_rls (final authorization migration)
--
-- Single SELECT policy on public.activity_events per §7 Group J:
--   admin OR (project-scoped event AND activity.view on that project).
--
-- Access follows CURRENT authorization. lign_project_role only returns roles
-- for participants with status='active', so revoked/removed participants and
-- revoked stakeholders lose access to historical project events immediately.
-- Unclaimed stakeholders (user_id NULL) cannot authenticate and therefore
-- have no path to visibility.
--
-- Workspace-level events (project_id IS NULL) are visible ONLY to workspace
-- admins. Project participants without admin role cannot see them.
--
-- No INSERT/UPDATE/DELETE policies — direct client writes remain closed.
-- Event emission continues via SECURITY DEFINER RPCs / triggers (owned by
-- postgres, which bypasses RLS). Existing V1 append-only triggers
-- (activity_events_no_update, activity_events_no_delete) remain
-- authoritative for defense in depth.
--
-- No new helpers, indexes, triggers, or RPCs. No schema changes.

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
