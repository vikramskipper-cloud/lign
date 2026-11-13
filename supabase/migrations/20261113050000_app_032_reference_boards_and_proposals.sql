-- APP 032: collaborative references, immutable proposal acceptance and two gates.
create table public.reference_boards (
 id uuid primary key default gen_random_uuid(),project_id uuid not null,workspace_id uuid not null,area_id uuid,
 title text not null check(length(trim(title)) between 1 and 160),kind text not null default 'moodboard' check(kind in ('moodboard','references','template')),
 description text not null default '' check(length(description)<=3000),edit_version bigint not null default 1,
 created_by uuid not null references public.profiles(id),archived_at timestamptz,created_at timestamptz not null default now(),
 unique(id,project_id,workspace_id),foreign key(project_id,workspace_id) references public.projects(id,workspace_id),
 foreign key(area_id,project_id,workspace_id) references public.project_areas(id,project_id,workspace_id)
);
create index reference_boards_project_idx on public.reference_boards(project_id,workspace_id);
create index reference_boards_area_idx on public.reference_boards(area_id,project_id,workspace_id);
create index reference_boards_author_idx on public.reference_boards(created_by);
create table public.reference_cards (
 id uuid primary key default gen_random_uuid(),board_id uuid not null,project_id uuid not null,workspace_id uuid not null,
 title text not null check(length(trim(title)) between 1 and 200),description text not null default '' check(length(description)<=5000),
 url text,file_id uuid,selected_for_brief boolean not null default false,edit_version bigint not null default 1,
 author_id uuid not null references public.profiles(id),archived_at timestamptz,created_at timestamptz not null default now(),
 unique(id,project_id,workspace_id),foreign key(board_id,project_id,workspace_id) references public.reference_boards(id,project_id,workspace_id)
);
create index reference_cards_board_idx on public.reference_cards(board_id,project_id,workspace_id);
create index reference_cards_project_idx on public.reference_cards(project_id,workspace_id);
create index reference_cards_author_idx on public.reference_cards(author_id);
create table public.reference_preferences (
 card_id uuid not null,project_id uuid not null,workspace_id uuid not null,user_id uuid not null references public.profiles(id),
 choice text not null check(choice in ('shortlisted','liked','rejected')),note text not null default '' check(length(note)<=2000),updated_at timestamptz not null default now(),
 primary key(card_id,user_id),foreign key(card_id,project_id,workspace_id) references public.reference_cards(id,project_id,workspace_id)
);
create index reference_preferences_card_idx on public.reference_preferences(card_id,project_id,workspace_id);
create index reference_preferences_user_idx on public.reference_preferences(user_id);
create index reference_preferences_project_idx on public.reference_preferences(project_id,workspace_id);
create table public.reference_comments (
 id uuid primary key default gen_random_uuid(),card_id uuid not null,project_id uuid not null,workspace_id uuid not null,
 author_id uuid not null references public.profiles(id),body text not null check(length(trim(body)) between 1 and 3000),created_at timestamptz not null default now(),
 foreign key(card_id,project_id,workspace_id) references public.reference_cards(id,project_id,workspace_id)
);
create index reference_comments_card_idx on public.reference_comments(card_id,project_id,workspace_id);
create index reference_comments_author_idx on public.reference_comments(author_id);
create index reference_comments_project_idx on public.reference_comments(project_id,workspace_id);

create table public.project_proposals (
 id uuid primary key default gen_random_uuid(),project_id uuid not null unique,workspace_id uuid not null,
 brief_revision_id uuid not null,document jsonb not null,respondent_id uuid,
 status text not null default 'draft' check(status in ('draft','submitted','awaiting_acceptance','accepted')),
 edit_version bigint not null default 1,revision_number integer not null default 0,current_revision_id uuid,
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(id,project_id,workspace_id),foreign key(project_id,workspace_id) references public.projects(id,workspace_id),
 foreign key(brief_revision_id,project_id) references public.project_brief_revisions(id,project_id),
 foreign key(respondent_id) references public.project_participants(id)
);
create index project_proposals_project_workspace_idx on public.project_proposals(project_id,workspace_id);
create index project_proposals_brief_idx on public.project_proposals(brief_revision_id,project_id);
create index project_proposals_respondent_idx on public.project_proposals(respondent_id);
create index project_proposals_author_idx on public.project_proposals(created_by);
create table public.proposal_revisions (
 id uuid primary key default gen_random_uuid(),proposal_id uuid not null,project_id uuid not null,workspace_id uuid not null,
 number integer not null,brief_revision_id uuid not null,document jsonb not null,snapshot jsonb not null,
 respondent_id uuid not null references public.project_participants(id),reviewed_by uuid not null references public.profiles(id),review_note text not null default '',created_at timestamptz not null default now(),
 unique(id,project_id),unique(proposal_id,number),
 foreign key(proposal_id,project_id,workspace_id) references public.project_proposals(id,project_id,workspace_id),
 foreign key(brief_revision_id,project_id) references public.project_brief_revisions(id,project_id)
);
create index proposal_revisions_proposal_idx on public.proposal_revisions(proposal_id,project_id,workspace_id);
create index proposal_revisions_project_idx on public.proposal_revisions(project_id,created_at);
create index proposal_revisions_brief_idx on public.proposal_revisions(brief_revision_id,project_id);
create index proposal_revisions_respondent_idx on public.proposal_revisions(respondent_id);
create index proposal_revisions_reviewer_idx on public.proposal_revisions(reviewed_by);
alter table public.project_proposals add constraint project_proposals_current_revision_fk foreign key(current_revision_id,project_id) references public.proposal_revisions(id,project_id);
create index project_proposals_current_revision_idx on public.project_proposals(current_revision_id,project_id);
create table public.proposal_decisions (
 id uuid primary key default gen_random_uuid(),revision_id uuid not null unique,project_id uuid not null,
 decision text not null check(decision in ('accepted','changes_requested')),note text not null default '' check(length(note)<=5000),
 actor_id uuid not null references public.profiles(id),created_at timestamptz not null default now(),
 foreign key(revision_id,project_id) references public.proposal_revisions(id,project_id)
);
create index proposal_decisions_revision_idx on public.proposal_decisions(revision_id,project_id);
create index proposal_decisions_project_idx on public.proposal_decisions(project_id,decision);
create index proposal_decisions_actor_idx on public.proposal_decisions(actor_id);
create table public.planning_files (
 id uuid primary key default gen_random_uuid(),project_id uuid not null,workspace_id uuid not null,
 reference_card_id uuid,proposal_id uuid,storage_path text not null unique,name text not null,mime_type text not null,size_bytes bigint not null check(size_bytes between 1 and 52428800),
 uploaded_by uuid not null references public.profiles(id),entity_version bigint not null,registered_at timestamptz,removed_at timestamptz,created_at timestamptz not null default now(),
 check(num_nonnulls(reference_card_id,proposal_id)=1),unique(id,project_id,workspace_id),
 foreign key(project_id,workspace_id) references public.projects(id,workspace_id),
 foreign key(reference_card_id,project_id,workspace_id) references public.reference_cards(id,project_id,workspace_id),
 foreign key(proposal_id,project_id,workspace_id) references public.project_proposals(id,project_id,workspace_id)
);
create index planning_files_card_idx on public.planning_files(reference_card_id,project_id,workspace_id);
create index planning_files_proposal_idx on public.planning_files(proposal_id,project_id,workspace_id);
create index planning_files_project_idx on public.planning_files(project_id,workspace_id);
create index planning_files_author_idx on public.planning_files(uploaded_by);
alter table public.reference_cards add constraint reference_cards_file_fk foreign key(file_id,project_id,workspace_id) references public.planning_files(id,project_id,workspace_id);
create index reference_cards_file_idx on public.reference_cards(file_id,project_id,workspace_id);

create or replace function public.planning_event(p_project_id uuid,p_kind text,p_subject uuid,p_payload jsonb default '{}')
returns void language sql security definer set search_path=''
as $$ insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload)
 select workspace_id,id,'project.updated',auth.uid(),'user','project',id,name,jsonb_build_object('planning_action',p_kind,'subject_id',p_subject)||p_payload from public.projects where id=p_project_id; $$;
create or replace function public.lign_reference_contributor(p_project_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.projects where id=p_project_id and archived_at is null and status<>'archived' and public.lign_has_capability(id,workspace_id,'comment.create')); $$;
create or replace function public.lign_prepare_proposal(p_project_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.projects where id=p_project_id and archived_at is null and status<>'archived' and public.lign_has_capability(id,workspace_id,'project.view')
 and (public.lign_manage_project_brief(id) or public.lign_project_role(id) in ('lead','contributor'))); $$;
create or replace function public.lign_edit_reference(p_card_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.reference_cards c join public.reference_boards b on b.id=c.board_id where c.id=p_card_id and c.archived_at is null and b.archived_at is null
 and public.lign_reference_contributor(c.project_id) and (c.author_id=auth.uid() or public.lign_manage_project_brief(c.project_id))); $$;
create or replace function public.lign_read_planning_file(p_file_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.planning_files f where f.id=p_file_id and f.registered_at is not null and public.lign_has_capability(f.project_id,f.workspace_id,'project.view')
 and (f.reference_card_id is not null or public.lign_prepare_proposal(f.project_id) or exists(select 1 from public.proposal_revisions r where r.project_id=f.project_id and r.snapshot->'files' @> jsonb_build_array(jsonb_build_object('id',f.id))))); $$;

alter table public.reference_boards enable row level security;
alter table public.reference_cards enable row level security;
alter table public.reference_preferences enable row level security;
alter table public.reference_comments enable row level security;
alter table public.project_proposals enable row level security;
alter table public.proposal_revisions enable row level security;
alter table public.proposal_decisions enable row level security;
alter table public.planning_files enable row level security;
create policy reference_boards_read on public.reference_boards for select to authenticated using(public.lign_has_capability(project_id,workspace_id,'project.view'));
create policy reference_cards_read on public.reference_cards for select to authenticated using(public.lign_has_capability(project_id,workspace_id,'project.view'));
create policy reference_preferences_read on public.reference_preferences for select to authenticated using(public.lign_has_capability(project_id,workspace_id,'project.view'));
create policy reference_comments_read on public.reference_comments for select to authenticated using(public.lign_has_capability(project_id,workspace_id,'project.view'));
create policy project_proposals_team_read on public.project_proposals for select to authenticated using(public.lign_prepare_proposal(project_id));
create policy proposal_revisions_read on public.proposal_revisions for select to authenticated using(public.lign_has_capability(project_id,workspace_id,'project.view'));
create policy proposal_decisions_read on public.proposal_decisions for select to authenticated using(exists(select 1 from public.projects p where p.id=project_id and public.lign_has_capability(p.id,p.workspace_id,'project.view')));
create policy planning_files_read on public.planning_files for select to authenticated using(public.lign_read_planning_file(id));
revoke all on public.reference_boards,public.reference_cards,public.reference_preferences,public.reference_comments,public.project_proposals,public.proposal_revisions,public.proposal_decisions,public.planning_files from anon,authenticated;
grant select on public.reference_boards,public.reference_cards,public.reference_preferences,public.reference_comments,public.project_proposals,public.proposal_revisions,public.proposal_decisions,public.planning_files to authenticated;

create or replace function public.save_reference_board(p_project_id uuid,p_title text,p_kind text default 'moodboard',p_description text default '',p_area_id uuid default null,p_board_id uuid default null,p_expected_version bigint default 0)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_ws uuid;v_id uuid;begin
 select workspace_id into v_ws from public.projects where id=p_project_id for no key update;
 if not coalesce(public.lign_manage_project_brief(p_project_id),false) then raise exception 'Project leadership required' using errcode='42501'; end if;
 if coalesce(length(trim(p_title)),0) not between 1 and 160 or p_kind is null or p_kind not in ('moodboard','references','template') or p_description is null or length(p_description)>3000 then raise exception 'Check the board title and details' using errcode='22023'; end if;
 if p_area_id is not null and not exists(select 1 from public.project_areas where id=p_area_id and project_id=p_project_id and archived_at is null) then raise exception 'Choose an active area in this project' using errcode='23503'; end if;
 if p_board_id is null then
 if (select count(*) from public.reference_boards where project_id=p_project_id and archived_at is null)>=100 then raise exception 'Use at most 100 active boards per project' using errcode='23514'; end if;
 insert into public.reference_boards(project_id,workspace_id,title,kind,description,area_id,created_by) values(p_project_id,v_ws,trim(p_title),p_kind,trim(p_description),p_area_id,auth.uid()) returning id into v_id;
 else
 update public.reference_boards set title=trim(p_title),kind=p_kind,description=trim(p_description),area_id=p_area_id,edit_version=edit_version+1 where id=p_board_id and project_id=p_project_id and archived_at is null and edit_version=p_expected_version returning id into v_id;
 if v_id is null then raise exception 'The board changed. Reload before saving.' using errcode='PT409'; end if;
 end if;
 perform public.planning_event(p_project_id,'reference_board.saved',v_id);return v_id;end; $$;

create or replace function public.archive_reference_board(p_board_id uuid,p_expected_version bigint)
returns void language plpgsql security definer set search_path=''
as $$ declare b public.reference_boards%rowtype;begin
 select * into b from public.reference_boards where id=p_board_id for update;
 if b.id is null or not public.lign_manage_project_brief(b.project_id) then raise exception 'Project leadership required' using errcode='42501'; end if;
 if b.edit_version<>p_expected_version or b.archived_at is not null then raise exception 'The board changed. Reload before continuing.' using errcode='PT409'; end if;
 update public.reference_boards set archived_at=now(),edit_version=edit_version+1 where id=b.id;
 perform public.planning_event(b.project_id,'reference_board.archived',b.id);end; $$;

create or replace function public.save_reference_card(p_board_id uuid,p_title text,p_description text default '',p_url text default null,p_card_id uuid default null,p_expected_version bigint default 0)
returns uuid language plpgsql security definer set search_path=''
as $$ declare b public.reference_boards%rowtype;v_id uuid;begin
 select * into b from public.reference_boards where id=p_board_id for update;
 if b.id is null or b.archived_at is not null or not public.lign_reference_contributor(b.project_id) then raise exception 'Reference contribution access required' using errcode='42501'; end if;
 if coalesce(length(trim(p_title)),0) not between 1 and 200 or p_description is null or length(p_description)>5000 or length(coalesce(p_url,''))>2000 or (nullif(trim(p_url),'') is not null and trim(p_url)!~'^https?://[^[:space:]]+$') then raise exception 'Add a title and an HTTP/HTTPS reference link' using errcode='22023'; end if;
 if p_card_id is null then
 if (select count(*) from public.reference_cards where board_id=b.id and archived_at is null)>=200 then raise exception 'Use at most 200 active references per board' using errcode='23514'; end if;
 insert into public.reference_cards(board_id,project_id,workspace_id,title,description,url,author_id) values(b.id,b.project_id,b.workspace_id,trim(p_title),trim(p_description),nullif(trim(p_url),''),auth.uid()) returning id into v_id;
 else
 if not public.lign_edit_reference(p_card_id) then raise exception 'Only the author and project leadership can edit a reference' using errcode='42501'; end if;
 update public.reference_cards set title=trim(p_title),description=trim(p_description),url=nullif(trim(p_url),''),edit_version=edit_version+1 where id=p_card_id and board_id=b.id and edit_version=p_expected_version returning id into v_id;
 if v_id is null then raise exception 'The reference changed. Reload before saving.' using errcode='PT409'; end if;
 end if;
 perform public.planning_event(b.project_id,'reference.saved',v_id);return v_id;end; $$;

create or replace function public.set_reference_selection(p_card_id uuid,p_selected boolean,p_expected_version bigint)
returns void language plpgsql security definer set search_path=''
as $$ declare c public.reference_cards%rowtype;begin
 select * into c from public.reference_cards where id=p_card_id for update;
 if c.id is null or not public.lign_manage_project_brief(c.project_id) then raise exception 'Project leadership chooses the agreed direction' using errcode='42501'; end if;
 if c.edit_version<>p_expected_version or c.archived_at is not null or not exists(select 1 from public.reference_boards where id=c.board_id and archived_at is null) then raise exception 'The reference changed. Reload before continuing.' using errcode='PT409'; end if;
 if p_selected is null then raise exception 'Choose a selection state' using errcode='22023'; end if;
 update public.reference_cards set selected_for_brief=p_selected,edit_version=edit_version+1 where id=c.id;
 perform public.planning_event(c.project_id,'reference.selection_changed',c.id,jsonb_build_object('selected',p_selected));end; $$;

create or replace function public.archive_reference_card(p_card_id uuid,p_expected_version bigint)
returns void language plpgsql security definer set search_path=''
as $$ declare c public.reference_cards%rowtype;begin
 select * into c from public.reference_cards where id=p_card_id for update;
 if c.id is null or not public.lign_edit_reference(c.id) then raise exception 'Reference editing access required' using errcode='42501'; end if;
 if c.edit_version<>p_expected_version then raise exception 'The reference changed. Reload before continuing.' using errcode='PT409'; end if;
 update public.reference_cards set archived_at=now(),edit_version=edit_version+1 where id=c.id;
 perform public.planning_event(c.project_id,'reference.archived',c.id);end; $$;

create or replace function public.set_reference_preference(p_card_id uuid,p_choice text,p_note text default '')
returns void language plpgsql security definer set search_path=''
as $$ declare c public.reference_cards%rowtype;v_previous jsonb;begin
 select * into c from public.reference_cards where id=p_card_id for share;
 if c.id is null or c.archived_at is not null or not public.lign_reference_contributor(c.project_id) or not exists(select 1 from public.reference_boards where id=c.board_id and archived_at is null) then raise exception 'Reference contribution access required' using errcode='42501'; end if;
 if p_choice is not null and p_choice not in ('shortlisted','liked','rejected') or p_note is null or length(p_note)>2000 then raise exception 'Choose a valid preference and note' using errcode='22023'; end if;
 select to_jsonb(v) into v_previous from public.reference_preferences v where card_id=c.id and user_id=auth.uid();
 if p_choice is null then delete from public.reference_preferences where card_id=c.id and user_id=auth.uid();
 else insert into public.reference_preferences(card_id,project_id,workspace_id,user_id,choice,note) values(c.id,c.project_id,c.workspace_id,auth.uid(),p_choice,trim(p_note))
 on conflict(card_id,user_id) do update set choice=excluded.choice,note=excluded.note,updated_at=now();end if;
 perform public.planning_event(c.project_id,'reference.preference_changed',c.id,jsonb_build_object('previous',v_previous,'choice',p_choice,'note',p_note));end; $$;

create or replace function public.add_reference_comment(p_card_id uuid,p_body text)
returns uuid language plpgsql security definer set search_path=''
as $$ declare c public.reference_cards%rowtype;v_id uuid;begin
 select * into c from public.reference_cards where id=p_card_id for share;
 if c.id is null or c.archived_at is not null or not public.lign_reference_contributor(c.project_id) or not exists(select 1 from public.reference_boards where id=c.board_id and archived_at is null) then raise exception 'Commenting access required' using errcode='42501'; end if;
 if coalesce(length(trim(p_body)),0) not between 1 and 3000 then raise exception 'Write a comment up to 3000 characters' using errcode='22023'; end if;
 insert into public.reference_comments(card_id,project_id,workspace_id,author_id,body) values(c.id,c.project_id,c.workspace_id,auth.uid(),trim(p_body)) returning id into v_id;
 perform public.planning_event(c.project_id,'reference.commented',c.id,jsonb_build_object('comment_id',v_id));return v_id;end; $$;

create or replace function public.reference_card_snapshot(p_card_id uuid)
returns jsonb language sql stable security definer set search_path=''
as $$ select jsonb_build_object('id',c.id,'title',c.title,'description',c.description,'url',c.url,'boardId',b.id,'boardTitle',b.title,'areaId',b.area_id,
 'areaPath',(select path from public.project_area_paths(c.project_id) where id=b.area_id),'authorId',c.author_id,'authorName',p.display_name,'editVersion',c.edit_version,'selected',c.selected_for_brief,
 'file',(select jsonb_build_object('id',f.id,'path',f.storage_path,'name',f.name,'mime',f.mime_type,'size',f.size_bytes) from public.planning_files f where f.id=c.file_id and f.registered_at is not null),
 'preferences',(select coalesce(jsonb_agg(jsonb_build_object('userId',v.user_id,'name',vp.display_name,'choice',v.choice,'note',v.note,'at',v.updated_at) order by v.updated_at,v.user_id),'[]'::jsonb) from public.reference_preferences v join public.profiles vp on vp.id=v.user_id where v.card_id=c.id),
 'commentCount',(select count(*) from public.reference_comments where card_id=c.id))
 from public.reference_cards c join public.reference_boards b on b.id=c.board_id join public.profiles p on p.id=c.author_id where c.id=p_card_id; $$;

create or replace function public.get_reference_boards(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v_ws uuid;begin
 select workspace_id into v_ws from public.projects where id=p_project_id;
 if v_ws is null or not public.lign_has_capability(p_project_id,v_ws,'project.view') then raise exception 'Project access required' using errcode='42501'; end if;
 return jsonb_build_object('canManage',public.lign_manage_project_brief(p_project_id),'canContribute',public.lign_reference_contributor(p_project_id),
 'boards',(select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('areaPath',(select path from public.project_area_paths(p_project_id) where id=b.area_id),'cardCount',(select count(*) from public.reference_cards where board_id=b.id and archived_at is null)) order by b.created_at,b.id),'[]'::jsonb) from public.reference_boards b where b.project_id=p_project_id and b.archived_at is null));
 end; $$;

create or replace function public.get_reference_board(p_board_id uuid,p_limit integer default 24,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare b public.reference_boards%rowtype;v jsonb;begin
 select * into b from public.reference_boards where id=p_board_id;
 if b.id is null or not public.lign_has_capability(b.project_id,b.workspace_id,'project.view') then raise exception 'Board access required' using errcode='42501'; end if;
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'Invalid page size' using errcode='22023'; end if;
 with page as (select id from public.reference_cards where board_id=b.id and archived_at is null and (p_after is null or id>p_after) order by id limit p_limit+1)
 select jsonb_build_object('cards',(select coalesce(jsonb_agg(public.reference_card_snapshot(x.id)||jsonb_build_object('canEdit',public.lign_edit_reference(x.id)) order by x.id),'[]'::jsonb) from(select id from page order by id limit p_limit)x),
 'nextCursor',case when (select count(*) from page)>p_limit then (select id from page order by id offset p_limit-1 limit 1) else null end) into v;
 return v;end; $$;

create or replace function public.get_reference_comments(p_card_id uuid,p_after uuid default null,p_limit integer default 30)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare c public.reference_cards%rowtype;v jsonb;begin
 select * into c from public.reference_cards where id=p_card_id;
 if c.id is null or not public.lign_has_capability(c.project_id,c.workspace_id,'project.view') then raise exception 'Reference access required' using errcode='42501'; end if;
 if p_limit is null or p_limit not between 1 and 100 then raise exception 'Invalid page size' using errcode='22023'; end if;
 with page as (select x.id,x.body,x.created_at,p.display_name as author from public.reference_comments x join public.profiles p on p.id=x.author_id where x.card_id=c.id and (p_after is null or (x.created_at,x.id)>(select z.created_at,z.id from public.reference_comments z where z.id=p_after and z.card_id=c.id)) order by x.created_at,x.id limit p_limit+1)
 select jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at,x.id),'[]'::jsonb) from(select * from page order by created_at,id limit p_limit)x),
 'nextCursor',case when (select count(*) from page)>p_limit then (select id from page order by created_at,id offset p_limit-1 limit 1) else null end) into v;
 return v;end; $$;

create or replace function public.duplicate_reference_template(p_board_id uuid,p_title text,p_area_id uuid default null)
returns uuid language plpgsql security definer set search_path=''
as $$ declare b public.reference_boards%rowtype;v_id uuid;begin
 select * into b from public.reference_boards where id=p_board_id;
 perform 1 from public.projects where id=b.project_id for no key update;
 select * into b from public.reference_boards where id=p_board_id for update;
 if b.id is null or b.kind<>'template' or b.archived_at is not null or not public.lign_manage_project_brief(b.project_id) then raise exception 'Choose a template managed in this project' using errcode='42501'; end if;
 v_id:=public.save_reference_board(b.project_id,p_title,'moodboard',b.description,p_area_id);
 insert into public.reference_cards(board_id,project_id,workspace_id,title,description,url,file_id,author_id)
 select v_id,c.project_id,c.workspace_id,c.title,c.description,c.url,c.file_id,auth.uid() from public.reference_cards c where c.board_id=b.id and c.archived_at is null;
 perform public.planning_event(b.project_id,'reference_template.used',v_id,jsonb_build_object('source_board_id',b.id));return v_id;end; $$;

create or replace function public.snapshot_brief_reference_selection(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v jsonb;begin
 if (select count(*) from public.reference_cards c join public.reference_boards b on b.id=c.board_id where c.project_id=p_project_id and c.selected_for_brief and c.archived_at is null and b.archived_at is null)>100 then raise exception 'Select at most 100 references for brief agreement' using errcode='23514'; end if;
 select coalesce(jsonb_agg(public.reference_card_snapshot(c.id) order by b.title,c.id),'[]'::jsonb) into v from public.reference_cards c join public.reference_boards b on b.id=c.board_id where c.project_id=p_project_id and c.selected_for_brief and c.archived_at is null and b.archived_at is null;
 if octet_length(v::text)>200000 then raise exception 'The selected reference summary is too large; reduce the selected set or notes' using errcode='23514'; end if;
 return v;end; $$;

-- Preserve the old gate as a separate milestone; detailed work now also needs
-- an accepted proposal. Both checks use immutable decisions, preserving baselines.
create or replace function public.lign_project_has_agreed_brief(p_project_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.project_brief_decisions d join public.project_brief_revisions r on r.id=d.revision_id and r.project_id=d.project_id where d.project_id=p_project_id and d.decision='agreed'); $$;
create or replace function public.lign_project_ready_for_design(p_project_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select public.lign_project_has_agreed_brief(p_project_id) and exists(select 1 from public.proposal_decisions d join public.proposal_revisions r on r.id=d.revision_id and r.project_id=d.project_id where d.project_id=p_project_id and d.decision='accepted'); $$;
create or replace function public.get_project_journey(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v_ws uuid;begin
 select workspace_id into v_ws from public.projects where id=p_project_id;
 if v_ws is null or not public.lign_has_capability(p_project_id,v_ws,'project.view') then raise exception 'Project access required' using errcode='42501'; end if;
 return jsonb_build_object('briefReady',public.lign_project_has_agreed_brief(p_project_id),'designReady',public.lign_project_ready_for_design(p_project_id));end; $$;
create or replace function public.guard_project_design_start()
returns trigger language plpgsql security definer set search_path=''
as $$ begin
 if not public.lign_project_ready_for_design(new.project_id) then raise exception 'Agree the brief and accept a design proposal before starting detailed design work' using errcode='23514'; end if;
 return new;end; $$;

create or replace function public.validate_proposal_document(p_project_id uuid,p_document jsonb)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v jsonb;v_sections jsonb:='[]';v_ids text[]:='{}';v_snapshot jsonb;v_list text;v_id text;begin
 if jsonb_typeof(p_document) is distinct from 'object' or octet_length(p_document::text)>300000 then raise exception 'Invalid proposal document' using errcode='22023'; end if;
 foreach v_list in array array['title','summary','scope','budget','timing','assumptions'] loop
 if jsonb_typeof(p_document->v_list) is distinct from 'string' or length(p_document->>v_list)>10000 then raise exception 'Proposal fields must be text, up to 10000 characters each' using errcode='22023'; end if;end loop;
 if length(trim(p_document->>'title')) not between 1 and 200 then raise exception 'Give the proposal a title up to 200 characters' using errcode='22023'; end if;
 if jsonb_typeof(p_document->'sections') is distinct from 'array' or jsonb_array_length(p_document->'sections')>100 then raise exception 'Use up to 100 proposal sections' using errcode='22023'; end if;
 for v in select value from jsonb_array_elements(p_document->'sections') loop
 if jsonb_typeof(v->'id') is distinct from 'string' or length(v->>'id') not between 1 and 100 or v->>'id'=any(v_ids)
 or jsonb_typeof(v->'title') is distinct from 'string' or length(trim(v->>'title')) not between 1 and 200
 or jsonb_typeof(v->'concept') is distinct from 'string' or length(v->>'concept')>10000
 or jsonb_typeof(v->'materials') is distinct from 'string' or length(v->>'materials')>10000 then raise exception 'Check each section title, concept and materials' using errcode='22023'; end if;
 v_ids:=array_append(v_ids,v->>'id');v_snapshot:=null;
 if nullif(v->>'areaId','') is not null then
 if (v->>'areaId')!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'Choose a valid area' using errcode='22023';end if;
 select jsonb_build_object('id',id,'path',path,'kind',kind) into v_snapshot from public.project_area_paths(p_project_id) where id=(v->>'areaId')::uuid and not archived;
 if v_snapshot is null then raise exception 'Choose an active area in this project' using errcode='23503'; end if;end if;
 v_sections:=v_sections||jsonb_build_array(v||jsonb_build_object('areaSnapshot',v_snapshot));end loop;
 foreach v_list in array array['referenceIds','requirementIds'] loop
 if jsonb_typeof(p_document->v_list) is distinct from 'array' or jsonb_array_length(p_document->v_list)>100 then raise exception 'Choose up to 100 references and requirements' using errcode='22023';end if;
 v_ids:='{}';for v_id in select value from jsonb_array_elements_text(p_document->v_list) loop
 if v_id is null or v_id!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or lower(v_id)=any(v_ids) then raise exception 'Choose unique, valid reference and requirement IDs' using errcode='22023';end if;
 v_ids:=array_append(v_ids,lower(v_id));
 if v_list='referenceIds' and not exists(select 1 from public.reference_cards c join public.reference_boards b on b.id=c.board_id where c.id=v_id::uuid and c.project_id=p_project_id and c.archived_at is null and b.archived_at is null) then raise exception 'Choose active references in this project' using errcode='23503';end if;
 if v_list='requirementIds' and not exists(select 1 from public.requirements where id=v_id::uuid and project_id=p_project_id and status in ('draft','active')) then raise exception 'Choose draft or active requirements in this project' using errcode='23503';end if;end loop;end loop;
 return jsonb_set(p_document,'{sections}',v_sections);end; $$;

create or replace function public.save_project_proposal(p_project_id uuid,p_document jsonb,p_brief_revision_id uuid,p_respondent_id uuid,p_expected_version bigint)
returns bigint language plpgsql security definer set search_path=''
as $$ declare v public.project_proposals%rowtype;v_ws uuid;v_version bigint;begin
 select workspace_id into v_ws from public.projects where id=p_project_id for no key update;
 if not public.lign_prepare_proposal(p_project_id) then raise exception 'Internal project team access required' using errcode='42501';end if;
 if not exists(select 1 from public.project_brief_revisions r join public.project_brief_decisions d on d.revision_id=r.id where r.id=p_brief_revision_id and r.project_id=p_project_id and d.decision='agreed') then raise exception 'Choose an agreed brief revision before preparing a proposal' using errcode='23514';end if;
 select * into v from public.project_proposals where project_id=p_project_id for update;
 if (v.id is null and p_expected_version is distinct from 0) or (v.id is not null and p_expected_version is distinct from v.edit_version) then raise exception 'The proposal changed. Reload before saving.' using errcode='PT409';end if;
 if v.id is not null and v.status<>'draft' then raise exception 'Return to a proposal draft before editing' using errcode='23514';end if;
 if p_respondent_id is not null and public.lign_brief_respondent_user(p_respondent_id,p_project_id) is null then raise exception 'Choose an active project approver' using errcode='23503';end if;
 p_document:=public.validate_proposal_document(p_project_id,p_document);
 if v.id is null then insert into public.project_proposals(project_id,workspace_id,brief_revision_id,document,respondent_id,created_by) values(p_project_id,v_ws,p_brief_revision_id,p_document,p_respondent_id,auth.uid()) returning id,edit_version into v.id,v_version;
 else update public.project_proposals set brief_revision_id=p_brief_revision_id,document=p_document,respondent_id=p_respondent_id,edit_version=edit_version+1,updated_at=now() where id=v.id returning edit_version into v_version;end if;
 perform public.planning_event(p_project_id,'proposal.saved',v.id);return v_version;end; $$;

create or replace function public.snapshot_project_proposal(p_proposal_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v public.project_proposals%rowtype;s jsonb;begin
 select * into v from public.project_proposals where id=p_proposal_id;
 select jsonb_build_object('brief',(select to_jsonb(r)||jsonb_build_object('decision',to_jsonb(d)) from public.project_brief_revisions r join public.project_brief_decisions d on d.revision_id=r.id where r.id=v.brief_revision_id and d.decision='agreed'),
 'references',(select coalesce(jsonb_agg(public.reference_card_snapshot(x::uuid) order by x),'[]'::jsonb) from jsonb_array_elements_text(v.document->'referenceIds') x),
 'requirements',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('areas',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'path',a.path) order by a.path),'[]'::jsonb) from public.requirement_areas ra join public.project_area_paths(v.project_id) a on a.id=ra.area_id where ra.requirement_id=coalesce(r.parent_requirement_id,r.id))) order by r.code),'[]'::jsonb) from public.requirements r where r.id in(select x::uuid from jsonb_array_elements_text(v.document->'requirementIds') x) and r.project_id=v.project_id),
 'files',(select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'path',f.storage_path,'name',f.name,'mime',f.mime_type,'size',f.size_bytes) order by f.created_at,f.id),'[]'::jsonb) from public.planning_files f where f.proposal_id=v.id and f.registered_at is not null and f.removed_at is null)) into s;
 if s->'brief'='null'::jsonb or octet_length(s::text)>5000000 then raise exception 'Choose a valid agreed brief and reduce this proposal package below 5 MB of metadata' using errcode='23514';end if;
 return s;end; $$;

create or replace function public.transition_project_proposal(p_project_id uuid,p_expected_version bigint,p_action text,p_note text default '')
returns bigint language plpgsql security definer set search_path=''
as $$ declare v public.project_proposals%rowtype;v_revision uuid;v_status text;v_snapshot jsonb;v_doc jsonb;v_user uuid;v_version bigint;begin
 perform 1 from public.projects where id=p_project_id for no key update;
 select * into v from public.project_proposals where project_id=p_project_id for update;
 if v.id is null or not public.lign_prepare_proposal(p_project_id) then raise exception 'Internal project team access required' using errcode='42501';end if;
 if v.edit_version is distinct from p_expected_version then raise exception 'The proposal changed. Reload before continuing.' using errcode='PT409';end if;
 if p_note is null or length(p_note)>5000 then raise exception 'Use a review note up to 5000 characters' using errcode='22023';end if;
 if p_action='submit' and v.status='draft' then
 v_doc:=public.validate_proposal_document(p_project_id,v.document);
 if trim(v_doc->>'summary')='' or trim(v_doc->>'scope')='' or jsonb_array_length(v_doc->'sections')=0 or exists(select 1 from jsonb_array_elements(v_doc->'sections') s where trim(s->>'concept')='') then raise exception 'Add the proposal summary, scope and at least one complete concept section' using errcode='23514';end if;
 v_status:='submitted';
 elsif p_action='return_to_draft' and v.status in ('submitted','awaiting_acceptance') and public.lign_manage_project_brief(p_project_id) then v_status:='draft';
 elsif p_action='revise' and v.status='accepted' and public.lign_manage_project_brief(p_project_id) then v_status:='draft';
 elsif p_action='request_acceptance' and v.status='submitted' and public.lign_manage_project_brief(p_project_id) then
 v_user:=public.lign_brief_respondent_user(v.respondent_id,p_project_id);
 if v_user is null or v_user=auth.uid() or v_user=v.created_by then raise exception 'Assign an independent, active project approver before requesting acceptance' using errcode='23514';end if;
 v_doc:=public.validate_proposal_document(p_project_id,v.document);
 update public.project_proposals set document=v_doc where id=v.id;
 v_snapshot:=public.snapshot_project_proposal(v.id);
 if jsonb_array_length(v_snapshot->'files')=0 and jsonb_array_length(v_snapshot->'references')=0 then raise exception 'Attach proposal files or choose reference material before requesting acceptance' using errcode='23514';end if;
 insert into public.proposal_revisions(proposal_id,project_id,workspace_id,number,brief_revision_id,document,snapshot,respondent_id,reviewed_by,review_note)
 values(v.id,v.project_id,v.workspace_id,v.revision_number+1,v.brief_revision_id,v_doc,v_snapshot,v.respondent_id,auth.uid(),trim(p_note)) returning id into v_revision;
 v_status:='awaiting_acceptance';
 else raise exception 'This action requires project leadership at the appropriate proposal stage' using errcode='23514';end if;
 update public.project_proposals set status=v_status,document=coalesce(v_doc,document),edit_version=edit_version+1,updated_at=now(),current_revision_id=case when v_status='draft' then null else coalesce(v_revision,current_revision_id) end,revision_number=revision_number+case when v_revision is null then 0 else 1 end where id=v.id returning edit_version into v_version;
 perform public.planning_event(p_project_id,'proposal.'||p_action,v.id,jsonb_build_object('revision_id',v_revision,'note',p_note));return v_version;end; $$;

create or replace function public.respond_project_proposal(p_project_id uuid,p_revision_id uuid,p_decision text,p_note text default '')
returns void language plpgsql security definer set search_path=''
as $$ declare v public.project_proposals%rowtype;r public.proposal_revisions%rowtype;begin
 perform 1 from public.projects where id=p_project_id for no key update;
 select * into v from public.project_proposals where project_id=p_project_id for update;
 select * into r from public.proposal_revisions where id=p_revision_id and project_id=p_project_id;
 if r.id is null or auth.uid() is null or public.lign_brief_respondent_user(r.respondent_id,p_project_id) is distinct from auth.uid()
 or not public.lign_has_capability(p_project_id,r.workspace_id,'project.view') or auth.uid()=r.reviewed_by
 or not exists(select 1 from public.projects where id=p_project_id and archived_at is null and status<>'archived') then raise exception 'The assigned independent approver must respond' using errcode='42501';end if;
 if v.status<>'awaiting_acceptance' or v.current_revision_id is distinct from p_revision_id or exists(select 1 from public.proposal_decisions where revision_id=p_revision_id) then raise exception 'This acceptance request is no longer current' using errcode='PT409';end if;
 if p_decision is null or p_decision not in ('accepted','changes_requested') or p_note is null or length(p_note)>5000 or (p_decision='changes_requested' and trim(p_note)='') then raise exception 'Choose acceptance or explain the changes requested' using errcode='22023';end if;
 insert into public.proposal_decisions(revision_id,project_id,decision,note,actor_id) values(r.id,p_project_id,p_decision,trim(p_note),auth.uid());
 update public.project_proposals set status=case when p_decision='accepted' then 'accepted' else 'draft' end,edit_version=edit_version+1,updated_at=now(),current_revision_id=case when p_decision='accepted' then r.id else null end where id=v.id;
 perform public.planning_event(p_project_id,'proposal.'||p_decision,r.id,jsonb_build_object('note',p_note));end; $$;

create or replace function public.get_project_proposal(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v public.project_proposals%rowtype;v_ws uuid;v_team boolean;v_current public.proposal_revisions%rowtype;begin
 select workspace_id into v_ws from public.projects where id=p_project_id;
 if v_ws is null or not public.lign_has_capability(p_project_id,v_ws,'project.view') then raise exception 'Project access required' using errcode='42501';end if;
 select * into v from public.project_proposals where project_id=p_project_id;
 select * into v_current from public.proposal_revisions where id=v.current_revision_id;
 v_team:=public.lign_prepare_proposal(p_project_id);
 return jsonb_build_object('briefReady',public.lign_project_has_agreed_brief(p_project_id),'designReady',public.lign_project_ready_for_design(p_project_id),
 'canPrepare',v_team,'canManage',public.lign_manage_project_brief(p_project_id),
 'canRespond',v.status='awaiting_acceptance' and public.lign_brief_respondent_user(v_current.respondent_id,p_project_id)=auth.uid() and v_current.reviewed_by<>auth.uid(),
 'working',case when v_team and v.id is not null then to_jsonb(v) else null end,'status',v.status,'currentRevisionId',v.current_revision_id,
 'agreedBriefs',case when v_team then (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'number',r.number,'at',r.created_at) order by r.number desc),'[]'::jsonb) from public.project_brief_revisions r join public.project_brief_decisions d on d.revision_id=r.id where r.project_id=p_project_id and d.decision='agreed') else '[]'::jsonb end,
 'approvers',case when v_team then (select coalesce(jsonb_agg(jsonb_build_object('id',pp.id,'name',p.display_name) order by p.display_name),'[]'::jsonb) from public.project_participants pp join public.profiles p on p.id=public.lign_brief_respondent_user(pp.id,p_project_id) where pp.project_id=p_project_id and pp.role='approver' and pp.status='active') else '[]'::jsonb end,
 'files',case when v_team then (select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'path',f.storage_path,'name',f.name,'mime',f.mime_type,'size',f.size_bytes) order by f.created_at),'[]'::jsonb) from public.planning_files f where f.proposal_id=v.id and f.registered_at is not null and f.removed_at is null) else '[]'::jsonb end,
 'revisions',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'number',r.number,'createdAt',r.created_at,'reviewedBy',p.display_name,'reviewNote',r.review_note,'decision',(select to_jsonb(d)||jsonb_build_object('name',dp.display_name) from public.proposal_decisions d join public.profiles dp on dp.id=d.actor_id where d.revision_id=r.id)) order by r.number desc),'[]'::jsonb) from public.proposal_revisions r join public.profiles p on p.id=r.reviewed_by where r.project_id=p_project_id));
 end; $$;

create or replace function public.get_proposal_revision(p_revision_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare r public.proposal_revisions%rowtype;begin
 select * into r from public.proposal_revisions where id=p_revision_id;
 if r.id is null or not public.lign_has_capability(r.project_id,r.workspace_id,'project.view') then raise exception 'Proposal revision access required' using errcode='42501';end if;
 return to_jsonb(r);end; $$;

create or replace function public.proposal_source_options(p_project_id uuid,p_kind text,p_search text default '',p_selected uuid[] default '{}')
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v jsonb;begin
 if not public.lign_prepare_proposal(p_project_id) then raise exception 'Internal project team access required' using errcode='42501';end if;
 if p_search is null or length(p_search)>200 or p_selected is null or cardinality(p_selected)>100 then raise exception 'Invalid source search' using errcode='22023';end if;
 if p_kind='reference' then
 with options as (select c.id,c.title,b.title as context from public.reference_cards c join public.reference_boards b on b.id=c.board_id where c.project_id=p_project_id and c.archived_at is null and b.archived_at is null), matching as (select * from options where title ilike '%'||trim(p_search)||'%' or context ilike '%'||trim(p_search)||'%' order by title,id limit 50),picked as(select * from options where id=any(p_selected) union select * from matching)
 select coalesce(jsonb_agg(to_jsonb(p) order by p.title,p.id),'[]'::jsonb) into v from picked p;
 elsif p_kind='requirement' then
 with options as (select id,title,code||' · '||status as context from public.requirements where project_id=p_project_id and status in ('draft','active')),matching as(select * from options where title ilike '%'||trim(p_search)||'%' or context ilike '%'||trim(p_search)||'%' order by title,id limit 50),picked as(select * from options where id=any(p_selected) union select * from matching)
 select coalesce(jsonb_agg(to_jsonb(p) order by p.title,p.id),'[]'::jsonb) into v from picked p;
 else raise exception 'Choose reference or requirement sources' using errcode='22023';end if;return v;end; $$;

create or replace function public.reserve_planning_upload(p_name text,p_mime text,p_size bigint,p_reference_id uuid default null,p_proposal_id uuid default null,p_expected_version bigint default null)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare v_project uuid;v_ws uuid;v_version bigint;v_id uuid:=gen_random_uuid();v_path text;c public.reference_cards%rowtype;v public.project_proposals%rowtype;begin
 if num_nonnulls(p_reference_id,p_proposal_id)<>1 or coalesce(length(trim(p_name)),0) not between 1 and 180 or p_name~'[[:cntrl:]]' or p_size is null or p_size not between 1 and 52428800 or p_mime is null or p_mime not in ('image/png','image/jpeg','image/webp','application/pdf','text/plain','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') then raise exception 'Choose a supported image, PDF or document up to 50 MB' using errcode='22023';end if;
 if p_reference_id is not null then
 select project_id into v_project from public.reference_cards where id=p_reference_id;
 perform 1 from public.projects where id=v_project for no key update;
 select * into c from public.reference_cards where id=p_reference_id for update;
 if not coalesce(public.lign_edit_reference(c.id),false) then raise exception 'Reference editing access required' using errcode='42501';end if;
 v_ws:=c.workspace_id;v_version:=c.edit_version;
 else
 select project_id into v_project from public.project_proposals where id=p_proposal_id;
 perform 1 from public.projects where id=v_project for no key update;
 select * into v from public.project_proposals where id=p_proposal_id for update;
 if not coalesce(public.lign_prepare_proposal(v_project),false) or v.status is distinct from 'draft' then raise exception 'Proposal draft editing access required' using errcode='42501';end if;
 if (select count(*) from public.planning_files where proposal_id=v.id and registered_at is not null and removed_at is null)>=50 then raise exception 'Use at most 50 active proposal files' using errcode='23514';end if;
 v_ws:=v.workspace_id;v_version:=v.edit_version;
 end if;
 if v_version is distinct from p_expected_version then raise exception 'The draft changed. Save or reload before uploading.' using errcode='PT409';end if;
 v_path:=v_project::text||'/'||v_id::text;
 insert into public.planning_files(id,project_id,workspace_id,reference_card_id,proposal_id,storage_path,name,mime_type,size_bytes,uploaded_by,entity_version)
 values(v_id,v_project,v_ws,p_reference_id,p_proposal_id,v_path,trim(p_name),p_mime,p_size,auth.uid(),v_version);
 return jsonb_build_object('id',v_id,'path',v_path);end; $$;

create or replace function public.lign_upload_planning_object(p_path text)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.planning_files f where f.storage_path=p_path and f.uploaded_by=auth.uid() and f.registered_at is null and f.removed_at is null and f.created_at>now()-interval '1 day'
 and ((f.reference_card_id is not null and public.lign_edit_reference(f.reference_card_id) and exists(select 1 from public.reference_cards c where c.id=f.reference_card_id and c.edit_version=f.entity_version))
 or (f.proposal_id is not null and public.lign_prepare_proposal(f.project_id) and exists(select 1 from public.project_proposals p where p.id=f.proposal_id and p.status='draft' and p.edit_version=f.entity_version)))); $$;

create or replace function public.finalize_planning_upload(p_file_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare f public.planning_files%rowtype;v_version bigint;v_size bigint;v_mime text;v_owner text;begin
 select * into f from public.planning_files where id=p_file_id;
 if f.id is null or auth.uid() is null or f.uploaded_by<>auth.uid() then raise exception 'Your upload reservation is required' using errcode='42501';end if;
 perform 1 from public.projects where id=f.project_id for no key update;
 if f.reference_card_id is not null then perform 1 from public.reference_cards where id=f.reference_card_id for update;
 else perform 1 from public.project_proposals where id=f.proposal_id for update;end if;
 select * into f from public.planning_files where id=p_file_id for update;
 if f.registered_at is not null then return jsonb_build_object('id',f.id,'alreadyRegistered',true);end if;
 if not public.lign_upload_planning_object(f.storage_path) then raise exception 'The upload no longer matches an editable draft' using errcode='42501';end if;
 select (metadata->>'size')::bigint,metadata->>'mimetype',owner_id into v_size,v_mime,v_owner from storage.objects where bucket_id='project-planning' and name=f.storage_path;
 if v_size is distinct from f.size_bytes or v_mime is distinct from f.mime_type or v_owner is distinct from auth.uid()::text then raise exception 'The private file does not match its upload reservation' using errcode='23514';end if;
 if f.proposal_id is not null and (select count(*) from public.planning_files where proposal_id=f.proposal_id and registered_at is not null and removed_at is null)>=50 then raise exception 'Use at most 50 active proposal files' using errcode='23514';end if;
 update public.planning_files set registered_at=now() where id=f.id;
 if f.reference_card_id is not null then update public.reference_cards set file_id=f.id,edit_version=edit_version+1 where id=f.reference_card_id returning edit_version into v_version;
 else update public.project_proposals set edit_version=edit_version+1,updated_at=now() where id=f.proposal_id returning edit_version into v_version;end if;
 perform public.planning_event(f.project_id,'planning_file.registered',f.id);return jsonb_build_object('id',f.id,'version',v_version);end; $$;

create or replace function public.remove_planning_file(p_file_id uuid,p_expected_version bigint)
returns void language plpgsql security definer set search_path=''
as $$ declare f public.planning_files%rowtype;v_version bigint;begin
 select * into f from public.planning_files where id=p_file_id;
 perform 1 from public.projects where id=f.project_id for no key update;
 if f.reference_card_id is not null then
 raise exception 'Remove reference attachments through their card' using errcode='22023'; else
 perform 1 from public.project_proposals where id=f.proposal_id for update;
 if not public.lign_prepare_proposal(f.project_id) then raise exception 'Internal project team access required' using errcode='42501';end if;
 update public.project_proposals set edit_version=edit_version+1,updated_at=now() where id=f.proposal_id and status='draft' and edit_version=p_expected_version returning edit_version into v_version;
 end if;
 if f.id is null or f.registered_at is null or f.removed_at is not null or v_version is null then raise exception 'The file or draft changed. Reload before continuing.' using errcode='PT409';end if;
 update public.planning_files set removed_at=now() where id=f.id;
 perform public.planning_event(f.project_id,'planning_file.removed',f.id);end; $$;

create or replace function public.remove_reference_attachment(p_card_id uuid,p_expected_version bigint)
returns void language plpgsql security definer set search_path=''
as $$ declare c public.reference_cards%rowtype;begin
 select * into c from public.reference_cards where id=p_card_id;
 perform 1 from public.projects where id=c.project_id for no key update;
 select * into c from public.reference_cards where id=p_card_id for update;
 if c.id is null or not public.lign_edit_reference(c.id) then raise exception 'Reference editing access required' using errcode='42501';end if;
 if c.edit_version is distinct from p_expected_version or c.file_id is null then raise exception 'The reference changed. Reload before removing its attachment.' using errcode='PT409';end if;
 update public.reference_cards set file_id=null,edit_version=edit_version+1 where id=c.id;
 perform public.planning_event(c.project_id,'reference.attachment_removed',c.id,jsonb_build_object('file_id',c.file_id));
 end; $$;

create or replace function public.lign_discard_planning_object(p_path text)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.planning_files where storage_path=p_path and uploaded_by=auth.uid() and registered_at is null); $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('project-planning','project-planning',false,52428800,array['image/png','image/jpeg','image/webp','application/pdf','text/plain','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);
create policy planning_upload on storage.objects for insert to authenticated with check(bucket_id='project-planning' and public.lign_upload_planning_object(name));
create policy planning_download on storage.objects for select to authenticated using(bucket_id='project-planning' and (public.lign_discard_planning_object(name) or exists(select 1 from public.planning_files f where f.storage_path=storage.objects.name and public.lign_read_planning_file(f.id))));
create policy planning_discard_unregistered on storage.objects for delete to authenticated using(bucket_id='project-planning' and owner_id=auth.uid()::text and public.lign_discard_planning_object(name));

create or replace function public.preserve_planning_history()
returns trigger language plpgsql set search_path=''
as $$ begin raise exception 'Reviewed proposal revisions, decisions and comments cannot be edited or deleted' using errcode='23514';end; $$;
create trigger proposal_revisions_immutable before update or delete on public.proposal_revisions for each row execute function public.preserve_planning_history();
create trigger proposal_decisions_immutable before update or delete on public.proposal_decisions for each row execute function public.preserve_planning_history();
create trigger reference_comments_immutable before update or delete on public.reference_comments for each row execute function public.preserve_planning_history();

create or replace function public.save_project_brief(p_project_id uuid,p_document jsonb,p_expected_version bigint,p_respondent_participant_id uuid default null)
returns bigint language plpgsql security definer set search_path=''
as $fn$
declare v_ws uuid; v_b public.project_briefs%rowtype; v_manager boolean; v_version bigint; v_item jsonb;
begin
 select workspace_id into v_ws from public.projects where id=p_project_id for no key update;
 v_manager:=public.lign_manage_project_brief(p_project_id);
 select * into v_b from public.project_briefs where project_id=p_project_id for update;
 if not coalesce(v_manager,false) and not coalesce(public.lign_edit_project_brief(p_project_id),false) then
  raise exception 'Only project leadership and the assigned brief approver can edit this draft' using errcode='42501'; end if;
 if p_expected_version is null or (v_b.id is null and p_expected_version<>0) or (v_b.id is not null and v_b.edit_version<>p_expected_version) then
  raise exception 'The brief changed. Reload the latest version before saving.' using errcode='PT409'; end if;
 if v_b.id is not null and v_b.status<>'draft' then raise exception 'Start a new draft before editing this brief' using errcode='23514'; end if;
 if not v_manager and p_respondent_participant_id is distinct from v_b.respondent_participant_id then
  raise exception 'Only project leadership can assign the brief approver' using errcode='42501'; end if;
 if p_respondent_participant_id is not null and not exists(select 1 from public.project_participants pp
  left join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
  left join public.stakeholders s on s.id=pp.stakeholder_id and s.status in ('active','invited')
  where pp.id=p_respondent_participant_id and pp.project_id=p_project_id and pp.status='active' and pp.role='approver' and (wm.id is not null or s.id is not null)) then
  raise exception 'Choose an active project approver or invite a client as an approver' using errcode='23514'; end if;
 p_document:=p_document-'referenceSelection';
 perform public.validate_project_brief_document(p_document);
 p_document:=public.enrich_project_brief_areas(p_project_id,p_document);
 for v_item in select value from jsonb_array_elements(p_document->'items') loop
  if nullif(v_item->>'ownerProfileId','') is not null and not exists(select 1 from public.project_participants pp
   join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
   where pp.project_id=p_project_id and pp.status='active' and pp.role in ('lead','contributor') and wm.user_id=(v_item->>'ownerProfileId')::uuid) then
   raise exception 'Choose a project lead or contributor responsible for this requirement' using errcode='23514'; end if;
 end loop;
 if v_b.id is null then
  insert into public.project_briefs(project_id,workspace_id,document,respondent_participant_id,created_by)
  values(p_project_id,v_ws,p_document,p_respondent_participant_id,auth.uid()) returning edit_version into v_version;
 else
  update public.project_briefs set document=p_document,respondent_participant_id=p_respondent_participant_id,edit_version=edit_version+1,updated_at=now()
   where id=v_b.id returning edit_version into v_version;
 end if;
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label)
 values(v_ws,p_project_id,'brief.saved',auth.uid(),'user','project',p_project_id,'Project brief');
 return v_version;
end;
$fn$;

create or replace function public.transition_project_brief(p_project_id uuid,p_expected_version bigint,p_action text)
returns bigint language plpgsql security definer set search_path=''
as $fn$
declare v_b public.project_briefs%rowtype; v_manager boolean; v_status text; v_item jsonb; v_revision uuid; v_files jsonb; v_owner uuid; v_items jsonb:='[]'::jsonb;
begin
 perform 1 from public.projects where id=p_project_id for no key update;
 select * into v_b from public.project_briefs where project_id=p_project_id for update;
 v_manager:=public.lign_manage_project_brief(p_project_id);
 if v_b.id is null or not (v_manager or (p_action='submit' and public.lign_edit_project_brief(p_project_id))) then
  raise exception 'Brief editing or project leadership required' using errcode='42501'; end if;
 if v_b.edit_version is distinct from p_expected_version then raise exception 'The brief changed. Reload before continuing.' using errcode='PT409'; end if;
 if p_action='submit' and v_b.status='draft' then v_status:='submitted';
 elsif p_action='return_to_draft' and v_b.status in ('submitted','awaiting_agreement') then v_status:='draft';
 elsif p_action='revise' and v_b.status='agreed' then v_status:='draft';
 elsif p_action='request_agreement' and v_b.status in ('draft','submitted') then
  if public.lign_brief_respondent_user(v_b.respondent_participant_id,p_project_id) is null then
   raise exception 'Assign a project approver who has accepted their invitation before requesting agreement' using errcode='23514'; end if;
  if public.lign_brief_respondent_user(v_b.respondent_participant_id,p_project_id)=auth.uid() then
   raise exception 'A different project approver must agree the brief you review' using errcode='23514'; end if;
  if not exists(select 1 from jsonb_array_elements(v_b.document->'items') i where i->>'kind' in ('mandatory','preference')) then
   raise exception 'Add at least one requirement or preference before agreement' using errcode='23514'; end if;
  for v_item in select value from jsonb_array_elements(v_b.document->'items') loop
   if v_item->>'kind'='question' and trim(coalesce(v_item->>'resolution',''))='' then
    raise exception 'Resolve open questions before requesting agreement' using errcode='23514'; end if;
   if v_item->>'kind' in ('mandatory','preference') and trim(coalesce(v_item->>'acceptance',''))='' then
    raise exception 'Describe how each requirement or preference will be checked' using errcode='23514'; end if;
   if v_item->>'kind' in ('mandatory','preference') then
    v_owner:=nullif(v_item->>'ownerProfileId','')::uuid;
    if v_owner is null then
     select wm.user_id into v_owner from public.project_participants pp join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
      where pp.project_id=p_project_id and pp.status='active' and pp.role in ('lead','contributor') order by case pp.role when 'lead' then 0 else 1 end,pp.id limit 1;
    end if;
    if v_owner is null or not exists(select 1 from public.project_participants pp join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
      where pp.project_id=p_project_id and pp.status='active' and pp.role in ('lead','contributor') and wm.user_id=v_owner) then
     raise exception 'Assign an active project lead or contributor responsible for each requirement' using errcode='23514'; end if;
    v_item:=jsonb_set(v_item,'{ownerProfileId}',to_jsonb(v_owner::text));
   end if;
   v_items:=v_items||jsonb_build_array(v_item);
  end loop;
  v_b.document:=public.enrich_project_brief_areas(p_project_id,jsonb_set(v_b.document,'{items}',v_items));
  v_b.document:=jsonb_set(v_b.document,'{referenceSelection}',public.snapshot_brief_reference_selection(p_project_id));
  select coalesce(jsonb_agg(to_jsonb(f) order by f.created_at),'[]'::jsonb) into v_files from public.project_brief_files f where f.brief_id=v_b.id and f.removed_at is null;
  insert into public.project_brief_revisions(brief_id,project_id,workspace_id,number,document,attachments,respondent_participant_id,requested_by)
   values(v_b.id,v_b.project_id,v_b.workspace_id,v_b.revision_number+1,v_b.document,v_files,v_b.respondent_participant_id,auth.uid()) returning id into v_revision;
  v_status:='awaiting_agreement';
 else raise exception 'This action is not available at the current brief stage' using errcode='23514'; end if;
 if p_action in ('submit','request_agreement') then
  if exists(select 1 from jsonb_array_elements(v_b.document->'fields') f where f->>'id' in ('objective','deliverables') and trim(coalesce(f->>'answer',''))='') then
   raise exception 'Describe the project objective and expected deliverables first' using errcode='23514'; end if;
 end if;
 update public.project_briefs set status=v_status,document=v_b.document,edit_version=edit_version+1,updated_at=now(),
  current_revision_id=coalesce(v_revision,current_revision_id),revision_number=revision_number+case when v_revision is null then 0 else 1 end
  where id=v_b.id returning edit_version into v_b.edit_version;
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload)
 values(v_b.workspace_id,p_project_id,'brief.'||p_action,auth.uid(),'user','project',p_project_id,'Project brief',jsonb_build_object('revision_id',v_revision));
 return v_b.edit_version;
end;
$fn$;

revoke all on function public.save_reference_board(uuid,text,text,text,uuid,uuid,bigint),public.archive_reference_board(uuid,bigint),public.save_reference_card(uuid,text,text,text,uuid,bigint),public.set_reference_selection(uuid,boolean,bigint),public.archive_reference_card(uuid,bigint),public.set_reference_preference(uuid,text,text),public.add_reference_comment(uuid,text),public.get_reference_boards(uuid),public.get_reference_board(uuid,integer,uuid),public.get_reference_comments(uuid,uuid,integer),public.duplicate_reference_template(uuid,text,uuid),public.get_project_journey(uuid),public.save_project_proposal(uuid,jsonb,uuid,uuid,bigint),public.transition_project_proposal(uuid,bigint,text,text),public.respond_project_proposal(uuid,uuid,text,text),public.get_project_proposal(uuid),public.get_proposal_revision(uuid),public.proposal_source_options(uuid,text,text,uuid[]),public.reserve_planning_upload(text,text,bigint,uuid,uuid,bigint),public.finalize_planning_upload(uuid),public.remove_planning_file(uuid,bigint),public.lign_reference_contributor(uuid),public.lign_prepare_proposal(uuid),public.lign_edit_reference(uuid),public.lign_read_planning_file(uuid),public.lign_upload_planning_object(text),public.lign_project_has_agreed_brief(uuid),public.planning_event(uuid,text,uuid,jsonb),public.reference_card_snapshot(uuid),public.snapshot_brief_reference_selection(uuid),public.validate_proposal_document(uuid,jsonb),public.snapshot_project_proposal(uuid),public.preserve_planning_history() from public,anon,authenticated;
grant execute on function public.save_reference_board(uuid,text,text,text,uuid,uuid,bigint),public.archive_reference_board(uuid,bigint),public.save_reference_card(uuid,text,text,text,uuid,bigint),public.set_reference_selection(uuid,boolean,bigint),public.archive_reference_card(uuid,bigint),public.set_reference_preference(uuid,text,text),public.add_reference_comment(uuid,text),public.get_reference_boards(uuid),public.get_reference_board(uuid,integer,uuid),public.get_reference_comments(uuid,uuid,integer),public.duplicate_reference_template(uuid,text,uuid),public.get_project_journey(uuid),public.save_project_proposal(uuid,jsonb,uuid,uuid,bigint),public.transition_project_proposal(uuid,bigint,text,text),public.respond_project_proposal(uuid,uuid,text,text),public.get_project_proposal(uuid),public.get_proposal_revision(uuid),public.proposal_source_options(uuid,text,text,uuid[]),public.reserve_planning_upload(text,text,bigint,uuid,uuid,bigint),public.finalize_planning_upload(uuid),public.remove_planning_file(uuid,bigint),public.lign_reference_contributor(uuid),public.lign_prepare_proposal(uuid),public.lign_edit_reference(uuid),public.lign_read_planning_file(uuid),public.lign_upload_planning_object(text),public.lign_project_has_agreed_brief(uuid) to authenticated,service_role;

revoke all on function public.lign_discard_planning_object(text) from public,anon,authenticated;
grant execute on function public.lign_discard_planning_object(text) to authenticated,service_role;

revoke all on function public.remove_reference_attachment(uuid,bigint) from public,anon,authenticated;
grant execute on function public.remove_reference_attachment(uuid,bigint) to authenticated,service_role;
