// Local-only: canonical categories with immutable, backwards-compatible publications.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
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
  }
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
  author = await login(f.people.reserve),
  member = await login(f.people.senior),
  external = await login(f.people.client),
  stamp = Date.now()
const org = ok(
  await service
    .from('organizations')
    .insert({
      name: 'Category verification ' + stamp,
      slug: 'category-check-' + stamp,
    })
    .select('id')
    .single(),
).id
for (const [person, role] of [
  [f.people.owner, 'owner'],
  [f.people.reserve, 'member'],
  [f.people.senior, 'member'],
])
  ok(
    await service
      .from('organization_members')
      .insert({
        organization_id: org,
        user_id: person.userId,
        role,
        status: 'active',
      }),
  )
const list = async (c) =>
  ok(await c.rpc('get_organization_library', { p_organization_id: org }))
    .collections
const current = async (id) => (await list(owner)).find((c) => c.id === id)
const transition = async (c, id, action) =>
  ok(
    await c.rpc('transition_library_collection', {
      p_collection_id: id,
      p_expected_version: (await current(id)).edit_version,
      p_action: action,
    }),
  )
const catalog = async (c, kind = 'all', view = 'published') =>
  ok(
    await c.rpc('get_library_catalog', {
      p_organization_id: org,
      p_kind: kind,
      p_view: view,
    }),
  )
const mapping = {
    template: 'templates_guides',
    references: 'inspiration',
    moodboard: 'inspiration',
    designs: 'details_solutions',
    inspiration: 'inspiration',
    materials_products: 'materials_products',
    details_solutions: 'details_solutions',
    templates_guides: 'templates_guides',
  },
  ids = {}
for (const [old, category] of Object.entries(mapping)) {
  const id = ok(
    await author.rpc('save_library_draft', {
      p_organization_id: org,
      p_title: old + ' ' + stamp,
      p_kind: old,
      p_tags: ['example'],
    }),
  )
  ids[old] = id
  ok(
    await author.rpc('save_library_item', {
      p_collection_id: id,
      p_title: 'Example item',
      p_description: 'Saved reusable resource',
      p_url: 'https://example.com/resource',
    }),
  )
  assert.equal((await catalog(member)).total, Object.keys(ids).length - 1)
  await transition(author, id, 'submit')
  await transition(owner, id, 'publish')
  assert(
    (await catalog(member, category)).collections.some(
      (c) => c.id === id && c.category === category,
    ),
  )
}
const before = ok(
  await service
    .from('library_revisions')
    .select('id,snapshot')
    .in('collection_id', Object.values(ids)),
).sort((a, b) => a.id.localeCompare(b.id))
for (const [old, category] of Object.entries(mapping))
  assert.deepEqual(
    (await catalog(member, old)).collections.map((c) => c.id),
    (await catalog(member, category)).collections.map((c) => c.id),
  )
const id = ids.moodboard,
  oldRevision = (await current(id)).published_revision_id
await transition(author, id, 'revise')
ok(
  await author.rpc('save_library_draft', {
    p_organization_id: org,
    p_id: id,
    p_expected_version: (await current(id)).edit_version,
    p_title: 'Material specification',
    p_kind: 'materials_products',
    p_tags: ['pending-material'],
  }),
)
assert(
  !(await catalog(member, 'materials_products')).collections.some(
    (c) => c.id === id,
  ),
)
assert(
  (await catalog(member, 'inspiration')).collections.some((c) => c.id === id),
)
assert(
  (
    await catalog(author, 'materials_products', 'contributions')
  ).collections.some((c) => c.id === id),
)
assert.equal((await current(id)).published_revision_id, oldRevision)
const after = ok(
  await service
    .from('library_revisions')
    .select('id,snapshot')
    .in('collection_id', Object.values(ids)),
).sort((a, b) => a.id.localeCompare(b.id))
assert.deepEqual(after, before)
assert.equal(
  (await external.rpc('get_library_catalog', { p_organization_id: org })).error
    ?.code,
  '42501',
)
assert.equal(
  (
    await member.rpc('get_library_catalog', {
      p_organization_id: org,
      p_view: 'review',
    })
  ).error?.code,
  '42501',
)
assert.equal(
  (
    await owner.rpc('save_library_draft', {
      p_organization_id: org,
      p_title: 'Invalid',
      p_kind: 'anything',
    })
  ).error?.code,
  '23514',
)
console.log(
  'PASS all four new categories save/publish/search; legacy categories map consistently; snapshots and pending-revision privacy preserved; invalid categories and external access denied',
)
