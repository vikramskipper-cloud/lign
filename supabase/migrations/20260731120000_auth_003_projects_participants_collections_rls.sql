-- AUTH 003: projects_participants_collections_rls
--
-- RLS policies for §7 Group D:
--   projects, project_participants, collections.
--
-- Plus the two SECURITY DEFINER workflow RPCs that AUTH 003 needs to
-- function correctly:
--   create_project(p_workspace_id, p_name, p_slug, p_description)
--   add_project_participant(p_project_id, p_workspace_member_id,
--                           p_stakeholder_id, p_role)
--
-- Rationale for RPCs (not new authorization design):
--   - projects has no INSERT policy — a direct RLS INSERT can't atomically
--     create the required first project_participants (lead) row, which would
--     leave a project with no participants and break RLS-based access. The
--     create_project RPC guarantees the atomic pair.
--   - project_participants is RPC-only for all writes per §7 Group D +
--     decision #2. add_project_participant enforces the dual-path
--     participation invariant (PERMISSIONS.md §6.3 D1) that cannot be
--     structurally encoded in a schema constraint.
--
-- Deferred to AUTH 003b or later: change_project_participant_role,
-- remove_project_participant. Not required for MVP AUTH 003 correctness.
--
-- No new authorization helper — lign_has_capability already wraps
-- lign_project_role under DEFINER, and lign_is_workspace_admin is DEFINER
-- too. No RLS recursion introduced.
--
-- No structural schema change; V1 lock intact.

------------------------------------------------------------------------------
-- 1. create_project — SECURITY DEFINER bootstrap RPC
------------------------------------------------------------------------------

create or replace function public.create_project(
  p_workspace_id uuid,
  p_name         text,
  p_slug         text,
  p_description  text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller     uuid;
  v_member_id  uuid;
  v_project_id uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'create_project: authentication required' using errcode = '42501';
  end if;

  if p_workspace_id is null then
    raise exception 'create_project: workspace_id required' using errcode = '22004';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'create_project: name required' using errcode = '22004';
  end if;
  if p_slug is null or length(trim(p_slug)) = 0 then
    raise exception 'create_project: slug required' using errcode = '22004';
  end if;

  -- Caller must be an active workspace_member of the target workspace.
  -- (owner/admin/member — guest was removed at V1 lock.)
  select id into v_member_id
    from public.workspace_members
   where workspace_id = p_workspace_id
     and user_id      = v_caller
     and status       = 'active';
  if v_member_id is null then
    raise exception 'create_project: caller is not an active workspace_member of workspace %', p_workspace_id
      using errcode = '42501';
  end if;

  insert into public.projects (
    workspace_id, name, slug, description, status, created_by_profile_id
  )
  values (
    p_workspace_id, p_name, p_slug::extensions.citext, p_description, 'active', v_caller
  )
  returning id into v_project_id;

  -- Atomic first participant: caller becomes project lead (via member path).
  insert into public.project_participants (
    workspace_id, project_id, workspace_member_id, stakeholder_id,
    role, status, added_at
  )
  values (
    p_workspace_id, v_project_id, v_member_id, null,
    'lead', 'active', now()
  );

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    p_workspace_id, v_project_id, now(), 'project.created',
    v_caller, 'user',
    'project', v_project_id, p_name,
    jsonb_build_object('name', p_name, 'slug', p_slug),
    '{}'::jsonb
  );

  return v_project_id;
end;
$$;

comment on function public.create_project(uuid, text, text, text) is
  'Bootstrap RPC: creates a project + first project_participants row (caller as lead) + project.created activity event, atomically. Caller must be an active workspace_member. Created_by is auth.uid(); caller-supplied identity is not accepted. SECURITY DEFINER, search_path pinned.';

revoke all on function public.create_project(uuid, text, text, text) from public;
revoke all on function public.create_project(uuid, text, text, text) from anon;
grant execute on function public.create_project(uuid, text, text, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 2. add_project_participant — SECURITY DEFINER RPC
------------------------------------------------------------------------------
-- Enforces:
--   - authenticated caller
--   - XOR on (workspace_member_id, stakeholder_id)
--   - role in the frozen project-role vocabulary
--   - authorization: workspace admin OR project.manage_access on the project
--   - the added identity belongs to the project's workspace
--   - dual-path participation invariant (PERMISSIONS.md §6.3 D1):
--     if the added identity is claimed (has user_id), refuse when the same
--     user is already active in the project via the OTHER identity path.
-- Emits project.participant.added.

create or replace function public.add_project_participant(
  p_project_id          uuid,
  p_workspace_member_id uuid,
  p_stakeholder_id      uuid,
  p_role                text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller         uuid;
  v_workspace_id   uuid;
  v_new_user_id    uuid;
  v_participant_id uuid;
  v_subject_label  text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'add_project_participant: authentication required' using errcode = '42501';
  end if;

  if p_project_id is null then
    raise exception 'add_project_participant: project_id required' using errcode = '22004';
  end if;

  if (p_workspace_member_id is null) = (p_stakeholder_id is null) then
    raise exception 'add_project_participant: exactly one of workspace_member_id or stakeholder_id must be set'
      using errcode = '23514';
  end if;

  if p_role is null or p_role not in ('lead','contributor','reviewer','approver','observer') then
    raise exception 'add_project_participant: invalid role %', coalesce(p_role, '(null)')
      using errcode = '23514';
  end if;

  select workspace_id into v_workspace_id
    from public.projects
   where id = p_project_id;
  if v_workspace_id is null then
    raise exception 'add_project_participant: project % not found', p_project_id
      using errcode = '23503';
  end if;

  -- Authorization: workspace admin OR project.manage_access on the project.
  if not (
    public.lign_is_workspace_admin(v_workspace_id)
    or public.lign_has_capability(p_project_id, v_workspace_id, 'project.manage_access')
  ) then
    raise exception 'add_project_participant: insufficient authorization'
      using errcode = '42501';
  end if;

  -- Resolve the added identity's user_id (may be null for unclaimed stakeholder).
  if p_workspace_member_id is not null then
    select user_id into v_new_user_id
      from public.workspace_members
     where id           = p_workspace_member_id
       and workspace_id = v_workspace_id
       and status       = 'active';
    if not found then
      raise exception 'add_project_participant: workspace_member % not found in workspace % (active)',
        p_workspace_member_id, v_workspace_id
        using errcode = '23503';
    end if;
    v_subject_label := 'wm:' || p_workspace_member_id::text;
  else
    select user_id into v_new_user_id
      from public.stakeholders
     where id           = p_stakeholder_id
       and workspace_id = v_workspace_id
       and status in ('active','invited');
    if not found then
      raise exception 'add_project_participant: stakeholder % not found in workspace % (active/invited)',
        p_stakeholder_id, v_workspace_id
        using errcode = '23503';
    end if;
    v_subject_label := 'sh:' || p_stakeholder_id::text;
  end if;

  -- Dual-path invariant enforcement.
  if v_new_user_id is not null then
    if p_workspace_member_id is not null then
      if exists (
        select 1
          from public.project_participants pp
          join public.stakeholders s on s.id = pp.stakeholder_id
         where pp.project_id = p_project_id
           and pp.status     = 'active'
           and s.user_id     = v_new_user_id
      ) then
        raise exception 'add_project_participant: dual-path violation — user is already active in project via stakeholder path'
          using errcode = '23514';
      end if;
    else
      if exists (
        select 1
          from public.project_participants pp
          join public.workspace_members wm on wm.id = pp.workspace_member_id
         where pp.project_id = p_project_id
           and pp.status     = 'active'
           and wm.user_id    = v_new_user_id
      ) then
        raise exception 'add_project_participant: dual-path violation — user is already active in project via workspace_member path'
          using errcode = '23514';
      end if;
    end if;
  end if;

  insert into public.project_participants (
    workspace_id, project_id, workspace_member_id, stakeholder_id,
    role, status, added_at
  )
  values (
    v_workspace_id, p_project_id, p_workspace_member_id, p_stakeholder_id,
    p_role, 'active', now()
  )
  returning id into v_participant_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    v_workspace_id, p_project_id, now(), 'project.participant.added',
    v_caller, 'user',
    'project_participant', v_participant_id, v_subject_label,
    jsonb_build_object(
      'role',                p_role,
      'workspace_member_id', p_workspace_member_id,
      'stakeholder_id',      p_stakeholder_id
    ),
    '{}'::jsonb
  );

  return v_participant_id;
end;
$$;

comment on function public.add_project_participant(uuid, uuid, uuid, text) is
  'SECURITY DEFINER RPC: adds a project_participant (via workspace_member XOR stakeholder). Authorization: workspace admin OR project.manage_access. Enforces the dual-path participation invariant (PERMISSIONS.md §6.3 D1) inside the same transaction — no admin can create a dual-path condition.';

revoke all on function public.add_project_participant(uuid, uuid, uuid, text) from public;
revoke all on function public.add_project_participant(uuid, uuid, uuid, text) from anon;
grant execute on function public.add_project_participant(uuid, uuid, uuid, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 3. projects policies
------------------------------------------------------------------------------

drop policy if exists projects_select on public.projects;
create policy projects_select on public.projects
  as permissive
  for select
  to authenticated
  using (
    public.lign_is_workspace_admin(workspace_id)
    or public.lign_has_capability(id, workspace_id, 'project.view')
  );

-- No INSERT policy → create_project RPC only.

drop policy if exists projects_update on public.projects;
create policy projects_update on public.projects
  as permissive
  for update
  to authenticated
  using      (public.lign_has_capability(id, workspace_id, 'project.edit'))
  with check (public.lign_has_capability(id, workspace_id, 'project.edit'));

-- No DELETE policy.

------------------------------------------------------------------------------
-- 4. project_participants policy — SELECT only; writes RPC-only
------------------------------------------------------------------------------

drop policy if exists project_participants_select on public.project_participants;
create policy project_participants_select on public.project_participants
  as permissive
  for select
  to authenticated
  using (
    public.lign_is_workspace_admin(workspace_id)
    or public.lign_has_capability(project_id, workspace_id, 'project.view')
  );

-- No INSERT/UPDATE/DELETE policies → RPC-only per §7 Group D + decision #2.

------------------------------------------------------------------------------
-- 5. collections policies
------------------------------------------------------------------------------

drop policy if exists collections_select on public.collections;
create policy collections_select on public.collections
  as permissive
  for select
  to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'collection.view'));

drop policy if exists collections_insert on public.collections;
create policy collections_insert on public.collections
  as permissive
  for insert
  to authenticated
  with check (
    public.lign_has_capability(project_id, workspace_id, 'collection.create')
    and created_by_profile_id = (select auth.uid())
  );

drop policy if exists collections_update on public.collections;
create policy collections_update on public.collections
  as permissive
  for update
  to authenticated
  using      (public.lign_has_capability(project_id, workspace_id, 'collection.edit'))
  with check (public.lign_has_capability(project_id, workspace_id, 'collection.edit'));

-- No DELETE policy → archive via status/archived_at (out of AUTH 003 scope).
