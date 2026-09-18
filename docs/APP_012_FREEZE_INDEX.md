# APP 012 — Freeze Index

**Canonical architecture reference for Lign Production Hardening.**

Implementation has not started. Unlike APP 001–011, this slice ships **no product surface**: no new screen, table, RPC, capability or event. Every item below is measured against the live system on **2026-09-18**, not inferred — production hardening is a domain where a plan built on assumption is worse than no plan.

**Foundational premise:**

> **APP 012 changes how the system is built, deployed, watched and rebuilt. It does not change what the system does.**
>
> If a change here alters behaviour visible to a user, it is out of scope or it is a bug. The one exception is *latency* — pages may get faster, never different.

**Companion inputs:** `docs/PLATFORM_CHEATSHEET.md` (rules 10, 19, 20), `supabase/migrations/RECONCILIATION.md`, `docs/freeze/MIGRATION_ARTIFACT_AMENDMENT.md`, `docs/APP_011_IMPLEMENTATION_REPORT.md`, `ops/`.

---

## 1. Measured baseline

| Dimension | Measured state (2026-09-18) |
|---|---|
| Bundle | **1,012.18 kB raw / 277.85 kB gzip in ONE chunk**; 39 routes, **zero** `lazy()`/dynamic imports |
| App source | 1,208 KB of TS/TSX — roughly half the bundle is app code, half vendor |
| Icons | `lucide-react` imported as named exports across 73 sites — tree-shaken, **not** the problem |
| CI | **None.** No `.github/`, no pipeline, no automated gate on any commit |
| Tests | 30 unit tests + 3 probe scripts (all added by APP 011); nothing runs them automatically |
| Deployment | **None.** No hosting config, no build artefact target, no environment promotion |
| Environments | **One.** Test fixtures and 7 test users live in production |
| Unindexed FKs | **24** (`INFO`) — a standing violation of cheatsheet rule 10 |
| Unused indexes | 74 (`INFO`) — expected at zero traffic; not actionable yet |
| Security advisors | 0 ERROR; 2 WARN (`SECURITY DEFINER` executable by signed-in users — by design; **leaked password protection disabled** — a real one-click fix) |
| Scheduling | `pg_cron` and `pg_net` **not installed**. The storage purge worker is manual-invoke only, and **1 file already sits orphaned** awaiting a purge that nothing will trigger |
| Observability | None. No error reporting, no performance instrumentation, no uptime check |
| DB size | 19 MB — scale is not a current problem, and APP 012 should not pretend otherwise |

---

## 2. What APP 012 owns

Five waves, ordered so each makes the next safer.

### Wave 1 — CI and automated gates  **[highest leverage]**

The project has real verification (`ops/verify_migrations.sh`, `ops/audit_schema_provenance.py`, `ops/replay_check.sh`, 30 tests, 3 probes) and **nothing runs any of it**. Every check in this repo is currently a thing a human remembers to do.

- GitHub Actions on push/PR: typecheck, build, `vitest run`.
- Migration drift gate: `verify_migrations.sh` against the live manifest.
- Schema provenance gate: `audit_schema_provenance.py`.
- Bundle-size budget that **fails** the build above a threshold, so wave 2's win cannot silently erode.

Wave 1 ships no user-visible change and protects everything after it. It goes first.

### Wave 2 — Bundle and loading

One 1,012 kB chunk means every user downloads the requirements module to look at a design asset.

- Route-level `lazy()` across the 39 routes, with `AsyncBoundary` already in place as the fallback (APP 002 provides it — no new primitive needed).
- Manual vendor chunking: react/react-dom, react-router, react-query, supabase-js.
- Defer `hash-wasm` — it is only needed once an upload starts, not on first paint.
- **Target: initial chunk under 450 kB raw.** To be confirmed by measurement, not asserted.

### Wave 3 — Database hardening

- **24 unindexed foreign keys.** Cheatsheet rule 10 says every FK gets a covering index in the same migration; APP 003, 008, 009 and 010 left these behind. Concentrated in `requirements` (7), `version_requirement_assessments` (5), `releases` (3), `requirement_design_assets` (3).
- Leave the 74 unused indexes **alone**. At 19 MB and near-zero traffic, "unused" means "no one has run the query yet", not "wrong". Dropping them would be optimising against absent evidence.
- Auth connection strategy: percentage-based rather than absolute 10.

### Wave 4 — Operations and lifecycle

- Install `pg_cron` (and `pg_net` only if a scheduled job genuinely needs outbound HTTP) and schedule the storage purge, invitation expiry, and approval expiry jobs the earlier layers deferred.
- Ops runbook: how to deploy, roll back, restore, rotate keys, run the verification suite.
- Enable leaked-password protection.

### Wave 5 — Environment separation  **[largest; may be deferred]**

Today there is one project, containing fixtures and test users. A staging environment is what makes the rebuild guarantee real rather than theoretical — and `platform_001_role_grants` means the migration set can now actually produce a working database, which is the precondition that was missing until today.

---

## 3. What APP 012 does NOT own

- **No UI/UX polish.** That is the phase after this one, by the architect's sequencing.
- **No new feature, table, RPC, capability, event or screen.**
- **No behavioural change.** Latency only.
- **No index removal** on the strength of "unused" at zero traffic (§2 wave 3).
- **No tightening of `anon` privileges.** Production grants `anon` full DML and TRUNCATE on all 32 tables, and TRUNCATE is not subject to RLS. That is a real security decision recorded in `platform_001_role_grants` — but it is a *product security* decision for the architect, not a hardening chore, and changing it silently under this slice would be wrong.

---

## 4. Open decisions

| # | Decision | Recommendation |
|---|---|---|
| **H-1** | Where does the app deploy? Nothing exists today. | Decide before wave 1 — CI has nowhere to publish otherwise. Any static host works; the app is a pure SPA against Supabase. |
| **H-2** | Is wave 5 (staging) in scope, or deferred? | **Deferred.** It is the largest item and depends on H-1. Waves 1–4 deliver most of the value without it. |
| **H-3** | Bundle budget threshold. | Set at the post-wave-2 measurement plus ~10 %, so it ratchets rather than aspires. |
| **H-4** | Do the 24 FK indexes go in one migration or per-slice? | **One migration.** They are a single class of debt; splitting it across four slice re-freezes buys nothing. |
| **H-5** | `create_review` overload (APP 011 report §5) — drop the 9-arg form? | Drop it. It is a latent `PGRST203` trap and APP 009 already set the precedent under F-2. Needs an APP 006 re-freeze note. |
| **H-6** | Remove test fixtures and test users from production? | Tied to H-2. Until staging exists they are the only way to exercise anything, so removing them first would make things worse. |

---

## 5. Success criteria

- [ ] CI runs typecheck, tests, build, migration drift and schema provenance on every push
- [ ] Bundle budget enforced in CI and failing above threshold
- [ ] Initial chunk measurably smaller, with the number reported
- [ ] 0 unindexed foreign keys
- [ ] Scheduled jobs running; no file orphaned indefinitely
- [ ] Runbook exists and has been followed once end to end
- [ ] Advisors: no new issue class
- [ ] **No behavioural change** — the 30 tests and 3 probes still pass unmodified

---

## 6. Non-goals (permanent)

Micro-optimisation without measurement, index removal without traffic data, premature caching layers, multi-region, horizontal scaling. The database is 19 MB and has never served a real user; APP 012 hardens the path to production, it does not pre-optimise for a scale that does not exist.
