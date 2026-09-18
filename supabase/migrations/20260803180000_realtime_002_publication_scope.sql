-- REALTIME 002: enable Postgres Changes for the 8 frozen MVP tables only.
-- Nothing else. RLS on these tables remains the sole authorization boundary
-- (Realtime v2 re-runs SELECT policies per subscriber per WAL record).
-- Publication membership is the entire realtime surface change for MVP; no
-- new RLS policies, no new roles, no schema changes, no triggers, no RPCs.

alter publication supabase_realtime add table
  public.comments,
  public.annotations,
  public.asset_versions,
  public.reviews,
  public.review_participants,
  public.approval_requests,
  public.approval_responses,
  public.design_assets;

comment on publication supabase_realtime is
  'REALTIME 002: MVP Postgres Changes surface — exactly 8 collaboration tables. RLS is the authorization boundary; client-side filters are performance narrowing only. Excluded on purpose: activity_events, files, version_files, profiles, workspaces, workspace_members, stakeholders, invitations, projects, collections, comment_edits, changes, decisions, releases, release_items, approval_request_approvers.';