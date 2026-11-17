alter table public.reference_preferences add column is_internal boolean not null default false;
alter table public.reference_comments add column is_internal boolean not null default false;

-- Existing boards retain their shared visibility. New boards start with the internal team.
alter table public.reference_boards add column shared_at timestamptz;
alter table public.reference_boards add column shared_by uuid references public.profiles(id);
alter table public.reference_boards add column is_client_input boolean not null default false;
create index reference_boards_shared_by_idx on public.reference_boards(shared_by);
create unique index reference_boards_client_input_unique on public.reference_boards(project_id) where is_client_input and archived_at is null;
update public.reference_boards set shared_at=created_at,shared_by=created_by;

create or replace function public.lign_reference_team(p_project_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.projects p join public.workspaces w on w.id=p.workspace_id
 where p.id=p_project_id and public.lign_has_capability(p.id,p.workspace_id,'project.view') and public.lign_is_org_member(w.organization_id)); $$;
create or replace function public.lign_read_reference_board(p_board_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.reference_boards b where b.id=p_board_id and b.archived_at is null
 and public.lign_has_capability(b.project_id,b.workspace_id,'project.view') and (b.shared_at is not null or public.lign_reference_team(b.project_id))); $$;

alter policy reference_boards_read on public.reference_boards using(public.lign_read_reference_board(id));
alter policy reference_cards_read on public.reference_cards using(public.lign_read_reference_board(board_id));
alter policy reference_preferences_read on public.reference_preferences using((not is_internal or public.lign_reference_team(project_id)) and exists(select 1 from public.reference_cards c where c.id=card_id and public.lign_read_reference_board(c.board_id)));
alter policy reference_comments_read on public.reference_comments using((not is_internal or public.lign_reference_team(project_id)) and exists(select 1 from public.reference_cards c where c.id=card_id and public.lign_read_reference_board(c.board_id)));

CREATE OR REPLACE FUNCTION public.get_reference_boards(p_project_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v_ws uuid;begin
 select workspace_id into v_ws from public.projects where id=p_project_id;
 if v_ws is null or not public.lign_has_capability(p_project_id,v_ws,'project.view') then raise exception 'Project access required' using errcode='42501'; end if;
 return jsonb_build_object('isTeam',public.lign_reference_team(p_project_id),'canManage',public.lign_manage_project_brief(p_project_id),'canContribute',public.lign_reference_contributor(p_project_id),
 'boards',(select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('areaPath',(select path from public.project_area_paths(p_project_id) where id=b.area_id),'selectedCount',(select count(*) from public.reference_cards where board_id=b.id and archived_at is null and selected_for_brief),'cardCount',(select count(*) from public.reference_cards where board_id=b.id and archived_at is null)) order by b.created_at,b.id),'[]'::jsonb) from public.reference_boards b where b.project_id=p_project_id and public.lign_read_reference_board(b.id)));
 end; $function$;

create or replace function public.reference_card_snapshot(p_card_id uuid)
returns jsonb language sql stable security definer set search_path=''
as $$ select jsonb_build_object('id',c.id,'title',c.title,'description',c.description,'url',c.url,'boardId',b.id,'boardTitle',b.title,'areaId',b.area_id,
 'areaPath',(select path from public.project_area_paths(c.project_id) where id=b.area_id),'authorId',c.author_id,'authorName',p.display_name,'editVersion',c.edit_version,'selected',c.selected_for_brief,
 'file',coalesce((select jsonb_build_object('id',f.id,'path',f.storage_path,'name',f.name,'mime',f.mime_type,'size',f.size_bytes) from public.planning_files f where f.id=c.file_id and f.registered_at is not null),public.library_file_snapshot(c.library_file_id)),
 'preferences',(select coalesce(jsonb_agg(jsonb_build_object('userId',v.user_id,'name',vp.display_name,'choice',v.choice,'note',v.note,'at',v.updated_at) order by v.updated_at,v.user_id),'[]'::jsonb) from public.reference_preferences v join public.profiles vp on vp.id=v.user_id where v.card_id=c.id and not v.is_internal),
 'commentCount',(select count(*) from public.reference_comments where card_id=c.id and not is_internal))
 from public.reference_cards c join public.reference_boards b on b.id=c.board_id join public.profiles p on p.id=c.author_id where c.id=p_card_id; $$;

CREATE OR REPLACE FUNCTION public.get_reference_board(p_board_id uuid, p_limit integer DEFAULT 24, p_after uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare b public.reference_boards%rowtype;v jsonb;begin
 select * into b from public.reference_boards where id=p_board_id;
 if b.id is null or not public.lign_read_reference_board(b.id) then raise exception 'Board access required' using errcode='42501'; end if;
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'Invalid page size' using errcode='22023'; end if;
 with page as (select id from public.reference_cards where board_id=b.id and archived_at is null and (p_after is null or id>p_after) order by id limit p_limit+1)
 select jsonb_build_object('cards',(select coalesce(jsonb_agg(public.reference_card_snapshot(x.id)||jsonb_build_object('canEdit',public.lign_edit_reference(x.id),
 'commentCount',(select count(*) from public.reference_comments n where n.card_id=x.id and (not n.is_internal or public.lign_reference_team(b.project_id))),
 'preferences',(select coalesce(jsonb_agg(jsonb_build_object('userId',v.user_id,'name',vp.display_name,'choice',v.choice,'note',v.note,'at',v.updated_at,'isInternal',v.is_internal) order by v.updated_at,v.user_id),'[]'::jsonb) from public.reference_preferences v join public.profiles vp on vp.id=v.user_id where v.card_id=x.id and (not v.is_internal or public.lign_reference_team(b.project_id)))) order by x.id),'[]'::jsonb) from(select id from page order by id limit p_limit)x),
 'nextCursor',case when (select count(*) from page)>p_limit then (select id from page order by id offset p_limit-1 limit 1) else null end) into v;
 return v;end; $function$;

CREATE OR REPLACE FUNCTION public.get_reference_comments(p_card_id uuid, p_after uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare c public.reference_cards%rowtype;v jsonb;begin
 select * into c from public.reference_cards where id=p_card_id;
 if c.id is null or not public.lign_read_reference_board(c.board_id) then raise exception 'Reference access required' using errcode='42501'; end if;
 if p_limit is null or p_limit not between 1 and 100 then raise exception 'Invalid page size' using errcode='22023'; end if;
 with page as (select x.id,x.body,x.is_internal,x.created_at,p.display_name as author from public.reference_comments x join public.profiles p on p.id=x.author_id where x.card_id=c.id and (not x.is_internal or public.lign_reference_team(c.project_id)) and (p_after is null or (x.created_at,x.id)>(select z.created_at,z.id from public.reference_comments z where z.id=p_after and z.card_id=c.id)) order by x.created_at,x.id limit p_limit+1)
 select jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at,x.id),'[]'::jsonb) from(select * from page order by created_at,id limit p_limit)x),
 'nextCursor',case when (select count(*) from page)>p_limit then (select id from page order by created_at,id offset p_limit-1 limit 1) else null end) into v;
 return v;end; $function$;

CREATE OR REPLACE FUNCTION public.lign_edit_reference(p_card_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select exists(select 1 from public.reference_cards c join public.reference_boards b on b.id=c.board_id where c.id=p_card_id and c.archived_at is null and b.archived_at is null
 and public.lign_read_reference_board(b.id) and public.lign_reference_contributor(c.project_id) and (c.author_id=auth.uid() or public.lign_manage_project_brief(c.project_id))); $function$;

CREATE OR REPLACE FUNCTION public.save_reference_card(p_board_id uuid, p_title text, p_description text DEFAULT ''::text, p_url text DEFAULT NULL::text, p_card_id uuid DEFAULT NULL::uuid, p_expected_version bigint DEFAULT 0)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare b public.reference_boards%rowtype;v_id uuid;begin
 select * into b from public.reference_boards where id=p_board_id for update;
 if b.id is null or not public.lign_read_reference_board(b.id) or b.archived_at is not null or not public.lign_reference_contributor(b.project_id) then raise exception 'Reference contribution access required' using errcode='42501'; end if;
 if coalesce(length(trim(p_title)),0) not between 1 and 200 or p_description is null or length(p_description)>5000 or length(coalesce(p_url,''))>2000 or (nullif(trim(p_url),'') is not null and trim(p_url)!~'^https?://[^[:space:]]+$') then raise exception 'Add a title and an HTTP/HTTPS reference link' using errcode='22023'; end if;
 if p_card_id is null then
 if (select count(*) from public.reference_cards where board_id=b.id and archived_at is null)>=200 then raise exception 'Use at most 200 active references per board' using errcode='23514'; end if;
 insert into public.reference_cards(board_id,project_id,workspace_id,title,description,url,author_id) values(b.id,b.project_id,b.workspace_id,trim(p_title),trim(p_description),nullif(trim(p_url),''),auth.uid()) returning id into v_id;
 else
 if not public.lign_edit_reference(p_card_id) then raise exception 'Only the author and project leadership can edit a reference' using errcode='42501'; end if;
 update public.reference_cards set title=trim(p_title),description=trim(p_description),url=nullif(trim(p_url),''),edit_version=edit_version+1 where id=p_card_id and board_id=b.id and edit_version=p_expected_version returning id into v_id;
 if v_id is null then raise exception 'The reference changed. Reload before saving.' using errcode='PT409'; end if;
 end if;
 perform public.planning_event(b.project_id,'reference.saved',v_id);return v_id;end; $function$;

drop function public.set_reference_preference(uuid,text,text);
CREATE OR REPLACE FUNCTION public.set_reference_preference(p_card_id uuid, p_choice text, p_note text DEFAULT ''::text, p_internal boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare c public.reference_cards%rowtype;v_previous jsonb;begin
 select * into c from public.reference_cards where id=p_card_id for share;
 if c.id is null or not public.lign_read_reference_board(c.board_id) or c.archived_at is not null or not public.lign_reference_contributor(c.project_id) or not exists(select 1 from public.reference_boards where id=c.board_id and archived_at is null) then raise exception 'Reference contribution access required' using errcode='42501'; end if;
 if p_internal is null or (p_internal and not public.lign_reference_team(c.project_id)) then raise exception 'Internal feedback requires project team access' using errcode='42501';end if;
 if p_choice is not null and p_choice not in ('shortlisted','liked','rejected') or p_note is null or length(p_note)>2000 then raise exception 'Choose a valid preference and note' using errcode='22023'; end if;
 select to_jsonb(v) into v_previous from public.reference_preferences v where card_id=c.id and user_id=auth.uid() and not v.is_internal;
 if p_choice is null then delete from public.reference_preferences where card_id=c.id and user_id=auth.uid();
 else insert into public.reference_preferences(card_id,project_id,workspace_id,user_id,choice,note,is_internal) values(c.id,c.project_id,c.workspace_id,auth.uid(),p_choice,trim(p_note),(p_internal or not exists(select 1 from public.reference_boards where id=c.board_id and shared_at is not null)))
 on conflict(card_id,user_id) do update set choice=excluded.choice,note=excluded.note,is_internal=excluded.is_internal,updated_at=now();end if;
 perform public.planning_event(c.project_id,'reference.preference_changed',c.id,case when p_internal or exists(select 1 from public.reference_boards where id=c.board_id and shared_at is null) then '{}'::jsonb else jsonb_build_object('previous',v_previous,'choice',p_choice,'note',p_note) end);end; $function$;

drop function public.add_reference_comment(uuid,text);
CREATE OR REPLACE FUNCTION public.add_reference_comment(p_card_id uuid, p_body text, p_internal boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare c public.reference_cards%rowtype;v_id uuid;begin
 select * into c from public.reference_cards where id=p_card_id for share;
 if c.id is null or not public.lign_read_reference_board(c.board_id) or c.archived_at is not null or not public.lign_reference_contributor(c.project_id) or not exists(select 1 from public.reference_boards where id=c.board_id and archived_at is null) then raise exception 'Commenting access required' using errcode='42501'; end if;
 if p_internal is null or (p_internal and not public.lign_reference_team(c.project_id)) then raise exception 'Internal feedback requires project team access' using errcode='42501';end if;
 if coalesce(length(trim(p_body)),0) not between 1 and 3000 then raise exception 'Write a comment up to 3000 characters' using errcode='22023'; end if;
 insert into public.reference_comments(card_id,project_id,workspace_id,author_id,body,is_internal) values(c.id,c.project_id,c.workspace_id,auth.uid(),trim(p_body),(p_internal or not exists(select 1 from public.reference_boards where id=c.board_id and shared_at is not null))) returning id into v_id;
 perform public.planning_event(c.project_id,'reference.commented',c.id,jsonb_build_object('comment_id',v_id));return v_id;end; $function$;

CREATE OR REPLACE FUNCTION public.set_reference_selection(p_card_id uuid, p_selected boolean, p_expected_version bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare c public.reference_cards%rowtype;begin
 select * into c from public.reference_cards where id=p_card_id for update;
 if c.id is null or not public.lign_manage_project_brief(c.project_id) then raise exception 'Project leadership chooses the agreed direction' using errcode='42501'; end if;
 if c.edit_version<>p_expected_version or c.archived_at is not null or not exists(select 1 from public.reference_boards where id=c.board_id and archived_at is null) then raise exception 'The reference changed. Reload before continuing.' using errcode='PT409'; end if;
 if p_selected and not exists(select 1 from public.reference_boards where id=c.board_id and shared_at is not null) then raise exception 'Share this board before including references in the brief' using errcode='23514';end if;
 if p_selected is null then raise exception 'Choose a selection state' using errcode='22023'; end if;
 update public.reference_cards set selected_for_brief=p_selected,edit_version=edit_version+1 where id=c.id;
 perform public.planning_event(c.project_id,'reference.selection_changed',c.id,jsonb_build_object('selected',p_selected));end; $function$;

CREATE OR REPLACE FUNCTION public.snapshot_brief_reference_selection(p_project_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v jsonb;begin
 if (select count(*) from public.reference_cards c join public.reference_boards b on b.id=c.board_id where c.project_id=p_project_id and c.selected_for_brief and c.archived_at is null and b.archived_at is null and b.shared_at is not null)>100 then raise exception 'Select at most 100 references for brief agreement' using errcode='23514'; end if;
 select coalesce(jsonb_agg(public.reference_card_snapshot(c.id) order by b.title,c.id),'[]'::jsonb) into v from public.reference_cards c join public.reference_boards b on b.id=c.board_id where c.project_id=p_project_id and c.selected_for_brief and c.archived_at is null and b.archived_at is null and b.shared_at is not null;
 if octet_length(v::text)>200000 then raise exception 'The selected reference summary is too large; reduce the selected set or notes' using errcode='23514'; end if;
 return v;end; $function$;

CREATE OR REPLACE FUNCTION public.validate_proposal_document(p_project_id uuid, p_document jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v jsonb;v_sections jsonb:='[]';v_ids text[]:='{}';v_snapshot jsonb;v_list text;v_id text;begin
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
 if v_list='referenceIds' and not exists(select 1 from public.reference_cards c join public.reference_boards b on b.id=c.board_id where c.id=v_id::uuid and c.project_id=p_project_id and c.archived_at is null and b.archived_at is null and b.shared_at is not null) then raise exception 'Choose active references in this project' using errcode='23503';end if;
 if v_list='requirementIds' and not exists(select 1 from public.requirements where id=v_id::uuid and project_id=p_project_id and status in ('draft','active')) then raise exception 'Choose draft or active requirements in this project' using errcode='23503';end if;end loop;end loop;
 return jsonb_set(p_document,'{sections}',v_sections);end; $function$;

CREATE OR REPLACE FUNCTION public.proposal_source_options(p_project_id uuid, p_kind text, p_search text DEFAULT ''::text, p_selected uuid[] DEFAULT '{}'::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v jsonb;begin
 if not public.lign_prepare_proposal(p_project_id) then raise exception 'Internal project team access required' using errcode='42501';end if;
 if p_search is null or length(p_search)>200 or p_selected is null or cardinality(p_selected)>100 then raise exception 'Invalid source search' using errcode='22023';end if;
 if p_kind='reference' then
 with options as (select c.id,c.title,b.title as context from public.reference_cards c join public.reference_boards b on b.id=c.board_id where c.project_id=p_project_id and c.archived_at is null and b.archived_at is null and b.shared_at is not null), matching as (select * from options where title ilike '%'||trim(p_search)||'%' or context ilike '%'||trim(p_search)||'%' order by title,id limit 50),picked as(select * from options where id=any(p_selected) union select * from matching)
 select coalesce(jsonb_agg(to_jsonb(p) order by p.title,p.id),'[]'::jsonb) into v from picked p;
 elsif p_kind='requirement' then
 with options as (select id,title,code||' · '||status as context from public.requirements where project_id=p_project_id and status in ('draft','active')),matching as(select * from options where title ilike '%'||trim(p_search)||'%' or context ilike '%'||trim(p_search)||'%' order by title,id limit 50),picked as(select * from options where id=any(p_selected) union select * from matching)
 select coalesce(jsonb_agg(to_jsonb(p) order by p.title,p.id),'[]'::jsonb) into v from picked p;
 else raise exception 'Choose reference or requirement sources' using errcode='22023';end if;return v;end; $function$;

CREATE OR REPLACE FUNCTION public.lign_read_planning_file(p_file_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select exists(select 1 from public.planning_files f where f.id=p_file_id and f.registered_at is not null and public.lign_has_capability(f.project_id,f.workspace_id,'project.view')
 and ((f.reference_card_id is not null and (public.lign_reference_team(f.project_id) or exists(select 1 from public.reference_cards c join public.reference_boards b on b.id=c.board_id where c.project_id=f.project_id and (c.id=f.reference_card_id or c.file_id=f.id) and b.shared_at is not null))) or (f.proposal_id is not null and public.lign_prepare_proposal(f.project_id)) or exists(select 1 from public.proposal_revisions r where r.project_id=f.project_id and public.lign_can_read_proposal_revision(r.id) and r.snapshot->'files' @> jsonb_build_array(jsonb_build_object('id',f.id))))); $function$;

CREATE OR REPLACE FUNCTION public.import_library_collection(p_collection_id uuid, p_project_id uuid, p_title text, p_area_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare b public.library_collections%rowtype;p public.projects%rowtype;v uuid;v_snapshot jsonb;begin
 select * into p from public.projects where id=p_project_id for no key update;
 select * into b from public.library_collections where id=p_collection_id for update;
 if b.id is null or b.archived_at is not null or not public.lign_is_org_member(b.organization_id) or not public.lign_manage_project_brief(p_project_id) or not exists(select 1 from public.workspaces where id=p.workspace_id and organization_id=b.organization_id) then raise exception 'Choose a library collection in the project organisation with project leadership access' using errcode='42501';end if;
 select snapshot into v_snapshot from public.library_revisions where id=b.published_revision_id;
 if v_snapshot is null or jsonb_array_length(v_snapshot->'items')=0 then raise exception 'Only approved published collections can be used in projects' using errcode='23514';end if;
 v:=public.save_reference_board(p_project_id,p_title,case when v_snapshot->>'kind' in ('template','moodboard') then 'moodboard' else 'references' end,v_snapshot->>'description',p_area_id);
 insert into public.reference_cards(board_id,project_id,workspace_id,title,description,url,library_file_id,author_id)
 select v,p.id,p.workspace_id,i->>'title',i->>'description',i->>'url',(i->>'file_id')::uuid,auth.uid() from jsonb_array_elements(v_snapshot->'items') i;
 -- File publication is deferred until the imported board is explicitly shared.
 perform public.planning_event(p.id,'library.imported',v,jsonb_build_object('collection_id',b.id,'revision_id',b.published_revision_id));return v;end; $function$;

CREATE OR REPLACE FUNCTION public.planning_event(p_project_id uuid, p_kind text, p_subject uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload)
 select workspace_id,id,'project.updated',auth.uid(),'user','project',id,name,jsonb_build_object('planning_action',p_kind,'subject_id',p_subject)||case when exists(select 1 from public.reference_boards b where b.shared_at is null and (b.id=p_subject or exists(select 1 from public.reference_cards c where c.id=p_subject and c.board_id=b.id))) then '{}'::jsonb else p_payload end from public.projects where id=p_project_id; $function$;


create or replace function public.share_reference_board(p_board_id uuid,p_expected_version bigint)
returns void language plpgsql security definer set search_path=''
as $$ declare b public.reference_boards%rowtype;begin
 select * into b from public.reference_boards where id=p_board_id for update;
 if b.id is null or not public.lign_manage_project_brief(b.project_id) then raise exception 'Project leadership required to share a board' using errcode='42501';end if;
 if b.archived_at is not null or b.edit_version is distinct from p_expected_version then raise exception 'The board changed. Reload before sharing.' using errcode='PT409';end if;
 if b.shared_at is not null then return;end if;
 update public.reference_boards set shared_at=now(),shared_by=auth.uid(),edit_version=edit_version+1 where id=b.id;
 insert into public.library_publications(file_id,project_id) select library_file_id,b.project_id from public.reference_cards where board_id=b.id and archived_at is null and library_file_id is not null on conflict do nothing;
 perform public.planning_event(b.project_id,'reference_board.shared',b.id);
end; $$;
create or replace function public.get_or_create_client_reference_board(p_project_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_ws uuid;v_id uuid;begin
 select workspace_id into v_ws from public.projects where id=p_project_id for no key update;
 if v_ws is null or not public.lign_reference_contributor(p_project_id) then raise exception 'Reference contribution access required' using errcode='42501';end if;
 select id into v_id from public.reference_boards where project_id=p_project_id and is_client_input and archived_at is null;
 if v_id is not null then return v_id;end if;
 if (select count(*) from public.reference_boards where project_id=p_project_id and archived_at is null)>=100 then raise exception 'Use at most 100 active boards per project' using errcode='23514';end if;
 insert into public.reference_boards(project_id,workspace_id,title,kind,description,created_by,shared_at,shared_by,is_client_input)
 values(p_project_id,v_ws,'Client suggestions','references','Add your own examples and explain which colours, layout, materials or details you have in mind.',auth.uid(),now(),auth.uid(),true) returning id into v_id;
 perform public.planning_event(p_project_id,'reference_board.client_input_opened',v_id);return v_id;
end; $$;
revoke all on function public.lign_reference_team(uuid),public.lign_read_reference_board(uuid),public.share_reference_board(uuid,bigint),public.get_or_create_client_reference_board(uuid) from public,anon,authenticated;
grant execute on function public.lign_reference_team(uuid),public.lign_read_reference_board(uuid),public.share_reference_board(uuid,bigint),public.get_or_create_client_reference_board(uuid) to authenticated,service_role;

create or replace function public.get_reference_direction(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v_ws uuid;begin
 select workspace_id into v_ws from public.projects where id=p_project_id;
 if v_ws is null or not public.lign_has_capability(p_project_id,v_ws,'project.view') then raise exception 'Project access required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(public.reference_card_snapshot(c.id)||jsonb_build_object('canEdit',false) order by b.title,c.id),'[]'::jsonb)
 from public.reference_cards c join public.reference_boards b on b.id=c.board_id where c.project_id=p_project_id and c.selected_for_brief and c.archived_at is null and b.archived_at is null and b.shared_at is not null);
end; $$;
revoke all on function public.get_reference_direction(uuid) from public,anon,authenticated;
grant execute on function public.get_reference_direction(uuid) to authenticated,service_role;

revoke all on function public.set_reference_preference(uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function public.set_reference_preference(uuid,text,text,boolean) to authenticated,service_role;

revoke all on function public.add_reference_comment(uuid,text,boolean) from public,anon,authenticated;
grant execute on function public.add_reference_comment(uuid,text,boolean) to authenticated,service_role;
