-- APP 010: Notifications authz + router + RPCs (Migration B).
--
-- Delivers per APP_010_BACKEND_PROPOSAL §9.1, §11.3, §15, §16:
--   * lign_has_capability reissued additively (F-3): 2 wired
--     (notification.view, notification.manage) granted to every role;
--     6 reserved keys registered by name returning false for every caller.
--     Every prior slice's role map preserved byte-identically.
--   * routing bridge trigger on activity_events (AFTER INSERT, boundary-additive):
--     enforce_notification_router_bridge → resolve_notification_router_targets
--     - SECURITY DEFINER, SET search_path = '', REVOKE public/anon/authenticated,
--       NO GRANT (trigger context only).
--     - Body wrapped in BEGIN … EXCEPTION WHEN OTHERS THEN RAISE WARNING …;
--       RETURN NEW; END so router failures never roll back workflow transactions.
--     - F-2 explicit `notification.*` recursion guard as step 1a.
--   * 5 read RPCs: list_notifications_inbox, get_notification,
--     get_notification_badge_count, get_notification_center,
--     list_notifications_by_source
--   * 5 write RPCs: mark_notification_read, mark_notification_unread,
--     mark_all_notifications_read, dismiss_notification, archive_notification
--
-- Every RPC: SECURITY DEFINER, SET search_path = '', REVOKE from
-- public/anon/authenticated, GRANT EXECUTE to authenticated, service_role.
-- Every write RPC sets lign.allow_notification_rpc_write='true' before UPDATE
-- and resets it after; enforces recipient_profile_id = auth.uid() in-body.

------------------------------------------------------------------------------
-- 1. lign_has_capability — additive reissue (F-3, §11.3, C-2)
------------------------------------------------------------------------------
-- Preserves every frozen key + role mapping byte-identically. Appends 2 wired
-- notification.* keys and registers 6 reserved keys returning false.

create or replace function public.lign_has_capability(
  p_project_id uuid,
  p_workspace_id uuid,
  p_capability_key text
)
returns boolean
language plpgsql
stable parallel safe security definer
set search_path = ''
as $$
declare
  v_project_ok boolean;
  v_role       text;
begin
  -- APP 010: notification.view + notification.manage are PERSONAL capabilities
  -- granted to every authenticated user regardless of project scope. Recipient
  -- enforcement lives in the RPC/RLS layer via recipient_profile_id = auth.uid().
  -- Answer these keys BEFORE the project-scope validation so that workspace-scoped
  -- notification reads (which pass project_id = NULL) resolve true.
  if p_capability_key in ('notification.view', 'notification.manage') then
    return auth.uid() is not null;
  end if;

  -- APP 010: 6 RESERVED capability keys — name-only registration; zero grants in v1.
  if p_capability_key in (
    'notification.view_any',
    'notification.announce',
    'notification.ai_prioritize',
    'notification.ai_summarize',
    'notification.ai_digest',
    'notification.preference'
  ) then
    return false;
  end if;

  -- ---------------------------------------------------------------------
  -- Below is byte-identical to the frozen APP 009 lign_has_capability body
  -- (20260814180000_app_009_releases_authz_and_rpcs.sql L39–161).
  -- ---------------------------------------------------------------------

  select exists (
    select 1
      from public.projects
     where id = p_project_id
       and workspace_id = p_workspace_id
  ) into v_project_ok;

  if not v_project_ok then
    return false;
  end if;

  if p_capability_key = any (array[
    'project.view','project.edit','project.manage_access','project.archive',
    'collection.view','collection.archive',
    'asset.view','asset.archive',
    'version.view','review.view','comment.view','annotation.view',
    'change.view','decision.view','approval.view','release.view',
    'file.download','activity.view',
    'requirement.view'
  ]) then
    if public.lign_is_workspace_admin(p_workspace_id) then
      return true;
    end if;
  end if;

  v_role := public.lign_project_role(p_project_id);
  if v_role is null then
    return false;
  end if;

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
      'activity.view',
      'requirement.view','requirement.create','requirement.edit',
      'requirement.archive','requirement.assess'
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
      'activity.view',
      'requirement.view','requirement.create','requirement.edit','requirement.assess'
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
      'activity.view',
      'requirement.view','requirement.assess'
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
      'activity.view',
      'requirement.view','requirement.assess'
    ])
    when 'observer' then p_capability_key = any (array[
      'project.view',
      'collection.view','asset.view','version.view',
      'review.view','comment.view','annotation.view',
      'change.view','decision.view','approval.view','release.view',
      'file.download','activity.view',
      'requirement.view'
    ])
    else false
  end;
end $$;

comment on function public.lign_has_capability(uuid, uuid, text) is
  'AUTH capability primer. Extended by REQUIREMENTS 003 (5 requirement.* keys). APP 008 reserves 4 requirement.* keys. APP 009 reserves 6 release.* keys. APP 010 wires 2 personal notification.* keys (notification.view/manage; implicit for every authenticated user) and reserves 6 more (notification.view_any/.announce/.ai_prioritize/.ai_summarize/.ai_digest/.preference; zero grants).';

------------------------------------------------------------------------------
-- 2. Router function: resolve_notification_router_targets (§9.1)
------------------------------------------------------------------------------
-- SECURITY DEFINER (reads recipient-resolution tables the emitting caller
-- may not have direct SELECT on). SET search_path = ''. REVOKE from
-- public/anon/authenticated. NO GRANT (trigger dispatcher only).
--
-- Body wrapped in BEGIN … EXCEPTION WHEN OTHERS THEN RAISE WARNING …;
-- RETURN NEW; END. Under no circumstance does a router failure propagate into
-- the parent workflow transaction. This is inviolable.

create or replace function public.resolve_notification_router_targets()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_snap             jsonb;
  v_notification_type text;
  v_category         text;
  v_priority         text;
  v_channels         text[];
  v_recipients       uuid[];
  v_recipient_id     uuid;
  v_actor_display    text;
  v_deep_link        jsonb;
  v_deep_link_kind   text;
  v_deep_link_id     uuid;
  v_preview          text;
  v_payload          jsonb;
begin
  -- Defensive early return for null event_type.
  if new.event_type is null then
    return new;
  end if;

  -- F-2: explicit notification.* recursion guard (PRIMARY loop-guard mechanism).
  -- Runs before routing-table lookup so guard is unavoidable. Routing-table
  -- absence of notification.* entries is the secondary defense (§9.1).
  if new.event_type like 'notification.%' then
    return new;
  end if;

  -- Wrap all routing work in exception-safe body. Router MUST NOT roll back
  -- the parent workflow transaction under any circumstance (§2.8, §9.1, §17.1,
  -- §20.8). If routing fails, the missed notification is a silent loss visible
  -- only in Postgres logs.
  begin
    v_snap := coalesce(new.subject_snapshot, '{}'::jsonb);
    v_channels := array['in_app']::text[];

    -- Routing-table dispatch. Maps event_type → (notification_type, category,
    -- priority, channels, recipient-rule). Per Freeze Index §8.1 (~34 wired
    -- consumer paths). Unmatched event_types silently return (feed-only or
    -- reserved-forward events per G-51).
    case
      -- ================= REVIEW cluster (4) =================
      when new.event_type = 'review.opened' then
        v_notification_type := 'review.assigned_to_you';
        v_category := 'assigned_to_me'; v_priority := 'high';
        -- Direct-actor rule: review_participants roster minus actor
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.review_participants rp
              left join public.workspace_members wm on wm.id = rp.workspace_member_id
              left join public.stakeholders sh on sh.id = rp.stakeholder_id
             where rp.review_id = new.subject_id
          ) p
         where p.profile_id is not null;

      when new.event_type = 'review.completed' then
        v_notification_type := 'review.your_review_completed';
        v_category := 'governance_state_change'; v_priority := 'medium';
        select array[created_by_profile_id]::uuid[] into v_recipients
          from public.reviews where id = new.subject_id;

      when new.event_type = 'review.cancelled' then
        v_notification_type := 'review.your_review_cancelled';
        v_category := 'governance_state_change'; v_priority := 'medium';
        select array[created_by_profile_id]::uuid[] into v_recipients
          from public.reviews where id = new.subject_id;

      when new.event_type = 'review.reviewer_responded' then
        v_notification_type := 'review.reviewer_responded_on_your_review';
        v_category := 'project_activity'; v_priority := 'medium';
        select array[r.created_by_profile_id]::uuid[] into v_recipients
          from public.reviews r
          join public.review_participants rp on rp.review_id = r.id
         where rp.id = new.subject_id;

      -- ================= APPROVAL cluster (6) =================
      when new.event_type = 'approval.requested' then
        v_notification_type := 'approval.awaiting_your_decision';
        v_category := 'assigned_to_me'; v_priority := 'high';
        v_channels := array['in_app','email_payload']::text[];
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.approval_request_approvers ara
              left join public.workspace_members wm on wm.id = ara.workspace_member_id
              left join public.stakeholders sh on sh.id = ara.stakeholder_id
             where ara.approval_request_id = new.subject_id
          ) p
         where p.profile_id is not null;

      when new.event_type = 'approval.responded' then
        v_notification_type := 'approval.responded_on_your_request';
        v_category := 'project_activity'; v_priority := 'medium';
        select array[ar.created_by_profile_id]::uuid[] into v_recipients
          from public.approval_requests ar
         where ar.id = new.subject_id
            or ar.id = (v_snap->>'approval_request_id')::uuid;

      when new.event_type = 'approval.approved' then
        v_notification_type := 'approval.approved_your_request';
        v_category := 'governance_state_change'; v_priority := 'high';
        select array[created_by_profile_id]::uuid[] into v_recipients
          from public.approval_requests where id = new.subject_id;

      when new.event_type = 'approval.rejected' then
        v_notification_type := 'approval.rejected_your_request';
        v_category := 'governance_state_change'; v_priority := 'high';
        select array[created_by_profile_id]::uuid[] into v_recipients
          from public.approval_requests where id = new.subject_id;

      when new.event_type = 'approval.expired' then
        v_notification_type := 'approval.expired_your_request';
        v_category := 'governance_state_change'; v_priority := 'high';
        select array[created_by_profile_id]::uuid[] into v_recipients
          from public.approval_requests where id = new.subject_id;

      when new.event_type = 'approval.cancelled' then
        v_notification_type := 'approval.request_cancelled';
        v_category := 'governance_state_change'; v_priority := 'medium';
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.approval_request_approvers ara
              left join public.workspace_members wm on wm.id = ara.workspace_member_id
              left join public.stakeholders sh on sh.id = ara.stakeholder_id
             where ara.approval_request_id = new.subject_id
          ) p
         where p.profile_id is not null;

      -- ================= COMMENT (1) =================
      when new.event_type = 'comment.mentioned' then
        v_notification_type := 'comment.mentioned_you';
        v_category := 'mentions'; v_priority := 'high';
        v_recipients := array[(v_snap->>'mentioned_profile_id')::uuid];

      -- ================= ANNOTATION (1) =================
      when new.event_type = 'annotation.resolved' then
        v_notification_type := 'annotation.your_annotation_resolved';
        v_category := 'project_activity'; v_priority := 'low';
        select array[author_profile_id]::uuid[] into v_recipients
          from public.annotations where id = new.subject_id;

      -- ================= CHANGE cluster (4) =================
      when new.event_type = 'change.created' then
        v_notification_type := 'change.needs_leads_attention';
        v_category := 'project_activity'; v_priority := 'medium';
        -- Project leads
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.project_participants pp
              left join public.workspace_members wm on wm.id = pp.workspace_member_id
              left join public.stakeholders sh on sh.id = pp.stakeholder_id
             where pp.project_id = new.project_id
               and pp.role = 'lead'
               and pp.status = 'active'
          ) p
         where p.profile_id is not null;

      when new.event_type = 'change.accepted' then
        v_notification_type := 'change.your_change_accepted';
        v_category := 'governance_state_change'; v_priority := 'medium';
        select array[author_profile_id]::uuid[] into v_recipients
          from public.changes where id = new.subject_id;

      when new.event_type = 'change.rejected' then
        v_notification_type := 'change.your_change_rejected';
        v_category := 'governance_state_change'; v_priority := 'medium';
        select array[author_profile_id]::uuid[] into v_recipients
          from public.changes where id = new.subject_id;

      when new.event_type = 'change.withdrawn' then
        v_notification_type := 'change.your_change_withdrawn';
        v_category := 'governance_state_change'; v_priority := 'low';
        select array[author_profile_id]::uuid[] into v_recipients
          from public.changes where id = new.subject_id;

      -- ================= RELEASE cluster (2) =================
      when new.event_type = 'release.finalized' then
        v_notification_type := 'release.published_in_your_project';
        v_category := 'project_activity'; v_priority := 'medium';
        -- Project-broadcast rule: all project_participants (excluding actor)
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.project_participants pp
              left join public.workspace_members wm on wm.id = pp.workspace_member_id
              left join public.stakeholders sh on sh.id = pp.stakeholder_id
             where pp.project_id = new.project_id
               and pp.status = 'active'
          ) p
         where p.profile_id is not null;

      when new.event_type = 'release.withdrawn' then
        v_notification_type := 'release.withdrawn_in_your_project';
        v_category := 'governance_state_change'; v_priority := 'high';
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.project_participants pp
              left join public.workspace_members wm on wm.id = pp.workspace_member_id
              left join public.stakeholders sh on sh.id = pp.stakeholder_id
             where pp.project_id = new.project_id
               and pp.status = 'active'
          ) p
         where p.profile_id is not null;

      -- ================= ASSET cluster (2) =================
      when new.event_type = 'asset.archived' then
        v_notification_type := 'asset.archived_in_your_project';
        v_category := 'project_activity'; v_priority := 'low';
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.project_participants pp
              left join public.workspace_members wm on wm.id = pp.workspace_member_id
              left join public.stakeholders sh on sh.id = pp.stakeholder_id
             where pp.project_id = new.project_id
               and pp.status = 'active'
          ) p
         where p.profile_id is not null;

      when new.event_type = 'asset.unarchived' then
        v_notification_type := 'asset.unarchived_in_your_project';
        v_category := 'project_activity'; v_priority := 'low';
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.project_participants pp
              left join public.workspace_members wm on wm.id = pp.workspace_member_id
              left join public.stakeholders sh on sh.id = pp.stakeholder_id
             where pp.project_id = new.project_id
               and pp.status = 'active'
          ) p
         where p.profile_id is not null;

      -- ================= PROJECT cluster (5) =================
      when new.event_type = 'project.archived' then
        v_notification_type := 'project.archived_in_your_project';
        v_category := 'governance_state_change'; v_priority := 'medium';
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.project_participants pp
              left join public.workspace_members wm on wm.id = pp.workspace_member_id
              left join public.stakeholders sh on sh.id = pp.stakeholder_id
             where pp.project_id = new.project_id
               and pp.status = 'active'
          ) p
         where p.profile_id is not null;

      when new.event_type = 'project.unarchived' then
        v_notification_type := 'project.unarchived_in_your_project';
        v_category := 'project_activity'; v_priority := 'low';
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.project_participants pp
              left join public.workspace_members wm on wm.id = pp.workspace_member_id
              left join public.stakeholders sh on sh.id = pp.stakeholder_id
             where pp.project_id = new.project_id
               and pp.status = 'active'
          ) p
         where p.profile_id is not null;

      when new.event_type = 'project.participant.added' then
        v_notification_type := 'project.you_were_added';
        v_category := 'assigned_to_me'; v_priority := 'high';
        select array[coalesce(wm.user_id, sh.user_id)]::uuid[] into v_recipients
          from public.project_participants pp
          left join public.workspace_members wm on wm.id = pp.workspace_member_id
          left join public.stakeholders sh on sh.id = pp.stakeholder_id
         where pp.id = new.subject_id;

      when new.event_type = 'project.participant.role_changed' then
        v_notification_type := 'project.your_role_changed';
        v_category := 'governance_state_change'; v_priority := 'medium';
        select array[coalesce(wm.user_id, sh.user_id)]::uuid[] into v_recipients
          from public.project_participants pp
          left join public.workspace_members wm on wm.id = pp.workspace_member_id
          left join public.stakeholders sh on sh.id = pp.stakeholder_id
         where pp.id = new.subject_id;

      when new.event_type = 'project.participant.removed' then
        v_notification_type := 'project.you_were_removed';
        v_category := 'governance_state_change'; v_priority := 'high';
        -- Prefer snapshot-carried profile id if the participant row is gone
        v_recipients := array[nullif(v_snap->>'profile_id', '')::uuid];
        if v_recipients[1] is null then
          select array[coalesce(wm.user_id, sh.user_id)]::uuid[] into v_recipients
            from public.project_participants pp
            left join public.workspace_members wm on wm.id = pp.workspace_member_id
            left join public.stakeholders sh on sh.id = pp.stakeholder_id
           where pp.id = new.subject_id;
        end if;

      -- ================= WORKSPACE / STAKEHOLDER / INVITATION cluster (9) =================
      when new.event_type = 'workspace.member.invited' then
        -- Invitee-by-email (pre-profile): email_payload only, no in-app row.
        -- v1 handling: skip (no recipient profile yet).
        v_recipients := array[]::uuid[];

      when new.event_type = 'workspace.member.activated' then
        v_notification_type := 'workspace.your_invitation_was_accepted';
        v_category := 'system'; v_priority := 'medium';
        -- Inviter: read from invitation invited_by
        v_recipients := array[nullif(v_snap->>'invited_by_profile_id', '')::uuid];

      when new.event_type = 'workspace.member.role_changed' then
        v_notification_type := 'workspace.your_role_changed';
        v_category := 'governance_state_change'; v_priority := 'high';
        select array[user_id]::uuid[] into v_recipients
          from public.workspace_members where id = new.subject_id;

      when new.event_type = 'workspace.member.suspended' then
        v_notification_type := 'workspace.you_were_suspended';
        v_category := 'governance_state_change'; v_priority := 'critical';
        v_channels := array['in_app','email_payload']::text[];
        select array[user_id]::uuid[] into v_recipients
          from public.workspace_members where id = new.subject_id;

      when new.event_type = 'workspace.member.removed' then
        v_notification_type := 'workspace.you_were_removed';
        v_category := 'governance_state_change'; v_priority := 'critical';
        v_channels := array['in_app','email_payload']::text[];
        v_recipients := array[nullif(v_snap->>'user_id', '')::uuid];

      when new.event_type = 'stakeholder.invited' then
        -- Invitee-by-email (pre-profile): skip in-app row in v1.
        v_recipients := array[]::uuid[];

      when new.event_type = 'stakeholder.claimed' then
        v_notification_type := 'stakeholder.claimed_by_recipient';
        v_category := 'system'; v_priority := 'medium';
        v_recipients := array[nullif(v_snap->>'invited_by_profile_id', '')::uuid];

      when new.event_type = 'stakeholder.revoked' then
        v_notification_type := 'stakeholder.you_were_revoked';
        v_category := 'governance_state_change'; v_priority := 'high';
        select array[user_id]::uuid[] into v_recipients
          from public.stakeholders where id = new.subject_id;

      when new.event_type = 'invitation.expired' then
        v_notification_type := 'invitation.your_invitation_expired';
        v_category := 'system'; v_priority := 'low';
        v_recipients := array[nullif(v_snap->>'invited_by_profile_id', '')::uuid];

      else
        -- Feed-only / reserved-forward event: silent skip per G-51.
        return new;
    end case;

    -- No recipients resolved → nothing to write.
    if v_recipients is null or array_length(v_recipients, 1) is null then
      return new;
    end if;

    -- Materialize payload once (denormalized rendering-ready).
    -- Actor display name (best-effort; NULL for system events).
    if new.actor_profile_id is not null then
      select coalesce(display_name, 'Former member') into v_actor_display
        from public.profiles where id = new.actor_profile_id;
    else
      v_actor_display := 'System';
    end if;

    -- Deep-link kind derived from event source module.
    v_deep_link_kind := split_part(new.event_type, '.', 1);
    v_deep_link_id := new.subject_id;
    v_deep_link := jsonb_build_object(
      'kind', v_deep_link_kind,
      'id', v_deep_link_id,
      'workspace_id', new.workspace_id,
      'project_id', new.project_id
    );

    v_preview := coalesce(new.subject_label, new.event_type);

    v_payload := jsonb_build_object(
      'source_event_type', new.event_type,
      'actor_profile_id', new.actor_profile_id,
      'actor_display_name', v_actor_display,
      'subject_kind', new.subject_kind,
      'subject_id', new.subject_id,
      'subject_label', new.subject_label,
      'occurred_at', new.occurred_at,
      'deep_link', v_deep_link,
      'preview_snippet', v_preview
    );

    -- INSERT one row per resolved recipient. Self-exclusion applied inline.
    -- Dedup via ON CONFLICT DO NOTHING targeting the I-7 partial unique index.
    foreach v_recipient_id in array v_recipients loop
      if v_recipient_id is null then
        continue;
      end if;
      -- Self-exclusion (§9.8, G-8, G-15): actor never notified about own action.
      -- Skipped naturally for actor_kind='system' (actor_profile_id IS NULL).
      if new.actor_profile_id is not null and v_recipient_id = new.actor_profile_id then
        continue;
      end if;

      insert into public.notifications (
        workspace_id, project_id, recipient_profile_id, source_event_id,
        event_type, notification_type, category, priority,
        channels_attempted, delivery_state,
        subject_kind, subject_id, subject_label, actor_profile_id,
        payload
      ) values (
        new.workspace_id, new.project_id, v_recipient_id, new.id,
        new.event_type, v_notification_type, v_category, v_priority,
        v_channels, 'delivered',
        coalesce(new.subject_kind, v_deep_link_kind), new.subject_id,
        new.subject_label, new.actor_profile_id,
        v_payload
      )
      on conflict on constraint notifications_dedup_uniq_idx do nothing;
    end loop;

    return new;

  exception
    when others then
      raise warning 'notification router failed for event % (type %): %',
        new.id, new.event_type, sqlerrm;
      return new;
  end;
end;
$$;

comment on function public.resolve_notification_router_targets() is
  'APP 010 §9.1: routing bridge trigger function. Consumes activity_events AFTER INSERT via enforce_notification_router_bridge. Materializes per-recipient rows in public.notifications. SECURITY DEFINER + SET search_path = "". Body wrapped in BEGIN…EXCEPTION WHEN OTHERS THEN RAISE WARNING…; RETURN NEW; END — router failures NEVER roll back the parent workflow transaction (inviolable, §2.8, §20.8). F-2 explicit notification.* recursion guard at step 1a.';

revoke all on function public.resolve_notification_router_targets() from public;
revoke all on function public.resolve_notification_router_targets() from anon;
revoke all on function public.resolve_notification_router_targets() from authenticated;
-- NO GRANT: invoked via trigger dispatcher only.

------------------------------------------------------------------------------
-- 3. Trigger: enforce_notification_router_bridge — AFTER INSERT on activity_events (§9.1)
------------------------------------------------------------------------------
-- Boundary-additive extension on frozen activity_events (§3.3 rationale):
--   * AFTER INSERT (does not modify the frozen row)
--   * Reads NEW; writes only to the new notifications table
--   * Does not modify activity_events schema, RLS, or the frozen
--     activity_events_no_update / activity_events_no_delete triggers
--   * Function body is exception-safe (never rolls back workflow TX)

drop trigger if exists enforce_notification_router_bridge on public.activity_events;
create trigger enforce_notification_router_bridge
  after insert on public.activity_events
  for each row execute function public.resolve_notification_router_targets();

------------------------------------------------------------------------------
-- 4. READ RPC: list_notifications_inbox (§15.1)
------------------------------------------------------------------------------

create or replace function public.list_notifications_inbox(
  p_ws_id             uuid,
  p_tab               text,
  p_category_filter   text[],
  p_priority_filter   text[],
  p_source_filter     text[],
  p_date_from         timestamptz,
  p_date_to           timestamptz,
  p_cursor_created_at timestamptz,
  p_cursor_id         uuid,
  p_limit             int
)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_uid          uuid;
  v_limit        int;
  v_rows         jsonb;
  v_next_cursor  jsonb;
  v_facets       jsonb;
  v_total        int;
  v_unread       int;
  v_by_cat       jsonb;
  v_by_pri       jsonb;
  v_has_more     boolean;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'list_notifications_inbox: authentication required' using errcode='42501';
  end if;
  -- Personal capability check (implicit-pass for every authenticated user in v1).
  if not public.lign_has_capability(null, p_ws_id, 'notification.view') then
    raise exception 'list_notifications_inbox: forbidden (notification.view)' using errcode='42501';
  end if;

  v_limit := coalesce(nullif(p_limit, 0), 50);
  if v_limit > 200 then v_limit := 200; end if;

  with base as (
    select n.*
      from public.notifications n
     where n.recipient_profile_id = v_uid
       and n.workspace_id = p_ws_id
       and (
         coalesce(p_tab, 'all') = 'all'
           and n.dismissed_at is null and n.archived_at is null
         or coalesce(p_tab, 'all') = 'unread'
           and n.read_at is null and n.dismissed_at is null and n.archived_at is null
         or coalesce(p_tab, 'all') = 'mentions'
           and n.category = 'mentions' and n.dismissed_at is null and n.archived_at is null
         or coalesce(p_tab, 'all') = 'assigned'
           and n.category = 'assigned_to_me' and n.dismissed_at is null and n.archived_at is null
         or coalesce(p_tab, 'all') = 'governance'
           and n.category = 'governance_state_change' and n.dismissed_at is null and n.archived_at is null
         or coalesce(p_tab, 'all') = 'archived'
           and n.archived_at is not null
       )
       and (p_category_filter is null or n.category = any (p_category_filter))
       and (p_priority_filter is null or n.priority = any (p_priority_filter))
       and (p_source_filter is null or split_part(n.event_type, '.', 1) = any (p_source_filter))
       and (p_date_from is null or n.created_at >= p_date_from)
       and (p_date_to is null or n.created_at <= p_date_to)
  ),
  paged as (
    select *
      from base
     where (p_cursor_created_at is null and p_cursor_id is null)
        or (created_at, id) < (p_cursor_created_at, p_cursor_id)
     order by created_at desc, id desc
     limit v_limit + 1
  ),
  paged_capped as (
    select * from paged order by created_at desc, id desc limit v_limit
  )
  select
    coalesce(jsonb_agg(to_jsonb(pc) order by pc.created_at desc, pc.id desc), '[]'::jsonb),
    (select count(*) > v_limit from paged)
  into v_rows, v_has_more
  from paged_capped pc;

  -- Compute next_cursor: last row's (created_at, id) if has_more.
  if v_has_more and jsonb_array_length(v_rows) > 0 then
    v_next_cursor := jsonb_build_object(
      'created_at', v_rows -> (jsonb_array_length(v_rows) - 1) ->> 'created_at',
      'id', v_rows -> (jsonb_array_length(v_rows) - 1) ->> 'id'
    );
  else
    v_next_cursor := null;
  end if;

  -- Facets: total non-dismissed/archived + unread + per-category + per-priority.
  select
    count(*)::int,
    count(*) filter (where read_at is null)::int,
    coalesce(jsonb_object_agg(cat, cnt) filter (where cat is not null), '{}'::jsonb),
    coalesce(jsonb_object_agg(pri, pcnt) filter (where pri is not null), '{}'::jsonb)
    into v_total, v_unread, v_by_cat, v_by_pri
  from (
    select category as cat, priority as pri, count(*) as cnt, count(*) as pcnt, read_at
      from public.notifications
     where recipient_profile_id = v_uid
       and workspace_id = p_ws_id
       and dismissed_at is null
       and archived_at is null
     group by category, priority, read_at
  ) s;

  v_facets := jsonb_build_object(
    'total_count', v_total,
    'unread_count', v_unread,
    'by_category', v_by_cat,
    'by_priority', v_by_pri
  );

  return jsonb_build_object(
    'rows', v_rows,
    'next_cursor', v_next_cursor,
    'has_more', v_has_more,
    'facets', v_facets
  );
end $$;

comment on function public.list_notifications_inbox(uuid, text, text[], text[], text[], timestamptz, timestamptz, timestamptz, uuid, int) is
  'APP 010 §15.1: primary Inbox read. Returns paginated hydrated notification rows for the caller in the workspace, filtered by tab + filter chips + cursor. SECURITY DEFINER + notification.view capability check + recipient_profile_id = auth.uid() in-body predicate. Sorted by (created_at DESC, id DESC).';

revoke all on function public.list_notifications_inbox(uuid, text, text[], text[], text[], timestamptz, timestamptz, timestamptz, uuid, int) from public;
revoke all on function public.list_notifications_inbox(uuid, text, text[], text[], text[], timestamptz, timestamptz, timestamptz, uuid, int) from anon;
revoke all on function public.list_notifications_inbox(uuid, text, text[], text[], text[], timestamptz, timestamptz, timestamptz, uuid, int) from authenticated;
grant execute on function public.list_notifications_inbox(uuid, text, text[], text[], text[], timestamptz, timestamptz, timestamptz, uuid, int) to authenticated, service_role;

------------------------------------------------------------------------------
-- 5. READ RPC: get_notification (§15.3)
------------------------------------------------------------------------------

create or replace function public.get_notification(p_notification_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_row public.notifications%rowtype;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'get_notification: authentication required' using errcode='42501';
  end if;
  if not public.lign_has_capability(null, null, 'notification.view') then
    raise exception 'get_notification: forbidden (notification.view)' using errcode='42501';
  end if;

  select * into v_row
    from public.notifications
   where id = p_notification_id
     and recipient_profile_id = v_uid;

  if v_row.id is null then
    return null;
  end if;

  return to_jsonb(v_row);
end $$;

comment on function public.get_notification(uuid) is
  'APP 010 §15.3: single-row read. Powers /deep/notification/:id resolver and Inbox ?highlight= param. Returns NULL when the caller is not the recipient or the row does not exist (avoids leaking existence). SECURITY DEFINER. Clients read actor_display_name from row.payload.actor_display_name (F-5 canonical position).';

revoke all on function public.get_notification(uuid) from public;
revoke all on function public.get_notification(uuid) from anon;
revoke all on function public.get_notification(uuid) from authenticated;
grant execute on function public.get_notification(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 6. READ RPC: get_notification_badge_count (§15.4)
------------------------------------------------------------------------------

create or replace function public.get_notification_badge_count(p_ws_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_total     int;
  v_by_cat    jsonb;
  v_has_crit  boolean;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'get_notification_badge_count: authentication required' using errcode='42501';
  end if;
  if not public.lign_has_capability(null, p_ws_id, 'notification.view') then
    raise exception 'get_notification_badge_count: forbidden (notification.view)' using errcode='42501';
  end if;

  select
    coalesce(sum(cnt), 0)::int,
    coalesce(jsonb_object_agg(category, cnt) filter (where category is not null), '{}'::jsonb),
    bool_or(has_crit)
    into v_total, v_by_cat, v_has_crit
  from (
    select category,
           count(*)::int as cnt,
           bool_or(priority = 'critical') as has_crit
      from public.notifications
     where recipient_profile_id = v_uid
       and workspace_id = p_ws_id
       and read_at is null
       and dismissed_at is null
       and archived_at is null
       and priority <> 'informational'
     group by category
  ) s;

  return jsonb_build_object(
    'total_unread', v_total,
    'by_category', coalesce(v_by_cat, '{}'::jsonb),
    'has_critical', coalesce(v_has_crit, false)
  );
end $$;

comment on function public.get_notification_badge_count(uuid) is
  'APP 010 §15.4 / §14.1: bell-badge unread count. Returns {total_unread int, by_category jsonb, has_critical boolean}. Excludes priority=informational per §7.1. Powered by partial index I-1. SECURITY DEFINER.';

revoke all on function public.get_notification_badge_count(uuid) from public;
revoke all on function public.get_notification_badge_count(uuid) from anon;
revoke all on function public.get_notification_badge_count(uuid) from authenticated;
grant execute on function public.get_notification_badge_count(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 7. READ RPC: get_notification_center (§15.5)
------------------------------------------------------------------------------

create or replace function public.get_notification_center(p_ws_id uuid, p_limit int)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_uid   uuid;
  v_limit int;
  v_rows  jsonb;
  v_total int;
  v_more  boolean;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'get_notification_center: authentication required' using errcode='42501';
  end if;
  if not public.lign_has_capability(null, p_ws_id, 'notification.view') then
    raise exception 'get_notification_center: forbidden (notification.view)' using errcode='42501';
  end if;

  v_limit := coalesce(nullif(p_limit, 0), 15);
  if v_limit > 100 then v_limit := 100; end if;

  select
    coalesce(jsonb_agg(to_jsonb(n) order by n.created_at desc, n.id desc), '[]'::jsonb)
    into v_rows
  from (
    select *
      from public.notifications
     where recipient_profile_id = v_uid
       and workspace_id = p_ws_id
       and read_at is null
       and dismissed_at is null
       and archived_at is null
     order by created_at desc, id desc
     limit v_limit
  ) n;

  select count(*)::int into v_total
    from public.notifications
   where recipient_profile_id = v_uid
     and workspace_id = p_ws_id
     and read_at is null
     and dismissed_at is null
     and archived_at is null;

  v_more := v_total > v_limit;

  return jsonb_build_object(
    'rows', v_rows,
    'has_more', v_more,
    'total_unread', v_total
  );
end $$;

comment on function public.get_notification_center(uuid, int) is
  'APP 010 §15.5 / §13: Notification Center popover contents. Returns top N (default 15) unread notifications hydrated with rendering-ready payload, plus has_more flag. SECURITY DEFINER + notification.view.';

revoke all on function public.get_notification_center(uuid, int) from public;
revoke all on function public.get_notification_center(uuid, int) from anon;
revoke all on function public.get_notification_center(uuid, int) from authenticated;
grant execute on function public.get_notification_center(uuid, int) to authenticated, service_role;

------------------------------------------------------------------------------
-- 8. READ RPC: list_notifications_by_source (§15.6)
------------------------------------------------------------------------------

create or replace function public.list_notifications_by_source(
  p_source_kind text,
  p_source_id   uuid,
  p_limit       int
)
returns setof jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_uid   uuid;
  v_limit int;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'list_notifications_by_source: authentication required' using errcode='42501';
  end if;
  if not public.lign_has_capability(null, null, 'notification.view') then
    raise exception 'list_notifications_by_source: forbidden (notification.view)' using errcode='42501';
  end if;

  v_limit := coalesce(nullif(p_limit, 0), 50);
  if v_limit > 200 then v_limit := 200; end if;

  return query
    select to_jsonb(n)
      from public.notifications n
     where n.subject_kind = p_source_kind
       and n.subject_id = p_source_id
       and n.recipient_profile_id = v_uid
     order by n.created_at desc, n.id desc
     limit v_limit;
end $$;

comment on function public.list_notifications_by_source(text, uuid, int) is
  'APP 010 §15.6: reverse-lookup. "Give me every notification citing this subject." RLS still filters to the caller''s own rows. SECURITY DEFINER. Powered by partial index I-8.';

revoke all on function public.list_notifications_by_source(text, uuid, int) from public;
revoke all on function public.list_notifications_by_source(text, uuid, int) from anon;
revoke all on function public.list_notifications_by_source(text, uuid, int) from authenticated;
grant execute on function public.list_notifications_by_source(text, uuid, int) to authenticated, service_role;

------------------------------------------------------------------------------
-- 9. WRITE RPC: mark_notification_read (§16.1)
------------------------------------------------------------------------------

create or replace function public.mark_notification_read(p_notification_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid;
  v_affected int;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'mark_notification_read: authentication required' using errcode='42501';
  end if;
  if not public.lign_has_capability(null, null, 'notification.manage') then
    raise exception 'mark_notification_read: forbidden (notification.manage)' using errcode='42501';
  end if;

  perform set_config('lign.allow_notification_rpc_write', 'true', true);
  update public.notifications
     set read_at = now()
   where id = p_notification_id
     and recipient_profile_id = v_uid
     and read_at is null;
  get diagnostics v_affected = row_count;
  perform set_config('lign.allow_notification_rpc_write', 'false', true);

  return v_affected > 0;
end $$;

comment on function public.mark_notification_read(uuid) is
  'APP 010 §16.1: set read_at=now() on a single notification. Idempotent (no-op if already read). Self-only via WHERE recipient_profile_id = auth.uid(). Sets lign.allow_notification_rpc_write GUC around UPDATE. SECURITY DEFINER + notification.manage.';

revoke all on function public.mark_notification_read(uuid) from public;
revoke all on function public.mark_notification_read(uuid) from anon;
revoke all on function public.mark_notification_read(uuid) from authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 10. WRITE RPC: mark_notification_unread (§16.2)
------------------------------------------------------------------------------

create or replace function public.mark_notification_unread(p_notification_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid;
  v_affected int;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'mark_notification_unread: authentication required' using errcode='42501';
  end if;
  if not public.lign_has_capability(null, null, 'notification.manage') then
    raise exception 'mark_notification_unread: forbidden (notification.manage)' using errcode='42501';
  end if;

  perform set_config('lign.allow_notification_rpc_write', 'true', true);
  update public.notifications
     set read_at = null
   where id = p_notification_id
     and recipient_profile_id = v_uid
     and read_at is not null;
  get diagnostics v_affected = row_count;
  perform set_config('lign.allow_notification_rpc_write', 'false', true);

  return v_affected > 0;
end $$;

comment on function public.mark_notification_unread(uuid) is
  'APP 010 §16.2 / G-5: set read_at=NULL on a single notification. Idempotent. Self-only. SECURITY DEFINER + notification.manage.';

revoke all on function public.mark_notification_unread(uuid) from public;
revoke all on function public.mark_notification_unread(uuid) from anon;
revoke all on function public.mark_notification_unread(uuid) from authenticated;
grant execute on function public.mark_notification_unread(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 11. WRITE RPC: mark_all_notifications_read (§16.3)
------------------------------------------------------------------------------

create or replace function public.mark_all_notifications_read(
  p_ws_id    uuid,
  p_category text default null
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid;
  v_affected int;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'mark_all_notifications_read: authentication required' using errcode='42501';
  end if;
  if not public.lign_has_capability(null, p_ws_id, 'notification.manage') then
    raise exception 'mark_all_notifications_read: forbidden (notification.manage)' using errcode='42501';
  end if;

  perform set_config('lign.allow_notification_rpc_write', 'true', true);
  update public.notifications
     set read_at = now()
   where recipient_profile_id = v_uid
     and workspace_id = p_ws_id
     and read_at is null
     and dismissed_at is null
     and archived_at is null
     and (p_category is null or category = p_category);
  get diagnostics v_affected = row_count;
  perform set_config('lign.allow_notification_rpc_write', 'false', true);

  return v_affected;
end $$;

comment on function public.mark_all_notifications_read(uuid, text) is
  'APP 010 §16.3 / G-10 / G-47: single UPDATE per G-10; scans I-1 partial index. Includes informational notifications per G-47. Optional category filter. Self-only. SECURITY DEFINER + notification.manage.';

revoke all on function public.mark_all_notifications_read(uuid, text) from public;
revoke all on function public.mark_all_notifications_read(uuid, text) from anon;
revoke all on function public.mark_all_notifications_read(uuid, text) from authenticated;
grant execute on function public.mark_all_notifications_read(uuid, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 12. WRITE RPC: dismiss_notification (§16.5)
------------------------------------------------------------------------------

create or replace function public.dismiss_notification(p_notification_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid;
  v_affected int;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'dismiss_notification: authentication required' using errcode='42501';
  end if;
  if not public.lign_has_capability(null, null, 'notification.manage') then
    raise exception 'dismiss_notification: forbidden (notification.manage)' using errcode='42501';
  end if;

  perform set_config('lign.allow_notification_rpc_write', 'true', true);
  update public.notifications
     set dismissed_at = now(),
         read_at = coalesce(read_at, now())
   where id = p_notification_id
     and recipient_profile_id = v_uid
     and dismissed_at is null;
  get diagnostics v_affected = row_count;
  perform set_config('lign.allow_notification_rpc_write', 'false', true);

  return v_affected > 0;
end $$;

comment on function public.dismiss_notification(uuid) is
  'APP 010 §16.5: set dismissed_at=now(); also sets read_at=now() if unread (dismissing implies acknowledged). One-way in v1 (no undismiss RPC). Self-only. SECURITY DEFINER + notification.manage.';

revoke all on function public.dismiss_notification(uuid) from public;
revoke all on function public.dismiss_notification(uuid) from anon;
revoke all on function public.dismiss_notification(uuid) from authenticated;
grant execute on function public.dismiss_notification(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 13. WRITE RPC: archive_notification (§16.7)
------------------------------------------------------------------------------

create or replace function public.archive_notification(p_notification_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid;
  v_affected int;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'archive_notification: authentication required' using errcode='42501';
  end if;
  if not public.lign_has_capability(null, null, 'notification.manage') then
    raise exception 'archive_notification: forbidden (notification.manage)' using errcode='42501';
  end if;

  perform set_config('lign.allow_notification_rpc_write', 'true', true);
  update public.notifications
     set archived_at = now(),
         read_at = coalesce(read_at, now())
   where id = p_notification_id
     and recipient_profile_id = v_uid
     and archived_at is null;
  get diagnostics v_affected = row_count;
  perform set_config('lign.allow_notification_rpc_write', 'false', true);

  return v_affected > 0;
end $$;

comment on function public.archive_notification(uuid) is
  'APP 010 §16.7 / G-40: set archived_at=now(); also sets read_at=now() if unread. One-way in v1 (unarchive RESERVED for future wave). Self-only. SECURITY DEFINER + notification.manage.';

revoke all on function public.archive_notification(uuid) from public;
revoke all on function public.archive_notification(uuid) from anon;
revoke all on function public.archive_notification(uuid) from authenticated;
grant execute on function public.archive_notification(uuid) to authenticated, service_role;
