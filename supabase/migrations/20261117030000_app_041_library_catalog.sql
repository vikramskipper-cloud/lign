-- Read-only catalogue of authorised working collections or immutable approved revisions.
-- Existing author, publication and file permissions remain the authority.
create or replace function public.get_library_catalog(
 p_organization_id uuid,p_view text default 'published',p_search text default '',
 p_kind text default 'all',p_tag text default '',p_stage text default 'all',p_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_library jsonb;v_result jsonb;v_search text:=lower(trim(coalesce(p_search,'')));
begin
 if not public.lign_is_org_member(p_organization_id) then
  raise exception 'Organisation membership required' using errcode='42501';
 end if;
 if p_view is null or p_view not in ('published','contributions','review')
 or p_kind is null or p_kind not in ('all','template','moodboard','references','designs')
 or p_stage is null or p_stage not in ('all','draft','in_review','changes_requested','published')
 or p_offset is null or p_offset<0 or p_offset>100000 or length(v_search)>160 or length(coalesce(p_tag,''))>100 then
  raise exception 'Invalid library filters' using errcode='22023';
 end if;
 if p_view='review' and not public.lign_is_org_admin(p_organization_id) then
  raise exception 'Administrator access required' using errcode='42501';
 end if;
 v_library:=public.get_organization_library(p_organization_id);
 with eligible as materialized (
  select case when p_view='published' then
   c||(c->'published')||jsonb_build_object('status','published','canEdit',false)
   else c end as c
  from jsonb_array_elements(v_library->'collections') c
  where case p_view when 'published' then c->'published'<>'null'::jsonb
   when 'review' then (c->>'canReview')::boolean
   else (c->>'canSeeDraft')::boolean end
 ), filtered as materialized (
  select c,case when p_view='published' then public.get_library_items((c->>'id')::uuid)
   else public.get_library_draft_items((c->>'id')::uuid) end as items
  from eligible where (p_kind='all' or c->>'kind'=p_kind)
   and (p_stage='all' or c->>'status'=p_stage)
   and (coalesce(p_tag,'')='' or c->'tags' ? p_tag)
 ), searched as materialized (
  select c,items,
   (select coalesce(jsonb_agg(jsonb_build_object('id',i->>'id','title',i->>'title','fileName',i->'file'->>'name')),'[]'::jsonb)
    from jsonb_array_elements(items) i where v_search<>'' and
    position(v_search in lower(concat_ws(' ',i->>'title',i->>'description',i->>'url',i->'file'->>'name')))>0) matches
  from filtered
 ), matched as materialized (
  select c||jsonb_build_object('itemCount',jsonb_array_length(items),
   'cover',(select i->'file' from jsonb_array_elements(items) i where i->'file'->>'mime' in ('image/png','image/jpeg','image/webp') limit 1),
   'matchCount',jsonb_array_length(matches),'matches',(select coalesce(jsonb_agg(m),'[]'::jsonb) from (select m from jsonb_array_elements(matches) m limit 3) x)) as c
  from searched where v_search='' or jsonb_array_length(matches)>0
   or position(v_search in lower(concat_ws(' ',c->>'title',c->>'description',c->>'authorName',(c->'tags')::text)))>0
 ), page as (
  select c from matched order by lower(c->>'title'),c->>'id' limit 24 offset p_offset
 )
 select jsonb_build_object('collections',(select coalesce(jsonb_agg(c order by lower(c->>'title'),c->>'id'),'[]'::jsonb) from page),
  'total',(select count(*) from matched),
  'tags',(select coalesce(jsonb_agg(tag order by tag),'[]'::jsonb) from
   (select distinct jsonb_array_elements_text(coalesce(nullif(c->'tags','null'::jsonb),'[]'::jsonb)) tag from eligible) t)) into v_result;
 return v_result;
end; $$;
revoke all on function public.get_library_catalog(uuid,text,text,text,text,text,integer) from public,anon,authenticated;
grant execute on function public.get_library_catalog(uuid,text,text,text,text,text,integer) to authenticated,service_role;
