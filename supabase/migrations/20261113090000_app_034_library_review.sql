-- APP 034: member-authored private drafts, locked reviews and immutable published library revisions.
alter table public.library_collections add column status text not null default 'draft' check(status in ('draft','in_review','changes_requested','published'));
alter table public.library_collections add column tags text[] not null default '{}' check(cardinality(tags)<=12);
alter table public.library_collections add column review_note text not null default '' check(length(review_note)<=3000);
alter table public.library_collections add column published_revision_id uuid;
alter table public.library_collections drop constraint library_collections_kind_check;
alter table public.library_collections add constraint library_collections_kind_check check(kind in ('template','references','moodboard','designs'));
create table public.library_revisions (
 id uuid primary key default gen_random_uuid(), collection_id uuid not null, organization_id uuid not null,
 revision_number integer not null check(revision_number>0), snapshot jsonb not null,
 published_by uuid not null references public.profiles(id), published_at timestamptz not null default now(),
 foreign key(collection_id,organization_id) references public.library_collections(id,organization_id),
 unique(collection_id,revision_number),unique(id,collection_id,organization_id),unique(id,organization_id)
);
create table public.library_revision_files (
 revision_id uuid not null, organization_id uuid not null, file_id uuid not null,
 primary key(revision_id,file_id),foreign key(revision_id,organization_id) references public.library_revisions(id,organization_id),
 foreign key(file_id,organization_id) references public.library_files(id,organization_id)
);
create index library_revision_files_file on public.library_revision_files(file_id,organization_id);
alter table public.library_collections add constraint library_published_revision_fk foreign key(published_revision_id,id,organization_id) references public.library_revisions(id,collection_id,organization_id);
create index library_collections_published on public.library_collections(published_revision_id);
create table public.library_review_events (
 id uuid primary key default gen_random_uuid(),collection_id uuid not null references public.library_collections(id),
 actor_id uuid not null references public.profiles(id),action text not null check(action in ('submit','publish','request_changes','withdraw','revise','archive')),
 note text not null default '' check(length(note)<=3000),created_at timestamptz not null default now()
);
create index library_review_events_collection on public.library_review_events(collection_id,created_at,id);
create or replace function public.preserve_library_review_history()
returns trigger language plpgsql set search_path=''
as $$ begin raise exception 'Published library revisions and review records are immutable' using errcode='23514';end; $$;
create trigger library_revision_immutable before update or delete on public.library_revisions for each row execute function public.preserve_library_review_history();
create trigger library_revision_files_immutable before update or delete on public.library_revision_files for each row execute function public.preserve_library_review_history();
create trigger library_review_events_immutable before update or delete on public.library_review_events for each row execute function public.preserve_library_review_history();
create or replace function public.lign_library_author(p_collection_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.library_collections b where b.id=p_collection_id and public.lign_is_org_member(b.organization_id) and (b.created_by=auth.uid() or public.lign_is_org_admin(b.organization_id))); $$;
create or replace function public.library_draft_snapshot(p_collection_id uuid)
returns jsonb language sql stable security definer set search_path=''
as $$ select jsonb_build_object('id',b.id,'title',b.title,'kind',b.kind,'description',b.description,'tags',b.tags,'items',
 (select coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('file',public.library_file_snapshot(i.file_id)) order by i.created_at,i.id),'[]'::jsonb) from public.library_items i where i.collection_id=b.id and i.archived_at is null)) from public.library_collections b where b.id=p_collection_id; $$;
-- Existing administrator-curated, nonempty collections retain their published availability.
insert into public.library_revisions(collection_id,organization_id,revision_number,snapshot,published_by)
 select b.id,b.organization_id,1,public.library_draft_snapshot(b.id),b.created_by from public.library_collections b
 where b.archived_at is null and exists(select 1 from public.library_items where collection_id=b.id and archived_at is null);
insert into public.library_revision_files(revision_id,organization_id,file_id)
 select distinct r.id,r.organization_id,i.file_id from public.library_revisions r join public.library_items i on i.collection_id=r.collection_id where i.archived_at is null and i.file_id is not null;
update public.library_collections b set status='published',published_revision_id=r.id from public.library_revisions r where r.collection_id=b.id;

-- Raw working data is private even when an older approved version is available to members.
alter policy library_collections_read on public.library_collections using(public.lign_library_author(id));
alter policy library_items_read on public.library_items using(public.lign_library_author(collection_id));
alter table public.library_revisions enable row level security;
alter table public.library_revision_files enable row level security;
alter table public.library_review_events enable row level security;
create policy library_revisions_read on public.library_revisions for select to authenticated using(public.lign_is_org_member(organization_id));
create policy library_revision_files_read on public.library_revision_files for select to authenticated using(public.lign_is_org_member(organization_id));
create policy library_review_events_read on public.library_review_events for select to authenticated using(public.lign_library_author(collection_id));
revoke all on public.library_revisions,public.library_revision_files,public.library_review_events from anon,authenticated;
grant select on public.library_revisions,public.library_revision_files,public.library_review_events to authenticated;
grant all on public.library_revisions,public.library_revision_files,public.library_review_events to service_role;

create or replace function public.save_library_collection(p_organization_id uuid,p_title text,p_kind text,p_description text default '',p_id uuid default null,p_expected_version bigint default 0,p_archive boolean default false)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v uuid;b public.library_collections%rowtype;begin
 perform 1 from public.organizations where id=p_organization_id for no key update;
 if not public.lign_is_org_member(p_organization_id) then raise exception 'Active organisation membership required' using errcode='42501';end if;
 if p_id is null then
 if p_archive or p_expected_version is distinct from 0 then raise exception 'Invalid new draft' using errcode='22023';end if;
 if (select count(*) from public.library_collections where organization_id=p_organization_id and archived_at is null)>=100 then raise exception 'Use at most 100 active collections' using errcode='23514';end if;
 insert into public.library_collections(organization_id,title,kind,description,created_by) values(p_organization_id,trim(p_title),p_kind,p_description,auth.uid()) returning id into v;
 else
 select * into b from public.library_collections where id=p_id for update;
 if b.id is null or b.organization_id<>p_organization_id or not public.lign_library_author(b.id) then raise exception 'Your draft or administrator access required' using errcode='42501';end if;
 if b.edit_version is distinct from p_expected_version or b.archived_at is not null then raise exception 'Collection changed. Reload before saving.' using errcode='PT409';end if;
 if p_archive then
 if b.published_revision_id is not null and not public.lign_is_org_admin(b.organization_id) then raise exception 'Only administrators can archive published collections' using errcode='42501';end if;
 update public.library_collections set archived_at=now(),edit_version=edit_version+1 where id=b.id;
 insert into public.library_review_events(collection_id,actor_id,action) values(b.id,auth.uid(),'archive');
 else
 if b.status not in ('draft','changes_requested') then raise exception 'Start a revision or withdraw the review before editing' using errcode='23514';end if;
 update public.library_collections set title=trim(p_title),kind=p_kind,description=p_description,edit_version=edit_version+1 where id=b.id;
 end if;v:=b.id;end if;return v;end; $$;
create or replace function public.save_library_item(p_collection_id uuid,p_title text,p_description text default '',p_url text default null,p_id uuid default null,p_expected_version bigint default 0,p_file_id uuid default null,p_archive boolean default false)
returns uuid language plpgsql security definer set search_path=''
as $$ declare b public.library_collections%rowtype;v uuid;begin
 select * into b from public.library_collections where id=p_collection_id for update;
 if b.id is null or b.archived_at is not null or not public.lign_library_author(b.id) then raise exception 'Your active draft or administrator access required' using errcode='42501';end if;
 if b.status not in ('draft','changes_requested') then raise exception 'Only a draft can be edited' using errcode='23514';end if;
 if p_file_id is not null and not exists(select 1 from public.library_files where id=p_file_id and organization_id=b.organization_id and registered_at is not null and public.lign_read_library_file(id)) then raise exception 'Choose a registered organisation file' using errcode='22023';end if;
 if p_id is null then
 if p_archive or p_expected_version<>0 then raise exception 'Invalid new reference' using errcode='22023';end if;
 if (select count(*) from public.library_items where collection_id=b.id and archived_at is null)>=100 then raise exception 'Use at most 100 references per collection' using errcode='23514';end if;
 insert into public.library_items(collection_id,organization_id,title,description,url,file_id) values(b.id,b.organization_id,trim(p_title),p_description,nullif(trim(p_url),''),p_file_id) returning id into v;
 else update public.library_items set title=trim(p_title),description=p_description,url=nullif(trim(p_url),''),file_id=p_file_id,archived_at=case when p_archive then now() else null end,edit_version=edit_version+1 where id=p_id and collection_id=b.id and edit_version=p_expected_version and archived_at is null returning id into v;
 if v is null then raise exception 'Reference changed. Reload before saving.' using errcode='PT409';end if;end if;update public.library_collections set edit_version=edit_version+1 where id=b.id;return v;end; $$;

create or replace function public.transition_library_collection(p_collection_id uuid,p_expected_version bigint,p_action text,p_note text default '')
returns void language plpgsql security definer set search_path=''
as $$ declare b public.library_collections%rowtype;v_id uuid;v_snapshot jsonb;begin
 select * into b from public.library_collections where id=p_collection_id for update;
 if b.id is null or b.archived_at is not null or not public.lign_library_author(b.id) then raise exception 'Author or organisation administrator access required' using errcode='42501';end if;
 if b.edit_version is distinct from p_expected_version then raise exception 'Collection changed. Reload before continuing.' using errcode='PT409';end if;
 if p_note is null or length(p_note)>3000 then raise exception 'Use feedback up to 3000 characters' using errcode='22023';end if;
 if p_action='submit' and b.status in ('draft','changes_requested') then
 if not exists(select 1 from public.library_items where collection_id=b.id and archived_at is null) then raise exception 'Add at least one reference before submitting' using errcode='23514';end if;
 update public.library_collections set status='in_review',edit_version=edit_version+1 where id=b.id;
 elsif p_action in ('publish','request_changes') and b.status='in_review' then
 if not public.lign_is_org_admin(b.organization_id) then raise exception 'Organisation administrator approval required' using errcode='42501';end if;
 if p_action='request_changes' then
 if length(trim(p_note))=0 then raise exception 'Explain the changes requested' using errcode='22023';end if;
 update public.library_collections set status='changes_requested',review_note=trim(p_note),edit_version=edit_version+1 where id=b.id;
 else
 v_snapshot:=public.library_draft_snapshot(b.id);
 insert into public.library_revisions(collection_id,organization_id,revision_number,snapshot,published_by)
 values(b.id,b.organization_id,(select coalesce(max(revision_number),0)+1 from public.library_revisions where collection_id=b.id),v_snapshot,auth.uid()) returning id into v_id;
 insert into public.library_revision_files(revision_id,organization_id,file_id) select distinct v_id,b.organization_id,file_id from public.library_items where collection_id=b.id and archived_at is null and file_id is not null;
 update public.library_collections set status='published',published_revision_id=v_id,review_note='',edit_version=edit_version+1 where id=b.id;
 end if;
 elsif p_action='withdraw' and b.status='in_review' then
 update public.library_collections set status='draft',edit_version=edit_version+1 where id=b.id;
 elsif p_action='revise' and b.status='published' then
 update public.library_collections set status='draft',edit_version=edit_version+1 where id=b.id;
 else raise exception 'This action is not available at the current stage' using errcode='23514';end if;
 insert into public.library_review_events(collection_id,actor_id,action,note) values(b.id,auth.uid(),p_action,trim(p_note));end; $$;

create or replace function public.get_organization_library(p_organization_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ begin
 if not public.lign_is_org_member(p_organization_id) then raise exception 'Organisation membership required' using errcode='42501';end if;
 return jsonb_build_object('canManage',public.lign_is_org_admin(p_organization_id),'collections',
 (select coalesce(jsonb_agg(case when public.lign_library_author(b.id) then
 to_jsonb(b)||jsonb_build_object('itemCount',(select count(*) from public.library_items where collection_id=b.id and archived_at is null),'canSeeDraft',true,'canEdit',b.status in ('draft','changes_requested'),'canReview',public.lign_is_org_admin(b.organization_id) and b.status='in_review')
 else jsonb_build_object('id',b.id,'title',r.snapshot->>'title','kind',r.snapshot->>'kind','description',r.snapshot->>'description','tags',r.snapshot->'tags','status','published','edit_version',0,'itemCount',jsonb_array_length(r.snapshot->'items'),'canSeeDraft',false,'canEdit',false,'canReview',false) end
 ||jsonb_build_object('authorName',p.display_name,'published',case when r.id is not null then (r.snapshot-'items')||jsonb_build_object('revision',r.revision_number) else null end) order by b.created_at,b.id),'[]'::jsonb)
 from public.library_collections b join public.profiles p on p.id=b.created_by left join public.library_revisions r on r.id=b.published_revision_id
 where b.organization_id=p_organization_id and b.archived_at is null and (public.lign_library_author(b.id) or r.id is not null)));end; $$;
create or replace function public.get_published_library(p_organization_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ begin
 if not public.lign_is_org_member(p_organization_id) then raise exception 'Organisation membership required' using errcode='42501';end if;
 return jsonb_build_object('canManage',false,'collections',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'title',r.snapshot->>'title','description',r.snapshot->>'description','kind',r.snapshot->>'kind','itemCount',jsonb_array_length(r.snapshot->'items'),'edit_version',0,'status','published') order by r.snapshot->>'title',b.id),'[]'::jsonb) from public.library_collections b join public.library_revisions r on r.id=b.published_revision_id where b.organization_id=p_organization_id and b.archived_at is null));end; $$;
-- This existing RPC now always returns approved items, including during a pending revision.
create or replace function public.get_library_items(p_collection_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare b public.library_collections%rowtype;begin
 select * into b from public.library_collections where id=p_collection_id;
 if b.id is null or b.archived_at is not null or not public.lign_is_org_member(b.organization_id) then raise exception 'Organisation membership required' using errcode='42501';end if;
 return coalesce((select snapshot->'items' from public.library_revisions where id=b.published_revision_id),'[]'::jsonb);end; $$;
create or replace function public.get_library_draft_items(p_collection_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ begin
 if not public.lign_library_author(p_collection_id) then raise exception 'Author or administrator access required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('file',public.library_file_snapshot(i.file_id)) order by i.created_at,i.id),'[]'::jsonb) from public.library_items i where collection_id=p_collection_id and archived_at is null);end; $$;
create or replace function public.get_library_review_history(p_collection_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ begin
 if not public.lign_library_author(p_collection_id) then raise exception 'Author or administrator access required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc),'[]'::jsonb) from (select e.id,e.action,e.note,e.created_at,p.display_name as name from public.library_review_events e join public.profiles p on p.id=e.actor_id where e.collection_id=p_collection_id order by e.created_at desc,e.id desc limit 30)x);end; $$;
create or replace function public.lign_read_library_file(p_file_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.library_files f where f.id=p_file_id and f.registered_at is not null and
 ((public.lign_is_org_member(f.organization_id) and (f.uploaded_by=auth.uid() or public.lign_is_org_admin(f.organization_id)
 or exists(select 1 from public.library_items i where i.file_id=f.id and public.lign_library_author(i.collection_id))
 or exists(select 1 from public.library_revision_files r where r.file_id=f.id)))
 or exists(select 1 from public.library_publications x join public.projects p on p.id=x.project_id where x.file_id=f.id and public.lign_has_capability(p.id,p.workspace_id,'project.view')))); $$;
create or replace function public.reserve_library_upload(p_organization_id uuid,p_name text,p_mime text,p_size bigint)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare v uuid:=gen_random_uuid();v_path text;begin
 if not public.lign_is_org_member(p_organization_id) then raise exception 'Active organisation membership required' using errcode='42501';end if;
 if coalesce(length(trim(p_name)),0) not between 1 and 180 or p_name~'[[:cntrl:]]' or p_size is null or p_size not between 1 and 52428800 or p_mime is null or p_mime not in ('image/png','image/jpeg','image/webp','application/pdf','text/plain','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') then raise exception 'Choose an image, PDF or document up to 50 MB' using errcode='22023';end if;
 v_path:=p_organization_id::text||'/'||v::text;
 insert into public.library_files(id,organization_id,storage_path,name,mime_type,size_bytes,uploaded_by) values(v,p_organization_id,v_path,trim(p_name),p_mime,p_size,auth.uid());
 return jsonb_build_object('id',v,'path',v_path);end; $$;
create or replace function public.lign_pending_library_upload(p_path text)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.library_files where storage_path=p_path and uploaded_by=auth.uid() and registered_at is null and created_at>now()-interval '1 day' and public.lign_is_org_member(organization_id)); $$;
create or replace function public.finalize_library_upload(p_file_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $$ declare f public.library_files%rowtype;v_size bigint;v_mime text;v_owner text;begin
 select * into f from public.library_files where id=p_file_id for update;
 if f.id is null or f.uploaded_by<>auth.uid() or not public.lign_is_org_member(f.organization_id) then raise exception 'Your organisation upload is required' using errcode='42501';end if;
 if f.registered_at is not null then return f.id;end if;
 if not public.lign_pending_library_upload(f.storage_path) then raise exception 'Upload reservation expired' using errcode='42501';end if;
 select (metadata->>'size')::bigint,metadata->>'mimetype',owner_id into v_size,v_mime,v_owner from storage.objects where bucket_id='organization-library' and name=f.storage_path;
 if v_size is distinct from f.size_bytes or v_mime is distinct from f.mime_type or v_owner is distinct from auth.uid()::text then raise exception 'File does not match its reservation' using errcode='23514';end if;
 update public.library_files set registered_at=now() where id=f.id;return f.id;end; $$;

create or replace function public.import_library_collection(p_collection_id uuid,p_project_id uuid,p_title text,p_area_id uuid default null)
returns uuid language plpgsql security definer set search_path=''
as $$ declare b public.library_collections%rowtype;p public.projects%rowtype;v uuid;v_snapshot jsonb;begin
 select * into p from public.projects where id=p_project_id for no key update;
 select * into b from public.library_collections where id=p_collection_id for update;
 if b.id is null or b.archived_at is not null or not public.lign_is_org_member(b.organization_id) or not public.lign_manage_project_brief(p_project_id) or not exists(select 1 from public.workspaces where id=p.workspace_id and organization_id=b.organization_id) then raise exception 'Choose a library collection in the project organisation with project leadership access' using errcode='42501';end if;
 select snapshot into v_snapshot from public.library_revisions where id=b.published_revision_id;
 if v_snapshot is null or jsonb_array_length(v_snapshot->'items')=0 then raise exception 'Only approved published collections can be used in projects' using errcode='23514';end if;
 v:=public.save_reference_board(p_project_id,p_title,case when v_snapshot->>'kind' in ('template','moodboard') then 'moodboard' else 'references' end,v_snapshot->>'description',p_area_id);
 insert into public.reference_cards(board_id,project_id,workspace_id,title,description,url,library_file_id,author_id)
 select v,p.id,p.workspace_id,i->>'title',i->>'description',i->>'url',(i->>'file_id')::uuid,auth.uid() from jsonb_array_elements(v_snapshot->'items') i;
 insert into public.library_publications(file_id,project_id) select file_id,p.id from public.library_revision_files where revision_id=b.published_revision_id on conflict do nothing;
 perform public.planning_event(p.id,'library.imported',v,jsonb_build_object('collection_id',b.id,'revision_id',b.published_revision_id));return v;end; $$;
revoke all on function public.lign_library_author(uuid) from public,anon,authenticated;
revoke all on function public.transition_library_collection(uuid,bigint,text,text) from public,anon,authenticated;
revoke all on function public.get_published_library(uuid) from public,anon,authenticated;
revoke all on function public.get_library_draft_items(uuid) from public,anon,authenticated;
revoke all on function public.get_library_review_history(uuid) from public,anon,authenticated;
revoke all on function public.library_draft_snapshot(uuid) from public,anon,authenticated;
revoke all on function public.preserve_library_review_history() from public,anon,authenticated;
grant execute on function public.lign_library_author(uuid) to authenticated,service_role;
grant execute on function public.transition_library_collection(uuid,bigint,text,text) to authenticated,service_role;
grant execute on function public.get_published_library(uuid) to authenticated,service_role;
grant execute on function public.get_library_draft_items(uuid) to authenticated,service_role;
grant execute on function public.get_library_review_history(uuid) to authenticated,service_role;

-- The metadata editor wraps the existing checked save so old callers retain the same guards.
create or replace function public.save_library_draft(p_organization_id uuid,p_title text,p_kind text,p_description text default '',p_id uuid default null,p_expected_version bigint default 0,p_tags text[] default '{}')
returns uuid language plpgsql security definer set search_path=''
as $$ declare v uuid;v_tags text[];begin
 if p_tags is null or cardinality(p_tags)>12 or exists(select 1 from unnest(p_tags) t where t is null or length(trim(t)) not between 1 and 40) then raise exception 'Use up to 12 tags of 1–40 characters' using errcode='22023';end if;
 select coalesce(array_agg(distinct lower(trim(t))),'{}') into v_tags from unnest(p_tags)t;
 v:=public.save_library_collection(p_organization_id,p_title,p_kind,p_description,p_id,p_expected_version,false);
 update public.library_collections set tags=v_tags where id=v;return v;end; $$;
revoke all on function public.save_library_draft(uuid,text,text,text,uuid,bigint,text[]) from public,anon,authenticated;
grant execute on function public.save_library_draft(uuid,text,text,text,uuid,bigint,text[]) to authenticated,service_role;
