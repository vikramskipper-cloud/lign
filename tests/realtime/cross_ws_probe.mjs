// Cross-workspace + cross-project isolation probe.
// Contrib subscribes WITHOUT a workspace filter (or with W2 filter) so any
// row from WS_TWO would flow through if RLS were leaky. RLS should block.
// None subscribes to WS_ONE with no participant status — should also get 0.

import fs from 'node:fs';
import ws from 'ws';
import { createClient } from '@supabase/supabase-js';
import { URL, ANON, USERS, WS_ONE, WS_TWO } from './harness.mjs';

const OUT = '/tmp/lign_rt_crossws.json';
const TABLES = ['comments','annotations','asset_versions','reviews','review_participants',
                'approval_requests','approval_responses','design_assets'];

async function mk(user) {
  const c = createClient(URL, ANON, {
    auth: { autoRefreshToken:false, persistSession:false, detectSessionInUrl:false },
    realtime: { params: { eventsPerSecond: 30 }, transport: ws },
  });
  if (user) {
    const { error } = await c.auth.signInWithPassword({ email: user.email, password: user.pw });
    if (error) throw new Error(`signIn ${user.email}: ${error.message}`);
  }
  return c;
}

async function subscribe(client, bag, tag, filter) {
  const ch = client.channel(`${tag}-${Math.random().toString(36).slice(2,6)}`);
  for (const t of TABLES) {
    const cfg = { event:'*', schema:'public', table:t };
    if (filter) cfg.filter = filter;
    ch.on('postgres_changes', cfg,
      (p) => bag.push({ at:Date.now(), tag, table:t, ev:p.eventType, new:p.new, ws: p.new?.workspace_id }));
  }
  await new Promise((res, rej) => ch.subscribe((s,e) => {
    if (s==='SUBSCRIBED') res();
    else if (['CHANNEL_ERROR','TIMED_OUT','CLOSED'].includes(s)) rej(new Error(`${s} ${e||''}`));
  }));
  return ch;
}

(async () => {
  const evs = {
    contrib_ws2_filter: [], // contrib subscribed with workspace_id=WS_TWO filter → should get 0
    contrib_no_filter:  [], // contrib subscribed with no filter → RLS-only guarantees no W2 or non-PR1 leakage
    admin_ws2_filter:   [], // admin IS in W2 (admin) → should get W2 events
    none_ws1_filter:    [], // none subscribed with WS_ONE filter → still 0 (no PR1 participation)
  };
  const cContrib = await mk(USERS.contrib);
  const cAdmin   = await mk(USERS.admin);
  const cNone    = await mk(USERS.none);

  await subscribe(cContrib, evs.contrib_ws2_filter, 'contrib_ws2', `workspace_id=eq.${WS_TWO}`);
  await subscribe(cContrib, evs.contrib_no_filter,  'contrib_noflt', null);
  await subscribe(cAdmin,   evs.admin_ws2_filter,   'admin_ws2',   `workspace_id=eq.${WS_TWO}`);
  await subscribe(cNone,    evs.none_ws1_filter,    'none_ws1',    `workspace_id=eq.${WS_ONE}`);

  await new Promise(r => setTimeout(r, 2000));
  fs.writeFileSync('/tmp/lign_rt_crossws_ready', String(Date.now()));

  await new Promise(r => setTimeout(r, 60000));

  fs.writeFileSync(OUT, JSON.stringify(evs, null, 2));
  console.log('DUMPED', OUT);
  process.exit(0);
})().catch(e => { console.error('FATAL', e); process.exit(1); });
