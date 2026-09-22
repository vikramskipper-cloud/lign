-- APP 014 fix — email and slug matching was case-sensitive.
--
-- create_project_full runs with `set search_path to ''`, which is correct for
-- a SECURITY DEFINER function. The side effect: the citext `=` operator lives
-- in the extensions schema and is therefore NOT visible for unqualified
-- operator resolution. Postgres does not error — it finds the implicit
-- citext->text cast and resolves to pg_catalog's text equality instead, which
-- is case-SENSITIVE.
--
-- Consequences, all silent:
--   * "Client@Acme.example" did not match the existing stakeholder
--     "client@acme.example", so the insert hit stakeholders_workspace_email_key
--     and took the whole creation down with it.
--   * The same address typed with different capitalisation was not recognised
--     as a duplicate within one call.
--   * An address belonging to an existing member was only recognised if the
--     capitalisation matched their profile exactly — the precise case that is
--     supposed to prevent one person having two identities in a workspace.
--
-- Rather than qualify the operator, every comparison is now done on explicitly
-- lower-cased text, so it behaves the same whatever the search_path is.
-- Addresses are stored lower-cased for the same reason.
--
-- NOTE: invite_stakeholder() has the identical pattern and therefore the same
-- latent defect. It is frozen under APP 013 and out of scope here — flagged in
-- the APP 014 report rather than changed.

create or replace function public.create_project_full(
  p_workspace_id    uuid,
  p_name            text,
  p_code            text    default null,
  p_description     text    default null,
  p_lead_member_id  uuid    default null,
  p_client_emails   text[]  default '{}'::text[],
  p_expires_in_days integer default 14
)
returns table (
  out_project_id uuid,
  out_slug       text,
  out_code       text,
  out_invites    jsonb
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_caller        uuid;
  v_caller_member uuid;
  v_lead_member   uuid;
  v_name          text;
  v_code          text;
  v_desc          text;
  v_base          text;
  v_slug          text;
  v_n             integer := 1;
  v_project_id    uuid;
  v_conflict      text;
  v_email         text;
  v_raw           text;
  v_member        uuid;
  v_member_label  text;
  v_sh            uuid;
  v_participant   uuid;
  v_token         text;
  v_hash          text;
  v_expires       timestamptz;
  v_inv           uuid;
  v_invites       jsonb := '[]'::jsonb;
  v_seen          text[] := '{}';
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'create_project_full: authentication required' using errcode = '42501';
  end if;
  if p_workspace_id is null then
    raise exception 'create_project_full: workspace_id required' using errcode = '22004';
  end if;

  -- The control. The dialog hides its button without this, but hiding a button
  -- is a courtesy, not a permission.
  if not public.lign_has_capability(null, p_workspace_id, 'workspace.manage') then
    raise exception 'create_project_full: forbidden (workspace.manage)' using errcode = '42501';
  end if;

  select id into v_caller_member
    from public.workspace_members
   where workspace_id = p_workspace_id
     and user_id      = v_caller
     and status       = 'active';
  if v_caller_member is null then
    raise exception 'create_project_full: caller is not an active member of workspace %', p_workspace_id
      using errcode = '42501';
  end if;

  ---------------------------------------------------------------- name + code
  v_name := trim(coalesce(p_name, ''));
  if length(v_name) = 0 then
    raise exception 'create_project_full: name required' using errcode = '22004';
  end if;
  if length(v_name) > 120 then
    raise exception 'create_project_full: name exceeds 120 characters' using errcode = '22001';
  end if;

  -- Empty stays null. A code the user did not choose is a code they will never
  -- recognise, so nothing is generated on their behalf.
  v_code := nullif(upper(trim(coalesce(p_code, ''))), '');
  if v_code is not null then
    if v_code !~ '^[A-Z0-9][A-Z0-9-]{0,15}$' then
      raise exception 'create_project_full: invalid code format' using errcode = '22023';
    end if;
    -- Uniqueness is enforced HERE only. projects.code carries no unique index
    -- (projects_workspace_slug_key is on slug), so two simultaneous creations
    -- can still both pass this check. See the gap noted in the task report.
    select name into v_conflict
      from public.projects
     where workspace_id = p_workspace_id
       and upper(code)  = v_code
       and archived_at is null
     limit 1;
    if v_conflict is not null then
      raise exception 'PROJECT_CODE_TAKEN' using errcode = '23505', detail = v_conflict;
    end if;
  end if;

  v_desc := nullif(trim(coalesce(p_description, '')), '');
  if length(coalesce(v_desc, '')) > 280 then
    raise exception 'create_project_full: description exceeds 280 characters' using errcode = '22001';
  end if;

  ---------------------------------------------------------------------- slug
  -- slug is NOT NULL and unique per workspace, but it is not a field in the
  -- dialog: the brief asks for one required input. Derived from the name and
  -- suffixed until free, so two "Northgate Flagship" projects can coexist.
  -- Compared as lower(text) rather than citext for the reason in the header.
  v_base := regexp_replace(lower(v_name), '[^a-z0-9]+', '-', 'g');
  v_base := trim(both '-' from v_base);
  v_base := left(nullif(v_base, ''), 56);
  if v_base is null then
    v_base := 'project';
  end if;
  v_slug := v_base;
  while exists (
    select 1 from public.projects
     where workspace_id = p_workspace_id and lower(slug::text) = v_slug
  ) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n::text;
  end loop;

  ---------------------------------------------------------------------- lead
  v_lead_member := coalesce(p_lead_member_id, v_caller_member);
  if not exists (
    select 1 from public.workspace_members
     where id = v_lead_member and workspace_id = p_workspace_id and status = 'active'
  ) then
    raise exception 'create_project_full: lead % is not an active member of this workspace', v_lead_member
      using errcode = '23503';
  end if;

  ------------------------------------------------------------------- project
  insert into public.projects (
    workspace_id, name, slug, code, description, status, created_by_profile_id
  )
  values (
    p_workspace_id, v_name, v_slug::extensions.citext, v_code, v_desc, 'active', v_caller
  )
  returning id into v_project_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    p_workspace_id, v_project_id, now(), 'project.created',
    v_caller, 'user',
    'project', v_project_id, v_name,
    jsonb_build_object('name', v_name, 'slug', v_slug, 'code', v_code),
    jsonb_build_object('actor_capacity', 'internal')
  );

  --------------------------------------------------------------- participants
  insert into public.project_participants (
    workspace_id, project_id, workspace_member_id, stakeholder_id, role, status, added_at
  )
  values (p_workspace_id, v_project_id, v_lead_member, null, 'lead', 'active', now())
  returning id into v_participant;

  select p.display_name into v_member_label
    from public.workspace_members wm join public.profiles p on p.id = wm.user_id
   where wm.id = v_lead_member;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    p_workspace_id, v_project_id, now(), 'project.participant_added',
    v_caller, 'user',
    'project_participant', v_participant, coalesce(v_member_label, ''),
    jsonb_build_object('role', 'lead', 'workspace_member_id', v_lead_member),
    jsonb_build_object('capacity', 'internal', 'actor_capacity', 'internal')
  );

  -- Handing the lead role to someone else must not lock the creator out. Work
  -- capabilities (version.upload, release.create, approval.respond) resolve
  -- only through project_participants, so a workspace admin who creates a
  -- project and hands it over would otherwise be able to view it and do
  -- nothing in it.
  if v_lead_member <> v_caller_member then
    insert into public.project_participants (
      workspace_id, project_id, workspace_member_id, stakeholder_id, role, status, added_at
    )
    values (p_workspace_id, v_project_id, v_caller_member, null, 'contributor', 'active', now())
    returning id into v_participant;

    select p.display_name into v_member_label from public.profiles p where p.id = v_caller;

    insert into public.activity_events (
      workspace_id, project_id, occurred_at, event_type,
      actor_profile_id, actor_kind,
      subject_kind, subject_id, subject_label, subject_snapshot, payload
    )
    values (
      p_workspace_id, v_project_id, now(), 'project.participant_added',
      v_caller, 'user',
      'project_participant', v_participant, coalesce(v_member_label, ''),
      jsonb_build_object('role', 'contributor', 'workspace_member_id', v_caller_member),
      jsonb_build_object('capacity', 'internal', 'actor_capacity', 'internal',
                         'reason', 'creator retained access after assigning another lead')
    );
  end if;

  ----------------------------------------------------------- client approvers
  foreach v_raw in array coalesce(p_client_emails, '{}'::text[]) loop
    v_email := nullif(lower(trim(coalesce(v_raw, ''))), '');
    continue when v_email is null;
    continue when v_email = any (v_seen);
    v_seen := v_seen || v_email;

    -- An address that already belongs to a member of this workspace is that
    -- person. Creating a stakeholder for them would give one human two
    -- identities in the same workspace and split their audit trail.
    select wm.id, p.display_name into v_member, v_member_label
      from public.workspace_members wm
      join public.profiles p on p.id = wm.user_id
     where wm.workspace_id    = p_workspace_id
       and wm.status          = 'active'
       and lower(p.email::text) = v_email
     limit 1;

    if v_member is not null then
      insert into public.project_participants (
        workspace_id, project_id, workspace_member_id, stakeholder_id, role, status, added_at
      )
      values (p_workspace_id, v_project_id, v_member, null, 'approver', 'active', now())
      returning id into v_participant;

      insert into public.activity_events (
        workspace_id, project_id, occurred_at, event_type,
        actor_profile_id, actor_kind,
        subject_kind, subject_id, subject_label, subject_snapshot, payload
      )
      values (
        p_workspace_id, v_project_id, now(), 'project.participant_added',
        v_caller, 'user',
        'project_participant', v_participant, coalesce(v_member_label, v_email),
        jsonb_build_object('role', 'approver', 'workspace_member_id', v_member),
        jsonb_build_object('capacity', 'internal', 'actor_capacity', 'internal',
                           'resolved_from_email', v_email)
      );

      v_invites := v_invites || jsonb_build_object(
        'email', v_email, 'kind', 'member',
        'display_name', v_member_label, 'token', null
      );
      v_member := null;
      continue;
    end if;

    select id into v_sh
      from public.stakeholders
     where workspace_id = p_workspace_id and lower(email::text) = v_email;
    if v_sh is null then
      insert into public.stakeholders (workspace_id, email, display_name, status)
      values (p_workspace_id, v_email::extensions.citext, null, 'invited')
      returning id into v_sh;
    else
      update public.stakeholders
         set status     = case when status = 'revoked' then 'invited' else status end,
             revoked_at = case when status = 'revoked' then null else revoked_at end
       where id = v_sh;
    end if;

    insert into public.project_participants (
      workspace_id, project_id, workspace_member_id, stakeholder_id, role, status, added_at
    )
    values (p_workspace_id, v_project_id, null, v_sh, 'approver', 'active', now())
    returning id into v_participant;

    insert into public.activity_events (
      workspace_id, project_id, occurred_at, event_type,
      actor_profile_id, actor_kind,
      subject_kind, subject_id, subject_label, subject_snapshot, payload
    )
    values (
      p_workspace_id, v_project_id, now(), 'project.participant_added',
      v_caller, 'user',
      'project_participant', v_participant, v_email,
      jsonb_build_object('role', 'approver', 'stakeholder_id', v_sh),
      jsonb_build_object('capacity', 'external', 'actor_capacity', 'internal')
    );

    v_token   := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
    v_hash    := encode(extensions.digest(v_token::bytea, 'sha256'), 'hex');
    v_expires := now() + make_interval(days => greatest(1, coalesce(p_expires_in_days, 14)));

    insert into public.invitations (
      workspace_id, email, kind, role, invited_by_profile_id, status, token_hash, expires_at
    )
    values (
      p_workspace_id, v_email::extensions.citext, 'stakeholder', 'approver', v_caller,
      'sent', v_hash, v_expires
    )
    returning id into v_inv;

    insert into public.activity_events (
      workspace_id, project_id, occurred_at, event_type,
      actor_profile_id, actor_kind,
      subject_kind, subject_id, subject_label, subject_snapshot, payload
    )
    values (
      p_workspace_id, v_project_id, now(), 'stakeholder.invited',
      v_caller, 'user',
      'stakeholder', v_sh, v_email,
      jsonb_build_object('email', v_email, 'role', 'approver', 'invitation_id', v_inv),
      jsonb_build_object('capacity', 'external', 'actor_capacity', 'internal')
    );

    v_invites := v_invites || jsonb_build_object(
      'email', v_email, 'kind', 'stakeholder',
      'stakeholder_id', v_sh, 'invitation_id', v_inv,
      'token', v_token, 'expires_at', v_expires
    );
  end loop;

  return query select v_project_id, v_slug, v_code, v_invites;
end;
$function$;