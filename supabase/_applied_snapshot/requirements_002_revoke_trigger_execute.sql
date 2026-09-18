-- Trigger functions run under the definer's privileges when fired by the
-- trigger itself; direct invocation via PostgREST /rpc is neither useful nor
-- intended. Remove EXECUTE from all app-facing roles.

revoke all on function public.enforce_requirement_hierarchy()      from public, anon, authenticated;
revoke all on function public.enforce_requirement_immutability()   from public, anon, authenticated;
revoke all on function public.enforce_assessment_applicability()   from public, anon, authenticated;
revoke all on function public.enforce_assessment_immutability()    from public, anon, authenticated;

comment on function public.enforce_requirement_hierarchy()    is 'REQUIREMENTS 002: trigger-only. EXECUTE revoked from public/anon/authenticated; runs in trigger context under definer privileges.';
comment on function public.enforce_requirement_immutability() is 'REQUIREMENTS 002: trigger-only. EXECUTE revoked from public/anon/authenticated.';
comment on function public.enforce_assessment_applicability() is 'REQUIREMENTS 002: trigger-only. EXECUTE revoked from public/anon/authenticated.';
comment on function public.enforce_assessment_immutability()  is 'REQUIREMENTS 002: trigger-only. EXECUTE revoked from public/anon/authenticated.';
