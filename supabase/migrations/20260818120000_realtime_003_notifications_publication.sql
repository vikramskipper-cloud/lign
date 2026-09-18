-- REALTIME 003 (APP 011 wave 1B): add public.notifications to the Postgres
-- Changes surface.
--
-- Authority: APP 010 §25.2 states that adding `notifications` to the
-- publication is a REALTIME re-freeze event and names APP 011 as the authority
-- for it. Reviewed and approved in docs/APP_011_BACKEND_DELTA.md §2.
--
-- This is the entire backend surface of APP 011. No table, column, index,
-- constraint, policy, trigger, function, RPC, capability, event or grant.
--
-- Safety:
--   * Publication membership controls what Realtime STREAMS, not what a client
--     may READ. Realtime v2 re-runs the SELECT policy per subscriber per WAL
--     record, so this widens no access.
--   * notifications_select is already scoped to
--     recipient_profile_id = auth.uid() plus the notification.view capability,
--     so a subscriber can only ever receive their own rows.
--   * Writes remain impossible over this transport: notifications_insert is
--     deny, notifications_update requires the RPC-only-write GUC, and
--     notifications_delete is deny.
--   * The activity_events AFTER INSERT router bridge is untouched; publication
--     membership is orthogonal to trigger execution.
--
-- Reversible with:
--   alter publication supabase_realtime drop table public.notifications;

alter publication supabase_realtime add table public.notifications;

comment on publication supabase_realtime is
  'REALTIME 002 + 003: Postgres Changes surface — 8 collaboration tables (comments, annotations, asset_versions, reviews, review_participants, approval_requests, approval_responses, design_assets) plus notifications (REALTIME 003, APP 011 wave 1B; recipient-scoped by RLS). RLS is the authorization boundary; client-side filters are performance narrowing only. Excluded on purpose: activity_events, files, version_files, profiles, workspaces, workspace_members, stakeholders, invitations, projects, collections, comment_edits, changes, decisions, releases, release_items, approval_request_approvers.';
