// REALTIME 002 end-to-end verification.
//
// Runs everything except the revocation SQL (which is issued externally via
// MCP execute_sql between phases). Coordination is a file at /tmp/lign_rt_go.txt
// whose contents drive Node's phase advance.
//
// Design choices:
//   * Real Supabase JS realtime client (not custom WS).
//   * Real GoTrue sign-in with password (no service_role in this process).
//   * Writes via PostgREST using each user's own JWT so RLS INSERT policies
//     are exercised the same way the app will exercise them.
//   * Every subscriber receives ALL 8 tables under one workspace-scoped filter
//     to prove multiplexing works on a single client connection.
//   * Anon subscriber runs in parallel to prove no leakage without a JWT.

import fs from 'node:fs';
import ws from 'ws';
import { createClient } from '@supabase/supabase-js';
import { URL, ANON, USERS, WS_ONE, PROJ_ONE, ASSET1, V_DRAFT } from './harness.mjs';

const GO_FILE = '/tmp/lign_rt_go.txt';
const OUT_FILE = '/tmp/lign_rt_result.json';

const TABLES = [
  'comments','annotations','asset_versions','reviews','review_participants',
  'approval_requests','approval_responses','design_assets',
];

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

async function waitForGoFile(phase, timeoutMs=300000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      if (fs.readFileSync(GO_FILE, 'utf8').trim() === phase) return true;
    } catch {}
    await sleep(200);
  }
  return false;
}

async function makeAuthedClient(user) {
  const c = createClient(URL, ANON, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    realtime: { params: { eventsPerSecond: 30 }, transport: ws },
  });
  const { data, error } = await c.auth.signInWithPassword({ email: user.email, password: user.pw });
  if (error) throw new Error(`signIn ${user.email}: ${error.message}`);
  return { client: c, token: data.session.access_token };
}

function makeAnonClient() {
  const c = createClient(URL, ANON, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    realtime: { params: { eventsPerSecond: 30 }, transport: ws },
  });
  return { client: c, token: ANON };
}

// Subscribe one client to all 8 tables under a workspace filter.
// events are appended to `bag`.
async function subscribeAll(client, bag, tag, filterOnWorkspace=true) {
  const filter = filterOnWorkspace ? `workspace_id=eq.${WS_ONE}` : undefined;
  const channelName = `${tag}-rt-${Math.random().toString(36).slice(2,7)}`;
  const ch = client.channel(channelName);
  for (const table of TABLES) {
    ch.on('postgres_changes',
      { event: '*', schema: 'public', table, filter },
      (payload) => {
        bag.push({
          at: Date.now(),
          tag,
          table,
          event: payload.eventType,
          new_keys: payload.new ? Object.keys(payload.new) : null,
          new: payload.new,
          old: payload.old,
        });
      });
  }
  await new Promise((resolve, reject) => {
    ch.subscribe((status, err) => {
      if (status === 'SUBSCRIBED') resolve();
      else if (['CHANNEL_ERROR','TIMED_OUT','CLOSED'].includes(status))
        reject(new Error(`${tag}: ${status} ${err?err.message:''}`));
    });
  });
  return ch;
}

// Insert a comment via PostgREST as the given authed client.
async function insertComment(a, body, targetVersion=V_DRAFT) {
  const r = await fetch(`${URL}/rest/v1/comments`, {
    method: 'POST',
    headers: {
      apikey: ANON,
      Authorization: `Bearer ${a.token}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    body: JSON.stringify({
      workspace_id: WS_ONE,
      body,
      author_profile_id: (await a.client.auth.getUser()).data.user.id,
      target_version_id: targetVersion,
    }),
  });
  return { status: r.status, body: await r.text() };
}

async function insertAnnotation(a) {
  const r = await fetch(`${URL}/rest/v1/annotations`, {
    method: 'POST',
    headers: {
      apikey: ANON,
      Authorization: `Bearer ${a.token}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
    },
    body: JSON.stringify({
      workspace_id: WS_ONE,
      asset_version_id: V_DRAFT,
      version_file_id: null,
      author_profile_id: (await a.client.auth.getUser()).data.user.id,
      anchor_kind: 'pin',
      page_number: 1,
      position: { x: 0.5, y: 0.5 },
    }),
  });
  return { status: r.status, body: await r.text() };
}

async function main() {
  try { fs.unlinkSync(GO_FILE); } catch {}
  try { fs.unlinkSync(OUT_FILE); } catch {}

  const events = { contrib: [], stake: [], none: [], anon: [], admin: [] };
  const timeline = [];

  // Sign in 4 authenticated clients + 1 anon
  const lead    = await makeAuthedClient(USERS.lead);
  const contrib = await makeAuthedClient(USERS.contrib);
  const stake   = await makeAuthedClient(USERS.stake);
  const none    = await makeAuthedClient(USERS.none);
  const admin   = await makeAuthedClient(USERS.admin); // workspace admin, no project participation
  const anon    = makeAnonClient();
  timeline.push({ t: Date.now(), event: 'signed_in' });

  // Subscribe (project participants + admin + none + anon all listening).
  const chContrib = await subscribeAll(contrib.client, events.contrib, 'contrib');
  const chStake   = await subscribeAll(stake.client,   events.stake,   'stake');
  const chNone    = await subscribeAll(none.client,    events.none,    'none');
  const chAdmin   = await subscribeAll(admin.client,   events.admin,   'admin');
  const chAnon    = await subscribeAll(anon.client,    events.anon,    'anon').catch(e => ({ error: e.message }));
  timeline.push({ t: Date.now(), event: 'subscribed', anon_channel_error: chAnon?.error || null });

  // Give the realtime server ~500ms to be ready
  await sleep(500);

  // ==================== PHASE 1: baseline delivery ====================
  const t1 = await insertComment(lead, `[phase1-baseline] hello from lead ${Date.now()}`);
  timeline.push({ t: Date.now(), event: 'phase1_comment_inserted', status: t1.status });
  await sleep(1500);

  const a1 = await insertAnnotation(lead);
  timeline.push({ t: Date.now(), event: 'phase1_annotation_inserted', status: a1.status });
  await sleep(1500);

  // Signal ready for revocation
  fs.writeFileSync(GO_FILE, 'ready_for_revoke');
  timeline.push({ t: Date.now(), event: 'awaiting_external_revoke' });

  const ok = await waitForGoFile('revoked');
  timeline.push({ t: Date.now(), event: 'external_revoke_confirmed', ok });
  if (!ok) throw new Error('Timeout waiting for external revoke');

  // ==================== PHASE 2: post-revoke delivery ====================
  await sleep(500);
  const t2 = await insertComment(lead, `[phase2-post-revoke] should NOT reach contrib/stake ${Date.now()}`);
  timeline.push({ t: Date.now(), event: 'phase2_comment_inserted', status: t2.status });
  await sleep(2000);

  // ==================== PHASE 3: verify JWT-refresh doesn't matter ====================
  // Force contrib's realtime socket to re-authenticate with the SAME (unchanged) JWT.
  // Supabase Realtime v2 re-runs RLS on every message; a JWT refresh isn't the
  // primary control here. But if the socket happens to hold a stale-view somehow,
  // this call proves the state doesn't come back.
  try {
    // The client's realtime socket has a `setAuth` that pushes a fresh access
    // token to the server. We push the existing (still-valid) contrib token.
    contrib.client.realtime.setAuth(contrib.token);
    stake.client.realtime.setAuth(stake.token);
    timeline.push({ t: Date.now(), event: 'contrib_stake_realtime_setAuth_called' });
  } catch (e) {
    timeline.push({ t: Date.now(), event: 'setAuth_error', err: String(e) });
  }
  await sleep(500);
  const t3 = await insertComment(lead, `[phase3-after-setAuth] still should NOT reach contrib/stake ${Date.now()}`);
  timeline.push({ t: Date.now(), event: 'phase3_comment_inserted', status: t3.status });
  await sleep(2000);

  // Signal ready for restore
  fs.writeFileSync(GO_FILE, 'phase3_done');

  const okR = await waitForGoFile('restored');
  timeline.push({ t: Date.now(), event: 'external_restore_confirmed', ok: okR });
  if (!okR) throw new Error('Timeout waiting for external restore');

  // ==================== PHASE 4: restored delivery ====================
  await sleep(500);
  const t4 = await insertComment(lead, `[phase4-restored] should reach contrib/stake again ${Date.now()}`);
  timeline.push({ t: Date.now(), event: 'phase4_comment_inserted', status: t4.status });
  await sleep(2000);

  // ==================== PHASE 5: reconnect / missed-event test ====================
  // Kill contrib's channel entirely, insert while disconnected, resubscribe, verify
  // no automatic replay (client must refetch to catch up).
  const chContribBefore = events.contrib.length;
  await contrib.client.removeChannel(chContrib);
  timeline.push({ t: Date.now(), event: 'contrib_channel_removed', count_before: chContribBefore });
  await sleep(500);
  const t5 = await insertComment(lead, `[phase5-while-disconnected] contrib should miss this ${Date.now()}`);
  timeline.push({ t: Date.now(), event: 'phase5_comment_inserted_while_disconnected', status: t5.status });
  await sleep(1500);
  const chContribCountAfterDisconnected = events.contrib.length;
  const chContrib2 = await subscribeAll(contrib.client, events.contrib, 'contrib-reconn');
  timeline.push({ t: Date.now(), event: 'contrib_resubscribed' });
  await sleep(1000);
  const chContribCountAfterResub = events.contrib.length;
  const t6 = await insertComment(lead, `[phase6-after-reconnect] should reach contrib fresh ${Date.now()}`);
  timeline.push({ t: Date.now(), event: 'phase6_after_reconnect_inserted', status: t6.status });
  await sleep(1500);
  const finalContribCount = events.contrib.length;

  // Cleanup channels
  try { await contrib.client.removeAllChannels(); } catch {}
  try { await stake.client.removeAllChannels(); } catch {}
  try { await none.client.removeAllChannels(); } catch {}
  try { await admin.client.removeAllChannels(); } catch {}
  try { await anon.client.removeAllChannels(); } catch {}

  const result = {
    timeline,
    events,
    reconnect_probe: {
      contrib_before_disconnect: chContribBefore,
      contrib_after_disconnect_insert: chContribCountAfterDisconnected,
      contrib_after_resub_but_before_new_insert: chContribCountAfterResub,
      contrib_final: finalContribCount,
    },
  };
  fs.writeFileSync(OUT_FILE, JSON.stringify(result, null, 2));
  console.log('WROTE', OUT_FILE, 'events counts', Object.fromEntries(Object.entries(events).map(([k,v])=>[k,v.length])));
  process.exit(0);
}

main().catch(e => { console.error('FATAL', e); process.exit(1); });
