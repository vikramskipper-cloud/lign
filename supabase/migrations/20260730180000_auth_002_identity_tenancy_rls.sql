-- AUTH 002: identity_tenancy_rls

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

drop policy if exists workspace_members_select_workspace on public.workspace_members;
create policy workspace_members_select_workspace on public.workspace_members
  as permissive
  for select
  to authenticated
  using (public.lign_is_workspace_member(workspace_id));

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

drop policy if exists invitations_select_admin_or_invitee on public.invitations;
create policy invitations_select_admin_or_invitee on public.invitations
  as permissive
  for select
  to authenticated
  using (
    public.lign_is_workspace_admin(workspace_id)
    or email = (auth.email())::extensions.citext
  );