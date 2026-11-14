-- APP 035: organisation disciplines captured during owner activation, inherited by new briefs.
alter table public.organizations add column design_disciplines text[] not null default '{}' check(cardinality(design_disciplines)<=5 and design_disciplines <@ array['interiors','architecture','product','furniture','fashion']::text[] and array_position(design_disciplines,null) is null);
alter table public.organizations add column design_profile_configured boolean not null default false;
alter table public.organizations add column design_profile_version bigint not null default 0;
create or replace function public.save_organization_design_profile(p_organization_id uuid,p_disciplines text[],p_expected_version bigint)
returns void language plpgsql security definer set search_path=''
as $$ declare v bigint;v_ids text[];begin
 if not public.lign_is_org_admin(p_organization_id) then raise exception 'Organisation owner or administrator access required' using errcode='42501';end if;
 if p_disciplines is null or cardinality(p_disciplines)>5 or not(p_disciplines <@ array['interiors','architecture','product','furniture','fashion']::text[]) or array_position(p_disciplines,null) is not null then raise exception 'Choose supported disciplines or general design' using errcode='22023';end if;
 select coalesce(array_agg(distinct id order by id),'{}') into v_ids from unnest(p_disciplines) id;
 update public.organizations set design_disciplines=v_ids,design_profile_configured=true,design_profile_version=design_profile_version+1 where id=p_organization_id and design_profile_version=p_expected_version returning design_profile_version into v;
 if v is null then raise exception 'Organisation settings changed. Reload before saving.' using errcode='PT409';end if;end; $$;
create or replace function public.get_organization_design_profile(p_organization_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ begin
 if not public.lign_is_org_member(p_organization_id) then raise exception 'Organisation membership required' using errcode='42501';end if;
 return (select jsonb_build_object('name',name,'disciplines',design_disciplines,'configured',design_profile_configured,'version',design_profile_version,'canManage',public.lign_is_org_admin(id)) from public.organizations where id=p_organization_id);end; $$;
create or replace function public.get_activation_design_profile()
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare r public.access_requests%rowtype;begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501';end if;
 select a.* into r from public.access_requests a join public.profiles p on lower(p.email::text)=lower(a.email::text) where p.id=auth.uid() and a.status='approved' order by (a.founded_organization_id is null),a.decided_at,a.id limit 1;
 if r.id is null then return jsonb_build_object('needsProfile',false);end if;
 if r.founded_organization_id is null then return jsonb_build_object('needsProfile',true);end if;
 return jsonb_build_object('needsProfile',public.lign_is_org_admin(r.founded_organization_id) and not coalesce((select design_profile_configured from public.organizations where id=r.founded_organization_id),true));end; $$;
create or replace function public.complete_approved_access_profile(p_disciplines text[] default null)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_ws uuid;v_org uuid;v_version bigint;begin
 -- The existing activation RPC enforces the approved request, verified email and owner membership.
 v_ws:=public.complete_approved_access();
 if v_ws is not null and p_disciplines is not null then
 select w.organization_id into v_org from public.workspaces w where w.id=v_ws;
 perform 1 from public.organizations where id=v_org for update;
 select design_profile_version into v_version from public.organizations where id=v_org and not design_profile_configured;
 if found then perform public.save_organization_design_profile(v_org,p_disciplines,v_version);end if;end if;
 return v_ws;end; $$;
create or replace function public.create_workspace_with_design_profile(p_name text,p_slug text,p_disciplines text[])
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_ws uuid;v_org uuid;v_version bigint;begin
 v_ws:=public.create_workspace(p_name,p_slug,null);
 select organization_id into v_org from public.workspaces where id=v_ws;
 select design_profile_version into v_version from public.organizations where id=v_org for update;
 perform public.save_organization_design_profile(v_org,p_disciplines,v_version);return v_ws;end; $$;
create or replace function public.get_project_brief(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_ws uuid; v_b public.project_briefs%rowtype;
begin
 select workspace_id into v_ws from public.projects where id=p_project_id;
 if v_ws is null or not public.lign_has_capability(p_project_id,v_ws,'project.view') then
  raise exception 'Project access required' using errcode='42501'; end if;
 select * into v_b from public.project_briefs where project_id=p_project_id;
 return jsonb_build_object('organizationDisciplines',(select to_jsonb(o.design_disciplines) from public.workspaces w join public.organizations o on o.id=w.organization_id where w.id=v_ws),'brief',case when v_b.id is null then null else to_jsonb(v_b) end,
  'canManage',public.lign_manage_project_brief(p_project_id),
  'canEdit',coalesce(public.lign_edit_project_brief(p_project_id),false),
  'canComment',public.lign_has_capability(p_project_id,v_ws,'comment.create'),
  'canGenerate',public.lign_has_capability(p_project_id,v_ws,'requirement.create'),
  'canRespond',coalesce(v_b.status='awaiting_agreement' and public.lign_brief_respondent_user(v_b.respondent_participant_id,p_project_id)=auth.uid(),false),
  'approvers',(select coalesce(jsonb_agg(jsonb_build_object('id',pp.id,'name',coalesce(p.display_name,s.display_name,s.email::text),'pending',s.id is not null and (s.user_id is null or s.status<>'active')) order by coalesce(p.display_name,s.display_name,s.email::text)),'[]'::jsonb)
   from public.project_participants pp left join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
   left join public.profiles p on p.id=wm.user_id left join public.stakeholders s on s.id=pp.stakeholder_id and s.status in ('active','invited')
   where pp.project_id=p_project_id and pp.status='active' and pp.role='approver' and (wm.id is not null or s.id is not null)),
  'owners',(select coalesce(jsonb_agg(jsonb_build_object('id',wm.user_id,'name',p.display_name) order by p.display_name),'[]'::jsonb)
   from public.project_participants pp join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active'
   join public.profiles p on p.id=wm.user_id where pp.project_id=p_project_id and pp.status='active' and pp.role in ('lead','contributor')),
  'files',(select coalesce(jsonb_agg(to_jsonb(f) order by f.created_at),'[]'::jsonb) from public.project_brief_files f where f.project_id=p_project_id and f.removed_at is null),
  'revisions',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('decision',(select to_jsonb(d)||jsonb_build_object('actorName',p.display_name) from public.project_brief_decisions d join public.profiles p on p.id=d.actor_id where d.revision_id=r.id),
   'generatedCount',(select count(*) from public.project_brief_requirement_links l where l.revision_id=r.id)) order by r.number desc),'[]'::jsonb) from public.project_brief_revisions r where r.project_id=p_project_id),
  'notes',(select coalesce(jsonb_agg(to_jsonb(n)||jsonb_build_object('authorName',p.display_name) order by n.created_at),'[]'::jsonb) from public.project_brief_notes n join public.profiles p on p.id=n.author_id where n.project_id=p_project_id));
end;
$fn$;
revoke all on function public.save_organization_design_profile(uuid,text[],bigint) from public,anon,authenticated;
grant execute on function public.save_organization_design_profile(uuid,text[],bigint) to authenticated,service_role;
revoke all on function public.get_organization_design_profile(uuid) from public,anon,authenticated;
grant execute on function public.get_organization_design_profile(uuid) to authenticated,service_role;
revoke all on function public.get_activation_design_profile() from public,anon,authenticated;
grant execute on function public.get_activation_design_profile() to authenticated,service_role;
revoke all on function public.complete_approved_access_profile(text[]) from public,anon,authenticated;
grant execute on function public.complete_approved_access_profile(text[]) to authenticated,service_role;
revoke all on function public.create_workspace_with_design_profile(text,text,text[]) from public,anon,authenticated;
grant execute on function public.create_workspace_with_design_profile(text,text,text[]) to authenticated,service_role;
