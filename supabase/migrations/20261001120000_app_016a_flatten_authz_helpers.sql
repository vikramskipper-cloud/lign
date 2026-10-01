-- APP 016a — flatten the two widened authorization helpers.
--
-- APP 015 claimed these added "a second index probe" and admitted the cost was
-- unmeasured. Measured, with the workspace id resolved outside the timed loop:
--
--   membership-only (pre-APP 015)            17.0 us/call
--   widened, membership clause HITS          17.7 us/call   (+4%)
--   widened, membership clause MISSES       246.4 us/call   (14x)
--   this version, membership clause MISSES   33.5 us/call
--
-- The cost is not the probe, it is the nesting. A SECURITY DEFINER function
-- cannot be inlined by the planner, so lign_is_workspace_member calling
-- lign_org_of_workspace calling lign_is_org_admin pays three full function
-- invocations each with its own snapshot. One query over a join pays one.
--
-- This is much worse than "org admins pay it". RLS evaluates its policy per
-- candidate row and the membership clause misses on every row you cannot see,
-- so a user holding one of fifty workspaces took the 246 us path forty-nine
-- times on every list query.
--
-- lign_is_org_member, lign_is_org_admin and lign_org_of_workspace all stay:
-- the policies on the organisation tables and the frontend use them. They are
-- simply no longer called from inside the hot path.
--
-- Behaviour is identical by construction — same two predicates, same OR, only
-- the call shape changes. Verified against the APP 015 access matrix.

create or replace function public.lign_is_workspace_member(p_workspace_id uuid)
returns boolean
language sql
stable parallel safe security definer
set search_path to ''
as $function$
  select exists (
    select 1
      from public.workspace_members
     where user_id = auth.uid()
       and workspace_id = p_workspace_id
       and status = 'active'
  ) or exists (
    -- Deliberately NOT lign_is_org_admin(lign_org_of_workspace(...)).
    select 1
      from public.workspaces w
      join public.organization_members om on om.organization_id = w.organization_id
     where w.id       = p_workspace_id
       and om.user_id = auth.uid()
       and om.status  = 'active'
       and om.role in ('owner', 'admin')
  );
$function$;

create or replace function public.lign_is_workspace_admin(p_workspace_id uuid)
returns boolean
language sql
stable parallel safe security definer
set search_path to ''
as $function$
  select exists (
    select 1
      from public.workspace_members
     where user_id = auth.uid()
       and workspace_id = p_workspace_id
       and status = 'active'
       and role in ('owner','admin')
  ) or exists (
    select 1
      from public.workspaces w
      join public.organization_members om on om.organization_id = w.organization_id
     where w.id       = p_workspace_id
       and om.user_id = auth.uid()
       and om.status  = 'active'
       and om.role in ('owner', 'admin')
  );
$function$;