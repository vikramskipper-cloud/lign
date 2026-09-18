// Passive listener: subscribe with all needed identities, dump everything received.
// Writes happen via MCP execute_sql from outside. When SIGTERM arrives, dump JSON.

import fs from 'node:fs';
import ws from 'ws';
import { createClient } from '@supabase/supabase-js';
import { URL, ANON, USERS, WS_ONE } from './harness.mjs';

const OUT = '/tmp/lign_rt_lifecycle.json';
const TABLES = [
  'comments','annotations','asset_versions','reviews','review_participants',
  'approval_requests','approval_responses','design_assets',
];

async function mk(user) {
  const c = createClient(URL, ANON, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    realtime: { params: { eventsPerSecond: 60 }, transport: ws },
  });
  if (user) {
    const { error } = await c.auth.signInWithPassword({ email: user.email, password: user.pw });
    if (error) throw new Error(`signIn ${user.email}: ${error.message}`);
  }
  return c;
}

async function subscribeAll(client, bag, tag) {
  const ch = client.channel(`${tag}-${Math.random().toString(36).slice(2,6)}`);
  for (const t of TABLES) {
    ch.on('postgres_changes',
      { event: '*', schema: 'public', table: t, filter: `workspace_id=eq.${WS_ONE}` },
      (p) => bag.push({ at: Date.now(), tag, table: t, ev: p.eventType, new: p.new, old: p.old }));
  }
  await new Promise((resolve, reject) => {
    ch.subscribe((s, e) => {
      if (s === 'SUBSCRIBED') resolve();
      else if (['CHANNEL_ERROR','TIMED_OUT','CLOSED'].includes(s)) reject(new Error(`${s} ${e||''}`));
    });
  });
  return ch;
}

const events = { contrib: [], lead: [], reviewer: [], observer: [], none: [], stake: [], admin: [], anon: [] };
const started_at = Date.now();

(async () => {
  const clients = {};
  for (const [k, u] of Object.entries(USERS)) {
    clients[k] = await mk(u);
    await subscribeAll(clients[k], events[k] || (events[k]=[]), k);
  }
  clients.anon = await mk(null);
  await subscribeAll(clients.anon, events.anon, 'anon');

  console.log('SUBSCRIBED_ALL', new Date().toISOString());
  // Give server 2s to fully register subs, then signal ready. Then wait
  // 25s for external MCP-driven writes to arrive, then dump + exit.
  await new Promise(r => setTimeout(r, 2000));
  fs.writeFileSync('/tmp/lign_rt_lifecycle_ready', String(Date.now()));
  console.log('READY', new Date().toISOString());
  await new Promise(r => setTimeout(r, 90000));
  fs.writeFileSync(OUT, JSON.stringify({ started_at, events }, null, 2));
  console.log('DUMPED', OUT);
  process.exit(0);
})().catch(e => { console.error('FATAL', e); process.exit(1); });
