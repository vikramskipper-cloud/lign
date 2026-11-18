-- Read-only live context for the existing brief review/agreement rules.
create or replace function public.get_project_brief_readiness(p_project_id uuid,p_respondent_participant_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v_ws uuid;v_b public.project_briefs%rowtype;v_target uuid;v_user uuid;v_people jsonb;v_approver jsonb;v_refs jsonb;v_ref_error text;begin
 select workspace_id into v_ws from public.projects where id=p_project_id;
 if v_ws is null or not public.lign_has_capability(p_project_id,v_ws,'project.view') then raise exception 'Project access required' using errcode='42501';end if;
 select * into v_b from public.project_briefs where project_id=p_project_id;
 v_target:=coalesce(p_respondent_participant_id,v_b.respondent_participant_id);
 v_user:=public.lign_brief_respondent_user(v_target,p_project_id);
 select coalesce(jsonb_agg(jsonb_build_object('id',wm.user_id,'name',p.display_name,'role',pp.role) order by case pp.role when 'lead' then 0 else 1 end,pp.id),'[]'::jsonb) into v_people
 from public.project_participants pp join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active' join public.profiles p on p.id=wm.user_id
 where pp.project_id=p_project_id and pp.status='active' and pp.role in ('lead','contributor');
 select jsonb_build_object('id',pp.id,'name',coalesce(p.display_name,s.display_name,s.email::text),'pending',s.id is not null and (s.user_id is null or s.status<>'active'),'available',v_user is not null,'isRequester',coalesce(v_user=auth.uid(),false)) into v_approver
 from public.project_participants pp left join public.workspace_members wm on wm.id=pp.workspace_member_id and wm.status='active' left join public.profiles p on p.id=wm.user_id
 left join public.stakeholders s on s.id=pp.stakeholder_id and s.status in ('active','invited')
 where pp.id=v_target and pp.project_id=p_project_id and pp.status='active' and pp.role='approver' and (wm.id is not null or s.id is not null);
 begin v_refs:=public.snapshot_brief_reference_selection(p_project_id);
 exception when check_violation then v_ref_error:=sqlerrm;end;
 return jsonb_build_object('version',coalesce(v_b.edit_version,0),'respondentId',v_target,'people',v_people,'defaultOwner',v_people->0,'approver',v_approver,
 'selectedReferenceCount',(select count(*) from public.reference_cards c join public.reference_boards b on b.id=c.board_id where c.project_id=p_project_id and c.selected_for_brief and c.archived_at is null and b.archived_at is null and b.shared_at is not null),
 'referenceError',v_ref_error,'canRequest',public.lign_manage_project_brief(p_project_id),'canSubmit',coalesce(v_b.status='draft' and (public.lign_manage_project_brief(p_project_id) or public.lign_edit_project_brief(p_project_id)),false));
end; $$;
revoke all on function public.get_project_brief_readiness(uuid,uuid) from public,anon,authenticated;
grant execute on function public.get_project_brief_readiness(uuid,uuid) to authenticated,service_role;
