// Shared WebSocket test helpers for REALTIME 002.
// Uses real supabase-js realtime channels + real GoTrue sign-in.
// No mocks. RLS + Realtime v2 are exercised end-to-end against the live project.

import { createClient } from '@supabase/supabase-js';

export const URL  = 'https://hsfporioghapwghrvvzd.supabase.co';
export const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhzZnBvcmlvZ2hhcHdnaHJ2dnpkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUyNDUyOTUsImV4cCI6MjEwMDgyMTI5NX0.SJZl7NxG17qWxdfdp2Gu4u5XHtzWb3fCM5Z5UcbSzTE';

// Test user roster from the STORAGE 003 fixtures (workspace WS-One, project PR1).
// Passwords set via REALTIME 002 preflight.
export const USERS = {
  admin:    { id: 'c0000000-0000-0000-0000-000000000001', email: 'p_admin@lign.test',    pw: 'LignTest!2026' },
  lead:     { id: 'c0000000-0000-0000-0000-000000000002', email: 'p_lead@lign.test',     pw: 'LignTest!2026' },
  contrib:  { id: 'c0000000-0000-0000-0000-000000000003', email: 'p_contrib@lign.test',  pw: 'LignTest!2026' },
  reviewer: { id: 'c0000000-0000-0000-0000-000000000004', email: 'p_reviewer@lign.test', pw: 'LignTest!2026' },
  observer: { id: 'c0000000-0000-0000-0000-000000000005', email: 'p_observer@lign.test', pw: 'LignTest!2026' },
  none:     { id: 'c0000000-0000-0000-0000-000000000006', email: 'p_none@lign.test',     pw: 'LignTest!2026' },
  stake:    { id: 'c0000000-0000-0000-0000-000000000007', email: 'p_stake@lign.test',    pw: 'LignTest!2026' },
};

// Frozen fixture identifiers (from STORAGE 003 seed).
export const WS_ONE   = 'a0000000-0000-0000-0000-000000000001';
export const WS_TWO   = 'a0000000-0000-0000-0000-000000000002';
export const PROJ_ONE = 'd1000000-0000-0000-0000-000000000001';
export const PROJ_W2  = 'd2000000-0000-0000-0000-000000000001';
export const ASSET1   = '11000000-0000-0000-0000-000000000001';
// Draft versions still remaining after STORAGE 003 tests:
//   V1 (published: no), V2 (published: yes), V5 (draft)
export const V_DRAFT  = '21000000-0000-0000-0000-000000000001'; // V_D1 still draft

export async function signIn(user) {
  const c = createClient(URL, ANON, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    realtime: { params: { eventsPerSecond: 20 } },
  });
  const { data, error } = await c.auth.signInWithPassword({ email: user.email, password: user.pw });
  if (error) throw new Error(`signIn ${user.email}: ${error.message}`);
  return { client: c, token: data.session.access_token, refresh: data.session.refresh_token, expires_at: data.session.expires_at };
}

// Subscribe to a set of table-scoped Postgres Changes channels.
// events accumulate into `bag`, one entry per delivery.
export function subscribe(client, { table, schema='public', event='*', filter=null, tag }, bag) {
  const channelName = `${tag||table}-${Math.random().toString(36).slice(2,7)}`;
  const cfg = { event, schema, table };
  if (filter) cfg.filter = filter;
  const ch = client.channel(channelName).on('postgres_changes', cfg, (payload) => {
    bag.push({ at: Date.now(), tag: tag||table, event: payload.eventType, new: payload.new, old: payload.old, errors: payload.errors });
  });
  return new Promise((resolve, reject) => {
    ch.subscribe((status, err) => {
      if (status === 'SUBSCRIBED') resolve(ch);
      else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') reject(new Error(`${channelName}: ${status} ${err||''}`));
    });
  });
}

export const sleep = (ms) => new Promise(r => setTimeout(r, ms));

// Wait until `predicate(bag)` returns true or timeout expires.
// Returns { hit: boolean, waited_ms: number }.
export async function waitFor(bag, predicate, timeoutMs=3000, pollMs=50) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (predicate(bag)) return { hit: true, waited_ms: Date.now() - start };
    await sleep(pollMs);
  }
  return { hit: false, waited_ms: Date.now() - start };
}

export function summary(results) {
  const pass = results.filter(r => r.outcome === 'OK').length;
  const fail = results.filter(r => r.outcome !== 'OK').length;
  return { pass, fail, results };
}
