// Local-only: catalog retrieval must respect author/private drafts and approved snapshots.
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
const options = { auth: { persistSession: false, autoRefreshToken: false } },
  ok = (r) => {
    assert.equal(r.error, null, r.error?.message)
    return r.data
  },
  deny = (r, code = '42501') =>
    assert.equal(r.error?.code, code, r.error?.message ?? 'Unexpected success')
async function login(person) {
  const c = createClient(cfg.API_URL, cfg.ANON_KEY, options)
  ok(
    await c.auth.signInWithPassword({
      email: person.email,
      password: f.password,
    }),
  )
  return c
}
const author = await login(f.people.reserve),
  owner = await login(f.people.owner),
  member = await login(f.people.senior),
  external = await login(f.people.client),
  stamp = String(Date.now()),
  tag = 'catalog-' + stamp
const catalog = async (c, filters = {}) =>
    ok(
      await c.rpc('get_library_catalog', {
        p_organization_id: f.orgId,
        ...filters,
      }),
    ),
  current = async (c, id) =>
    ok(
      await c.rpc('get_organization_library', { p_organization_id: f.orgId }),
    ).collections.find((c) => c.id === id)
const transition = async (c, id, action) =>
  ok(
    await c.rpc('transition_library_collection', {
      p_collection_id: id,
      p_expected_version: (await current(c, id)).edit_version,
      p_action: action,
    }),
  )
const id = ok(
  await author.rpc('save_library_draft', {
    p_organization_id: f.orgId,
    p_title: 'Catalog ' + stamp,
    p_kind: 'template',
    p_description: 'Reusable starting point',
    p_tags: [tag, 'approved-' + stamp],
  }),
)
const png = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
  'base64',
)
async function upload(name) {
  const file = ok(
    await author.rpc('reserve_library_upload', {
      p_organization_id: f.orgId,
      p_name: name,
      p_mime: 'image/png',
      p_size: png.length,
    }),
  )
  ok(
    await author.storage
      .from('organization-library')
      .upload(file.path, png, { contentType: 'image/png' }),
  )
  ok(await author.rpc('finalize_library_upload', { p_file_id: file.id }))
  return file
}
const file = await upload('filename-' + stamp + '.png'),
  item = ok(
    await author.rpc('save_library_item', {
      p_collection_id: id,
      p_title: 'Palette',
      p_description: 'Specific material-' + stamp,
      p_url: 'https://example.com/source-' + stamp,
      p_file_id: file.id,
    }),
  )
assert.equal(
  (
    await catalog(author, {
      p_view: 'contributions',
      p_search: 'filename-' + stamp,
    })
  ).collections[0].matches[0].id,
  item,
)
assert.equal((await catalog(member, { p_search: stamp })).total, 0)
assert.equal(
  (await catalog(member, { p_view: 'contributions', p_search: stamp })).total,
  0,
)
deny(
  await member.rpc('get_library_catalog', {
    p_organization_id: f.orgId,
    p_view: 'review',
  }),
)
deny(await external.rpc('get_library_catalog', { p_organization_id: f.orgId }))
deny(
  await owner.rpc('get_library_catalog', {
    p_organization_id: f.orgId,
    p_view: 'unknown',
  }),
  '22023',
)
ok(
  await author.rpc('get_library_catalog', {
    p_organization_id: f.orgId,
    p_view: 'contributions',
  }),
)
await transition(author, id, 'submit')
assert.equal(
  (await catalog(owner, { p_view: 'review', p_search: stamp })).collections[0]
    .id,
  id,
)
await transition(owner, id, 'publish')
for (const needle of [
  'filename-' + stamp,
  'material-' + stamp,
  'source-' + stamp,
]) {
  const result = await catalog(member, { p_search: needle })
  assert.equal(result.total, 1)
  assert.equal(result.collections[0].matches[0].id, item)
  assert.equal(result.collections[0].cover.id, file.id)
}
assert.equal(
  (await catalog(member, { p_tag: tag, p_kind: 'template' })).total,
  1,
)
assert.equal(
  (await catalog(member, { p_tag: tag, p_kind: 'designs' })).total,
  0,
)
await transition(author, id, 'revise')
const replacement = await upload('secret-file-' + stamp + '.png')
ok(
  await author.rpc('save_library_draft', {
    p_organization_id: f.orgId,
    p_id: id,
    p_expected_version: (await current(author, id)).edit_version,
    p_title: 'Secret title ' + stamp,
    p_kind: 'designs',
    p_description: 'Secret description',
    p_tags: ['secret-' + stamp],
  }),
)
ok(
  await author.rpc('save_library_item', {
    p_collection_id: id,
    p_id: item,
    p_expected_version: 1,
    p_title: 'Secret item ' + stamp,
    p_description: 'Pending content',
    p_file_id: replacement.id,
  }),
)
for (const c of [member, owner, author]) {
  assert.equal(
    (await catalog(c, { p_search: 'secret-file-' + stamp })).total,
    0,
  )
  assert.equal(
    (await catalog(c, { p_search: 'secret title ' + stamp })).total,
    0,
  )
  assert(!(await catalog(c)).tags.includes('secret-' + stamp))
  assert.equal(
    (await catalog(c, { p_tag: tag })).collections[0].title,
    'Catalog ' + stamp,
  )
}
assert.equal(
  (
    await catalog(author, {
      p_view: 'contributions',
      p_search: 'secret-file-' + stamp,
    })
  ).collections[0].cover.id,
  replacement.id,
)
assert.equal(
  (
    await catalog(member, {
      p_view: 'contributions',
      p_search: 'secret-file-' + stamp,
    })
  ).total,
  0,
)
// A complete page plus one result verifies stable retrieval beyond the first screen.
const pagination = 'page-' + stamp
for (let i = 0; i < 25; i++)
  ok(
    await author.rpc('save_library_draft', {
      p_organization_id: f.orgId,
      p_title: `Paged ${stamp} ${String(i).padStart(2, '0')}`,
      p_kind: 'references',
      p_tags: [pagination],
    }),
  )
const first = await catalog(author, {
    p_view: 'contributions',
    p_tag: pagination,
  }),
  last = await catalog(author, {
    p_view: 'contributions',
    p_tag: pagination,
    p_offset: 24,
  })
assert.equal(first.total, 25)
assert.equal(first.collections.length, 24)
assert.equal(last.collections.length, 1)
assert(!first.collections.some((c) => c.id === last.collections[0].id))
deny(
  await owner.rpc('get_library_catalog', {
    p_organization_id: f.orgId,
    p_offset: -1,
  }),
  '22023',
)
console.log(
  'PASS catalog filename/details/URL search, types/tags/covers, review queue, pagination, external denial, author-only drafts and approved-only search during revision',
)
