-- AUTH 001: helpers_bootstrap
--
-- Authorization helper functions + profile identity protection + three
-- SECURITY DEFINER bootstrap/identity RPCs. No RLS policies in this
-- migration; those land in AUTH 002+.
--
-- Contents:
--   1. lign_current_profile_id()              — SECURITY INVOKER
--   2. lign_is_workspace_member(uuid)         — SECURITY DEFINER
--   3. lign_is_workspace_admin(uuid)          — SECURITY DEFINER
--   4. lign_is_active_stakeholder(uuid)       — SECURITY DEFINER
--   5. lign_project_role(uuid)                — SECURITY DEFINER
--   6. lign_has_capability(uuid, uuid, text)  — SECURITY DEFINER, central resolver
--   7. lign_can_see_profile(uuid)             — SECURITY DEFINER
--   8. profiles identity-immutability trigger — blocks id/email mutations
--   9. create_workspace(text, text)           — SECURITY DEFINER bootstrap
--  10. accept_invitation(text)                — SECURITY DEFINER
--  11. claim_stakeholder_invitation(text)     — SECURITY DEFINER
--
-- Every SECURITY DEFINER function:
--   - SET search_path = ''
--   - fully-qualified references
--   - REVOKE ALL FROM PUBLIC, anon
--   - GRANT EXECUTE TO authenticated, service_role
--   - never trusts caller-supplied identity (uses auth.uid()/auth.users)
--
-- Token hashing uses extensions.digest(token::bytea, 'sha256') encoded as
-- hex; the invite RPCs (not implemented here) must use the same convention.
-- pgcrypto is installed in schema extensions.
--
-- Explicit non-goals:
--   - No RLS policies (deferred to AUTH 002+).
--   - No RPCs beyond the three bootstrap paths (create_workspace,
--     accept_invitation, claim_stakeholder_invitation).
--   - No storage, cron, realtime, notification changes.

------------------------------------------------------------------------------
-- 1. lign_current_profile_id — INVOKER wrapper on auth.uid()
------------------------------------------------------------------------------

create or replace function public.lign_current_profile_id()
returns uuid
language sql
stable
parallel safe
set search_path = ''
as $$
  select auth.uid();
$$;

comment on function public.lign_current_profile_id() is
  'Returns the authenticated Profile id (auth.uid()). SECURITY INVOKER — no privileged access needed.';

revoke all on function public.lign_current_profile_id() from public;
revoke all on function public.lign_current_profile_id() from anon;
grant execute on function public.lign_current_profile_id() to authenticated, service_role;

------------------------------------------------------------------------------
-- 2. lign_is_workspace_member — DEFINER
------------------------------------------------------------------------------

create or replace function public.lign_is_workspace_member(p_workspace_id uuid)
returns boolean
language sql
stable
parallel safe
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.workspace_members
     where user_id = auth.uid()
       and workspace_id = p_workspace_id
       and status = 'active'
  );
$$;

comment on function public.lign_is_workspace_member(uuid) is
  'True if the caller is an active workspace_member of p_workspace_id. SECURITY DEFINER: called from RLS policies that themselves protect workspace_members — DEFINER avoids recursion.';

revoke all on function public.lign_is_workspace_member(uuid) from public;
revoke all on function public.lign_is_workspace_member(uuid) from anon;
grant execute on function public.lign_is_workspace_member(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 3. lign_is_workspace_admin — DEFINER
------------------------------------------------------------------------------

create or replace function public.lign_is_workspace_admin(p_workspace_id uuid)
returns boolean
language sql
stable
parallel safe
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.workspace_members
     where user_id = auth.uid()
       and workspace_id = p_workspace_id
       and status = 'active'
       and role in ('owner','admin')
  );
$$;

comment on function public.lign_is_workspace_admin(uuid) is
  'True if the caller holds workspace owner/admin role in p_workspace_id (active). SECURITY DEFINER.';

revoke all on function public.lign_is_workspace_admin(uuid) from public;
revoke all on function public.lign_is_workspace_admin(uuid) from anon;
grant execute on function public.lign_is_workspace_admin(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 4. lign_is_active_stakeholder — DEFINER
------------------------------------------------------------------------------

create or replace function public.lign_is_active_stakeholder(p_workspace_id uuid)
returns boolean
language sql
stable
parallel safe
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.stakeholders
     where user_id = auth.uid()
       and workspace_id = p_workspace_id
       and status = 'active'
  );
$$;

comment on function public.lign_is_active_stakeholder(uuid) is
  'True if the caller is a claimed, active stakeholder of p_workspace_id. Requires stakeholders.user_id to be non-null. SECURITY DEFINER.';

revoke all on function public.lign_is_active_stakeholder(uuid) from public;
revoke all on function public.lign_is_active_stakeholder(uuid) from anon;
grant execute on function public.lign_is_active_stakeholder(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 5. lign_project_role — DEFINER
------------------------------------------------------------------------------
-- Returns the caller's active project role for p_project_id, or NULL.
-- Rank tie-break: lead > contributor > approver > reviewer > observer.
-- Defensive — normal operation returns exactly one row because the
-- dual-path invariant (PERMISSIONS.md §6.3 D1) is RPC-enforced.

create or replace function public.lign_project_role(p_project_id uuid)
returns text
language sql
stable
parallel safe
security definer
set search_path = ''
as $$
  select pp.role
    from public.project_participants pp
    left join public.workspace_members wm
           on wm.id = pp.workspace_member_id
          and wm.status = 'active'
    left join public.stakeholders sh
           on sh.id = pp.stakeholder_id
          and sh.status = 'active'
   where pp.project_id = p_project_id
     and pp.status = 'active'
     and (wm.user_id = auth.uid() or sh.user_id = auth.uid())
   order by
     case pp.role
       when 'lead'        then 1
       when 'contributor' then 2
       when 'approver'    then 3
       when 'reviewer'    then 4
       when 'observer'    then 5
       else 6
     end
   limit 1;
$$;

comment on function public.lign_project_role(uuid) is
  'Returns the caller''s active project role for p_project_id, or NULL. Tie-break rank: lead > contributor > approver > reviewer > observer (defensive against dual-path violations). SECURITY DEFINER.';

revoke all on function public.lign_project_role(uuid) from public;
revoke all on function public.lign_project_role(uuid) from anon;
grant execute on function public.lign_project_role(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 6. lign_has_capability — DEFINER, central resolver
------------------------------------------------------------------------------
-- First validates project_id belongs to workspace_id. Then evaluates:
--   admin override → workspace admin gets .view + management capabilities
--   role-based grant → per-role capability set for the caller's project role
--
-- Encodes the frozen role → capability matrix from PERMISSIONS.md §3.2.
-- Editing the matrix means editing this function body only; no schema change.

create or replace function public.lign_has_capability(
  p_project_id     uuid,
  p_workspace_id   uuid,
  p_capability_key text
)
returns boolean
language plpgsql
stable
parallel safe
security definer
set search_path = ''
as $$
declare
  v_project_ok boolean;
  v_role       text;
begin
  -- Step 1: validate project_id belongs to workspace_id.
  select exists (
    select 1
      from public.projects
     where id = p_project_id
       and workspace_id = p_workspace_id
  ) into v_project_ok;

  if not v_project_ok then
    return false;
  end if;

  -- Step 2: administrative override (workspace admin can perform admin-set
  -- capabilities on any project in their workspace).
  if p_capability_key = any (array[
    'project.view','project.edit','project.manage_access','project.archive',
    'collection.view','collection.archive',
    'asset.view','asset.archive',
    'version.view','review.view','comment.view','annotation.view',
    'change.view','decision.view','approval.view','release.view',
    'file.download','activity.view'
  ]) then
    if public.lign_is_workspace_admin(p_workspace_id) then
      return true;
    end if;
  end if;

  -- Step 3: caller's project role.
  v_role := public.lign_project_role(p_project_id);
  if v_role is null then
    return false;
  end if;

  -- Step 4: role-based grants (frozen matrix from PERMISSIONS.md §3.2).
  return case v_role
    when 'lead' then p_capability_key = any (array[
      'project.view','project.edit','project.manage_access','project.archive',
      'collection.view','collection.create','collection.edit','collection.archive',
      'asset.view','asset.create','asset.edit','asset.archive','asset.set_current',
      'version.view','version.upload','version.publish','version.discard_draft',
      'review.view','review.create','review.complete',
      'comment.view','comment.create','comment.edit_own','comment.resolve',
      'annotation.view','annotation.create','annotation.resolve',
      'change.view','change.create','change.resolve',
      'decision.view','decision.create',
      'approval.view','approval.request','approval.cancel',
      'release.view','release.create','release.finalize','release.withdraw',
      'file.upload','file.attach','file.download','file.remove_orphaned',
      'activity.view'
    ])
    when 'contributor' then p_capability_key = any (array[
      'project.view',
      'collection.view','collection.create','collection.edit','collection.archive',
      'asset.view','asset.create','asset.edit','asset.archive','asset.set_current',
      'version.view','version.upload','version.publish','version.discard_draft',
      'review.view','review.create','review.complete',
      'comment.view','comment.create','comment.edit_own','comment.resolve',
      'annotation.view','annotation.create','annotation.resolve',
      'change.view','change.create','change.resolve',
      'decision.view','decision.create',
      'approval.view','approval.request','approval.cancel',
      'release.view','release.create',
      'file.upload','file.attach','file.download',
      'activity.view'
    ])
    when 'reviewer' then p_capability_key = any (array[
      'project.view',
      'collection.view','asset.view','version.view',
      'review.view','review.participate',
      'comment.view','comment.create','comment.edit_own',
      'annotation.view','annotation.create',
      'change.view','change.create',
      'decision.view',
      'approval.view',
      'release.view',
      'file.download',
      'activity.view'
    ])
    when 'approver' then p_capability_key = any (array[
      'project.view',
      'collection.view','asset.view','version.view',
      'review.view',
      'comment.view','comment.create','comment.edit_own',
      'annotation.view','annotation.create',
      'change.view','change.create',
      'decision.view',
      'approval.view','approval.respond',
      'release.view',
      'file.download',
      'activity.view'
    ])
    when 'observer' then p_capability_key = any (array[
      'project.view',
      'collection.view','asset.view','version.view',
      'review.view','comment.view','annotation.view',
      'change.view','decision.view','approval.view','release.view',
      'file.download','activity.view'
    ])
    else false
  end;
end;
$$;

comment on function public.lign_has_capability(uuid, uuid, text) is
  'Central authorization resolver. Validates project_id belongs to workspace_id first, then evaluates admin override + role-based grants. Frozen role→capability matrix from PERMISSIONS.md §3.2 encoded inline. SECURITY DEFINER for recursion-safe helper access.';

revoke all on function public.lign_has_capability(uuid, uuid, text) from public;
revoke all on function public.lign_has_capability(uuid, uuid, text) from anon;
grant execute on function public.lign_has_capability(uuid, uuid, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 7. lign_can_see_profile — DEFINER
------------------------------------------------------------------------------

create or replace function public.lign_can_see_profile(p_target_profile_id uuid)
returns boolean
language sql
stable
parallel safe
security definer
set search_path = ''
as $$
  select
    -- own row
    p_target_profile_id = auth.uid()
    -- shared workspace membership
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
    -- shared project via any identity path (them = target, me = caller)
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
$$;

comment on function public.lign_can_see_profile(uuid) is
  'True if the caller may see p_target_profile_id: own row, shared workspace membership, or shared active project participation (via either identity path). SECURITY DEFINER.';

revoke all on function public.lign_can_see_profile(uuid) from public;
revoke all on function public.lign_can_see_profile(uuid) from anon;
grant execute on function public.lign_can_see_profile(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 8. Profile identity immutability trigger
------------------------------------------------------------------------------
-- Blocks user-visible mutation of profiles.id and profiles.email. Any change
-- to email must go through the auth-sync trigger (SECURITY DEFINER surface),
-- not through direct UPDATE on public.profiles.

create or replace function public.enforce_profile_identity_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id is distinct from old.id then
    raise exception 'profiles.id is immutable (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.email is distinct from old.email then
    raise exception 'profiles.email is immutable via public UPDATE (row id=%); email sync happens via the auth trigger', old.id
      using errcode = '23514';
  end if;
  return new;
end;
$$;

comment on function public.enforce_profile_identity_immutable() is
  'DB-boundary trigger: rejects UPDATE that changes profiles.id or profiles.email. Identity fields are auth-authoritative.';

drop trigger if exists profiles_identity_immutable on public.profiles;
create trigger profiles_identity_immutable
  before update on public.profiles
  for each row execute function public.enforce_profile_identity_immutable();

------------------------------------------------------------------------------
-- 9. create_workspace — SECURITY DEFINER bootstrap RPC
------------------------------------------------------------------------------
-- Atomically:
--   - validates authenticated caller
--   - creates workspaces row
--   - creates active owner workspace_members row for auth.uid()
--   - emits workspace.created activity_event
-- Fails atomically on any error (single transaction).
--
-- Never trusts caller-supplied identity — the owner row is always auth.uid().

create or replace function public.create_workspace(
  p_name text,
  p_slug text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_profile_id uuid;
  v_workspace_id      uuid;
begin
  v_caller_profile_id := auth.uid();
  if v_caller_profile_id is null then
    raise exception 'create_workspace: authentication required'
      using errcode = '42501';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'create_workspace: name required'
      using errcode = '22004';
  end if;

  if p_slug is null or length(trim(p_slug)) = 0 then
    raise exception 'create_workspace: slug required'
      using errcode = '22004';
  end if;

  -- Ensure the caller has a profile row (should exist via handle_new_auth_user).
  if not exists (
    select 1 from public.profiles where id = v_caller_profile_id
  ) then
    raise exception 'create_workspace: caller profile % not found', v_caller_profile_id
      using errcode = '23503';
  end if;

  -- Create the workspace.
  insert into public.workspaces (name, slug, status)
  values (p_name, p_slug::extensions.citext, 'active')
  returning id into v_workspace_id;

  -- Create the owner workspace_members row (active from creation).
  insert into public.workspace_members (
    workspace_id, user_id, role, status, invited_at, activated_at
  )
  values (
    v_workspace_id, v_caller_profile_id, 'owner', 'active', now(), now()
  );

  -- Emit workspace.created event.
  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    v_workspace_id, null, now(), 'workspace.created',
    v_caller_profile_id, 'user',
    'workspace', v_workspace_id, p_name,
    jsonb_build_object('name', p_name, 'slug', p_slug),
    '{}'::jsonb
  );

  return v_workspace_id;
end;
$$;

comment on function public.create_workspace(text, text) is
  'Bootstrap RPC: creates a workspace + owner workspace_members row + workspace.created activity_event, all atomically. Owner is always the authenticated caller (auth.uid()) — caller-supplied identity is not accepted. SECURITY DEFINER, search_path pinned.';

revoke all on function public.create_workspace(text, text) from public;
revoke all on function public.create_workspace(text, text) from anon;
grant execute on function public.create_workspace(text, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 10. accept_invitation — SECURITY DEFINER
------------------------------------------------------------------------------
-- Accepts a workspace_member invitation by token. Validates:
--   - authenticated caller
--   - token hash matches an active workspace_member invitation
--   - invitation not expired
--   - invitation email matches auth.users.email of caller (case-insensitive
--     via citext)
-- Then: creates/activates the workspace_members row (idempotent), marks the
-- invitation accepted, emits workspace.member.activated.
--
-- Replay-safe: re-running with the same token after acceptance finds the
-- invitation status != 'sent' and returns an error, but the caller's
-- membership is already active — no side effects.

create or replace function public.accept_invitation(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_profile_id uuid;
  v_caller_email      extensions.citext;
  v_token_hash        text;
  v_invitation        public.invitations%rowtype;
  v_member_id         uuid;
begin
  v_caller_profile_id := auth.uid();
  if v_caller_profile_id is null then
    raise exception 'accept_invitation: authentication required'
      using errcode = '42501';
  end if;

  if p_token is null or length(p_token) = 0 then
    raise exception 'accept_invitation: token required'
      using errcode = '22004';
  end if;

  -- Authoritative caller email from auth.users (not caller-supplied).
  select email::extensions.citext into v_caller_email
    from auth.users
   where id = v_caller_profile_id;

  if v_caller_email is null then
    raise exception 'accept_invitation: caller has no email on auth.users'
      using errcode = '23503';
  end if;

  -- Hash the token (matches the invite-side hashing convention).
  v_token_hash := encode(extensions.digest(p_token::bytea, 'sha256'), 'hex');

  -- Find matching workspace_member invitation.
  select * into v_invitation
    from public.invitations
   where token_hash = v_token_hash
     and kind       = 'workspace_member'
     and status     = 'sent'
     and expires_at > now()
   limit 1;

  if not found then
    raise exception 'accept_invitation: invitation not found, expired, revoked, or already accepted'
      using errcode = '42501';
  end if;

  -- Email binding check.
  if v_invitation.email is distinct from v_caller_email then
    raise exception 'accept_invitation: invitation email does not match caller'
      using errcode = '42501';
  end if;

  -- Create or activate the workspace_members row.
  select id into v_member_id
    from public.workspace_members
   where workspace_id = v_invitation.workspace_id
     and user_id      = v_caller_profile_id
   limit 1;

  if v_member_id is null then
    insert into public.workspace_members (
      workspace_id, user_id, role, status, invited_at, activated_at
    )
    values (
      v_invitation.workspace_id,
      v_caller_profile_id,
      coalesce(v_invitation.role, 'member'),
      'active',
      v_invitation.created_at,
      now()
    )
    returning id into v_member_id;
  else
    update public.workspace_members
       set status       = 'active',
           activated_at = coalesce(activated_at, now())
     where id = v_member_id
       and status in ('invited','suspended');
  end if;

  -- Mark the invitation accepted (only this one).
  update public.invitations
     set status      = 'accepted',
         accepted_at = now()
   where id = v_invitation.id;

  -- Emit workspace.member.activated.
  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    v_invitation.workspace_id, null, now(), 'workspace.member.activated',
    v_caller_profile_id, 'user',
    'workspace_member', v_member_id, v_caller_email::text,
    jsonb_build_object(
      'invitation_id', v_invitation.id,
      'role',          coalesce(v_invitation.role, 'member')
    ),
    '{}'::jsonb
  );

  return v_member_id;
end;
$$;

comment on function public.accept_invitation(text) is
  'SECURITY DEFINER RPC: accepts a workspace_member invitation by token. Never trusts caller-supplied identity — email is read from auth.users. Idempotent for the workspace_members row; the invitation is single-use (status transitions sent → accepted).';

revoke all on function public.accept_invitation(text) from public;
revoke all on function public.accept_invitation(text) from anon;
grant execute on function public.accept_invitation(text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 11. claim_stakeholder_invitation — SECURITY DEFINER
------------------------------------------------------------------------------
-- Claims a stakeholder invitation by token. Validates:
--   - authenticated caller
--   - token hash matches an active stakeholder invitation
--   - invitation not expired
--   - invitation email matches auth.users.email of caller
-- Then: finds the stakeholders row keyed by (workspace_id, email), links it
-- to the caller's profile (user_id = auth.uid()), activates status; marks
-- only that invitation accepted; emits stakeholder.claimed.
--
-- Does NOT reactivate soft-removed project_participants rows. Related
-- participation is expected to be created 'active' by the invite RPC at
-- invitation time (per PERMISSIONS.md §6.2 + STATE_MACHINES.md v1 §4).
-- Access via the stakeholder path becomes possible once user_id is claimed.

create or replace function public.claim_stakeholder_invitation(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_profile_id uuid;
  v_caller_email      extensions.citext;
  v_token_hash        text;
  v_invitation        public.invitations%rowtype;
  v_stakeholder_id    uuid;
  v_existing_user_id  uuid;
begin
  v_caller_profile_id := auth.uid();
  if v_caller_profile_id is null then
    raise exception 'claim_stakeholder_invitation: authentication required'
      using errcode = '42501';
  end if;

  if p_token is null or length(p_token) = 0 then
    raise exception 'claim_stakeholder_invitation: token required'
      using errcode = '22004';
  end if;

  select email::extensions.citext into v_caller_email
    from auth.users
   where id = v_caller_profile_id;

  if v_caller_email is null then
    raise exception 'claim_stakeholder_invitation: caller has no email on auth.users'
      using errcode = '23503';
  end if;

  v_token_hash := encode(extensions.digest(p_token::bytea, 'sha256'), 'hex');

  select * into v_invitation
    from public.invitations
   where token_hash = v_token_hash
     and kind       = 'stakeholder'
     and status     = 'sent'
     and expires_at > now()
   limit 1;

  if not found then
    raise exception 'claim_stakeholder_invitation: invitation not found, expired, revoked, or already accepted'
      using errcode = '42501';
  end if;

  if v_invitation.email is distinct from v_caller_email then
    raise exception 'claim_stakeholder_invitation: invitation email does not match caller'
      using errcode = '42501';
  end if;

  -- Locate the stakeholder row for this workspace+email pair (single per
  -- workspace by UNIQUE (workspace_id, email)).
  select id, user_id
    into v_stakeholder_id, v_existing_user_id
    from public.stakeholders
   where workspace_id = v_invitation.workspace_id
     and email        = v_invitation.email
   limit 1;

  if v_stakeholder_id is null then
    raise exception 'claim_stakeholder_invitation: stakeholder record not found (workspace=%, email=%)',
      v_invitation.workspace_id, v_invitation.email
      using errcode = '23503';
  end if;

  -- Guard: if already claimed by a different profile, refuse.
  if v_existing_user_id is not null and v_existing_user_id <> v_caller_profile_id then
    raise exception 'claim_stakeholder_invitation: stakeholder is already claimed by a different profile'
      using errcode = '42501';
  end if;

  -- Link + activate. Idempotent when re-run by the same profile.
  update public.stakeholders
     set user_id = v_caller_profile_id,
         status  = 'active'
   where id = v_stakeholder_id;

  -- Mark only this invitation accepted.
  update public.invitations
     set status      = 'accepted',
         accepted_at = now()
   where id = v_invitation.id;

  -- Emit stakeholder.claimed.
  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    v_invitation.workspace_id, null, now(), 'stakeholder.claimed',
    v_caller_profile_id, 'user',
    'stakeholder', v_stakeholder_id, v_caller_email::text,
    jsonb_build_object('invitation_id', v_invitation.id),
    '{}'::jsonb
  );

  return v_stakeholder_id;
end;
$$;

comment on function public.claim_stakeholder_invitation(text) is
  'SECURITY DEFINER RPC: claims a stakeholder invitation by token. Never trusts caller-supplied identity. Idempotent per (invitation, caller). Refuses to hijack a stakeholder already claimed by a different profile. Does not touch project_participants — those are created ''active'' at invite time.';

revoke all on function public.claim_stakeholder_invitation(text) from public;
revoke all on function public.claim_stakeholder_invitation(text) from anon;
grant execute on function public.claim_stakeholder_invitation(text) to authenticated, service_role;
