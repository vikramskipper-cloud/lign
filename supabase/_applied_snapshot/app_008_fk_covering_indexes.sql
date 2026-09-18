-- APP 008: covering composite indexes for the two additive composite FKs
-- so the unindexed_foreign_keys linter recognizes them. Both are partial on
-- the nullable leading column to stay small.

create index if not exists comments_target_requirement_workspace_covering_idx
  on public.comments (target_requirement_id, workspace_id)
  where target_requirement_id is not null;

create index if not exists requirements_owner_workspace_covering_idx
  on public.requirements (owner_profile_id, workspace_id)
  where owner_profile_id is not null;
