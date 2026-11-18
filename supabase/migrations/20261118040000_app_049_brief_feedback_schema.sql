create table public.brief_feedback_items (
 id uuid primary key default gen_random_uuid(),project_id uuid not null references public.projects(id),source_revision_id uuid not null,
 target_kind text not null default 'overall' check(target_kind in ('overall','field','item','reference')),target_id text,
 body text not null check(length(trim(body)) between 1 and 5000),from_decision boolean not null default false,
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),
 status text not null default 'open' check(status in ('open','addressed','verified')),edit_version bigint not null default 1,
 response text not null default '' check(length(response)<=5000),addressed_by uuid references public.profiles(id),addressed_at timestamptz,
 response_edit_version bigint,response_content_digest text,response_revision_id uuid,
 verified_by uuid references public.profiles(id),verified_at timestamptz,verified_revision_id uuid,
 unique(id,project_id),foreign key(source_revision_id,project_id) references public.project_brief_revisions(id,project_id),
 foreign key(response_revision_id,project_id) references public.project_brief_revisions(id,project_id),
 foreign key(verified_revision_id,project_id) references public.project_brief_revisions(id,project_id),
 check((target_kind='overall' and target_id is null) or (target_kind<>'overall' and target_id is not null))
);
create index brief_feedback_project_idx on public.brief_feedback_items(project_id,created_at);
create index brief_feedback_source_idx on public.brief_feedback_items(source_revision_id,project_id);
create index brief_feedback_response_idx on public.brief_feedback_items(response_revision_id,project_id);
create index brief_feedback_verified_revision_idx on public.brief_feedback_items(verified_revision_id,project_id);
create index brief_feedback_creator_idx on public.brief_feedback_items(created_by);
create index brief_feedback_addressed_idx on public.brief_feedback_items(addressed_by);
create index brief_feedback_verified_idx on public.brief_feedback_items(verified_by);
create unique index brief_feedback_decision_unique on public.brief_feedback_items(source_revision_id) where from_decision;
create table public.brief_feedback_events (
 id uuid primary key default gen_random_uuid(),feedback_id uuid not null,project_id uuid not null,
 actor_id uuid not null references public.profiles(id),action text not null check(action in ('created','addressed','included_in_revision','verified','reopened')),
 note text not null default '',revision_id uuid,created_at timestamptz not null default now(),
 foreign key(feedback_id,project_id) references public.brief_feedback_items(id,project_id),
 foreign key(revision_id,project_id) references public.project_brief_revisions(id,project_id)
);
create index brief_feedback_events_feedback_idx on public.brief_feedback_events(feedback_id,project_id,created_at);
create index brief_feedback_events_project_idx on public.brief_feedback_events(project_id);
create index brief_feedback_events_actor_idx on public.brief_feedback_events(actor_id);
create index brief_feedback_events_revision_idx on public.brief_feedback_events(revision_id,project_id);
alter table public.brief_feedback_items enable row level security;
alter table public.brief_feedback_events enable row level security;
create policy brief_feedback_items_read on public.brief_feedback_items for select to authenticated using(exists(select 1 from public.projects p where p.id=project_id and public.lign_has_capability(p.id,p.workspace_id,'project.view')));
create policy brief_feedback_events_read on public.brief_feedback_events for select to authenticated using(exists(select 1 from public.projects p where p.id=project_id and public.lign_has_capability(p.id,p.workspace_id,'project.view')));
revoke all on public.brief_feedback_items,public.brief_feedback_events from public,anon,authenticated;
grant select on public.brief_feedback_items,public.brief_feedback_events to authenticated;
