-- APP 023 — wire every invitation to the mail queue, ready for a sender.
--
-- email_outbox (APP 020) only ever held access-request mail. The four
-- invitation paths — org member, workspace member, stakeholder, and the client
-- invites inside create_project_full — minted a token, returned it to the
-- caller, and queued nothing. So "we'll email you to sign in" was true of
-- nothing. This makes all four enqueue, so that adding a sender later is the
-- only remaining step.
--
-- WHY A SEPARATE RPC RATHER THAN EDITING THE FOUR.
--
-- The obvious move is to add an outbox insert inside each invite function.
-- Two reasons not to.
--
-- First, the APP 014 brief said it directly: "send invite emails only after
-- the transaction commits." An enqueue inside create_project_full is inside
-- its transaction by construction.
--
-- Second, those four bodies total ~23 KB and a migration must carry the whole
-- replacement text literally. Retyping 23 KB of working authorization code to
-- add one statement each is a transcription risk out of all proportion to the
-- feature, and the functions are frozen surface besides.
--
-- So delivery is a post-commit step: the caller already holds the plaintext
-- token — every one of those RPCs returns it — and hands it back here.
--
-- POSSESSION IS THE CREDENTIAL. The token is never looked up by id. It is
-- hashed and matched against token_hash, which is the same test
-- accept_invitation applies. A caller who does not hold a live token cannot
-- queue mail for anybody, and the error does not say which of the two
-- invitation tables was missed.
--
-- The caller must ALSO be the inviter or hold the matching admin right. Not
-- strictly necessary once possession is proven, but it costs nothing and keeps
-- "who may cause mail to be sent" answerable without reasoning about who might
-- have seen a token.
--
-- IDEMPOTENT. dedupe_key carries 'invitation:<id>' under a partial unique
-- index, and the insert is ON CONFLICT DO NOTHING. Calling twice — a retry, a
-- double-clicked button, a client that re-queues on remount — sends one email.
-- This is also what keeps the endpoint from being a mailer: the only address
-- it can ever reach is the one already on the invitation, and only once.
--
-- THE TOKEN AT REST, AND WHY THAT IS NEW. Until now only sha256(token) was
-- stored. A queued email must carry a usable link, so the plaintext now sits
-- in email_outbox.payload until it is sent. That is a real weakening and it is
-- mitigated, not waved away:
--
--   * No client role can read it. The table-wide SELECT grant is withdrawn
--     from anon and authenticated and re-granted column by column, omitting
--     payload. A column-level REVOKE cannot cut back a table-wide grant
--     (Postgres: "REVOKE ... (column) will not revoke a table-wide
--     privilege"), which is why the grant is rebuilt rather than trimmed —
--     verified: reading payload as a platform admin now fails 42501, and so
--     does SELECT *.
--   * Only service_role — the drainer — can read it.
--   * THE DRAINER MUST REDACT ON SEND. Marking a row sent must also clear it:
--         update public.email_outbox
--            set status = 'sent', sent_at = now(), payload = '{}'::jsonb
--          where id = $1;
--     so the plaintext exists only between enqueue and delivery. This is a
--     contract the sender has to honour; nothing in the database can force it.
--   * Tokens already expire (14 days by default).
--
-- The alternative was a drainer that mints a fresh token as it sends, so no
-- plaintext is ever stored. It is stronger, and it is incompatible with the
-- copy-a-link delivery the product uses today: rotating on send kills the link
-- an admin already copied. Worth revisiting when email becomes the only path.

-- ------------------------------------------------------------- idempotency --
alter table public.email_outbox add column dedupe_key text;

comment on column public.email_outbox.dedupe_key is
  'Optional caller-supplied identity for a message, so re-queueing the same thing is a no-op. Invitation mail uses ''invitation:<id>''. Null means "no deduplication", which is right for anything genuinely repeatable.';

create unique index email_outbox_dedupe_key_uq
  on public.email_outbox (dedupe_key) where dedupe_key is not null;

-- ---------------------------------------------------- the token stays unread
-- Rebuilt rather than trimmed: see the note above on column REVOKE being
-- unable to narrow a table-wide grant. anon loses the read entirely; it never
-- had a reason for one.
revoke select on table public.email_outbox from anon, authenticated;
grant select (id, to_email, template, status, attempts, last_error,
              created_at, sent_at, dedupe_key)
  on table public.email_outbox to authenticated;

-- --------------------------------------------------------------- the enqueue
create or replace function public.queue_invitation_email(p_token text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_caller    uuid;
  v_hash      text;
  v_id        uuid;
  v_email     text;
  v_role      text;
  v_template  text;
  v_route     text;
  v_context   text;
  v_expires   timestamptz;
  v_status    text;
  v_inviter   uuid;
  v_authorised boolean := false;
  v_ws        uuid;
  v_org       uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'queue_invitation_email: authentication required' using errcode = '42501';
  end if;
  if coalesce(trim(p_token), '') = '' then
    raise exception 'queue_invitation_email: token required' using errcode = '22004';
  end if;

  v_hash := encode(extensions.digest(trim(p_token)::bytea, 'sha256'), 'hex');

  -- Organisation invitations first, then workspace and stakeholder ones. Found
  -- by hash only: an id is never accepted, so possession of a live token is
  -- the entry condition.
  select oi.id, lower(oi.email::text), oi.role, oi.status, oi.expires_at,
         oi.invited_by_profile_id, oi.organization_id, o.name
    into v_id, v_email, v_role, v_status, v_expires, v_inviter, v_org, v_context
    from public.organization_invitations oi
    join public.organizations o on o.id = oi.organization_id
   where oi.token_hash = v_hash;

  if v_id is not null then
    v_template := 'org_invitation';
    v_route    := '/org-invite';
    v_authorised := v_inviter = v_caller or public.lign_is_org_admin(v_org);
  else
    select i.id, lower(i.email::text), i.role, i.status, i.expires_at,
           i.invited_by_profile_id, i.workspace_id, w.name,
           case i.kind when 'stakeholder' then 'stakeholder_invitation'
                       else 'workspace_member_invitation' end
      into v_id, v_email, v_role, v_status, v_expires, v_inviter, v_ws, v_context, v_template
      from public.invitations i
      join public.workspaces w on w.id = i.workspace_id
     where i.token_hash = v_hash;

    if v_id is null then
      -- Deliberately does not say which table was searched, nor whether the
      -- token merely expired.
      raise exception 'queue_invitation_email: no live invitation for that token'
        using errcode = '23503';
    end if;
    v_route := '/invite';
    v_authorised := v_inviter = v_caller
                 or public.lign_has_capability(null, v_ws, 'member.invite');
  end if;

  if v_status <> 'sent' then
    raise exception 'queue_invitation_email: invitation is %, not pending', v_status
      using errcode = '23514';
  end if;
  if v_expires <= now() then
    raise exception 'queue_invitation_email: invitation has expired' using errcode = '23514';
  end if;
  if not v_authorised then
    raise exception 'queue_invitation_email: forbidden' using errcode = '42501';
  end if;

  -- claim_route carries the path WITHOUT the token, so the sender composes
  -- <app url> || claim_route || '/' || token and needs to know nothing about
  -- LIGN's routing. One secret, one route hint.
  insert into public.email_outbox (to_email, template, payload, dedupe_key)
  values (
    v_email::extensions.citext,
    v_template,
    jsonb_build_object(
      'invitation_id', v_id,
      'email',         v_email,
      'role',          v_role,
      'context_name',  v_context,
      'claim_route',   v_route,
      'token',         trim(p_token),
      'expires_at',    v_expires
    ),
    'invitation:' || v_id::text
  )
  on conflict (dedupe_key) where dedupe_key is not null do nothing;
end;
$function$;

comment on function public.queue_invitation_email(text) is
  'Queues the invitation email for a token the caller already holds. Found by sha256 of the token, never by id, so possession is the credential; idempotent per invitation via dedupe_key. Called AFTER the inviting transaction commits, per the APP 014 brief.';

revoke all on function public.queue_invitation_email(text) from public;
revoke all on function public.queue_invitation_email(text) from anon;
grant execute on function public.queue_invitation_email(text) to authenticated, service_role;
