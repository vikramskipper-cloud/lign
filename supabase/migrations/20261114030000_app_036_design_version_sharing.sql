-- APP 036: independent internal sign-off and explicit recipient/version access.
alter table public.asset_versions add column author_profile_id uuid references public.profiles(id);
create table public.design_version_reviews (
 version_id uuid primary key references public.asset_versions(id),
 stage text not null default 'draft' check(stage in ('draft','submitted','changes_requested','approved')),
 author_id uuid references public.profiles(id),edit_version bigint not null default 0,
 submitted_at timestamptz,reviewed_at timestamptz,reviewed_by uuid references public.profiles(id),note text not null default '' check(length(note)<=5000)
);
create table public.design_version_review_events (
 id uuid primary key default gen_random_uuid(),version_id uuid not null references public.asset_versions(id),
 actor_id uuid not null references public.profiles(id),action text not null,note text not null default '',created_at timestamptz not null default now()
);
create index design_version_review_events_version on public.design_version_review_events(version_id,created_at,id);
create table public.design_version_shares (
 version_id uuid not null references public.asset_versions(id),participant_id uuid not null references public.project_participants(id),
 shared_by uuid not null references public.profiles(id),shared_at timestamptz not null default now(),revoked_at timestamptz,
 primary key(version_id,participant_id)
);
create index design_version_shares_participant on public.design_version_shares(participant_id,version_id);
create table public.design_share_events (
 id uuid primary key default gen_random_uuid(),version_id uuid not null references public.asset_versions(id),
 participant_id uuid not null references public.project_participants(id),actor_id uuid not null references public.profiles(id),
 action text not null check(action in ('shared','revoked')),created_at timestamptz not null default now()
);
create index design_share_events_version on public.design_share_events(version_id,created_at,id);
create or replace function public.lign_design_team_for(p_project_id uuid,p_user_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.projects p join public.workspaces w on w.id=p.workspace_id join public.organization_members om on om.organization_id=w.organization_id and om.user_id=p_user_id and om.status='active'
 where p.id=p_project_id and (om.role in ('owner','admin') or exists(select 1 from public.workspace_members wm where wm.workspace_id=w.id and wm.user_id=p_user_id and wm.status='active' and wm.role in ('owner','admin')) or exists(select 1 from public.project_participants pp left join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active' left join public.stakeholders sh on sh.id=pp.stakeholder_id and sh.status='active' where pp.project_id=p.id and pp.status='active' and pp.role in ('lead','contributor') and coalesce(wm.user_id,sh.user_id)=p_user_id))); $$;
create or replace function public.lign_design_team(p_project_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select auth.uid() is not null and public.lign_design_team_for(p_project_id,auth.uid()); $$;
create or replace function public.lign_design_participant_user(p_participant_id uuid,p_project_id uuid)
returns uuid language sql stable security definer set search_path=''
as $$ select coalesce(wm.user_id,sh.user_id) from public.project_participants pp left join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active' left join public.stakeholders sh on sh.id=pp.stakeholder_id and sh.status='active' where pp.id=p_participant_id and pp.project_id=p_project_id and pp.status='active'; $$;
create or replace function public.lign_version_internally_approved(p_version_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.design_version_reviews r where r.version_id=p_version_id and r.stage='approved' and r.reviewed_by is not null and r.author_id is not null and r.reviewed_by<>r.author_id); $$;
create or replace function public.lign_can_read_design_version(p_version_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.asset_versions v where v.id=p_version_id and auth.uid() is not null and public.lign_has_capability(v.project_id,v.workspace_id,'version.view') and
 (public.lign_design_team(v.project_id)
 or exists(select 1 from public.deliverable_submissions s where s.asset_version_id=v.id and s.author_id=auth.uid() and public.lign_can_submit_deliverables(v.project_id))
 or (v.status in ('published','superseded','deprecated') and public.lign_version_internally_approved(v.id) and exists(select 1 from public.design_version_shares x where x.version_id=v.id and x.revoked_at is null and public.lign_design_participant_user(x.participant_id,v.project_id)=auth.uid())))); $$;
create or replace function public.lign_can_read_design_asset(p_asset_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.design_assets a where a.id=p_asset_id and (public.lign_design_team(a.project_id) or exists(select 1 from public.asset_versions v where v.design_asset_id=a.id and public.lign_can_read_design_version(v.id)))); $$;
create or replace function public.lign_can_read_design_review(p_review_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.reviews r where r.id=p_review_id and (public.lign_design_team(r.project_id) or (r.status<>'draft' and public.lign_can_read_design_version(r.version_id) and exists(select 1 from public.review_participants rp left join public.workspace_members wm on wm.id=rp.workspace_member_id and wm.status='active' left join public.stakeholders sh on sh.id=rp.stakeholder_id and sh.status='active' where rp.review_id=r.id and rp.removed_at is null and coalesce(wm.user_id,sh.user_id)=auth.uid())))); $$;
create or replace function public.lign_can_read_design_approval(p_request_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.approval_requests r where r.id=p_request_id and (public.lign_design_team(r.project_id) or (r.status<>'draft' and public.lign_can_read_design_version(r.version_id) and exists(select 1 from public.approval_request_approvers rp left join public.workspace_members wm on wm.id=rp.workspace_member_id and wm.status='active' left join public.stakeholders sh on sh.id=rp.stakeholder_id and sh.status='active' where rp.approval_request_id=r.id and rp.removed_at is null and coalesce(wm.user_id,sh.user_id)=auth.uid())))); $$;
create or replace function public.lign_can_read_proposal_revision(p_revision_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.proposal_revisions r where r.id=p_revision_id and public.lign_has_capability(r.project_id,r.workspace_id,'project.view') and (public.lign_design_team(r.project_id) or public.lign_brief_respondent_user(r.respondent_id,r.project_id)=auth.uid())); $$;

create or replace function public.lign_can_download_file(p_file_id uuid,p_workspace_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.files f where f.id=p_file_id and f.workspace_id=p_workspace_id and
 ((public.lign_is_workspace_admin(p_workspace_id) and public.lign_is_org_member((select organization_id from public.workspaces where id=p_workspace_id))) or exists(select 1 from public.version_files vf where vf.file_id=f.id and public.lign_can_read_design_version(vf.asset_version_id)))); $$;
alter table public.comments add column audience text not null default 'internal' check(audience in ('internal','shared'));
alter table public.annotations add column audience text not null default 'internal' check(audience in ('internal','shared'));
alter table public.changes add column audience text not null default 'internal' check(audience in ('internal','shared'));
alter table public.decisions add column audience text not null default 'internal' check(audience in ('internal','shared'));
create or replace function public.lign_design_row_project(p_row jsonb,p_depth integer default 0)
returns uuid language plpgsql stable security definer set search_path=''
as $$ declare v uuid;j jsonb;begin
 if p_depth>20 then return null;end if;
 if p_row->>'project_id' is not null then return (p_row->>'project_id')::uuid;end if;
 select project_id into v from public.asset_versions where id=coalesce((p_row->>'asset_version_id')::uuid,(p_row->>'target_version_id')::uuid,(p_row->>'version_id')::uuid);if found then return v;end if;
 select project_id into v from public.design_assets where id=coalesce((p_row->>'target_design_asset_id')::uuid,(p_row->>'design_asset_id')::uuid);if found then return v;end if;
 select project_id into v from public.reviews where id=coalesce((p_row->>'target_review_id')::uuid,(p_row->>'review_id')::uuid);if found then return v;end if;
 select project_id into v from public.approval_requests where id=coalesce((p_row->>'target_approval_request_id')::uuid,(p_row->>'approval_request_id')::uuid);if found then return v;end if;
 select project_id into v from public.requirements where id=coalesce((p_row->>'target_requirement_id')::uuid,(p_row->>'requirement_id')::uuid);if found then return v;end if;
 select to_jsonb(a) into j from public.annotations a where id=(p_row->>'target_annotation_id')::uuid;if found then return public.lign_design_row_project(j,p_depth+1);end if;
 select to_jsonb(a) into j from public.changes a where id=(p_row->>'target_change_id')::uuid;if found then return public.lign_design_row_project(j,p_depth+1);end if;
 select to_jsonb(a) into j from public.decisions a where id=(p_row->>'target_decision_id')::uuid;if found then return public.lign_design_row_project(j,p_depth+1);end if;
 select to_jsonb(a) into j from public.comments a where id=(p_row->>'comment_id')::uuid;if found then return public.lign_design_row_project(j,p_depth+1);end if;
 select project_id into v from public.releases where id=(p_row->>'release_id')::uuid;return v;
end; $$;
create or replace function public.lign_design_row_visible(p_table text,p_row jsonb,p_depth integer default 0)
returns boolean language plpgsql stable security definer set search_path=''
as $$ declare p uuid;j jsonb;v uuid;has_target boolean:=false;begin
 if auth.uid() is null or p_depth>20 then return false;end if;
 if p_table='notifications' and (p_row->>'recipient_profile_id')::uuid is distinct from auth.uid() then return false;end if;
 p:=public.lign_design_row_project(p_row);if public.lign_design_team(p) then return true;end if;
 if p_table='files' then return public.lign_can_download_file((p_row->>'id')::uuid,(p_row->>'workspace_id')::uuid);end if;
 if p_table='asset_versions' then return public.lign_can_read_design_version((p_row->>'id')::uuid);end if;
 if p_table='design_assets' then return public.lign_can_read_design_asset((p_row->>'id')::uuid);end if;
 if p_table='reviews' then return public.lign_can_read_design_review((p_row->>'id')::uuid);end if;
 if p_table='approval_requests' then return public.lign_can_read_design_approval((p_row->>'id')::uuid);end if;
 if p_table='proposal_revisions' then return public.lign_can_read_proposal_revision((p_row->>'id')::uuid);end if;
 if p_table='proposal_decisions' then return public.lign_can_read_proposal_revision((p_row->>'revision_id')::uuid);end if;
 if p_table='collections' then return exists(select 1 from public.design_assets a where a.collection_id=(p_row->>'id')::uuid and public.lign_can_read_design_asset(a.id));end if;
 if p_table='version_files' then return public.lign_can_read_design_version((p_row->>'asset_version_id')::uuid);end if;
 if p_table='deliverable_submissions' then return (p_row->>'author_id')::uuid=auth.uid() and public.lign_can_submit_deliverables(p);end if;
 if p_table='deliverable_submission_events' then select to_jsonb(s) into j from public.deliverable_submissions s where id=(p_row->>'submission_id')::uuid;return public.lign_design_row_visible('deliverable_submissions',j,p_depth+1);end if;
 if p_table='review_participants' then return public.lign_can_read_design_review((p_row->>'review_id')::uuid);end if;
 if p_table in ('approval_request_approvers','approval_responses') then return public.lign_can_read_design_approval((p_row->>'approval_request_id')::uuid);end if;
 if p_table='comment_edits' then return false;end if;
 -- Internal evidence and working activity are not client publications.
 if p_table in ('releases','release_items','version_requirement_assessments','activity_events','design_version_reviews','design_version_review_events','design_share_events') then return false;end if;
 if p_table='notifications' then
 if p is null then return true;end if;
 if p_row->>'event_type' not in ('review.opened','review.participant_added','review.completed','review.cancelled','approval.sent','approval.responded','approval.approved','approval.rejected','approval.expired','approval.cancelled','version.shared','design.internal_review_requested','design.internal_review_decided') then return false;end if;
 if p is null then return true;end if;
 if p_row->>'subject_kind'='asset_version' then return public.lign_can_read_design_version((p_row->>'subject_id')::uuid);end if;
 if p_row->>'subject_kind'='review' then return public.lign_can_read_design_review((p_row->>'subject_id')::uuid);end if;
 if p_row->>'subject_kind'='approval_request' then return public.lign_can_read_design_approval((p_row->>'subject_id')::uuid);end if;return false;end if;
 if p_table='comments' and p_row->>'deleted_at' is not null then return false;end if;
 if p_table='annotations' and p_row->>'archived_at' is not null then return false;end if;
 if p_table not in ('comments','annotations','changes','decisions') or p_row->>'audience'<>'shared' then return false;end if;
 if p_row->>'parent_comment_id' is not null then select to_jsonb(c) into j from public.comments c where id=(p_row->>'parent_comment_id')::uuid;if not coalesce(public.lign_design_row_visible('comments',j,p_depth+1),false) then return false;end if;end if;
 for v in select value::uuid from jsonb_each_text(p_row) where key in ('target_version_id','asset_version_id','from_version_id','to_version_id','resulting_version_id') and value is not null loop has_target:=true;if not public.lign_can_read_design_version(v) then return false;end if;end loop;
 if p_row->>'target_review_id' is not null then has_target:=true;if not public.lign_can_read_design_review((p_row->>'target_review_id')::uuid) then return false;end if;end if;
 if p_row->>'target_approval_request_id' is not null then has_target:=true;if not public.lign_can_read_design_approval((p_row->>'target_approval_request_id')::uuid) then return false;end if;end if;
 if p_row->>'target_annotation_id' is not null then has_target:=true;select to_jsonb(a) into j from public.annotations a where id=(p_row->>'target_annotation_id')::uuid;if not coalesce(public.lign_design_row_visible('annotations',j,p_depth+1),false) then return false;end if;end if;
 if p_row->>'target_change_id' is not null then has_target:=true;select to_jsonb(a) into j from public.changes a where id=(p_row->>'target_change_id')::uuid;if not coalesce(public.lign_design_row_visible('changes',j,p_depth+1),false) then return false;end if;end if;
 if p_row->>'target_decision_id' is not null then has_target:=true;select to_jsonb(a) into j from public.decisions a where id=(p_row->>'target_decision_id')::uuid;if not coalesce(public.lign_design_row_visible('decisions',j,p_depth+1),false) then return false;end if;end if;
 if p_row->>'target_design_asset_id' is not null then has_target:=true;if not public.lign_can_read_design_asset((p_row->>'target_design_asset_id')::uuid) then return false;end if;end if;
 if p_row->>'target_requirement_id' is not null then has_target:=true;if not public.lign_has_capability(p,(p_row->>'workspace_id')::uuid,'requirement.view') then return false;end if;end if;
 return has_target;
end; $$;

create or replace function public.transition_design_version_review(p_version_id uuid,p_expected_version bigint,p_action text,p_note text default '')
returns void language plpgsql security definer set search_path=''
as $$ declare v public.asset_versions%rowtype;r public.design_version_reviews%rowtype;begin
 select * into v from public.asset_versions where id=p_version_id for update;
 if not exists(select 1 from public.projects where id=v.project_id and archived_at is null and status<>'archived') then raise exception 'An active project is required' using errcode='23514';end if;
 if v.id is null or v.status not in ('draft','published','superseded') or not public.lign_design_team(v.project_id) then raise exception 'Internal design team access to a draft is required' using errcode='42501';end if;
 insert into public.design_version_reviews(version_id,author_id) values(v.id,coalesce(v.author_profile_id,v.published_by_profile_id,auth.uid())) on conflict do nothing;
 select * into r from public.design_version_reviews where version_id=v.id for update;
 if r.edit_version is distinct from p_expected_version then raise exception 'The review changed. Reload before continuing.' using errcode='PT409';end if;
 if p_note is null or length(p_note)>5000 then raise exception 'Use a review note up to 5000 characters' using errcode='22023';end if;
 if p_action='submit' and r.stage in ('draft','changes_requested') then
 if exists(select 1 from public.deliverable_submissions where asset_version_id=v.id and stage<>'accepted') then raise exception 'Review the deliverable submission first' using errcode='23514';end if;
 if not exists(select 1 from public.version_files vf join public.files f on f.id=vf.file_id where vf.asset_version_id=v.id and f.status='active') then raise exception 'Attach at least one completed file before review' using errcode='23514';end if;
 update public.design_version_reviews set stage='submitted',submitted_at=now(),reviewed_by=null,reviewed_at=null,edit_version=edit_version+1 where version_id=v.id;
 elsif p_action in ('approve','request_changes') and r.stage='submitted' then
 if not public.lign_manage_project_brief(v.project_id) or r.author_id=auth.uid() or exists(select 1 from public.version_files vf join public.files f on f.id=vf.file_id where vf.asset_version_id=v.id and f.uploaded_by_profile_id=auth.uid()) then raise exception 'A different project lead, workspace lead or organisation owner/admin must review' using errcode='42501';end if;
 if p_action='request_changes' and trim(p_note)='' then raise exception 'Explain the changes required' using errcode='22023';end if;
 update public.design_version_reviews set stage=case when p_action='approve' then 'approved' else 'changes_requested' end,note=trim(p_note),reviewed_by=auth.uid(),reviewed_at=now(),edit_version=edit_version+1 where version_id=v.id;
 elsif p_action='withdraw' and r.stage in ('submitted','approved') then
 if v.status<>'draft' and r.stage='approved' then raise exception 'Published approvals are retained. Create a new design version for further changes.' using errcode='23514';end if;
 if auth.uid()<>r.author_id and not public.lign_manage_project_brief(v.project_id) then raise exception 'Author or project leadership required' using errcode='42501';end if;
 update public.design_version_reviews set stage='draft',reviewed_by=null,reviewed_at=null,edit_version=edit_version+1 where version_id=v.id;
 else raise exception 'Action is unavailable at the current review stage' using errcode='23514';end if;
 insert into public.design_version_review_events(version_id,actor_id,action,note) values(v.id,auth.uid(),p_action,trim(p_note));perform public.notify_design_review(v.id,p_action);end; $$;
create or replace function public.grant_design_version_share(p_version_id uuid,p_participant_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ declare v public.asset_versions%rowtype;begin
 select * into v from public.asset_versions where id=p_version_id;
 if not public.lign_design_team(v.project_id) or v.status not in ('published','superseded','deprecated') or not public.lign_version_internally_approved(v.id) then raise exception 'Only internally approved published versions can be shared' using errcode='42501';end if;
 if not exists(select 1 from public.project_participants pp left join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active' left join public.stakeholders sh on sh.id=pp.stakeholder_id and sh.status in ('active','invited') where pp.id=p_participant_id and pp.project_id=v.project_id and pp.status='active' and (wm.id is not null or sh.id is not null)) then raise exception 'Choose an active project participant or pending project invitation' using errcode='22023';end if;
 insert into public.design_version_shares(version_id,participant_id,shared_by) values(v.id,p_participant_id,auth.uid()) on conflict(version_id,participant_id) do update set shared_by=excluded.shared_by,shared_at=now(),revoked_at=null;
 insert into public.design_share_events(version_id,participant_id,actor_id,action) values(v.id,p_participant_id,auth.uid(),'shared');end; $$;
create or replace function public.share_design_version(p_version_id uuid,p_participant_ids uuid[])
returns void language plpgsql security definer set search_path=''
as $$ declare v public.asset_versions%rowtype;x uuid;begin
 select * into v from public.asset_versions where id=p_version_id for update;
 if v.id is null or not public.lign_design_team(v.project_id) or not public.lign_manage_project_brief(v.project_id) then raise exception 'Project or inherited leadership access required' using errcode='42501';end if;
 if p_participant_ids is null or cardinality(p_participant_ids) not between 1 and 100 then raise exception 'Select 1–100 active recipients' using errcode='22023';end if;
 foreach x in array p_participant_ids loop perform public.grant_design_version_share(v.id,x);end loop;end; $$;
create or replace function public.revoke_design_version_share(p_version_id uuid,p_participant_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ declare v public.asset_versions%rowtype;begin
 select * into v from public.asset_versions where id=p_version_id for update;
 if v.id is null or not public.lign_design_team(v.project_id) or not public.lign_manage_project_brief(v.project_id) then raise exception 'Project leadership access required' using errcode='42501';end if;
 update public.design_version_shares set revoked_at=now() where version_id=v.id and participant_id=p_participant_id and revoked_at is null;
 if found then insert into public.design_share_events(version_id,participant_id,actor_id,action) values(v.id,p_participant_id,auth.uid(),'revoked');end if;end; $$;
create or replace function public.get_design_version_access(p_version_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v public.asset_versions%rowtype;r public.design_version_reviews%rowtype;team boolean;begin
 select * into v from public.asset_versions where id=p_version_id;
 if v.id is null or not public.lign_can_read_design_version(v.id) then raise exception 'Shared version access required' using errcode='42501';end if;
 team:=public.lign_design_team(v.project_id);select * into r from public.design_version_reviews where version_id=v.id;
 return jsonb_build_object('internal',team,'stage',coalesce(r.stage,'draft'),'version',coalesce(r.edit_version,0),'authorId',coalesce(r.author_id,v.author_profile_id),'canReview',team and public.lign_manage_project_brief(v.project_id) and coalesce(r.author_id,v.author_profile_id) is distinct from auth.uid() and not exists(select 1 from public.version_files vf join public.files f on f.id=vf.file_id where vf.asset_version_id=v.id and f.uploaded_by_profile_id=auth.uid()),
 'canPublish',team and public.lign_version_internally_approved(v.id) and (public.lign_manage_project_brief(v.project_id) or public.lign_has_capability(v.project_id,v.workspace_id,'version.publish')),'canShare',team and public.lign_manage_project_brief(v.project_id) and v.status<>'draft' and public.lign_version_internally_approved(v.id),'note',case when team then coalesce(r.note,'') else '' end,
 'recipients',case when team and public.lign_manage_project_brief(v.project_id) then (select coalesce(jsonb_agg(jsonb_build_object('id',pp.id,'name',coalesce(p.display_name,sh.display_name,sh.email::text),'role',pp.role,'shared',exists(select 1 from public.design_version_shares x where x.version_id=v.id and x.participant_id=pp.id and x.revoked_at is null)) order by pp.id),'[]'::jsonb) from public.project_participants pp left join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active' left join public.stakeholders sh on sh.id=pp.stakeholder_id and sh.status in ('active','invited') left join public.profiles p on p.id=coalesce(wm.user_id,sh.user_id) where pp.project_id=v.project_id and pp.status='active' and (wm.id is not null or sh.id is not null)) else '[]'::jsonb end,
 'history',case when team then (select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at desc),'[]'::jsonb) from (select e.action,e.note,e.created_at,p.display_name as name from public.design_version_review_events e join public.profiles p on p.id=e.actor_id where e.version_id=v.id order by e.created_at desc limit 30)e) else '[]'::jsonb end);end; $$;
create or replace function public.guard_design_version_review()
returns trigger language plpgsql security definer set search_path=''
as $$ declare r public.design_version_reviews%rowtype;v_id uuid;begin
 if tg_table_name='asset_versions' then
 if tg_op='INSERT' then new.author_profile_id:=coalesce(auth.uid(),new.author_profile_id);return new;end if;
 select * into r from public.design_version_reviews where version_id=old.id for update;
 if tg_op='DELETE' and r.version_id is not null then raise exception 'Reviewed versions are retained' using errcode='23514';end if;
 if tg_op='DELETE' then return old;end if;
 if new.author_profile_id is distinct from old.author_profile_id then raise exception 'Version authorship is immutable' using errcode='23514';end if;
 if new.status='published' and old.status='draft' and not public.lign_version_internally_approved(old.id) then raise exception 'Independent leadership approval is required before publication' using errcode='23514';end if;
 if r.stage in ('submitted','approved') and (new.label is distinct from old.label or new.notes is distinct from old.notes or new.design_asset_id<>old.design_asset_id or new.project_id<>old.project_id or new.workspace_id<>old.workspace_id or new.sequence<>old.sequence) then raise exception 'Reviewed version content is frozen. Withdraw the review before editing.' using errcode='23514';end if;
 return new;
 end if;
 v_id:=case when tg_op='DELETE' then old.asset_version_id else new.asset_version_id end;
 if tg_op<>'DELETE' and auth.uid() is not null and not exists(select 1 from public.files f where f.id=new.file_id and (f.uploaded_by_profile_id=auth.uid() or public.lign_can_download_file(f.id,f.workspace_id))) then raise exception 'Access to the attachment is required' using errcode='42501';end if;
 select * into r from public.design_version_reviews where version_id=v_id for update;
 if r.stage in ('submitted','approved') then raise exception 'Reviewed file attachments are frozen' using errcode='23514';end if;
 if tg_op='UPDATE' and new.asset_version_id is distinct from old.asset_version_id and exists(select 1 from public.design_version_reviews where version_id=old.asset_version_id and stage in ('submitted','approved')) then raise exception 'Reviewed file attachments are frozen' using errcode='23514';end if;
 if tg_op='DELETE' then return old;end if;return new;end; $$;
create trigger vp_version_review_guard before insert or update or delete on public.asset_versions for each row execute function public.guard_design_version_review();
create trigger vp_files_review_guard before insert or update or delete on public.version_files for each row execute function public.guard_design_version_review();
create or replace function public.preserve_design_review_history()
returns trigger language plpgsql set search_path=''
as $$ begin raise exception 'Design review and share evidence is immutable' using errcode='23514';end; $$;
create trigger vp_review_history_immutable before update or delete on public.design_version_review_events for each row execute function public.preserve_design_review_history();
create trigger vp_share_history_immutable before update or delete on public.design_share_events for each row execute function public.preserve_design_review_history();

create or replace function public.guard_design_discussion_scope()
returns trigger language plpgsql security definer set search_path=''
as $$ declare p uuid;j jsonb;parent public.comments%rowtype;team boolean;begin
 j:=to_jsonb(new);p:=public.lign_design_row_project(j);team:=public.lign_design_team(p);
 if auth.uid() is null then return new;end if;
 if tg_table_name='comments' then if new.parent_comment_id is not null then
 select * into parent from public.comments where id=new.parent_comment_id;
 if not public.lign_design_row_visible('comments',to_jsonb(parent)) then raise exception 'Parent discussion access required' using errcode='42501';end if;
 new.audience:=parent.audience;
 end if;end if;
 if not team then new.audience:='shared';end if;
 if not public.lign_design_row_visible(tg_table_name,to_jsonb(new)) then raise exception 'Access to this shared design discussion is required' using errcode='42501';end if;
 if tg_op='UPDATE' and not team and old.audience='internal' then raise exception 'Internal discussion is private' using errcode='42501';end if;
 return new;end; $$;
create trigger vp_comments_scope_guard before insert or update on public.comments for each row execute function public.guard_design_discussion_scope();
create trigger vp_annotations_scope_guard before insert or update on public.annotations for each row execute function public.guard_design_discussion_scope();
create trigger vp_changes_scope_guard before insert or update on public.changes for each row execute function public.guard_design_discussion_scope();
create trigger vp_decisions_scope_guard before insert or update on public.decisions for each row execute function public.guard_design_discussion_scope();
create or replace function public.guard_design_request_scope()
returns trigger language plpgsql security definer set search_path=''
as $$ declare r public.reviews%rowtype;a public.approval_requests%rowtype;pp uuid;target_user uuid;v_id uuid;p_id uuid;recipient_user uuid;begin
 if auth.uid() is null then return new;end if;
 if tg_table_name='approval_requests' then
 if new.status<>'draft' and (tg_op='INSERT' or old.status='draft') and not public.lign_version_internally_approved(new.version_id) then raise exception 'Leadership sign-off is required before sending client approvals' using errcode='23514';end if;
 return new;
 elsif tg_table_name='approval_responses' then
 if not public.lign_can_read_design_approval(new.approval_request_id) then raise exception 'Access to the exact shared approval version is required' using errcode='42501';end if;return new;
 elsif tg_table_name='review_participants' then
 select * into r from public.reviews where id=new.review_id;v_id:=r.version_id;p_id:=r.project_id;
 elsif tg_table_name='approval_request_approvers' then
 select * into a from public.approval_requests where id=new.approval_request_id;v_id:=a.version_id;p_id:=a.project_id;
 end if;
 select coalesce(wm.user_id,sh.user_id) into target_user from (select 1)x left join public.workspace_members wm on wm.id=new.workspace_member_id and wm.status='active' left join public.stakeholders sh on sh.id=new.stakeholder_id and sh.status in ('active','invited');
 if tg_table_name='review_participants' and tg_op='UPDATE' and not public.lign_design_team(p_id) then
 if not public.lign_can_read_design_review(new.review_id) then raise exception 'Access to the shared review version is required' using errcode='42501';end if;
 return new;end if;
 if not public.lign_design_team_for(p_id,target_user) and not public.lign_version_internally_approved(v_id) then raise exception 'Internal sign-off is required before assigning external recipients' using errcode='23514';end if;
 return new;end; $$;
create trigger vp_approval_send_guard before insert or update on public.approval_requests for each row execute function public.guard_design_request_scope();
create trigger vp_approval_response_guard before insert on public.approval_responses for each row execute function public.guard_design_request_scope();
create trigger vp_review_recipient_guard before insert or update on public.review_participants for each row execute function public.guard_design_request_scope();
create trigger vp_approval_recipient_guard before insert or update on public.approval_request_approvers for each row execute function public.guard_design_request_scope();
create or replace function public.publish_design_request_shares()
returns trigger language plpgsql security definer set search_path=''
as $$ declare p uuid;v uuid;x uuid;begin
 if auth.uid() is null then return new;end if;
 if tg_table_name='approval_requests' then
 if new.status='draft' then return new;end if;p:=new.project_id;v:=new.version_id;if not public.lign_design_team(p) then return new;end if;
 for x in select pp.id from public.approval_request_approvers a join public.project_participants pp on pp.project_id=p and pp.status='active' and (pp.workspace_member_id=a.workspace_member_id or pp.stakeholder_id=a.stakeholder_id) where a.approval_request_id=new.id and a.removed_at is null loop perform public.grant_design_version_share(v,x);end loop;
 elsif tg_table_name='approval_request_approvers' then
 select project_id,version_id into p,v from public.approval_requests where id=new.approval_request_id and status<>'draft';
 if p is not null and not public.lign_design_team(p) then return new;end if;
 if p is not null and new.removed_at is null then select id into x from public.project_participants where project_id=p and status='active' and (workspace_member_id=new.workspace_member_id or stakeholder_id=new.stakeholder_id);if x is not null then perform public.grant_design_version_share(v,x);end if;end if;
 elsif tg_table_name='reviews' then
 if new.status='draft' then return new;end if;p:=new.project_id;v:=new.version_id;if not public.lign_design_team(p) then return new;end if;
 for x in select pp.id from public.review_participants a join public.project_participants pp on pp.project_id=p and pp.status='active' and (pp.workspace_member_id=a.workspace_member_id or pp.stakeholder_id=a.stakeholder_id) where a.review_id=new.id and a.removed_at is null and not public.lign_design_team_for(p,public.lign_design_participant_user(pp.id,p)) loop perform public.grant_design_version_share(v,x);end loop;
 elsif tg_table_name='review_participants' then
 select project_id,version_id into p,v from public.reviews where id=new.review_id and status<>'draft';
 if p is not null and not public.lign_design_team(p) then return new;end if;
 if p is not null and new.removed_at is null then select id into x from public.project_participants where project_id=p and status='active' and (workspace_member_id=new.workspace_member_id or stakeholder_id=new.stakeholder_id);if x is not null and not public.lign_design_team_for(p,public.lign_design_participant_user(x,p)) then perform public.grant_design_version_share(v,x);end if;end if;
 end if;return new;end; $$;
create trigger vp_approval_share after insert or update of status on public.approval_requests for each row execute function public.publish_design_request_shares();
create trigger vp_approval_roster_share after insert or update on public.approval_request_approvers for each row execute function public.publish_design_request_shares();
create trigger vp_review_share after insert or update of status on public.reviews for each row execute function public.publish_design_request_shares();
create trigger vp_review_roster_share after insert or update on public.review_participants for each row execute function public.publish_design_request_shares();
create or replace function public.sync_deliverable_design_review()
returns trigger language plpgsql security definer set search_path=''
as $$ declare r public.design_version_reviews%rowtype;begin
 if new.stage='submitted' and old.stage<>new.stage then
 insert into public.design_version_reviews(version_id,stage,author_id,submitted_at,edit_version) values(new.asset_version_id,'submitted',new.author_id,now(),1)
 on conflict(version_id) do update set stage='submitted',submitted_at=now(),edit_version=public.design_version_reviews.edit_version+1;
 elsif new.stage in ('accepted','changes_requested') and old.stage<>new.stage then
 select * into r from public.design_version_reviews where version_id=new.asset_version_id;
 perform public.transition_design_version_review(new.asset_version_id,r.edit_version,case when new.stage='accepted' then 'approve' else 'request_changes' end,coalesce(current_setting('lign.deliverable_review_note',true),''));
 end if;return new;end; $$;
create trigger vp_deliverable_design_review after update of stage on public.deliverable_submissions for each row execute function public.sync_deliverable_design_review();
CREATE OR REPLACE FUNCTION public.transition_deliverable_submission(p_submission_id uuid, p_action text, p_note text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if not public.lign_manage_project_brief(v_s.project_id) or not public.lign_design_team(v_s.project_id) or auth.uid()=v_s.author_id then raise exception 'Another project lead or contributor must review this submission' using errcode='42501'; end if;
  if v_s.stage<>'submitted' then raise exception 'This submission is no longer awaiting review' using errcode='PT409'; end if;
  if p_action='request_changes' and trim(coalesce(p_note,''))='' then raise exception 'Describe the changes requested' using errcode='22023'; end if;
  v_stage:=case p_action when 'accept' then 'accepted' else 'changes_requested' end;
 elsif p_action='withdraw' then
  if v_s.author_id<>auth.uid() or not public.lign_can_submit_deliverables(v_s.project_id) then raise exception 'Only the permitted author can withdraw this submission' using errcode='42501'; end if;
  if v_s.stage not in ('draft','submitted') then raise exception 'This submission can no longer be withdrawn' using errcode='PT409'; end if;
  v_stage:='withdrawn';
 else raise exception 'Unknown submission action' using errcode='22023'; end if;
 if p_action in ('accept','request_changes') then perform set_config('lign.deliverable_review_note',coalesce(p_note,''),true);end if;
 update public.deliverable_submissions set stage=v_stage,updated_at=now() where id=v_s.id;
 insert into public.deliverable_submission_events(submission_id,project_id,workspace_id,actor_id,action,note) values(v_s.id,v_s.project_id,v_s.workspace_id,auth.uid(),v_stage,coalesce(p_note,''));
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload)
 values(v_s.workspace_id,v_s.project_id,'deliverable.'||v_stage,auth.uid(),'user','asset_version',v_version,v_s.title,jsonb_build_object('note',coalesce(p_note,'')));
end; $function$;
CREATE OR REPLACE FUNCTION public.publish_version(p_asset_version_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller           uuid;
  v_workspace_id     uuid;
  v_project_id       uuid;
  v_design_asset_id  uuid;
  v_status           text;
  v_seq              integer;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'publish_version: auth required' using errcode='42501'; end if;

  select workspace_id, project_id, design_asset_id, status, sequence
    into v_workspace_id, v_project_id, v_design_asset_id, v_status, v_seq
    from public.asset_versions
   where id = p_asset_version_id
   for update;
  if v_workspace_id is null then raise exception 'publish_version: version not found' using errcode='23503'; end if;
  if v_status <> 'draft' then raise exception 'publish_version: version is % (must be draft)', v_status using errcode='23514'; end if;

  if not (public.lign_design_team(v_project_id) and (public.lign_has_capability(v_project_id,v_workspace_id,'version.publish') or public.lign_manage_project_brief(v_project_id))) then
    raise exception 'publish_version: forbidden (version.publish)' using errcode='42501';
  end if;

  if exists (
    select 1 from public.version_files vf
    join public.files f on f.id = vf.file_id
    where vf.asset_version_id = p_asset_version_id
      and f.status <> 'active'
  ) then
    raise exception 'publish_version: version has non-active file attachments' using errcode='23514';
  end if;

  update public.asset_versions
     set status='published', published_at=now(), published_by_profile_id=v_caller
   where id = p_asset_version_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_workspace_id, v_project_id, now(), 'version.published',
    v_caller, 'user', 'asset_version', p_asset_version_id, 'v'||v_seq,
    jsonb_build_object('design_asset_id', v_design_asset_id, 'sequence', v_seq), '{}'::jsonb
  );

  return p_asset_version_id;
end $function$;
CREATE OR REPLACE FUNCTION public.guard_deliverable_version()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_s public.deliverable_submissions%rowtype;
begin
 select * into v_s from public.deliverable_submissions where asset_version_id=old.id for update;
 if not found then if tg_op='DELETE' then return old; end if;return new;end if;
 if tg_op='DELETE' then raise exception 'Submission versions are retained in project history' using errcode='23514'; end if;
 if new.status='published' and old.status='draft' then
  if not exists(select 1 from public.projects where id=v_s.project_id and archived_at is null and status<>'archived') then raise exception 'Archived projects cannot publish submissions' using errcode='23514'; end if;
  if v_s.stage<>'accepted' then raise exception 'Accept the submitted deliverable before publishing its version' using errcode='23514'; end if;
  if not (public.lign_design_team(v_s.project_id) and (public.lign_has_capability(v_s.project_id,v_s.workspace_id,'version.publish') or public.lign_manage_project_brief(v_s.project_id))) then raise exception 'Project publishing permission required' using errcode='42501'; end if;
 elsif old.status='draft' and v_s.stage<>'draft' and (to_jsonb(new)-'updated_at') is distinct from (to_jsonb(old)-'updated_at') then
  raise exception 'Reviewed submission versions are frozen' using errcode='23514';
 end if;
 return new;
end; $function$;
CREATE OR REPLACE FUNCTION public.lign_prepare_proposal(p_project_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select exists(select 1 from public.projects p where p.id=p_project_id and p.archived_at is null and p.status<>'archived' and public.lign_design_team(p.id) and public.lign_has_capability(p.id,p.workspace_id,'project.view')); $function$;
CREATE OR REPLACE FUNCTION public.lign_read_planning_file(p_file_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select exists(select 1 from public.planning_files f where f.id=p_file_id and f.registered_at is not null and public.lign_has_capability(f.project_id,f.workspace_id,'project.view')
 and (f.reference_card_id is not null or public.lign_prepare_proposal(f.project_id) or exists(select 1 from public.proposal_revisions r where r.project_id=f.project_id and public.lign_can_read_proposal_revision(r.id) and r.snapshot->'files' @> jsonb_build_array(jsonb_build_object('id',f.id))))); $function$;
CREATE OR REPLACE FUNCTION public.transition_project_proposal(p_project_id uuid, p_expected_version bigint, p_action text, p_note text DEFAULT ''::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v public.project_proposals%rowtype;v_revision uuid;v_status text;v_snapshot jsonb;v_doc jsonb;v_user uuid;v_version bigint;begin
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
 if auth.uid()=v.created_by then raise exception 'A different project or inherited leader must review the proposal before client acceptance' using errcode='42501';end if;
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
 perform public.planning_event(p_project_id,'proposal.'||p_action,v.id,jsonb_build_object('revision_id',v_revision,'note',p_note));return v_version;end; $function$;

create or replace function public.lign_shared_design_for_user(p_version_id uuid,p_user_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.asset_versions v join public.design_version_shares x on x.version_id=v.id and x.revoked_at is null where v.id=p_version_id and v.status in ('published','superseded','deprecated') and public.lign_version_internally_approved(v.id) and public.lign_design_participant_user(x.participant_id,v.project_id)=p_user_id); $$;

create or replace function public.lign_design_notification_allowed(p_event jsonb,p_user_id uuid)
returns boolean language plpgsql stable security definer set search_path=''
as $$ declare p uuid:=(p_event->>'project_id')::uuid;begin
 if p is null or public.lign_design_team_for(p,p_user_id) then return true;end if;
 if p_event->>'subject_kind'='approval_request' then return exists(select 1 from public.approval_requests r where r.id=(p_event->>'subject_id')::uuid and r.status<>'draft' and public.lign_shared_design_for_user(r.version_id,p_user_id) and exists(select 1 from public.approval_request_approvers a left join public.workspace_members wm on wm.id=a.workspace_member_id and wm.status='active' left join public.stakeholders sh on sh.id=a.stakeholder_id and sh.status='active' where a.approval_request_id=r.id and a.removed_at is null and coalesce(wm.user_id,sh.user_id)=p_user_id));end if;
 if p_event->>'subject_kind'='review' then return exists(select 1 from public.reviews r where r.id=(p_event->>'subject_id')::uuid and r.status<>'draft' and public.lign_shared_design_for_user(r.version_id,p_user_id) and exists(select 1 from public.review_participants a left join public.workspace_members wm on wm.id=a.workspace_member_id and wm.status='active' left join public.stakeholders sh on sh.id=a.stakeholder_id and sh.status='active' where a.review_id=r.id and a.removed_at is null and coalesce(wm.user_id,sh.user_id)=p_user_id));end if;
 return false;end; $$;
CREATE OR REPLACE FUNCTION public.resolve_notification_router_targets()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_snap             jsonb;
  v_notification_type text;
  v_category         text;
  v_priority         text;
  v_channels         text[];
  v_recipients       uuid[];
  v_recipient_id     uuid;
  v_actor_display    text;
  v_deep_link        jsonb;
  v_deep_link_kind   text;
  v_deep_link_id     uuid;
  v_preview          text;
  v_payload          jsonb;
begin
  if new.event_type is null then
    return new;
  end if;

  -- F-2 explicit notification.* recursion guard (primary loop-guard).
  if new.event_type like 'notification.%' then
    return new;
  end if;

  begin
    v_snap := coalesce(new.subject_snapshot, '{}'::jsonb);
    v_channels := array['in_app']::text[];

    case
      when new.event_type in ('design.internal_review_requested','design.internal_review_decided') then
        v_notification_type:=new.event_type;v_category:='assigned_to_me';v_priority:='high';
        select array_agg(value::uuid) into v_recipients from jsonb_array_elements_text(new.payload->'recipient_ids');
      when new.event_type = 'review.opened' then
        v_notification_type := 'review.assigned_to_you';
        v_category := 'assigned_to_me'; v_priority := 'high';
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.review_participants rp
              left join public.workspace_members wm on wm.id = rp.workspace_member_id
              left join public.stakeholders sh on sh.id = rp.stakeholder_id
             where rp.review_id = new.subject_id
          ) p
         where p.profile_id is not null;

      when new.event_type = 'review.completed' then
        v_notification_type := 'review.your_review_completed';
        v_category := 'governance_state_change'; v_priority := 'medium';
        select array[created_by_profile_id]::uuid[] into v_recipients
          from public.reviews where id = new.subject_id;

      when new.event_type = 'review.cancelled' then
        v_notification_type := 'review.your_review_cancelled';
        v_category := 'governance_state_change'; v_priority := 'medium';
        select array[created_by_profile_id]::uuid[] into v_recipients
          from public.reviews where id = new.subject_id;

      when new.event_type = 'review.reviewer_responded' then
        v_notification_type := 'review.reviewer_responded_on_your_review';
        v_category := 'project_activity'; v_priority := 'medium';
        select array[r.created_by_profile_id]::uuid[] into v_recipients
          from public.reviews r
          join public.review_participants rp on rp.review_id = r.id
         where rp.id = new.subject_id;

      when new.event_type in ('approval.requested','approval.sent') then
        v_notification_type := 'approval.awaiting_your_decision';
        v_category := 'assigned_to_me'; v_priority := 'high';
        v_channels := array['in_app','email_payload']::text[];
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.approval_request_approvers ara
              left join public.workspace_members wm on wm.id = ara.workspace_member_id
              left join public.stakeholders sh on sh.id = ara.stakeholder_id
             where ara.approval_request_id = new.subject_id
          ) p
         where p.profile_id is not null;

      when new.event_type = 'approval.responded' then
        v_notification_type := 'approval.responded_on_your_request';
        v_category := 'project_activity'; v_priority := 'medium';
        select array[ar.created_by_profile_id]::uuid[] into v_recipients
          from public.approval_requests ar
         where ar.id = new.subject_id
            or ar.id = (v_snap->>'approval_request_id')::uuid;

      when new.event_type = 'approval.approved' then
        v_notification_type := 'approval.approved_your_request';
        v_category := 'governance_state_change'; v_priority := 'high';
        select array[created_by_profile_id]::uuid[] into v_recipients
          from public.approval_requests where id = new.subject_id;

      when new.event_type = 'approval.rejected' then
        v_notification_type := 'approval.rejected_your_request';
        v_category := 'governance_state_change'; v_priority := 'high';
        select array[created_by_profile_id]::uuid[] into v_recipients
          from public.approval_requests where id = new.subject_id;

      when new.event_type = 'approval.expired' then
        v_notification_type := 'approval.expired_your_request';
        v_category := 'governance_state_change'; v_priority := 'high';
        select array[created_by_profile_id]::uuid[] into v_recipients
          from public.approval_requests where id = new.subject_id;

      when new.event_type = 'approval.cancelled' then
        v_notification_type := 'approval.request_cancelled';
        v_category := 'governance_state_change'; v_priority := 'medium';
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.approval_request_approvers ara
              left join public.workspace_members wm on wm.id = ara.workspace_member_id
              left join public.stakeholders sh on sh.id = ara.stakeholder_id
             where ara.approval_request_id = new.subject_id
          ) p
         where p.profile_id is not null;

      when new.event_type = 'comment.mentioned' then
        v_notification_type := 'comment.mentioned_you';
        v_category := 'mentions'; v_priority := 'high';
        v_recipients := array[(v_snap->>'mentioned_profile_id')::uuid];

      when new.event_type = 'annotation.resolved' then
        v_notification_type := 'annotation.your_annotation_resolved';
        v_category := 'project_activity'; v_priority := 'low';
        select array[author_profile_id]::uuid[] into v_recipients
          from public.annotations where id = new.subject_id;

      when new.event_type = 'change.created' then
        v_notification_type := 'change.needs_leads_attention';
        v_category := 'project_activity'; v_priority := 'medium';
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.project_participants pp
              left join public.workspace_members wm on wm.id = pp.workspace_member_id
              left join public.stakeholders sh on sh.id = pp.stakeholder_id
             where pp.project_id = new.project_id
               and pp.role = 'lead'
               and pp.status = 'active'
          ) p
         where p.profile_id is not null;

      when new.event_type = 'change.accepted' then
        v_notification_type := 'change.your_change_accepted';
        v_category := 'governance_state_change'; v_priority := 'medium';
        select array[author_profile_id]::uuid[] into v_recipients
          from public.changes where id = new.subject_id;

      when new.event_type = 'change.rejected' then
        v_notification_type := 'change.your_change_rejected';
        v_category := 'governance_state_change'; v_priority := 'medium';
        select array[author_profile_id]::uuid[] into v_recipients
          from public.changes where id = new.subject_id;

      when new.event_type = 'change.withdrawn' then
        v_notification_type := 'change.your_change_withdrawn';
        v_category := 'governance_state_change'; v_priority := 'low';
        select array[author_profile_id]::uuid[] into v_recipients
          from public.changes where id = new.subject_id;

      when new.event_type = 'release.finalized' then
        v_notification_type := 'release.published_in_your_project';
        v_category := 'project_activity'; v_priority := 'medium';
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.project_participants pp
              left join public.workspace_members wm on wm.id = pp.workspace_member_id
              left join public.stakeholders sh on sh.id = pp.stakeholder_id
             where pp.project_id = new.project_id
               and pp.status = 'active'
          ) p
         where p.profile_id is not null;

      when new.event_type = 'release.withdrawn' then
        v_notification_type := 'release.withdrawn_in_your_project';
        v_category := 'governance_state_change'; v_priority := 'high';
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.project_participants pp
              left join public.workspace_members wm on wm.id = pp.workspace_member_id
              left join public.stakeholders sh on sh.id = pp.stakeholder_id
             where pp.project_id = new.project_id
               and pp.status = 'active'
          ) p
         where p.profile_id is not null;

      when new.event_type = 'asset.archived' then
        v_notification_type := 'asset.archived_in_your_project';
        v_category := 'project_activity'; v_priority := 'low';
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.project_participants pp
              left join public.workspace_members wm on wm.id = pp.workspace_member_id
              left join public.stakeholders sh on sh.id = pp.stakeholder_id
             where pp.project_id = new.project_id
               and pp.status = 'active'
          ) p
         where p.profile_id is not null;

      when new.event_type = 'asset.unarchived' then
        v_notification_type := 'asset.unarchived_in_your_project';
        v_category := 'project_activity'; v_priority := 'low';
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.project_participants pp
              left join public.workspace_members wm on wm.id = pp.workspace_member_id
              left join public.stakeholders sh on sh.id = pp.stakeholder_id
             where pp.project_id = new.project_id
               and pp.status = 'active'
          ) p
         where p.profile_id is not null;

      when new.event_type = 'project.archived' then
        v_notification_type := 'project.archived_in_your_project';
        v_category := 'governance_state_change'; v_priority := 'medium';
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.project_participants pp
              left join public.workspace_members wm on wm.id = pp.workspace_member_id
              left join public.stakeholders sh on sh.id = pp.stakeholder_id
             where pp.project_id = new.project_id
               and pp.status = 'active'
          ) p
         where p.profile_id is not null;

      when new.event_type = 'project.unarchived' then
        v_notification_type := 'project.unarchived_in_your_project';
        v_category := 'project_activity'; v_priority := 'low';
        select coalesce(array_agg(distinct p.profile_id), array[]::uuid[])
          into v_recipients
          from (
            select coalesce(wm.user_id, sh.user_id) as profile_id
              from public.project_participants pp
              left join public.workspace_members wm on wm.id = pp.workspace_member_id
              left join public.stakeholders sh on sh.id = pp.stakeholder_id
             where pp.project_id = new.project_id
               and pp.status = 'active'
          ) p
         where p.profile_id is not null;

      when new.event_type = 'project.participant.added' then
        v_notification_type := 'project.you_were_added';
        v_category := 'assigned_to_me'; v_priority := 'high';
        select array[coalesce(wm.user_id, sh.user_id)]::uuid[] into v_recipients
          from public.project_participants pp
          left join public.workspace_members wm on wm.id = pp.workspace_member_id
          left join public.stakeholders sh on sh.id = pp.stakeholder_id
         where pp.id = new.subject_id;

      when new.event_type = 'project.participant.role_changed' then
        v_notification_type := 'project.your_role_changed';
        v_category := 'governance_state_change'; v_priority := 'medium';
        select array[coalesce(wm.user_id, sh.user_id)]::uuid[] into v_recipients
          from public.project_participants pp
          left join public.workspace_members wm on wm.id = pp.workspace_member_id
          left join public.stakeholders sh on sh.id = pp.stakeholder_id
         where pp.id = new.subject_id;

      when new.event_type = 'project.participant.removed' then
        v_notification_type := 'project.you_were_removed';
        v_category := 'governance_state_change'; v_priority := 'high';
        v_recipients := array[nullif(v_snap->>'profile_id', '')::uuid];
        if v_recipients[1] is null then
          select array[coalesce(wm.user_id, sh.user_id)]::uuid[] into v_recipients
            from public.project_participants pp
            left join public.workspace_members wm on wm.id = pp.workspace_member_id
            left join public.stakeholders sh on sh.id = pp.stakeholder_id
           where pp.id = new.subject_id;
        end if;

      when new.event_type = 'workspace.member.invited' then
        v_recipients := array[]::uuid[];

      when new.event_type = 'workspace.member.activated' then
        v_notification_type := 'workspace.your_invitation_was_accepted';
        v_category := 'system'; v_priority := 'medium';
        v_recipients := array[nullif(v_snap->>'invited_by_profile_id', '')::uuid];

      when new.event_type = 'workspace.member.role_changed' then
        v_notification_type := 'workspace.your_role_changed';
        v_category := 'governance_state_change'; v_priority := 'high';
        select array[user_id]::uuid[] into v_recipients
          from public.workspace_members where id = new.subject_id;

      when new.event_type = 'workspace.member.suspended' then
        v_notification_type := 'workspace.you_were_suspended';
        v_category := 'governance_state_change'; v_priority := 'critical';
        v_channels := array['in_app','email_payload']::text[];
        select array[user_id]::uuid[] into v_recipients
          from public.workspace_members where id = new.subject_id;

      when new.event_type = 'workspace.member.removed' then
        v_notification_type := 'workspace.you_were_removed';
        v_category := 'governance_state_change'; v_priority := 'critical';
        v_channels := array['in_app','email_payload']::text[];
        v_recipients := array[nullif(v_snap->>'user_id', '')::uuid];

      when new.event_type = 'stakeholder.invited' then
        v_recipients := array[]::uuid[];

      when new.event_type = 'stakeholder.claimed' then
        v_notification_type := 'stakeholder.claimed_by_recipient';
        v_category := 'system'; v_priority := 'medium';
        v_recipients := array[nullif(v_snap->>'invited_by_profile_id', '')::uuid];

      when new.event_type = 'stakeholder.revoked' then
        v_notification_type := 'stakeholder.you_were_revoked';
        v_category := 'governance_state_change'; v_priority := 'high';
        select array[user_id]::uuid[] into v_recipients
          from public.stakeholders where id = new.subject_id;

      when new.event_type = 'invitation.expired' then
        v_notification_type := 'invitation.your_invitation_expired';
        v_category := 'system'; v_priority := 'low';
        v_recipients := array[nullif(v_snap->>'invited_by_profile_id', '')::uuid];

      else
        return new;
    end case;

    if v_recipients is null or array_length(v_recipients, 1) is null then
      return new;
    end if;

    if new.actor_profile_id is not null then
      select coalesce(display_name, 'Former member') into v_actor_display
        from public.profiles where id = new.actor_profile_id;
    else
      v_actor_display := 'System';
    end if;

    v_deep_link_kind := case when new.event_type in ('design.internal_review_requested','design.internal_review_decided') then 'version' else split_part(new.event_type,'.',1) end;
    v_deep_link_id := new.subject_id;
    v_deep_link := jsonb_build_object(
      'kind', v_deep_link_kind,
      'id', v_deep_link_id,
      'workspace_id', new.workspace_id,
      'project_id', new.project_id
    );

    v_preview := coalesce(new.subject_label, new.event_type);

    v_payload := jsonb_build_object(
      'source_event_type', new.event_type,
      'actor_profile_id', new.actor_profile_id,
      'actor_display_name', v_actor_display,
      'subject_kind', new.subject_kind,
      'subject_id', new.subject_id,
      'subject_label', new.subject_label,
      'occurred_at', new.occurred_at,
      'deep_link', v_deep_link,
      'preview_snippet', v_preview
    );

    foreach v_recipient_id in array v_recipients loop
      if not public.lign_design_notification_allowed(to_jsonb(new),v_recipient_id) then continue;end if;
      if v_recipient_id is null then
        continue;
      end if;
      if new.actor_profile_id is not null and v_recipient_id = new.actor_profile_id then
        continue;
      end if;

      -- ON CONFLICT with inference on partial unique index I-7 (must include WHERE).
      insert into public.notifications (
        workspace_id, project_id, recipient_profile_id, source_event_id,
        event_type, notification_type, category, priority,
        channels_attempted, delivery_state,
        subject_kind, subject_id, subject_label, actor_profile_id,
        payload
      ) values (
        new.workspace_id, new.project_id, v_recipient_id, new.id,
        new.event_type, v_notification_type, v_category, v_priority,
        v_channels, 'delivered',
        coalesce(new.subject_kind, v_deep_link_kind), new.subject_id,
        new.subject_label, new.actor_profile_id,
        v_payload
      )
      on conflict (recipient_profile_id, source_event_id, notification_type)
        where archived_at is null
        do nothing;
    end loop;

    return new;

  exception
    when others then
      raise warning 'notification router failed for event % (type %): %',
        new.id, new.event_type, sqlerrm;
      return new;
  end;
end;
$function$;
create policy vp_design_assets_scope on public.design_assets as restrictive for select to authenticated using(public.lign_design_row_visible('design_assets',to_jsonb(design_assets)));
create or replace view public.vp_read_design_assets with (security_barrier=true) as select t.* from public.design_assets t where public.lign_design_row_visible('design_assets',to_jsonb(t));
revoke all on public.vp_read_design_assets from public,anon,authenticated;
grant select on public.vp_read_design_assets to service_role;
create policy vp_asset_versions_scope on public.asset_versions as restrictive for select to authenticated using(public.lign_design_row_visible('asset_versions',to_jsonb(asset_versions)));
create or replace view public.vp_read_asset_versions with (security_barrier=true) as select t.* from public.asset_versions t where public.lign_design_row_visible('asset_versions',to_jsonb(t));
revoke all on public.vp_read_asset_versions from public,anon,authenticated;
grant select on public.vp_read_asset_versions to service_role;
create policy vp_version_files_scope on public.version_files as restrictive for select to authenticated using(public.lign_design_row_visible('version_files',to_jsonb(version_files)));
create or replace view public.vp_read_version_files with (security_barrier=true) as select t.* from public.version_files t where public.lign_design_row_visible('version_files',to_jsonb(t));
revoke all on public.vp_read_version_files from public,anon,authenticated;
grant select on public.vp_read_version_files to service_role;
create policy vp_files_scope on public.files as restrictive for select to authenticated using(public.lign_design_row_visible('files',to_jsonb(files)));
create or replace view public.vp_read_files with (security_barrier=true) as select t.* from public.files t where public.lign_design_row_visible('files',to_jsonb(t));
revoke all on public.vp_read_files from public,anon,authenticated;
grant select on public.vp_read_files to service_role;
create policy vp_collections_scope on public.collections as restrictive for select to authenticated using(public.lign_design_row_visible('collections',to_jsonb(collections)));
create or replace view public.vp_read_collections with (security_barrier=true) as select t.* from public.collections t where public.lign_design_row_visible('collections',to_jsonb(t));
revoke all on public.vp_read_collections from public,anon,authenticated;
grant select on public.vp_read_collections to service_role;
create policy vp_comments_scope on public.comments as restrictive for select to authenticated using(public.lign_design_row_visible('comments',to_jsonb(comments)));
create or replace view public.vp_read_comments with (security_barrier=true) as select t.* from public.comments t where public.lign_design_row_visible('comments',to_jsonb(t));
revoke all on public.vp_read_comments from public,anon,authenticated;
grant select on public.vp_read_comments to service_role;
create policy vp_comment_edits_scope on public.comment_edits as restrictive for select to authenticated using(public.lign_design_row_visible('comment_edits',to_jsonb(comment_edits)));
create or replace view public.vp_read_comment_edits with (security_barrier=true) as select t.* from public.comment_edits t where public.lign_design_row_visible('comment_edits',to_jsonb(t));
revoke all on public.vp_read_comment_edits from public,anon,authenticated;
grant select on public.vp_read_comment_edits to service_role;
create policy vp_annotations_scope on public.annotations as restrictive for select to authenticated using(public.lign_design_row_visible('annotations',to_jsonb(annotations)));
create or replace view public.vp_read_annotations with (security_barrier=true) as select t.* from public.annotations t where public.lign_design_row_visible('annotations',to_jsonb(t));
revoke all on public.vp_read_annotations from public,anon,authenticated;
grant select on public.vp_read_annotations to service_role;
create policy vp_changes_scope on public.changes as restrictive for select to authenticated using(public.lign_design_row_visible('changes',to_jsonb(changes)));
create or replace view public.vp_read_changes with (security_barrier=true) as select t.* from public.changes t where public.lign_design_row_visible('changes',to_jsonb(t));
revoke all on public.vp_read_changes from public,anon,authenticated;
grant select on public.vp_read_changes to service_role;
create policy vp_decisions_scope on public.decisions as restrictive for select to authenticated using(public.lign_design_row_visible('decisions',to_jsonb(decisions)));
create or replace view public.vp_read_decisions with (security_barrier=true) as select t.* from public.decisions t where public.lign_design_row_visible('decisions',to_jsonb(t));
revoke all on public.vp_read_decisions from public,anon,authenticated;
grant select on public.vp_read_decisions to service_role;
create policy vp_reviews_scope on public.reviews as restrictive for select to authenticated using(public.lign_design_row_visible('reviews',to_jsonb(reviews)));
create or replace view public.vp_read_reviews with (security_barrier=true) as select t.* from public.reviews t where public.lign_design_row_visible('reviews',to_jsonb(t));
revoke all on public.vp_read_reviews from public,anon,authenticated;
grant select on public.vp_read_reviews to service_role;
create policy vp_review_participants_scope on public.review_participants as restrictive for select to authenticated using(public.lign_design_row_visible('review_participants',to_jsonb(review_participants)));
create or replace view public.vp_read_review_participants with (security_barrier=true) as select t.* from public.review_participants t where public.lign_design_row_visible('review_participants',to_jsonb(t));
revoke all on public.vp_read_review_participants from public,anon,authenticated;
grant select on public.vp_read_review_participants to service_role;
create policy vp_approval_requests_scope on public.approval_requests as restrictive for select to authenticated using(public.lign_design_row_visible('approval_requests',to_jsonb(approval_requests)));
create or replace view public.vp_read_approval_requests with (security_barrier=true) as select t.* from public.approval_requests t where public.lign_design_row_visible('approval_requests',to_jsonb(t));
revoke all on public.vp_read_approval_requests from public,anon,authenticated;
grant select on public.vp_read_approval_requests to service_role;
create policy vp_approval_request_approvers_scope on public.approval_request_approvers as restrictive for select to authenticated using(public.lign_design_row_visible('approval_request_approvers',to_jsonb(approval_request_approvers)));
create or replace view public.vp_read_approval_request_approvers with (security_barrier=true) as select t.* from public.approval_request_approvers t where public.lign_design_row_visible('approval_request_approvers',to_jsonb(t));
revoke all on public.vp_read_approval_request_approvers from public,anon,authenticated;
grant select on public.vp_read_approval_request_approvers to service_role;
create policy vp_approval_responses_scope on public.approval_responses as restrictive for select to authenticated using(public.lign_design_row_visible('approval_responses',to_jsonb(approval_responses)));
create or replace view public.vp_read_approval_responses with (security_barrier=true) as select t.* from public.approval_responses t where public.lign_design_row_visible('approval_responses',to_jsonb(t));
revoke all on public.vp_read_approval_responses from public,anon,authenticated;
grant select on public.vp_read_approval_responses to service_role;
create policy vp_releases_scope on public.releases as restrictive for select to authenticated using(public.lign_design_row_visible('releases',to_jsonb(releases)));
create or replace view public.vp_read_releases with (security_barrier=true) as select t.* from public.releases t where public.lign_design_row_visible('releases',to_jsonb(t));
revoke all on public.vp_read_releases from public,anon,authenticated;
grant select on public.vp_read_releases to service_role;
create policy vp_release_items_scope on public.release_items as restrictive for select to authenticated using(public.lign_design_row_visible('release_items',to_jsonb(release_items)));
create or replace view public.vp_read_release_items with (security_barrier=true) as select t.* from public.release_items t where public.lign_design_row_visible('release_items',to_jsonb(t));
revoke all on public.vp_read_release_items from public,anon,authenticated;
grant select on public.vp_read_release_items to service_role;
create policy vp_version_requirement_assessments_scope on public.version_requirement_assessments as restrictive for select to authenticated using(public.lign_design_row_visible('version_requirement_assessments',to_jsonb(version_requirement_assessments)));
create or replace view public.vp_read_version_requirement_assessments with (security_barrier=true) as select t.* from public.version_requirement_assessments t where public.lign_design_row_visible('version_requirement_assessments',to_jsonb(t));
revoke all on public.vp_read_version_requirement_assessments from public,anon,authenticated;
grant select on public.vp_read_version_requirement_assessments to service_role;
create policy vp_deliverable_submissions_scope on public.deliverable_submissions as restrictive for select to authenticated using(public.lign_design_row_visible('deliverable_submissions',to_jsonb(deliverable_submissions)));
create or replace view public.vp_read_deliverable_submissions with (security_barrier=true) as select t.* from public.deliverable_submissions t where public.lign_design_row_visible('deliverable_submissions',to_jsonb(t));
revoke all on public.vp_read_deliverable_submissions from public,anon,authenticated;
grant select on public.vp_read_deliverable_submissions to service_role;
create policy vp_deliverable_submission_events_scope on public.deliverable_submission_events as restrictive for select to authenticated using(public.lign_design_row_visible('deliverable_submission_events',to_jsonb(deliverable_submission_events)));
create or replace view public.vp_read_deliverable_submission_events with (security_barrier=true) as select t.* from public.deliverable_submission_events t where public.lign_design_row_visible('deliverable_submission_events',to_jsonb(t));
revoke all on public.vp_read_deliverable_submission_events from public,anon,authenticated;
grant select on public.vp_read_deliverable_submission_events to service_role;
create policy vp_activity_events_scope on public.activity_events as restrictive for select to authenticated using(public.lign_design_row_visible('activity_events',to_jsonb(activity_events)));
create or replace view public.vp_read_activity_events with (security_barrier=true) as select t.* from public.activity_events t where public.lign_design_row_visible('activity_events',to_jsonb(t));
revoke all on public.vp_read_activity_events from public,anon,authenticated;
grant select on public.vp_read_activity_events to service_role;
create policy vp_notifications_scope on public.notifications as restrictive for select to authenticated using(public.lign_design_row_visible('notifications',to_jsonb(notifications)));
create or replace view public.vp_read_notifications with (security_barrier=true) as select t.* from public.notifications t where public.lign_design_row_visible('notifications',to_jsonb(t));
revoke all on public.vp_read_notifications from public,anon,authenticated;
grant select on public.vp_read_notifications to service_role;
create policy vp_proposal_revisions_scope on public.proposal_revisions as restrictive for select to authenticated using(public.lign_design_row_visible('proposal_revisions',to_jsonb(proposal_revisions)));
create or replace view public.vp_read_proposal_revisions with (security_barrier=true) as select t.id,t.proposal_id,t.project_id,t.workspace_id,t.number,t.brief_revision_id,t.document,t.snapshot,t.respondent_id,t.reviewed_by,case when public.lign_design_team(t.project_id) then t.review_note else '' end as review_note,t.created_at from public.proposal_revisions t where public.lign_design_row_visible('proposal_revisions',to_jsonb(t));
revoke all on public.vp_read_proposal_revisions from public,anon,authenticated;
grant select on public.vp_read_proposal_revisions to service_role;
create policy vp_proposal_decisions_scope on public.proposal_decisions as restrictive for select to authenticated using(public.lign_design_row_visible('proposal_decisions',to_jsonb(proposal_decisions)));
create or replace view public.vp_read_proposal_decisions with (security_barrier=true) as select t.* from public.proposal_decisions t where public.lign_design_row_visible('proposal_decisions',to_jsonb(t));
revoke all on public.vp_read_proposal_decisions from public,anon,authenticated;
grant select on public.vp_read_proposal_decisions to service_role;
revoke select on public.proposal_revisions from authenticated;
grant select(id,proposal_id,project_id,workspace_id,number,brief_revision_id,document,snapshot,respondent_id,reviewed_by,created_at) on public.proposal_revisions to authenticated;
CREATE OR REPLACE FUNCTION public.get_studio_overview(p_organization_id uuid DEFAULT NULL::uuid, p_workspace_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_org uuid; v_workspaces jsonb; v_activity jsonb;
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
   raise exception 'Studio ownership or administration required' using errcode='42501';
  end if;
 end if;

 select coalesce(jsonb_agg(row_data order by workspace_name),'[]'::jsonb) into v_workspaces
 from (
  select w.name workspace_name,jsonb_build_object(
   'id',w.id,'name',w.name,'status',w.status,
   'teamCount',(select count(*) from public.workspace_members wm where wm.workspace_id=w.id and wm.status='active'),
   'leads',(select coalesce(jsonb_agg(jsonb_build_object('userId',wm.user_id,'name',p.display_name,'role',wm.role) order by wm.role,p.display_name),'[]'::jsonb)
      from public.workspace_members wm join public.profiles p on p.id=wm.user_id
     where wm.workspace_id=w.id and wm.status='active' and wm.role in ('owner','admin')),
   'projects',(select coalesce(jsonb_agg(jsonb_build_object(
    'id',pr.id,'name',pr.name,'status',pr.status,'code',pr.code,'updatedAt',pr.updated_at,
    'leads',(select coalesce(jsonb_agg(jsonb_build_object('name',coalesce(p.display_name,sh.display_name,sh.email::text),'userId',coalesce(wm.user_id,sh.user_id))),'[]'::jsonb)
       from public.project_participants pp
       left join public.workspace_members wm on wm.id=pp.workspace_member_id
       left join public.profiles p on p.id=wm.user_id
       left join public.stakeholders sh on sh.id=pp.stakeholder_id
      where pp.project_id=pr.id and pp.status='active' and pp.role='lead'),
    'pendingReviews',(select count(*) from public.vp_read_reviews r where r.project_id=pr.id and r.status in ('ready_for_review','open','in_progress','waiting')),
    'pendingApprovals',(select count(*) from public.vp_read_approval_requests a where a.project_id=pr.id and a.status in ('pending','in_progress')),
    'latestActivityAt',coalesce((select max(e.occurred_at) from public.vp_read_activity_events e where e.workspace_id=w.id and e.project_id=pr.id),pr.updated_at)
   ) order by pr.updated_at desc),'[]'::jsonb)
    from public.projects pr where pr.workspace_id=w.id and pr.archived_at is null)
  ) row_data
  from public.workspaces w where w.organization_id=v_org and w.status='active'
   and (p_workspace_id is null or w.id=p_workspace_id)
 ) ws;

 select coalesce(jsonb_agg(row_data order by occurred_at desc),'[]'::jsonb) into v_activity from (
  select e.occurred_at,jsonb_build_object('id',e.id,'occurredAt',e.occurred_at,'eventType',e.event_type,
   'subject',e.subject_label,'actor',coalesce(p.display_name,'System'),
   'workspaceId',e.workspace_id,'workspaceName',w.name,'projectId',e.project_id) row_data
   from public.vp_read_activity_events e join public.workspaces w on w.id=e.workspace_id
   left join public.profiles p on p.id=e.actor_profile_id
  where w.organization_id=v_org and w.status='active' and (p_workspace_id is null or w.id=p_workspace_id)
  order by e.occurred_at desc limit 20
 ) events;
 return jsonb_build_object('organizationId',v_org,'organizationName',(select name from public.organizations where id=v_org),
   'workspaces',v_workspaces,'activity',v_activity);
end;
$function$;
CREATE OR REPLACE FUNCTION public.get_project_proposal(p_project_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v public.project_proposals%rowtype;v_ws uuid;v_team boolean;v_current public.proposal_revisions%rowtype;begin
 select workspace_id into v_ws from public.projects where id=p_project_id;
 if v_ws is null or not public.lign_has_capability(p_project_id,v_ws,'project.view') then raise exception 'Project access required' using errcode='42501';end if;
 select * into v from public.project_proposals where project_id=p_project_id;
 select * into v_current from public.vp_read_proposal_revisions proposal_revisions where id=v.current_revision_id;
 v_team:=public.lign_prepare_proposal(p_project_id);
 return jsonb_build_object('briefReady',public.lign_project_has_agreed_brief(p_project_id),'designReady',public.lign_project_ready_for_design(p_project_id),
 'canPrepare',v_team,'canReview',v_team and public.lign_manage_project_brief(p_project_id) and v.created_by is distinct from auth.uid(),'canManage',public.lign_manage_project_brief(p_project_id),
 'canRespond',v.status='awaiting_acceptance' and public.lign_brief_respondent_user(v_current.respondent_id,p_project_id)=auth.uid() and v_current.reviewed_by<>auth.uid(),
 'working',case when v_team and v.id is not null then to_jsonb(v) else null end,'status',case when v_team or public.lign_can_read_proposal_revision(v.current_revision_id) then v.status else null end,'currentRevisionId',case when v_team or public.lign_can_read_proposal_revision(v.current_revision_id) then v.current_revision_id else null end,
 'agreedBriefs',case when v_team then (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'number',r.number,'at',r.created_at) order by r.number desc),'[]'::jsonb) from public.project_brief_revisions r join public.project_brief_decisions d on d.revision_id=r.id where r.project_id=p_project_id and d.decision='agreed') else '[]'::jsonb end,
 'approvers',case when v_team then (select coalesce(jsonb_agg(jsonb_build_object('id',pp.id,'name',p.display_name) order by p.display_name),'[]'::jsonb) from public.project_participants pp join public.profiles p on p.id=public.lign_brief_respondent_user(pp.id,p_project_id) where pp.project_id=p_project_id and pp.role='approver' and pp.status='active') else '[]'::jsonb end,
 'files',case when v_team then (select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'path',f.storage_path,'name',f.name,'mime',f.mime_type,'size',f.size_bytes) order by f.created_at),'[]'::jsonb) from public.planning_files f where f.proposal_id=v.id and f.registered_at is not null and f.removed_at is null) else '[]'::jsonb end,
 'revisions',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'number',r.number,'createdAt',r.created_at,'reviewedBy',p.display_name,'reviewNote',r.review_note,'decision',(select to_jsonb(d)||jsonb_build_object('name',dp.display_name) from public.vp_read_proposal_decisions d join public.profiles dp on dp.id=d.actor_id where d.revision_id=r.id)) order by r.number desc),'[]'::jsonb) from public.vp_read_proposal_revisions r join public.profiles p on p.id=r.reviewed_by where r.project_id=p_project_id));
 end; $function$;
CREATE OR REPLACE FUNCTION public.get_project_review_metrics(p_proj_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ws uuid; v_out int; v_over int;
begin
  select workspace_id into v_ws from public.projects where id = p_proj_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(p_proj_id, v_ws, 'review.view') then
    raise exception 'get_project_review_metrics: forbidden (review.view)' using errcode='42501';
  end if;

  select count(*) into v_out from public.vp_read_reviews reviews
    where project_id = p_proj_id and status in ('open','in_progress','waiting','ready_for_review');
  select count(*) into v_over from public.vp_read_reviews reviews
    where project_id = p_proj_id
      and due_at is not null and due_at < now()
      and status in ('open','in_progress','waiting');

  return jsonb_build_object(
    'outstanding_count', v_out,
    'overdue_count', v_over
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_release_by_code(p_project_id uuid, p_ws_id uuid, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  if not public.lign_has_capability(p_project_id, p_ws_id, 'release.view') then
    raise exception 'get_release_by_code: forbidden (release.view)' using errcode='42501';
  end if;
  select id into v_id from public.vp_read_releases releases
   where project_id = p_project_id and workspace_id = p_ws_id and code = p_code;
  if v_id is null then return null; end if;
  return public.get_release(v_id);
end $function$;
CREATE OR REPLACE FUNCTION public.get_notification(p_notification_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid;
  v_row public.notifications%rowtype;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'get_notification: authentication required' using errcode='42501';
  end if;
  if not public.lign_has_capability(null, null, 'notification.view') then
    raise exception 'get_notification: forbidden (notification.view)' using errcode='42501';
  end if;

  select * into v_row
    from public.vp_read_notifications notifications
   where id = p_notification_id
     and recipient_profile_id = v_uid;

  if v_row.id is null then
    return null;
  end if;

  return to_jsonb(v_row);
end $function$;
CREATE OR REPLACE FUNCTION public.list_applicable_requirements(p_design_asset_id uuid, p_asset_version_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(out_requirement_id uuid, out_code text, out_title text, out_status text, out_parent_requirement_id uuid, out_is_project_wide boolean, out_assessment_status text, out_assessed_at timestamp with time zone, out_assessed_by_profile_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ws uuid; v_pj uuid; v_coll uuid;
begin
  if auth.uid() is null then raise exception 'list_applicable_requirements: authentication required' using errcode='42501'; end if;
  select workspace_id, project_id, collection_id into v_ws, v_pj, v_coll
    from public.vp_read_design_assets design_assets where id = p_design_asset_id;
  if v_ws is null then raise exception 'list_applicable_requirements: design_asset % not found', p_design_asset_id using errcode='23503'; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.view') then
    raise exception 'list_applicable_requirements: forbidden (requirement.view)' using errcode='42501';
  end if;
  if p_asset_version_id is not null then
    perform 1 from public.vp_read_asset_versions asset_versions where id = p_asset_version_id and design_asset_id = p_design_asset_id;
    if not found then
      raise exception 'list_applicable_requirements: asset_version % is not part of design_asset %', p_asset_version_id, p_design_asset_id using errcode='23514';
    end if;
  end if;
  return query
    with root_scoped as (
      select r.id, r.code, r.title, r.status, r.parent_requirement_id, coalesce(r.parent_requirement_id, r.id) as effective_root_id
        from public.requirements r where r.project_id = v_pj and r.status in ('draft','active')
    ),
    all_project_roots as (
      select id from public.requirements where project_id = v_pj and parent_requirement_id is null and status in ('draft','active')
    ),
    -- The spaces this asset belongs to. Exactly one today; its ancestors too
    -- once collections nest. Empty when the asset sits in no collection, which
    -- keeps such assets on precisely the old behaviour.
    ancestry as (
      select v_coll as collection_id where v_coll is not null
    ),
    scoped_root_ids as (
      select distinct requirement_id as root_id from public.requirement_design_assets where design_asset_id = p_design_asset_id
    ),
    collection_root_ids as (
      select distinct rc.requirement_id as root_id
        from public.requirement_collections rc
        join ancestry a on a.collection_id = rc.collection_id
    ),
    root_wide as (
      select id from all_project_roots where id not in (
        select requirement_id from public.requirement_design_assets where requirement_id in (select id from all_project_roots)
        union
        select requirement_id from public.requirement_collections where requirement_id in (select id from all_project_roots)
      )
    ),
    applicable_root_ids as (
      select id from root_wide
      union select root_id as id from scoped_root_ids
      union select root_id as id from collection_root_ids
    )
    select rs.id, rs.code, rs.title, rs.status, rs.parent_requirement_id,
           (rs.effective_root_id in (select id from root_wide)) as is_pw,
           a.status, a.assessed_at, a.assessed_by_profile_id
      from root_scoped rs
      left join public.vp_read_version_requirement_assessments a
             on a.asset_version_id = p_asset_version_id and a.requirement_id = rs.id
     where rs.effective_root_id in (select id from applicable_root_ids)
     order by rs.code;
end $function$;
CREATE OR REPLACE FUNCTION public.get_deliverable_submissions(p_project_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ws uuid;
begin
 select workspace_id into v_ws from public.projects where id=p_project_id;
 if v_ws is null or not public.lign_has_capability(p_project_id,v_ws,'project.view') then raise exception 'Project access required' using errcode='42501'; end if;
 return jsonb_build_object('canSubmit',public.lign_can_submit_deliverables(p_project_id),
  'canReview',public.lign_has_capability(p_project_id,v_ws,'version.publish') and exists(select 1 from public.projects where id=p_project_id and archived_at is null and status<>'archived'),
  'assets',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.name) order by a.name),'[]'::jsonb) from public.vp_read_design_assets a where a.project_id=p_project_id and a.archived_at is null and a.status<>'archived'),
  'submissions',(select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('authorName',p.display_name,'versionSequence',v.sequence,'versionStatus',v.status,'isCurrent',coalesce((select a.current_version_id=s.asset_version_id from public.vp_read_design_assets a where a.id=s.asset_id),false),
   'childId',(select id from public.vp_read_deliverable_submissions child where child.parent_submission_id=s.id),
   'events',(select coalesce(jsonb_agg(to_jsonb(e)||jsonb_build_object('actorName',ep.display_name) order by e.created_at),'[]'::jsonb) from public.vp_read_deliverable_submission_events e join public.profiles ep on ep.id=e.actor_id where e.submission_id=s.id)) order by s.created_at desc),'[]'::jsonb)
   from public.vp_read_deliverable_submissions s join public.profiles p on p.id=s.author_id join public.vp_read_asset_versions v on v.id=s.asset_version_id where s.project_id=p_project_id));
end; $function$;
CREATE OR REPLACE FUNCTION public.get_version_assessments(p_asset_version_id uuid)
 RETURNS TABLE(out_assessment_id uuid, out_requirement_id uuid, out_code text, out_title text, out_status text, out_note text, out_assessed_by_profile_id uuid, out_assessed_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ws uuid; v_pj uuid;
begin
  if auth.uid() is null then raise exception 'get_version_assessments: authentication required' using errcode='42501'; end if;
  select workspace_id, project_id into v_ws, v_pj from public.vp_read_asset_versions asset_versions where id = p_asset_version_id;
  if v_ws is null then raise exception 'get_version_assessments: asset_version % not found', p_asset_version_id using errcode='23503'; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.view') then
    raise exception 'get_version_assessments: forbidden (requirement.view)' using errcode='42501';
  end if;
  return query
    select a.id, a.requirement_id, r.code, r.title, a.status, a.note, a.assessed_by_profile_id, a.assessed_at
      from public.vp_read_version_requirement_assessments a
      join public.requirements r on r.id = a.requirement_id
     where a.asset_version_id = p_asset_version_id
     order by r.code;
end $function$;
CREATE OR REPLACE FUNCTION public.list_reviews_dashboard(p_ws_id uuid, p_proj_id uuid DEFAULT NULL::uuid, p_view text DEFAULT 'recent'::text, p_status_filter text[] DEFAULT NULL::text[], p_owner_ids uuid[] DEFAULT NULL::uuid[], p_reviewer_profile_ids uuid[] DEFAULT NULL::uuid[], p_cursor_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 30)
 RETURNS TABLE(out_id uuid, out_workspace_id uuid, out_project_id uuid, out_design_asset_id uuid, out_version_id uuid, out_title text, out_description text, out_status text, out_round_number integer, out_root_review_id uuid, out_policy text, out_created_by_profile_id uuid, out_coordinator_profile_id uuid, out_due_at timestamp with time zone, out_completed_at timestamp with time zone, out_cancelled_at timestamp with time zone, out_created_at timestamp with time zone, out_updated_at timestamp with time zone, out_open_reviewer_count integer, out_signed_off_count integer, out_declined_count integer, out_commented_count integer, out_total_reviewer_count integer, out_open_comment_count integer, out_overdue_flag boolean, out_my_slot_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_caller uuid; v_lim int;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'list_reviews_dashboard: authentication required' using errcode='42501'; end if;
  if p_ws_id is null then raise exception 'list_reviews_dashboard: ws_id required' using errcode='22004'; end if;
  v_lim := greatest(1, least(coalesce(p_limit, 30), 100));

  return query
    with visible as (
      select r.*
        from public.vp_read_reviews r
       where r.workspace_id = p_ws_id
         and (p_proj_id is null or r.project_id = p_proj_id)
         and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
    ),
    filtered as (
      select v.*
        from visible v
       where (p_status_filter is null or v.status = any(p_status_filter))
         and (p_owner_ids is null or v.created_by_profile_id = any(p_owner_ids))
         and (
           p_reviewer_profile_ids is null
           or exists (
             select 1 from public.vp_read_review_participants rp
              left join public.workspace_members wm on wm.id = rp.workspace_member_id
              left join public.stakeholders sh on sh.id = rp.stakeholder_id
              where rp.review_id = v.id
                and rp.removed_at is null
                and coalesce(wm.user_id, sh.user_id) = any(p_reviewer_profile_ids)
           )
         )
         and case p_view
           when 'assigned_to_me' then exists (
             select 1 from public.vp_read_review_participants rp
              left join public.workspace_members wm on wm.id = rp.workspace_member_id
              left join public.stakeholders sh on sh.id = rp.stakeholder_id
              where rp.review_id = v.id
                and rp.removed_at is null
                and rp.status = 'pending'
                and coalesce(wm.user_id, sh.user_id) = v_caller
           ) and v.status in ('open','in_progress','waiting')
           when 'waiting_on_others' then v.created_by_profile_id = v_caller
                                        and v.status in ('open','in_progress','waiting')
           when 'overdue' then v.due_at is not null and v.due_at < now()
                              and v.status in ('open','in_progress','waiting')
           when 'completed' then v.status = 'completed'
                                and (
                                  v.created_by_profile_id = v_caller
                                  or exists (
                                    select 1 from public.vp_read_review_participants rp
                                     left join public.workspace_members wm on wm.id = rp.workspace_member_id
                                     left join public.stakeholders sh on sh.id = rp.stakeholder_id
                                     where rp.review_id = v.id
                                       and coalesce(wm.user_id, sh.user_id) = v_caller
                                  )
                                )
           when 'bookmarks' then exists (
             select 1 from public.user_bookmarks b
              where b.user_id = v_caller
                and b.subject_kind = 'review'
                and b.subject_id = v.id
           )
           else true
         end
    )
    select
      f.id, f.workspace_id, f.project_id, f.design_asset_id, f.version_id,
      f.title, f.description, f.status, f.round_number, f.root_review_id, f.policy,
      f.created_by_profile_id, f.coordinator_profile_id,
      f.due_at, f.completed_at, f.cancelled_at, f.created_at, f.updated_at,
      (select count(*)::int from public.vp_read_review_participants review_participants
        where review_id = f.id and status = 'pending' and removed_at is null),
      (select count(*)::int from public.vp_read_review_participants review_participants
        where review_id = f.id and status = 'signed_off' and removed_at is null),
      (select count(*)::int from public.vp_read_review_participants review_participants
        where review_id = f.id and status = 'declined' and removed_at is null),
      (select count(*)::int from public.vp_read_review_participants review_participants
        where review_id = f.id and status = 'commented' and removed_at is null),
      (select count(*)::int from public.vp_read_review_participants review_participants
        where review_id = f.id and removed_at is null),
      (select count(*)::int from public.vp_read_comments comments
        where target_review_id = f.id
          and parent_comment_id is null
          and resolved_at is null
          and deleted_at is null),
      (f.due_at is not null and f.due_at < now() and f.status in ('open','in_progress','waiting')),
      (select rp.status from public.vp_read_review_participants rp
        left join public.workspace_members wm on wm.id = rp.workspace_member_id
        left join public.stakeholders sh on sh.id = rp.stakeholder_id
        where rp.review_id = f.id
          and rp.removed_at is null
          and coalesce(wm.user_id, sh.user_id) = v_caller
        limit 1)
    from filtered f
    where (p_cursor_updated_at is null
           or (f.updated_at, f.id) < (p_cursor_updated_at, p_cursor_id))
    order by f.updated_at desc, f.id desc
    limit v_lim;
end $function$;
CREATE OR REPLACE FUNCTION public.get_review(p_review_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_caller uuid; v_row jsonb; v_participants jsonb; v_metrics jsonb;
        v_ws uuid; v_proj uuid; v_asset uuid; v_version uuid;
        v_opened_at timestamptz; v_first_resp_at timestamptz; v_first_comm_at timestamptz;
        v_newer_exists boolean; v_chain jsonb;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_review: authentication required' using errcode='42501'; end if;

  select r.workspace_id, r.project_id, r.design_asset_id, r.version_id
    into v_ws, v_proj, v_asset, v_version
    from public.vp_read_reviews r where r.id = p_review_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(v_proj, v_ws, 'review.view') then
    raise exception 'get_review: forbidden (review.view)' using errcode='42501';
  end if;

  select to_jsonb(r) into v_row from public.vp_read_reviews r where r.id = p_review_id;

  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_participants
  from (
    select rp.id, rp.workspace_member_id, rp.stakeholder_id,
           rp.status, rp.assigned_at, rp.responded_at,
           rp.required, rp.sequence_index, rp.removed_at, rp.removed_reason,
           coalesce(wm_p.display_name, sh_p.display_name, sh.display_name) as display_name,
           coalesce(wm_p.avatar_url, sh_p.avatar_url) as avatar_url,
           coalesce(wm.user_id, sh.user_id) as profile_id,
           case when rp.workspace_member_id is not null then 'member' else 'stakeholder' end as identity
      from public.vp_read_review_participants rp
      left join public.workspace_members wm on wm.id = rp.workspace_member_id
      left join public.stakeholders sh on sh.id = rp.stakeholder_id
      left join public.profiles wm_p on wm_p.id = wm.user_id
      left join public.profiles sh_p on sh_p.id = sh.user_id
     where rp.review_id = p_review_id
     order by rp.sequence_index asc, rp.assigned_at asc
  ) x;

  select min(ae.occurred_at) into v_opened_at
    from public.vp_read_activity_events ae
   where ae.subject_kind = 'review' and ae.subject_id = p_review_id
     and ae.event_type = 'review.opened';

  select min(ae.occurred_at) into v_first_resp_at
    from public.vp_read_activity_events ae
   where ae.subject_kind = 'review_participant'
     and (ae.payload->>'review_id')::uuid = p_review_id
     and ae.event_type = 'review.reviewer_responded';

  select min(c.created_at) into v_first_comm_at
    from public.vp_read_comments c
   where c.target_review_id = p_review_id and c.deleted_at is null;

  select v_version is not null and exists (
    select 1 from public.vp_read_asset_versions av2
     where av2.design_asset_id = v_asset
       and av2.status = 'published'
       and av2.published_at > coalesce((select published_at from public.vp_read_asset_versions asset_versions where id = v_version), '-infinity'::timestamptz)
  ) into v_newer_exists;

  v_metrics := jsonb_build_object(
    'opened_at', v_opened_at,
    'first_responded_at', v_first_resp_at,
    'first_commented_at', v_first_comm_at,
    'open_comment_count', (
      select count(*) from public.vp_read_comments comments
       where target_review_id = p_review_id
         and parent_comment_id is null
         and resolved_at is null
         and deleted_at is null
    ),
    'response_distribution', (
      select jsonb_build_object(
        'signed_off', count(*) filter (where status='signed_off'),
        'commented',  count(*) filter (where status='commented'),
        'declined',   count(*) filter (where status='declined'),
        'pending',    count(*) filter (where status='pending')
      ) from public.vp_read_review_participants review_participants where review_id = p_review_id and removed_at is null
    ),
    'newer_version_exists', v_newer_exists
  );

  select jsonb_build_object(
    'round_number', (v_row->>'round_number')::int,
    'is_latest', not exists (
      select 1 from public.vp_read_reviews r2
       where r2.parent_review_id = p_review_id
    ),
    'prior_review_id', (v_row->>'parent_review_id')::uuid,
    'next_review_id', (
      select r2.id from public.vp_read_reviews r2
       where r2.parent_review_id = p_review_id
       limit 1
    )
  ) into v_chain;

  return jsonb_build_object(
    'review', v_row,
    'participants', v_participants,
    'metrics', v_metrics,
    'chain_position', v_chain
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_review_chain(p_root_review_id uuid)
 RETURNS TABLE(out_id uuid, out_round_number integer, out_status text, out_title text, out_created_at timestamp with time zone, out_completed_at timestamp with time zone, out_cancelled_at timestamp with time zone, out_reviewer_count integer, out_signed_off_count integer, out_declined_count integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_caller uuid; v_ws uuid; v_proj uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_review_chain: authentication required' using errcode='42501'; end if;

  select workspace_id, project_id into v_ws, v_proj
    from public.vp_read_reviews reviews where id = p_root_review_id;
  if v_ws is null then return; end if;
  if not public.lign_has_capability(v_proj, v_ws, 'review.view') then
    raise exception 'get_review_chain: forbidden (review.view)' using errcode='42501';
  end if;

  return query
    select r.id, r.round_number, r.status, r.title,
           r.created_at, r.completed_at, r.cancelled_at,
           (select count(*)::int from public.vp_read_review_participants review_participants
             where review_id = r.id and removed_at is null),
           (select count(*)::int from public.vp_read_review_participants review_participants
             where review_id = r.id and status='signed_off' and removed_at is null),
           (select count(*)::int from public.vp_read_review_participants review_participants
             where review_id = r.id and status='declined' and removed_at is null)
      from public.vp_read_reviews r
     where r.root_review_id = p_root_review_id or r.id = p_root_review_id
     order by r.round_number asc;
end $function$;
CREATE OR REPLACE FUNCTION public.get_review_inbox_count(p_ws_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_caller uuid; v_assigned int; v_overdue int; v_coord int;
begin
  v_caller := auth.uid();
  if v_caller is null then return jsonb_build_object('assigned_to_me',0,'overdue',0,'coordinating',0); end if;
  if p_ws_id is null then return jsonb_build_object('assigned_to_me',0,'overdue',0,'coordinating',0); end if;

  select count(*) into v_assigned
    from public.vp_read_reviews r
    join public.vp_read_review_participants rp on rp.review_id = r.id
    left join public.workspace_members wm on wm.id = rp.workspace_member_id
    left join public.stakeholders sh on sh.id = rp.stakeholder_id
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
     and rp.removed_at is null
     and rp.status = 'pending'
     and r.status in ('open','in_progress','waiting')
     and coalesce(wm.user_id, sh.user_id) = v_caller;

  select count(*) into v_overdue
    from public.vp_read_reviews r
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
     and r.due_at is not null
     and r.due_at < now()
     and r.status in ('open','in_progress','waiting');

  select count(*) into v_coord
    from public.vp_read_reviews r
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
     and r.status in ('open','in_progress','waiting')
     and (r.coordinator_profile_id = v_caller or (r.coordinator_profile_id is null and r.created_by_profile_id = v_caller));

  return jsonb_build_object(
    'assigned_to_me', v_assigned,
    'overdue', v_overdue,
    'coordinating', v_coord
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_workspace_review_metrics(p_ws_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_caller uuid; v_out int; v_over int;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_workspace_review_metrics: authentication required' using errcode='42501'; end if;
  if p_ws_id is null then return null; end if;

  select count(*) into v_out from public.vp_read_reviews r
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
     and r.status in ('open','in_progress','waiting','ready_for_review');

  select count(*) into v_over from public.vp_read_reviews r
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
     and r.due_at is not null and r.due_at < now()
     and r.status in ('open','in_progress','waiting');

  return jsonb_build_object(
    'outstanding_count', v_out,
    'overdue_count', v_over
  );
end $function$;
CREATE OR REPLACE FUNCTION public.list_approvals_dashboard(p_ws_id uuid, p_proj_id uuid DEFAULT NULL::uuid, p_view text DEFAULT 'recent'::text, p_status_filter text[] DEFAULT NULL::text[], p_policy_filter text[] DEFAULT NULL::text[], p_requester_ids uuid[] DEFAULT NULL::uuid[], p_approver_profile_ids uuid[] DEFAULT NULL::uuid[], p_cursor_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 30)
 RETURNS TABLE(out_id uuid, out_workspace_id uuid, out_project_id uuid, out_design_asset_id uuid, out_version_id uuid, out_title text, out_description text, out_status text, out_policy text, out_quorum_min integer, out_root_approval_request_id uuid, out_supersedes_approval_request_id uuid, out_related_review_id uuid, out_created_by_profile_id uuid, out_due_at timestamp with time zone, out_expires_at timestamp with time zone, out_sent_at timestamp with time zone, out_outcome_at timestamp with time zone, out_created_at timestamp with time zone, out_updated_at timestamp with time zone, out_pending_count integer, out_approved_count integer, out_rejected_count integer, out_abstained_count integer, out_total_approver_count integer, out_has_veto_approver boolean, out_overdue_flag boolean, out_my_slot_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_caller uuid; v_lim int;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'list_approvals_dashboard: authentication required' using errcode='42501'; end if;
  if p_ws_id is null then raise exception 'list_approvals_dashboard: ws_id required' using errcode='22004'; end if;
  v_lim := greatest(1, least(coalesce(p_limit, 30), 100));

  return query
    with visible as (
      select ar.*
        from public.vp_read_approval_requests ar
       where ar.workspace_id = p_ws_id
         and (p_proj_id is null or ar.project_id = p_proj_id)
         and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
    ),
    filtered as (
      select v.*
        from visible v
       where (p_status_filter is null or v.status = any(p_status_filter))
         and (p_policy_filter is null or v.policy = any(p_policy_filter))
         and (p_requester_ids is null or v.created_by_profile_id = any(p_requester_ids))
         and (
           p_approver_profile_ids is null
           or exists (
             select 1 from public.vp_read_approval_request_approvers a
              left join public.workspace_members wm on wm.id = a.workspace_member_id
              left join public.stakeholders sh on sh.id = a.stakeholder_id
              where a.approval_request_id = v.id
                and a.removed_at is null
                and coalesce(wm.user_id, sh.user_id) = any(p_approver_profile_ids)
           )
         )
         and case p_view
           when 'awaiting_me' then exists (
             select 1 from public.vp_read_approval_request_approvers a
              left join public.workspace_members wm on wm.id = a.workspace_member_id
              left join public.stakeholders sh on sh.id = a.stakeholder_id
              left join public.vp_read_approval_responses r on r.approver_slot_id = a.id
              where a.approval_request_id = v.id
                and a.removed_at is null
                and r.id is null
                and coalesce(wm.user_id, sh.user_id) = v_caller
           ) and v.status in ('pending','in_progress')
           when 'awaiting_others' then v.created_by_profile_id = v_caller
                                        and v.status in ('pending','in_progress')
           when 'approved' then v.status = 'approved'
           when 'rejected' then v.status = 'rejected'
           when 'expired_cancelled' then v.status in ('expired','cancelled')
           when 'bookmarks' then exists (
             select 1 from public.user_bookmarks b
              where b.user_id = v_caller
                and b.subject_kind = 'approval_request'
                and b.subject_id = v.id
           )
           else true
         end
    )
    select
      f.id, f.workspace_id, f.project_id, f.design_asset_id, f.version_id,
      f.title, f.description, f.status, f.policy, f.quorum_min,
      f.root_approval_request_id, f.supersedes_approval_request_id, f.related_review_id,
      f.created_by_profile_id,
      f.due_at, f.expires_at, f.sent_at, f.outcome_at,
      f.created_at, f.updated_at,
      (select count(*)::int from public.vp_read_approval_request_approvers a
        left join public.vp_read_approval_responses r on r.approver_slot_id = a.id
        where a.approval_request_id = f.id and a.removed_at is null and r.id is null),
      (select count(*)::int from public.vp_read_approval_responses r
        where r.approval_request_id = f.id and r.decision = 'approved'),
      (select count(*)::int from public.vp_read_approval_responses r
        where r.approval_request_id = f.id and r.decision = 'rejected'),
      (select count(*)::int from public.vp_read_approval_responses r
        where r.approval_request_id = f.id and r.decision = 'abstained'),
      (select count(*)::int from public.vp_read_approval_request_approvers a
        where a.approval_request_id = f.id and a.removed_at is null),
      (select exists (select 1 from public.vp_read_approval_request_approvers a
        where a.approval_request_id = f.id and a.removed_at is null and a.veto_power = true)),
      (f.expires_at is not null and f.expires_at < now() and f.status in ('pending','in_progress')),
      (select r.decision from public.vp_read_approval_request_approvers a
        left join public.workspace_members wm on wm.id = a.workspace_member_id
        left join public.stakeholders sh on sh.id = a.stakeholder_id
        left join public.vp_read_approval_responses r on r.approver_slot_id = a.id
        where a.approval_request_id = f.id and a.removed_at is null
          and coalesce(wm.user_id, sh.user_id) = v_caller
        limit 1)
    from filtered f
    where (p_cursor_updated_at is null
           or (f.updated_at, f.id) < (p_cursor_updated_at, p_cursor_id))
    order by f.updated_at desc, f.id desc
    limit v_lim;
end $function$;
CREATE OR REPLACE FUNCTION public.list_approvals_for_version(p_version_id uuid)
 RETURNS TABLE(out_id uuid, out_title text, out_status text, out_policy text, out_created_by_profile_id uuid, out_created_at timestamp with time zone, out_outcome_at timestamp with time zone, out_expires_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_caller uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'list_approvals_for_version: authentication required' using errcode='42501'; end if;

  return query
    select ar.id, ar.title, ar.status, ar.policy,
           ar.created_by_profile_id, ar.created_at, ar.outcome_at, ar.expires_at
      from public.vp_read_approval_requests ar
     where ar.version_id = p_version_id
       and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
     order by ar.outcome_at desc nulls first, ar.created_at desc;
end $function$;
CREATE OR REPLACE FUNCTION public.get_approval_inbox_count(p_ws_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_caller uuid; v_awaiting int; v_expiring int; v_coord int;
begin
  v_caller := auth.uid();
  if v_caller is null then
    return jsonb_build_object('awaiting_my_decision', 0, 'expiring_soon', 0, 'coordinating', 0);
  end if;
  if p_ws_id is null then
    return jsonb_build_object('awaiting_my_decision', 0, 'expiring_soon', 0, 'coordinating', 0);
  end if;

  select count(*) into v_awaiting
    from public.vp_read_approval_requests ar
    join public.vp_read_approval_request_approvers a on a.approval_request_id = ar.id
    left join public.workspace_members wm on wm.id = a.workspace_member_id
    left join public.stakeholders sh on sh.id = a.stakeholder_id
    left join public.vp_read_approval_responses r on r.approver_slot_id = a.id
   where ar.workspace_id = p_ws_id
     and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
     and a.removed_at is null
     and r.id is null
     and ar.status in ('pending','in_progress')
     and coalesce(wm.user_id, sh.user_id) = v_caller;

  select count(*) into v_expiring
    from public.vp_read_approval_requests ar
   where ar.workspace_id = p_ws_id
     and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
     and ar.expires_at is not null
     and ar.expires_at < (now() + interval '24 hours')
     and ar.status in ('pending','in_progress');

  select count(*) into v_coord
    from public.vp_read_approval_requests ar
   where ar.workspace_id = p_ws_id
     and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
     and ar.status in ('pending','in_progress')
     and ar.created_by_profile_id = v_caller;

  return jsonb_build_object(
    'awaiting_my_decision', v_awaiting,
    'expiring_soon',        v_expiring,
    'coordinating',         v_coord
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_project_approval_metrics(p_proj_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ws uuid; v_out int; v_over int;
begin
  select workspace_id into v_ws from public.projects where id = p_proj_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(p_proj_id, v_ws, 'approval.view') then
    raise exception 'get_project_approval_metrics: forbidden' using errcode='42501';
  end if;

  select count(*) into v_out from public.vp_read_approval_requests approval_requests
    where project_id = p_proj_id and status in ('pending','in_progress');
  select count(*) into v_over from public.vp_read_approval_requests approval_requests
    where project_id = p_proj_id
      and expires_at is not null and expires_at < now()
      and status in ('pending','in_progress');

  return jsonb_build_object(
    'outstanding_count', v_out,
    'overdue_count',     v_over
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_approval(p_approval_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller uuid;
  v_ws uuid; v_proj uuid;
  v_row jsonb; v_slots jsonb; v_responses jsonb; v_metrics jsonb; v_chain jsonb;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_approval: authentication required' using errcode='42501'; end if;

  select workspace_id, project_id into v_ws, v_proj
    from public.vp_read_approval_requests approval_requests where id = p_approval_request_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(v_proj, v_ws, 'approval.view') then
    raise exception 'get_approval: forbidden (approval.view)' using errcode='42501';
  end if;

  select to_jsonb(ar) into v_row from public.vp_read_approval_requests ar where ar.id = p_approval_request_id;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order asc, x.created_at asc), '[]'::jsonb) into v_slots
  from (
    select a.id, a.workspace_member_id, a.stakeholder_id,
           a.required, a.veto_power, a.sort_order,
           a.removed_at, a.removed_reason,
           a.created_at, a.updated_at,
           coalesce(wm_p.display_name, sh_p.display_name, sh.display_name) as display_name,
           coalesce(wm_p.avatar_url, sh_p.avatar_url) as avatar_url,
           coalesce(wm.user_id, sh.user_id) as profile_id,
           case when a.workspace_member_id is not null then 'member' else 'stakeholder' end as identity,
           (select jsonb_build_object(
              'id', r.id,
              'decision', r.decision,
              'comment', r.comment,
              'responded_at', r.responded_at,
              'is_veto_cast', r.is_veto_cast
            ) from public.vp_read_approval_responses r where r.approver_slot_id = a.id) as response
      from public.vp_read_approval_request_approvers a
      left join public.workspace_members wm on wm.id = a.workspace_member_id
      left join public.stakeholders sh on sh.id = a.stakeholder_id
      left join public.profiles wm_p on wm_p.id = wm.user_id
      left join public.profiles sh_p on sh_p.id = sh.user_id
     where a.approval_request_id = p_approval_request_id
  ) x;

  select coalesce(jsonb_agg(to_jsonb(y) order by y.responded_at asc), '[]'::jsonb) into v_responses
  from (
    select r.id, r.approver_slot_id, r.responder_profile_id,
           r.decision, r.comment, r.responded_at, r.is_veto_cast,
           r.decision_metadata
      from public.vp_read_approval_responses r
     where r.approval_request_id = p_approval_request_id
  ) y;

  v_metrics := jsonb_build_object(
    'response_distribution', (
      select jsonb_build_object(
        'approved',  count(*) filter (where decision='approved'),
        'rejected',  count(*) filter (where decision='rejected'),
        'abstained', count(*) filter (where decision='abstained'),
        'pending',   (select count(*) from public.vp_read_approval_request_approvers a
                       left join public.vp_read_approval_responses rr on rr.approver_slot_id = a.id
                       where a.approval_request_id = p_approval_request_id
                         and a.removed_at is null and rr.id is null)
      ) from public.vp_read_approval_responses approval_responses where approval_request_id = p_approval_request_id
    ),
    'has_veto_cast', (
      select exists (select 1 from public.vp_read_approval_responses approval_responses
        where approval_request_id = p_approval_request_id and is_veto_cast = true)
    ),
    'time_to_first_response', (
      select extract(epoch from (min(r.responded_at) - min(ar.sent_at)))
        from public.vp_read_approval_responses r
        cross join lateral (select sent_at from public.vp_read_approval_requests approval_requests where id = p_approval_request_id) ar
       where r.approval_request_id = p_approval_request_id
    ),
    'time_to_outcome', (
      select extract(epoch from (ar.outcome_at - ar.sent_at))
        from public.vp_read_approval_requests ar where ar.id = p_approval_request_id
    )
  );

  select jsonb_build_object(
    'root_approval_request_id', (v_row->>'root_approval_request_id')::uuid,
    'is_latest', not exists (
      select 1 from public.vp_read_approval_requests a2
       where a2.supersedes_approval_request_id = p_approval_request_id
    ),
    'prior_request_id', (v_row->>'supersedes_approval_request_id')::uuid,
    'next_request_id', (
      select a2.id from public.vp_read_approval_requests a2
       where a2.supersedes_approval_request_id = p_approval_request_id
       limit 1
    )
  ) into v_chain;

  return jsonb_build_object(
    'request', v_row,
    'slots', v_slots,
    'responses', v_responses,
    'metrics', v_metrics,
    'chain_position', v_chain
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_approval_chain(p_root_approval_request_id uuid)
 RETURNS TABLE(out_id uuid, out_status text, out_title text, out_policy text, out_supersedes_approval_request_id uuid, out_created_at timestamp with time zone, out_outcome_at timestamp with time zone, out_approved_count integer, out_rejected_count integer, out_total_count integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_caller uuid; v_ws uuid; v_proj uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_approval_chain: authentication required' using errcode='42501'; end if;

  select workspace_id, project_id into v_ws, v_proj
    from public.vp_read_approval_requests approval_requests where id = p_root_approval_request_id;
  if v_ws is null then return; end if;
  if not public.lign_has_capability(v_proj, v_ws, 'approval.view') then
    raise exception 'get_approval_chain: forbidden (approval.view)' using errcode='42501';
  end if;

  return query
    select ar.id, ar.status, ar.title, ar.policy,
           ar.supersedes_approval_request_id,
           ar.created_at, ar.outcome_at,
           (select count(*)::int from public.vp_read_approval_responses r
             where r.approval_request_id = ar.id and r.decision='approved'),
           (select count(*)::int from public.vp_read_approval_responses r
             where r.approval_request_id = ar.id and r.decision='rejected'),
           (select count(*)::int from public.vp_read_approval_request_approvers a
             where a.approval_request_id = ar.id and a.removed_at is null)
      from public.vp_read_approval_requests ar
     where ar.root_approval_request_id = p_root_approval_request_id
        or ar.id = p_root_approval_request_id
     order by ar.created_at asc;
end $function$;
CREATE OR REPLACE FUNCTION public.get_approval_readiness(p_version_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller uuid;
  v_has_approved boolean := false;
  v_latest jsonb := null;
  v_blocking uuid[];
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_approval_readiness: authentication required' using errcode='42501'; end if;

  select exists (
    select 1 from public.vp_read_approval_requests ar
     where ar.version_id = p_version_id and ar.status = 'approved'
       and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
  ) into v_has_approved;

  select jsonb_build_object(
      'status',      ar.status,
      'outcome_at',  ar.outcome_at,
      'request_id',  ar.id
    ) into v_latest
    from public.vp_read_approval_requests ar
   where ar.version_id = p_version_id
     and ar.outcome_at is not null
     and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
   order by ar.outcome_at desc
   limit 1;

  select coalesce(array_agg(ar.id), '{}'::uuid[]) into v_blocking
    from public.vp_read_approval_requests ar
   where ar.version_id = p_version_id
     and ar.status in ('pending','in_progress','rejected')
     and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view');

  return jsonb_build_object(
    'has_approved', v_has_approved,
    'latest_outcome', v_latest,
    'blocking_requests', to_jsonb(v_blocking)
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_workspace_approval_metrics(p_ws_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_caller uuid; v_out int; v_over int;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_workspace_approval_metrics: authentication required' using errcode='42501'; end if;
  if p_ws_id is null then return null; end if;

  select count(*) into v_out from public.vp_read_approval_requests ar
    where ar.workspace_id = p_ws_id
      and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
      and ar.status in ('pending','in_progress');
  select count(*) into v_over from public.vp_read_approval_requests ar
    where ar.workspace_id = p_ws_id
      and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view')
      and ar.expires_at is not null and ar.expires_at < now()
      and ar.status in ('pending','in_progress');

  return jsonb_build_object(
    'outstanding_count', v_out,
    'overdue_count',     v_over
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_requirement(p_requirement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ws uuid; v_pj uuid;
  v_row jsonb;
  v_subs jsonb;
  v_app_summary jsonb;
  v_assess_summary jsonb;
  v_metrics jsonb;
  v_chain jsonb;
  v_asset_count int;
  v_asset_ids uuid[];
  v_root_id uuid;
begin
  if auth.uid() is null then raise exception 'get_requirement: authentication required' using errcode='42501'; end if;

  select workspace_id, project_id, coalesce(parent_requirement_id, id)
    into v_ws, v_pj, v_root_id
    from public.requirements where id = p_requirement_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.view') then
    return null; -- fail-closed: don't leak existence
  end if;

  select to_jsonb(r) into v_row
    from public.requirements r where r.id = p_requirement_id;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.code), '[]'::jsonb)
    into v_subs
    from public.requirements c where c.parent_requirement_id = p_requirement_id;

  select count(*)::int, coalesce(array_agg(design_asset_id), array[]::uuid[])
    into v_asset_count, v_asset_ids
    from public.requirement_design_assets where requirement_id = v_root_id;

  v_app_summary := jsonb_build_object(
    'is_project_wide', v_asset_count = 0,
    'asset_count',     v_asset_count,
    'asset_ids',       to_jsonb(v_asset_ids)
  );

  -- Assessment summary: count applicable latest-versions and how many are assessed.
  with applicable_versions as (
    select av.id as version_id, av.design_asset_id
      from public.vp_read_asset_versions av
     where av.project_id = v_pj
       and (
         v_asset_count = 0  -- project-wide
         or av.design_asset_id = any (v_asset_ids)
       )
  ),
  latest_per_asset as (
    select distinct on (design_asset_id) version_id, design_asset_id
      from applicable_versions
      -- Every asset_version has a created_at; choose latest.
     order by design_asset_id, version_id desc
  ),
  joined as (
    select l.design_asset_id, l.version_id, vra.status
      from latest_per_asset l
      left join public.vp_read_version_requirement_assessments vra
             on vra.asset_version_id = l.version_id
            and vra.requirement_id   = p_requirement_id
  )
  select jsonb_build_object(
           'versions_applicable', count(*)::int,
           'versions_assessed',   count(*) filter (where status is not null)::int,
           'latest_status_per_asset', coalesce(jsonb_object_agg(
             design_asset_id::text, coalesce(status, 'unassessed')
           ) filter (where design_asset_id is not null), '{}'::jsonb)
         )
    into v_assess_summary
    from joined;

  -- Days-since-last-assessment; days-until-due.
  select jsonb_build_object(
           'coverage_pct',
             case
               when (v_assess_summary->>'versions_applicable')::int = 0 then 0
               else round(
                 100.0 * (v_assess_summary->>'versions_assessed')::numeric
                       / nullif((v_assess_summary->>'versions_applicable')::numeric, 0),
                 2)
             end,
           'days_since_last_assessment', (
             select case when max(assessed_at) is null then null
                        else extract(day from now() - max(assessed_at))::int end
               from public.vp_read_version_requirement_assessments version_requirement_assessments
              where requirement_id = p_requirement_id
           ),
           'days_until_due', (
             case when (v_row->>'due_at') is null then null
                  else extract(day from (v_row->>'due_at')::timestamptz - now())::int end
           )
         )
    into v_metrics;

  -- Chain position: forward + backward pointers.
  select jsonb_build_object(
           'supersedes',
             (select id from public.requirements
               where superseded_by_requirement_id = p_requirement_id
               order by created_at desc limit 1),
           'superseded_by', (v_row->>'superseded_by_requirement_id')::uuid,
           'chain_depth', (
             with recursive walk as (
               select id, superseded_by_requirement_id, 0 as d
                 from public.requirements where id = p_requirement_id
               union all
               select r.id, r.superseded_by_requirement_id, w.d + 1
                 from public.requirements r
                 join walk w on w.superseded_by_requirement_id = r.id
                where w.d < 32
             )
             select coalesce(max(d), 0) from walk
           )
         )
    into v_chain;

  return jsonb_build_object(
    'requirement',          v_row,
    'sub_requirements',     v_subs,
    'applicability_summary', v_app_summary,
    'assessment_summary',   v_assess_summary,
    'metrics',              v_metrics,
    'chain_position',       v_chain
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_requirement_inbox_count(p_ws_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller uuid := auth.uid();
  v_assigned int;
  v_overdue int;
  v_needs int;
begin
  if v_caller is null then raise exception 'get_requirement_inbox_count: authentication required' using errcode='42501'; end if;

  select count(*)::int into v_assigned
    from public.requirements r
   where r.workspace_id = p_ws_id
     and r.owner_profile_id = v_caller
     and r.status in ('draft','active')
     and public.lign_has_capability(r.project_id, r.workspace_id, 'requirement.view');

  select count(*)::int into v_overdue
    from public.requirements r
   where r.workspace_id = p_ws_id
     and r.priority = 'critical'
     and r.status in ('draft','active')
     and r.due_at is not null and r.due_at < now()
     and public.lign_has_capability(r.project_id, r.workspace_id, 'requirement.view');

  select count(*)::int into v_needs
    from public.requirements r
   where r.workspace_id = p_ws_id
     and r.priority = 'critical'
     and r.status in ('draft','active')
     and public.lign_has_capability(r.project_id, r.workspace_id, 'requirement.view')
     and not exists (
       select 1 from public.vp_read_version_requirement_assessments vra
        where vra.requirement_id = r.id
     );

  return jsonb_build_object(
    'assigned_to_me',   v_assigned,
    'overdue_critical', v_overdue,
    'needs_assessment', v_needs
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_requirement_trace(p_requirement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ws uuid; v_pj uuid;
  v_row jsonb;
  v_root_id uuid;
  v_asset_count int;
  v_asset_ids uuid[];
  v_apps jsonb;
  v_subs jsonb;
  v_assessments jsonb;
  v_changes jsonb;
  v_decisions jsonb;
  v_dcount int;
  v_ars jsonb;
  v_chain jsonb;
  v_metrics jsonb;
begin
  if auth.uid() is null then raise exception 'get_requirement_trace: authentication required' using errcode='42501'; end if;

  select workspace_id, project_id, coalesce(parent_requirement_id, id)
    into v_ws, v_pj, v_root_id
    from public.requirements where id = p_requirement_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.view') then
    return null;
  end if;

  select to_jsonb(r) into v_row from public.requirements r where r.id = p_requirement_id;

  select count(*)::int, coalesce(array_agg(design_asset_id), array[]::uuid[])
    into v_asset_count, v_asset_ids
    from public.requirement_design_assets where requirement_id = v_root_id;

  if v_asset_count = 0 then
    v_apps := '[]'::jsonb;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
             'design_asset_id', da.id,
             'name',            da.title,
             'project_id',      da.project_id
           )), '[]'::jsonb)
      into v_apps
      from public.vp_read_design_assets da
     where da.id = any (v_asset_ids);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'code', code, 'title', title,
           'status', status, 'priority', priority
         ) order by code), '[]'::jsonb)
    into v_subs
    from public.requirements where parent_requirement_id = p_requirement_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'asset_version_id', asset_version_id,
           'asset_id', (select design_asset_id from public.vp_read_asset_versions asset_versions where id = vra.asset_version_id),
           'version_number', (select version_number from public.vp_read_asset_versions asset_versions where id = vra.asset_version_id),
           'status', status, 'note', note, 'assessed_at', assessed_at,
           'assessed_by_profile_id', assessed_by_profile_id
         ) order by assessed_at desc), '[]'::jsonb)
    into v_assessments
    from public.vp_read_version_requirement_assessments vra
   where vra.requirement_id = p_requirement_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'change_id', id, 'kind', kind, 'created_at', created_at,
           'subject_label', label
         ) order by created_at desc), '[]'::jsonb)
    into v_changes
    from public.vp_read_changes changes where requirement_id = p_requirement_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'decision_id', id, 'subject_kind', subject_kind, 'subject_id', subject_id,
           'created_at', created_at,
           'decision_reason_snippet', left(coalesce(decision_reason, ''), 200)
         ) order by created_at desc), '[]'::jsonb)
    into v_decisions
    from public.vp_read_decisions decisions where requirement_id = p_requirement_id;

  select count(*)::int into v_dcount
    from public.vp_read_comments comments
   where target_requirement_id = p_requirement_id and deleted_at is null;

  select coalesce(jsonb_agg(distinct jsonb_build_object(
           'approval_request_id', ar.id,
           'status', ar.status,
           'outcome_at', ar.outcome_at,
           'root_approval_request_id', ar.root_approval_request_id
         )), '[]'::jsonb)
    into v_ars
    from public.vp_read_decisions d
    join public.vp_read_approval_requests ar on ar.id = d.subject_id
   where d.requirement_id = p_requirement_id
     and d.subject_kind = 'approval_request';

  v_chain := public.get_requirement_chain(p_requirement_id);

  v_metrics := jsonb_build_object(
    'coverage_pct',
      (case
         when jsonb_array_length(v_assessments) = 0 then 0
         else round(
           100.0 * (select count(*) from jsonb_array_elements(v_assessments) x where x->>'status' = 'satisfied')
                 / nullif(jsonb_array_length(v_assessments)::numeric, 0), 2)
       end),
    'critical_unsatisfied_count',
      (select count(*) from jsonb_array_elements(v_assessments) x
        where x->>'status' in ('not_satisfied','partial')
          and (v_row->>'priority') = 'critical'),
    'unassessed_on_latest_count', 0
  );

  return jsonb_build_object(
    'requirement',        v_row,
    'applicable_assets',  v_apps,
    'is_project_wide',    v_asset_count = 0,
    'sub_requirements',   v_subs,
    'assessments',        v_assessments,
    'related_changes',    v_changes,
    'related_decisions',  v_decisions,
    'discussion_count',   v_dcount,
    'approval_requests',  v_ars,
    'supersession_chain', v_chain,
    'metrics',            v_metrics
  );
end $function$;
CREATE OR REPLACE FUNCTION public.list_requirements_dashboard(p_ws_id uuid, p_proj_id uuid, p_view text DEFAULT 'all_active'::text, p_status_filter text[] DEFAULT NULL::text[], p_priority_filter text[] DEFAULT NULL::text[], p_source_filter text[] DEFAULT NULL::text[], p_category_filter text[] DEFAULT NULL::text[], p_scope_filter text DEFAULT NULL::text, p_owner_ids uuid[] DEFAULT NULL::uuid[], p_search text DEFAULT NULL::text, p_cursor_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 50, p_saved_view_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller uuid := auth.uid();
  v_rows jsonb;
  v_next_cursor jsonb;
  v_effective_view text := coalesce(p_view, 'all_active');
  v_status_filter text[] := p_status_filter;
  v_priority_filter text[] := p_priority_filter;
  v_source_filter text[] := p_source_filter;
  v_category_filter text[] := p_category_filter;
  v_owner_ids uuid[] := p_owner_ids;
  v_search text := p_search;
  v_scope_filter text := p_scope_filter;
  v_saved_payload jsonb;
  v_limit int := greatest(1,least(coalesce(p_limit, 50), 200));
begin
  if v_caller is null then raise exception 'list_requirements_dashboard: authentication required' using errcode='42501'; end if;
  if p_ws_id is null then raise exception 'list_requirements_dashboard: workspace id required' using errcode='22004'; end if;

  -- Resolve saved view (if any) — override the filter set.
  if p_saved_view_id is not null then
    select payload into v_saved_payload
      from public.user_saved_views
     where id = p_saved_view_id
       and user_id = v_caller
       and workspace_id = p_ws_id
       and scope = 'requirements';
    if v_saved_payload is not null then
      v_effective_view    := coalesce(v_saved_payload->>'view', v_effective_view);
      v_status_filter     := case when v_saved_payload ? 'status_filter'    then array(select jsonb_array_elements_text(v_saved_payload->'status_filter'))    else v_status_filter    end;
      v_priority_filter   := case when v_saved_payload ? 'priority_filter'  then array(select jsonb_array_elements_text(v_saved_payload->'priority_filter'))  else v_priority_filter  end;
      v_source_filter     := case when v_saved_payload ? 'source_filter'    then array(select jsonb_array_elements_text(v_saved_payload->'source_filter'))    else v_source_filter    end;
      v_category_filter   := case when v_saved_payload ? 'category_filter'  then array(select jsonb_array_elements_text(v_saved_payload->'category_filter'))  else v_category_filter  end;
      v_scope_filter      := coalesce(v_saved_payload->>'scope_filter', v_scope_filter);
      v_search            := coalesce(v_saved_payload->>'search', v_search);
      v_owner_ids         := case when v_saved_payload ? 'owner_ids'        then (select array_agg(x::uuid) from jsonb_array_elements_text(v_saved_payload->'owner_ids') as x) else v_owner_ids end;
    end if;
  end if;

  -- Interpret magic view names.
  if v_effective_view = 'assigned_to_me' then
    v_owner_ids := array[v_caller];
  end if;
  if v_effective_view = 'archived' then
    v_status_filter := array['archived'];
  elsif v_effective_view = 'superseded' then
    v_status_filter := array['superseded'];
  elsif v_effective_view in ('overdue_critical') then
    v_priority_filter := array['critical'];
  end if;

  -- Authorization: at workspace scope, filter to projects the caller can view.
  -- At project scope, gate at RPC entry.
  if p_proj_id is not null then
    if not public.lign_has_capability(p_proj_id, p_ws_id, 'requirement.view') then
      raise exception 'list_requirements_dashboard: forbidden (requirement.view)' using errcode='42501';
    end if;
  end if;

  with base as (
    select r.*,
           p.name as project_name,
           (select count(*)::int from public.requirement_design_assets rda
              where rda.requirement_id = coalesce(r.parent_requirement_id, r.id))
             as rda_count
      from public.requirements r
      join public.projects p on p.id = r.project_id
     where r.workspace_id = p_ws_id
       and (p_proj_id is null or r.project_id = p_proj_id)
       and (
         p_proj_id is not null
         or public.lign_has_capability(r.project_id, r.workspace_id, 'requirement.view')
       )
       and (v_status_filter is null   or r.status         = any (v_status_filter))
       and (v_priority_filter is null or r.priority       = any (v_priority_filter))
       and (v_source_filter is null   or r.source_kind    = any (v_source_filter))
       and (v_category_filter is null or r.category_kind  = any (v_category_filter))
       and (v_owner_ids is null       or r.owner_profile_id = any (v_owner_ids))
       and (v_search is null or v_search = ''
            or r.code        ilike '%' || v_search || '%'
            or r.title       ilike '%' || v_search || '%'
            or coalesce(r.description, '') ilike '%' || v_search || '%')
       -- Default view: only non-terminal unless user asked otherwise.
       and (
         v_effective_view in ('all','archived','superseded')
         or v_status_filter is not null
         or r.status in ('draft','active')
       )
       and (
         p_cursor_updated_at is null
         or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id)
       )
  ),
  scoped as (
    select * from base
     where (
       v_scope_filter is null
       or (v_scope_filter = 'project_wide' and rda_count = 0)
       or (v_scope_filter = 'asset_scoped' and rda_count > 0)
     )
  ),
  filtered as (
    select * from scoped
     order by updated_at desc, id desc
     limit v_limit + 1
  ),
  page as (
    select * from filtered limit v_limit
  ),
  paged as (
    select b.*,
      jsonb_build_object(
        'scope', case when b.rda_count = 0 then 'project_wide' else 'asset_scoped' end,
        'asset_count', b.rda_count
      ) as applicability_summary,
      (
        with applicable_versions as (
          select av.id as version_id, av.design_asset_id
            from public.vp_read_asset_versions av
           where av.project_id = b.project_id
             and (b.rda_count = 0
                  or av.design_asset_id in (
                    select design_asset_id from public.requirement_design_assets
                     where requirement_id = coalesce(b.parent_requirement_id, b.id)))
        ),
        latest as (
          select distinct on (design_asset_id) version_id
            from applicable_versions
           order by design_asset_id, version_id desc
        ),
        j as (
          select l.version_id, vra.status
            from latest l
            left join public.vp_read_version_requirement_assessments vra
                   on vra.asset_version_id = l.version_id
                  and vra.requirement_id   = b.id
        )
        select jsonb_build_object(
                 'applicable_versions_count', count(*)::int,
                 'satisfied_count',           count(*) filter (where status = 'satisfied')::int,
                 'coverage_pct',
                   case when count(*) = 0 then 0
                        else round(100.0 * count(*) filter (where status = 'satisfied')::numeric
                                       / nullif(count(*)::numeric, 0), 2)
                   end,
                 'latest_version_assessed',
                   coalesce(bool_and(status is not null), false)
               ) from j
      ) as assessment_coverage
      from page b
  )
  -- The page and cursor must be read in the same CTE statement.
  select (select coalesce(jsonb_agg(
           jsonb_build_object(
             'requirement_id',       id,
             'code',                 code,
             'title',                title,
             'status',               status,
             'priority',             priority,
             'source_kind',          source_kind,
             'category_kind',        category_kind,
             'owner_profile_id',     owner_profile_id,
             'updated_at',           updated_at,
             'applicability_summary', applicability_summary,
             'assessment_coverage',  assessment_coverage,
             'project_id',           project_id,
             'project_name',         project_name,
             'workspace_id',         workspace_id,
             'due_at',               due_at
           ) order by updated_at desc,id desc
         ), '[]'::jsonb) from paged),
    (select case when count(*)>v_limit then
       (select jsonb_build_object('updated_at',updated_at,'id',id) from page order by updated_at asc,id asc limit 1)
     else null end from filtered)
    into v_rows,v_next_cursor;

  return jsonb_build_object(
    'rows',        v_rows,
    'next_cursor', v_next_cursor
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_project_requirement_metrics(p_project_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ws uuid;
  v_out jsonb;
begin
  if auth.uid() is null then raise exception 'get_project_requirement_metrics: authentication required' using errcode='42501'; end if;
  select workspace_id into v_ws from public.projects where id = p_project_id;
  if v_ws is null then raise exception 'get_project_requirement_metrics: project not found' using errcode='23503'; end if;
  if not public.lign_has_capability(p_project_id, v_ws, 'requirement.view') then
    raise exception 'get_project_requirement_metrics: forbidden (requirement.view)' using errcode='42501';
  end if;

  with r as (select * from public.requirements where project_id = p_project_id)
  select jsonb_build_object(
    'total_count', (select count(*)::int from r),
    'by_status',
      (select jsonb_object_agg(status, cnt) from
        (select status, count(*)::int as cnt from r group by status) s),
    'by_priority',
      (select jsonb_object_agg(coalesce(priority, 'unset'), cnt) from
        (select priority, count(*)::int as cnt from r group by priority) s),
    'by_source',
      (select jsonb_object_agg(coalesce(source_kind, 'unset'), cnt) from
        (select source_kind, count(*)::int as cnt from r group by source_kind) s),
    'unassessed_on_latest_count',
      (select count(*)::int from r
        where status in ('draft','active')
          and not exists (
            select 1 from public.vp_read_version_requirement_assessments vra
             where vra.requirement_id = r.id)),
    'critical_unsatisfied_count',
      (select count(*)::int from r
        where status in ('draft','active') and priority = 'critical'
          and exists (
            select 1 from public.vp_read_version_requirement_assessments vra
             where vra.requirement_id = r.id and vra.status in ('not_satisfied','partial'))),
    'overdue_count',
      (select count(*)::int from r
        where status in ('draft','active')
          and due_at is not null and due_at < now()),
    'coverage_rate',
      (select case when count(*) = 0 then 0
                   else round(100.0 * count(*) filter (where vra.status = 'satisfied')::numeric
                                    / nullif(count(*)::numeric, 0), 2) end
         from r
         left join public.vp_read_version_requirement_assessments vra on vra.requirement_id = r.id
        where r.status in ('draft','active')),
    'trailing_30d_creation_rate',
      (select count(*)::int from public.vp_read_activity_events activity_events
        where project_id = p_project_id
          and event_type = 'requirement.created'
          and occurred_at > now() - interval '30 days'),
    'trailing_30d_assessment_activity_rate',
      (select count(*)::int from public.vp_read_activity_events activity_events
        where project_id = p_project_id
          and event_type = 'requirement.assessed'
          and occurred_at > now() - interval '30 days')
  ) into v_out;

  return v_out;
end $function$;
CREATE OR REPLACE FUNCTION public.get_workspace_requirement_metrics(p_ws_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller uuid := auth.uid();
  v_out jsonb;
begin
  if v_caller is null then raise exception 'get_workspace_requirement_metrics: authentication required' using errcode='42501'; end if;

  with visible as (
    select r.* from public.requirements r
     where r.workspace_id = p_ws_id
       and public.lign_has_capability(r.project_id, r.workspace_id, 'requirement.view')
  )
  select jsonb_build_object(
    'total_active',
      (select count(*)::int from visible where status in ('draft','active')),
    'by_status',
      (select jsonb_object_agg(status, cnt) from
        (select status, count(*)::int as cnt from visible group by status) s),
    'by_priority',
      (select jsonb_object_agg(coalesce(priority, 'unset'), cnt) from
        (select priority, count(*)::int as cnt from visible group by priority) s),
    'top5_projects_by_critical_unsatisfied',
      (select coalesce(jsonb_agg(x order by cnt desc), '[]'::jsonb) from
        (select v.project_id,
                (select name from public.projects p where p.id = v.project_id) as project_name,
                count(*)::int as cnt
           from visible v
           join public.vp_read_version_requirement_assessments vra on vra.requirement_id = v.id
          where v.priority = 'critical' and vra.status in ('not_satisfied','partial')
          group by v.project_id
          order by cnt desc
          limit 5) as x),
    'top5_owners_by_open_load',
      (select coalesce(jsonb_agg(x order by cnt desc), '[]'::jsonb) from
        (select owner_profile_id,
                (select display_name from public.profiles where id = v.owner_profile_id) as display_name,
                count(*)::int as cnt
           from visible v
          where owner_profile_id is not null
            and priority in ('critical','high')
            and status = 'active'
          group by owner_profile_id
          order by cnt desc
          limit 5) as x),
    'overdue_count_across_workspace',
      (select count(*)::int from visible
        where status in ('draft','active')
          and due_at is not null and due_at < now())
  ) into v_out;

  return v_out;
end $function$;
CREATE OR REPLACE FUNCTION public.get_release_readiness_for_version(p_asset_version_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ws uuid; v_pj uuid; v_asset uuid;
  v_out jsonb;
begin
  if auth.uid() is null then raise exception 'get_release_readiness_for_version: authentication required' using errcode='42501'; end if;
  select workspace_id, project_id, design_asset_id
    into v_ws, v_pj, v_asset
    from public.vp_read_asset_versions asset_versions where id = p_asset_version_id;
  if v_ws is null then raise exception 'get_release_readiness_for_version: version not found' using errcode='23503'; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.view') then
    raise exception 'get_release_readiness_for_version: forbidden (requirement.view)' using errcode='42501';
  end if;

  with root_scoped as (
    select r.id, r.priority
      from public.requirements r
     where r.project_id = v_pj
       and r.status in ('draft','active')
  ),
  scoped_root_ids as (
    select distinct requirement_id as root_id from public.requirement_design_assets
     where design_asset_id = v_asset
  ),
  all_project_roots as (
    select id from public.requirements
     where project_id = v_pj and parent_requirement_id is null
       and status in ('draft','active')
  ),
  root_wide as (
    select id from all_project_roots
     where id not in (
       select distinct requirement_id from public.requirement_design_assets
        where requirement_id in (select id from all_project_roots)
     )
  ),
  applicable_root_ids as (
    select id from root_wide union select root_id as id from scoped_root_ids
  ),
  applicable as (
    select rs.id, rs.priority,
           coalesce((select r2.parent_requirement_id from public.requirements r2 where r2.id = rs.id), rs.id) as root_id
      from root_scoped rs
     where coalesce(
             (select parent_requirement_id from public.requirements rr where rr.id = rs.id),
             rs.id
           ) in (select id from applicable_root_ids)
  ),
  joined as (
    select a.id, a.priority, vra.status
      from applicable a
      left join public.vp_read_version_requirement_assessments vra
             on vra.requirement_id = a.id
            and vra.asset_version_id = p_asset_version_id
  )
  select jsonb_build_object(
    'applicable_count',           count(*)::int,
    'satisfied_count',            count(*) filter (where status = 'satisfied')::int,
    'partial_count',              count(*) filter (where status = 'partial')::int,
    'not_satisfied_count',        count(*) filter (where status = 'not_satisfied')::int,
    'unassessed_count',           count(*) filter (where status is null)::int,
    'critical_unsatisfied_count', count(*) filter (where priority = 'critical' and status in ('not_satisfied','partial'))::int,
    'critical_unassessed_count',  count(*) filter (where priority = 'critical' and status is null)::int
  ) into v_out
  from joined;

  return v_out;
end $function$;
CREATE OR REPLACE FUNCTION public.get_release(p_release_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_r          public.releases%rowtype;
  v_item_count int;
  v_chain_len  int;
  v_chain_pos  int;
  v_root_id    uuid;
begin
  select * into v_r from public.vp_read_releases releases where id = p_release_id;
  if v_r.id is null then
    return null;
  end if;
  if not public.lign_has_capability(v_r.project_id, v_r.workspace_id, 'release.view') then
    raise exception 'get_release: forbidden (release.view)' using errcode='42501';
  end if;

  select count(*) into v_item_count from public.vp_read_release_items release_items where release_id = p_release_id;

  v_root_id := coalesce(v_r.root_release_id, v_r.id);
  with recursive chain(id, depth) as (
    select v_root_id, 1
    union all
    select r.id, c.depth + 1
      from chain c
      join public.vp_read_releases r on r.superseded_by_release_id = c.id
     where r.project_id = v_r.project_id
  )
  select count(*)::int into v_chain_len from chain;

  with recursive chain(id, depth) as (
    select v_root_id, 1
    union all
    select r.id, c.depth + 1
      from chain c
      join public.vp_read_releases r on r.superseded_by_release_id = c.id
     where r.project_id = v_r.project_id
  )
  select depth into v_chain_pos from chain where id = v_r.id;

  return jsonb_build_object(
    'id', v_r.id,
    'workspace_id', v_r.workspace_id,
    'project_id', v_r.project_id,
    'name', v_r.name,
    'notes', v_r.notes,
    'channel', v_r.channel,
    'release_type', v_r.release_type,
    'status', v_r.status,
    'code', v_r.code,
    'effective_at', v_r.effective_at,
    'released_at', v_r.released_at,
    'withdrawn_at', v_r.withdrawn_at,
    'withdrawn_reason', v_r.withdrawn_reason,
    'created_by_profile_id', v_r.created_by_profile_id,
    'published_by_profile_id', v_r.published_by_profile_id,
    'created_at', v_r.created_at,
    'updated_at', v_r.updated_at,
    'discarded_at', v_r.discarded_at,
    'superseded_by_release_id', v_r.superseded_by_release_id,
    'root_release_id', v_r.root_release_id,
    'item_count', v_item_count,
    'chain_length', v_chain_len,
    'chain_position', coalesce(v_chain_pos, 1)
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_release_chain(p_release_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_r public.releases%rowtype;
  v_root_id uuid;
  v_arr jsonb;
begin
  select * into v_r from public.vp_read_releases releases where id = p_release_id;
  if v_r.id is null then return jsonb_build_object('nodes','[]'::jsonb); end if;
  if not public.lign_has_capability(v_r.project_id, v_r.workspace_id, 'release.view') then
    raise exception 'get_release_chain: forbidden (release.view)' using errcode='42501';
  end if;
  v_root_id := coalesce(v_r.root_release_id, v_r.id);
  with recursive walk(id, depth) as (
    select v_root_id, 0
    union all
    select r.id, w.depth + 1
      from walk w join public.vp_read_releases r on r.superseded_by_release_id = w.id
     where r.project_id = v_r.project_id
  ),
  nodes as (
    select r.id as release_id, r.code, r.name, r.release_type, r.status,
           r.released_at, r.withdrawn_at, w.depth,
           (w.depth = 0) as is_root,
           (r.superseded_by_release_id is null) as is_head
      from walk w join public.vp_read_releases r on r.id = w.id
  )
  select jsonb_agg(
    jsonb_build_object(
      'release_id', release_id, 'code', code, 'name', name,
      'release_type', release_type, 'status', status,
      'released_at', released_at, 'withdrawn_at', withdrawn_at,
      'is_root', is_root, 'is_head', is_head
    ) order by depth asc)
  into v_arr from nodes;
  return jsonb_build_object('nodes', coalesce(v_arr, '[]'::jsonb));
end $function$;
CREATE OR REPLACE FUNCTION public.list_release_items(p_release_id uuid)
 RETURNS TABLE(out_release_item_id uuid, out_design_asset_id uuid, out_design_asset_name text, out_version_id uuid, out_version_sequence integer, out_version_published_at timestamp with time zone, out_notes text, out_sort_order integer, out_approval_state jsonb, out_requirement_readiness_summary jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ws uuid; v_pj uuid;
begin
  select workspace_id, project_id into v_ws, v_pj from public.vp_read_releases releases where id = p_release_id;
  if v_ws is null then return; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.view') then
    raise exception 'list_release_items: forbidden (release.view)' using errcode='42501';
  end if;
  return query
    select ri.id, ri.design_asset_id, da.name, ri.version_id, av.sequence,
           av.published_at, ri.notes, ri.sort_order,
           public.get_approval_readiness(ri.version_id),
           public.get_release_readiness_for_version(ri.version_id)
      from public.vp_read_release_items ri
      join public.vp_read_design_assets  da on da.id = ri.design_asset_id
      join public.vp_read_asset_versions av on av.id = ri.version_id
     where ri.release_id = p_release_id
     order by ri.sort_order asc, ri.created_at asc;
end $function$;
CREATE OR REPLACE FUNCTION public.get_release_evidence(p_release_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_r public.releases%rowtype;
  v_delta_arr jsonb;
begin
  select * into v_r from public.vp_read_releases releases where id = p_release_id;
  if v_r.id is null then return null; end if;
  if not public.lign_has_capability(v_r.project_id, v_r.workspace_id, 'release.view') then
    raise exception 'get_release_evidence: forbidden (release.view)' using errcode='42501';
  end if;
  with items as (
    select ri.id as release_item_id, ri.design_asset_id, ri.version_id
      from public.vp_read_release_items ri where ri.release_id = p_release_id
  ),
  computed as (
    select i.release_item_id, i.design_asset_id, i.version_id,
           public.get_approval_readiness(i.version_id) as approval_current,
           public.get_release_readiness_for_version(i.version_id) as requirement_current
      from items i
  )
  select jsonb_agg(jsonb_build_object(
    'release_item_id', release_item_id,
    'design_asset_id', design_asset_id,
    'version_id', version_id,
    'approval_current', approval_current,
    'requirement_current', requirement_current
  )) into v_delta_arr from computed;
  return jsonb_build_object(
    'snapshot', v_r.evidence_snapshot,
    'live_delta', jsonb_build_object('items', coalesce(v_delta_arr, '[]'::jsonb)),
    'has_deltas', (v_r.evidence_snapshot is not null)
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_release_comparison(p_release_id uuid, p_compare_to_release_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_this public.releases%rowtype;
  v_other public.releases%rowtype;
  v_other_id uuid;
  v_this_json jsonb;
  v_other_json jsonb;
  v_added jsonb;
  v_removed jsonb;
  v_changed jsonb;
begin
  select * into v_this from public.vp_read_releases releases where id = p_release_id;
  if v_this.id is null then return null; end if;
  if not public.lign_has_capability(v_this.project_id, v_this.workspace_id, 'release.view') then
    raise exception 'get_release_comparison: forbidden (release.view)' using errcode='42501';
  end if;
  v_other_id := p_compare_to_release_id;
  if v_other_id is null then
    select id into v_other_id from public.vp_read_releases releases
     where superseded_by_release_id = v_this.id and project_id = v_this.project_id limit 1;
  end if;
  if v_other_id is not null then
    select * into v_other from public.vp_read_releases releases where id = v_other_id;
    if v_other.id is null then v_other_id := null;
    elsif v_other.project_id <> v_this.project_id then
      raise exception 'get_release_comparison: releases must be same project' using errcode='23514';
    end if;
  end if;
  v_this_json := public.get_release(v_this.id);
  v_other_json := case when v_other_id is not null then public.get_release(v_other_id) else null end;
  with this_items as (
    select design_asset_id, version_id from public.vp_read_release_items release_items where release_id = v_this.id
  ),
  other_items as (
    select design_asset_id, version_id from public.vp_read_release_items release_items
     where release_id = coalesce(v_other_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ),
  added as (
    select ti.design_asset_id, ti.version_id from this_items ti
     where not exists (select 1 from other_items oi where oi.design_asset_id = ti.design_asset_id)
  ),
  removed as (
    select oi.design_asset_id, oi.version_id from other_items oi
     where not exists (select 1 from this_items ti where ti.design_asset_id = oi.design_asset_id)
  ),
  changed as (
    select ti.design_asset_id, ti.version_id as this_version_id, oi.version_id as compare_version_id
      from this_items ti join other_items oi on oi.design_asset_id = ti.design_asset_id
     where ti.version_id <> oi.version_id
  )
  select
    (select coalesce(jsonb_agg(jsonb_build_object('design_asset_id',design_asset_id,'version_id',version_id)),'[]'::jsonb) from added),
    (select coalesce(jsonb_agg(jsonb_build_object('design_asset_id',design_asset_id,'version_id',version_id)),'[]'::jsonb) from removed),
    (select coalesce(jsonb_agg(jsonb_build_object('design_asset_id',design_asset_id,'this_version_id',this_version_id,'compare_version_id',compare_version_id)),'[]'::jsonb) from changed)
    into v_added, v_removed, v_changed;
  return jsonb_build_object(
    'this_release', v_this_json,
    'compare_to', v_other_json,
    'item_diff', jsonb_build_object('added', v_added, 'removed', v_removed, 'changed_version', v_changed)
  );
end $function$;
CREATE OR REPLACE FUNCTION public.list_release_activity(p_release_id uuid, p_cursor_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 25)
 RETURNS TABLE(out_id uuid, out_event_type text, out_occurred_at timestamp with time zone, out_actor_profile_id uuid, out_subject_kind text, out_subject_id uuid, out_subject_label text, out_subject_snapshot jsonb, out_payload jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ws uuid; v_pj uuid;
begin
  select workspace_id, project_id into v_ws, v_pj from public.vp_read_releases releases where id = p_release_id;
  if v_ws is null then return; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.view') then
    raise exception 'list_release_activity: forbidden (release.view)' using errcode='42501';
  end if;
  return query
    select ae.id, ae.event_type, ae.occurred_at, ae.actor_profile_id,
           ae.subject_kind, ae.subject_id, ae.subject_label, ae.subject_snapshot, ae.payload
      from public.vp_read_activity_events ae
     where ae.workspace_id = v_ws
       and ((ae.subject_kind = 'release' and ae.subject_id = p_release_id)
         or (ae.subject_kind = 'release_item'
             and ae.subject_id in (select id from public.vp_read_release_items release_items where release_id = p_release_id)))
       and (p_cursor_at is null
            or ae.occurred_at < p_cursor_at
            or (ae.occurred_at = p_cursor_at and ae.id < coalesce(p_cursor_id,'00000000-0000-0000-0000-000000000000'::uuid)))
     order by ae.occurred_at desc, ae.id desc
     limit greatest(1, least(coalesce(p_limit, 25), 200));
end $function$;
CREATE OR REPLACE FUNCTION public.list_releases_dashboard(p_ws_id uuid, p_proj_id uuid DEFAULT NULL::uuid, p_view text DEFAULT 'all'::text, p_status_filter text[] DEFAULT NULL::text[], p_release_type_filter text[] DEFAULT NULL::text[], p_published_by_ids uuid[] DEFAULT NULL::uuid[], p_search text DEFAULT NULL::text, p_include_discarded boolean DEFAULT false, p_cursor_released_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 25, p_saved_view_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(out_release_id uuid, out_workspace_id uuid, out_project_id uuid, out_project_name text, out_code text, out_name text, out_release_type text, out_status text, out_channel text, out_released_at timestamp with time zone, out_withdrawn_at timestamp with time zone, out_discarded_at timestamp with time zone, out_created_by_profile_id uuid, out_published_by_profile_id uuid, out_created_at timestamp with time zone, out_updated_at timestamp with time zone, out_item_count integer, out_next_cursor_at timestamp with time zone, out_next_cursor_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller uuid;
  v_saved jsonb;
  v_view text := coalesce(p_view, 'all');
  v_lim integer := greatest(1, least(coalesce(p_limit, 25), 200));
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'list_releases_dashboard: authentication required' using errcode='42501';
  end if;
  if p_proj_id is not null then
    if not public.lign_has_capability(p_proj_id, p_ws_id, 'release.view') then
      raise exception 'list_releases_dashboard: forbidden (release.view)' using errcode='42501';
    end if;
  end if;
  if p_saved_view_id is not null then
    select payload into v_saved from public.user_saved_views
     where id = p_saved_view_id and workspace_id = p_ws_id and profile_id = v_caller;
    if v_saved is null then
      raise exception 'list_releases_dashboard: saved view not found' using errcode='23503';
    end if;
  end if;
  return query
    select r.id, r.workspace_id, r.project_id, p.name,
           r.code, r.name, r.release_type, r.status, r.channel,
           r.released_at, r.withdrawn_at, r.discarded_at,
           r.created_by_profile_id, r.published_by_profile_id,
           r.created_at, r.updated_at,
           (select count(*)::int from public.vp_read_release_items ri where ri.release_id = r.id),
           r.released_at, r.id
      from public.vp_read_releases r
      join public.projects p on p.id = r.project_id
     where r.workspace_id = p_ws_id
       and (p_proj_id is null or r.project_id = p_proj_id)
       and (p_proj_id is not null or public.lign_has_capability(r.project_id, r.workspace_id, 'release.view'))
       and (v_view <> 'draft'          or r.status = 'draft')
       and (v_view <> 'released'       or r.status = 'released')
       and (v_view <> 'withdrawn'      or r.status = 'withdrawn')
       and (v_view <> 'discarded'      or r.discarded_at is not null)
       and (v_view <> 'published_by_me' or r.published_by_profile_id = v_caller)
       and (p_include_discarded or v_view = 'discarded' or r.discarded_at is null)
       and (p_status_filter is null or r.status = any (p_status_filter))
       and (p_release_type_filter is null or r.release_type = any (p_release_type_filter))
       and (p_published_by_ids is null or r.published_by_profile_id = any (p_published_by_ids))
       and (p_search is null
            or r.name ilike '%' || p_search || '%'
            or (r.code is not null and r.code ilike '%' || p_search || '%'))
       and (p_cursor_released_at is null
            or (r.released_at is not null and (r.released_at < p_cursor_released_at
                or (r.released_at = p_cursor_released_at and r.id < coalesce(p_cursor_id,'00000000-0000-0000-0000-000000000000'::uuid)))))
     order by r.released_at desc nulls last, r.id desc
     limit v_lim;
end $function$;
CREATE OR REPLACE FUNCTION public.get_release_inbox_count(p_ws_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_r30 int; v_dr int; v_per jsonb;
begin
  if auth.uid() is null then
    raise exception 'get_release_inbox_count: authentication required' using errcode='42501';
  end if;
  select coalesce(sum(case when r.status='released' and r.released_at >= (now() - interval '30 days') then 1 else 0 end),0)::int,
         coalesce(sum(case when r.status='draft' and r.discarded_at is null then 1 else 0 end),0)::int
    into v_r30, v_dr
    from public.vp_read_releases r
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'release.view');
  with per as (
    select r.project_id,
           sum(case when r.status='released' and r.released_at >= (now() - interval '30 days') then 1 else 0 end)::int as released_trailing_30d
      from public.vp_read_releases r
     where r.workspace_id = p_ws_id
       and public.lign_has_capability(r.project_id, r.workspace_id, 'release.view')
     group by r.project_id
  )
  select jsonb_agg(jsonb_build_object('project_id', project_id, 'released_trailing_30d', released_trailing_30d))
    into v_per from per;
  return jsonb_build_object(
    'workspace_released_trailing_30d', v_r30,
    'workspace_draft_count', v_dr,
    'per_project', coalesce(v_per, '[]'::jsonb)
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_project_release_metrics(p_project_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ws uuid; v_result jsonb;
begin
  select workspace_id into v_ws from public.projects where id = p_project_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(p_project_id, v_ws, 'release.view') then
    raise exception 'get_project_release_metrics: forbidden (release.view)' using errcode='42501';
  end if;
  select jsonb_build_object(
    'total_draft', coalesce(sum(case when status='draft' then 1 else 0 end),0)::int,
    'total_released', coalesce(sum(case when status='released' then 1 else 0 end),0)::int,
    'total_withdrawn', coalesce(sum(case when status='withdrawn' then 1 else 0 end),0)::int,
    'released_trailing_30d', coalesce(sum(case when status='released' and released_at >= (now() - interval '30 days') then 1 else 0 end),0)::int,
    'released_trailing_90d', coalesce(sum(case when status='released' and released_at >= (now() - interval '90 days') then 1 else 0 end),0)::int,
    'by_type', jsonb_build_object(
      'internal',   coalesce(sum(case when release_type='internal' then 1 else 0 end),0)::int,
      'preview',    coalesce(sum(case when release_type='preview' then 1 else 0 end),0)::int,
      'client',     coalesce(sum(case when release_type='client' then 1 else 0 end),0)::int,
      'regulatory', coalesce(sum(case when release_type='regulatory' then 1 else 0 end),0)::int,
      'final',      coalesce(sum(case when release_type='final' then 1 else 0 end),0)::int,
      'patch',      coalesce(sum(case when release_type='patch' then 1 else 0 end),0)::int,
      'hotfix',     coalesce(sum(case when release_type='hotfix' then 1 else 0 end),0)::int
    ),
    'chain_head_count', coalesce(sum(case when superseded_by_release_id is null and status='released' then 1 else 0 end),0)::int,
    'discarded_count', coalesce(sum(case when discarded_at is not null then 1 else 0 end),0)::int
  ) into v_result from public.vp_read_releases releases where project_id = p_project_id;
  return v_result;
end $function$;
CREATE OR REPLACE FUNCTION public.get_workspace_release_metrics(p_ws_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_result jsonb; v_top5 jsonb;
begin
  if auth.uid() is null then
    raise exception 'get_workspace_release_metrics: authentication required' using errcode='42501';
  end if;
  select jsonb_build_object(
    'total_draft', coalesce(sum(case when status='draft' then 1 else 0 end),0)::int,
    'total_released', coalesce(sum(case when status='released' then 1 else 0 end),0)::int,
    'total_withdrawn', coalesce(sum(case when status='withdrawn' then 1 else 0 end),0)::int,
    'released_trailing_30d', coalesce(sum(case when status='released' and released_at >= (now() - interval '30 days') then 1 else 0 end),0)::int,
    'released_trailing_90d', coalesce(sum(case when status='released' and released_at >= (now() - interval '90 days') then 1 else 0 end),0)::int,
    'by_type', jsonb_build_object(
      'internal',   coalesce(sum(case when release_type='internal' then 1 else 0 end),0)::int,
      'preview',    coalesce(sum(case when release_type='preview' then 1 else 0 end),0)::int,
      'client',     coalesce(sum(case when release_type='client' then 1 else 0 end),0)::int,
      'regulatory', coalesce(sum(case when release_type='regulatory' then 1 else 0 end),0)::int,
      'final',      coalesce(sum(case when release_type='final' then 1 else 0 end),0)::int,
      'patch',      coalesce(sum(case when release_type='patch' then 1 else 0 end),0)::int,
      'hotfix',     coalesce(sum(case when release_type='hotfix' then 1 else 0 end),0)::int
    ),
    'chain_head_count', coalesce(sum(case when superseded_by_release_id is null and status='released' then 1 else 0 end),0)::int,
    'discarded_count', coalesce(sum(case when discarded_at is not null then 1 else 0 end),0)::int
  ) into v_result
  from public.vp_read_releases r
  where r.workspace_id = p_ws_id
    and public.lign_has_capability(r.project_id, r.workspace_id, 'release.view');
  with per as (
    select r.project_id,
           sum(case when r.status='released' and r.released_at >= (now() - interval '30 days') then 1 else 0 end)::int as released_trailing_30d
      from public.vp_read_releases r
     where r.workspace_id = p_ws_id
       and public.lign_has_capability(r.project_id, r.workspace_id, 'release.view')
     group by r.project_id
     order by released_trailing_30d desc
     limit 5
  )
  select jsonb_agg(jsonb_build_object('project_id', project_id, 'released_trailing_30d', released_trailing_30d))
    into v_top5 from per;
  return v_result || jsonb_build_object('per_project_top5', coalesce(v_top5, '[]'::jsonb));
end $function$;
CREATE OR REPLACE FUNCTION public.list_releases_for_asset(p_design_asset_id uuid)
 RETURNS TABLE(out_release_id uuid, out_code text, out_name text, out_release_type text, out_status text, out_released_at timestamp with time zone, out_version_id uuid, out_version_sequence integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ws uuid; v_pj uuid;
begin
  select workspace_id, project_id into v_ws, v_pj from public.vp_read_design_assets design_assets where id = p_design_asset_id;
  if v_ws is null then return; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.view') then
    raise exception 'list_releases_for_asset: forbidden (release.view)' using errcode='42501';
  end if;
  return query
    select r.id, r.code, r.name, r.release_type, r.status, r.released_at,
           ri.version_id, av.sequence
      from public.vp_read_release_items ri
      join public.vp_read_releases r  on r.id = ri.release_id
      join public.vp_read_asset_versions av on av.id = ri.version_id
     where ri.design_asset_id = p_design_asset_id
     order by r.released_at desc nulls last, r.id desc;
end $function$;
CREATE OR REPLACE FUNCTION public.list_releases_for_version(p_version_id uuid)
 RETURNS TABLE(out_release_id uuid, out_code text, out_name text, out_release_type text, out_status text, out_released_at timestamp with time zone, out_version_id uuid, out_version_sequence integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ws uuid; v_pj uuid;
begin
  select workspace_id, project_id into v_ws, v_pj from public.vp_read_asset_versions asset_versions where id = p_version_id;
  if v_ws is null then return; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.view') then
    raise exception 'list_releases_for_version: forbidden (release.view)' using errcode='42501';
  end if;
  return query
    select r.id, r.code, r.name, r.release_type, r.status, r.released_at,
           ri.version_id, av.sequence
      from public.vp_read_release_items ri
      join public.vp_read_releases r  on r.id = ri.release_id
      join public.vp_read_asset_versions av on av.id = ri.version_id
     where ri.version_id = p_version_id
     order by r.released_at desc nulls last, r.id desc;
end $function$;
CREATE OR REPLACE FUNCTION public.get_release_readiness_for_publish(p_design_asset_id uuid, p_version_id uuid, p_release_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ws uuid; v_pj uuid; v_approval jsonb; v_req jsonb;
  v_review_count int; v_blockers jsonb := '[]'::jsonb; v_can boolean := true;
begin
  select workspace_id, project_id into v_ws, v_pj from public.vp_read_design_assets design_assets where id = p_design_asset_id;
  if v_ws is null then
    return jsonb_build_object('can_publish', false,
      'blocking_conditions', jsonb_build_array(jsonb_build_object('code','asset_not_found','message','Design asset not found','source','evidence')),
      'approval_evidence', null, 'requirement_evidence', null, 'review_evidence', null);
  end if;
  if not public.lign_has_capability(v_pj, v_ws, 'release.view') then
    raise exception 'get_release_readiness_for_publish: forbidden (release.view)' using errcode='42501';
  end if;
  v_approval := public.get_approval_readiness(p_version_id);
  v_req := public.get_release_readiness_for_version(p_version_id);
  select count(*)::int into v_review_count
    from public.vp_read_reviews rv where rv.version_id = p_version_id and rv.status = 'completed';
  if v_approval is null or coalesce((v_approval->>'has_approved')::boolean, false) is not true then
    v_can := false;
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code','no_approved_request',
      'message','No approved approval request for this version.',
      'source','approval'));
  end if;
  if p_release_type in ('regulatory','final') then
    if v_req is not null and coalesce((v_req->>'critical_unsatisfied_count')::int, 0) > 0 then
      v_can := false;
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'code','critical_requirements_unsatisfied',
        'message','Regulatory / final releases require zero critical unsatisfied requirements.',
        'source','requirement'));
    end if;
    if v_req is not null and coalesce((v_req->>'critical_unassessed_count')::int, 0) > 0 then
      v_can := false;
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'code','critical_requirements_unassessed',
        'message','Regulatory / final releases require zero critical unassessed requirements.',
        'source','requirement'));
    end if;
  elsif p_release_type = 'client' then
    if v_req is not null and coalesce((v_req->>'critical_unsatisfied_count')::int, 0) > 0 then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'code','client_release_has_critical_unsat',
        'message','Client release has critical unsatisfied requirements (soft warning).',
        'source','requirement'));
    end if;
  end if;
  return jsonb_build_object(
    'can_publish', v_can,
    'blocking_conditions', v_blockers,
    'approval_evidence', v_approval,
    'requirement_evidence', v_req,
    'review_evidence', jsonb_build_object('completed_review_count', v_review_count)
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_proposal_revision(p_revision_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare r public.proposal_revisions%rowtype;begin
 select * into r from public.vp_read_proposal_revisions proposal_revisions where id=p_revision_id;
 if r.id is null or not public.lign_has_capability(r.project_id,r.workspace_id,'project.view') then raise exception 'Proposal revision access required' using errcode='42501';end if;
 return to_jsonb(r);end; $function$;
CREATE OR REPLACE FUNCTION public.list_notifications_inbox(p_ws_id uuid, p_tab text, p_category_filter text[], p_priority_filter text[], p_source_filter text[], p_date_from timestamp with time zone, p_date_to timestamp with time zone, p_cursor_created_at timestamp with time zone, p_cursor_id uuid, p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid          uuid;
  v_limit        int;
  v_rows         jsonb;
  v_next_cursor  jsonb;
  v_facets       jsonb;
  v_total        int;
  v_unread       int;
  v_by_cat       jsonb;
  v_by_pri       jsonb;
  v_has_more     boolean;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'list_notifications_inbox: authentication required' using errcode='42501';
  end if;
  -- Personal capability check (implicit-pass for every authenticated user in v1).
  if not public.lign_has_capability(null, p_ws_id, 'notification.view') then
    raise exception 'list_notifications_inbox: forbidden (notification.view)' using errcode='42501';
  end if;

  v_limit := coalesce(nullif(p_limit, 0), 50);
  if v_limit > 200 then v_limit := 200; end if;

  with base as (
    select n.*
      from public.vp_read_notifications n
     where n.recipient_profile_id = v_uid
       and n.workspace_id = p_ws_id
       and (
         coalesce(p_tab, 'all') = 'all'
           and n.dismissed_at is null and n.archived_at is null
         or coalesce(p_tab, 'all') = 'unread'
           and n.read_at is null and n.dismissed_at is null and n.archived_at is null
         or coalesce(p_tab, 'all') = 'mentions'
           and n.category = 'mentions' and n.dismissed_at is null and n.archived_at is null
         or coalesce(p_tab, 'all') = 'assigned'
           and n.category = 'assigned_to_me' and n.dismissed_at is null and n.archived_at is null
         or coalesce(p_tab, 'all') = 'governance'
           and n.category = 'governance_state_change' and n.dismissed_at is null and n.archived_at is null
         or coalesce(p_tab, 'all') = 'archived'
           and n.archived_at is not null
       )
       and (p_category_filter is null or n.category = any (p_category_filter))
       and (p_priority_filter is null or n.priority = any (p_priority_filter))
       and (p_source_filter is null or split_part(n.event_type, '.', 1) = any (p_source_filter))
       and (p_date_from is null or n.created_at >= p_date_from)
       and (p_date_to is null or n.created_at <= p_date_to)
  ),
  paged as (
    select *
      from base
     where (p_cursor_created_at is null and p_cursor_id is null)
        or (created_at, id) < (p_cursor_created_at, p_cursor_id)
     order by created_at desc, id desc
     limit v_limit + 1
  ),
  paged_capped as (
    select * from paged order by created_at desc, id desc limit v_limit
  )
  select
    coalesce(jsonb_agg(to_jsonb(pc) order by pc.created_at desc, pc.id desc), '[]'::jsonb),
    (select count(*) > v_limit from paged)
  into v_rows, v_has_more
  from paged_capped pc;

  -- Compute next_cursor: last row's (created_at, id) if has_more.
  if v_has_more and jsonb_array_length(v_rows) > 0 then
    v_next_cursor := jsonb_build_object(
      'created_at', v_rows -> (jsonb_array_length(v_rows) - 1) ->> 'created_at',
      'id', v_rows -> (jsonb_array_length(v_rows) - 1) ->> 'id'
    );
  else
    v_next_cursor := null;
  end if;

  -- Facets: total non-dismissed/archived + unread + per-category + per-priority.
  select
    count(*)::int,
    count(*) filter (where read_at is null)::int,
    coalesce(jsonb_object_agg(cat, cnt) filter (where cat is not null), '{}'::jsonb),
    coalesce(jsonb_object_agg(pri, pcnt) filter (where pri is not null), '{}'::jsonb)
    into v_total, v_unread, v_by_cat, v_by_pri
  from (
    select category as cat, priority as pri, count(*) as cnt, count(*) as pcnt, read_at
      from public.vp_read_notifications notifications
     where recipient_profile_id = v_uid
       and workspace_id = p_ws_id
       and dismissed_at is null
       and archived_at is null
     group by category, priority, read_at
  ) s;

  v_facets := jsonb_build_object(
    'total_count', v_total,
    'unread_count', v_unread,
    'by_category', v_by_cat,
    'by_priority', v_by_pri
  );

  return jsonb_build_object(
    'rows', v_rows,
    'next_cursor', v_next_cursor,
    'has_more', v_has_more,
    'facets', v_facets
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_notification_badge_count(p_ws_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid       uuid;
  v_total     int;
  v_by_cat    jsonb;
  v_has_crit  boolean;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'get_notification_badge_count: authentication required' using errcode='42501';
  end if;
  if not public.lign_has_capability(null, p_ws_id, 'notification.view') then
    raise exception 'get_notification_badge_count: forbidden (notification.view)' using errcode='42501';
  end if;

  select
    coalesce(sum(cnt), 0)::int,
    coalesce(jsonb_object_agg(category, cnt) filter (where category is not null), '{}'::jsonb),
    bool_or(has_crit)
    into v_total, v_by_cat, v_has_crit
  from (
    select category,
           count(*)::int as cnt,
           bool_or(priority = 'critical') as has_crit
      from public.vp_read_notifications notifications
     where recipient_profile_id = v_uid
       and workspace_id = p_ws_id
       and read_at is null
       and dismissed_at is null
       and archived_at is null
       and priority <> 'informational'
     group by category
  ) s;

  return jsonb_build_object(
    'total_unread', v_total,
    'by_category', coalesce(v_by_cat, '{}'::jsonb),
    'has_critical', coalesce(v_has_crit, false)
  );
end $function$;
CREATE OR REPLACE FUNCTION public.get_notification_center(p_ws_id uuid, p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid   uuid;
  v_limit int;
  v_rows  jsonb;
  v_total int;
  v_more  boolean;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'get_notification_center: authentication required' using errcode='42501';
  end if;
  if not public.lign_has_capability(null, p_ws_id, 'notification.view') then
    raise exception 'get_notification_center: forbidden (notification.view)' using errcode='42501';
  end if;

  v_limit := coalesce(nullif(p_limit, 0), 15);
  if v_limit > 100 then v_limit := 100; end if;

  select
    coalesce(jsonb_agg(to_jsonb(n) order by n.created_at desc, n.id desc), '[]'::jsonb)
    into v_rows
  from (
    select *
      from public.vp_read_notifications notifications
     where recipient_profile_id = v_uid
       and workspace_id = p_ws_id
       and read_at is null
       and dismissed_at is null
       and archived_at is null
     order by created_at desc, id desc
     limit v_limit
  ) n;

  select count(*)::int into v_total
    from public.vp_read_notifications notifications
   where recipient_profile_id = v_uid
     and workspace_id = p_ws_id
     and read_at is null
     and dismissed_at is null
     and archived_at is null;

  v_more := v_total > v_limit;

  return jsonb_build_object(
    'rows', v_rows,
    'has_more', v_more,
    'total_unread', v_total
  );
end $function$;
CREATE OR REPLACE FUNCTION public.list_notifications_by_source(p_source_kind text, p_source_id uuid, p_limit integer)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid   uuid;
  v_limit int;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'list_notifications_by_source: authentication required' using errcode='42501';
  end if;
  if not public.lign_has_capability(null, null, 'notification.view') then
    raise exception 'list_notifications_by_source: forbidden (notification.view)' using errcode='42501';
  end if;

  v_limit := coalesce(nullif(p_limit, 0), 50);
  if v_limit > 200 then v_limit := 200; end if;

  return query
    select to_jsonb(n)
      from public.vp_read_notifications n
     where n.subject_kind = p_source_kind
       and n.subject_id = p_source_id
       and n.recipient_profile_id = v_uid
     order by n.created_at desc, n.id desc
     limit v_limit;
end $function$;
alter table public.design_version_reviews enable row level security;
revoke all on public.design_version_reviews from anon,authenticated;
grant all on public.design_version_reviews to service_role;
create policy design_version_reviews_read on public.design_version_reviews for select to authenticated using(public.lign_design_team((select project_id from public.asset_versions where id=version_id)));
grant select on public.design_version_reviews to authenticated;
alter table public.design_version_review_events enable row level security;
revoke all on public.design_version_review_events from anon,authenticated;
grant all on public.design_version_review_events to service_role;
create policy design_version_review_events_read on public.design_version_review_events for select to authenticated using(public.lign_design_team((select project_id from public.asset_versions where id=version_id)));
grant select on public.design_version_review_events to authenticated;
alter table public.design_version_shares enable row level security;
revoke all on public.design_version_shares from anon,authenticated;
grant all on public.design_version_shares to service_role;
alter table public.design_share_events enable row level security;
revoke all on public.design_share_events from anon,authenticated;
grant all on public.design_share_events to service_role;
create policy design_share_events_read on public.design_share_events for select to authenticated using(public.lign_design_team((select project_id from public.asset_versions where id=version_id)));
grant select on public.design_share_events to authenticated;
revoke all on function public.lign_design_team_for(uuid,uuid) from public,anon,authenticated;
revoke all on function public.lign_design_team(uuid) from public,anon,authenticated;
grant execute on function public.lign_design_team(uuid) to authenticated,service_role;
revoke all on function public.lign_design_participant_user(uuid,uuid) from public,anon,authenticated;
revoke all on function public.lign_version_internally_approved(uuid) from public,anon,authenticated;
revoke all on function public.lign_can_read_design_version(uuid) from public,anon,authenticated;
grant execute on function public.lign_can_read_design_version(uuid) to authenticated,service_role;
revoke all on function public.lign_can_read_design_asset(uuid) from public,anon,authenticated;
grant execute on function public.lign_can_read_design_asset(uuid) to authenticated,service_role;
revoke all on function public.lign_can_read_design_review(uuid) from public,anon,authenticated;
grant execute on function public.lign_can_read_design_review(uuid) to authenticated,service_role;
revoke all on function public.lign_can_read_design_approval(uuid) from public,anon,authenticated;
grant execute on function public.lign_can_read_design_approval(uuid) to authenticated,service_role;
revoke all on function public.lign_can_read_proposal_revision(uuid) from public,anon,authenticated;
grant execute on function public.lign_can_read_proposal_revision(uuid) to authenticated,service_role;
revoke all on function public.lign_design_row_project(jsonb,integer) from public,anon,authenticated;
revoke all on function public.lign_design_row_visible(text,jsonb,integer) from public,anon,authenticated;
grant execute on function public.lign_design_row_visible(text,jsonb,integer) to authenticated,service_role;
revoke all on function public.transition_design_version_review(uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.transition_design_version_review(uuid,bigint,text,text) to authenticated,service_role;
revoke all on function public.grant_design_version_share(uuid,uuid) from public,anon,authenticated;
revoke all on function public.share_design_version(uuid,uuid[]) from public,anon,authenticated;
grant execute on function public.share_design_version(uuid,uuid[]) to authenticated,service_role;
revoke all on function public.revoke_design_version_share(uuid,uuid) from public,anon,authenticated;
grant execute on function public.revoke_design_version_share(uuid,uuid) to authenticated,service_role;
revoke all on function public.get_design_version_access(uuid) from public,anon,authenticated;
grant execute on function public.get_design_version_access(uuid) to authenticated,service_role;
revoke all on function public.guard_design_version_review() from public,anon,authenticated;
revoke all on function public.preserve_design_review_history() from public,anon,authenticated;
revoke all on function public.guard_design_discussion_scope() from public,anon,authenticated;
revoke all on function public.guard_design_request_scope() from public,anon,authenticated;
revoke all on function public.publish_design_request_shares() from public,anon,authenticated;
revoke all on function public.sync_deliverable_design_review() from public,anon,authenticated;
revoke all on function public.lign_shared_design_for_user(uuid,uuid) from public,anon,authenticated;
revoke all on function public.lign_design_notification_allowed(jsonb,uuid) from public,anon,authenticated;
-- Presence uses private, version-authorized channels rather than public room names.
create or replace function public.lign_can_join_design_presence(p_topic text)
returns boolean language plpgsql stable security definer set search_path=''
as $$ begin
 if p_topic is null or p_topic !~ '^lign:presence:version:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then return false;end if;
 return public.lign_can_read_design_version(split_part(p_topic,':',4)::uuid);end; $$;
revoke all on function public.lign_can_join_design_presence(text) from public,anon;
grant execute on function public.lign_can_join_design_presence(text) to authenticated,service_role;
create policy vp_presence_read on realtime.messages for select to authenticated using(extension='presence' and public.lign_can_join_design_presence(realtime.topic()));
create policy vp_presence_write on realtime.messages for insert to authenticated with check(extension='presence' and public.lign_can_join_design_presence(realtime.topic()));
-- Scoped work queue and in-app routing for internal sign-off.
create or replace function public.get_design_review_queue(p_workspace_id uuid,p_project_id uuid default null,p_after uuid default null,p_limit integer default 30)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare internal boolean;v jsonb;begin
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'Choose a page size between 1 and 50' using errcode='22023';end if;
 select exists(select 1 from public.projects p where p.workspace_id=p_workspace_id and (p_project_id is null or p.id=p_project_id) and public.lign_design_team(p.id)) into internal;
 if not internal then return jsonb_build_object('internal',false,'pending',0,'items','[]'::jsonb,'nextCursor',null);end if;
 with eligible as(select v.id,v.project_id,v.design_asset_id,v.sequence,r.author_id,r.submitted_at,a.name,pr.name as project_name,prof.display_name as author_name
 from public.design_version_reviews r join public.asset_versions v on v.id=r.version_id join public.design_assets a on a.id=v.design_asset_id join public.projects pr on pr.id=v.project_id left join public.profiles prof on prof.id=r.author_id
 where r.stage='submitted' and v.workspace_id=p_workspace_id and (p_project_id is null or v.project_id=p_project_id) and pr.archived_at is null and pr.status<>'archived' and public.lign_design_team(v.project_id)), page as(select * from eligible where p_after is null or id>p_after order by id limit p_limit+1)
 select jsonb_build_object('internal',true,'pending',(select count(*) from eligible),'items',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) from(select * from page order by id limit p_limit)x),'nextCursor',case when (select count(*) from page)>p_limit then (select id from page order by id offset p_limit-1 limit 1) else null end) into v;return v;end; $$;
create or replace function public.notify_design_review(p_version_id uuid,p_action text)
returns void language plpgsql security definer set search_path=''
as $$ declare v public.asset_versions%rowtype;r public.design_version_reviews%rowtype;recipients uuid[];org uuid;begin
 select * into v from public.asset_versions where id=p_version_id;
 select * into r from public.design_version_reviews where version_id=v.id;
 select organization_id into org from public.workspaces where id=v.workspace_id;
 if p_action='submit' then
 select array_agg(distinct u.id) into recipients from (select public.lign_design_participant_user(pp.id,v.project_id) as id from public.project_participants pp where pp.project_id=v.project_id and pp.status='active' and pp.role='lead')u where u.id is not null and u.id<>r.author_id and public.lign_design_team_for(v.project_id,u.id) and not exists(select 1 from public.version_files vf join public.files f on f.id=vf.file_id where vf.asset_version_id=v.id and f.uploaded_by_profile_id=u.id);
 if coalesce(cardinality(recipients),0)=0 then select array_agg(distinct wm.user_id) into recipients from public.workspace_members wm where wm.workspace_id=v.workspace_id and wm.status='active' and wm.role in ('owner','admin') and wm.user_id<>r.author_id and public.lign_design_team_for(v.project_id,wm.user_id) and not exists(select 1 from public.version_files vf join public.files f on f.id=vf.file_id where vf.asset_version_id=v.id and f.uploaded_by_profile_id=wm.user_id);end if;
 if coalesce(cardinality(recipients),0)=0 then select array_agg(distinct om.user_id) into recipients from public.organization_members om where om.organization_id=org and om.status='active' and om.role in ('owner','admin') and om.user_id<>r.author_id and not exists(select 1 from public.version_files vf join public.files f on f.id=vf.file_id where vf.asset_version_id=v.id and f.uploaded_by_profile_id=om.user_id);end if;
 elsif p_action in ('approve','request_changes') then recipients:=array[r.author_id];else return;end if;
 if coalesce(cardinality(recipients),0)=0 then return;end if;
 insert into public.activity_events(workspace_id,project_id,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,payload)
 values(v.workspace_id,v.project_id,case when p_action='submit' then 'design.internal_review_requested' else 'design.internal_review_decided' end,auth.uid(),'user','asset_version',v.id,'v'||v.sequence,jsonb_build_object('recipient_ids',recipients,'review_action',p_action));end; $$;
revoke all on function public.get_design_review_queue(uuid,uuid,uuid,integer),public.notify_design_review(uuid,text) from public,anon,authenticated;
grant execute on function public.get_design_review_queue(uuid,uuid,uuid,integer) to authenticated,service_role;
