-- APP 027: a leadership-only view of existing access, with no new grants.
-- Include inherited administration, explicit project roles, pending external
-- participants and unaccepted invitations. Never return invitation tokens.
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
  select pp.id,pp.role,pr.id project_id,pr.name project_name,pr.status project_status,
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
    'workspaceId',r.workspace_id,'role',r.role,'source',r.source,'sourceId',r.source_id,'status',r.status)
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
revoke all on function public.get_access_directory(uuid,uuid) from public,anon;
grant execute on function public.get_access_directory(uuid,uuid) to authenticated;
