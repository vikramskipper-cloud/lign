-- AUTH 002: identity_tenancy_rls
--
-- RLS policies for the identity/tenancy tier:
--   profiles, workspaces, workspace_members, stakeholders, invitations.
--
-- Source of truth: docs/AUTHORIZATION_ARCHITECTURE.md §7 Groups A–C.
-- Helpers reused from AUTH 001; one small SECURITY DEFINER helper added
-- (lign_shares_project_with_stakeholder) because project_participants has RLS
-- enabled with no policies yet — an inline EXISTS would return no rows.
--
-- All policies TO authenticated only. No anon access. No permissive fallback.
-- Non-listed operations (INSERT/UPDATE/DELETE that aren't explicit here) have
-- no policy → RLS denies them. This is the intended block on direct writes;
-- membership/invitation lifecycle remains RPC-controlled.
--
-- Non-goals:
--   - AUTH 003 (projects/participants/collections) is NOT in this migration.
--   - No new RPCs. No storage/notifications/cron/realtime.
--   - No structural schema change; V1 lock intact.

------------------------------------------------------------------------------
-- 1. Helper: lign_shares_project_with_stakeholder(stakeholder_id) — DEFINER
------------------------------------------------------------------------------
-- True if the caller is an active project_participant in the same project as
-- the target stakeholder (also active). Wraps project_participants access in
-- DEFINER so the stakeholders RLS policy can reference it before AUTH 003.

create or replace function public.lign_shares_project_with_stakeholder(p_stakeholder_id uuid)
returns boolean
language sql
stable
parallel safe
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.project_participants pp_them
      join public.project_participants pp_me
        on pp_me.project_id = pp_them.project_id
       and pp_me.status = 'active'
      left join public.workspace_members wm_me
             on wm_me.id = pp_me.workspace_member_id
             and wm_me.status = 'active'
      left join public.stakeholders sh_me
             on sh_me.id = pp_me.stakeholder_id
             and sh_me.status = 'active'
     where pp_them.stakeholder_id = p_stakeholder_id
       and pp_them.status = 'active'
       and (wm_me.user_id = auth.uid() or sh_me.user_id = auth.uid())
  );
$$;

comment on function public.lign_shares_project_with_stakeholder(uuid) is
  'True if the caller shares an active project with the target stakeholder (either identity path). SECURITY DEFINER — used by stakeholders RLS to bypass empty-policy state on project_participants until AUTH 003.';

revoke all on function public.lign_shares_project_with_stakeholder(uuid) from public;
revoke all on function public.lign_shares_project_with_stakeholder(uuid) from anon;
grant execute on function public.lign_shares_project_with_stakeholder(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 2. profiles policies (Group A)
------------------------------------------------------------------------------
--   SELECT: lign_can_see_profile(id) — self, workspace-shared, project-shared.
--   UPDATE: id = auth.uid() (identity trigger already blocks id/email).
--   INSERT/DELETE: no policy → denied.

drop policy if exists profiles_select_visible on public.profiles;
create policy profiles_select_visible on public.profiles
  as permissive
  for select
  to authenticated
  using (public.lign_can_see_profile(id));

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  as permissive
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

------------------------------------------------------------------------------
-- 3. workspaces policies (Group B)
------------------------------------------------------------------------------
--   SELECT: lign_is_workspace_member(id) OR lign_is_active_stakeholder(id).
--   UPDATE: lign_is_workspace_admin(id) both USING and WITH CHECK.
--   INSERT: no policy → denied (create_workspace RPC only).
--   DELETE: no policy → denied.

drop policy if exists workspaces_select_member_or_stakeholder on public.workspaces;
create policy workspaces_select_member_or_stakeholder on public.workspaces
  as permissive
  for select
  to authenticated
  using (
    public.lign_is_workspace_member(id)
    or public.lign_is_active_stakeholder(id)
  );

drop policy if exists workspaces_update_admin on public.workspaces;
create policy workspaces_update_admin on public.workspaces
  as permissive
  for update
  to authenticated
  using (public.lign_is_workspace_admin(id))
  with check (public.lign_is_workspace_admin(id));

------------------------------------------------------------------------------
-- 4. workspace_members policy (Group C)
------------------------------------------------------------------------------
--   SELECT: lign_is_workspace_member(workspace_id).
--     Stakeholders do NOT see the raw workspace_members roster; they see
--     individual member profiles via lign_can_see_profile on `profiles` only
--     (§7 Group C, explicit).
--   INSERT/UPDATE/DELETE: no policy → denied (RPC-only lifecycle).

drop policy if exists workspace_members_select_workspace on public.workspace_members;
create policy workspace_members_select_workspace on public.workspace_members
  as permissive
  for select
  to authenticated
  using (public.lign_is_workspace_member(workspace_id));

------------------------------------------------------------------------------
-- 5. stakeholders policy (Group C)
------------------------------------------------------------------------------
--   SELECT: workspace admin OR own claimed identity OR shared active project.
--   INSERT/UPDATE/DELETE: no policy → denied (RPC-only lifecycle).

drop policy if exists stakeholders_select_admin_self_or_shared_project on public.stakeholders;
create policy stakeholders_select_admin_self_or_shared_project on public.stakeholders
  as permissive
  for select
  to authenticated
  using (
    public.lign_is_workspace_admin(workspace_id)
    or user_id = auth.uid()
    or public.lign_shares_project_with_stakeholder(id)
  );

------------------------------------------------------------------------------
-- 6. invitations policy (Group C)
------------------------------------------------------------------------------
--   SELECT: workspace admin OR the authenticated invitee (email match).
--   INSERT/UPDATE/DELETE: no policy → denied (RPC-only lifecycle).
-- auth.email() returns the JWT email claim as text; cast to citext for a
-- case-insensitive compare against invitations.email.

drop policy if exists invitations_select_admin_or_invitee on public.invitations;
create policy invitations_select_admin_or_invitee on public.invitations
  as permissive
  for select
  to authenticated
  using (
    public.lign_is_workspace_admin(workspace_id)
    or email = (auth.email())::extensions.citext
  );
