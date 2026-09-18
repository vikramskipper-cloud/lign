-- APP 009 F-2 enforcement: drop the frozen 1-arg finalize_release and 2-arg withdraw_release
-- overloads so the CREATE OR REPLACE-extended single functions are the only ones present.
-- Frozen positional call sites still bind unchanged: finalize_release(uuid) resolves to
-- finalize_release(uuid, text default null); withdraw_release(uuid, text) resolves to
-- withdraw_release(uuid, text, boolean default false). No dual overloads => no
-- "function is not unique" trap under named-argument resolution.
drop function if exists public.finalize_release(uuid);
drop function if exists public.withdraw_release(uuid, text);
