-- APP 016e — organisation audit trail and organisation invitations, without
-- touching a frozen table.
--
-- THE SECOND ATTEMPT, AND WHY IT LOOKS DIFFERENT. The first design loosened
-- activity_events.workspace_id and invitations.workspace_id to nullable and
-- added an organization_id to each, discriminated by a scope CHECK. That is a
-- destructive change to two frozen tables, and it was refused. Rather than
-- press the same statement again, this gives the two new concepts their own
-- storage. Everything here is CREATE; no column is retyped, no constraint
-- dropped, no policy replaced.
--
-- It is also the better model, which the first attempt obscured. activity_events
-- carries a workspace-shaped contract — workspace_id NOT NULL, project_id
-- optional beneath it — and an organisation event fits none of it. Bending one
-- table to two shapes with a XOR CHECK meant every reader had to learn which
-- half it was looking at; the policy needed three arms, two of them guarding
-- against a NULL that only existed because of the bend. Two tables, each with
-- its own NOT NULL scope, need none of that.
--
-- THE COST, stated plainly: "everything that happened" is now a UNION of two
-- tables. Nothing reads across both today — the dashboard's activity feed is
-- workspace-scoped and stays correct untouched — but a future org-wide audit
-- view has to union them, and whoever writes it needs to know that. The
-- columns below deliberately mirror activity_events name-for-name and
-- type-for-type so that union is a straight UNION ALL with no casting.

-- --------------------------------------------------- organisation events ----

create table public.organization_events (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references public.organizations (id) on delete restrict,
  occurred_at       timestamptz not null default now(),
  event_type        text not null,
  actor_profile_id  uuid references public.profiles (id) on delete set null,
  actor_kind        text not null check (actor_kind in ('user', 'system')),
  subject_kind      text,
  subject_id        uuid,
  subject_label     text,
  subject_snapshot  jsonb not null default '{}'::jsonb,
  payload           jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now(),
  -- Same coherence rule activity_events enforces: a user action names its
  -- actor, a system action must not.
  constraint organization_events_actor_coherence_check check (
    (actor_kind = 'user' and actor_profile_id is not null)
    or (actor_kind = 'system' and actor_profile_id is null)
  )
);

comment on table public.organization_events is
  'Audit trail for organisation-scoped actions. Deliberately separate from activity_events, whose workspace_id is NOT NULL and which is frozen. Columns mirror it so the two can be UNION ALL-ed.';

create index organization_events_organization_id_idx
  on public.organization_events (organization_id, occurred_at desc);
create index organization_events_actor_profile_id_idx
  on public.organization_events (actor_profile_id);

alter table public.organization_events enable row level security;

-- Read for org admins only, matching activity_events where the workspace arm
-- is lign_is_workspace_admin. A plain org `member` holds no administrative
-- authority and so sees no administrative log.
create policy organization_events_select on public.organization_events
  for select to authenticated
  using (public.lign_is_org_admin(organization_id));

-- ---------------------------------------------- organisation invitations ----

create table public.organization_invitations (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null references public.organizations (id) on delete cascade,
  email                 extensions.citext not null,
  role                  text not null check (role in ('owner', 'admin', 'member')),
  invited_by_profile_id uuid references public.profiles (id) on delete set null,
  status                text not null default 'sent'
                        check (status in ('sent', 'accepted', 'expired', 'revoked')),
  token_hash            text not null,
  expires_at            timestamptz not null,
  accepted_at           timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

comment on table public.organization_invitations is
  'Email invitations to an organisation. Separate from invitations, whose workspace_id is NOT NULL and which is frozen. Only the sha256 of the token is stored.';

-- One live invitation per address per organisation. Partial, so a revoked or
-- accepted one does not block re-inviting.
create unique index organization_invitations_pending_key
  on public.organization_invitations (organization_id, email)
  where status = 'sent';
create index organization_invitations_organization_id_idx
  on public.organization_invitations (organization_id);
create index organization_invitations_invited_by_idx
  on public.organization_invitations (invited_by_profile_id);
create index organization_invitations_token_hash_idx
  on public.organization_invitations (token_hash);

create trigger organization_invitations_set_updated_at
  before update on public.organization_invitations
  for each row execute function public.set_updated_at();

alter table public.organization_invitations enable row level security;

-- Org admins see their organisation's invitations; an invitee sees their own,
-- which is what lets the claim screen show who invited them before they have
-- any membership at all.
create policy organization_invitations_select on public.organization_invitations
  for select to authenticated
  using (
    public.lign_is_org_admin(organization_id)
    or email = ((select auth.email()))::extensions.citext
  );

grant select, insert, update, delete, truncate, references, trigger
  on table public.organization_events to anon, authenticated, service_role;
grant select, insert, update, delete, truncate, references, trigger
  on table public.organization_invitations to anon, authenticated, service_role;