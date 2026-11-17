// Local-only: prepare privately -> share -> client input -> selected public direction.
import assert from 'node:assert/strict'
import { readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
const require = createRequire(
    new URL('../../app/package.json', import.meta.url),
  ),
  { createClient } = require('@supabase/supabase-js')
const cfg = JSON.parse(
    readFileSync(new URL('../../ops/.tmp/access-local.json', import.meta.url)),
  ),
  f = JSON.parse(
    readFileSync(
      new URL('../../ops/.tmp/planning-fixture.json', import.meta.url),
    ),
  ),
  v = JSON.parse(
    readFileSync(
      new URL('../../ops/.tmp/version-sharing-fixture.json', import.meta.url),
    ),
  )
const host = new URL(cfg.API_URL)
assert(
  ['localhost', '127.0.0.1'].includes(host.hostname) && host.port === '58321',
)
const opts = { auth: { persistSession: false, autoRefreshToken: false } },
  service = createClient(cfg.API_URL, cfg.SERVICE_ROLE_KEY, opts),
  ok = (r) => {
    assert.equal(r.error, null, r.error?.message)
    return r.data
  },
  deny = (r, code = '42501') =>
    assert.equal(r.error?.code, code, r.error?.message ?? 'Unexpected success')
async function login(person) {
  const c = createClient(cfg.API_URL, cfg.ANON_KEY, opts)
  ok(
    await c.auth.signInWithPassword({
      email: person.email,
      password: f.password,
    }),
  )
  return c
}
const owner = await login(f.people.owner),
  lead = await login(f.people.senior),
  client = await login(v.people.client),
  viewer = await login(v.people.viewer),
  outsider = await login(f.people.outsider),
  stamp = Date.now()
const member = ok(
  await service
    .from('workspace_members')
    .select('id')
    .eq('workspace_id', f.wsA)
    .eq('user_id', f.people.senior.userId)
    .single(),
).id
const p = ok(
  await owner.rpc('create_project_with_client', {
    p_workspace_id: f.wsA,
    p_name: 'Reference sharing ' + stamp,
    p_lead_member_id: member,
    p_client_emails: [],
  }),
)[0].out_project_id
for (const [person, role] of [
  [v.people.client, 'approver'],
  [v.people.viewer, 'observer'],
])
  ok(
    await owner.rpc('add_project_participant', {
      p_project_id: p,
      p_workspace_member_id: null,
      p_stakeholder_id: person.sh,
      p_role: role,
    }),
  )
const boards = async (c = owner) =>
    ok(await c.rpc('get_reference_boards', { p_project_id: p })),
  boardState = async (id) => (await boards()).boards.find((b) => b.id === id),
  cards = async (c, id) =>
    ok(await c.rpc('get_reference_board', { p_board_id: id })).cards
const board = ok(
    await owner.rpc('save_reference_board', {
      p_project_id: p,
      p_title: 'Private palette ' + stamp,
      p_kind: 'moodboard',
    }),
  ),
  card = ok(
    await owner.rpc('save_reference_card', {
      p_board_id: board,
      p_title: 'Private finish ' + stamp,
      p_description: 'Private material notes',
      p_url: 'https://example.com/private',
    }),
  )
assert.equal((await boardState(board)).shared_at, null)
assert((await boards(lead)).boards.some((b) => b.id === board))
assert.equal((await boards(client)).boards.length, 0)
ok(
  await lead.rpc('set_reference_preference', {
    p_card_id: card,
    p_choice: 'liked',
    p_note: 'PRIVATE PREFERENCE ' + stamp,
  }),
)
ok(
  await lead.rpc('add_reference_comment', {
    p_card_id: card,
    p_body: 'PRIVATE DISCUSSION ' + stamp,
  }),
)
for (const actor of [client, viewer, outsider]) {
  deny(await actor.rpc('get_reference_board', { p_board_id: board }))
  deny(await actor.rpc('get_reference_comments', { p_card_id: card }))
  deny(
    await actor.rpc('save_reference_card', {
      p_board_id: board,
      p_title: 'Forbidden',
    }),
  )
  deny(
    await actor.rpc('set_reference_preference', {
      p_card_id: card,
      p_choice: 'liked',
    }),
  )
  deny(
    await actor.rpc('add_reference_comment', {
      p_card_id: card,
      p_body: 'Forbidden',
    }),
  )
}
for (const table of [
  'reference_boards',
  'reference_cards',
  'reference_preferences',
  'reference_comments',
])
  assert.equal(
    ok(
      await client
        .from(table)
        .select('*')
        .eq(
          table === 'reference_boards'
            ? 'id'
            : table === 'reference_cards'
              ? 'board_id'
              : 'card_id',
          table === 'reference_boards' || table === 'reference_cards'
            ? board
            : card,
        ),
    ).length,
    0,
  )
const events = ok(
  await client.from('activity_events').select('payload').eq('project_id', p),
)
assert(!JSON.stringify(events).includes('PRIVATE PREFERENCE'))
deny(
  await owner.rpc('set_reference_selection', {
    p_card_id: card,
    p_selected: true,
    p_expected_version: (await cards(owner, board))[0].editVersion,
  }),
  '23514',
)
const png = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
  'base64',
)
const file = ok(
  await owner.rpc('reserve_planning_upload', {
    p_name: 'Private swatch.png',
    p_mime: 'image/png',
    p_size: png.length,
    p_reference_id: card,
    p_expected_version: (await cards(owner, board))[0].editVersion,
  }),
)
ok(
  await owner.storage
    .from('project-planning')
    .upload(file.path, png, { contentType: 'image/png' }),
)
ok(await owner.rpc('finalize_planning_upload', { p_file_id: file.id }))
assert(
  (await client.storage.from('project-planning').download(file.path)).error,
)
assert.equal(
  ok(await client.from('planning_files').select('*').eq('id', file.id)).length,
  0,
)
// Approved Library content imported into a private board must not publish its file to the client yet.
const collection = ok(
    await owner.rpc('save_library_draft', {
      p_organization_id: f.orgId,
      p_title: 'Reference import ' + stamp,
      p_kind: 'materials_products',
    }),
  ),
  libraryFile = ok(
    await owner.rpc('reserve_library_upload', {
      p_organization_id: f.orgId,
      p_name: 'Unshared library.png',
      p_mime: 'image/png',
      p_size: png.length,
    }),
  )
ok(
  await owner.storage
    .from('organization-library')
    .upload(libraryFile.path, png, { contentType: 'image/png' }),
)
ok(await owner.rpc('finalize_library_upload', { p_file_id: libraryFile.id }))
ok(
  await owner.rpc('save_library_item', {
    p_collection_id: collection,
    p_title: 'Material library item',
    p_file_id: libraryFile.id,
  }),
)
const coll = () =>
  owner
    .rpc('get_organization_library', { p_organization_id: f.orgId })
    .then(ok)
    .then((d) => d.collections.find((c) => c.id === collection))
for (const action of ['submit', 'publish'])
  ok(
    await owner.rpc('transition_library_collection', {
      p_collection_id: collection,
      p_expected_version: (await coll()).edit_version,
      p_action: action,
    }),
  )
const imported = ok(
  await owner.rpc('import_library_collection', {
    p_collection_id: collection,
    p_project_id: p,
    p_title: 'Private library import',
  }),
)
assert.equal((await boardState(imported)).shared_at, null)
assert(
  (await client.storage.from('organization-library').download(libraryFile.path))
    .error,
)
assert.equal(
  ok(
    await service
      .from('library_publications')
      .select('*')
      .eq('file_id', libraryFile.id)
      .eq('project_id', p),
  ).length,
  0,
)
for (const actor of [client, viewer])
  deny(
    await actor.rpc('share_reference_board', {
      p_board_id: board,
      p_expected_version: 1,
    }),
  )
const concurrent = await Promise.all([
  owner.rpc('share_reference_board', {
    p_board_id: board,
    p_expected_version: 1,
  }),
  lead.rpc('share_reference_board', {
    p_board_id: board,
    p_expected_version: 1,
  }),
])
assert.equal(concurrent.filter((r) => !r.error).length, 1)
assert.equal(concurrent.find((r) => r.error).error.code, 'PT409')
assert.equal((await cards(client, board))[0].preferences.length, 0)
assert.equal(
  ok(await client.rpc('get_reference_comments', { p_card_id: card })).rows
    .length,
  0,
)
assert.equal((await cards(owner, board))[0].preferences.length, 1)
assert.equal(
  ok(await owner.rpc('get_reference_comments', { p_card_id: card })).rows
    .length,
  1,
)
assert((await client.storage.from('project-planning').download(file.path)).data)
ok(
  await client.rpc('set_reference_preference', {
    p_card_id: card,
    p_choice: 'shortlisted',
    p_note: 'I like the finish',
  }),
)
ok(
  await client.rpc('add_reference_comment', {
    p_card_id: card,
    p_body: 'Use this finish, but not the layout.',
  }),
)
const suggestion = ok(
  await client.rpc('save_reference_card', {
    p_board_id: board,
    p_title: 'Client example',
    p_url: 'https://example.com/client',
  }),
)
assert((await cards(owner, board)).some((c) => c.id === suggestion))
deny(
  await viewer.rpc('save_reference_card', {
    p_board_id: board,
    p_title: 'Read-only',
  }),
)
const state = (await cards(owner, board)).find((c) => c.id === card)
ok(
  await lead.rpc('set_reference_selection', {
    p_card_id: card,
    p_selected: true,
    p_expected_version: state.editVersion,
  }),
)
const direction = ok(
  await client.rpc('get_reference_direction', { p_project_id: p }),
)
assert.equal(direction.length, 1)
assert.equal(direction[0].preferences.length, 1)
assert(!JSON.stringify(direction).includes('PRIVATE'))
const snapshot = ok(
  await service.rpc('snapshot_brief_reference_selection', { p_project_id: p }),
)
assert(!JSON.stringify(snapshot).includes('PRIVATE'))
assert.equal(snapshot[0].preferences.length, 1)
// Client input board creation is bounded, shared and idempotent even before any team board is shared.
const input = await Promise.all([
  client.rpc('get_or_create_client_reference_board', { p_project_id: p }),
  owner.rpc('get_or_create_client_reference_board', { p_project_id: p }),
])
assert.equal(ok(input[0]), ok(input[1]))
assert.equal((await boardState(ok(input[0]))).is_client_input, true)
assert((await boardState(ok(input[0]))).shared_at)
deny(
  await viewer.rpc('get_or_create_client_reference_board', { p_project_id: p }),
)
ok(
  await owner.rpc('share_reference_board', {
    p_board_id: imported,
    p_expected_version: (await boardState(imported)).edit_version,
  }),
)
assert(
  (await client.storage.from('organization-library').download(libraryFile.path))
    .data,
)
ok(
  await lead.rpc('add_reference_comment', {
    p_card_id: card,
    p_body: 'LATE PRIVATE DISCUSSION ' + stamp,
    p_internal: true,
  }),
)
ok(
  await lead.rpc('set_reference_preference', {
    p_card_id: card,
    p_choice: 'liked',
    p_note: 'LATE PRIVATE PREFERENCE ' + stamp,
    p_internal: true,
  }),
)
deny(
  await client.rpc('add_reference_comment', {
    p_card_id: card,
    p_body: 'Private client bypass',
    p_internal: true,
  }),
)
deny(
  await client.rpc('set_reference_preference', {
    p_card_id: card,
    p_choice: 'liked',
    p_internal: true,
  }),
)
// Internal preparation notes remain hidden in direct tables and activity after sharing as well.
assert.equal(
  ok(await client.from('reference_comments').select('*').eq('card_id', card))
    .length,
  1,
)
assert.equal(
  ok(await client.from('reference_preferences').select('*').eq('card_id', card))
    .length,
  1,
)
assert(
  !JSON.stringify(
    ok(
      await client
        .from('activity_events')
        .select('payload')
        .eq('project_id', p),
    ),
  ).includes('PRIVATE'),
)
writeFileSync(
  new URL('../../ops/.tmp/reference-sharing-fixture.json', import.meta.url),
  JSON.stringify({
    project: p,
    workspace: f.wsA,
    board,
    card,
    imported,
    input: ok(input[0]),
    file,
    libraryFile,
    client: v.people.client,
    viewer: v.people.viewer,
  }),
  { mode: 0o600 },
)
console.log(
  'PASS private board/RPC/raw-table/file denial, internal feedback retention, activity redaction, shared client collaboration, concurrent sharing/client input, approved-only Library publication, selected public direction and immutable brief snapshot privacy',
)
