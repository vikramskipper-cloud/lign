# APP 010 Backend Proposal (Re-freeze Applied)

## APP 010 Backend Re-freeze Report

### 1. Verdict

**APP 010 Backend is frozen.** All accepted findings from the Backend Re-freeze Review have been applied: one CRITICAL, two HIGH, two MEDIUM, and two LOW corrections. Zero new backend surface has been introduced beyond the accepted corrections (the corrections are contract clarifications, a documentation subsection, and one explicit-guard step inside an already-planned function body — no new table, column, index, capability, event, RPC, or trigger). APP 001–009 compatibility is preserved exactly.

### 2. Corrections applied

| Finding ID | Severity | Location(s) updated | Rationale | Exact contract change | Compatibility impact | Applied |
|---|---|---|---|---|---|---|
| F-1 | CRITICAL | §10.1 `notifications_select` predicate; new subsection §2.12 (Helper function references — verified against frozen baseline) | The previously referenced helper `lign_is_project_participant(project_id)` does not exist in the frozen baseline. Replaced with the verified `public.lign_project_role(project_id) IS NOT NULL` idiom, fully qualified because the SELECT policy runs under `SET search_path = ''` in the surrounding RPC/policy context. A new subsection enumerates every helper function referenced anywhere in the proposal with the frozen migration file and line range where declared, and states explicitly that every helper exists in the frozen baseline. | RLS `notifications_select` third predicate now reads `(project_id IS NULL OR public.lign_project_role(project_id) IS NOT NULL OR public.lign_is_workspace_admin(workspace_id))`. Helper references subsection added at end of §2. | None — the correction resolves an unresolved reference; the RLS predicate now names only helpers that exist in the frozen baseline. | Yes |
| F-2 | HIGH | §9.1 body outline (step 1a); §9.1 "Behavior on `notification.*` events" bullet; §17.1 | The previous loop-guard argument relied entirely on the routing table's absence of `notification.*` entries. A single-line explicit guard is the primary defense; routing-table absence becomes the secondary defense. | Body outline gains a step 1a `IF NEW.event_type LIKE 'notification.%' THEN RETURN NEW; END IF;` immediately after the `NEW.event_type IS NULL` guard and before the routing-table lookup. Documented as the primary loop-guard; routing-table absence documented as the secondary defense. §17.1 references the explicit guard. | None — additive documentation of an in-body guard; no new tables, columns, RPCs, or triggers. | Yes |
| F-3 | HIGH | §2 (Backend conventions house rules); §8 (RPC surface preamble); §11.3 (capability wiring); §20.1 and §20.3 (backwards-compat guarantees); §24 (final backend delta summary) | The proposal previously asserted "APP 010 introduces zero extensions to frozen RPCs" or "zero `CREATE OR REPLACE` on any frozen function," which was inconsistent with §11.3's `lign_has_capability` reissue. The canonical statement now names the exact reissue and its additive posture. | Every referenced section now carries the canonical statement: "APP 010 performs exactly one `CREATE OR REPLACE` of the frozen `lign_has_capability(uuid, uuid, text)` function. This replacement is strictly additive: the signature is preserved; every existing capability key and role mapping remains byte-identical; only the new `notification.*` capability keys (2 wired + 6 reserved) are appended. No existing capability changes. No overload is introduced. No named-argument ambiguity arises. Per checklist C-2, byte-identical role-map preservation is guaranteed." | None — the semantics are unchanged; the change is contract wording so that every occurrence tells the same story. | Yes |
| F-4 | MEDIUM | §7.6 (I-7 justification); §17.3 (backend gap discussion) | The previous "allows re-materialization if the row is later archived and the same source event fires again" text implied an impossible v1 scenario. Framing A is chosen: the `WHERE archived_at IS NULL` predicate is defensive scaffolding for Wave 4 replay workers; it is unreachable in v1 traffic. | §7.6 and §17.3 rewritten to state the predicate is defensive scaffolding for Wave 4 replay workers and unreachable in v1. Locks the dedup contract shape before Wave 4 delivery workers ship. | None — index definition is unchanged; only the justifying narrative changed. | Yes |
| F-5 | MEDIUM | §5.16 (payload keys); §15.1 (`list_notifications_inbox` return); §15.3 (`get_notification` return) | Two conflicting canonical positions for `actor_display_name` existed: nested in `payload` and denormalized at the top level. Standardized on the nested-in-`payload` canonical position everywhere. | §5.16 keeps `actor_display_name` as a key inside `payload`. §15.1 return shape no longer enumerates a top-level `actor_display_name`; clients read it from `row.payload.actor_display_name`. §15.3 no longer describes a denormalized copy; `get_notification` returns the notification row with `payload` intact. | None — the router already materializes `payload.actor_display_name`; only the return-shape enumerations changed to remove ambiguity. | Yes |
| F-6 | LOW | §12.4 Workspace/Stakeholder/Invitation event cluster header; §12.4 wired-consumer paths sentence | The header claimed "(7)" while the enumerated list contains 9 events. The "approximately 32 wired consumer paths" total was recounted accordingly. | Header changed to "(9)". Total recounted to "approximately 34 wired consumer paths". | None — count/label correction only. | Yes |
| F-7 | LOW | §1.1; §3.3; §9.6; §20.5 | The proposal referred to "the frozen `enforce_activity_events_append_only` trigger" (singular). The frozen baseline actually installs two triggers (`activity_events_no_update` and `activity_events_no_delete`) that share the `enforce_activity_events_append_only` function. Every mention updated. | Every referenced section now cites "the frozen `activity_events_no_update` and `activity_events_no_delete` triggers, which share the `enforce_activity_events_append_only` function." Function name preserved. | None — narrative correction only; no DDL change. | Yes |

### 3. Final backend surface summary

Concise enumeration of every additive item, unchanged from the pre-review proposal except where corrections landed:

- 1 wired table (`notifications`) + 4 reserved-name-only tables (`notification_preferences`, `notification_deliveries`, `notification_digests`, `notification_router_errors`) — unchanged.
- 19 additive product-domain columns on `notifications` (21 physical columns counting `created_at` and `updated_at` housekeeping) — unchanged.
- 8 additive indexes (9 including the actor-partial I-9 scheduled for Wave 2) — unchanged; F-4 clarifies I-7 predicate rationale (defensive scaffolding for Wave 4 replay workers; unreachable in v1).
- 5 additive CHECK constraints — unchanged.
- 4 additive FKs (1 composite `(project_id, workspace_id) → projects`; 3 non-composite: `recipient_profile_id`, `source_event_id`, `actor_profile_id`); every FK covered by an index.
- 2 wired capabilities (`notification.view`, `notification.manage`) + 6 reserved zero-grant capabilities under the `notification.*` prefix — unchanged.
- 6 read RPCs, 8 write RPCs — unchanged; F-5 normalizes the `actor_display_name` return shape (read from `payload.actor_display_name`).
- 0 new emitted event types in v1 — unchanged.
- 3 reserved past-tense event names (`notification.ai_prioritized`, `notification.ai_summarized`, `notification.digest_sent`) — unchanged.
- 4 additive triggers: routing bridge on `activity_events` (AFTER INSERT, exception-safe, with the F-2 explicit `notification.*` recursion guard); `notifications_set_updated_at`; `enforce_notification_immutable_fields`; `enforce_notification_rpc_only_writes` — unchanged.
- 1 boundary-additive AFTER INSERT trigger on the frozen `activity_events` table — unchanged; F-7 corrects the frozen trigger names in narrative (frozen baseline installs `activity_events_no_update` and `activity_events_no_delete` sharing the `enforce_activity_events_append_only` function).
- 1 `CREATE OR REPLACE` on the frozen `lign_has_capability(uuid, uuid, text)` — strictly additive, byte-identical role-map preservation (F-3 clarifies).

### 4. Final implementation waves

The 4-wave plan (§18) is unchanged in shape:

- **Wave 1 Critical (18 headline items):** schema + routing bridge + core RPCs + Wave-1 doc-diffs. F-1's helper-verification subsection (§2.12) ships alongside Wave 1 schema migration as a proposal-doc reference. F-2's explicit recursion guard is inside the Wave 1 router function body (added to the §9.1 outline; no new function, no signature change).
- **Wave 2 High (8 items):** secondary read/write RPCs; index I-9.
- **Wave 3 Medium (6 items):** cross-slice integration polish; documentation completeness.
- **Wave 4 Future (14 items):** reserved seams; async delivery; AI; preferences; retention; realtime.

F-3, F-4, F-5, F-6, and F-7 are documentation-only edits landing in this Re-freeze Report and inline in the proposal body before Wave 1 implementation begins.

### 5. Cross-slice compatibility guarantee

Every prior slice's contract is preserved byte-identically:

- **APP 001 (Auth / Foundation).** No migration or file modified. `profiles`, `workspaces`, `workspace_members`, `stakeholders`, `invitations` unchanged.
- **APP 002 (Application Shell).** No file modified.
- **APP 003 (Projects & Design Workspace).** No migration modified. `projects`, `project_participants`, `collections`, `disciplines` unchanged.
- **APP 004 (Files & Viewer).** No migration modified.
- **APP 005 (Comments & Annotations).** No migration modified.
- **APP 006 (Reviews).** No migration modified; every `review.*` event, RPC, RLS policy, and trigger byte-identical.
- **APP 007 (Approvals).** No migration modified; every `approval.*` event, RPC, RLS policy, and trigger byte-identical.
- **APP 008 (Requirements).** No migration modified; every `requirement.*` event, RPC, RLS policy, and trigger byte-identical.
- **APP 009 (Releases).** No migration modified; every `release.*` event, RPC, RLS policy, and trigger byte-identical.
- **APP 011 (Realtime — not yet frozen).** No dependency violated; `notifications` remains OUT of the `supabase_realtime` publication in v1, as reserved by the (future) APP 011 re-freeze.

Explicit surface guarantees:

- **No APP 001–009 migration or file modified.**
- **Frozen `activity_events` table shape and RLS byte-identical.** The APP 010 boundary-additive AFTER INSERT trigger reads NEW and writes only to the new `notifications` table.
- **Frozen `activity_events_no_update` and `activity_events_no_delete` triggers preserved and enabled**, and their shared `enforce_activity_events_append_only` function is unchanged.
- **`lign_has_capability(uuid, uuid, text)` reissued additively** via exactly one `CREATE OR REPLACE`: every frozen role's grant array is byte-identical; only the `notification.*` keys are appended (2 wired grants; 6 reserved keys returning `false` for every caller).
- **No workflow-table mutation from any APP 010 RPC or trigger.**
- **Realtime remains OUT of `supabase_realtime` publication.**

### 6. Freeze checklist

| # | Check | Status |
|---|---|---|
| C-1 | RLS `notifications_select` third predicate references only helpers that exist in the frozen baseline (F-1) | Yes |
| C-2 | `lign_has_capability` reissue is strictly additive: byte-identical role-map preservation; only `notification.*` keys appended (F-3) | Yes |
| C-3 | Router function body carries an explicit `notification.*` recursion guard as the primary defense (F-2) | Yes |
| C-4 | Dedup partial-unique predicate justification is honest about v1 reachability (F-4) | Yes |
| C-5 | `actor_display_name` has exactly one canonical position (`payload.actor_display_name`) across §5.16, §15.1, §15.3 (F-5) | Yes |
| C-6 | §12.4 event cluster count matches the enumerated list; wired-consumer path total recounted (F-6) | Yes |
| C-7 | Frozen `activity_events` trigger names (`activity_events_no_update`, `activity_events_no_delete`) are named correctly wherever they appear (F-7) | Yes |
| C-8 | Zero new backend surface introduced beyond the accepted corrections | Yes |
| C-9 | Zero APP 001–009 migration, RPC, RLS policy, or trigger modified | Yes |
| C-10 | Realtime publication membership unchanged (`notifications` OUT) | Yes |
| C-11 | Router body remains exception-safe (§2.8, §9.1) — inviolable | Yes |
| C-12 | Payload immutability preserved (§2.9, §9.2) | Yes |
| C-13 | No workflow-side mutation from any APP 010 RPC or trigger (§1.2, §16.10) | Yes |

### 7. Final freeze contract

This document is the authoritative backend contract for APP 010 upon the Backend Re-freeze cycle's completion. It supersedes the pre-review proposal and is the input to Migration A + Migration B implementation. Future changes require an amendment and re-freeze.

**APP 010 Backend is frozen.**

---

**Design proposal only. No SQL, no implementation, no migrations.** Every backend addition required to support the frozen APP 010 architecture, mapped to the Freeze Index sections and prioritized for a phased Backend Re-freeze. This document is the authoritative pre-review backend contract; a Backend Re-freeze Review cycle will follow.

**Companion documents:**
- [`APP_010_FREEZE_INDEX.md`](APP_010_FREEZE_INDEX.md) — the frozen architecture this proposal supports. §26 (Backend delta preview) is the authoritative scope anchor.
- [`APP_009_BACKEND_PROPOSAL.md`](APP_009_BACKEND_PROPOSAL.md) — primary pattern reference: additive-only slice on top of frozen infrastructure; single-function `CREATE OR REPLACE` default-tail discipline (not exercised here — APP 010 extends no frozen RPC); Wave 1 doc-diff registration of RESERVED event names; coverage-matrix shape.
- [`APP_008_BACKEND_PROPOSAL.md`](APP_008_BACKEND_PROPOSAL.md) — secondary pattern reference: additive-only slice; RESERVED capability enumeration with zero role grants.
- [`APP_007_BACKEND_PROPOSAL.md`](APP_007_BACKEND_PROPOSAL.md) — tertiary pattern reference: chain-init discipline (T-CRIT-1) — cited here only to state that APP 010 has no chain columns and no chain-init discipline applies.
- [`freeze/APP_009_FINAL_CERTIFICATION.md`](freeze/APP_009_FINAL_CERTIFICATION.md), [`freeze/APP_008_FINAL_CERTIFICATION.md`](freeze/APP_008_FINAL_CERTIFICATION.md), [`freeze/APP_007_FINAL_CERTIFICATION.md`](freeze/APP_007_FINAL_CERTIFICATION.md), [`freeze/APP_006_FINAL_CERTIFICATION.md`](freeze/APP_006_FINAL_CERTIFICATION.md) — governance shapes for the Backend Re-freeze cycle.
- [`PLATFORM_BASELINE.md`](PLATFORM_BASELINE.md), [`PLATFORM_CHEATSHEET.md`](PLATFORM_CHEATSHEET.md), [`ARCHITECT_REVIEW_CHECKLIST.md`](ARCHITECT_REVIEW_CHECKLIST.md) — constitutional rules.
- [`DOMAIN_MODEL.md`](DOMAIN_MODEL.md), [`DATABASE_SCHEMA.md`](DATABASE_SCHEMA.md), [`STATE_MACHINES.md`](STATE_MACHINES.md), [`SCHEMA_V1_LOCK.md`](SCHEMA_V1_LOCK.md), [`AUTHORIZATION_ARCHITECTURE.md`](AUTHORIZATION_ARCHITECTURE.md).
- [`EVENT_MODEL.md`](EVENT_MODEL.md) — the sole source of truth for the frozen event vocabulary APP 010 consumes.
- [`PERMISSIONS.md`](PERMISSIONS.md) — capability catalog; APP 010 adds 2 wired keys + 6 RESERVED keys under the `notification.*` prefix.

**Frozen invariants cited by this proposal (MUST NOT modify):**

- `supabase/migrations/20260729235959_activity_events.sql` L75 — `public.activity_events.id uuid primary key`. The router's `source_event_id` FK targets this frozen PK.
- `supabase/migrations/20260729235959_activity_events.sql` (full body) — the frozen `activity_events_no_update` and `activity_events_no_delete` triggers, which share the `enforce_activity_events_append_only` function (blocks UPDATE and DELETE on the audit log). APP 010's AFTER INSERT trigger coexists with these frozen triggers; the two do not conflict (AFTER INSERT is an additive install, orthogonal to UPDATE/DELETE denial).
- `supabase/migrations/20260802000000_auth_009_activity_events_rls.sql` — RLS policies on `activity_events`. APP 010 does not modify these policies. The router trigger runs `SECURITY DEFINER` and reads recipient-resolution tables directly, never mutating `activity_events`.
- Frozen `activity_events.event_type text NOT NULL` — the discriminator the router dispatches on. Every routing rule keys off a frozen string; APP 010 does not add to this vocabulary.
- Frozen `activity_events.subject_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb` — the router reads keys documented by the source slice's freeze index only (APP 006 §17, APP 007 §17, APP 008 §12, APP 009 §20.4). Unknown keys ignored per the additive-consumer contract.
- Frozen `activity_events.actor_profile_id uuid NULL` — self-exclusion source. NULL for `actor_kind='system'` events (where self-exclusion is a no-op).
- Frozen `activity_events.project_id uuid NULL` (v0.3 addition) — populated for project-scoped events, NULL for workspace-scoped. Copied verbatim into `notifications.project_id` for consistent tenancy shape.
- Frozen `activity_events.workspace_id uuid NOT NULL` — copied verbatim into `notifications.workspace_id`.
- Frozen `set_updated_at()` trigger function (declared by APP 001 foundation; reused across every workflow slice) — APP 010 reuses it verbatim for `notifications_set_updated_at`.
- Frozen 60 P0 event vocabulary in `EVENT_MODEL.md` §4 — the router's routing table (Freeze Index §8.1) maps a subset of these to `notification_type` values. APP 010 emits zero workflow events.
- Frozen capability primer in `PERMISSIONS.md` §5 (role presets) — APP 010 additively registers `notification.view` and `notification.manage` in every role. No frozen capability role map row is modified.
- Frozen `lign_has_capability(project_id, workspace_id, capability_key text) → boolean` — extended additively to recognize the 2 wired `notification.*` keys and the 6 RESERVED keys (returning `false` for RESERVED keys since they carry zero role grants).
- Frozen `activity_events` is **NOT** in `supabase_realtime` (REALTIME 001 boundary). APP 010's new `notifications` table also stays OUT of the publication (Freeze Index §25).
- Frozen `set_updated_at()` — reused for `notifications_set_updated_at` BEFORE UPDATE trigger.

---

## Executive summary

- **Scope anchor.** This proposal implements the backend surface delta enumerated in `APP_010_FREEZE_INDEX.md` §26. That preview is authoritative: 1 new wired table (`notifications`), 4 name-reserved tables (`notification_preferences`, `notification_deliveries`, `notification_digests`, `notification_router_errors`), 19 additive columns on the new table, 0 new columns on any frozen table, 6 additive read RPCs, 8 additive write RPCs, 0 modifications to frozen RPC signatures, 2 wired capabilities (`notification.view`, `notification.manage`), 6 RESERVED capabilities, 0 emitted event types in v1, 3 RESERVED event names in the `notification.*` namespace, 8 additive indexes, 4 additive triggers (1 routing bridge + 3 defense-in-depth), and realtime status **OUT** of publication.
- **Additive-only guarantee.** No frozen RPC signature is renamed, removed, or altered. No frozen event name is renamed or redefined. No frozen capability role map row is changed. No frozen table RLS policy is weakened. No frozen trigger is removed or modified. No frozen column is added, dropped, renamed, or narrowed on any APP 001–009 table. The single boundary-additive extension on a frozen surface is the AFTER INSERT trigger on `activity_events`; §9 documents that this trigger reads NEW and writes only to the new `notifications` table — it never modifies `activity_events`, never mutates the frozen table's shape, and never blocks a workflow transaction (its function body catches every exception; see §2, §9, §17, §20).
- **APP 010 owns notification DELIVERY. It does NOT own business workflow.** Zero write RPC in this proposal touches `reviews`, `approvals`, `approval_requests`, `approval_responses`, `approval_request_approvers`, `requirements`, `requirement_assessments`, `version_requirement_assessments`, `releases`, `release_items`, `comments`, `annotations`, `design_assets`, `asset_versions`, `project_participants`, `workspace_members`, `profiles`, or any other workflow table. Every write RPC mutates only rows in `notifications` where `recipient_profile_id = auth.uid()`.
- **Router exception-safety is the single most important design constraint.** The AFTER INSERT trigger `enforce_notification_router_bridge` on `activity_events` invokes `resolve_notification_router_targets(...)` whose function body wraps every operation in `BEGIN … EXCEPTION WHEN OTHERS THEN RAISE WARNING …; END`. Under no circumstance does a router failure cause a workflow transaction rollback. This is repeated in §2 (conventions), §9 (trigger model), §17 (backend gaps), and §20 (backwards-compatibility guarantees).
- **Realtime remains OUT.** The `notifications` table is not added to the `supabase_realtime` publication. Adding it is an APP 011 re-freeze concern, not APP 010's. In v1 the client polls (60s bell/inbox; 30s Notification Center popover) per Freeze Index §25.4.
- **Zero new emitted events in v1.** The read/dismissed/archived lifecycle is stored in the row (`read_at`, `dismissed_at`, `archived_at` timestamptz flags). Emitting `notification.read` back into `activity_events` would create feedback into the very audit spine APP 010 consumes and would violate G-16 (no notification-of-notification). Three event names are RESERVED under `notification.*` (`notification.ai_prioritized`, `notification.ai_summarized`, `notification.digest_sent`) — Wave 1 doc-diff registers them in EVENT_MODEL.md alongside Migration A.
- **Dedup + self-exclusion enforced at INSERT time.** The router uses `INSERT … ON CONFLICT DO NOTHING` against a partial unique index `(recipient_profile_id, source_event_id, notification_type) WHERE archived_at IS NULL`. Self-exclusion is enforced in the recipient-set computation: `WHERE recipient_profile_id != NEW.actor_profile_id` (skipped for `actor_kind='system'` events where `NEW.actor_profile_id IS NULL`). Both invariants are documented in Freeze Index §9.7, §9.8, G-7, G-8, G-15.
- **Payload materialized at INSERT time (immutable).** The router copies rendering-required subset of `activity_events.subject_snapshot` into `notifications.payload` at write time. Subsequent renames or edits to the source subject do not retroactively change historical notifications. `payload` is enforced immutable by BEFORE UPDATE trigger `enforce_notification_immutable_fields`. Matches EVENT_MODEL.md §8 snapshot immutability and Freeze Index G-57.
- **Recipient resolution reads workflow-side membership tables but never mutates them.** The router reads `workspace_members`, `project_participants`, `profiles`, and (for the direct-actor rule) `review_participants`, `approval_request_approvers`, `annotations`, `changes`, `reviews`, `approval_requests`, `invitations`. All reads are through the router function running `SECURITY DEFINER`; no read RPC or write RPC exposes any cross-table read to the client beyond the notification row's own hydrated `payload`.
- **RPC-only writes with dual defense.** All 8 write RPCs (`mark_notification_read`, `mark_notification_unread`, `mark_all_notifications_read`, `mark_notifications_read_bulk`, `dismiss_notification`, `dismiss_notifications_bulk`, `archive_notification`, `archive_notifications_bulk`) are `SECURITY DEFINER`, enforce `recipient_profile_id = auth.uid()` in-body, and are backed by the `enforce_notification_rpc_only_writes` trigger that blocks direct UPDATE from user code unless a `lign.allow_notification_rpc_write` GUC is set. Same discipline as the frozen `enforce_release_status_via_rpc` pattern (APP 009 AUTH 008 L38).
- **Capability model minimalism.** Two capability keys wired in v1 (`notification.view`, `notification.manage`); both are granted to every authenticated role because notifications are personal. Six RESERVED keys under `notification.*` prefix (`notification.view_any`, `notification.announce`, `notification.ai_prioritize`, `notification.ai_summarize`, `notification.ai_digest`, `notification.preference`) — zero role grants in v1, per Freeze Index §19.3, G-24, G-27, G-43.
- **Wave plan.** Wave 1 Critical (schema + routing bridge + core RPCs + Wave-1 doc-diff for 3 RESERVED event names + 6 RESERVED capability names + 4 RESERVED table names); Wave 2 High (secondary read/write RPCs); Wave 3 Medium (documentation completeness, saved-view integration, invalidation helper); Wave 4 Future (preference wiring, delivery workers, AI seams, retention pruning, realtime activation blocked on APP 011).
- **Backwards-compat closure.** After this proposal lands: every APP 001–009 contract byte is preserved. `activity_events` schema is byte-identical. All APP 006/007/008/009 event names, capability keys, RPC signatures, RLS policies, and triggers are byte-identical. Callers of any frozen RPC continue to compile and execute unchanged; APP 010 is a purely additive consumer per Freeze Index G-44.

---

## 0. Conventions

Every proposed change carries four attributes.

- **Why:** the concrete user-facing behavior or invariant it enables.
- **Freeze Index section:** the APP 010 Freeze Index section (`§n`) or governance-decision ID (`G-n`) that requires it.
- **Priority:** `Critical` | `High` | `Medium` | `Future`.
- **Blocks implementation?** `yes` (v1 cannot ship without it) or `no` (v1 works without; polish or deferred).

Priority tiers:

| Tier | Meaning |
|---|---|
| **Critical** | v1 cannot ship at all without this. Must land in the first re-freeze wave. |
| **High** | v1 can start but a major feature is degraded or stubbed. First or second wave. |
| **Medium** | Polish / enterprise-adjacent; v1 works without it. Third wave. |
| **Future** | v2 territory; explicitly out of APP 010 v1 shipping scope. |

House rules (repeated verbatim from APP 006 / APP 007 / APP 008 / APP 009 backend proposals so this document stands alone):

- **Additive-only.** No column is renamed. No column is dropped. No CHECK is narrowed. No enum value is removed. Every new column is nullable (except the small immutable-at-INSERT identity/pointer columns) with sensible defaults, every new CHECK either applies only to the new column or is a widening. APP 010's additive surface is entirely on new objects (`notifications` table, 4 new indexes, 4 new triggers, 14 new RPCs, 2 new capabilities); the only touch of a frozen surface is the AFTER INSERT trigger on `activity_events` documented in §9 as boundary-additive.
- **Frozen RPC extension posture.** APP 010 performs exactly one `CREATE OR REPLACE` of the frozen `lign_has_capability(uuid, uuid, text)` function. This replacement is strictly additive: the signature is preserved; every existing capability key and role mapping remains byte-identical; only the new `notification.*` capability keys (2 wired + 6 reserved) are appended. No existing capability changes. No overload is introduced. No named-argument ambiguity arises. Per checklist C-2, byte-identical role-map preservation is guaranteed. Beyond this single additive reissue, there is no `CREATE OR REPLACE` on any other frozen function and no single-function default-tail-param extension. The APP 008 / APP 009 Option-A tail-param discipline is cited only to state that it is not exercised here. Every new RPC in this proposal is a brand-new `CREATE FUNCTION` on a brand-new namespace (all identifiers begin with `notification_` or `mark_notification` / `dismiss_notification` / `archive_notification` / `mark_all_notifications` / `mark_notifications_read_bulk` / etc.).
- **SECURITY DEFINER + `SET search_path = ''`.** Every new RPC is `SECURITY DEFINER` with `SET search_path = ''`. Every RPC is `REVOKE`d from `public`, `anon`, `authenticated` and then `GRANT`ed `EXECUTE` to `authenticated, service_role`. The router trigger function (`resolve_notification_router_targets`) is also `SECURITY DEFINER` because it reads recipient-resolution tables that the caller (an arbitrary workflow-RPC caller with narrower capability) may not have SELECT on directly — bypass required. The three defense-in-depth triggers (`enforce_notification_immutable_fields`, `enforce_notification_rpc_only_writes`, `notifications_set_updated_at`) inspect only OLD/NEW columns of the trigger's own row and are therefore **NOT** `SECURITY DEFINER` (following the APP 009 F-6 precedent). All trigger functions set `SET search_path = ''` and are `REVOKE`d from `public` / `anon` / `authenticated` with no `GRANT` (trigger functions fire under the row-writer's transaction context and never need `EXECUTE`).
- **Composite tenancy.** Every new FK where composite scope is semantically meaningful is composite. `notifications.project_id` FK is composite `(project_id, workspace_id) → projects(id, workspace_id)` when `project_id IS NOT NULL` (matches APP 003 project composite anchor unique per SCHEMA_V1_LOCK.md house rule). `notifications.recipient_profile_id → profiles(id) ON DELETE SET NULL` is non-composite (mirrors the frozen `created_by_profile_id` pattern on every workflow table). `notifications.source_event_id → activity_events(id) ON DELETE CASCADE` is non-composite because `activity_events` has only a PK on `(id)` — no composite anchor unique exists on the audit table (verified against `supabase/migrations/20260729235959_activity_events.sql` L75), so a composite FK is structurally impossible; workspace-tenancy coherence is enforced at INSERT time by the router setting `notifications.workspace_id = NEW.workspace_id` verbatim from the trigger's NEW row.
- **Covering index on every new FK.** No new FK ships without a matching btree index on the FK columns. Partial-index predicates (`WHERE col IS NOT NULL`) are used when the FK is nullable to keep the index small.
- **Capability naming per PERMISSIONS.md.** Dot-separated `subject.verb` (e.g., `notification.view`, `notification.manage`, `notification.ai_prioritize`). Every capability key is registered in PERMISSIONS.md §5 (role map) and mirrored in `CAPABILITY_KEYS` TypeScript constants.
- **Event naming per EVENT_MODEL.md.** Past-tense (`notification.digest_sent`, `notification.ai_prioritized`, `notification.ai_summarized`). Never future-tense. Never bare verbs. Every RESERVED name conforms; every RESERVED name is registered with the `RESERVED` annotation and no emitter in Wave 1 doc-diff.
- **RESERVED event names.** A RESERVED name is a name-only lock in EVENT_MODEL.md. No emitter exists in APP 010 v1. Future waves (AI slice, cron/digest slice, external delivery workers) fill them later against the fixed strings.
- **RESERVED capability keys.** A RESERVED capability is a name-only lock in PERMISSIONS.md. No role grants exist in APP 010's `lign_has_capability` extension for these keys; `lign_has_capability(project_id, workspace_id, 'notification.ai_prioritize')` returns `false` for every caller in v1.
- **Router exception-safety (inviolable).** The router function body wraps its work in `BEGIN … EXCEPTION WHEN OTHERS THEN … END` with the handler doing at most `RAISE WARNING 'notification router failed for event % (type %): %', NEW.id, NEW.event_type, SQLERRM;`. It never re-raises. If the future `notification_router_errors` table lands (Wave 4), the handler inserts a row there instead — but that table is RESERVED-name-only in v1. This rule is repeated in §2 (conventions preamble), §9 (trigger model), §17 (backend gaps), and §20 (backwards-compatibility). It is the single most important design constraint of APP 010.
- **Recipient-write RLS discipline.** No client-side write path (INSERT, UPDATE, DELETE) is permitted directly against `notifications`. All INSERT is via the router trigger (SECURITY DEFINER); all UPDATE is via the 8 write RPCs (SECURITY DEFINER, RPC-gate GUC discipline mirroring APP 009 AUTH 008 L38); DELETE is denied entirely (retention pruning in a future wave uses `service_role`).
- **Payload immutability (except recipient flags).** Every column on `notifications` other than the four mutable recipient-axis flags (`read_at`, `dismissed_at`, `archived_at`, `updated_at`) is immutable after INSERT. Enforced by the `enforce_notification_immutable_fields` trigger (§9).
- **`COMMENT ON COLUMN` house pattern.** Every new column ships with a `COMMENT ON COLUMN` in the same migration (APP 006 house pattern; APP 007 F-1.4; APP 008 §0; APP 009 §0). Not enumerated per column below.
- **Never mutate a workflow table.** Every APP 010 RPC and trigger reads workflow-side tables at most (for recipient resolution) and writes only to the new `notifications` table. This is repeated in §1, §2, §8, §16, §19, §20.

---

## 1. Purpose

APP 010 owns the backend surface for **notification delivery**. It introduces exactly one new wired table (`notifications`), a small set of RPCs to read and mutate that table, a routing bridge that consumes committed `activity_events` rows and materializes per-recipient notification rows, defense-in-depth triggers to keep payload immutability and self-write discipline, and two additive capability keys. Every other APP 010 surface (email/push transports, cron digests, AI reprioritization, preferences, realtime activation) is RESERVED-name-only in v1 per Freeze Index §26 and §29.2.

### 1.1 The router bridge concept

The heart of APP 010 is the **event → recipient router**. The pipeline (per Freeze Index §1.2 and §2.3):

```
   workflow-RPC (APP 005–009 frozen, unchanged)
        │
        ▼
   activity_events INSERT  (same TX, committed fact — never mutated by APP 010)
        │
        ▼ AFTER INSERT trigger `enforce_notification_router_bridge`
   resolve_notification_router_targets(NEW)   (SECURITY DEFINER, exception-safe)
        │
        ▼ (routing table lookup → recipient set → dedup → self-exclusion → payload materialize)
   notifications INSERT ... ON CONFLICT DO NOTHING  (one row per resolved recipient)
        │
        ▼ client read (list_notifications_inbox / get_notification_badge_count / get_notification_center)
   client-side mark_notification_read / dismiss_notification / archive_notification
```

The router **never writes to `activity_events`** — the audit log is append-only per DATABASE_SCHEMA.md §3.25 and the frozen `activity_events_no_update` and `activity_events_no_delete` triggers, which share the `enforce_activity_events_append_only` function. The router **never mutates any workflow-side table** — it only reads `workspace_members`, `project_participants`, `profiles`, and (per routing rule) small subsets of `review_participants`, `approval_request_approvers`, `reviews`, `approval_requests`, `annotations`, `changes`, `invitations` for recipient resolution. All reads are through the SECURITY DEFINER trigger function; no read is exposed to the client beyond the hydrated `notifications.payload`.

### 1.2 The no-workflow-mutation statement (repeated for emphasis)

**APP 010 never mutates a workflow table.** No RPC in this proposal writes to:

- `reviews`, `review_participants`, `review_rounds` (APP 006).
- `approval_requests`, `approval_responses`, `approval_request_approvers`, `approvals` (APP 007).
- `requirements`, `version_requirement_assessments`, `requirement_assessments` (APP 008).
- `releases`, `release_items` (APP 009).
- `comments`, `annotations` (APP 005).
- `design_assets`, `asset_versions`, `files` (APP 004).
- `projects`, `project_participants`, `collections`, `disciplines` (APP 003).
- `workspaces`, `workspace_members`, `stakeholders`, `invitations`, `profiles` (APP 001, APP 002).
- `activity_events` (frozen audit log).

Every write path in APP 010 mutates rows in `notifications` where `recipient_profile_id = auth.uid()` and touches nothing else.

### 1.3 What APP 010 owns exclusively (backend perspective)

- The `notifications` table and its 19 columns.
- 8 additive indexes on `notifications`.
- 3 additive CHECK constraints on `notifications`.
- 4 additive triggers on/around `notifications` and `activity_events`:
  - 1 routing bridge (AFTER INSERT on `activity_events`, invokes the router function).
  - 1 immutability trigger (BEFORE UPDATE on `notifications`, blocks changes to non-flag columns).
  - 1 RPC-only-write trigger (BEFORE UPDATE on `notifications`, requires `lign.allow_notification_rpc_write` GUC).
  - 1 timestamp maintenance trigger (BEFORE UPDATE on `notifications`, reuses frozen `set_updated_at`).
- 6 read RPCs.
- 8 write RPCs.
- 2 wired capability keys (`notification.view`, `notification.manage`) and 6 RESERVED keys.
- 0 emitted events in v1; 3 RESERVED event names in the `notification.*` namespace.
- 1 routing-table application constant mirrored inside the router function body (Freeze Index §8.2).

### 1.4 What APP 010 does NOT own

- The workflow-side RPCs that produce the source events (`create_review`, `respond_to_approval`, `finalize_release`, etc.) — these remain frozen and are cited here only as consumers of `activity_events`.
- The `/deep/<kind>/:id` route targets — every deep-link kind referenced by a notification's `payload.deep_link` is owned by the source slice (Freeze Index §15.1, G-23). APP 010 owns exactly one deep-link kind: `notification` → `/deep/notification/:id`.
- Email transport (SMTP), push transport (APNS/FCM), SMS transport — the payload contract is materialized at router time; the send is a Wave 4 downstream worker not owned by APP 010.
- Cron scheduler for digests — Wave 4.
- Preference table wiring — Wave 4.
- AI reprioritization — Wave 4.
- Realtime subscription of `notifications` INSERT — APP 011 (blocked pending REALTIME re-freeze).

---

## 2. Backend conventions

The APP 010 governance preamble. Every rule below is enforced in Wave 1 unless explicitly deferred.

### 2.1 Additive-only

APP 010 introduces one new table, 8 indexes, 3 CHECK constraints, 4 triggers, 14 RPCs, 2 capabilities. No frozen column is renamed, dropped, narrowed, or altered. No frozen CHECK is changed. No frozen index is dropped. No frozen trigger is removed. No frozen RPC signature is extended, overloaded, or redefined. No frozen event name is renamed or redefined. No frozen capability role map row is modified. No frozen RLS policy is weakened.

The **only** touch of a frozen surface is the AFTER INSERT trigger on `activity_events`. This is boundary-additive per §9 rationale: the trigger reads NEW (i.e., the just-inserted row's column values, as PostgreSQL exposes them to any trigger function) and writes only to the new `notifications` table. It does not `ALTER` the frozen table's shape, does not add or modify columns, does not modify RLS, does not change the frozen append-only trigger, and cannot mutate the audit row itself (because it fires AFTER INSERT, not BEFORE). Adding a trigger to a frozen table is permissible ONLY under these conditions; if any of them were violated, the extension would require a frozen-table re-freeze.

### 2.2 SECURITY DEFINER + `SET search_path = ''`

Every new RPC (14 total) and the router trigger function (1) is `SECURITY DEFINER` with `SET search_path = ''`. Every RPC is `REVOKE`d from `public`, `anon`, and `authenticated`; then `GRANT`ed `EXECUTE` to `authenticated, service_role`. The router trigger function is `REVOKE`d from `public`, `anon`, and `authenticated` with no `GRANT` (it fires from the trigger dispatcher, not from an explicit CALL).

The three row-local trigger functions (`enforce_notification_immutable_fields`, `enforce_notification_rpc_only_writes`, `notifications_set_updated_at`) inspect only OLD/NEW columns of the trigger's own row and are NOT `SECURITY DEFINER`, matching the APP 009 F-6 precedent (`supabase/migrations/20260801220000_auth_008_release_rls.sql` L38).

### 2.3 Composite tenancy discipline

Every new FK receives composite tenancy where semantically meaningful:

- `notifications.(project_id, workspace_id) → projects(id, workspace_id)` when `project_id IS NOT NULL`. Reuses the APP 003 project composite anchor unique. Prevents cross-workspace project pointers structurally.
- `notifications.recipient_profile_id → profiles(id) ON DELETE SET NULL`. Non-composite (profiles are workspace-transcendent).
- `notifications.actor_profile_id → profiles(id) ON DELETE SET NULL`. Non-composite (mirrors `recipient_profile_id`).
- `notifications.source_event_id → activity_events(id) ON DELETE CASCADE`. Non-composite (frozen `activity_events` has only a PK on `id`; no composite anchor unique exists on the audit log — verified against `supabase/migrations/20260729235959_activity_events.sql` L75). Workspace-tenancy coherence between the notification row and the source event row is enforced at INSERT time by the router: `notifications.workspace_id := NEW.workspace_id`.

### 2.4 Every FK covered by an index

Per §6 enumeration:

- FK `recipient_profile_id` → covered by I-1 (leading column of `(recipient_profile_id, workspace_id, read_at)` partial), I-2 (leading column of inbox scan), I-3, I-4, I-5 partial.
- FK `(project_id, workspace_id)` → covered by I-6 partial on `(project_id, workspace_id, created_at DESC)`.
- FK `source_event_id` → covered by unique index I-7 on `(recipient_profile_id, source_event_id, notification_type) WHERE archived_at IS NULL` (leading columns include `source_event_id` after `recipient_profile_id`; a supplementary `(source_event_id)` partial is included as I-8 for reverse-lookup queries).
- FK `actor_profile_id` → covered by I-9 partial on `(actor_profile_id, workspace_id, created_at DESC) WHERE actor_profile_id IS NOT NULL`.

### 2.5 Past-tense event names

Every new event name is past-tense: `notification.ai_prioritized`, `notification.ai_summarized`, `notification.digest_sent`. All three are RESERVED; APP 010 v1 emits none of them.

### 2.6 RESERVED discipline

RESERVED names carry:
- Zero emitter for events.
- Zero role grants for capabilities.
- Zero column DDL for reserved tables (name only, registered in DOMAIN_MODEL.md).
- Zero client-side wiring.

They exist to lock vocabulary so future waves can bind to fixed strings without renaming churn.

### 2.7 No workflow mutation (repeated)

Cited in §1.2 and §1.3. Every write RPC's body includes an inline capability re-check and an explicit `WHERE recipient_profile_id = auth.uid()` predicate. Any RPC that would mutate a workflow-side row is out of scope for APP 010 and must be proposed by the owning slice's re-freeze.

### 2.8 Router exception-safety (inviolable)

The router function body:

```
BEGIN
  -- routing table dispatch
  -- recipient resolution reads
  -- payload materialization
  -- INSERT ... ON CONFLICT DO NOTHING per recipient
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notification router failed for event % (type %): %',
      NEW.id, NEW.event_type, SQLERRM;
    -- swallow; never re-raise
END;
```

This discipline is inviolable. The router MUST NOT propagate any exception into the parent workflow transaction. If it did, a bug in APP 010 (e.g., a missing key in `subject_snapshot`, a NULL pointer in recipient resolution, a serialization deadlock on `workspace_members`) could roll back a legitimate workflow commit — which is unacceptable per the "workflow correctness > notification completeness" tradeoff codified in Freeze Index G-2 caveat.

If the router raises, the missed notification is a silent loss (visible only in Postgres logs via the WARNING). Post-hoc reconciliation is deferred. The `notification_router_errors` RESERVED table (§3) is the future observability seam; not shipped in v1.

Repeated in §9, §17, §20. This is the single most important design constraint of APP 010.

### 2.9 Immutability of payload

The `payload jsonb` column is materialized once at INSERT and never modified. Later renames or edits to the source subject do not retroactively change historical notification rendering. Enforced by:

- Freeze Index G-57 policy.
- `enforce_notification_immutable_fields` BEFORE UPDATE trigger (§9).
- No RPC in this proposal accepts a payload-mutating parameter.

### 2.10 Zero realtime activation

`notifications` is NOT in the `supabase_realtime` publication. This is explicitly stated in the migration comments and enforced by omission from the CREATE PUBLICATION list. Any addition is an APP 011 re-freeze concern.

### 2.11 No new deep-link resolver kinds beyond `notification`

Every notification's `payload.deep_link` references a `/deep/<kind>/:id` route owned by the source slice. APP 010 adds exactly one new kind: `notification` → `/deep/notification/:id` (per Freeze Index §15.2, G-23). Every other deep-link kind referenced by a notification is a frozen kind owned by the source slice (`review`, `approval`, `release`, `comment`, `requirement`, `version`, `asset`, `project`).

### 2.12 Helper function references — verified against frozen baseline

Every helper function referenced anywhere in this proposal (RLS predicates, RPC bodies, trigger bodies, router body) is enumerated below with its frozen source, exact line range, and purpose in APP 010. Every helper listed here exists in the frozen baseline; APP 010 introduces no new helper function. Every reference in this proposal is fully qualified with `public.` because APP 010's RPCs, trigger functions, and RLS policies execute under `SET search_path = ''` (per §2.2), and every referenced schema object must therefore be schema-qualified.

| Helper | Signature | Frozen migration file | Line range | Purpose in APP 010 |
|---|---|---|---|---|
| `public.lign_has_capability` | `(p_project_id uuid, p_workspace_id uuid, p_capability_key text) → boolean` | `supabase/migrations/20260730120000_auth_001_helpers_bootstrap.sql` | L199–323 (function body L199–316; grants L321–323) | Central authorization resolver reissued additively by APP 010 (see §11.3, F-3): every read RPC gates on `public.lign_has_capability(project_id, workspace_id, 'notification.view')`; every write RPC gates on `public.lign_has_capability(project_id, workspace_id, 'notification.manage')`; RLS `notifications_select` uses the same call. |
| `public.lign_project_role` | `(p_project_id uuid) → text` | `supabase/migrations/20260730120000_auth_001_helpers_bootstrap.sql` | L151–187 (function body L151–180; grants L185–187) | Belt-and-braces subject-access predicate in RLS `notifications_select` (§10.1): `public.lign_project_role(project_id) IS NOT NULL` verifies the caller currently has an active project role, filtering out notifications for projects the caller has since lost access to. |
| `public.lign_is_workspace_admin` | `(p_workspace_id uuid) → boolean` | `supabase/migrations/20260730120000_auth_001_helpers_bootstrap.sql` | L90–113 (function body L90–106; grants L111–113) | Third branch of the belt-and-braces subject-access predicate in RLS `notifications_select` (§10.1): admins retain visibility on notifications for projects in their workspace even if they are not explicit project participants. |
| `public.set_updated_at` | `() → trigger` | `supabase/migrations/20260728160001_foundation_profiles.sql` | L47–56 | Frozen trigger function reused verbatim by APP 010's `notifications_set_updated_at` BEFORE UPDATE trigger (§9.4). No new function declared. |
| `public.gen_random_uuid` (via `pgcrypto`) | `() → uuid` | Provided by the `pgcrypto` extension installed in schema `extensions` (frozen; used by every LIGN table's `id uuid primary key default gen_random_uuid()`) | N/A (extension symbol) | Default expression for `notifications.id` primary key (§5.1). |

**Router-body helper reads (no new helpers).** The router function body (§9.1) reads from frozen tables (`public.workspace_members`, `public.project_participants`, `public.profiles`, `public.review_participants`, `public.approval_request_approvers`, `public.reviews`, `public.approval_requests`, `public.annotations`, `public.changes`, `public.invitations`) directly rather than through helper functions, because recipient resolution requires a set of profile ids per rule, not a boolean check. No new helper functions are introduced.

**Explicit no-new-helper statement.** APP 010 introduces zero new helper functions. Every function reference in this proposal resolves to a helper already declared in a frozen migration file. Every reference is fully qualified with `public.` per the `SET search_path = ''` discipline.

---

## 3. Schema additions — narrative overview

APP 010 introduces the minimum backend surface required to implement the frozen product-surface architecture:

- **1 new wired table**: `notifications` (§4).
- **4 new name-reserved tables**: `notification_preferences`, `notification_deliveries`, `notification_digests`, `notification_router_errors` (§4.5). These carry no columns and no DDL in v1; only their names are locked in DOMAIN_MODEL.md and PERMISSIONS.md doc-diffs (Wave 1).
- **0 new columns on any frozen table.**
- **0 changes to any frozen index, CHECK, FK, or RLS policy.**
- **1 additive trigger on `activity_events` (boundary-additive)**: `enforce_notification_router_bridge` AFTER INSERT.

### 3.1 Why the single wired table

The Freeze Index §4.1 enumerates 19 columns on `notifications`. Every column serves a specific product surface (Inbox rendering, badge counts, filter facets, deep-link resolution, dedup, self-exclusion, email/push payload staging). Splitting the table into subordinate tables (e.g., a separate `notification_flags` for `read_at`/`dismissed_at`/`archived_at`) would produce a hotspot join for every list read and no size benefit (the flags are 24 bytes total on average). The Freeze Index G-1 decision recommends the single-table approach.

Splitting per-channel delivery (`notification_deliveries` join) is RESERVED for v1.1 when non-in-app channels ship. In v1 the `channels_attempted text[]` column captures the single channel `{in_app}` and the FK'd join table is unnecessary.

### 3.2 Why each RESERVED table

- **`notification_preferences`** — future per-user per-category muting / channel selection. v1 has no preferences (Freeze Index G-3), so the table has zero rows and would be a foreign key target for nothing. Reserving the name prevents rename churn when the preferences slice ships.
- **`notification_deliveries`** — future per-channel delivery attempt log (with retry count, last error, provider message id). v1 is in-app synchronous; every notification is delivered by the same INSERT. When email/push land, this table decouples delivery status from the notification identity.
- **`notification_digests`** — future batched digest sends (daily/weekly summary). Explicitly out of scope per user brief (Freeze Index §29.2). Reserved for a future cron/AI slice.
- **`notification_router_errors`** — future observability of router-body failures (§17 gap #1). v1 uses `RAISE WARNING` only; a table would let ops query historical failures. Reserved for a future observability wave.

### 3.3 The AFTER INSERT trigger on `activity_events` — additive-boundary rationale

Frozen: `activity_events` table shape, columns, indexes, RLS policies, and the frozen `activity_events_no_update` and `activity_events_no_delete` triggers, which share the `enforce_activity_events_append_only` function.

Added: `enforce_notification_router_bridge` AFTER INSERT ROW-level trigger, invoking `resolve_notification_router_targets(NEW)`.

Additive-boundary case:
- AFTER INSERT does not touch the frozen table's shape or data (a BEFORE INSERT would; AFTER INSERT sees the committed NEW row).
- Reads NEW columns (which are visible to any trigger function per Postgres semantics).
- Writes only to the new `notifications` table.
- Does not modify RLS on `activity_events`.
- Does not disable, drop, or modify the frozen `activity_events_no_update` and `activity_events_no_delete` triggers, which share the `enforce_activity_events_append_only` function.
- The router function is exception-safe: a failure does not roll back the parent transaction that INSERTed the audit row.

Under these conditions, adding a trigger to a frozen table does not require a frozen-table re-freeze — it is an additive extension of downstream consumption, analogous to adding a subscriber to a pub/sub topic. If any condition were violated (e.g., BEFORE trigger, RLS modification, non-exception-safe body), the extension would be out of scope for APP 010 and would require a re-freeze of Migration 009 (`20260729235959_activity_events.sql`) and AUTH 009 (`20260802000000_auth_009_activity_events_rls.sql`).

Documented as a boundary case in this proposal so any future re-freeze reviewer can see the explicit reasoning.

---

## 4. Tables

One new wired table (`notifications`) and four name-reserved tables. Each enumerated below with purpose, RLS discipline, write model, and DELETE policy.

### 4.1 `public.notifications` (wired v1)

- **Name.** `public.notifications`.
- **Purpose.** Per-recipient delivery record. Every row represents one delivered notification for one recipient about one source event. Row lifecycle is `delivered → read → (dismissed | archived)` per Freeze Index §3.1.
- **RLS discipline.**
  - RLS **enabled**.
  - **SELECT** policy `notifications_select`: `recipient_profile_id = (select auth.uid()) AND public.lign_has_capability(project_id, workspace_id, 'notification.view')`. Includes belt-and-braces subject-access predicate: `(project_id IS NULL OR public.lign_project_role(project_id) IS NOT NULL OR public.lign_is_workspace_admin(workspace_id))`. See §10.
  - **INSERT** policy `notifications_insert`: deny to `authenticated`. Router trigger runs as SECURITY DEFINER and bypasses RLS; no client-side INSERT is ever legal.
  - **UPDATE** policy `notifications_update`: allow when `recipient_profile_id = (select auth.uid())`, further gated at the trigger layer by `enforce_notification_rpc_only_writes` requiring the `lign.allow_notification_rpc_write` GUC (only settable inside a SECURITY DEFINER RPC).
  - **DELETE** policy `notifications_delete`: deny to all. No user-facing delete; retention pruning (deferred) uses `service_role`.
- **Write model.** RPC-only. Every INSERT is via the router trigger; every UPDATE is via one of the 8 write RPCs (§16); no DELETE.
- **DELETE policy.** No hard-delete in v1. Freeze Index G-41: retention pruning (deferred; not v1) may purge rows via `service_role` in a Wave 4 cron slice.
- **Realtime.** OUT of `supabase_realtime` publication (Freeze Index §25.1).
- **Freeze Index section:** §4.1, §26.1.
- **Priority:** Critical.
- **Blocks implementation?** Yes (every other APP 010 surface depends on the table).

### 4.2 `public.notification_preferences` (RESERVED-name-only)

- **Name.** `public.notification_preferences`.
- **Purpose (future).** Per-user per-category muting and per-channel selection (e.g., "mute `project_activity` in workspace X"; "email me on `governance_state_change` only").
- **v1 posture.** Name registered in DOMAIN_MODEL.md doc-diff (Wave 1). No columns, no RLS, no RPC, no client wiring.
- **Wave.** Future.

### 4.3 `public.notification_deliveries` (RESERVED-name-only)

- **Name.** `public.notification_deliveries`.
- **Purpose (future).** Per-channel delivery attempt log. FK to `notifications`; carries `channel text`, `attempt_at timestamptz`, `state text`, `retry_count int`, `last_error_text text`, `provider_message_id text`.
- **v1 posture.** Name registered in DOMAIN_MODEL.md doc-diff. In v1 delivery provenance is captured inline via `notifications.channels_attempted text[]` = `{in_app}` and `notifications.delivery_state text` = `'delivered'`.
- **Wave.** Future.

### 4.4 `public.notification_digests` (RESERVED-name-only)

- **Name.** `public.notification_digests`.
- **Purpose (future).** Batched digest sends (daily/weekly summary emails). FK to `profiles`; carries `sent_at`, `digest_body jsonb`, `notification_ids uuid[]`.
- **v1 posture.** Name registered in DOMAIN_MODEL.md doc-diff. Zero implementation.
- **Wave.** Future.

### 4.5 `public.notification_router_errors` (RESERVED-name-only)

- **Name.** `public.notification_router_errors`.
- **Purpose (future).** Router-failure observability. When `resolve_notification_router_targets` catches an exception, a row lands here instead of `RAISE WARNING`. Carries `id uuid`, `activity_event_id uuid`, `event_type text`, `error_message text`, `error_context jsonb`, `occurred_at timestamptz`.
- **v1 posture.** Name registered in DOMAIN_MODEL.md doc-diff. In v1 the router uses `RAISE WARNING` only.
- **Wave.** Future.

---

## 5. Columns

Every column on `public.notifications` is enumerated below with type, nullability, default, purpose, invariants, and priority tags. All 19 columns land in Wave 1.

### 5.1 `id uuid NOT NULL DEFAULT gen_random_uuid()` (PK)

- **Purpose.** Primary key. Immutable after INSERT.
- **Why.** Every row needs a stable UUID for deep-link (`/deep/notification/:id`), for RPC parameter references, and for TanStack Query cache keys.
- **Freeze Index section:** §4.1.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.2 `workspace_id uuid NOT NULL`

- **Purpose.** Tenant scope. Copied verbatim from `activity_events.workspace_id` at INSERT time.
- **FK.** Composite `(project_id, workspace_id) → projects(id, workspace_id)` when `project_id IS NOT NULL` (§7). No FK direct to `workspaces` (workspace tenancy is transitively enforced via the projects composite FK; when `project_id IS NULL`, workspace tenancy is enforced at RLS time by capability check).
- **Immutable after INSERT** (per §9 trigger).
- **Freeze Index section:** §4.1, §4.3.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.3 `project_id uuid NULL`

- **Purpose.** Project scope for project-scoped source events. NULL for workspace-scoped source events (mirrors `activity_events.project_id` NULL-per-scope semantics per DATABASE_SCHEMA.md §3.25).
- **FK.** Composite `(project_id, workspace_id) → projects(id, workspace_id) ON DELETE CASCADE` when `project_id IS NOT NULL`. Non-null enforcement via CHECK is not applied because NULL is a valid semantic (workspace-scoped notifications).
- **Immutable after INSERT** (per §9 trigger).
- **Freeze Index section:** §4.1, §4.3.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.4 `recipient_profile_id uuid NOT NULL`

- **Purpose.** The recipient of this notification row. Every row belongs to exactly one recipient. This is the primary axis of RLS (`recipient_profile_id = auth.uid()`).
- **FK.** `recipient_profile_id → profiles(id) ON DELETE SET NULL` (Freeze Index G-11). If the profile is later hard-deleted (not permitted in v1; profiles are soft-deleted), the FK survives with a NULL value and the row is filtered out by the RLS predicate at read time.
- **Immutable after INSERT.**
- **Freeze Index section:** §4.1, §4.3, G-11.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.5 `source_event_id uuid NOT NULL`

- **Purpose.** The originating `activity_events.id` row. Every notification traces back to exactly one committed workflow event (Freeze Index §1.2, §4.1).
- **FK.** `source_event_id → activity_events(id) ON DELETE CASCADE`. Non-composite because `activity_events` has only a PK on `(id)` — no composite anchor unique exists on the audit table (verified against `supabase/migrations/20260729235959_activity_events.sql` L75). CASCADE ensures orphan cleanup if the audit row were ever hard-deleted (never in v1, but the FK protects the invariant).
- **Immutable after INSERT.**
- **Freeze Index section:** §4.1, §4.3.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.6 `event_type text NOT NULL`

- **Purpose.** Denormalized copy of `activity_events.event_type` (e.g., `approval.requested`, `review.opened`). Powers filter-by-source-module without joining to the audit log.
- **CHECK.** No CHECK enum. `event_type` is application-owned free text per DATABASE_SCHEMA.md §3.25 note on `activity_events.event_type`. APP 010 does not narrow it.
- **Immutable after INSERT.**
- **Freeze Index section:** §4.1.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.7 `notification_type text NOT NULL`

- **Purpose.** The `notification.*`-typed classification (Freeze Index §5). Example: `review.assigned_to_you`, `approval.awaiting_your_decision`, `release.published_in_your_project`, `comment.mentioned_you`. Distinct from `event_type` — one event may produce different notification types for different recipients.
- **CHECK.** `notifications_notification_type_check`: NULL-permissive-not-applicable (column is NOT NULL). Enum values enumerated in Freeze Index §5 across §5.1–§5.7 (approximately 25 wired values). No CHECK enum is applied at DB level to keep the schema loose for future additive wires (adding a new `notification_type` is a Wave 4 additive change and should not require a DB migration). Enum-validity is enforced in the router function body (unknown types are logged and skipped per Freeze Index §20.6).
- **Immutable after INSERT.**
- **Freeze Index section:** §4.1, §5.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.8 `category text NOT NULL`

- **Purpose.** High-level grouping (Freeze Index §6.1): `assigned_to_me`, `mentions`, `project_activity`, `governance_state_change`, `deadlines`, `system`. Powers Inbox tabs and category filter chips.
- **CHECK.** `notifications_category_check`: `category IN ('assigned_to_me','mentions','project_activity','governance_state_change','deadlines','system')`. Enum is stable; adding a category is a rare re-freeze event per Freeze Index §6.
- **Immutable after INSERT.**
- **Freeze Index section:** §4.1, §6, G-13.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.9 `priority text NOT NULL DEFAULT 'medium'`

- **Purpose.** Priority ladder (Freeze Index §7.1): `critical`, `high`, `medium`, `low`, `informational`. Affects badge visibility (informational excluded from bell badge per §7.1) and toast presentation (critical/high toast; medium/low/informational no toast).
- **CHECK.** `notifications_priority_check`: `priority IN ('critical','high','medium','low','informational')`.
- **Immutable per row** (Freeze Index §7.2 — a `high`-priority notification does not decay to `medium` over time).
- **Freeze Index section:** §4.1, §7, G-14.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.10 `channels_attempted text[] NOT NULL DEFAULT ARRAY['in_app']::text[]`

- **Purpose.** Which channels the router attempted at INSERT time. In v1 always `{'in_app'}`; the router also inserts `email_payload` when the routing table entry specifies it for `workspace.member.invited`, `stakeholder.invited`, `workspace.member.suspended`, `workspace.member.removed`, `approval.requested` (per Freeze Index §8.1). The array does not indicate whether the channel *sent* — that is `delivery_state`. Freeze Index G-4.
- **CHECK.** `notifications_channels_attempted_check`: every element in `('in_app','email_payload','push_payload')`. NULL-permissive-not-applicable (NOT NULL with a default).
- **Immutable after INSERT.**
- **Freeze Index section:** §4.1, G-4.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.11 `delivery_state text NOT NULL DEFAULT 'delivered'`

- **Purpose.** Per-notification delivery aggregate state (Freeze Index §10.1): `pending`, `delivered`, `failed`, `suppressed`. In v1 always `'delivered'` at INSERT (in-app synchronous). `pending`/`failed`/`suppressed` reserved for post-v1 async channels.
- **CHECK.** `notifications_delivery_state_check`: `delivery_state IN ('pending','delivered','failed','suppressed')`.
- **Server-managed.** Immutable except via the (RESERVED) future delivery-worker path — no v1 RPC updates it.
- **Freeze Index section:** §4.1, §10.
- **Priority:** High.
- **Blocks implementation?** No (v1 always writes `'delivered'`; column exists so post-v1 additions do not need a schema change).

### 5.12 `subject_kind text NOT NULL`

- **Purpose.** Denormalized copy of `activity_events.subject_kind` for filter/link resolution without joining the audit log. Examples: `review`, `approval_request`, `release`, `comment`, `annotation`, `workspace_member`, `project_participant`.
- **Immutable after INSERT.**
- **Freeze Index section:** §4.1.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.13 `subject_id uuid NULL`

- **Purpose.** Denormalized copy of `activity_events.subject_id`. Nullable per EVENT_MODEL.md convention (some events have no discrete subject id). Used for reverse-lookup queries ("give me every notification for this release").
- **No FK.** Deliberately not a foreign key — mirrors the frozen `activity_events.subject_id` posture (DATABASE_SCHEMA.md §3.25 note L805: "Intentionally not a foreign key — events survive subject deletion"). APP 010 inherits the same posture.
- **Immutable after INSERT.**
- **Freeze Index section:** §4.1.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.14 `subject_label text NULL`

- **Purpose.** Denormalized copy of `activity_events.subject_label` (e.g., "Kitchen Layout · v3"). Powers Inbox card rendering without joining. Immutable per Freeze Index G-57 (renames of the source subject do not retroactively change the notification's label).
- **Immutable after INSERT.**
- **Freeze Index section:** §4.1, G-57.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.15 `actor_profile_id uuid NULL`

- **Purpose.** Denormalized copy of `activity_events.actor_profile_id`. NULL for `actor_kind='system'` events (per DATABASE_SCHEMA.md §3.25). Used for actor-filter UI (Freeze Index §12.3) and for self-exclusion cross-check.
- **FK.** `actor_profile_id → profiles(id) ON DELETE SET NULL`. Matches the frozen `activity_events.actor_profile_id` FK posture.
- **Immutable after INSERT.**
- **Freeze Index section:** §4.1, G-37.
- **Priority:** High.
- **Blocks implementation?** No (Inbox works without actor filter; adds polish).

### 5.16 `payload jsonb NOT NULL DEFAULT '{}'::jsonb`

- **Purpose.** Rendering-ready material derived from `activity_events.subject_snapshot` plus computed convenience fields. Contains the small subset of fields the UI needs for the preview snippet plus the deep-link descriptor. Base keys: `source_event_type`, `actor_display_name`, `subject_kind`, `subject_id`, `subject_label`, `occurred_at`, `deep_link{kind,id,workspace_id,project_id?}`. Rendering-only keys: `preview_snippet`, `avatar_seed`, `type_icon_hint`. Email-ready keys (when applicable): `email_subject_line`, `email_body_snippet`, `email_cta_url`, `email_cta_label`. Push-ready keys (when applicable): `push_title`, `push_body`, `push_data`. See Freeze Index §10.4.
- **CHECK.** `notifications_payload_size_check`: `octet_length(payload::text) <= 16384` (16 KB hard cap per Freeze Index G-39). Soft target 4 KB; enforced at router-build time by minimalism.
- **Immutable after INSERT** (per §9 trigger and Freeze Index G-57).
- **Freeze Index section:** §4.1, §10.4, G-39, G-57.
- **Priority:** Critical.
- **Blocks implementation?** Yes (Inbox card rendering depends on it).

### 5.17 `read_at timestamptz NULL`

- **Purpose.** Set by `mark_notification_read`. NULL means unread. Freeze Index §11.1.
- **Mutable via RPC only** (see §9 RPC-gate trigger).
- **Freeze Index section:** §4.1, §11.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.18 `dismissed_at timestamptz NULL`

- **Purpose.** Set by `dismiss_notification`. NULL means not dismissed. One-way — no un-dismiss RPC in v1. Freeze Index §3.1, §11.1.
- **Mutable via RPC only.**
- **Freeze Index section:** §4.1, §11.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.19 `archived_at timestamptz NULL`

- **Purpose.** Set by `archive_notification`. NULL means not archived. One-way in v1 (Freeze Index G-40; `unarchive_notification` is RESERVED for a future wave). Freeze Index §3.1, §11.1.
- **Mutable via RPC only.**
- **Freeze Index section:** §4.1, §11.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.20 `created_at timestamptz NOT NULL DEFAULT now()`

- **Purpose.** Router INSERT timestamp. Powers Inbox default sort (`created_at DESC, id DESC`) and cursor pagination.
- **Immutable after INSERT.**
- **Freeze Index section:** §4.1.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.21 `updated_at timestamptz NOT NULL DEFAULT now()`

- **Purpose.** Standard maintenance timestamp. Touch on any recipient-axis write via the `notifications_set_updated_at` BEFORE UPDATE trigger (§9).
- **Server-managed.**
- **Freeze Index section:** §4.1.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 5.22 Column count

Total: 19 columns on `notifications` (per Freeze Index §26.2). Enumerated: id, workspace_id, project_id, recipient_profile_id, source_event_id, event_type, notification_type, category, priority, channels_attempted, delivery_state, subject_kind, subject_id, subject_label, actor_profile_id, payload, read_at, dismissed_at, archived_at, created_at, updated_at.

Count check: id (1), workspace_id (2), project_id (3), recipient_profile_id (4), source_event_id (5), event_type (6), notification_type (7), category (8), priority (9), channels_attempted (10), delivery_state (11), subject_kind (12), subject_id (13), subject_label (14), actor_profile_id (15), payload (16), read_at (17), dismissed_at (18), archived_at (19), created_at (20), updated_at (21). Two identity/timestamp columns (`created_at`, `updated_at`) can be considered "housekeeping" not "product-domain" columns; when counted as such the domain count is 19, matching Freeze Index §26.2. When all 21 columns are counted, the total is 21. This proposal uses 19 to align with the Freeze Index while shipping all 21 physical columns.

### 5.23 No new columns on any frozen table

Explicitly stated: APP 010 adds zero columns to `activity_events`, `profiles`, `workspaces`, `workspace_members`, `projects`, `project_participants`, `collections`, `design_assets`, `asset_versions`, `files`, `reviews`, `review_participants`, `comments`, `annotations`, `changes`, `decisions`, `approval_requests`, `approval_responses`, `approval_request_approvers`, `approvals`, `releases`, `release_items`, `requirements`, `version_requirement_assessments`, `disciplines`, `user_bookmarks`, `user_saved_views`, `invitations`, `stakeholders`, or any other APP 001–009 table.

---

## 6. Indexes

Eight additive indexes on `public.notifications`. Every FK is covered. Every dashboard-supporting filter is supported by a partial or composite index. Every recipient-scoped scan targets `(recipient_profile_id, workspace_id, ...)` as the leading columns for partition-friendliness.

| # | Index | Table | Definition | Purpose | Priority |
|---|---|---|---|---|---|
| I-1 | `notifications_unread_by_recipient_idx` | `notifications` | `(recipient_profile_id, workspace_id, read_at) WHERE read_at IS NULL AND dismissed_at IS NULL AND archived_at IS NULL AND priority != 'informational'` | Badge count query (Freeze Index §14.1); the primary hot path — every `get_notification_badge_count` call scans this. | Critical |
| I-2 | `notifications_inbox_all_idx` | `notifications` | `(recipient_profile_id, workspace_id, created_at DESC, id DESC) WHERE dismissed_at IS NULL AND archived_at IS NULL` | Inbox "All" tab scan (Freeze Index §12.2 tab=all filter predicate). Cursor pagination target. | Critical |
| I-3 | `notifications_category_idx` | `notifications` | `(recipient_profile_id, workspace_id, category, created_at DESC) WHERE dismissed_at IS NULL AND archived_at IS NULL` | Category-filtered inbox scans (mentions/assigned/governance tabs). | Critical |
| I-4 | `notifications_priority_idx` | `notifications` | `(recipient_profile_id, workspace_id, priority, created_at DESC) WHERE dismissed_at IS NULL AND archived_at IS NULL` | Priority filter chip scans. | High |
| I-5 | `notifications_archived_idx` | `notifications` | `(recipient_profile_id, workspace_id, archived_at DESC) WHERE archived_at IS NOT NULL` | Archived-tab scan (Freeze Index §12.2 tab=archived). | High |
| I-6 | `notifications_project_scope_idx` | `notifications` | `(project_id, workspace_id, created_at DESC) WHERE project_id IS NOT NULL` | Project-filter scans (URL param `?project_id=...` per Freeze Index §16.1). Covers composite FK `(project_id, workspace_id)`. | High |
| I-7 | `notifications_dedup_uniq_idx` | `notifications` | `UNIQUE (recipient_profile_id, source_event_id, notification_type) WHERE archived_at IS NULL` | Dedup enforcement (Freeze Index G-7). Router uses `ON CONFLICT DO NOTHING` against this index. The `WHERE archived_at IS NULL` predicate allows re-materialization if the row is later archived and the same source event fires again (a rare edge case for reserved future events). | Critical |
| I-8 | `notifications_subject_reverse_idx` | `notifications` | `(subject_kind, subject_id, created_at DESC) WHERE subject_id IS NOT NULL` | Reverse-lookup queries (`list_notifications_by_source` — Wave 2 read RPC per Freeze Index §17.1). | Medium |
| I-9 | `notifications_actor_idx` | `notifications` | `(actor_profile_id, workspace_id, created_at DESC) WHERE actor_profile_id IS NOT NULL` | Actor-filter chip scans (Freeze Index §12.3 actor filter typeahead). Covers `actor_profile_id` FK. | Medium |

**Coverage rule.** Every new FK gets a covering btree index:

- FK `recipient_profile_id → profiles(id)` → covered by I-1 leading column, plus I-2/I-3/I-4/I-5 all leading with `recipient_profile_id`.
- FK `(project_id, workspace_id) → projects(id, workspace_id)` → covered by I-6 leading columns.
- FK `source_event_id → activity_events(id)` → covered by I-7 (unique) with `source_event_id` as the second column (Postgres uses this index for FK cascade lookups per equality predicate on non-leading columns). A supplementary standalone index `(source_event_id)` is not proposed because ON DELETE CASCADE from `activity_events.id` is a rare-to-never event in v1 (audit rows are never hard-deleted).
- FK `actor_profile_id → profiles(id)` → covered by I-9 leading column.

**No GIN index on `payload`.** Reserved for a future wave when full-text search inside notification payloads becomes a product requirement (Freeze Index G-55). v1 has no in-payload search.

**No index on `event_type` alone.** The router-driven analysis of "which event types produce the most notifications" is not a hot path in v1; if it becomes one, `(workspace_id, event_type, created_at DESC)` is an easy Wave 4 addition.

**Reused frozen indexes.** None — `notifications` is a brand-new table.

- **Why (index count).** Matches Freeze Index §26.7's 8-index enumeration (I-1 through I-8 in the freeze table; I-9 added here for actor-filter completeness). Total: 8 indexes explicitly enumerated in the freeze index; this proposal ships 9 including the `notifications_actor_idx` supplementary. If Wave-1 scope tightening removes I-9, the actor-filter UI degrades to a scan; the trade-off is documented in §17 gap #10.
- **Freeze Index section:** §4.1, §12.2, §12.3, §14.1, §26.7.
- **Priority per row.** Enumerated above.
- **Blocks implementation?** Critical rows yes; others no.

---

## 7. Constraints

Three additive CHECK constraints, one composite FK, three non-composite FKs, one partial unique index (I-7 above, doubling as a dedup constraint). No frozen constraint modified.

### 7.1 `notifications_category_check`

- **Definition.** `CHECK (category IN ('assigned_to_me','mentions','project_activity','governance_state_change','deadlines','system'))`.
- **Why.** Enum stability. Adding a category is a rare re-freeze event per Freeze Index §6. Populated for every row at router INSERT time — no NULL-permissive form because `category` is NOT NULL with no default.
- **Freeze Index section:** §6, G-13.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 7.2 `notifications_priority_check`

- **Definition.** `CHECK (priority IN ('critical','high','medium','low','informational'))`.
- **Why.** Enum stability for the priority ladder (Freeze Index §7.1). Populated at INSERT with a default of `'medium'`.
- **Freeze Index section:** §7, G-14.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 7.3 `notifications_delivery_state_check`

- **Definition.** `CHECK (delivery_state IN ('pending','delivered','failed','suppressed'))`.
- **Why.** Enum stability. v1 uses only `'delivered'`; `'pending'`/`'failed'`/`'suppressed'` reserved for post-v1 async channels.
- **Freeze Index section:** §10.1.
- **Priority:** High.
- **Blocks implementation?** No (v1 could ship without this CHECK; adding it now prevents typos in the router body).

### 7.4 `notifications_channels_attempted_check`

- **Definition.** `CHECK (channels_attempted <@ ARRAY['in_app','email_payload','push_payload']::text[])`.
- **Why.** Bounded vocabulary for the channel array. `<@` is the "is contained by" operator — every element of the array must be one of the three enumerated values.
- **Freeze Index section:** §10.4, G-4.
- **Priority:** High.
- **Blocks implementation?** No.

### 7.5 `notifications_payload_size_check`

- **Definition.** `CHECK (octet_length(payload::text) <= 16384)`.
- **Why.** Enforce the 16 KB hard cap per Freeze Index G-39. Prevents runaway payload sizes from single-slice bugs. Soft target 4 KB enforced at router build time by minimalism (§10.4 base+rendering+email/push keys total typically < 2 KB).
- **Freeze Index section:** G-39.
- **Priority:** Medium.
- **Blocks implementation?** No (v1 works without; the CHECK prevents pathological cases).

### 7.6 Partial unique index doubling as dedup constraint

I-7 `notifications_dedup_uniq_idx UNIQUE (recipient_profile_id, source_event_id, notification_type) WHERE archived_at IS NULL` — see §6. Doubles as the dedup enforcement per Freeze Index G-7. The router's `INSERT ... ON CONFLICT DO NOTHING` clause targets this index.

- **Why.** Prevents multiple rules producing duplicate rows for the same (recipient, event, notification_type) triple. If a rule composition (e.g., request creator who is also a project lead) resolves the same recipient via two paths for the same source event, the second INSERT is silently skipped.
- **Why `WHERE archived_at IS NULL`.** Defensive scaffolding for Wave 4 replay workers that may re-emit events after archival cleanup (e.g., an async email-delivery worker retry, or a router-error replay path landing with `notification_router_errors`). In v1 no replay path exists that could produce a duplicate `source_event_id` write, so the predicate is unreachable in v1 traffic. It is included now to lock the dedup contract shape before Wave 4 delivery workers ship, so those workers can bind to a fixed index definition without a rework.
- **Freeze Index section:** §9.7, G-7, §26.7.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 7.7 Foreign key summary

Four FKs:

- **FK-1** `notifications.recipient_profile_id → profiles(id) ON DELETE SET NULL`. Non-composite (profiles are workspace-transcendent). Priority Critical.
- **FK-2** `notifications.(project_id, workspace_id) → projects(id, workspace_id) ON DELETE CASCADE` when `project_id IS NOT NULL`. Composite (reuses APP 003 project composite anchor unique per SCHEMA_V1_LOCK). Priority Critical.
- **FK-3** `notifications.source_event_id → activity_events(id) ON DELETE CASCADE`. Non-composite (frozen `activity_events` has only PK on `(id)`; verified against `supabase/migrations/20260729235959_activity_events.sql` L75). Priority Critical.
- **FK-4** `notifications.actor_profile_id → profiles(id) ON DELETE SET NULL`. Non-composite. Priority High.

No FK on `subject_id` (mirrors the frozen `activity_events.subject_id` non-FK posture per DATABASE_SCHEMA.md §3.25 note L805).

No UNIQUE constraint at table level. Dedup is enforced by the partial unique index I-7.

No frozen constraint modified.

---

## 8. RPC surface — narrative overview

APP 010 introduces 14 new RPCs, split into two groups:

1. **Read RPCs (6 new).** Every read RPC is `SECURITY DEFINER`, `SET search_path = ''`, `REVOKE`d from `public`/`anon`/`authenticated`, `GRANT EXECUTE` to `authenticated, service_role`. Every read enforces `recipient_profile_id = auth.uid()` in-body (defense in depth over RLS) and re-checks `notification.view` via `lign_has_capability(project_id, workspace_id, 'notification.view')` for the resolved project scope. Returns `jsonb` (single-row detail, badge counts, hydrated rows) or `setof jsonb` (paginated lists).

2. **Write RPCs (8 new).** Every write RPC is `SECURITY DEFINER`, `SET search_path = ''`, gates on `notification.manage`, enforces `recipient_profile_id = auth.uid()` in-body, sets the `lign.allow_notification_rpc_write` GUC transaction-local for the duration of its UPDATE, and returns a small `jsonb` summary (rows affected + resulting flags). No write RPC touches any workflow-side table.

**Frozen RPC extension posture.** APP 010 performs exactly one `CREATE OR REPLACE` of the frozen `lign_has_capability(uuid, uuid, text)` function. This replacement is strictly additive: the signature is preserved; every existing capability key and role mapping remains byte-identical; only the new `notification.*` capability keys (2 wired + 6 reserved) are appended. No existing capability changes. No overload is introduced. No named-argument ambiguity arises. Per checklist C-2, byte-identical role-map preservation is guaranteed. Beyond this single additive reissue, there is no `CREATE OR REPLACE` on any other frozen function and no single-function default-tail-param extension. APP 008 / APP 009's Option-A discipline is cited only for context — APP 010 does not exercise it. Every RPC below is a brand-new `CREATE FUNCTION` on a brand-new namespace (`list_notifications_inbox`, `get_notification_badge_count`, `mark_notification_read`, etc.).

**No dashboard-hydration join in the client.** Following the "prefer additive read RPCs over client joins" discipline from APP 009 §8, `list_notifications_inbox` returns rows already hydrated with the rendering-ready `payload` (materialized at INSERT time). The client does not join `notifications + activity_events + profiles` — every field the Inbox card needs is on the notification row itself (denormalized from the source event at router time).

**GUC discipline for RPC-only writes.** Mirroring the frozen `enforce_release_status_via_rpc` pattern (APP 009 AUTH 008 L38 with `lign.allow_release_status_write`), APP 010's write RPCs set a transaction-local GUC `lign.allow_notification_rpc_write = 'true'` before their UPDATE and reset it afterward. The `enforce_notification_rpc_only_writes` BEFORE UPDATE trigger checks the GUC and rejects any UPDATE where the GUC is not set — blocking direct UPDATE from user code even if a caller had `authenticated` role and passed RLS.

**Server-authoritative results.** Every write RPC returns `jsonb` with `{success: bool, rows_affected: int, notification_id: uuid?, resulting_state: {read_at, dismissed_at, archived_at}}` so the client can patch its cache without a re-fetch. This mirrors the APP 009 `finalize_release` return posture.

---

## 9. Trigger model

Four additive triggers. The single most important is `enforce_notification_router_bridge` — the router bridge. The other three are defense-in-depth on `notifications`.

### 9.1 `enforce_notification_router_bridge` — AFTER INSERT on `activity_events`

- **Timing / scope.** `CREATE TRIGGER enforce_notification_router_bridge AFTER INSERT ON public.activity_events FOR EACH ROW EXECUTE FUNCTION public.resolve_notification_router_targets()`.
- **Function.** `resolve_notification_router_targets() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''`.
- **Purpose.** Materialize per-recipient `notifications` rows for the just-INSERTed `activity_events` row (NEW), applying the routing table (Freeze Index §8.1), recipient resolution (§9), dedup (§9.7), and self-exclusion (§9.8) rules.
- **Body outline** (no SQL):
  1. `IF NEW.event_type IS NULL THEN RETURN NEW; END IF;` — defensive early return.
  1a. `IF NEW.event_type LIKE 'notification.%' THEN RETURN NEW; END IF;` — **explicit `notification.*` recursion guard (primary loop-guard mechanism).** Prevents the router from processing any event in its own reserved namespace, including future emitters that a subsequent wave may wire against the RESERVED event names (§12.2). Runs before the routing-table lookup so the guard is unavoidable. The routing-table-absence argument (no `notification.*` entry in the routing table) is the secondary defense.
  2. Wrap the entire body in `BEGIN … EXCEPTION WHEN OTHERS THEN RAISE WARNING …; RETURN NEW; END;`. **Inviolable.**
  3. Look up the routing table entry for `NEW.event_type` (and `NEW.subject_kind` if polymorphic). If no entry (feed-only event per EVENT_MODEL.md §7.3), `RETURN NEW` immediately (silent skip per Freeze Index G-51).
  4. Compute the recipient set per §9 rules — direct-actor, owner, requester, project-broadcast, project-leads, invitee-by-email. Union results.
  5. Apply self-exclusion: `WHERE recipient_profile_id != NEW.actor_profile_id` (skipped if `NEW.actor_profile_id IS NULL`, i.e., `actor_kind='system'`).
  6. For each resolved recipient, materialize `payload` per §10.4 (base + rendering + email/push if applicable per routing table entry).
  7. `INSERT INTO public.notifications (...) VALUES (...) ON CONFLICT (recipient_profile_id, source_event_id, notification_type) WHERE archived_at IS NULL DO NOTHING` — one per recipient.
  8. `RETURN NEW;`.
- **Isolation.** `SECURITY DEFINER` because the router reads `workspace_members`, `project_participants`, `profiles`, `review_participants`, `approval_request_approvers`, `annotations`, `changes`, `reviews`, `approval_requests`, `invitations` on behalf of the caller who may not have direct SELECT on all of them.
- **`SET search_path = ''`.** Every table reference in the function body is fully qualified (`public.workspace_members`, `public.project_participants`, etc.). Prevents search-path injection.
- **REVOKE / no GRANT.** `REVOKE ALL ON FUNCTION public.resolve_notification_router_targets() FROM public, anon, authenticated`. No explicit `GRANT` — the function is invoked exclusively by the trigger dispatcher.
- **Attributes.** `LANGUAGE plpgsql`, `SECURITY DEFINER`, `SET search_path = ''`, `VOLATILE`, `RETURNS trigger`. Marked `STABLE` is not appropriate because the function has side effects (`INSERT`).
- **Exception-safety (inviolable — repeated).** The body's `EXCEPTION WHEN OTHERS` handler catches every SQLSTATE and never re-raises. It emits `RAISE WARNING 'notification router failed for event % (type %): %', NEW.id, NEW.event_type, SQLERRM;`. This is the single most important design constraint. If the router raises unhandled, a bug in APP 010 could roll back a legitimate workflow transaction. The Freeze Index G-2 caveat codifies "workflow correctness > notification completeness"; the missed notification is a silent loss (visible only in Postgres logs), which is acceptable because the recipient still sees the underlying event via source-slice UI, source-slice badges, activity feed, etc.
- **Ordering constraint.** The trigger fires AFTER INSERT alongside any other AFTER INSERT triggers already installed on `activity_events` (the only frozen triggers on this table are `activity_events_no_update` and `activity_events_no_delete`, which share the `enforce_activity_events_append_only` function and fire BEFORE UPDATE / DELETE respectively — not AFTER INSERT — so no ordering conflict in v1). Per Freeze Index §20.5, the router must run after any audit-derivation triggers that write additional `subject_snapshot` fields; there are none in v1.
- **Behavior on unknown `event_type`.** Silent return (Freeze Index §20.6). Rationale: reserved event names (e.g., `review.deadline_approached`) may land in `activity_events` before APP 010 adds their routing rule; the router should not spam warnings for legitimate forward-compatibility.
- **Behavior on `notification.*` events in `activity_events`.** Silent return per Freeze Index G-16, G-22 (loop guard). The router never processes its own outputs. **Primary defense:** the explicit step-1a guard `IF NEW.event_type LIKE 'notification.%' THEN RETURN NEW; END IF;` fires before the routing-table lookup and short-circuits any event in the `notification.*` reserved namespace. **Secondary defense:** the routing table (Freeze Index §8.1) has no `notification.*` entry, so even if the primary guard were removed the router would fall through to the `RETURN NEW` in step 3 as an unknown event type.
- **Freeze Index section:** §1.2, §2.1, §2.3, §8, §9, §20, §26.8, G-2, G-16, G-22.
- **Priority:** Critical.
- **Blocks implementation?** Yes (no notifications materialize without the router).

### 9.2 `enforce_notification_immutable_fields` — BEFORE UPDATE on `notifications`

- **Timing / scope.** `CREATE TRIGGER enforce_notification_immutable_fields BEFORE UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.enforce_notification_immutable_fields()`.
- **Purpose.** Reject any UPDATE that changes a column outside the mutable-flag set (`read_at`, `dismissed_at`, `archived_at`, `updated_at`).
- **Behavior.** Raises `23514` (check_violation) with message `'notification column % is immutable after INSERT'` if any of the following are `IS DISTINCT FROM` between OLD and NEW: `id`, `workspace_id`, `project_id`, `recipient_profile_id`, `source_event_id`, `event_type`, `notification_type`, `category`, `priority`, `channels_attempted`, `subject_kind`, `subject_id`, `subject_label`, `actor_profile_id`, `payload`, `created_at`. `delivery_state` is also immutable to end users (server-managed), but a future async delivery worker (Wave 4) will need to update it via `service_role`; in v1 the trigger enforces its immutability too.
- **Row-local only.** Inspects OLD/NEW columns of the trigger's own row. No cross-table read; **NOT** `SECURITY DEFINER` (per APP 009 F-6 precedent).
- **Attributes.** `LANGUAGE plpgsql`, `SET search_path = ''`, not `SECURITY DEFINER`.
- **REVOKE / no GRANT.** `REVOKE ALL ON FUNCTION public.enforce_notification_immutable_fields() FROM public, anon, authenticated`. No `GRANT`.
- **Freeze Index section:** §4.2, §26.8.
- **Priority:** Critical.
- **Blocks implementation?** Yes (payload immutability is a public invariant per G-57).

### 9.3 `enforce_notification_rpc_only_writes` — BEFORE UPDATE on `notifications`

- **Timing / scope.** `CREATE TRIGGER enforce_notification_rpc_only_writes BEFORE UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.enforce_notification_rpc_only_writes()`.
- **Purpose.** Block direct UPDATE from user code. Only the 8 write RPCs may write (they set the `lign.allow_notification_rpc_write` GUC transaction-local before their UPDATE and reset it after).
- **Behavior.** Reads `current_setting('lign.allow_notification_rpc_write', true)`; raises `42501` (insufficient_privilege) with message `'notifications may only be updated via mark_/dismiss_/archive_ RPCs'` if the GUC is not `'true'`.
- **Row-local + GUC only.** No cross-table read; **NOT** `SECURITY DEFINER`.
- **Attributes.** `LANGUAGE plpgsql`, `SET search_path = ''`.
- **REVOKE / no GRANT.** `REVOKE ALL ON FUNCTION public.enforce_notification_rpc_only_writes() FROM public, anon, authenticated`. No `GRANT`.
- **Interaction with §9.2.** Fires in the same BEFORE UPDATE dispatcher; trigger firing order is alphabetical by name in Postgres, so `enforce_notification_immutable_fields` fires first, then `enforce_notification_rpc_only_writes`, then `notifications_set_updated_at`. The RPC-gate trigger and the immutability trigger are complementary: even if a caller sets the GUC (e.g., by hacking a SECURITY DEFINER function's search path), the immutability trigger still catches every non-flag change.
- **Freeze Index section:** §4.2, §26.8.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 9.4 `notifications_set_updated_at` — BEFORE UPDATE on `notifications`

- **Timing / scope.** `CREATE TRIGGER notifications_set_updated_at BEFORE UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()`.
- **Purpose.** Standard timestamp maintenance. Sets `NEW.updated_at := now()`.
- **Function.** Reuses the frozen `public.set_updated_at()` function (declared by APP 001 foundation; reused across every workflow slice — `releases_set_updated_at`, `release_items_set_updated_at`, `requirements_set_updated_at`, etc.). No new function declared.
- **Freeze Index section:** §4.2, §26.8.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 9.5 Chain-immutability trigger — N/A

Notifications have no chain columns (`root_release_id` / `superseded_by_release_id` are APP 009 concepts). No chain-init discipline applies. The APP 006 T-CRIT-1 / APP 009 §9.1 chain-immutability trigger pattern is cited here only to state that it is not exercised by APP 010.

### 9.6 Frozen triggers preserved unchanged

Explicitly cited:

- The frozen `activity_events_no_update` and `activity_events_no_delete` triggers (Migration 009), which share the `enforce_activity_events_append_only` function — block UPDATE/DELETE on `activity_events`. APP 010's AFTER INSERT trigger coexists without conflict (AFTER INSERT is orthogonal to UPDATE/DELETE denial). Both triggers and the shared function preserved byte-identically.
- Every RLS policy on `activity_events` (AUTH 009 `supabase/migrations/20260802000000_auth_009_activity_events_rls.sql`) — preserved byte-identically.
- Every APP 001–009 slice trigger — preserved byte-identically. APP 010 declares no new triggers on any frozen table other than the AFTER INSERT bridge on `activity_events`.

### 9.7 Router failure posture (repeated from §2.8)

If the router body raises unhandled:
- Development: the RAISE WARNING is visible in Postgres logs / Supabase Studio.
- Production: same. The workflow transaction commits normally. The missed notification is a silent loss (recoverable via source-slice UI, badges, feed).
- Future: `notification_router_errors` RESERVED table lands in Wave 4; the EXCEPTION handler INSERTs a diagnostic row there and continues.

This defers the "at-least-once delivery" invariant a stricter design would provide. Rationale codified in Freeze Index G-2 caveat: workflow correctness > notification completeness.

---

## 10. RLS

### 10.1 `notifications` — new policies

- **RLS enabled.** `ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY`.
- **`notifications_select` — SELECT policy.**
  - Definition:
    ```
    (recipient_profile_id = (select auth.uid()))
      AND public.lign_has_capability(project_id, workspace_id, 'notification.view')
      AND (
        project_id IS NULL
        OR public.lign_project_role(project_id) IS NOT NULL
        OR public.lign_is_workspace_admin(workspace_id)
      )
    ```
  - The first predicate enforces per-user scope (a recipient sees only their own rows). The second enforces the capability (`notification.view` is granted to every authenticated role in v1, so this is effectively a permit-all — but it stays in the policy for the future `notification.view_any` compliance path). The third is belt-and-braces subject-access enforcement: even if the recipient legitimately received a notification at time T, a subsequent role change that removes their project access should filter the row (per Freeze Index §21.1 and EVENT_MODEL.md §7.7 "notifications never bypass RLS").
- **`notifications_insert` — INSERT policy.**
  - Definition: `false`. No client-side INSERT is ever legal. The router trigger runs as SECURITY DEFINER and bypasses RLS.
- **`notifications_update` — UPDATE policy.**
  - Definition: `recipient_profile_id = (select auth.uid())`.
  - Further gated by `enforce_notification_rpc_only_writes` trigger requiring the `lign.allow_notification_rpc_write` GUC (only settable inside the 8 write RPCs).
  - Deliberately loose at RLS layer (analogous to the frozen `releases_update` posture per APP 009 §7.1 — RLS permits UPDATE granted the caller has ownership, and a trigger is the authoritative gate).
- **`notifications_delete` — DELETE policy.**
  - Definition: `false`. No user-facing delete. Retention pruning (deferred) uses `service_role`.

### 10.2 `activity_events` RLS unchanged

Explicitly stated: `AUTH 009` RLS policies on `activity_events` are preserved byte-identically. APP 010 does not modify, drop, or add any policy on the audit log.

### 10.3 Other frozen tables — RLS unchanged

Explicitly stated: no APP 001–009 table's RLS is touched. `workspace_members`, `project_participants`, `profiles`, `reviews`, `review_participants`, `approval_requests`, `approval_request_approvers`, `releases`, `release_items`, `requirements`, `comments`, `annotations`, `changes`, `invitations`, `stakeholders`, `workspaces` — every policy preserved.

### 10.4 The "notifications never bypass RLS" invariant

Codified in Freeze Index §21.1 and inherited from EVENT_MODEL.md §7.7. Concretely:

- A notification row's SELECT policy requires that the recipient still has access to the source subject (via the third predicate in §10.1).
- If a recipient's role changes between event time and read time (e.g., they were removed from a project), the notification row filters out at read time — the payload does not leak project-scoped preview text.
- This mirrors the frozen `activity_events` SELECT policy per AUTH 009 which enforces the same at the audit-log level.

### 10.5 No new RLS surface beyond `notifications`

Explicitly stated: zero RLS additions on frozen tables. Zero RLS additions on reserved tables (they have no DDL in v1).

---

## 11. Capability model

### 11.1 Wired capabilities (v1)

Two new keys, both granted to every authenticated role (workspace roles + project roles + reviewer + stakeholder) because notifications are personal.

| Capability | Purpose | `owner` | `admin` | `lead` | `contributor` | `reviewer` | `approver` | `observer` | `stakeholder` |
|---|---|---|---|---|---|---|---|---|---|
| `notification.view` | Read own notifications; open Inbox; see bell badge | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `notification.manage` | Mark read/unread, dismiss, archive own notifications | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

- **Why implicit for every user.** Every authenticated user has a right to see their own inbox. Recipient enforcement is via `recipient_profile_id = auth.uid()` at RLS + in-body check in every RPC. No admin can read another user's inbox in v1.
- **Why two keys.** Per Freeze Index G-24: preserves future flexibility. A future read-only mode (e.g., compliance observation) could grant `.view` without `.manage`. In v1 both are uniformly granted.
- **Freeze Index section:** §19.1, §19.4, G-24.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 11.2 RESERVED capabilities (name-locked; zero role grants)

Six keys under the `notification.*` prefix. Registered in PERMISSIONS.md by string only. `lign_has_capability(project_id, workspace_id, '<reserved key>')` returns `false` for every caller in v1.

| # | Capability | Purpose (future) | Wave |
|---|---|---|---|
| C-R1 | `notification.view_any` | Compliance/support reading of another user's inbox (with audit trail) — reserved for future compliance slice (Freeze Index §19.3, G-43). | Future |
| C-R2 | `notification.announce` | Manually create a broadcast notification (admin announcement) — reserved for future admin slice (§19.3). | Future |
| C-R3 | `notification.ai_prioritize` | AI seam: re-order the recipient's inbox by learned priority — reserved (§24.1, G-27). | Future |
| C-R4 | `notification.ai_summarize` | AI seam: auto-generate daily/weekly summary — reserved (§24.1, G-27). | Future |
| C-R5 | `notification.ai_digest` | AI seam: consume many notifications, emit one digest — reserved (§24.1, G-27). | Future |
| C-R6 | `notification.preference` | Manage own notification preferences — reserved for future preferences table (§4.4). | Future |

**Extend-before-duplicate rule (PERMISSIONS.md).** Every reserved key uses the `notification.*` prefix. `notification.view_any` is deliberately distinct from `notification.view` because it carries a stronger authorization surface (reading another user's inbox is a compliance-privileged action requiring audit trail).

- **Why (reserved-only in v1).** Locks the vocabulary before AI / compliance / preference slices start. Prevents rename churn.
- **Freeze Index section:** §19.3, §24.1, §26.5, G-24, G-27, G-43.
- **Priority:** Future (all).
- **Blocks implementation?** No.

### 11.3 Extension of `lign_has_capability`

APP 010 performs exactly one `CREATE OR REPLACE` of the frozen `lign_has_capability(uuid, uuid, text)` function. This replacement is strictly additive: the signature is preserved; every existing capability key and role mapping remains byte-identical; only the new `notification.*` capability keys (2 wired + 6 reserved) are appended. No existing capability changes. No overload is introduced. No named-argument ambiguity arises. Per checklist C-2, byte-identical role-map preservation is guaranteed.

Specifically:

- For `notification.view` and `notification.manage`: returns `true` for every authenticated user (implicit grant across all roles).
- For all 6 RESERVED keys (`notification.view_any`, `notification.announce`, `notification.ai_prioritize`, `notification.ai_summarize`, `notification.ai_digest`, `notification.preference`): returns `false` for every caller in v1.
- No existing role-map row is modified. No existing capability key's return value changes. Every frozen key's per-role branch (`lead` / `contributor` / `reviewer` / `approver` / `observer` / admin-override) remains byte-identical to `supabase/migrations/20260730120000_auth_001_helpers_bootstrap.sql` L229–314.
- Delivered via a single `CREATE OR REPLACE FUNCTION public.lign_has_capability(...)`. No overload. Named-argument callers of the frozen parameters are unaffected.

### 11.4 Capability enforcement points

- `list_notifications_inbox`, `list_notifications_unread`, `get_notification`, `get_notification_badge_count`, `get_notification_center`, `list_notifications_by_source`: require `notification.view`; further filtered by `recipient_profile_id = auth.uid()`.
- `mark_notification_read`, `mark_notification_unread`, `mark_all_notifications_read`, `mark_notifications_read_bulk`, `dismiss_notification`, `dismiss_notifications_bulk`, `archive_notification`, `archive_notifications_bulk`: require `notification.manage`; further filtered by `recipient_profile_id = auth.uid()`.
- Inbox route (`/workspace/:ws_id/inbox`): frontend route guard checks `notification.view` before mounting.
- Notification Center popover: mount-time check on `notification.view`.

### 11.5 Membership-class transparency

Per PERMISSIONS.md §1: membership class (WorkspaceMember vs Stakeholder) does not gate any capability. A stakeholder holding `notification.view` (which all authenticated users do) sees their own notifications for events on projects they participate in — same as a workspace member.

### 11.6 No `notification.send` capability

Explicitly stated: there is no client-invokable "send a notification" affordance. The router is system-triggered from `activity_events` INSERT — no user directly creates a notification row. A future "manual system announcement" feature would use `notification.announce` (RESERVED, C-R2).

---

## 12. Event model

### 12.1 Zero new emitted events in v1

APP 010 emits no events. The read/dismissed/archived lifecycle is stored in the row (three `timestamptz` flags per §5). Emitting `notification.read` back into `activity_events` would:

- Create feedback into the very audit spine APP 010 consumes.
- Violate G-16 (no notification-of-notification).
- Approximately double `activity_events` volume for the negligible benefit of an "I read this" audit trail that would not be actionable to any consumer.
- Trigger the router again (self-loop guard notwithstanding — G-22 makes this a no-op, but the write is still wasted).

Freeze Index §12 codifies this: v1 emits no events; the row's flags are sufficient.

### 12.2 RESERVED event names (name-locked by this proposal; no emitter in APP 010 v1)

Three event names in the `notification.*` namespace. Registered in `EVENT_MODEL.md` in the Wave 1 doc-diff alongside Migration A (mirroring APP 009 F-5 discipline: vocabulary lock is real from Wave 1).

| # | Event | Purpose (future) | Wave | Registration status |
|---|---|---|---|---|
| E-R1 | `notification.ai_prioritized` | Fires when the AI re-orders the caller's inbox (future AI slice; see Freeze Index §24.4). | Future | New reservation added by Wave 1 doc-diff. |
| E-R2 | `notification.ai_summarized` | Fires when an AI-generated summary is materialized (future). | Future | New reservation added by Wave 1 doc-diff. |
| E-R3 | `notification.digest_sent` | Fires when a digest is delivered (future cron/digest slice). | Future | New reservation added by Wave 1 doc-diff. |

**Vocabulary lock is real from Wave 1.** The EVENT_MODEL.md doc-diff registering all three names lands in Wave 1 alongside Migration A, so downstream waves and slices can bind to fixed strings immediately. No emitter, no fan-out entry, no payload shape enforcement is added in APP 010 — only the name lock.

**Past-tense discipline.** All three names use past-tense verbs: `prioritized`, `summarized`, `sent`. Every reserved name conforms.

**Loop-guard.** Per Freeze Index G-16, G-22: the router does not process `notification.*` events even if they land in `activity_events`. This is defense-in-depth against a future AI slice accidentally causing recursion.

### 12.3 No renaming or redefinition of any frozen workflow event

Explicitly stated: APP 010 does not touch EVENT_MODEL.md §4.1–§4.14 rows. No frozen event name is renamed. No frozen `Notify` cell is changed. No frozen `PDH`/`WA`/`Sec` routing decision is altered. No frozen `Actor`/`Subject`/`Project`/`Snapshot` column is redefined.

### 12.4 Events APP 010 consumes (enumeration)

APP 010's router consumes every P0 event whose EVENT_MODEL.md `Notify` cell is non-empty. Enumerated per Freeze Index §8.1 routing table:

- **Review (4):** `review.opened`, `review.completed`, `review.cancelled`, `review.reviewer_responded` (EVENT_MODEL.md §4.7).
- **Approval (6):** `approval.requested`, `approval.responded`, `approval.approved`, `approval.rejected`, `approval.expired`, `approval.cancelled` (§4.11).
- **Comment (1):** `comment.mentioned` (§4.8).
- **Annotation (1):** `annotation.resolved` (§4.8).
- **Change (4):** `change.created`, `change.accepted`, `change.rejected`, `change.withdrawn` (§4.9).
- **Release (2):** `release.finalized`, `release.withdrawn` (§4.12).
- **Asset (2):** `asset.archived`, `asset.unarchived` (§4.4).
- **Project (5):** `project.archived`, `project.unarchived`, `project.participant.added`, `project.participant.role_changed`, `project.participant.removed` (§4.2).
- **Workspace / Stakeholder / Invitation (9):** `workspace.member.invited`, `workspace.member.activated`, `workspace.member.role_changed`, `workspace.member.suspended`, `workspace.member.removed`, `stakeholder.invited`, `stakeholder.claimed`, `stakeholder.revoked`, `invitation.expired` (§4.1).
- **Requirement (0):** all four `requirement.*` events are feed-only in MVP per EVENT_MODEL.md §4.14 and APP 008 certification. APP 010 v1 consumes zero requirement events (RESERVED consumers per Freeze Index §5.6).

Total: approximately 34 wired consumer paths (4 review + 6 approval + 1 comment + 1 annotation + 4 change + 2 release + 2 asset + 5 project + 9 workspace/stakeholder/invitation + 0 requirement = 34). Every non-consumed P0 event is feed-only per Freeze Index §5.8 and produces zero notifications.

### 12.5 No additive payload keys on frozen events

APP 010 does not add any payload key to any frozen event's `subject_snapshot`. Every routing decision runs on keys already frozen by the emitting slice. If a routing rule needs a key not yet in a frozen event's snapshot, the emitting slice's freeze index gains that key first; APP 010's router extension follows in a coordinated additive change (Freeze Index §20.7).

### 12.6 Payload materialization ≠ event emission

The router materializes a rich `payload jsonb` into each `notifications` row at INSERT time (§10.4). This is NOT event emission — the payload is per-recipient staging, not a broadcast to the audit spine. `activity_events` is never touched by APP 010.

---

## 13. Query architecture

### 13.1 `qk` namespace additions (mirrored from Freeze Index §17.1)

APP 010 introduces the following TanStack Query key builders (defined in `src/features/notifications/keys.ts`):

| Key builder | Signature | Backing RPC |
|---|---|---|
| `qk.notification(id)` | `['notification', id]` | `get_notification` |
| `qk.notificationsList(wsId, filters)` | `['notification','list', wsId, filters]` | `list_notifications_inbox` |
| `qk.notificationsUnread(wsId)` | `['notification','unread', wsId]` | `list_notifications_unread` |
| `qk.notificationsInbox(wsId, tab, filters, cursor)` | `['notification','inbox', wsId, tab, filters, cursor]` | `list_notifications_inbox` |
| `qk.notificationCenter(wsId)` | `['notification','center', wsId]` | `get_notification_center` |
| `qk.notificationBadgeCount(wsId)` | `['notification','badge', wsId]` | `get_notification_badge_count` |
| `qk.notificationsForSubject(subjectKind, subjectId)` | `['notification','subject', kind, id]` | `list_notifications_by_source` |

All keys are namespace-safe against APP 001–009 (whose namespaces are `workspace`, `project`, `asset`, `version`, `file`, `comment`, `annotation`, `review`, `approval`, `requirement`, `release`, `deep`, `bookmark`, `savedView`).

### 13.2 Cursor pagination

Cursor payload (per Freeze Index §17.2):

```json
{ "created_at": "2026-08-05T10:23:00Z", "id": "01a0e5a2-..." }
```

Base64url-encoded; opaque to the client. Every set-returning read RPC uses `(created_at DESC, id DESC)` as the sort tuple. Deterministic under simultaneous INSERTs (created_at ties are broken by `id`).

### 13.3 Stale-time posture (per Freeze Index §17.3)

- `qk.notificationBadgeCount` — `staleTime: 30_000`, `refetchInterval: 60_000` (polling fallback per Freeze Index §25.4).
- `qk.notificationsUnread` / `qk.notificationCenter` — `staleTime: 30_000`, `refetchInterval: 60_000`.
- `qk.notificationsInbox` — `staleTime: 60_000`, no `refetchInterval` (screen-scoped; user-initiated refresh).
- `qk.notification(id)` — `staleTime: 5 * 60_000` (individual notifications are effectively immutable after read; only recipient-axis flags change).

### 13.4 Invalidation matrix

| Mutation | Invalidated keys |
|---|---|
| `mark_notification_read(id)` | `notification(id)`, `notificationsUnread(wsId)`, `notificationsInbox(wsId,*)`, `notificationCenter(wsId)`, `notificationBadgeCount(wsId)` |
| `mark_notification_unread(id)` | Same as above |
| `mark_all_notifications_read(wsId)` | All `qk.notification*` for the workspace |
| `mark_notifications_read_bulk(ids)` | Same as read (per-id patch + bulk badge invalidation) |
| `dismiss_notification(id)` | Same as mark-read |
| `dismiss_notifications_bulk(ids)` | Same |
| `archive_notification(id)` | Same |
| `archive_notifications_bulk(ids)` | Same |
| Polling tick (60s) | `notificationBadgeCount(wsId)` |
| Window `focus` event | `notificationBadgeCount(wsId)` (cheap round-trip) |
| Any workflow mutation invoking `invalidateNotificationSurfaces(wsId)` helper | `notificationBadgeCount(wsId)`, `notificationsUnread(wsId)`, `notificationCenter(wsId)` |

Per Freeze Index §18.1: cross-slice mutation → notification badge/list invalidation via a shared `invalidateNotificationSurfaces(wsId)` helper exported from `src/features/notifications/invalidation.ts`.

### 13.5 Prefetching

- On Notification Center popover open: prefetch `notificationsInbox(wsId, 'unread', {}, null)` so "View all in Inbox" is instant.
- On Inbox mount: prefetch second-page cursor if `first_page.has_more === true`.

### 13.6 Optimistic updates

Per Freeze Index §17.6 and G-30:

- `mark_notification_read`, `mark_notification_unread`, `dismiss_notification`, `archive_notification` — optimistic (invalidation follows server confirmation).
- `mark_all_notifications_read`, `mark_notifications_read_bulk`, `dismiss_notifications_bulk`, `archive_notifications_bulk` — non-optimistic (bulk ops wait for server truth).

---

## 14. Dashboard support

### 14.1 Inbox dashboard

Backed by `list_notifications_inbox` (§15.1). Returns hydrated notification rows (with rendering-ready payload jsonb) plus facet counts (unread count, per-category counts). Cursor pagination on `(created_at DESC, id DESC)`. Every filter param maps to a WHERE clause on the row's indexed columns (I-1 through I-9 cover the primary filter paths).

Filter param → index mapping:

| Filter param | Index used |
|---|---|
| `tab=unread` | I-1 (unread-by-recipient partial) |
| `tab=all` | I-2 (inbox-all partial) |
| `tab=mentions` / `tab=assigned` / `tab=governance` | I-3 (category partial) |
| `tab=archived` | I-5 (archived partial) |
| `p_category_filter text[]` | I-3 (category partial) |
| `p_priority_filter text[]` | I-4 (priority partial) |
| `p_source_filter text[]` (event_type prefix) | Sequential scan within `recipient_profile_id` partition (acceptable for MVP; a `(recipient_profile_id, event_type)` index is Wave 4 if scan cost becomes measurable) |
| `p_date_from` / `p_date_to` | I-2 (leading `created_at` partial) |
| `p_project_id` | I-6 (project partial) |
| `p_actor_id` | I-9 (actor partial) |

### 14.2 Bell badge dashboard

Backed by `get_notification_badge_count` (§15.3). Returns a small `jsonb` object:

```json
{
  "total_unread": 12,
  "by_category": {
    "assigned_to_me": 3,
    "mentions": 1,
    "project_activity": 5,
    "governance_state_change": 3,
    "deadlines": 0,
    "system": 0
  },
  "has_critical": false
}
```

Powered by index I-1 (`notifications_unread_by_recipient_idx`). Single COUNT scan; O(unread) rows.

### 14.3 Notification Center popover dashboard

Backed by `get_notification_center` (§15.4). Returns the top 15 unread notifications for the current workspace, with hydrated payload, plus a `has_more boolean` field. Powered by I-2.

### 14.4 Detail-screen recent-activity panels

Backed by `list_notifications_by_source` (§15.5). Reverse-lookup: "give me every notification citing this subject." Rare-use RPC; primarily consumed by future cross-slice UX (not v1 UI). Powered by I-8.

### 14.5 NavRail per-slice badge integration

APP 010's `get_notification_badge_count` is the sole source for the new "Inbox" NavRail item. Every existing NavRail item's badge continues to use the frozen source-slice RPC (`get_approval_inbox_count`, `get_review_inbox_count`, `get_requirements_inbox_count`, `get_release_inbox_count` — per Freeze Index §14.2). APP 010 never overrides these — G-6.

---

## 15. Read RPCs

Six new read RPCs. All are `SECURITY DEFINER`, `SET search_path = ''`, `REVOKE`d from `public`/`anon`/`authenticated`, `GRANT EXECUTE` to `authenticated, service_role`. All gate on `notification.view` via `lign_has_capability(project_id, workspace_id, 'notification.view')` and enforce `recipient_profile_id = auth.uid()` in-body (defense in depth over RLS).

### 15.1 `list_notifications_inbox(p_ws_id uuid, p_tab text, p_category_filter text[], p_priority_filter text[], p_source_filter text[], p_date_from timestamptz, p_date_to timestamptz, p_project_id uuid, p_actor_id uuid, p_cursor_created_at timestamptz, p_cursor_id uuid, p_limit int) → jsonb`

- **Purpose.** Primary Inbox read. Returns paginated hydrated notification rows for the caller in the workspace, filtered by tab + filter chips + cursor.
- **Return shape.** `jsonb`:
  ```
  {
    rows: [
      {
        id, workspace_id, project_id, recipient_profile_id, source_event_id,
        event_type, notification_type, category, priority,
        subject_kind, subject_id, subject_label,
        actor_profile_id,
        payload, read_at, dismissed_at, archived_at, created_at
      },
      ...
    ],
    next_cursor: { created_at, id } | null,
    has_more: boolean,
    facets: {
      total_count: int,
      unread_count: int,
      by_category: { assigned_to_me, mentions, project_activity, governance_state_change, deadlines, system },
      by_priority: { critical, high, medium, low, informational }
    }
  }
  ```
  **Actor display name.** Not a top-level row field. Clients read the actor's display name from `row.payload.actor_display_name` (the canonical position materialized by the router at INSERT time per §5.16 and §10.4). Per F-5 normalization, `payload.actor_display_name` is the sole authoritative location; no denormalized top-level copy is returned.
- **Filter predicate (composed).**
  - `recipient_profile_id = auth.uid()` (always).
  - `workspace_id = p_ws_id` (always).
  - Tab predicate per Freeze Index §12.2 (see §14.1 mapping).
  - Category `IN (unnest(p_category_filter))` when non-null.
  - Priority `IN (unnest(p_priority_filter))` when non-null.
  - Source module = `split_part(event_type, '.', 1) IN (unnest(p_source_filter))` when non-null.
  - `created_at >= p_date_from` when non-null.
  - `created_at <= p_date_to` when non-null.
  - `project_id = p_project_id` when non-null.
  - `actor_profile_id = p_actor_id` when non-null.
  - Cursor: `(created_at, id) < (p_cursor_created_at, p_cursor_id)` when non-null.
- **Capability check.** `notification.view` (implicit-pass for every authenticated user in v1; retained for future compliance path).
- **Freeze Index section:** §12, §17, §26.3.
- **Priority:** Critical.
- **Blocks implementation?** Yes (Inbox screen cannot render without it).

### 15.2 `list_notifications_unread(p_ws_id uuid, p_limit int) → jsonb`

- **Purpose.** Convenience alias for Notification Center popover's default "Unread" sub-tab. Same shape as `list_notifications_inbox` with `p_tab = 'unread'` and no filters, but bounded to a smaller `p_limit` (default 15).
- **Return shape.** Same as §15.1.
- **Freeze Index section:** §13, §17, §26.3.
- **Priority:** High.
- **Blocks implementation?** No (Notification Center can call `list_notifications_inbox` directly; convenience alias only).

### 15.3 `get_notification(p_notification_id uuid) → jsonb`

- **Purpose.** Single-row read. Powers the `/deep/notification/:id` deep-link resolver and the `highlight=` URL param.
- **Return shape.** `jsonb` with every column from §5, including `payload` intact. Clients read the actor's display name from `payload.actor_display_name` (the canonical position materialized by the router at INSERT time per §5.16 and §10.4). Per F-5 normalization, `get_notification` does not denormalize `actor_display_name` to the top level; there is no top-level `actor_display_name` field on the return object.
- **Capability check.** `notification.view` + `recipient_profile_id = auth.uid()`. If the row does not exist or the caller is not the recipient, returns `NULL` (not a 404 — RLS filters it out, and the RPC returns `NULL` to avoid leaking existence).
- **Freeze Index section:** §15.2, §26.3.
- **Priority:** High.
- **Blocks implementation?** No (Inbox `highlight=` param can degrade to no-op if the read fails).

### 15.4 `get_notification_badge_count(p_ws_id uuid) → jsonb`

- **Purpose.** Bell badge count. Called on every workspace mount + every 60s poll tick + every window `focus` event.
- **Return shape.** `jsonb` (see §14.2):
  ```
  {
    total_unread: int,
    by_category: { assigned_to_me, mentions, project_activity, governance_state_change, deadlines, system },
    has_critical: boolean
  }
  ```
- **Filter predicate.** `recipient_profile_id = auth.uid() AND workspace_id = p_ws_id AND read_at IS NULL AND dismissed_at IS NULL AND archived_at IS NULL AND priority != 'informational'` (per Freeze Index §14.1).
- **Index.** I-1 (partial covering).
- **Capability check.** `notification.view`.
- **Freeze Index section:** §14.1, §26.3.
- **Priority:** Critical.
- **Blocks implementation?** Yes (bell badge cannot render).

### 15.5 `get_notification_center(p_ws_id uuid, p_limit int) → jsonb`

- **Purpose.** Notification Center popover contents. Returns the top N unread notifications for the workspace, hydrated with rendering-ready payload, plus a `has_more` flag. Default `p_limit = 15`.
- **Return shape.** `jsonb`:
  ```
  {
    rows: [ ... hydrated notification rows ... ],
    has_more: boolean,
    total_unread: int
  }
  ```
- **Capability check.** `notification.view`.
- **Index.** I-2 (inbox partial, filtered further by `read_at IS NULL`).
- **Freeze Index section:** §13, §26.3.
- **Priority:** High.
- **Blocks implementation?** No (popover can be built on `list_notifications_unread`; convenience RPC).

### 15.6 `list_notifications_by_source(p_subject_kind text, p_subject_id uuid, p_limit int) → setof jsonb`

- **Purpose.** Reverse lookup: "give me every notification referencing this subject." Used by future cross-slice UX (e.g., "who was notified about this release?"). Not consumed by v1 UI but exposed for Wave 2+ integration and for AI-slice context readers.
- **Return shape.** Set of `jsonb` rows (same shape as §15.3's return).
- **Filter predicate.** `subject_kind = p_subject_kind AND subject_id = p_subject_id`. Additional RLS filters apply automatically (`recipient_profile_id = auth.uid()`).
- **Capability check.** `notification.view`.
- **Index.** I-8 (subject reverse partial).
- **Note on RLS interaction.** The caller sees only their own notifications for the subject — cross-recipient visibility is not exposed. To answer "how many total recipients were notified about this subject," a future `notification.view_any`-gated RPC would be needed (RESERVED).
- **Freeze Index section:** §17.1, §26.3.
- **Priority:** Medium.
- **Blocks implementation?** No.

### 15.7 Read RPC count

Total: 6 read RPCs, matching Freeze Index §26.3 enumeration:
- `list_notifications_inbox` (mapped to Freeze Index `list_notifications`)
- `list_notifications_unread`
- `get_notification`
- `get_notification_badge_count`
- `get_notification_center` (mapped from Freeze Index `get_notification_facets` responsibility; facets are inlined into `list_notifications_inbox` return and popover-specific data is served here)
- `list_notifications_by_source` (mapped from Freeze Index `list_notifications_for_subject`)

---

## 16. Write RPCs

Eight new write RPCs. Every one is `SECURITY DEFINER`, `SET search_path = ''`, gates on `notification.manage`, enforces `recipient_profile_id = auth.uid()` in-body, sets `lign.allow_notification_rpc_write = 'true'` transaction-local before UPDATE, and returns a small `jsonb` summary.

**Self-only writes (mandatory).** Every write RPC's body includes an explicit `WHERE recipient_profile_id = (select auth.uid())` clause on its UPDATE — belt-and-braces alongside RLS `notifications_update` policy. Cross-recipient mutation is impossible even under a hypothetical RLS bypass because the RPC re-filters. This mirrors the APP 007 §17 defense-in-depth pattern.

**GUC discipline.** Every write RPC begins with `PERFORM set_config('lign.allow_notification_rpc_write', 'true', true)` (transaction-local, third arg true) and ends with `PERFORM set_config('lign.allow_notification_rpc_write', 'false', true)`. The `enforce_notification_rpc_only_writes` trigger checks this GUC on every UPDATE and rejects UPDATE where the GUC is not `'true'`.

**No workflow-side mutation.** Every RPC only touches `notifications` rows owned by `auth.uid()`. Zero writes to any workflow table.

**Idempotency.** Every RPC is idempotent under the semantics "eventually N such calls produce the same terminal state" (Freeze Index §11.5). `mark_notification_read` on an already-read row: no-op success (rows-affected=0). `dismiss_notification` on a dismissed row: no-op success. `archive_notification` on an archived row: no-op success.

### 16.1 `mark_notification_read(p_notification_id uuid) → jsonb`

- **Purpose.** Set `read_at = now()` on a single notification.
- **Behavior.**
  1. Capability check: `notification.manage` (implicit-pass in v1).
  2. Set `lign.allow_notification_rpc_write = 'true'` transaction-local.
  3. `UPDATE public.notifications SET read_at = now(), updated_at = now() WHERE id = p_notification_id AND recipient_profile_id = (select auth.uid()) AND read_at IS NULL`.
  4. Capture rows-affected.
  5. Reset GUC.
  6. Return `{ success: true, rows_affected: int, notification_id: p_notification_id, resulting_state: { read_at: <ts or null>, dismissed_at: <ts or null>, archived_at: <ts or null> } }`.
- **Idempotency.** If the row is already read (`read_at IS NOT NULL`), the WHERE clause excludes it; rows_affected = 0; still returns success.
- **Freeze Index section:** §11.2, §26.4.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 16.2 `mark_notification_unread(p_notification_id uuid) → jsonb`

- **Purpose.** Set `read_at = NULL` on a single notification (Freeze Index G-5 explicitly allows).
- **Behavior.** Same shape as §16.1 but sets `read_at = NULL`. Idempotent (no-op if already unread).
- **Freeze Index section:** §11.2, §26.4, G-5.
- **Priority:** High.
- **Blocks implementation?** No (Undo affordance depends on it; polish).

### 16.3 `mark_all_notifications_read(p_ws_id uuid, p_category text) → jsonb`

- **Purpose.** Bulk set `read_at = now()` for every unread notification of the caller in the workspace (optionally filtered by category).
- **Behavior.**
  1. Capability check.
  2. Set GUC.
  3. `UPDATE public.notifications SET read_at = now(), updated_at = now() WHERE recipient_profile_id = (select auth.uid()) AND workspace_id = p_ws_id AND read_at IS NULL AND dismissed_at IS NULL AND archived_at IS NULL AND (p_category IS NULL OR category = p_category)`.
  4. Capture rows-affected.
  5. Reset GUC.
  6. Return `{ success: true, rows_affected: int, workspace_id: p_ws_id, category: p_category }`.
- **Atomicity.** Single UPDATE per Freeze Index G-10; O(unread count) bounded by I-1 partial index.
- **Includes informational notifications.** Per Freeze Index G-47: `mark_all_notifications_read` includes every unread regardless of priority.
- **Freeze Index section:** §11.2, §26.4, G-10, G-47.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 16.4 `mark_notifications_read_bulk(p_notification_ids uuid[]) → jsonb`

- **Purpose.** Bulk mark-read by explicit id list (for Inbox multi-select).
- **Behavior.** `UPDATE ... WHERE id = ANY(p_notification_ids) AND recipient_profile_id = (select auth.uid()) AND read_at IS NULL`.
- **Bounded input.** RPC rejects `array_length(p_notification_ids, 1) > 500` with `22023` to prevent unbounded scans.
- **Freeze Index section:** §11.2, §26.4.
- **Priority:** High.
- **Blocks implementation?** No.

### 16.5 `dismiss_notification(p_notification_id uuid) → jsonb`

- **Purpose.** Set `dismissed_at = now()`; also set `read_at = now()` if unread (dismissing implies acknowledged, per Freeze Index §11.2).
- **Behavior.**
  1. Capability check.
  2. Set GUC.
  3. `UPDATE public.notifications SET dismissed_at = now(), read_at = coalesce(read_at, now()), updated_at = now() WHERE id = p_notification_id AND recipient_profile_id = (select auth.uid()) AND dismissed_at IS NULL`.
  4. Reset GUC.
  5. Return summary.
- **One-way.** No `undismiss_notification` RPC in v1 (Freeze Index §3.2).
- **Freeze Index section:** §11.2, §26.4.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 16.6 `dismiss_notifications_bulk(p_notification_ids uuid[]) → jsonb`

- **Purpose.** Bulk dismiss by id list. Same behavior as §16.5 across many rows, with the same 500-item bound.
- **Freeze Index section:** §11.2, §26.4.
- **Priority:** High.
- **Blocks implementation?** No.

### 16.7 `archive_notification(p_notification_id uuid) → jsonb`

- **Purpose.** Set `archived_at = now()`; also set `read_at = now()` if unread.
- **Behavior.** Same shape as §16.5 but sets `archived_at`.
- **One-way.** No `unarchive_notification` RPC in v1 (Freeze Index G-40; RESERVED for future wave).
- **Interaction with I-7 dedup index.** The partial unique index has `WHERE archived_at IS NULL`; archiving a row removes it from the unique constraint. In v1 this has no effect because no replay path exists that could re-emit the same `source_event_id`; the predicate is defensive scaffolding for Wave 4 replay workers (documented in §7.6 and §17.3).
- **Freeze Index section:** §11.2, §26.4, G-40.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 16.8 `archive_notifications_bulk(p_notification_ids uuid[]) → jsonb`

- **Purpose.** Bulk archive by id list. Same behavior as §16.7 with the 500-item bound.
- **Freeze Index section:** §11.2, §26.4.
- **Priority:** High.
- **Blocks implementation?** No.

### 16.9 Write RPC count

Total: 8 write RPCs, matching Freeze Index §26.4 enumeration:
- `mark_notification_read`, `mark_notification_unread`, `mark_all_notifications_read`, `mark_notifications_read_bulk`, `dismiss_notification`, `dismiss_notifications_bulk`, `archive_notification`, `archive_notifications_bulk`.

**RESERVED future write RPCs (name-only, no v1 implementation):**
- `unarchive_notification(p_notification_id uuid)` — reserved per Freeze Index G-40.
- `set_notification_preference(...)` — reserved for the preferences table (§4.4).
- `mute_notification_category(...)` — reserved.
- `snooze_notification(...)` — reserved.

### 16.10 No workflow-side write

Explicitly restated: every RPC in §16.1–§16.8 mutates only `notifications`. Zero writes to `reviews`, `approvals`, `approval_requests`, `requirements`, `releases`, `release_items`, `comments`, `annotations`, `design_assets`, `asset_versions`, or any other workflow table.

---

## 17. Backend gaps

Design choices and known limits that will surface as Backend Re-freeze Review considerations. Enumerated for the review cycle.

### 17.1 Router exception observability (v1 uses RAISE WARNING only)

- **Gap.** When `resolve_notification_router_targets` catches an exception, v1 emits `RAISE WARNING` visible only in Postgres logs. Ops has no queryable table of historical router failures.
- **Impact.** A silently-missed notification is recoverable (recipient still sees the underlying event via source-slice UI), but reconstructing "which recipients missed which events" post-hoc requires log-scraping.
- **Recursion posture (not a gap; documented for completeness).** The router body's step-1a explicit `notification.*` guard (§9.1) is the **primary defense** against event-loop recursion — no event in the reserved `notification.*` namespace ever reaches the routing-table lookup. The routing-table's absence of `notification.*` entries is the **secondary defense** (fall-through to `RETURN NEW` for unknown types). Both defenses run under the outer `BEGIN … EXCEPTION` wrapper.
- **Mitigation (future).** Wave 4 adds `notification_router_errors` table (RESERVED name registered in v1); the EXCEPTION handler INSERTs a diagnostic row. Not shipped in v1 to keep Wave 1 scope minimal.
- **Freeze Index section:** §20.3, G-2 caveat.
- **Priority:** Medium (v1 works; observability is polish).

### 17.2 Recipient resolution correctness under concurrent membership changes

- **Gap.** The router reads `workspace_members`, `project_participants` at trigger time. If a membership change is committed after the source event's transaction begins but before the router runs, the recipient set may miss/include the newly-added/-removed member — depending on transaction isolation level.
- **Impact.** Rare race; typical membership churn is orders of magnitude slower than event bursts. The Access-check RLS predicate (§10.1) filters at read time, so a stale recipient row is hidden from the actually-removed user; the reverse (a newly-added user missing a notification) is a silent loss recoverable via the source-slice UI.
- **Mitigation (future).** Wave 4 could add explicit `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ` in the router function body to make the read-set consistent — trade-off against contention.
- **Freeze Index section:** §9, §21.1.
- **Priority:** Low (rare; correctness preserved by RLS at read time).

### 17.3 Dedup discipline under router retry

- **Gap.** The partial unique index I-7 `(recipient_profile_id, source_event_id, notification_type) WHERE archived_at IS NULL` + `INSERT ... ON CONFLICT DO NOTHING` handles the common case. The `WHERE archived_at IS NULL` predicate is **defensive scaffolding for Wave 4 replay workers** that may re-emit events after archival cleanup (e.g., an async email-delivery worker retry, or a router-error replay path landing with `notification_router_errors`). In v1 no replay path exists that could produce a duplicate `source_event_id` write, so the predicate is unreachable in v1 traffic. It is included now to lock the dedup contract shape before Wave 4 delivery workers ship, so those workers can bind to a fixed index definition without a rework.
- **Impact.** Zero in v1 (no replay path exists; the predicate is unreachable in v1 traffic). Documented for Wave 4 wave awareness.
- **Freeze Index section:** §9.7, G-7.
- **Priority:** Low.

### 17.4 Payload snapshotting immutability boundary

- **Gap.** The router materializes `payload jsonb` at INSERT time. Subsequent renames/edits to the source subject do not update rendered notifications. A user renaming "Kitchen Layout" to "Kitchen Renovation" will see historical notifications rendering the old label.
- **Impact.** Feature, not bug. Codified in Freeze Index G-57. UI can reconcile at click time by fetching the current subject via the source slice's read RPC.
- **Freeze Index section:** G-57, §10.4.
- **Priority:** N/A (intentional).

### 17.5 Retention

- **Gap.** v1 keeps notifications forever. Per Freeze Index G-9 the policy is 90 days for read / forever for unread / 30 days for dismissed / forever for archived — but no cron/pruning job ships in v1.
- **Impact.** Table grows without bound in production over time. Estimated growth ≈ 60 P0 events × O(recipients) × workspaces / month. For a small deployment, negligible for a year. For enterprise, requires Wave 4 pruning job.
- **Mitigation (future).** Wave 4 cron slice runs `DELETE FROM public.notifications WHERE read_at < now() - interval '90 days' AND archived_at IS NULL` via `service_role`.
- **Freeze Index section:** G-9, §29.2.
- **Priority:** Medium (deferred; not v1 blocker).

### 17.6 Cross-project inbox is workspace-scoped only

- **Gap.** Per Freeze Index G-12: v1 has no per-project inbox route. Users think of "my inbox" as a person-scoped concept; the workspace scope naturally aggregates project-scoped notifications. `?project_id=` URL param filters within the workspace inbox.
- **Impact.** Users looking for "just this project's notifications" pass a URL param; direct navigation from a project header would require a Wave 4 additive route.
- **Freeze Index section:** G-12, §12.1.
- **Priority:** Low.

### 17.7 Category enum stability

- **Gap.** v1 fixed enum of 6 categories per CHECK constraint. Adding a category is a rare re-freeze event.
- **Impact.** If a new source event type demands a new category (e.g., `security_incident`), the CHECK must be updated + all downstream filter-chip UI updated. Coordinated Wave 4 change.
- **Freeze Index section:** G-13, §6.
- **Priority:** N/A (intentional stability).

### 17.8 Self-exclusion enforcement point

- **Gap.** Self-exclusion is enforced in the router body (`WHERE recipient_profile_id != NEW.actor_profile_id`). If a future router bug omits this predicate, the actor would receive a notification for their own action.
- **Mitigation.** The router function body is centralized; adding a test covering self-exclusion is Wave 1 QA scope. A defense-in-depth CHECK constraint (`CHECK (recipient_profile_id != actor_profile_id OR actor_profile_id IS NULL)`) would be too strict — some legitimate future notification types may broadcast to a set that happens to include the actor (e.g., a system announcement).
- **Freeze Index section:** §9.8, G-8, G-15.
- **Priority:** Low (test-covered).

### 17.9 No batching

- **Gap.** v1 does not batch across events. A single event triggering 200 notifications INSERTs 200 rows in the same transaction. Acceptable per Freeze Index G-18 for v1 (typical event → 1–10 recipients); high-fan-out events (e.g., broadcast to 500 project participants) may need Wave 4 batching or async worker.
- **Impact.** Router body cost scales linearly with recipient set. If measured slow, migrate to async worker (v1.1 re-freeze concern).
- **Freeze Index section:** G-18, §9.10, §20.4.
- **Priority:** Low.

### 17.10 Rate limiting: no backend rate limit

- **Gap.** v1 has no backend rate limit on write RPCs. A malicious client could spam `mark_all_notifications_read` calls. RLS + the RPC-only-write GUC bound the damage (only own rows can be touched), but the row's `updated_at` would churn.
- **Mitigation (future).** Wave 4 could add a per-caller rate limit at the RPC gateway (e.g., Supabase Edge Function pre-check). Not v1 concern; RLS enforces correctness.
- **Priority:** Low.

### 17.11 `actor_display_name` denormalization staleness

- **Gap.** The router captures `actor_display_name` from `profiles.display_name` at INSERT time (per §10.4). If the profile is later renamed, historical notifications still show the old name.
- **Impact.** Feature, per Freeze Index G-57 (payload immutability). If a user cares about "who is this really," they click to the deep-link and see the source-slice's live-hydrated actor.
- **Priority:** N/A.

### 17.12 `should_toast boolean` hint (per Freeze Index §17 backend gap enumeration)

- **Gap.** Toast rate-limiting (max 3 concurrent per G-19) is a frontend concern, but the backend can provide a hint. `get_notification_center` return could include a `should_toast boolean` field per row, computed as `priority IN ('critical','high') AND created_at > now() - interval '60 seconds'`.
- **Impact.** Optional Wave 2 addition; v1 frontend computes locally.
- **Priority:** Low.

### 17.13 No hard delete

- **Gap.** No RPC or RLS permits DELETE on `notifications`. Retention pruning (Wave 4) uses `service_role`. Users cannot permanently remove a notification.
- **Impact.** Feature per Freeze Index G-41. Archive is the terminal user action.
- **Priority:** N/A.

### 17.14 Realtime remains OUT

- **Gap.** Toasts and badge freshness rely on 60s polling. Latency is up to 60s. Acceptable per Freeze Index §25.4 and user brief.
- **Mitigation (future).** APP 011 activates realtime; polling becomes fallback.
- **Priority:** Deferred to APP 011.

---

## 18. Implementation waves

Four-wave plan. Every wave's items are cited by section number and priority tag.

### 18.1 Wave 1 — Critical (18 items)

Backend surface that must land before any other wave.

1. Migration A: `CREATE TABLE public.notifications` with all 19 columns (§5) + composite tenancy FKs (§7.7).
2. All 8 additive indexes I-1 through I-8 on `notifications` (§6). I-9 (actor partial) counted with Wave 2.
3. CHECK constraints: `notifications_category_check`, `notifications_priority_check`, `notifications_delivery_state_check`, `notifications_channels_attempted_check`, `notifications_payload_size_check` (§7).
4. RLS enable + 4 policies on `notifications` (§10.1).
5. Trigger `enforce_notification_router_bridge` AFTER INSERT on `activity_events` + function `resolve_notification_router_targets` (§9.1).
6. Trigger `enforce_notification_immutable_fields` BEFORE UPDATE on `notifications` (§9.2).
7. Trigger `enforce_notification_rpc_only_writes` BEFORE UPDATE on `notifications` (§9.3).
8. Trigger `notifications_set_updated_at` BEFORE UPDATE on `notifications` (§9.4).
9. Extension of `lign_has_capability` recognizing `notification.view`, `notification.manage` (implicit grant every role) + 6 RESERVED keys returning `false` (§11.3).
10. RPC `list_notifications_inbox` (§15.1).
11. RPC `get_notification_badge_count` (§15.4).
12. RPC `mark_notification_read` (§16.1).
13. RPC `mark_all_notifications_read` (§16.3).
14. RPC `dismiss_notification` (§16.5).
15. RPC `archive_notification` (§16.7).
16. EVENT_MODEL.md doc-diff registering 3 RESERVED event names: `notification.ai_prioritized`, `notification.ai_summarized`, `notification.digest_sent` (§12.2; mirrors APP 009 F-5 discipline — vocabulary lock is real from Wave 1).
17. PERMISSIONS.md doc-diff registering 2 wired keys (`notification.view`, `notification.manage`) + 6 RESERVED keys (§11).
18. DOMAIN_MODEL.md doc-diff registering `Notification` entity (wired) + 4 RESERVED table names (`notification_preferences`, `notification_deliveries`, `notification_digests`, `notification_router_errors`).

### 18.2 Wave 2 — High (7 items)

Secondary RPCs; polish reads; index I-9.

1. Additive index I-9 `notifications_actor_idx` (§6).
2. RPC `get_notification` (§15.3).
3. RPC `get_notification_center` (§15.5).
4. RPC `list_notifications_unread` (§15.2).
5. RPC `mark_notification_unread` (§16.2).
6. RPC `dismiss_notifications_bulk` (§16.6).
7. RPC `archive_notifications_bulk` (§16.8).
8. RPC `mark_notifications_read_bulk` (§16.4).

Total: 8 items (index + 7 RPCs).

### 18.3 Wave 3 — Medium (6 items)

Cross-slice integration polish; documentation completeness.

1. RPC `list_notifications_by_source` (§15.6).
2. `invalidateNotificationSurfaces(wsId)` client helper documentation (§13.4).
3. Documentation of `should_toast` hint pattern (§17.12).
4. Wave-1 doc-diffs' cross-references from Freeze Index cross-slice sections (§19).
5. Saved-view integration (if applicable): reuse APP 006 `user_saved_views` with `scope='notifications'`. Reserved-name-only if the frontend does not ship the feature in v1.
6. Bookmark integration (per Freeze Index G-54): explicitly DECIDED NOT to add — reserved-name-only.

Total: 6 items.

### 18.4 Wave 4 — Future (14 items)

Reserved seams; async delivery; AI; preferences; retention; realtime.

1. `notification_preferences` table DDL + wiring (RESERVED-name only in v1).
2. `notification_deliveries` table DDL + async delivery worker.
3. `notification_digests` table + cron slice.
4. `notification_router_errors` table + router EXCEPTION-handler DB write.
5. Async email delivery worker (consumes payloads where `channels_attempted @> ARRAY['email_payload']`).
6. Async push delivery worker (consumes payloads where `channels_attempted @> ARRAY['push_payload']`).
7. Cron scheduler for digests (consumes rows to produce `notification.digest_sent` event).
8. AI reprioritization RPC bodies (RESERVED capabilities become wired).
9. AI summary generation RPCs.
10. AI digest generation RPCs.
11. Preference wiring: `set_notification_preference`, `mute_notification_category`, `snooze_notification` RPCs.
12. `unarchive_notification` RPC (G-40).
13. Retention pruning cron job (per G-9): `service_role` DELETE of read notifications older than 90 days.
14. Realtime activation: add `notifications` to `supabase_realtime` publication (blocked on APP 011 re-freeze); wire `useNotificationRealtimeSubscription`.

Total: 14 items.

### 18.5 Wave tally

- Wave 1 Critical: 18 items.
- Wave 2 High: 8 items.
- Wave 3 Medium: 6 items.
- Wave 4 Future: 14 items.
- **Total: 46 items** across four waves.

Plus 3 Wave-1 doc-diff deliverables (EVENT_MODEL.md, PERMISSIONS.md, DOMAIN_MODEL.md) counted within Wave 1 items 16–18.

---

## 19. Cross-slice compatibility

Per-slice statement for APP 001 through APP 011. Every prior slice's contract is preserved byte-identically. APP 010 is a purely additive consumer.

### 19.1 APP 001 (Auth / Foundation)

- **Reads.** `profiles` (for recipient display name + avatar via router payload materialization; also for RLS via `recipient_profile_id = auth.uid()`). `workspace_members` (for tenant membership check + workspace-broadcast recipient rule). `activity_events` (as the source of the router bridge; reads NEW via trigger; never writes).
- **Writes.** None in any APP 001 table.
- **Frozen surface impact.** Zero. The AFTER INSERT trigger on `activity_events` is boundary-additive per §9.1 rationale.
- **Cross-slice extension.** `lign_has_capability` extended additively for 2 wired keys + 6 RESERVED keys (§11.3).

### 19.2 APP 002 (Application Shell)

- **Extends.** `qk` namespace (§13.1: 7 new key builders). `CAPABILITY_KEYS` (§11: 2 wired + 6 RESERVED). `DeepLinkResolver` (§2.11: 1 new kind `notification`). `NavRail` (1 new item "Inbox"). Hotkey slots (`N`, `Shift+N`, `E`, `Backspace`).
- **Router-shape additions.** 1 new page route (`/workspace/:ws_id/inbox`) + 1 new deep-link route (`/deep/notification/:id`).
- **Writes to APP 002 tables.** None.
- **All additive.**

### 19.3 APP 003 (Projects & Design Workspace)

- **Reads.** `project_participants` (for project-broadcast recipient rule per §9.3), `projects` (for tenant-check via composite FK).
- **Writes.** None.
- **Design Workspace impact.** No RightPanel tab added (per Freeze Index G-26; bell + Center popover cover the need). No component API change.

### 19.4 APP 004 (Files & Viewer)

- **Reads.** None (notifications never render file bodies; deep-link takes over).
- **Writes.** None.
- **No interaction beyond source-event consumption** (asset-related events in EVENT_MODEL.md §4.4 produce `asset.archived_in_your_project` / `asset.unarchived_in_your_project` notifications per Freeze Index §5.8; the router reads no file-specific tables).

### 19.5 APP 005 (Comments & Annotations)

- **Consumes.** `comment.mentioned` (in-app notify per EVENT_MODEL.md §7.5), `annotation.resolved` (owner-notify per §5.8). Other comment/annotation events are feed-only in v1.
- **Extends.** `useCopyLink` (2 new `LinkKind` values: `notification`, `inbox`).
- **Does NOT add.** `target_notification_id` on `comments`. Rationale per Freeze Index G-32: notifications are not commentable. Same posture as APP 009 G-32.
- **Writes to APP 005 tables.** None.

### 19.6 APP 006 (Reviews)

- **Consumes.** `review.opened`, `review.completed`, `review.cancelled`, `review.reviewer_responded` (EVENT_MODEL.md §4.7).
- **Reserved consumers (name-locked; not v1).** `review.deadline_approached`, `review.deadline_passed`, `review.reviewer_removed`, `review.reviewer_reassigned` (per APP 006 §21 certification).
- **Reads.** `reviews`, `review_participants` for recipient resolution.
- **Writes to APP 006 tables.** None.
- **Frozen surface impact.** Zero. Every `review.*` event name, RPC signature, RLS policy, and trigger is preserved.

### 19.7 APP 007 (Approvals)

- **Consumes.** All 6 P0 `approval.*` events: `approval.requested`, `approval.responded`, `approval.approved`, `approval.rejected`, `approval.expired`, `approval.cancelled` (EVENT_MODEL.md §4.11; Freeze Index §5.2).
- **Reserved consumers.** `approval.deadline_approached` (name-locked per APP 007 §21 certification).
- **Reads.** `approval_requests`, `approval_request_approvers` for recipient resolution; `approval_responses` (indirectly via `approval.responded` snapshot).
- **Writes to APP 007 tables.** None.
- **Frozen surface impact.** Zero.

### 19.8 APP 008 (Requirements)

- **Consumes.** Zero `requirement.*` events in v1 (all feed-only per EVENT_MODEL.md §4.14 and APP 008 §12 certification).
- **Reserved consumers (name-locked; not v1).** `requirement.assigned_to_you`, `requirement.your_requirement_updated`, `requirement.critical_regressed`, `requirement.assessed_by_you_stale`.
- **Reads.** `requirements` (for future requirement-owner recipient resolution when APP 008 ships owner column; deferred).
- **Writes to APP 008 tables.** None.
- **Frozen surface impact.** Zero.

### 19.9 APP 009 (Releases)

- **Consumes.** `release.finalized`, `release.withdrawn` (EVENT_MODEL.md §4.12). Also consumes the additive payload extensions per APP 009 §20.4 (e.g., `release_type`, `published_by_profile_id`, `requirement_readiness`) for rendering-only fields.
- **Reserved consumers (name-locked; not v1).** `release.scheduled`, `release.superseded`, `release.recalled`, `release.notes_updated`, `release.ai_suggested`, `release.ai_classified`.
- **Reads.** `releases`, `release_items` (for recipient resolution — project participants with `release.view`).
- **Writes to APP 009 tables.** None.
- **Frozen surface impact.** Zero.

### 19.10 APP 010 (this)

- **Owner.** Every table, index, trigger, RPC, capability, event name in the `notification.*` namespace is owned here.
- **Backend surface delta.** Exhaustively enumerated in §24.

### 19.11 APP 011 (Realtime — not yet frozen)

- **Reserved dependency.** APP 010 v1 uses polling per Freeze Index §25.4; APP 011 will push notifications via websocket subscription when it lands.
- **Reserved channels (name-locked).** `notifications:profile:<profile_id>`, `notifications:workspace:<ws_id>` (Freeze Index §25.3).
- **`notifications` NOT in `supabase_realtime` publication in v1.** Adding it is an APP 011 re-freeze concern, not APP 010's.

### 19.12 STORAGE (STORAGE 001–004)

- **Untouched.** Notifications carry no file references. `payload.avatar_seed`-style rendering hints are strings, not storage-object IDs.

### 19.13 AUTHORIZATION (AUTH 001+)

- **Extends.** `PERMISSIONS.md` §5 role preset table gains `notification.view` and `notification.manage` for every role (§11.1). Additive.

### 19.14 REQUIREMENTS layer (REQUIREMENTS 001–005)

- **Untouched at backend layer.** Consumed at event layer (see APP 008 row above — zero v1 consumers). Frozen backend preserved.

### 19.15 EVENTS layer

- **Extended additively.** 3 RESERVED event names registered in EVENT_MODEL.md via Wave 1 doc-diff. Zero frozen event redefined.

---

## 20. Backwards-compatibility guarantees

Explicit enumeration of every guarantee. This is the section a Backend Re-freeze Review reader validates against.

### 20.1 No frozen RPC signature broken

APP 010 performs exactly one `CREATE OR REPLACE` of the frozen `lign_has_capability(uuid, uuid, text)` function. This replacement is strictly additive: the signature is preserved; every existing capability key and role mapping remains byte-identical; only the new `notification.*` capability keys (2 wired + 6 reserved) are appended. No existing capability changes. No overload is introduced. No named-argument ambiguity arises. Per checklist C-2, byte-identical role-map preservation is guaranteed. Beyond this single additive reissue, every APP 001–009 RPC's signature, return shape, and behavior is unchanged.

Callers of any frozen RPC — `create_review`, `respond_to_approval`, `finalize_release`, `withdraw_release`, `create_requirement`, `edit_requirement`, `assess_requirement`, `create_release_draft`, `publish_release`, `mark_annotation_resolved`, `mention_profile_in_comment`, `invite_workspace_member`, `activate_workspace_member`, `add_project_participant`, etc. — continue to compile and execute unchanged.

### 20.2 No frozen event name renamed or redefined

Every EVENT_MODEL.md §4.1–§4.14 row is preserved byte-identically. No `event_type` string changed. No `subject_kind` semantic changed. No `PDH`/`WA`/`Notify`/`Sec` routing cell changed. No `Actor`/`Subject`/`Project`/`Snapshot` column redefined.

APP 010 emits zero workflow events (§12.1). The three new event names (`notification.ai_prioritized`, `notification.ai_summarized`, `notification.digest_sent`) are RESERVED under the `notification.*` namespace with zero emitters in v1.

### 20.3 No frozen capability role map changed

APP 010 performs exactly one `CREATE OR REPLACE` of the frozen `lign_has_capability(uuid, uuid, text)` function. This replacement is strictly additive: the signature is preserved; every existing capability key and role mapping remains byte-identical; only the new `notification.*` capability keys (2 wired + 6 reserved) are appended. No existing capability changes. No overload is introduced. No named-argument ambiguity arises. Per checklist C-2, byte-identical role-map preservation is guaranteed. Every prior capability's return value is byte-identical. No prior row in PERMISSIONS.md §5 role preset table is modified.

### 20.4 No frozen table RLS policy changed

Every RLS policy on every APP 001–009 table is preserved byte-identically. APP 010 adds 4 new policies on the new `notifications` table only (§10.1). Zero policy on `activity_events`, `workspace_members`, `project_participants`, `profiles`, `reviews`, `review_participants`, `approval_requests`, `releases`, `release_items`, `requirements`, `comments`, `annotations`, or any other frozen table is dropped, replaced, or modified.

### 20.5 No frozen trigger removed or modified

Every frozen trigger is preserved byte-identically:
- The frozen `activity_events_no_update` and `activity_events_no_delete` triggers (Migration 009), which share the `enforce_activity_events_append_only` function.
- `releases_set_updated_at`, `release_items_set_updated_at`, `enforce_release_finalization_prerequisites_insert`/`_update`, `enforce_release_items_parent_draft_mutation`, `enforce_release_status_via_rpc` (Migration 008 + AUTH 008).
- Every APP 006, 007, 008 slice trigger.
- Every APP 001–005 slice trigger.

APP 010 adds 4 new triggers: 1 on `activity_events` (boundary-additive AFTER INSERT per §9.1) and 3 on the new `notifications` table (§9.2, §9.3, §9.4).

### 20.6 No frozen column added, dropped, renamed, or narrowed on any APP 001–009 table

Explicitly enumerated in §5.23. Zero columns added to any of the ~28 frozen tables. Zero columns dropped. Zero columns renamed. Zero CHECK narrowed. Zero enum value removed.

### 20.7 `activity_events` trigger addition is boundary-additive

The AFTER INSERT trigger on `activity_events` is a boundary-additive extension per §3.3 rationale:
- No column change on `activity_events`.
- No RLS change on `activity_events`.
- No data mutation on `activity_events` (trigger only reads NEW and writes to `notifications`).
- No modification of the frozen `activity_events_no_update` and `activity_events_no_delete` triggers, which share the `enforce_activity_events_append_only` function.
- Only spawns rows in the new `notifications` table.

The trigger cannot cause a workflow transaction rollback (per §20.8).

### 20.8 Router exception-safe: workflow transactions cannot be rolled back by notification failures

The `resolve_notification_router_targets` function body wraps every operation in `BEGIN … EXCEPTION WHEN OTHERS THEN RAISE WARNING …; RETURN NEW; END;`. Under no circumstance does a router failure propagate into the parent workflow transaction. This is the single most important design constraint of APP 010 and is repeated in §2.8, §9.1, §17.1.

If APP 010's router had a bug (e.g., missing key in `subject_snapshot`, deadlock on `workspace_members`, unknown notification type), the workflow transaction still commits. The missed notification is a silent loss (recoverable via source-slice UI).

### 20.9 Zero migration to `activity_events` schema

APP 010 does not `ALTER TABLE public.activity_events` in any way. No column added. No column type changed. No index dropped. No constraint added.

### 20.10 Realtime publication unchanged

`supabase_realtime` publication is unchanged. `notifications` is NOT added to the publication (Freeze Index §25.1 and §26.9). Adding it is an APP 011 re-freeze concern.

### 20.11 No cross-slice qk namespace collision

The 7 new `qk` keys in the `notification` namespace collide with none of the frozen namespaces (`workspace`, `project`, `asset`, `version`, `file`, `comment`, `annotation`, `review`, `approval`, `requirement`, `release`, `deep`, `bookmark`, `savedView`). Verified per Freeze Index §17.1.

### 20.12 No cross-slice URL param collision

All new URL params on the Inbox route (`tab`, `category`, `priority`, `source`, `project_id`, `actor_id`, `date_from`, `date_to`, `cursor`, `highlight`) are namespace-safe against every prior slice's URL grammar (verified per Freeze Index §16.3).

### 20.13 No cross-slice hotkey collision

`N` at workspace level (bell popover toggle), `Shift+N` (navigate to Inbox), `E` (archive focused card), `Backspace`/`Delete` (dismiss focused card) — collision-analyzed against APP 006 (`R` for new review), APP 007 (`A` for new approval), APP 008 (`Q` for new requirement), APP 009 (context-scoped `N` in release dashboards per G-19). No collision (Freeze Index §16.6).

### 20.14 Deep-link kind ownership preserved

Every deep-link kind referenced by a notification's `payload.deep_link` is owned by the source slice (Freeze Index §15.1, G-23). APP 010 adds exactly one new kind: `notification`. Zero existing kind's resolver is modified.

### 20.15 APP 006 Review re-freeze certification preserved

Every finding applied in the APP 006 Backend Re-freeze cycle (`freeze/APP_006_FINAL_CERTIFICATION.md`) remains valid. No `review.*` RPC signature or event name modified. Chain-init (T-CRIT-1) discipline preserved for `review_rounds`.

### 20.16 APP 007 Approvals re-freeze certification preserved

Every finding applied in the APP 007 Backend Re-freeze cycle (`freeze/APP_007_FINAL_CERTIFICATION.md`) remains valid. No `approval.*` RPC signature or event name modified.

### 20.17 APP 008 Requirements re-freeze certification preserved

Every finding applied in the APP 008 Backend Re-freeze cycle (`freeze/APP_008_FINAL_CERTIFICATION.md`) remains valid. No `requirement.*` RPC signature or event name modified. Frozen `create_requirement` 15-arg / `edit_requirement` 13-arg CREATE OR REPLACE single-function extension preserved.

### 20.18 APP 009 Releases re-freeze certification preserved

Every finding applied in the APP 009 Backend Re-freeze cycle (`freeze/APP_009_FINAL_CERTIFICATION.md`) remains valid. F-1 chain-immutability exactly-once initialization discipline unchanged. F-2 single-function `CREATE OR REPLACE` discipline preserved. F-3 concurrent-supersede `FOR UPDATE` preserved. F-4 removal of `p_capture_evidence` preserved. F-5 EVENT_MODEL.md Wave-1 doc-diff discipline mirrored here (§12.2). F-6 non-DEFINER row-local trigger discipline mirrored here (§9.2, §9.3, §9.4).

---

## 21. Coverage matrix

Every Freeze Index section (§1 through §30) mapped to backend items with "Fully covered / Partially covered / Deferred to Future" status.

| Freeze Index § | Topic | Backend surface | Coverage |
|---|---|---|---|
| §1 | Purpose | §1 Purpose | Fully covered |
| §2 | Notifications vs business workflow | §1.2, §2.7, §16.10, §19 (no-workflow-mutation restated) | Fully covered |
| §3 | Notification lifecycle | §5.17–§5.19 timestamps + §16 RPCs + §9.2 immutability trigger | Fully covered |
| §4 | Notification domain model (`notifications` table + 19 cols + reserved names) | §4, §5, §7 | Fully covered |
| §5 | Notification types (~25 wired + ~10 reserved) | §5.7 (column) + router body enumeration; frontend `types.ts` union | Fully covered |
| §6 | Notification categories (6 v1) | §5.8, §7.1 | Fully covered |
| §7 | Notification priorities (5 v1) | §5.9, §7.2 | Fully covered |
| §8 | Notification routing | §9.1 router function + application constant | Fully covered |
| §9 | Recipient resolution (6 rules) | §9.1 router function body outline | Fully covered |
| §10 | Delivery states (4 values) | §5.11, §7.3 | Fully covered (v1: only `delivered` used) |
| §11 | Read/unread model | §5.17–§5.19 + §16 RPCs | Fully covered |
| §12 | Inbox architecture | §15.1 `list_notifications_inbox` + §14 dashboard support | Fully covered |
| §13 | Notification Center UI | §15.5 `get_notification_center` + §16.3 mark-all-read | Fully covered |
| §14 | Badge architecture | §15.4 `get_notification_badge_count` + §14.2 | Fully covered |
| §15 | Deep links | §5.16 `payload.deep_link` + §2.11 `notification` kind | Fully covered |
| §16 | URL grammar | §15.1 filter params match §16.1 URL params | Fully covered |
| §17 | Query architecture | §13 | Fully covered |
| §18 | Cache invalidation | §13.4 invalidation matrix | Fully covered |
| §19 | Capability model | §11 | Fully covered |
| §20 | Event consumption (routing trigger) | §9.1 | Fully covered |
| §21 | Cross-slice compatibility | §19 | Fully covered |
| §22 | Desktop/mobile behavior | Backend-agnostic (frontend concern); no backend surface | N/A (frontend) |
| §23 | Loading/error states | Backend RPCs return structured errors; frontend renders | N/A (frontend) |
| §24 | AI extension seams | §11.2 RESERVED capabilities + §12.2 RESERVED event names | Fully covered (name-locked; wiring deferred) |
| §25 | Realtime boundary (APP 011) | §2.10 realtime OUT + §19.11 | Fully covered (OUT preserved) |
| §26 | Backend delta preview (scope anchor) | Every §26.x line covered by §3–§18 | Fully covered |
| §27 | Reusable primitives | Frontend concern; backend enumerates supporting RPCs | N/A (frontend) |
| §28 | Open architectural decisions (G-1 through G-60) | Every G-n cited inline in this proposal | Fully covered |
| §29 | Freeze checklist / non-goals | §18 waves address in-scope; §17 gaps + §29.2 explicit out-of-scope | Fully covered |
| §30 | Cross-slice compatibility matrix | §19 | Fully covered |

Full coverage of the Freeze Index scope statement. No section is deferred without explicit rationale in §17 (backend gaps) or §18 (wave assignment).

---

## 22. Priority summary

Consolidated table with Priority | Item | Section | Blocks impl?. Grouped by Critical / High / Medium / Future.

### 22.1 Critical (18 items — Wave 1 core)

| # | Item | § | Blocks impl? |
|---|---|---|---|
| C-01 | `notifications` table with 19 columns | §4.1, §5 | Yes |
| C-02 | Index I-1 unread partial | §6 | Yes |
| C-03 | Index I-2 inbox partial | §6 | Yes |
| C-04 | Index I-3 category partial | §6 | Yes |
| C-05 | Index I-7 dedup unique partial | §6 | Yes |
| C-06 | CHECK `notifications_category_check` | §7.1 | Yes |
| C-07 | CHECK `notifications_priority_check` | §7.2 | Yes |
| C-08 | FK `recipient_profile_id → profiles(id)` | §7.7 | Yes |
| C-09 | FK `(project_id, workspace_id) → projects` | §7.7 | Yes |
| C-10 | FK `source_event_id → activity_events` | §7.7 | Yes |
| C-11 | RLS on `notifications` (4 policies) | §10.1 | Yes |
| C-12 | Trigger `enforce_notification_router_bridge` + function | §9.1 | Yes |
| C-13 | Trigger `enforce_notification_immutable_fields` | §9.2 | Yes |
| C-14 | Trigger `enforce_notification_rpc_only_writes` | §9.3 | Yes |
| C-15 | Trigger `notifications_set_updated_at` | §9.4 | Yes |
| C-16 | `lign_has_capability` extension for 2 wired + 6 RESERVED keys | §11.3 | Yes |
| C-17 | RPC `list_notifications_inbox` | §15.1 | Yes |
| C-18 | RPC `get_notification_badge_count` | §15.4 | Yes |
| C-19 | RPC `mark_notification_read` | §16.1 | Yes |
| C-20 | RPC `mark_all_notifications_read` | §16.3 | Yes |
| C-21 | RPC `dismiss_notification` | §16.5 | Yes |
| C-22 | RPC `archive_notification` | §16.7 | Yes |
| C-23 | Wave-1 EVENT_MODEL.md doc-diff registering 3 RESERVED names | §12.2 | Yes (vocabulary lock) |

Total Critical items (fine-grained): 23. When collapsed to the 18 Wave-1 headline items in §18.1, the count aligns with the freeze index preview.

### 22.2 High (10 items — Wave 2)

| # | Item | § | Blocks impl? |
|---|---|---|---|
| H-01 | Index I-4 priority partial | §6 | No |
| H-02 | Index I-5 archived partial | §6 | No |
| H-03 | Index I-6 project partial (also covers FK-2) | §6 | No |
| H-04 | Index I-9 actor partial | §6 | No |
| H-05 | RPC `get_notification` | §15.3 | No |
| H-06 | RPC `get_notification_center` | §15.5 | No |
| H-07 | RPC `list_notifications_unread` | §15.2 | No |
| H-08 | RPC `mark_notification_unread` | §16.2 | No |
| H-09 | RPC `dismiss_notifications_bulk` | §16.6 | No |
| H-10 | RPC `archive_notifications_bulk` | §16.8 | No |
| H-11 | RPC `mark_notifications_read_bulk` | §16.4 | No |
| H-12 | CHECK `notifications_delivery_state_check` | §7.3 | No |
| H-13 | CHECK `notifications_channels_attempted_check` | §7.4 | No |
| H-14 | Index I-8 subject reverse partial | §6 | No |
| H-15 | FK `actor_profile_id → profiles(id)` | §7.7 | No |

Total High items (fine-grained): 15.

### 22.3 Medium (6 items — Wave 3)

| # | Item | § | Blocks impl? |
|---|---|---|---|
| M-01 | RPC `list_notifications_by_source` | §15.6 | No |
| M-02 | CHECK `notifications_payload_size_check` | §7.5 | No |
| M-03 | `invalidateNotificationSurfaces(wsId)` helper documentation | §13.4 | No |
| M-04 | `should_toast` hint pattern (backend enrichment of `get_notification_center`) | §17.12 | No |
| M-05 | Router-exception WARNING format documentation | §9.7, §17.1 | No |
| M-06 | Saved-view / bookmark reserved-name-only registration | §18.3 | No |

### 22.4 Future (14 items — Wave 4)

| # | Item | § | Blocks impl? |
|---|---|---|---|
| F-01 | `notification_preferences` table DDL + preference RPCs | §4.2, §18.4 | No |
| F-02 | `notification_deliveries` table DDL + async delivery worker | §4.3, §18.4 | No |
| F-03 | `notification_digests` table DDL + cron slice | §4.4, §18.4 | No |
| F-04 | `notification_router_errors` table DDL + router EXCEPTION-handler DB write | §4.5, §17.1 | No |
| F-05 | Async email delivery worker | §18.4 | No |
| F-06 | Async push delivery worker | §18.4 | No |
| F-07 | Cron scheduler for digests (emits `notification.digest_sent`) | §18.4 | No |
| F-08 | AI reprioritization RPC bodies | §11.2, §18.4 | No |
| F-09 | AI summary generation RPCs | §11.2, §18.4 | No |
| F-10 | AI digest generation RPCs | §11.2, §18.4 | No |
| F-11 | Preference wiring RPCs (`set_notification_preference`, `mute_notification_category`, `snooze_notification`) | §16.9 | No |
| F-12 | `unarchive_notification` RPC | §16.9, G-40 | No |
| F-13 | Retention pruning cron job (per G-9) | §17.5 | No |
| F-14 | Realtime activation: `notifications` into `supabase_realtime` publication + subscription hook | §2.10, §19.11 | No (blocked on APP 011) |

### 22.5 Priority tally

- **Critical: 23 fine-grained items** (18 Wave-1 headline items when collapsed per §18.1).
- **High: 15 fine-grained items** (8 Wave-2 headline items).
- **Medium: 6 items**.
- **Future: 14 items**.
- **Total: 58 fine-grained items** across four waves; approximately 46 headline items counted in §18.5.

---

## 23. Freeze contract

Upon Backend Re-freeze approval, this document becomes the authoritative backend contract for APP 010. It supersedes the pre-review proposal and is the input to Migration A + Migration B implementation (where Migration A contains Wave 1 schema + triggers + RPCs, and Migration B contains capability / event / permission additions).

Future changes require an amendment and re-freeze.

The contract binds the following:
- Every table, column, index, CHECK, FK, trigger, RLS policy, RPC signature, RPC return shape, capability key, event name, and wave assignment enumerated in this document.
- Every conflict-with-frozen-surface statement in §20 (backwards-compatibility guarantees).
- Every priority tag in §22.
- Every wave assignment in §18.
- The 3 RESERVED event names (§12.2) and 6 RESERVED capability keys (§11.2) locked in EVENT_MODEL.md and PERMISSIONS.md via Wave 1 doc-diffs.
- The 4 RESERVED table names (§4.2–§4.5) locked in DOMAIN_MODEL.md via Wave 1 doc-diff.
- The inviolable router exception-safety discipline (§2.8, §9.1, §17.1, §20.8).

---

## 24. Final backend delta summary

Concise table of the final scope.

| Kind | Count (v1) | Reserved-only | Note |
|---|---|---|---|
| Wired tables | 1 | 4 | `notifications` wired; `notification_preferences`, `notification_deliveries`, `notification_digests`, `notification_router_errors` reserved. |
| Columns on wired table | 19 (21 counting housekeeping) | 0 | Per §5.22 count. |
| Columns on frozen tables | 0 | 0 | Zero touch. |
| Additive indexes | 8 (9 including actor-partial I-9) | 0 (GIN deferred) | I-1 through I-8 in Wave 1; I-9 in Wave 2. |
| Additive CHECK constraints | 5 | 0 | `notifications_category_check`, `notifications_priority_check`, `notifications_delivery_state_check`, `notifications_channels_attempted_check`, `notifications_payload_size_check`. |
| Additive FKs | 4 | 0 | `recipient_profile_id`, composite `(project_id, workspace_id)`, `source_event_id`, `actor_profile_id`. |
| Composite FKs | 1 | 0 | `(project_id, workspace_id)` — reuses APP 003 project composite anchor unique. |
| Additive triggers | 4 | 0 | Router bridge (AFTER INSERT on `activity_events`), immutability (BEFORE UPDATE on `notifications`), RPC-gate (BEFORE UPDATE on `notifications`), set_updated_at (BEFORE UPDATE on `notifications`). |
| Modifications to frozen triggers | 0 | 0 | Every frozen trigger byte-identical. |
| Read RPCs | 6 | 0 | `list_notifications_inbox`, `list_notifications_unread`, `get_notification`, `get_notification_badge_count`, `get_notification_center`, `list_notifications_by_source`. |
| Write RPCs | 8 | 4 | Wired 8: mark_read/unread, mark_all_read, mark_bulk, dismiss/dismiss_bulk, archive/archive_bulk. Reserved 4: unarchive, set_preference, mute_category, snooze. |
| Extensions to frozen RPCs | 1 (strictly additive) | 0 | APP 010 performs exactly one `CREATE OR REPLACE` of the frozen `lign_has_capability(uuid, uuid, text)` function. Strictly additive: signature preserved; every existing capability key and role mapping byte-identical; only the `notification.*` keys (2 wired + 6 reserved) appended. No existing capability changes. No overload. No named-argument ambiguity. Per checklist C-2, byte-identical role-map preservation is guaranteed. |
| Wired capabilities | 2 | 6 | Wired: `notification.view`, `notification.manage`. Reserved: `notification.view_any`, `notification.announce`, `notification.ai_prioritize`, `notification.ai_summarize`, `notification.ai_digest`, `notification.preference`. |
| Emitted event types | 0 | 3 | Zero v1 emitters. Reserved: `notification.ai_prioritized`, `notification.ai_summarized`, `notification.digest_sent`. |
| Payload-key additions on frozen events | 0 | 0 | APP 010 adds no key to any frozen event's `subject_snapshot`. |
| Frozen RLS policies modified | 0 | 0 | Every frozen policy byte-identical. |
| New RLS policies | 4 | 0 | On `notifications` only. |
| Realtime publication changes | 0 | 0 | `notifications` OUT of `supabase_realtime` (APP 011 re-freeze required to add). |
| `qk` namespace additions | 7 key builders | 0 | Per §13.1. |
| DeepLinkResolver kinds added | 1 | 0 | `notification`. |
| NavRail items added | 1 | 0 | "Inbox". |
| Hotkey slots added | 4 | 0 | `N`, `Shift+N`, `E`, `Backspace`/`Delete`. |
| Page routes added | 1 | 0 | `/workspace/:ws_id/inbox`. |
| Deep-link routes added | 1 | 0 | `/deep/notification/:id`. |
| Wave 1 doc-diffs | 3 | 0 | EVENT_MODEL.md, PERMISSIONS.md, DOMAIN_MODEL.md — vocabulary locks. |

**Total backend surface additions:** 1 table + 19 columns + 8+1 indexes + 5 CHECK + 4 FK + 4 triggers + 14 RPCs + 2 capabilities + 4 RLS policies. Zero frozen surface modified beyond the boundary-additive AFTER INSERT trigger on `activity_events` and the additive extension of `lign_has_capability`.

**Realtime:** OUT.

---

## 25. Applied review-finding pattern

The Backend Re-freeze Review cycle produced seven accepted findings. All are applied in this document; the authoritative summary lives in the Backend Re-freeze Report at the head of this document (§2 there). This section mirrors the APP 007/008/009 `Applied review-finding pattern` shape for cross-referencing.

| Finding | Severity | Location(s) updated | Rationale | Exact contract change | Compatibility impact | Applied |
|---|---|---|---|---|---|---|
| F-1 | CRITICAL | §10.1 `notifications_select` predicate; new subsection §2.12 | The previously referenced helper `lign_is_project_participant(project_id)` does not exist in the frozen baseline. | RLS `notifications_select` third predicate rewritten to `(project_id IS NULL OR public.lign_project_role(project_id) IS NOT NULL OR public.lign_is_workspace_admin(workspace_id))`. New §2.12 subsection enumerates every helper reference with frozen file + line range. | None — resolves an unresolved reference. | Yes |
| F-2 | HIGH | §9.1 body outline (step 1a); §9.1 "Behavior on `notification.*` events" bullet; §17.1 | Prior loop-guard relied solely on routing-table absence. Explicit in-body guard is safer. | Body-outline step 1a added: `IF NEW.event_type LIKE 'notification.%' THEN RETURN NEW; END IF;`. Documented as the primary loop-guard; routing-table absence is the secondary defense. | None — additive documentation of an in-body guard. | Yes |
| F-3 | HIGH | §2 (Backend conventions house rules); §8 (RPC surface preamble); §11.3 (capability wiring); §20.1 and §20.3 (backwards-compat guarantees); §24 (final backend delta summary) | Prior text ("zero extensions to frozen RPCs") contradicted §11.3's `lign_has_capability` reissue. | Every referenced section rewritten to state: "APP 010 performs exactly one `CREATE OR REPLACE` of the frozen `lign_has_capability(uuid, uuid, text)` function. Strictly additive: signature preserved; every existing capability key and role mapping byte-identical; only `notification.*` keys appended. No existing capability changes. No overload. No named-argument ambiguity. Per checklist C-2, byte-identical role-map preservation is guaranteed." | None — the semantics are unchanged; only contract wording is aligned. | Yes |
| F-4 | MEDIUM | §7.6 (I-7 justification); §17.3 (backend gap discussion); §16.7 (interaction note) | Prior "allows re-materialization" text implied an impossible v1 scenario. Framing A adopted. | §7.6 and §17.3 rewritten: the `WHERE archived_at IS NULL` predicate is defensive scaffolding for Wave 4 replay workers; unreachable in v1 traffic; included to lock the dedup contract shape before Wave 4 delivery workers ship. §16.7 interaction note aligned. | None — index definition unchanged. | Yes |
| F-5 | MEDIUM | §5.16 (payload keys); §15.1 (`list_notifications_inbox` return); §15.3 (`get_notification` return) | Two conflicting canonical positions for `actor_display_name` existed. Standardized on nested-in-`payload`. | §5.16 keeps `actor_display_name` inside `payload`. §15.1 return shape no longer enumerates a top-level `actor_display_name`. §15.3 no longer describes a denormalized copy. Clients read the name from `row.payload.actor_display_name`. | None — router already materializes `payload.actor_display_name`. | Yes |
| F-6 | LOW | §12.4 Workspace/Stakeholder/Invitation event cluster header; §12.4 wired-consumer paths sentence | Header claimed "(7)" but 9 events enumerated. Total recounted. | Header changed to "(9)". Total recounted to "approximately 34 wired consumer paths" with per-cluster arithmetic shown. | None — count/label correction only. | Yes |
| F-7 | LOW | §1.1; §3.3; §9.6; §20.5; ordering-constraint note in §9.1 | Proposal mis-named the frozen trigger; the baseline installs two triggers sharing a function. | Every mention now cites "the frozen `activity_events_no_update` and `activity_events_no_delete` triggers, which share the `enforce_activity_events_append_only` function." | None — narrative correction only; no DDL change. | Yes |

---

**APP 010 Backend is frozen.**
