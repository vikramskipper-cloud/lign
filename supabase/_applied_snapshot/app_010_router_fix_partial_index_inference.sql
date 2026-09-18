-- APP 010 fix: router ON CONFLICT must use inference (cols + WHERE) for partial
-- unique index, not ON CONSTRAINT (which is for table constraints only).
-- Additive fix; router function body only. No schema, no signature change.

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
  if new.event_type is null then
    return new;
  end if;

  -- F-2 explicit notification.* recursion guard (primary loop-guard).
  if new.event_type like 'notification.%' then
    return new;
  end if;

  begin
    v_snap := coalesce(new.subject_snapshot, '{}'::jsonb);
    v_channels := array['in_app']::text[];

    case
      when new.event_type = 'review.opened' then
        v_notification_type := 'review.assigned_to_you';
        v_category := 'assigned_to_me'; v_priority := 'high';
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

      when new.event_type = 'comment.mentioned' then
        v_notification_type := 'comment.mentioned_you';
        v_category := 'mentions'; v_priority := 'high';
        v_recipients := array[(v_snap->>'mentioned_profile_id')::uuid];

      when new.event_type = 'annotation.resolved' then
        v_notification_type := 'annotation.your_annotation_resolved';
        v_category := 'project_activity'; v_priority := 'low';
        select array[author_profile_id]::uuid[] into v_recipients
          from public.annotations where id = new.subject_id;

      when new.event_type = 'change.created' then
        v_notification_type := 'change.needs_leads_attention';
        v_category := 'project_activity'; v_priority := 'medium';
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

      when new.event_type = 'release.finalized' then
        v_notification_type := 'release.published_in_your_project';
        v_category := 'project_activity'; v_priority := 'medium';
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
        v_recipients := array[nullif(v_snap->>'profile_id', '')::uuid];
        if v_recipients[1] is null then
          select array[coalesce(wm.user_id, sh.user_id)]::uuid[] into v_recipients
            from public.project_participants pp
            left join public.workspace_members wm on wm.id = pp.workspace_member_id
            left join public.stakeholders sh on sh.id = pp.stakeholder_id
           where pp.id = new.subject_id;
        end if;

      when new.event_type = 'workspace.member.invited' then
        v_recipients := array[]::uuid[];

      when new.event_type = 'workspace.member.activated' then
        v_notification_type := 'workspace.your_invitation_was_accepted';
        v_category := 'system'; v_priority := 'medium';
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
        return new;
    end case;

    if v_recipients is null or array_length(v_recipients, 1) is null then
      return new;
    end if;

    if new.actor_profile_id is not null then
      select coalesce(display_name, 'Former member') into v_actor_display
        from public.profiles where id = new.actor_profile_id;
    else
      v_actor_display := 'System';
    end if;

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

    foreach v_recipient_id in array v_recipients loop
      if v_recipient_id is null then
        continue;
      end if;
      if new.actor_profile_id is not null and v_recipient_id = new.actor_profile_id then
        continue;
      end if;

      -- ON CONFLICT with inference on partial unique index I-7 (must include WHERE).
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
      on conflict (recipient_profile_id, source_event_id, notification_type)
        where archived_at is null
        do nothing;
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
  'APP 010 §9.1: routing bridge trigger function. Consumes activity_events AFTER INSERT via enforce_notification_router_bridge. Materializes per-recipient rows in public.notifications. SECURITY DEFINER + SET search_path = "". Body wrapped in BEGIN…EXCEPTION WHEN OTHERS THEN RAISE WARNING…; RETURN NEW; END — router failures NEVER roll back the parent workflow transaction (inviolable, §2.8, §20.8). F-2 explicit notification.* recursion guard at step 1a. ON CONFLICT infers on partial unique index (recipient_profile_id, source_event_id, notification_type) WHERE archived_at IS NULL.';

revoke all on function public.resolve_notification_router_targets() from public;
revoke all on function public.resolve_notification_router_targets() from anon;
revoke all on function public.resolve_notification_router_targets() from authenticated;
