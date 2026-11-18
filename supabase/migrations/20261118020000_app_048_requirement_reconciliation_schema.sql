-- Reviewed operational handoff of immutable agreed brief revisions.
create table public.brief_requirement_changes (
 revision_id uuid not null, item_id text not null, project_id uuid not null,
 kind text not null check(kind in ('added','changed','unchanged','removed')),
 previous_requirement_id uuid, requirement_id uuid,
 previous_item jsonb, proposed_item jsonb,
 prepared_content jsonb, state text not null default 'pending' check(state in ('pending','applied','matched')),
 outcome text, matched_item_id text, review_note text not null default '',
 applied_by uuid references public.profiles(id), applied_at timestamptz,
 created_at timestamptz not null default now(),
 primary key(revision_id,item_id),
 foreign key(revision_id,project_id) references public.project_brief_revisions(id,project_id),
 foreign key(previous_requirement_id,project_id) references public.requirements(id,project_id),
 foreign key(requirement_id,project_id) references public.requirements(id,project_id),
 check(outcome is null or outcome in ('activated','reused','retired','retained','matched'))
);
create index brief_requirement_changes_project_idx on public.brief_requirement_changes(project_id,revision_id);
create index brief_requirement_changes_old_idx on public.brief_requirement_changes(previous_requirement_id,project_id);
create index brief_requirement_changes_new_idx on public.brief_requirement_changes(requirement_id,project_id);
create index brief_requirement_changes_actor_idx on public.brief_requirement_changes(applied_by);
create unique index brief_requirement_changes_source_unique on public.brief_requirement_changes(revision_id,previous_requirement_id) where previous_requirement_id is not null and state<>'matched';
alter table public.brief_requirement_changes enable row level security;
create policy brief_requirement_changes_read on public.brief_requirement_changes for select to authenticated using(exists(select 1 from public.projects p where p.id=project_id and public.lign_has_capability(p.id,p.workspace_id,'requirement.view') and (public.lign_manage_project_brief(p.id) or coalesce(public.lign_project_role(p.id) in ('lead','contributor'),false))));
revoke all on public.brief_requirement_changes from public,anon,authenticated;
grant select on public.brief_requirement_changes to authenticated;
