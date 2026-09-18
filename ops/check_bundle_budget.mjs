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
// Web workers are excluded: they are fetched on demand, not on the critical path.
const isWorker = (f) => /worker/i.test(f)
const entries = js.map((f) => {
  const bytes = readFileSync(join(assets, f))
  return { file: f, raw: bytes.length, gzip: gzipSync(bytes).length, worker: isWorker(f) }
})

const initial = entries.filter((e) => !e.worker)
const rawKb = initial.reduce((n, e) => n + e.raw, 0) / 1000
const gzipKb = initial.reduce((n, e) => n + e.gzip, 0) / 1000

const fmt = (n) => n.toFixed(2).padStart(9)
console.log('chunk                                          raw KB   gzip KB')
for (const e of entries.sort((a, b) => b.raw - a.raw)) {
  console.log(`${(e.file + (e.worker ? ' (worker, excluded)' : '')).padEnd(44)}${fmt(e.raw / 1000)}${fmt(e.gzip / 1000)}`)
}
console.log('-'.repeat(64))
console.log(`initial total${''.padEnd(31)}${fmt(rawKb)}${fmt(gzipKb)}`)
console.log(`budget       ${''.padEnd(31)}${fmt(budget.maxInitialRawKb)}${fmt(budget.maxInitialGzipKb)}`)
console.log(`chunks: ${initial.length} initial, ${entries.length - initial.length} deferred`)

const over = []
if (rawKb > budget.maxInitialRawKb) over.push(`raw ${rawKb.toFixed(2)} > ${budget.maxInitialRawKb} KB`)
if (gzipKb > budget.maxInitialGzipKb) over.push(`gzip ${gzipKb.toFixed(2)} > ${budget.maxInitialGzipKb} KB`)

if (over.length) {
  console.log(`\nRESULT: FAIL — ${over.join('; ')}`)
  console.log('Either reduce the bundle, or raise ops/bundle-budget.json deliberately and say why.')
  process.exit(1)
}
console.log('\nRESULT: PASS — within budget')
