-- APP 016d — organisation membership makes colleagues visible to each other.
--
-- Found by testing the organisation people screen: it listed one row where two
-- were expected. lign_can_see_profile grants visibility through a shared
-- WORKSPACE membership or a shared PROJECT participation, and nothing else.
-- Organisation membership was not a path, so:
--
--   * an org admin added to the organisation but not yet to any workspace had
--     an invisible profile — to everyone, including the owner who just added
--     them;
--   * the organisation people screen therefore could not show the name or
--     email of the very people it exists to manage, and fell back to
--     "Unknown";
--   * the embedded profile read returns NULL rather than erroring, so this
--     would have shipped looking like a data problem rather than a policy one.
--
-- The new clause mirrors the workspace clause exactly, one level up: a shared
-- ACTIVE organisation membership makes two people visible to each other, with
-- the same 'active','invited','suspended' tolerance on the target so a
-- pending or suspended colleague still renders instead of vanishing.
--
-- CONSEQUENCE, accepted deliberately. A plain organisation `member` — who has
-- no workspace access at all — can now see the names and emails of everyone
-- else in the organisation. Inside one company that is a staff directory, and
-- it is the same bargain already struck at workspace level. It does NOT leak
-- across tenants: the join is on a shared organisation_id, so one
-- organisation's people stay invisible to another's.
--
-- Written as a flat clause, not a call to lign_is_org_member, for the reason
-- APP 016a documents: nested SECURITY DEFINER functions cannot be inlined,
-- and this function is on the read path of every screen that renders a name.

create or replace function public.lign_can_see_profile(p_target_profile_id uuid)
returns boolean
language sql
stable parallel safe security definer
set search_path to ''
as $function$
  select
    p_target_profile_id = auth.uid()
    or exists (
      select 1
        from public.workspace_members me
        join public.workspace_members them
          on them.workspace_id = me.workspace_id
       where me.user_id = auth.uid()
         and me.status = 'active'
         and them.user_id = p_target_profile_id
         and them.status in ('active','invited','suspended')
    )
    or exists (
      select 1
        from public.organization_members me
        join public.organization_members them
          on them.organization_id = me.organization_id
       where me.user_id = auth.uid()
         and me.status = 'active'
         and them.user_id = p_target_profile_id
         and them.status in ('active','invited','suspended')
    )
    or exists (
      select 1
        from public.project_participants pp_them
        left join public.workspace_members wm_them
               on wm_them.id = pp_them.workspace_member_id
        left join public.stakeholders sh_them
               on sh_them.id = pp_them.stakeholder_id
       where pp_them.status = 'active'
         and (
           (wm_them.user_id = p_target_profile_id
              and wm_them.status in ('active','invited','suspended'))
           or (sh_them.user_id = p_target_profile_id
              and sh_them.status = 'active')
         )
         and exists (
           select 1
             from public.project_participants pp_me
             left join public.workspace_members wm_me
                    on wm_me.id = pp_me.workspace_member_id
             left join public.stakeholders sh_me
                    on sh_me.id = pp_me.stakeholder_id
            where pp_me.project_id = pp_them.project_id
              and pp_me.status = 'active'
              and (wm_me.user_id = auth.uid()
                or sh_me.user_id = auth.uid())
         )
    );
$function$;