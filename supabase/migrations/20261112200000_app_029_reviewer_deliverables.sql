-- APP 029: professional labels and narrowly scoped reviewer submissions.
-- Existing project role presets and creative capabilities remain unchanged.
alter table public.project_participants
 add column professional_label text not null default '' check(length(professional_label)<=80),
 add column can_submit_deliverables boolean not null default false;

create or replace function public.reset_reviewer_submission_permission()
returns trigger language plpgsql set search_path=''
as $$ begin
 if new.role<>'reviewer' or new.status<>'active' then new.can_submit_deliverables:=false; end if;
 return new;
end; $$;
create trigger project_participants_submission_permission before insert or update on public.project_participants
 for each row execute function public.reset_reviewer_submission_permission();

create or replace function public.set_project_participant_access(p_participant_id uuid,p_professional_label text,p_can_submit boolean)
returns void language plpgsql security definer set search_path=''
as $$
declare v_p public.project_participants%rowtype; v_label text:=trim(coalesce(p_professional_label,''));
begin
 select * into v_p from public.project_participants where id=p_participant_id for update;
 if v_p.id is null or not public.lign_has_capability(v_p.project_id,v_p.workspace_id,'project.manage_access') then
  raise exception 'Project or workspace leadership required' using errcode='42501'; end if;
 if length(v_label)>80 or v_label ~ '[[:cntrl:]]' then raise exception 'Professional labels must be 80 characters or fewer on one line' using errcode='22023'; end if;
 if coalesce(p_can_submit,false) and (v_p.role<>'reviewer' or v_p.status<>'active') then
  raise exception 'Only active reviewers can receive the additional submission permission' using errcode='23514'; end if;
 update public.project_participants set professional_label=v_label,can_submit_deliverables=coalesce(p_can_submit,false) where id=v_p.id;
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload)
 values(v_p.workspace_id,v_p.project_id,'project.participant.access_updated',auth.uid(),'user','project_participant',v_p.id,v_label,jsonb_build_object('can_submit_deliverables',coalesce(p_can_submit,false)));
end; $$;

-- Atomic invitation + access metadata; preserve the established invitation RPC.
create or replace function public.invite_project_participant(
 p_workspace_id uuid,p_email text,p_project_id uuid,p_role text default 'reviewer',
 p_display_name text default null,p_professional_label text default '',p_can_submit boolean default false
)
returns table(out_invitation_id uuid,out_stakeholder_id uuid,out_token text,out_expires_at timestamptz)
language plpgsql security definer set search_path=''
as $$
declare v_i record; v_p public.project_participants%rowtype;
begin
 select * into v_i from public.invite_stakeholder(p_workspace_id,p_email,p_project_id,p_role,p_display_name,14);
 select * into v_p from public.project_participants where project_id=p_project_id and stakeholder_id=v_i.out_stakeholder_id and status='active';
 if v_p.role is distinct from p_role then raise exception 'This person already has a different project role. Update it through Project people.' using errcode='23514'; end if;
 perform public.set_project_participant_access(v_p.id,p_professional_label,p_can_submit);
 return query select v_i.out_invitation_id,v_i.out_stakeholder_id,v_i.out_token,v_i.out_expires_at;
end; $$;

create table public.deliverable_submissions (
 id uuid primary key default gen_random_uuid(),project_id uuid not null,workspace_id uuid not null,
 asset_id uuid not null,asset_version_id uuid not null unique,
 author_id uuid not null references public.profiles(id),participant_id uuid not null references public.project_participants(id),
 professional_label text not null default '',title text not null check(length(trim(title)) between 1 and 200),
 notes text not null default '' check(length(notes)<=5000),
 stage text not null default 'draft' check(stage in ('draft','submitted','changes_requested','accepted','published','withdrawn')),
 parent_submission_id uuid unique references public.deliverable_submissions(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(project_id,workspace_id) references public.projects(id,workspace_id),
 foreign key(asset_id,project_id,workspace_id) references public.design_assets(id,project_id,workspace_id),
 foreign key(asset_version_id,asset_id) references public.asset_versions(id,design_asset_id),
 unique(id,project_id,workspace_id)
);
create index deliverable_submissions_project_idx on public.deliverable_submissions(project_id,created_at desc);
create table public.deliverable_submission_events (
 id uuid primary key default gen_random_uuid(),submission_id uuid not null,project_id uuid not null,workspace_id uuid not null,
 actor_id uuid not null references public.profiles(id),action text not null,note text not null default '',
 created_at timestamptz not null default now(),
 foreign key(submission_id,project_id,workspace_id) references public.deliverable_submissions(id,project_id,workspace_id)
);
create index deliverable_submission_events_submission_idx on public.deliverable_submission_events(submission_id,created_at);
create table public.deliverable_upload_reservations (
 asset_version_id uuid not null references public.asset_versions(id),file_id uuid not null references public.files(id),
 uploader_id uuid not null references public.profiles(id),created_at timestamptz not null default now(),
 primary key(asset_version_id,file_id,uploader_id)
);
alter table public.deliverable_submissions enable row level security;
alter table public.deliverable_submission_events enable row level security;
alter table public.deliverable_upload_reservations enable row level security;
create policy deliverable_submissions_read on public.deliverable_submissions for select to authenticated
 using(public.lign_has_capability(project_id,workspace_id,'project.view'));
create policy deliverable_submission_events_read on public.deliverable_submission_events for select to authenticated
 using(public.lign_has_capability(project_id,workspace_id,'project.view'));
revoke all on public.deliverable_submissions,public.deliverable_submission_events,public.deliverable_upload_reservations from anon,authenticated;
grant select on public.deliverable_submissions,public.deliverable_submission_events to authenticated;

create or replace function public.lign_can_submit_deliverables(p_project_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.project_participants pp
 join public.projects p on p.id=pp.project_id
 left join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
 left join public.stakeholders s on s.id=pp.stakeholder_id and s.status='active'
 where pp.project_id=p_project_id and pp.role='reviewer' and pp.status='active' and pp.can_submit_deliverables
 and coalesce(wm.user_id,s.user_id)=auth.uid() and p.archived_at is null and p.status<>'archived'); $$;

create or replace function public.lign_edit_deliverable_version(p_version_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.deliverable_submissions s join public.asset_versions v on v.id=s.asset_version_id
 where v.id=p_version_id and v.status='draft' and s.stage='draft' and s.author_id=auth.uid()
 and public.lign_can_submit_deliverables(s.project_id)); $$;

create or replace function public.get_deliverable_submissions(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_ws uuid;
begin
 select workspace_id into v_ws from public.projects where id=p_project_id;
 if v_ws is null or not public.lign_has_capability(p_project_id,v_ws,'project.view') then raise exception 'Project access required' using errcode='42501'; end if;
 return jsonb_build_object('canSubmit',public.lign_can_submit_deliverables(p_project_id),
  'canReview',public.lign_has_capability(p_project_id,v_ws,'version.publish') and exists(select 1 from public.projects where id=p_project_id and archived_at is null and status<>'archived'),
  'assets',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.name) order by a.name),'[]'::jsonb) from public.design_assets a where a.project_id=p_project_id and a.archived_at is null and a.status<>'archived'),
  'submissions',(select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('authorName',p.display_name,'versionSequence',v.sequence,'versionStatus',v.status,'isCurrent',coalesce((select a.current_version_id=s.asset_version_id from public.design_assets a where a.id=s.asset_id),false),
   'childId',(select id from public.deliverable_submissions child where child.parent_submission_id=s.id),
   'events',(select coalesce(jsonb_agg(to_jsonb(e)||jsonb_build_object('actorName',ep.display_name) order by e.created_at),'[]'::jsonb) from public.deliverable_submission_events e join public.profiles ep on ep.id=e.actor_id where e.submission_id=s.id)) order by s.created_at desc),'[]'::jsonb)
   from public.deliverable_submissions s join public.profiles p on p.id=s.author_id join public.asset_versions v on v.id=s.asset_version_id where s.project_id=p_project_id));
end; $$;

create or replace function public.create_deliverable_submission(p_project_id uuid,p_title text,p_notes text default '',p_asset_id uuid default null,p_parent_id uuid default null)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_ws uuid;v_pp public.project_participants%rowtype;v_asset uuid:=p_asset_id;v_version uuid;v_id uuid;v_sequence integer;v_parent public.deliverable_submissions%rowtype;
begin
 if not public.lign_can_submit_deliverables(p_project_id) then raise exception 'Reviewer submission permission required' using errcode='42501'; end if;
 if coalesce(length(trim(p_title)),0) not between 1 and 200 or length(coalesce(p_notes,''))>5000 then raise exception 'Add a title of up to 200 characters and notes of up to 5000 characters' using errcode='22023'; end if;
 select workspace_id into v_ws from public.projects where id=p_project_id for no key update;
 select pp.* into v_pp from public.project_participants pp
 left join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
 left join public.stakeholders sh on sh.id=pp.stakeholder_id and sh.status='active'
 where pp.project_id=p_project_id and pp.status='active' and pp.role='reviewer' and pp.can_submit_deliverables and coalesce(wm.user_id,sh.user_id)=auth.uid();
 if v_pp.id is null then raise exception 'Reviewer submission permission required' using errcode='42501'; end if;
 if p_parent_id is not null then
  select * into v_parent from public.deliverable_submissions where id=p_parent_id and project_id=p_project_id for update;
  if v_parent.id is null or v_parent.author_id<>auth.uid() or v_parent.stage<>'changes_requested' then raise exception 'Revise your own submission after changes are requested' using errcode='42501'; end if;
  select id into v_id from public.deliverable_submissions where parent_submission_id=p_parent_id;
  if v_id is not null then return v_id; end if;
  v_asset:=v_parent.asset_id;
 end if;
 if v_asset is null then
  insert into public.design_assets(workspace_id,project_id,name,description,created_by_profile_id) values(v_ws,p_project_id,trim(p_title),nullif(trim(p_notes),''),auth.uid()) returning id into v_asset;
 else
  perform 1 from public.design_assets where id=v_asset and project_id=p_project_id and archived_at is null and status<>'archived' for no key update;
  if not found then raise exception 'Choose a design asset in this active project' using errcode='23514'; end if;
 end if;
 select coalesce(max(sequence),0)+1 into v_sequence from public.asset_versions where design_asset_id=v_asset;
 insert into public.asset_versions(workspace_id,project_id,design_asset_id,sequence,label,notes)
 values(v_ws,p_project_id,v_asset,v_sequence,'Reviewer submission',coalesce(p_notes,'')) returning id into v_version;
 insert into public.deliverable_submissions(project_id,workspace_id,asset_id,asset_version_id,author_id,participant_id,professional_label,title,notes,parent_submission_id)
 values(p_project_id,v_ws,v_asset,v_version,auth.uid(),v_pp.id,v_pp.professional_label,trim(p_title),coalesce(p_notes,''),p_parent_id) returning id into v_id;
 insert into public.deliverable_submission_events(submission_id,project_id,workspace_id,actor_id,action,note) values(v_id,p_project_id,v_ws,auth.uid(),'created',coalesce(p_notes,''));
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label)
 values(v_ws,p_project_id,'deliverable.created',auth.uid(),'user','asset_version',v_version,trim(p_title));
 return v_id;
end; $$;

create or replace function public.transition_deliverable_submission(p_submission_id uuid,p_action text,p_note text default '')
returns void language plpgsql security definer set search_path=''
as $$
declare v_s public.deliverable_submissions%rowtype;v_version uuid;v_stage text;
begin
 select asset_version_id into v_version from public.deliverable_submissions where id=p_submission_id;
 perform 1 from public.asset_versions where id=v_version for update;
 select * into v_s from public.deliverable_submissions where id=p_submission_id for update;
 if v_s.id is null or not public.lign_has_capability(v_s.project_id,v_s.workspace_id,'project.view') then raise exception 'Project access required' using errcode='42501'; end if;
 if length(coalesce(p_note,''))>5000 then raise exception 'Keep notes to 5000 characters' using errcode='22023'; end if;
 if not exists(select 1 from public.projects where id=v_s.project_id and archived_at is null and status<>'archived') then raise exception 'Archived projects cannot receive submission changes' using errcode='23514'; end if;
 if p_action='submit' then
  if not public.lign_edit_deliverable_version(v_version) then raise exception 'Only the permitted author can submit their draft' using errcode='42501'; end if;
  if not exists(select 1 from public.version_files vf join public.files f on f.id=vf.file_id where vf.asset_version_id=v_version and f.status='active') then raise exception 'Upload at least one completed file before submitting' using errcode='23514'; end if;
  v_stage:='submitted';
 elsif p_action in ('accept','request_changes') then
  if not public.lign_has_capability(v_s.project_id,v_s.workspace_id,'version.publish') or auth.uid()=v_s.author_id then raise exception 'Another project lead or contributor must review this submission' using errcode='42501'; end if;
  if v_s.stage<>'submitted' then raise exception 'This submission is no longer awaiting review' using errcode='PT409'; end if;
  if p_action='request_changes' and trim(coalesce(p_note,''))='' then raise exception 'Describe the changes requested' using errcode='22023'; end if;
  v_stage:=case p_action when 'accept' then 'accepted' else 'changes_requested' end;
 elsif p_action='withdraw' then
  if v_s.author_id<>auth.uid() or not public.lign_can_submit_deliverables(v_s.project_id) then raise exception 'Only the permitted author can withdraw this submission' using errcode='42501'; end if;
  if v_s.stage not in ('draft','submitted') then raise exception 'This submission can no longer be withdrawn' using errcode='PT409'; end if;
  v_stage:='withdrawn';
 else raise exception 'Unknown submission action' using errcode='22023'; end if;
 update public.deliverable_submissions set stage=v_stage,updated_at=now() where id=v_s.id;
 insert into public.deliverable_submission_events(submission_id,project_id,workspace_id,actor_id,action,note) values(v_s.id,v_s.project_id,v_s.workspace_id,auth.uid(),v_stage,coalesce(p_note,''));
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload)
 values(v_s.workspace_id,v_s.project_id,'deliverable.'||v_stage,auth.uid(),'user','asset_version',v_version,v_s.title,jsonb_build_object('note',coalesce(p_note,'')));
end; $$;

create or replace function public.guard_deliverable_files()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_version uuid;v_stage text;
begin
 for v_version in select distinct x from unnest(case when tg_op='INSERT' then array[new.asset_version_id] when tg_op='DELETE' then array[old.asset_version_id] else array[old.asset_version_id,new.asset_version_id] end) x loop
  perform 1 from public.asset_versions where id=v_version for update;
  select stage into v_stage from public.deliverable_submissions where asset_version_id=v_version;
  if found and (v_stage<>'draft' or exists(select 1 from public.deliverable_submissions s join public.projects p on p.id=s.project_id where s.asset_version_id=v_version and (p.archived_at is not null or p.status='archived'))) then raise exception 'Submitted deliverable files are frozen. Create a revised submission after review.' using errcode='23514'; end if;
 end loop;
 if tg_op='DELETE' then return old; end if;return new;
end; $$;
create trigger version_files_deliverable_guard before insert or update or delete on public.version_files for each row execute function public.guard_deliverable_files();

create or replace function public.guard_deliverable_version()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_s public.deliverable_submissions%rowtype;
begin
 select * into v_s from public.deliverable_submissions where asset_version_id=old.id for update;
 if not found then if tg_op='DELETE' then return old; end if;return new;end if;
 if tg_op='DELETE' then raise exception 'Submission versions are retained in project history' using errcode='23514'; end if;
 if new.status='published' and old.status='draft' then
  if not exists(select 1 from public.projects where id=v_s.project_id and archived_at is null and status<>'archived') then raise exception 'Archived projects cannot publish submissions' using errcode='23514'; end if;
  if v_s.stage<>'accepted' then raise exception 'Accept the submitted deliverable before publishing its version' using errcode='23514'; end if;
  if not public.lign_has_capability(v_s.project_id,v_s.workspace_id,'version.publish') then raise exception 'Project publishing permission required' using errcode='42501'; end if;
 elsif old.status='draft' and v_s.stage<>'draft' and (to_jsonb(new)-'updated_at') is distinct from (to_jsonb(old)-'updated_at') then
  raise exception 'Reviewed submission versions are frozen' using errcode='23514';
 end if;
 return new;
end; $$;
create trigger asset_versions_deliverable_guard before update or delete on public.asset_versions for each row execute function public.guard_deliverable_version();

create or replace function public.record_deliverable_publication()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_s public.deliverable_submissions%rowtype;
begin
 if new.status='published' and old.status='draft' then
  update public.deliverable_submissions set stage='published',updated_at=now() where asset_version_id=new.id returning * into v_s;
  if found then insert into public.deliverable_submission_events(submission_id,project_id,workspace_id,actor_id,action) values(v_s.id,v_s.project_id,v_s.workspace_id,auth.uid(),'published'); end if;
 end if;
 return new;
end; $$;
create trigger asset_versions_deliverable_published after update of status on public.asset_versions for each row execute function public.record_deliverable_publication();

create or replace function public.remove_deliverable_file(p_submission_id uuid,p_version_file_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare v_version uuid;v_file uuid;
begin
 select asset_version_id into v_version from public.deliverable_submissions where id=p_submission_id;
 perform 1 from public.asset_versions where id=v_version for update;
 if not public.lign_edit_deliverable_version(v_version) then raise exception 'Only the permitted author can edit this submission draft' using errcode='42501'; end if;
 delete from public.version_files where id=p_version_file_id and asset_version_id=v_version returning file_id into v_file;
 if v_file is not null and not exists(select 1 from public.version_files where file_id=v_file) then
  update public.files set status='orphaned',orphaned_at=now() where id=v_file and status='active';
 end if;
end; $$;

revoke all on function public.reset_reviewer_submission_permission(),public.guard_deliverable_files(),public.guard_deliverable_version(),public.record_deliverable_publication() from public,anon,authenticated;
revoke all on function public.set_project_participant_access(uuid,text,boolean),public.invite_project_participant(uuid,text,uuid,text,text,text,boolean),public.lign_can_submit_deliverables(uuid),public.lign_edit_deliverable_version(uuid),public.get_deliverable_submissions(uuid),public.create_deliverable_submission(uuid,text,text,uuid,uuid),public.transition_deliverable_submission(uuid,text,text),public.remove_deliverable_file(uuid,uuid) from public,anon;
grant execute on function public.set_project_participant_access(uuid,text,boolean),public.invite_project_participant(uuid,text,uuid,text,text,text,boolean),public.lign_can_submit_deliverables(uuid),public.lign_edit_deliverable_version(uuid),public.get_deliverable_submissions(uuid),public.create_deliverable_submission(uuid,text,text,uuid,uuid),public.transition_deliverable_submission(uuid,text,text),public.remove_deliverable_file(uuid,uuid) to authenticated;



-- Keep external submission checksums out of the team's ordinary deduplication
-- namespace. Untrusted claimed checksums must not shadow later team uploads.
alter table public.files add column submission_scope_id uuid references public.deliverable_submissions(id);
drop index public.files_workspace_checksum_key;
create unique index files_workspace_checksum_key on public.files(workspace_id,checksum_sha256)
 where status<>'purged' and purge_reserved_at is null and submission_scope_id is null;
create unique index files_submission_checksum_key on public.files(submission_scope_id,checksum_sha256)
 where status<>'purged' and purge_reserved_at is null and submission_scope_id is not null;

create or replace function public.start_deliverable_file_upload(p_version_id uuid,p_checksum_hex text,p_mime_type text,p_size_bytes bigint)
returns table(out_file_id uuid,out_action text,out_bucket text,out_object_path text,out_size_bytes bigint,out_mime_type text)
language plpgsql security definer set search_path=''
as $$
declare v_s public.deliverable_submissions%rowtype;v_f public.files%rowtype;v_id uuid;v_path text;v_action text;v_checksum bytea:=decode(p_checksum_hex,'hex');
begin
 select * into v_s from public.deliverable_submissions where asset_version_id=p_version_id;
 if v_s.id is null or not exists(select 1 from public.projects where id=v_s.project_id and archived_at is null and status<>'archived') or v_s.stage<>'draft' or not (public.lign_edit_deliverable_version(p_version_id)
  or (public.lign_has_capability(v_s.project_id,v_s.workspace_id,'version.upload') and public.lign_has_capability(v_s.project_id,v_s.workspace_id,'file.attach'))) then
  raise exception 'An editable submission draft is required' using errcode='42501'; end if;
 v_id:=gen_random_uuid();v_path:=v_s.workspace_id::text||'/'||v_id::text;
 insert into public.files(id,workspace_id,checksum_sha256,mime_type,size_bytes,storage_ref,uploaded_by_profile_id,status,submission_scope_id)
 values(v_id,v_s.workspace_id,v_checksum,p_mime_type,p_size_bytes,v_path,auth.uid(),'uploaded',v_s.id)
 on conflict(submission_scope_id,checksum_sha256) where status<>'purged' and purge_reserved_at is null and submission_scope_id is not null do nothing
 returning * into v_f;
 if v_f.id is not null then v_action:='upload_required';
 else
  select * into v_f from public.files where submission_scope_id=v_s.id and checksum_sha256=v_checksum and status<>'purged' and purge_reserved_at is null for update;
  if v_f.size_bytes<>p_size_bytes then raise exception 'Checksum and size do not match the existing submission file' using errcode='23514'; end if;
  if v_f.status='active' then v_action:='reused';
  elsif v_f.status='uploaded' and v_f.uploaded_by_profile_id=auth.uid() then v_action:='upload_required';
  elsif v_f.status='uploaded' then v_action:='in_progress';
  elsif v_f.status='orphaned' then
   update public.files set status='uploaded',orphaned_at=null,uploaded_by_profile_id=auth.uid() where id=v_f.id;
   v_action:='reclaimed';
  else raise exception 'This file is unavailable' using errcode='23514'; end if;
 end if;
 insert into public.deliverable_upload_reservations(asset_version_id,file_id,uploader_id) values(p_version_id,v_f.id,auth.uid()) on conflict do nothing;
 return query select v_f.id,v_action,'lign-files'::text,v_f.storage_ref,v_f.size_bytes,v_f.mime_type;
end; $$;
revoke all on function public.start_deliverable_file_upload(uuid,text,text,bigint) from public,anon,authenticated;

-- Extend upload authorization only for the caller's editable submission.
-- Record each file/version reservation to prevent arbitrary file-ID attachment.
create or replace function public.start_version_file_upload(
  p_asset_version_id uuid,
  p_checksum_hex     text,
  p_mime_type        text,
  p_size_bytes       bigint
)
returns table (
  out_file_id     uuid,
  out_action      text,
  out_bucket      text,
  out_object_path text,
  out_size_bytes  bigint,
  out_mime_type   text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller            uuid;
  v_workspace_id      uuid;
  v_project_id        uuid;
  v_version_status    text;
  v_checksum          bytea;
  v_new_file_id       uuid;
  v_new_storage_ref   text;
  v_existing_id       uuid;
  v_existing_status   text;
  v_existing_uploader uuid;
  v_existing_ref      text;
  v_action            text;
  v_return_file_id    uuid;
  v_return_ref        text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'start_version_file_upload: authentication required' using errcode='42501'; end if;
  if p_asset_version_id is null then raise exception 'start_version_file_upload: asset_version_id required' using errcode='22004'; end if;
  if p_checksum_hex is null or length(p_checksum_hex) <> 64 then raise exception 'start_version_file_upload: checksum_hex must be 64-char sha256 hex' using errcode='22023'; end if;
  if p_mime_type is null or length(trim(p_mime_type))=0 then raise exception 'start_version_file_upload: mime_type required' using errcode='22004'; end if;
  if p_size_bytes is null or p_size_bytes <= 0 then raise exception 'start_version_file_upload: size_bytes must be > 0' using errcode='22023'; end if;
  if p_size_bytes > 500 * 1024 * 1024 then raise exception 'start_version_file_upload: size_bytes exceeds 500 MB limit' using errcode='22023'; end if;
  if lower(trim(p_mime_type)) = any (array[
    'application/x-msdownload','application/x-msdos-program',
    'application/x-executable','application/x-sh',
    'application/x-shellscript','text/x-shellscript'
  ]) then raise exception 'start_version_file_upload: mime_type % is denied', p_mime_type using errcode='22023'; end if;

  select workspace_id, project_id, status into v_workspace_id, v_project_id, v_version_status
    from public.asset_versions where id = p_asset_version_id for update;
  if v_workspace_id is null then raise exception 'start_version_file_upload: asset_version not found' using errcode='23503'; end if;
  if v_version_status <> 'draft' then raise exception 'start_version_file_upload: version is % (must be draft)', v_version_status using errcode='23514'; end if;

  if not (
        public.lign_has_capability(v_project_id, v_workspace_id, 'version.upload')
    and public.lign_has_capability(v_project_id, v_workspace_id, 'file.attach')
  ) and not public.lign_edit_deliverable_version(p_asset_version_id) then raise exception 'start_version_file_upload: forbidden (version.upload + file.attach)' using errcode='42501'; end if;

  if exists(select 1 from public.deliverable_submissions where asset_version_id=p_asset_version_id) then
    return query select * from public.start_deliverable_file_upload(p_asset_version_id,p_checksum_hex,p_mime_type,p_size_bytes);
    return;
  end if;

  v_checksum := decode(p_checksum_hex, 'hex');
  v_new_file_id := gen_random_uuid();
  v_new_storage_ref := v_workspace_id::text || '/' || v_new_file_id::text;

  insert into public.files (
    id, workspace_id, checksum_sha256, mime_type, size_bytes,
    storage_ref, uploaded_by_profile_id, status
  ) values (
    v_new_file_id, v_workspace_id, v_checksum, p_mime_type, p_size_bytes,
    v_new_storage_ref, v_caller, 'uploaded'
  )
  on conflict (workspace_id, checksum_sha256)
    where status <> 'purged' and purge_reserved_at is null and submission_scope_id is null
    do nothing
  returning id, storage_ref into v_return_file_id, v_return_ref;

  if v_return_file_id is not null then
    v_action := 'upload_required';
  else
    select id, status, uploaded_by_profile_id, storage_ref
      into v_existing_id, v_existing_status, v_existing_uploader, v_existing_ref
      from public.files
     where workspace_id = v_workspace_id
       and checksum_sha256 = v_checksum
       and submission_scope_id is null
       and status <> 'purged'
       and purge_reserved_at is null
     for update;

    if v_existing_status = 'active' then v_action := 'reused';
    elsif v_existing_status = 'uploaded' then
      if v_existing_uploader = v_caller then v_action := 'upload_required';
      else v_action := 'in_progress'; end if;
    elsif v_existing_status = 'orphaned' then
      update public.files
         set status='uploaded', orphaned_at=null, uploaded_by_profile_id=v_caller
       where id = v_existing_id;
      v_action := 'reclaimed';
    else raise exception 'start_version_file_upload: unexpected existing file status %', v_existing_status using errcode='XX000'; end if;

    v_return_file_id := v_existing_id;
    v_return_ref     := v_existing_ref;
  end if;

  return query select v_return_file_id, v_action, 'lign-files'::text, v_return_ref, p_size_bytes, p_mime_type;
end $$;

create or replace function public.finalize_version_file_upload(
  p_file_id          uuid,
  p_asset_version_id uuid,
  p_display_name     text default null,
  p_role             text default 'primary',
  p_sort_order       integer default null
)
returns table (
  out_file_id          uuid,
  out_version_files_id uuid,
  out_action           text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller           uuid;
  v_f_workspace_id   uuid;
  v_f_status         text;
  v_f_size_bytes     bigint;
  v_f_storage_ref    text;
  v_v_workspace_id   uuid;
  v_v_project_id     uuid;
  v_v_status         text;
  v_expected_ref     text;
  v_object_metadata  jsonb;
  v_object_size      bigint;
  v_vf_id            uuid;
  v_sort             integer;
  v_action           text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'finalize_version_file_upload: authentication required' using errcode='42501';
  end if;
  if p_file_id is null or p_asset_version_id is null then
    raise exception 'finalize_version_file_upload: file_id and asset_version_id required' using errcode='22004';
  end if;
  if p_role is null or p_role not in ('primary','reference','spec','source','export','other') then
    raise exception 'finalize_version_file_upload: invalid role %', coalesce(p_role,'(null)') using errcode='22023';
  end if;

  select workspace_id, project_id, status
    into v_v_workspace_id, v_v_project_id, v_v_status
    from public.asset_versions where id = p_asset_version_id for update;
  if v_v_workspace_id is null then
    raise exception 'finalize_version_file_upload: asset_version % not found', p_asset_version_id using errcode='23503';
  end if;
  if v_v_status <> 'draft' then
    raise exception 'finalize_version_file_upload: version is % (must be draft)', v_v_status using errcode='23514';
  end if;


  select workspace_id, status, size_bytes, storage_ref
    into v_f_workspace_id, v_f_status, v_f_size_bytes, v_f_storage_ref
    from public.files where id = p_file_id for update;
  if v_f_workspace_id is null then
    raise exception 'finalize_version_file_upload: file % not found', p_file_id using errcode='23503';
  end if;
  if v_f_status not in ('uploaded','active') then
    raise exception 'finalize_version_file_upload: file % is % (must be uploaded or active)', p_file_id, v_f_status using errcode='23514';
  end if;


  if v_f_workspace_id <> v_v_workspace_id then
    raise exception 'finalize_version_file_upload: file/version workspace mismatch' using errcode='23514';
  end if;

  if not (
        public.lign_has_capability(v_v_project_id, v_v_workspace_id, 'version.upload')
    and public.lign_has_capability(v_v_project_id, v_v_workspace_id, 'file.attach')
  ) and not (public.lign_edit_deliverable_version(p_asset_version_id) and exists(
    select 1 from public.deliverable_upload_reservations r where r.asset_version_id=p_asset_version_id and r.file_id=p_file_id and r.uploader_id=v_caller
  )) then
    raise exception 'finalize_version_file_upload: forbidden (version.upload + file.attach)' using errcode='42501';
  end if;

  v_expected_ref := v_f_workspace_id::text || '/' || p_file_id::text;
  if v_f_storage_ref is distinct from v_expected_ref then
    raise exception 'finalize_version_file_upload: storage_ref % does not match canonical form', v_f_storage_ref using errcode='23514';
  end if;

  select metadata into v_object_metadata
    from storage.objects
   where bucket_id = 'lign-files' and name = v_expected_ref;
  if not found then
    raise exception 'finalize_version_file_upload: storage object missing at % (upload not completed)', v_expected_ref using errcode='23514';
  end if;

  v_object_size := nullif(v_object_metadata->>'size','')::bigint;
  if v_object_size is not null and v_object_size <> v_f_size_bytes then
    raise exception 'finalize_version_file_upload: storage object size % does not match declared %', v_object_size, v_f_size_bytes using errcode='23514';
  end if;

  if v_f_status = 'uploaded' then
    update public.files set status = 'active' where id = p_file_id;
  end if;

  if p_sort_order is not null then
    v_sort := p_sort_order;
  else
    select coalesce(max(sort_order),-1)+1 into v_sort
      from public.version_files where asset_version_id = p_asset_version_id;
  end if;

  insert into public.version_files (
    workspace_id, asset_version_id, file_id, display_name, role, sort_order
  ) values (
    v_v_workspace_id, p_asset_version_id, p_file_id, p_display_name, p_role, v_sort
  )
  on conflict (asset_version_id, file_id) do nothing
  returning id into v_vf_id;

  if v_vf_id is null then
    select id into v_vf_id from public.version_files
     where asset_version_id = p_asset_version_id and file_id = p_file_id;
    v_action := 'already_attached';
  else
    v_action := 'attached';
    insert into public.activity_events (
      workspace_id, project_id, occurred_at, event_type,
      actor_profile_id, actor_kind,
      subject_kind, subject_id, subject_label, subject_snapshot, payload
    ) values (
      v_v_workspace_id, v_v_project_id, now(), 'file.attached',
      v_caller, 'user',
      'version_file', v_vf_id, coalesce(p_display_name, ''),
      jsonb_build_object('file_id', p_file_id, 'asset_version_id', p_asset_version_id, 'role', p_role),
      '{}'::jsonb
    );
  end if;

  return query select p_file_id, v_vf_id, v_action;
end $$;

create or replace function public.lign_can_upload_storage_object(p_object_name text)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.files f where f.storage_ref=p_object_name and f.status='uploaded' and f.uploaded_by_profile_id=auth.uid()
 and (f.submission_scope_id is null or exists(select 1 from public.deliverable_submissions s where s.id=f.submission_scope_id and s.stage='draft'
 and (public.lign_edit_deliverable_version(s.asset_version_id) or (public.lign_has_capability(s.project_id,s.workspace_id,'version.upload') and public.lign_has_capability(s.project_id,s.workspace_id,'file.attach')))))); $$;


-- Include the scoped professional label and extra permission in leadership views.
create or replace function public.get_access_directory(
 p_organization_id uuid default null, p_workspace_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = ''
as $fn$
declare v_org uuid; v_result jsonb;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_workspace_id is not null then
  select organization_id into v_org from public.workspaces where id=p_workspace_id;
  if v_org is null or not public.lign_is_workspace_admin(p_workspace_id)
    or (p_organization_id is not null and p_organization_id<>v_org) then
   raise exception 'Workspace leadership required' using errcode='42501';
  end if;
 else
  v_org := p_organization_id;
  if v_org is null or not public.lign_is_org_admin(v_org) then
   raise exception 'Studio leadership required' using errcode='42501';
  end if;
 end if;

 with ws as materialized (
  select id,name,status from public.workspaces
   where organization_id=v_org and (p_workspace_id is null or id=p_workspace_id)
 ), org_people as materialized (
  select om.user_id,om.role,om.status,p.display_name,p.email
   from public.organization_members om join public.profiles p on p.id=om.user_id
   where om.organization_id=v_org
 ), members as materialized (
  select wm.id,wm.workspace_id,wm.user_id,wm.role,wm.status,p.display_name,p.email
   from public.workspace_members wm join ws on ws.id=wm.workspace_id
   join public.profiles p on p.id=wm.user_id where wm.status<>'removed'
 ), external_identities as materialized (
  select lower(s.email::text) email_key,min(s.user_id::text) user_key
   from public.stakeholders s join ws on ws.id=s.workspace_id
   where s.status<>'revoked' and s.user_id is not null group by lower(s.email::text)
 ), external_people as materialized (
  select s.*,coalesce(s.user_id::text,
    (select o.user_id::text from org_people o where lower(o.email::text)=lower(s.email::text)),
    (select e.user_key from external_identities e where e.email_key=lower(s.email::text)),
    'email:'||lower(s.email::text)) person_key
   from public.stakeholders s join ws on ws.id=s.workspace_id where s.status<>'revoked'
 ), identities as (
  select user_id::text person_key,user_id,display_name,email::text email,0 priority
   from org_people where status<>'removed' and
    (p_workspace_id is null or (status='active' and role in ('owner','admin')))
  union all
  select user_id::text,user_id,display_name,email::text,1 from members
  union all
  select person_key,user_id,coalesce(display_name,email::text),email::text,2 from external_people
 ), people as (
  select distinct on (person_key) person_key,user_id,display_name,email from identities
   order by person_key,priority,email,display_name
 ), project_roles as materialized (
  select pp.id,pp.role,pp.professional_label,pp.can_submit_deliverables,pr.id project_id,pr.name project_name,pr.status project_status,
   pr.archived_at,pr.workspace_id,
   coalesce(m.user_id::text,s.person_key) person_key,
   case when s.id is not null then 'external' else 'internal' end source,
   coalesce(s.id,m.id) source_id,
   case when s.id is not null and (s.user_id is null or s.status='invited') then 'invited' else 'active' end status
   from public.project_participants pp join public.projects pr on pr.id=pp.project_id
   join ws on ws.id=pr.workspace_id
   left join members m on m.id=pp.workspace_member_id and m.status='active'
   left join external_people s on s.id=pp.stakeholder_id
   where pp.status='active' and (m.id is not null or s.id is not null)
 ), invitations as (
  select i.id,i.email::text email,'organization' scope,null::uuid workspace_id,
   i.role,i.expires_at from public.organization_invitations i
   where i.organization_id=v_org and p_workspace_id is null and i.status='sent' and i.expires_at>now()
  union all
  select i.id,i.email::text,case when i.kind='stakeholder' then 'external' else 'workspace' end,
   i.workspace_id,i.role,i.expires_at from public.invitations i join ws on ws.id=i.workspace_id
   where i.status='sent' and i.expires_at>now()
 )
 select jsonb_build_object(
  'organizationId',v_org,'organizationName',(select name from public.organizations where id=v_org),
  'workspaces',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'status',status) order by name),'[]'::jsonb) from ws),
  'people',(select coalesce(jsonb_agg(jsonb_build_object(
   'id',p.person_key,'userId',coalesce(p.user_id,o.user_id),'name',coalesce(p.display_name,p.email),'email',p.email,
   'organizationRole',o.role,'organizationStatus',o.status,
   'inheritedAdministration',coalesce(o.status='active' and o.role in ('owner','admin'),false),
   'internal',exists(select 1 from members m where m.user_id::text=p.person_key)
     or coalesce(o.status<>'removed',false),
   'workspaceRoles',(select coalesce(jsonb_agg(jsonb_build_object(
    'workspaceId',m.workspace_id,'role',m.role,'status',m.status) order by m.workspace_id),'[]'::jsonb)
    from members m where m.user_id::text=p.person_key),
   'projectRoles',(select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'projectId',r.project_id,'projectName',r.project_name,'projectStatus',r.project_status,
    'archived',r.archived_at is not null or r.project_status='archived',
    'workspaceId',r.workspace_id,'role',r.role,'professionalLabel',r.professional_label,'canSubmitDeliverables',r.can_submit_deliverables,'source',r.source,'sourceId',r.source_id,'status',r.status)
    order by r.project_name,r.id),'[]'::jsonb) from project_roles r where r.person_key=p.person_key)
   ) order by coalesce(p.display_name,p.email),p.person_key),'[]'::jsonb)
   from people p left join org_people o on o.user_id::text=p.person_key),
  'pendingInvitations',(select coalesce(jsonb_agg(jsonb_build_object(
   'id',i.id,'email',i.email,'scope',i.scope,'workspaceId',i.workspace_id,'role',i.role,'expiresAt',i.expires_at)
   order by i.expires_at),'[]'::jsonb) from invitations i)
 ) into v_result;
 return v_result;
end;
$fn$;


create or replace function public.attach_file_to_version(
  p_asset_version_id uuid, p_checksum_hex text, p_mime_type text,
  p_size_bytes bigint, p_storage_ref text,
  p_display_name text default null, p_role text default 'primary',
  p_sort_order integer default null
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_project_id uuid; v_status text; v_checksum bytea; v_file_id uuid; v_sort int; v_vf_id uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'attach_file_to_version: auth required' using errcode='42501'; end if;
  if p_asset_version_id is null then raise exception 'attach_file_to_version: asset_version_id required' using errcode='22004'; end if;
  if p_checksum_hex is null or length(p_checksum_hex) <> 64 then
    raise exception 'attach_file_to_version: checksum_hex must be 64-char sha256 hex' using errcode='22023';
  end if;
  if p_mime_type is null or length(trim(p_mime_type))=0 then raise exception 'attach_file_to_version: mime_type required' using errcode='22004'; end if;
  if p_size_bytes is null or p_size_bytes<0 then raise exception 'attach_file_to_version: size_bytes required nonneg' using errcode='22023'; end if;
  if p_storage_ref is null or length(trim(p_storage_ref))=0 then raise exception 'attach_file_to_version: storage_ref required' using errcode='22004'; end if;
  if p_role is null or p_role not in ('primary','reference','spec','source','export','other') then
    raise exception 'attach_file_to_version: invalid role %', coalesce(p_role,'(null)') using errcode='22023';
  end if;

  select workspace_id, project_id, status into v_workspace_id, v_project_id, v_status
    from public.asset_versions where id = p_asset_version_id for update;
  if v_workspace_id is null then
    raise exception 'attach_file_to_version: version % not found', p_asset_version_id using errcode='23503';
  end if;
  if v_status <> 'draft' then
    raise exception 'attach_file_to_version: version % is % (must be draft)', p_asset_version_id, v_status using errcode='23514';
  end if;
  if not (public.lign_has_capability(v_project_id, v_workspace_id, 'version.upload')
      and public.lign_has_capability(v_project_id, v_workspace_id, 'file.attach')) then
    raise exception 'attach_file_to_version: forbidden (version.upload+file.attach)' using errcode='42501';
  end if;

  v_checksum := decode(p_checksum_hex, 'hex');
  select id into v_file_id from public.files where workspace_id = v_workspace_id and checksum_sha256 = v_checksum and submission_scope_id is null;
  if v_file_id is null then
    insert into public.files (workspace_id, checksum_sha256, mime_type, size_bytes, storage_ref, uploaded_by_profile_id, status)
    values (v_workspace_id, v_checksum, p_mime_type, p_size_bytes, p_storage_ref, v_caller, 'active')
    returning id into v_file_id;
  end if;

  if p_sort_order is not null then
    v_sort := p_sort_order;
  else
    select coalesce(max(sort_order), -1) + 1 into v_sort
      from public.version_files where asset_version_id = p_asset_version_id;
  end if;

  insert into public.version_files (workspace_id, asset_version_id, file_id, display_name, role, sort_order)
  values (v_workspace_id, p_asset_version_id, v_file_id, p_display_name, p_role, v_sort)
  returning id into v_vf_id;
  return v_vf_id;
end $$;

create or replace function public.release_purge_claim(p_file_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_workspace_id uuid; v_status text; v_reserved_at timestamptz;
  v_checksum bytea; v_conflict boolean; v_scope uuid;
begin
  if p_file_id is null then raise exception 'release_purge_claim: file_id required' using errcode='22004'; end if;
  select workspace_id, status, purge_reserved_at, checksum_sha256, submission_scope_id
    into v_workspace_id, v_status, v_reserved_at, v_checksum, v_scope
    from public.files where id = p_file_id for update;
  if v_status is null then raise exception 'release_purge_claim: file % not found', p_file_id using errcode='23503'; end if;
  if v_status = 'purged' then raise exception 'release_purge_claim: file % is already purged (cannot release)', p_file_id using errcode='23514'; end if;
  if v_reserved_at is null then return; end if;

  -- STORAGE 004 race guard: if a fresh row for the same (workspace, checksum)
  -- was created while this row was reserved (start_version_file_upload's
  -- partial-index-bypass path), clearing the reservation here would violate
  -- files_workspace_checksum_key. In that case the reserved row is stranded
  -- and the operator must complete the physical DELETE and call
  -- mark_file_purged instead (purged rows are excluded from the index).
  select exists (
    select 1 from public.files f2
     where f2.workspace_id  = v_workspace_id
       and f2.checksum_sha256 = v_checksum
       and f2.submission_scope_id is not distinct from v_scope
       and f2.id <> p_file_id
       and f2.status <> 'purged'
       and f2.purge_reserved_at is null
  ) into v_conflict;

  if v_conflict then
    raise exception 'release_purge_claim: cannot release file % — another non-purged File exists for the same checksum (reclaim raced during in-flight purge). Complete the Storage HTTP DELETE and call mark_file_purged instead.', p_file_id using errcode='23514';
  end if;

  update public.files set purge_reserved_at=null, purge_reserved_by=null where id = p_file_id;
end $$;
