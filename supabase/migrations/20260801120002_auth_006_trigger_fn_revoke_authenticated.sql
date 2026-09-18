-- AUTH 006 addendum: revoke authenticated EXECUTE on the two trigger
-- functions. Trigger functions do not need to be callable via PostgREST
-- /rpc endpoints — triggers fire under the table owner's security context.
-- This eliminates the 0029 advisor WARN on these two functions.

revoke execute on function public.emit_change_lifecycle_event() from authenticated;
revoke execute on function public.emit_decision_recorded_event() from authenticated;
