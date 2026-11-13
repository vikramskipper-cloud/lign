-- Organisation library: canonical collections, immutable private files and explicit project publication.
create table public.library_collections (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 title text not null check(length(trim(title)) between 1 and 160), kind text not null check(kind in ('template','references')),
 description text not null default '' check(length(description)<=3000), edit_version bigint not null default 1,
 archived_at timestamptz, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), unique(id,organization_id)
);
create index library_collections_org on public.library_collections(organization_id,id);
create table public.library_files (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 storage_path text not null unique, name text not null, mime_type text not null, size_bytes bigint not null,
 uploaded_by uuid not null references public.profiles(id), registered_at timestamptz, created_at timestamptz not null default now(), unique(id,organization_id)
);
create index library_files_org on public.library_files(organization_id);
create table public.library_items (
 id uuid primary key default gen_random_uuid(), collection_id uuid not null, organization_id uuid not null,
 title text not null check(length(trim(title)) between 1 and 200), description text not null default '' check(length(description)<=5000),
 url text check(url is null or (length(url)<=2000 and url ~* '^https?://[^[:space:]]+$')), file_id uuid,
 edit_version bigint not null default 1, archived_at timestamptz, created_at timestamptz not null default now(),
 foreign key(collection_id,organization_id) references public.library_collections(id,organization_id),
 foreign key(file_id,organization_id) references public.library_files(id,organization_id)
);
create index library_items_collection on public.library_items(collection_id,id);
create index library_items_file on public.library_items(file_id,organization_id);
-- Publications are retained for existing project references and immutable brief/proposal evidence.
create table public.library_publications (
 file_id uuid not null references public.library_files(id), project_id uuid not null references public.projects(id),
 created_at timestamptz not null default now(), primary key(file_id,project_id)
);
create index library_publications_project on public.library_publications(project_id);
alter table public.reference_cards add column library_file_id uuid references public.library_files(id);
create index reference_cards_library_file on public.reference_cards(library_file_id);
create or replace function public.lign_read_library_file(p_file_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.library_files f where f.id=p_file_id and f.registered_at is not null and
 (public.lign_is_org_member(f.organization_id) or exists(select 1 from public.library_publications x join public.projects p on p.id=x.project_id where x.file_id=f.id and public.lign_has_capability(p.id,p.workspace_id,'project.view')))); $$;
create or replace function public.library_file_snapshot(p_file_id uuid)
returns jsonb language sql stable security definer set search_path=''
as $$ select jsonb_build_object('id',id,'path',storage_path,'name',name,'mime',mime_type,'size',size_bytes,'bucket','organization-library') from public.library_files where id=p_file_id and registered_at is not null; $$;
alter table public.library_collections enable row level security;
alter table public.library_items enable row level security;
alter table public.library_files enable row level security;
alter table public.library_publications enable row level security;
create policy library_collections_read on public.library_collections for select to authenticated using(public.lign_is_org_member(organization_id));
create policy library_items_read on public.library_items for select to authenticated using(public.lign_is_org_member(organization_id));
create policy library_files_read on public.library_files for select to authenticated using(public.lign_read_library_file(id));
revoke all on public.library_collections,public.library_items,public.library_files,public.library_publications from anon,authenticated;
grant select on public.library_collections,public.library_items,public.library_files to authenticated;
grant all on public.library_collections,public.library_items,public.library_files,public.library_publications to service_role;

create or replace function public.save_library_collection(p_organization_id uuid,p_title text,p_kind text,p_description text default '',p_id uuid default null,p_expected_version bigint default 0,p_archive boolean default false)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v uuid;begin
 perform 1 from public.organizations where id=p_organization_id for no key update;
 if not public.lign_is_org_admin(p_organization_id) then raise exception 'Organisation administrator access required' using errcode='42501';end if;
 if p_id is null then
 if p_archive or p_expected_version<>0 then raise exception 'Invalid new collection' using errcode='22023';end if;
 if (select count(*) from public.library_collections where organization_id=p_organization_id and archived_at is null)>=100 then raise exception 'Use at most 100 active collections' using errcode='23514';end if;
 insert into public.library_collections(organization_id,title,kind,description,created_by) values(p_organization_id,trim(p_title),p_kind,p_description,auth.uid()) returning id into v;
 else update public.library_collections set title=trim(p_title),kind=p_kind,description=p_description,archived_at=case when p_archive then now() else null end,edit_version=edit_version+1 where id=p_id and organization_id=p_organization_id and edit_version=p_expected_version and archived_at is null returning id into v;
 if v is null then raise exception 'Collection changed. Reload before saving.' using errcode='PT409';end if;end if;return v;end; $$;

create or replace function public.save_library_item(p_collection_id uuid,p_title text,p_description text default '',p_url text default null,p_id uuid default null,p_expected_version bigint default 0,p_file_id uuid default null,p_archive boolean default false)
returns uuid language plpgsql security definer set search_path=''
as $$ declare b public.library_collections%rowtype;v uuid;begin
 select * into b from public.library_collections where id=p_collection_id for update;
 if b.id is null or b.archived_at is not null or not public.lign_is_org_admin(b.organization_id) then raise exception 'Active collection administrator access required' using errcode='42501';end if;
 if p_file_id is not null and not exists(select 1 from public.library_files where id=p_file_id and organization_id=b.organization_id and registered_at is not null) then raise exception 'Choose a registered organisation file' using errcode='22023';end if;
 if p_id is null then
 if p_archive or p_expected_version<>0 then raise exception 'Invalid new reference' using errcode='22023';end if;
 if (select count(*) from public.library_items where collection_id=b.id and archived_at is null)>=100 then raise exception 'Use at most 100 references per collection' using errcode='23514';end if;
 insert into public.library_items(collection_id,organization_id,title,description,url,file_id) values(b.id,b.organization_id,trim(p_title),p_description,nullif(trim(p_url),''),p_file_id) returning id into v;
 else update public.library_items set title=trim(p_title),description=p_description,url=nullif(trim(p_url),''),file_id=p_file_id,archived_at=case when p_archive then now() else null end,edit_version=edit_version+1 where id=p_id and collection_id=b.id and edit_version=p_expected_version and archived_at is null returning id into v;
 if v is null then raise exception 'Reference changed. Reload before saving.' using errcode='PT409';end if;end if;return v;end; $$;

create or replace function public.get_organization_library(p_organization_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ begin
 if not public.lign_is_org_member(p_organization_id) then raise exception 'Organisation membership required' using errcode='42501';end if;
 return jsonb_build_object('canManage',public.lign_is_org_admin(p_organization_id),'collections',(select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('itemCount',(select count(*) from public.library_items where collection_id=b.id and archived_at is null)) order by b.title,b.id),'[]'::jsonb) from public.library_collections b where b.organization_id=p_organization_id and b.archived_at is null));end; $$;
create or replace function public.get_library_items(p_collection_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare b public.library_collections%rowtype;begin
 select * into b from public.library_collections where id=p_collection_id;
 if b.id is null or not public.lign_is_org_member(b.organization_id) then raise exception 'Organisation membership required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('file',public.library_file_snapshot(i.file_id)) order by i.created_at,i.id),'[]'::jsonb) from public.library_items i where collection_id=b.id and archived_at is null);end; $$;

create or replace function public.reserve_library_upload(p_organization_id uuid,p_name text,p_mime text,p_size bigint)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare v uuid:=gen_random_uuid();v_path text;begin
 if not public.lign_is_org_admin(p_organization_id) then raise exception 'Organisation administrator access required' using errcode='42501';end if;
 if coalesce(length(trim(p_name)),0) not between 1 and 180 or p_name~'[[:cntrl:]]' or p_size is null or p_size not between 1 and 52428800 or p_mime is null or p_mime not in ('image/png','image/jpeg','image/webp','application/pdf','text/plain','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') then raise exception 'Choose an image, PDF or document up to 50 MB' using errcode='22023';end if;
 v_path:=p_organization_id::text||'/'||v::text;
 insert into public.library_files(id,organization_id,storage_path,name,mime_type,size_bytes,uploaded_by) values(v,p_organization_id,v_path,trim(p_name),p_mime,p_size,auth.uid());
 return jsonb_build_object('id',v,'path',v_path);end; $$;
create or replace function public.lign_pending_library_upload(p_path text)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.library_files where storage_path=p_path and uploaded_by=auth.uid() and registered_at is null and created_at>now()-interval '1 day' and public.lign_is_org_admin(organization_id)); $$;
create or replace function public.finalize_library_upload(p_file_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $$ declare f public.library_files%rowtype;v_size bigint;v_mime text;v_owner text;begin
 select * into f from public.library_files where id=p_file_id for update;
 if f.id is null or f.uploaded_by<>auth.uid() or not public.lign_is_org_admin(f.organization_id) then raise exception 'Your administrator upload is required' using errcode='42501';end if;
 if f.registered_at is not null then return f.id;end if;
 if not public.lign_pending_library_upload(f.storage_path) then raise exception 'Upload reservation expired' using errcode='42501';end if;
 select (metadata->>'size')::bigint,metadata->>'mimetype',owner_id into v_size,v_mime,v_owner from storage.objects where bucket_id='organization-library' and name=f.storage_path;
 if v_size is distinct from f.size_bytes or v_mime is distinct from f.mime_type or v_owner is distinct from auth.uid()::text then raise exception 'File does not match its reservation' using errcode='23514';end if;
 update public.library_files set registered_at=now() where id=f.id;return f.id;end; $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('organization-library','organization-library',false,52428800,array['image/png','image/jpeg','image/webp','application/pdf','text/plain','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);
create policy library_upload on storage.objects for insert to authenticated with check(bucket_id='organization-library' and public.lign_pending_library_upload(name));
create policy library_download on storage.objects for select to authenticated using(bucket_id='organization-library' and (public.lign_pending_library_upload(name) or exists(select 1 from public.library_files f where f.storage_path=storage.objects.name and public.lign_read_library_file(f.id))));
create policy library_discard on storage.objects for delete to authenticated using(bucket_id='organization-library' and owner_id=auth.uid()::text and public.lign_pending_library_upload(name));

create or replace function public.import_library_collection(p_collection_id uuid,p_project_id uuid,p_title text,p_area_id uuid default null)
returns uuid language plpgsql security definer set search_path=''
as $$ declare b public.library_collections%rowtype;p public.projects%rowtype;v uuid;begin
 select * into p from public.projects where id=p_project_id for no key update;
 select * into b from public.library_collections where id=p_collection_id for update;
 if b.id is null or b.archived_at is not null or not public.lign_is_org_member(b.organization_id) or not public.lign_manage_project_brief(p_project_id) or not exists(select 1 from public.workspaces where id=p.workspace_id and organization_id=b.organization_id) then raise exception 'Choose a library collection in the project organisation with project leadership access' using errcode='42501';end if;
 if not exists(select 1 from public.library_items where collection_id=b.id and archived_at is null) then raise exception 'Add references before using this collection' using errcode='22023';end if;
 v:=public.save_reference_board(p_project_id,p_title,case when b.kind='template' then 'moodboard' else 'references' end,b.description,p_area_id);
 insert into public.reference_cards(board_id,project_id,workspace_id,title,description,url,library_file_id,author_id)
 select v,p.id,p.workspace_id,i.title,i.description,i.url,i.file_id,auth.uid() from public.library_items i where i.collection_id=b.id and i.archived_at is null;
 insert into public.library_publications(file_id,project_id) select distinct file_id,p.id from public.library_items where collection_id=b.id and archived_at is null and file_id is not null on conflict do nothing;
 perform public.planning_event(p.id,'library.imported',v,jsonb_build_object('collection_id',b.id));return v;end; $$;

create or replace function public.reference_card_snapshot(p_card_id uuid)
returns jsonb language sql stable security definer set search_path=''
as $$ select jsonb_build_object('id',c.id,'title',c.title,'description',c.description,'url',c.url,'boardId',b.id,'boardTitle',b.title,'areaId',b.area_id,
 'areaPath',(select path from public.project_area_paths(c.project_id) where id=b.area_id),'authorId',c.author_id,'authorName',p.display_name,'editVersion',c.edit_version,'selected',c.selected_for_brief,
 'file',coalesce((select jsonb_build_object('id',f.id,'path',f.storage_path,'name',f.name,'mime',f.mime_type,'size',f.size_bytes) from public.planning_files f where f.id=c.file_id and f.registered_at is not null),public.library_file_snapshot(c.library_file_id)),
 'preferences',(select coalesce(jsonb_agg(jsonb_build_object('userId',v.user_id,'name',vp.display_name,'choice',v.choice,'note',v.note,'at',v.updated_at) order by v.updated_at,v.user_id),'[]'::jsonb) from public.reference_preferences v join public.profiles vp on vp.id=v.user_id where v.card_id=c.id),
 'commentCount',(select count(*) from public.reference_comments where card_id=c.id))
 from public.reference_cards c join public.reference_boards b on b.id=c.board_id join public.profiles p on p.id=c.author_id where c.id=p_card_id; $$;
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
 if f.reference_card_id is not null then update public.reference_cards set file_id=f.id,library_file_id=null,edit_version=edit_version+1 where id=f.reference_card_id returning edit_version into v_version;
 else update public.project_proposals set edit_version=edit_version+1,updated_at=now() where id=f.proposal_id returning edit_version into v_version;end if;
 perform public.planning_event(f.project_id,'planning_file.registered',f.id);return jsonb_build_object('id',f.id,'version',v_version);end; $$;
create or replace function public.remove_reference_attachment(p_card_id uuid,p_expected_version bigint)
returns void language plpgsql security definer set search_path=''
as $$ declare c public.reference_cards%rowtype;begin
 select * into c from public.reference_cards where id=p_card_id;
 perform 1 from public.projects where id=c.project_id for no key update;
 select * into c from public.reference_cards where id=p_card_id for update;
 if c.id is null or not public.lign_edit_reference(c.id) then raise exception 'Reference editing access required' using errcode='42501';end if;
 if c.edit_version is distinct from p_expected_version or (c.file_id is null and c.library_file_id is null) then raise exception 'The reference changed. Reload before removing its attachment.' using errcode='PT409';end if;
 update public.reference_cards set file_id=null,library_file_id=null,edit_version=edit_version+1 where id=c.id;
 perform public.planning_event(c.project_id,'reference.attachment_removed',c.id,jsonb_build_object('file_id',c.file_id));
 end; $$;
create or replace function public.duplicate_reference_template(p_board_id uuid,p_title text,p_area_id uuid default null)
returns uuid language plpgsql security definer set search_path=''
as $$ declare b public.reference_boards%rowtype;v_id uuid;begin
 select * into b from public.reference_boards where id=p_board_id;
 perform 1 from public.projects where id=b.project_id for no key update;
 select * into b from public.reference_boards where id=p_board_id for update;
 if b.id is null or b.kind<>'template' or b.archived_at is not null or not public.lign_manage_project_brief(b.project_id) then raise exception 'Choose a template managed in this project' using errcode='42501'; end if;
 v_id:=public.save_reference_board(b.project_id,p_title,'moodboard',b.description,p_area_id);
 insert into public.reference_cards(board_id,project_id,workspace_id,title,description,url,file_id,library_file_id,author_id)
 select v_id,c.project_id,c.workspace_id,c.title,c.description,c.url,c.file_id,c.library_file_id,auth.uid() from public.reference_cards c where c.board_id=b.id and c.archived_at is null;
 perform public.planning_event(b.project_id,'reference_template.used',v_id,jsonb_build_object('source_board_id',b.id));return v_id;end; $$;
revoke all on function public.lign_read_library_file(uuid) from public,anon,authenticated;
revoke all on function public.save_library_collection(uuid,text,text,text,uuid,bigint,boolean) from public,anon,authenticated;
revoke all on function public.save_library_item(uuid,text,text,text,uuid,bigint,uuid,boolean) from public,anon,authenticated;
revoke all on function public.get_organization_library(uuid) from public,anon,authenticated;
revoke all on function public.get_library_items(uuid) from public,anon,authenticated;
revoke all on function public.reserve_library_upload(uuid,text,text,bigint) from public,anon,authenticated;
revoke all on function public.lign_pending_library_upload(text) from public,anon,authenticated;
revoke all on function public.finalize_library_upload(uuid) from public,anon,authenticated;
revoke all on function public.import_library_collection(uuid,uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.library_file_snapshot(uuid) from public,anon,authenticated;
grant execute on function public.lign_read_library_file(uuid) to authenticated,service_role;
grant execute on function public.save_library_collection(uuid,text,text,text,uuid,bigint,boolean) to authenticated,service_role;
grant execute on function public.save_library_item(uuid,text,text,text,uuid,bigint,uuid,boolean) to authenticated,service_role;
grant execute on function public.get_organization_library(uuid) to authenticated,service_role;
grant execute on function public.get_library_items(uuid) to authenticated,service_role;
grant execute on function public.reserve_library_upload(uuid,text,text,bigint) to authenticated,service_role;
grant execute on function public.lign_pending_library_upload(text) to authenticated,service_role;
grant execute on function public.finalize_library_upload(uuid) to authenticated,service_role;
grant execute on function public.import_library_collection(uuid,uuid,text,uuid) to authenticated,service_role;
