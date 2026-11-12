-- Grant (or revoke) LIGN platform administrator.
--
-- APP 021 created public.platform_admins EMPTY and on purpose: this role
-- decides who is admitted to LIGN, so it is granted out of band rather than
-- through a button in the product. Until at least one row exists, NOBODY can
-- read the access-request queue — including an organisation owner. That is the
-- intended resting state, not a bug.
--
-- THIS IS A DATA SCRIPT, NOT A MIGRATION. It must never be moved into
-- supabase/migrations/: it names a specific person, so a replay against an
-- empty database would fail on the missing profile, and it would break the
-- byte-identity guarantee ops/verify_migrations.sh enforces. Seeding rows does
-- not cause schema drift — verify_migrations.sh only compares migrations — so
-- running this from psql OR from the Supabase SQL editor is correct. No psql
-- meta-commands are used, so both work.
--
-- WHO SHOULD HOLD IT: LIGN staff only. Never a customer. It grants no access
-- to any customer workspace or project — it is not a superuser role — but it
-- does expose every applicant's name, work email and phone number, and the
-- power to admit or decline them.
--
-- USAGE: edit the two values in the DO block below, then run the whole file.

begin;

do $$
declare
  ---------------------------------------------------------------- edit these
  v_email  text := 'demo@lign.test';
  v_action text := 'grant';          -- 'grant' or 'revoke'
  ----------------------------------------------------------------------------
  v_target uuid;
  v_actor  uuid;
begin
  if v_action not in ('grant', 'revoke') then
    raise exception 'action must be grant or revoke, got %', v_action;
  end if;

  -- lower() on both sides explicitly. profiles.email is citext, and inside a
  -- function with search_path='' the citext '=' operator is invisible, which
  -- silently degrades to case-sensitive text matching — the trap that
  -- duplicated a stakeholder in APP 014. This block does not set an empty
  -- search_path, but matching the convention keeps it correct if it is ever
  -- pasted somewhere that does.
  select id into v_target from public.profiles where lower(email::text) = lower(v_email);
  if v_target is null then
    raise exception
      'no profile for %. They must sign in to LIGN at least once before they can be made a platform admin.',
      v_email;
  end if;

  -- Whoever is running this, when they are a known profile. Null when run as
  -- postgres from psql or the SQL editor, which is the normal case for the
  -- first grant — there is nobody to attribute it to yet.
  v_actor := auth.uid();

  if v_action = 'grant' then
    insert into public.platform_admins (profile_id, granted_by_profile_id, note)
    values (v_target, v_actor, 'granted via ops/grant_platform_admin.sql')
    on conflict (profile_id) do nothing;
    raise notice 'platform admin GRANTED to % (%)', v_email, v_target;
  else
    delete from public.platform_admins where profile_id = v_target;
    raise notice 'platform admin REVOKED from % (%)', v_email, v_target;
  end if;
end $$;

-- Read it back before committing, so a mistake is visible while rolling back
-- is still free.
select p.email::text as operator, pa.granted_at, pa.note
  from public.platform_admins pa
  join public.profiles p on p.id = pa.profile_id
 order by pa.granted_at;

commit;
