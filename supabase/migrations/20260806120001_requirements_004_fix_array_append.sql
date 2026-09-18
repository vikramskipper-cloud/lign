create or replace function public.edit_requirement(
  p_requirement_id uuid, p_title text default null, p_description text default null,
  p_category text default null, p_source text default null, p_source_ref text default null, p_status text default null
) returns table (out_requirement_id uuid, out_updated boolean)
language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_ws uuid; v_pj uuid; v_code text; v_cur_status text;
        v_cur_title text; v_cur_desc text; v_cur_cat text; v_cur_src text; v_cur_ref text;
        v_changed text[] := array[]::text[];
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'edit_requirement: authentication required' using errcode='42501'; end if;
  if p_requirement_id is null then raise exception 'edit_requirement: requirement_id required' using errcode='22004'; end if;
  select workspace_id, project_id, code, status, title, description, category, source, source_ref
    into v_ws, v_pj, v_code, v_cur_status, v_cur_title, v_cur_desc, v_cur_cat, v_cur_src, v_cur_ref
    from public.requirements where id = p_requirement_id for update;
  if v_ws is null then raise exception 'edit_requirement: requirement % not found', p_requirement_id using errcode='23503'; end if;
  if not public.lign_has_capability(v_pj, v_ws, 'requirement.edit') then
    raise exception 'edit_requirement: forbidden (requirement.edit)' using errcode='42501';
  end if;
  if v_cur_status in ('superseded','archived') then
    raise exception 'edit_requirement: requirement % is % and cannot be edited', p_requirement_id, v_cur_status using errcode='23514';
  end if;
  if p_status is not null and p_status not in ('draft','active') then
    raise exception 'edit_requirement: status transition to % not allowed here (use archive_requirement or supersede_requirement)', p_status using errcode='22023';
  end if;
  if p_title is not null and length(trim(p_title)) = 0 then
    raise exception 'edit_requirement: title cannot be blank' using errcode='22023';
  end if;
  if p_title       is not null and p_title       is distinct from v_cur_title  then v_changed := array_append(v_changed, 'title');       end if;
  if p_description is not null and p_description is distinct from v_cur_desc   then v_changed := array_append(v_changed, 'description'); end if;
  if p_category    is not null and p_category    is distinct from v_cur_cat    then v_changed := array_append(v_changed, 'category');    end if;
  if p_source      is not null and p_source      is distinct from v_cur_src    then v_changed := array_append(v_changed, 'source');      end if;
  if p_source_ref  is not null and p_source_ref  is distinct from v_cur_ref    then v_changed := array_append(v_changed, 'source_ref');  end if;
  if p_status      is not null and p_status      is distinct from v_cur_status then v_changed := array_append(v_changed, 'status');      end if;
  if array_length(v_changed, 1) is null then
    return query select p_requirement_id, false; return;
  end if;
  update public.requirements
     set title=coalesce(p_title,title), description=coalesce(p_description,description),
         category=coalesce(p_category,category), source=coalesce(p_source,source),
         source_ref=coalesce(p_source_ref,source_ref), status=coalesce(p_status,status)
   where id = p_requirement_id;
  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_ws, v_pj, now(), 'requirement.updated', v_caller, 'user', 'requirement', p_requirement_id, v_code,
          jsonb_build_object('code', v_code, 'kind', 'edit', 'changed_fields', to_jsonb(v_changed),
                             'previous_status', case when 'status' = any(v_changed) then v_cur_status else null end,
                             'new_status', case when 'status' = any(v_changed) then p_status else null end),
          '{}'::jsonb);
  return query select p_requirement_id, true;
end $$;