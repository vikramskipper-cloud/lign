-- AUTH 002 addendum: wrap direct auth.<function>() calls in (select ...) so
-- Postgres evaluates them once per query, not once per row (initplan best
-- practice per Supabase 0003_auth_rls_initplan lint). Semantics unchanged.
--
-- Applies to the three AUTH 002 policies that referenced auth.* directly:
--   profiles.profiles_update_own
--   stakeholders.stakeholders_select_admin_self_or_shared_project
--   invitations.invitations_select_admin_or_invitee
--
-- The other AUTH 002 policies only invoke helper functions (lign_*), so they
-- do not trigger the initplan lint.

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  as permissive
  for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists stakeholders_select_admin_self_or_shared_project on public.stakeholders;
create policy stakeholders_select_admin_self_or_shared_project on public.stakeholders
  as permissive
  for select
  to authenticated
  using (
    public.lign_is_workspace_admin(workspace_id)
    or user_id = (select auth.uid())
    or public.lign_shares_project_with_stakeholder(id)
  );

drop policy if exists invitations_select_admin_or_invitee on public.invitations;
create policy invitations_select_admin_or_invitee on public.invitations
  as permissive
  for select
  to authenticated
  using (
    public.lign_is_workspace_admin(workspace_id)
    or email = ((select auth.email()))::extensions.citext
  );
