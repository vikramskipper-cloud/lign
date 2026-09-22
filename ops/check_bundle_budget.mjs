#!/usr/bin/env node
// APP 012 wave 1 — fail the build when the bundle grows past its budget.
//
// The point is the RATCHET, not the number. Wave 2 splits the bundle; without a
// gate, the next ten features quietly put it all back. Lower `budget.json`
// after any real reduction so the win is locked in.
//
//   node ops/check_bundle_budget.mjs [dist-dir]
//
// Exit 0 within budget · 1 over · 2 usage/environment error.

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { gzipSync } from 'node:zlib'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const dist = process.argv[2] ?? join(root, 'app/dist')
const budgetFile = join(root, 'ops/bundle-budget.json')

if (!existsSync(dist)) {
  console.error(`error: ${dist} not found — run the build first`)
  process.exit(2)
}
const budget = JSON.parse(readFileSync(budgetFile, 'utf8'))

const assets = join(dist, 'assets')
const js = readdirSync(assets).filter((f) => f.endsWith('.js'))
if (js.length === 0) {
  console.error('error: no .js assets found')
  process.exit(2)
}

// "Initial" = everything the browser must fetch to render the first paint.
//
// This used to mean "every chunk except workers", which was right while the
// build emitted a single chunk and wrong the moment it did not: route-level
// lazy() chunks are fetched on navigation, and counting them as initial makes
// a successful split look like a regression.
//
// The authority is the built index.html. Vite puts the entry script there plus
// a <link rel="modulepreload"> for every chunk statically reachable from it —
// which is the definition of the critical path. Anything else is deferred.
const htmlFile = join(dist, 'index.html')
if (!existsSync(htmlFile)) {
  console.error(`error: ${htmlFile} not found — cannot tell initial chunks from lazy ones`)
  process.exit(2)
}
const html = readFileSync(htmlFile, 'utf8')
const referenced = new Set(
  [...html.matchAll(/(?:src|href)="[^"]*?\/assets\/([^"]+?\.js)"/g)].map((m) => m[1]),
)
if (referenced.size === 0) {
  console.error('error: index.html references no JS assets — unexpected build output')
  process.exit(2)
}

const isWorker = (f) => /worker/i.test(f)
const entries = js.map((f) => {
  const bytes = readFileSync(join(assets, f))
  return {
    file: f,
    raw: bytes.length,
    gzip: gzipSync(bytes).length,
    worker: isWorker(f),
    initial: referenced.has(f) && !isWorker(f),
  }
})

const initial = entries.filter((e) => e.initial)
const rawKb = initial.reduce((n, e) => n + e.raw, 0) / 1000
const gzipKb = initial.reduce((n, e) => n + e.gzip, 0) / 1000

const fmt = (n) => n.toFixed(2).padStart(9)
console.log('chunk                                          raw KB   gzip KB')
for (const e of entries.sort((a, b) => b.raw - a.raw)) {
  const tag = e.worker ? ' (worker)' : e.initial ? '' : ' (lazy)'
  console.log(`${(e.file + tag).padEnd(44)}${fmt(e.raw / 1000)}${fmt(e.gzip / 1000)}`)
}
console.log('-'.repeat(64))
console.log(`initial total${''.padEnd(31)}${fmt(rawKb)}${fmt(gzipKb)}`)
console.log(`budget       ${''.padEnd(31)}${fmt(budget.maxInitialRawKb)}${fmt(budget.maxInitialGzipKb)}`)
console.log(`chunks: ${initial.length} initial, ${entries.length - initial.length} deferred`)
const deferredGzip = entries.filter((e) => !e.initial).reduce((n, e) => n + e.gzip, 0) / 1000
console.log(`deferred (not counted, fetched on navigation): ${deferredGzip.toFixed(2)} KB gzip`)

const over = []
if (rawKb > budget.maxInitialRawKb) over.push(`raw ${rawKb.toFixed(2)} > ${budget.maxInitialRawKb} KB`)
if (gzipKb > budget.maxInitialGzipKb) over.push(`gzip ${gzipKb.toFixed(2)} > ${budget.maxInitialGzipKb} KB`)

if (over.length) {
  console.log(`\nRESULT: FAIL — ${over.join('; ')}`)
  console.log('Either reduce the bundle, or raise ops/bundle-budget.json deliberately and say why.')
  process.exit(1)
}
console.log('\nRESULT: PASS — within budget')
