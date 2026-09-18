# APP 007 Final Certification

**Permanent governance record for APP 007 — Approvals.**

This document certifies the collective status of the APP 007 slice as permanently frozen. Authoritative sources:

- [`docs/APP_007_FREEZE_INDEX.md`](../APP_007_FREEZE_INDEX.md)
- [`docs/APP_007_BACKEND_PROPOSAL.md`](../APP_007_BACKEND_PROPOSAL.md)
- APP 007 Backend Re-freeze Report
- APP 007 Implementation Report
- APP 007 Final Architecture Audit Report

---

## 1. Overall status

- **Version:** v1.0
- **Certification date:** 2026-08-04
- **Implementation status:** Complete. All Wave 1–3 backend surface deployed to project `hsfporioghapwghrvvzd` via Migrations 032–037. All frontend surfaces implemented, typechecked, built, and integrated with APP 002–006.
- **Freeze status:** **Permanently frozen.**

APP 007 has completed the full governance cycle: Architecture Freeze → Backend Proposal → Backend Re-freeze Review → Backend Re-freeze Report → Implementation → Implementation Report → Final Architecture Audit. Every CRITICAL finding was resolved before implementation began; every HIGH finding was applied in the rewritten backend contract; every empirical smoke test passed against the deployed database. No open blockers remain. APP 001–006 contracts remain intact.

---

## 2. Architecture verification

The deployed architecture matches the frozen contract along every dimension audited by the Final Architecture Audit Report:

- **Approval lifecycle**: 8-value status enum (`draft`, `pending`, `in_progress`, `approved`, `rejected`, `cancelled`, `expired`, `superseded`) with `approved` locked as terminal-immutable (F-10.1).
- **Chain model**: `supersedes_approval_request_id` + `root_approval_request_id` on `approval_requests`, backed by the `approval_requests_chain_immutable` trigger. The trigger extends coverage to `related_review_id` per F-10.2.
- **Chain-init discipline (F-7.1)**: both `create_approval_draft` and `supersede_approval_request` pre-compute `gen_random_uuid()` and INSERT with `root_approval_request_id` inline. No RPC performs a post-INSERT UPDATE of any chain column. APP 006 T-CRIT-1 does not recur.
- **Supersession ordering (F-1.1)**: `supersede_approval_request` executes `SELECT ... FOR UPDATE` on the old row, transitions it to `superseded`, then INSERTs the new row as `draft` — cannot conflict with the frozen `approval_requests_active_target_key` partial unique index (which excludes both `draft` and `superseded`).
- **Approver roster**: `approval_request_approvers` gains `required`, `veto_power`, `removed_at`, `removed_reason`. Sequential-policy ordering (F-1.2) is enforced by `create_approval_draft` / `supersede_approval_request` with distinct `sort_order` values or `errcode 22023`.
- **Response model**: `approval_responses.decision` widened additively to include `abstained` (F-2.1) while preserving `changes_requested` at the enum-CHECK level for legacy read compatibility. Mandatory reason (3–2000 chars) enforced by the widened `comment` CHECK (F-2.2). Frozen response-immutability triggers (`approval_responses_no_update`, `approval_responses_no_delete`) remain ENABLED post-migration. Veto-cast consistency enforced via `approval_responses_veto_cast_consistency_check`.
- **Requester-cannot-self-approve (F-2.4 / D-11)**: enforced at the DB boundary by `approval_responses_no_self_approve` BEFORE INSERT trigger; alphabetical trigger ordering ensures it fires before `approval_responses_slot_coherence`.
- **Separation from Reviews**: `related_review_id` is a loose composite FK to `(reviews.id, reviews.workspace_id)` with `ON DELETE SET NULL`. Approvals have no rounds, no coordinator role, no review-borrowed vocabulary. No `round_number` key appears in any approval event payload (F-4.3).
- **Release compatibility**: the frozen `enforce_release_ready` trigger (APP 009 anchor) is unmodified; `approved` is terminal, and `get_approval_readiness` exposes `outcome_at` for `outcome_at desc` latest-approval discovery.

---

## 3. Backend contract verification

**Migrations recorded in `supabase_migrations.schema_migrations`:**

| Migration | Purpose |
|---|---|
| `20260804125736_app_007_approvals_schema` | Columns, enum widening, CHECK constraints, composite-tenancy FKs, indexes, chain-immutable + no-self-approve triggers |
| `20260804125820_app_007_approvals_authz_and_rpcs` | `lign_has_capability` extended additively; `set_updated_at` trigger on `approval_request_approvers` |
| `20260804125920_app_007_write_rpcs` | `create_approval_draft`, `send_approval_request` |
| `20260804130049_app_007_respond_and_supersede` | Extended `respond_to_approval` (4-arg overload with `abstained`, veto arithmetic, outcome payload extension); `supersede_approval_request` |
| `20260804130150_app_007_cancel_expire_roster_rpcs` | Extended `cancel_approval` (3-arg overload); `expire_approval`; roster mutation RPCs |
| `20260804130319_app_007_read_rpcs` | Dashboard, detail, chain, per-version list, readiness, inbox, metrics |

**Schema surface (per Final Architecture Audit):**

- **Tables added:** 0. Zero new tables (bookmarks + saved views reused from APP 006).
- **Columns added:** 12 (6 on `approval_requests`, 4 on `approval_request_approvers`, 2 on `approval_responses`).
- **Indexes added:** 12 (all new FKs covered; dashboard + cron + throughput indexes).
- **CHECK constraints:** 14 additive/revised (chain integrity, quorum, cancellation reason, comment reason, veto-cast consistency, removal pair, widened status/policy/decision).
- **FKs:** 3 composite-tenancy (supersedes/root/related_review, each paired with `workspace_id`).
- **Triggers:** 3 new (`approval_requests_chain_immutable`, `approval_responses_no_self_approve`, `approval_request_approvers_set_updated_at`); every frozen approvals trigger enabled and preserved.
- **RLS:** unchanged. Three frozen SELECT policies gated by `approval.view`; zero WRITE policies (RPC-only).

**RPCs (12 write, 8 read; every one SECURITY DEFINER + `search_path=''` + REVOKE-from-public/anon/authenticated + GRANT EXECUTE to `authenticated,service_role`):**

Write: `create_approval_draft`, `send_approval_request`, `respond_to_approval` (both frozen 3-arg and new 4-arg overloads), `supersede_approval_request`, `cancel_approval` (both frozen 2-arg and new 3-arg overloads), `expire_approval`, `add_approver`, `remove_approver`, `set_approver_required`, `set_approver_veto_power`.

Read: `list_approvals_dashboard`, `get_approval`, `get_approval_chain`, `list_approvals_for_version`, `get_approval_readiness(p_version_id uuid)`, `get_approval_inbox_count`, `get_project_approval_metrics`, `get_workspace_approval_metrics`.

**Capabilities added (3):** `approval.veto` (default: lead), `approval.expire` (default: lead + workspace-admin override), `approval.supersede` (default: lead + contributor). Every prior capability key byte-identical.

**Events:**

- New emitted: `approval.sent`, `approval.superseded`, `approval.expired`.
- Payload-extended (frozen names, additive keys): `approval.requested`, `approval.responded`, `approval.cancelled`, `approval.approved`, `approval.rejected`.
- RESERVED (past-tense, not emitted in APP 007): `approval.deadline_approached`.

---

## 4. Approved architectural decisions

The following decisions from the freeze cycle are ratified and locked:

1. **Zero new tables.** APP 007 reuses APP 006's `user_bookmarks` and `user_saved_views` infrastructure with entity-kind discriminators.
2. **`approved` requests are terminal-immutable.** Supersession is only permitted from `pending` or `in_progress` (F-10.1). APP 009 discovers "latest approval" via `outcome_at desc`.
3. **`abstained` is a new decision value; `changes_requested` is preserved for legacy reads only.** New RPCs reject `changes_requested` at input; the enum CHECK retains the legacy value for historical rows (F-2.1).
4. **Mandatory response reason via widened `comment` CHECK.** No `decision_reason` column was added (F-2.2).
5. **Requester-cannot-self-approve is enforced at the DB boundary**, not only in the RPC (F-2.4 / D-11).
6. **Chain-init discipline is a governance rule, not a preference.** Pre-compute UUID; INSERT chain columns inline; never post-INSERT UPDATE. The chain-immutability trigger is the enforcement mechanism (F-7.1 / F-10.2).
7. **Sequential-policy ordering enforced by RPC-side validation** (distinct `sort_order` 0..N-1); no DB-level per-request uniqueness added in Wave 1 (deferred as a v2 candidate).
8. **No coordinator role for approvals.** Deliberate simplification from APP 006. Approvals have no rounds.
9. **`related_review_id` is a loose FK, part of the chain-immutable column set.** Set-at-creation-only.
10. **Policy vocabulary widened additively.** `any|all` preserved alongside new `single|unanimous|majority|quorum|sequential`; outcome arithmetic treats semantically-equivalent pairs identically.
11. **RESERVED event names lock past-tense grammar.** `approval.deadline_approached` — never `deadline_approaching` (F-4.2).
12. **Frozen 3-arg `respond_to_approval` and 2-arg `cancel_approval` overloads are preserved** for Option A additive-tail backward compatibility.

---

## 5. Files created

**Backend migrations (6):**

- `supabase/migrations/20260804125736_app_007_approvals_schema.sql`
- `supabase/migrations/20260804125820_app_007_approvals_authz_and_rpcs.sql`
- `supabase/migrations/20260804125920_app_007_write_rpcs.sql`
- `supabase/migrations/20260804130049_app_007_respond_and_supersede.sql`
- `supabase/migrations/20260804130150_app_007_cancel_expire_roster_rpcs.sql`
- `supabase/migrations/20260804130319_app_007_read_rpcs.sql`

**Frontend (all under `app/src/features/approvals/`):**

- `queries.ts`, `mutations.ts`
- `ApprovalFilterBar.tsx`, `ApprovalCard.tsx`, `ApprovalsDashboardBody.tsx`
- `WorkspaceApprovalsScreen.tsx`, `ProjectApprovalsScreen.tsx`, `ApprovalDetailScreen.tsx`
- `ApprovalActions.tsx`, `ApprovalRosterEditor.tsx`, `CreateApprovalDialog.tsx`, `ApprovalsTabPanel.tsx`

**Governance:**

- `docs/APP_007_FREEZE_INDEX.md`
- `docs/APP_007_BACKEND_PROPOSAL.md`
- `docs/freeze/APP_007_FINAL_CERTIFICATION.md` (this document)

---

## 6. Files modified

All modifications are additive and preserve existing behavior for prior slices:

- `app/src/types/capabilities.ts` — added `approval.veto`, `approval.expire`, `approval.supersede` to `CAPABILITY_KEYS`.
- `app/src/features/shared/StateBadge.tsx` — additive workflow-state members (`pending`, `approved`, `rejected`, `expired`, `superseded`).
- `app/src/features/comments/useCopyLink.ts` — `LinkKind` union extended with `'approval' | 'approver'`.
- `app/src/features/design-workspace/useWorkspaceHotkeys.ts` — new handlers `onApprove` (`A`), `onReject` (`X`), `onAbstain` (`Shift+A`).
- `app/src/lib/queryKeys.ts` — appended approval-namespaced keys.
- `app/src/features/shared/invalidate.ts` — appended `invalidateApprovalsLists`, `invalidateApproval`, `invalidateApprovalInbox`.
- `app/src/auth/DeepLinkResolver.tsx` — added real resolvers for `approval` and `approver` kinds (replaces APP 002 stubs).
- `app/src/router.tsx` — added three new routes plus `/deep/approver/:id`.

No APP 001–006 migration, RLS policy, RPC, capability key, event vocabulary entry, or public component API was removed, renamed, or semantically altered.

---

## 7. Backend surface summary

| Dimension | Count | Notes |
|---|---|---|
| Migrations | 6 | 032–037 in project `hsfporioghapwghrvvzd` |
| Tables added | 0 | Reuses APP 006 bookmark + saved-view infrastructure |
| Columns added | 12 | 6 requests + 4 approver-slots + 2 responses |
| Indexes added | 12 | All new FKs covered; dashboard + cron support |
| CHECK constraints | 14 | Additive/revised; chain, quorum, reason, veto, removal, enums |
| FKs added | 3 | All composite-tenancy `(child, workspace_id)` |
| Triggers added | 3 | Chain-immutable, no-self-approve, set_updated_at on approver slots |
| Frozen triggers preserved | 4 | Target eligibility, slot coherence, response no-update, response no-delete — all ENABLED |
| RLS policies added | 0 | Reads gated by frozen `approval.view`; writes RPC-only |
| RPCs added | 20 | 12 write + 8 read; every one SECURITY DEFINER + `search_path=''` |
| Frozen RPC overloads preserved | 2 | `respond_to_approval(uuid,text,text)`, `cancel_approval(uuid,text)` |
| Capabilities added | 3 | `approval.veto`, `approval.expire`, `approval.supersede` |
| New event types emitted | 3 | `approval.sent`, `approval.superseded`, `approval.expired` |
| Frozen event payload extensions | 5 | `approval.requested/responded/cancelled/approved/rejected` |
| RESERVED event names | 1 | `approval.deadline_approached` (past-tense) |

---

## 8. Query architecture

TanStack Query v5. Approval-namespaced keys append-only under the top-level namespace:

```
['approvals','list', wsId, projId, view, filters]
['approvals','ws-dashboard', wsId, view]
['approvals','proj-dashboard', projId, view]
['approvals','for-version', versionId]
['approval', requestId]
['approval', requestId, 'responses']
['approval', requestId, 'activity']
['approval','readiness', versionId]
['approval-chain', rootRequestId]
['approval-metrics', scope]
['approval-inbox-count', wsId]
['bookmarks', wsId, 'approval_request']   (reused, APP 006)
['saved-views', wsId, 'approvals']        (reused, APP 006)
['deep','approval', id]
['deep','approver', id]
```

No collision with APP 005 (`['comment', ...]`, `['annotation', ...]`) or APP 006 (`['review', ...]`, `['reviews', ...]`, `['review-chain', ...]`). Every mutation invalidates the correct combination of list-scope, detail, readiness, inbox, and (where applicable) bookmark/saved-view keys — verified by the Final Architecture Audit.

---

## 9. Routing

Router entries added to `app/src/router.tsx`:

| Path | Component | Notes |
|---|---|---|
| `/workspace/:ws_id/approvals` | `WorkspaceApprovalsScreen` | Workspace-scoped dashboard |
| `/workspace/:ws_id/project/:proj_id/approvals` | `ProjectApprovalsScreen` | Project-scoped dashboard |
| `/workspace/:ws_id/project/:proj_id/approval/:approval_id` | `ApprovalDetailScreen` | Detail + roster + chain |
| `/deep/approval/:id` | `DeepLinkResolver kind="approval"` | Promoted from APP 002 stub |
| `/deep/approver/:id` | `DeepLinkResolver kind="approver"` | New; forwards to detail with `?participant=` |

**URL parameters (owned by APP 007):**

- Dashboard: `?view`, `?status`, `?policy` (values enumerated in Freeze Index).
- Detail: `?tab` (`comments | decisions | files | activity`), `?participant`.
- Design Workspace context flag: `?approval=<id>`.

No collision with APP 003 `?discipline`, APP 005 `?comment/annotation`, APP 006 `?review`.

---

## 10. Reusable primitives

**Consumed unchanged from prior slices:**

- APP 002 shell primitives: `AuthGate`, `RootLayout`, `WorkspaceLayout`, `ProjectLayout`, `DeepLinkResolver`, `NavRail`, `qk` registry, `CAPABILITY_KEYS`.
- APP 005: `CommentsPanel` (embedded in Approval Detail Comments tab).
- APP 006: `RosterEditor` (composed by `ApprovalRosterEditor` without shape modification), `user_bookmarks`, `user_saved_views` tables + associated toggle/save RPCs (invoked with `entity_kind='approval_request'` and `scope='approvals'`).
- APP 006 dashboard pattern: filter chips, card layout, cursor pagination, keyboard shortcuts.

**New primitives introduced by APP 007 (approval-specific, not intended for cross-slice reuse in this wave):**

- `ApprovalFilterBar`, `ApprovalCard`, `ApprovalsDashboardBody`, `ApprovalActions`, `ApprovalRosterEditor`, `CreateApprovalDialog`, `ApprovalsTabPanel`.

---

## 11. Build verification

Recorded in the Implementation Report and re-confirmed by the Final Architecture Audit:

- `npm run typecheck`: **PASS** (zero errors).
- `npm run build`: **PASS** (1892 modules transformed; 1.97 s).
- Bundle: before `877,071 bytes` → after `913.12 kB` (256.15 kB gzip). Delta **+36.05 kB raw (~+11 kB gzip)**. Vite warning threshold unchanged from pre-APP-007 posture.
- Migration application: **PASS** — all 6 APP 007 migrations recorded in `supabase_migrations.schema_migrations`.

---

## 12. Advisor results

- **Security advisors:** zero ERROR advisors. WARN classes limited to `authenticated_security_definer_function_executable` (72 across the DB, matching the baseline established since APP 001 — every new APP 007 SECURITY DEFINER function correctly uses `search_path=''`, REVOKEs from `public/anon/authenticated`, and GRANTs EXECUTE only to `authenticated,service_role`) and one pre-existing `auth_leaked_password_protection` unrelated to APP 007. **No new issue class introduced.**
- **Performance advisors:** zero `unindexed_foreign_keys` on any APP 007 FK (all three composite FKs covered in the same migration). `unused_index` INFO lines for the 12 new APP 007 indexes match APP 006's post-freeze posture (freshly-created indexes with zero traffic; expected to clear once dashboards see load). **No new issue class introduced.**

---

## 13. APP 001–006 preservation

Every prior slice's contract is intact:

- **APP 001 — Domain Model.** 7-way comment target XOR arm preserved. Roles-as-capability-sets honored. No entity added, renamed, or redefined.
- **APP 002 — Application Shell.** Router, `qk` registry, `CAPABILITY_KEYS`, `DeepLinkResolver`, `useCopyLink`, `StateBadge`, `useWorkspaceHotkeys` all extended additively. Every existing route, key, capability, resolver, hotkey, and public component API preserved verbatim.
- **APP 003 — Projects, Disciplines & Design Workspace.** No file under `features/projects/`, `features/designs/`, or `features/design-workspace/` modified other than the additive hotkey handlers in `useWorkspaceHotkeys`.
- **APP 004 — Files & Viewer.** Viewer dispatcher, upload queue, hash worker, signed-URL cache, publish/discard workflows untouched. `FilesPanel` consumed read-only.
- **APP 005 — Comments & Annotations.** `CommentsPanel` embedded unmodified. The `target_approval_request_id` XOR arm frozen in APP 005 is the exact arm APP 007 links against — no schema drift.
- **APP 006 — Reviews.** Migrations 012 and 013 untouched; every `features/reviews/` file byte-identical. `user_bookmarks`, `user_saved_views`, and `RosterEditor` reused as external primitives (no shared source touched). `lign_has_capability` extended additively at the tail of each role's array, preserving every prior key byte-identically.

The frozen `approval_model` migration (2026-07-29) and `auth_007_approval_rls` migration (2026-07-29) remain live and authoritative. All frozen approval triggers (`approval_requests_target_eligibility`, `approval_responses_slot_coherence`, `approval_responses_no_update`, `approval_responses_no_delete`) are enabled (`tgenabled='O'`) and empirically fire as designed. The frozen `request_approval` RPC and the 3-arg `respond_to_approval` and 2-arg `cancel_approval` overloads coexist with the extended-tail overloads (Option A additive-tail discipline).

---

## 14. Non-blocking observations from the Final Architecture Audit

The Final Architecture Audit identified the following observations. All are informational and **do not affect the frozen implementation.** They are recorded here for transparency and future housekeeping consideration, not as freeze blockers.

- **F-1 (documentation drift):** The frozen 3-arg `respond_to_approval` overload delegates to the extended 4-arg body, which rejects `changes_requested` at input. `APP_007_BACKEND_PROPOSAL.md` §5.3 and §8.4 wording could be tightened to state that BOTH overloads reject at input while the enum CHECK preserves the value at the row level for read compatibility. Blast radius: zero — no rows exist with `decision='changes_requested'`; no frontend caller sends it.
- **F-2 (documentation drift):** The DB-level COMMENT on `public.approval_responses` still cites the pre-APP-007 decision vocabulary and omits `abstained`. Cosmetic; does not affect runtime behavior.
- **F-3 (documentation drift):** The deployed signature of `supersede_approval_request` differs cosmetically from the proposal §8.7 enumeration (drops redundant `p_deadline_at`, reorders identity arrays, appends `p_title`/`p_description`). All added params are defaulted; named-parameter callers are unaffected.
- **F-4 (maintenance note):** `approval_requests_policy_check` includes both the frozen `any|all` values and the new `single|unanimous|majority|quorum|sequential` values, with outcome arithmetic treating `('all','unanimous')` and `('any','single')` as equivalent pairs. This is per proposal §5.1's explicit design.
- **F-5 (dead code):** `app/src/auth/DeepLinkResolver.tsx` retains an unreachable `Placeholder` component from the APP 002 shell. Both `approval` and `approver` kinds short-circuit to real resolvers before it is reached.

None of these observations constitute a contract violation, a runtime bug, a cross-slice regression, or a maintenance risk that requires action prior to freeze. They may be addressed in a future housekeeping pass without amendment.

---

## 15. Freeze confirmations

- ✅ Every CRITICAL requirement from the APP 007 Backend Re-freeze Report is implemented and empirically verified (F-7.1 chain-init, F-1.1 supersede ordering, F-2.1 `abstained` semantics, F-10.1 `approved` terminal).
- ✅ Every HIGH requirement is implemented (F-2.2 widened comment CHECK, F-2.4 no-self-approve trigger, F-3.1 metadata-array ordering, F-4.1 event reclassification, F-4.2 past-tense RESERVED name, F-1.2 sequential uniqueness, F-7.2 redundant-trigger removal).
- ✅ Every MEDIUM and LOW documentation improvement is applied in the rewritten backend contract.
- ✅ Every backend contract item — schema, indexes, constraints, FKs, triggers, RLS, RPCs, capabilities, events — matches the frozen contract as verified by direct `pg_catalog` inspection.
- ✅ Every frontend contract item — routes, screens, primitives, query keys, mutations, URL parameters, deep links, keyboard shortcuts — matches the frozen contract as verified by file inspection.
- ✅ Every event vocabulary item matches the frozen contract. Past-tense verbs; no `round_number` in approval payloads; RESERVED name is `approval.deadline_approached`.
- ✅ Every capability matches the frozen contract. Three additive keys, default role maps as specified, prior capability role assignments byte-identical.
- ✅ Every RPC matches the frozen contract. SECURITY DEFINER + `search_path=''` + REVOKE/GRANT discipline verified on every function.
- ✅ APP 001–006 remain untouched except for approved additive extensions (§13).
- ✅ APP 007 introduces no unauthorized surface. No new tables. No unapproved capability keys. No unapproved event types. No route or query-key collisions.
- ✅ Empirical smoke tests pass: chain-immutable triggers fire on all three columns; no-self-approve trigger fires first (before slot_coherence) on properly-constructed fixtures; supersession succeeds through the frozen active-target unique index; `approved` cannot be superseded; sequential-policy duplicate `sort_order` rejected; response mandatory reason enforced; veto-cast consistency enforced; frozen response-immutability triggers ENABLED and functional.
- ✅ Build verification: typecheck PASS, build PASS, bundle delta within acceptable slope, all migrations applied.
- ✅ Advisor verification: zero ERROR advisors; only expected WARN classes; no new issue class introduced by APP 007.

---

**APP 007 is permanently frozen.**

This report becomes the authoritative certification document for APP 007. Future changes require an amendment and re-freeze.
