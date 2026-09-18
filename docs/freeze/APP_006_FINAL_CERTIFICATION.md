# APP 006 Final Certification

**Permanent governance record for APP 006 — Reviews.**

This document supersedes no earlier freeze document; it certifies their collective status. Authoritative sources for APP 006:

- [`docs/APP_006_FREEZE_INDEX.md`](../APP_006_FREEZE_INDEX.md)
- [`docs/APP_006_BACKEND_PROPOSAL.md`](../APP_006_BACKEND_PROPOSAL.md)
- APP 006 Backend Re-freeze Report
- APP 006 Implementation Report
- APP 006 Freeze Report
- APP 006 Final Architecture Audit
- APP 006 Critical Fix Report

---

## 1. Status

- **Version:** v1.0
- **Certification date:** 2026-08-08
- **Implementation status:** Complete. All Wave 1–3 backend surface deployed to project `hsfporioghapwghrvvzd` via Migrations 012 + 013 (and an audit-mandated `create_review` initialization patch verified by functional smoke test). All frontend surfaces implemented, typechecked, built, and integrated with APP 002–005.
- **Freeze status:** **Permanently frozen.**

APP 006 has completed the full governance cycle: Architecture Freeze → Backend Re-freeze → Implementation → Final Architecture Audit → Critical Fix Verification → Functional Smoke Testing. No open blockers remain. All eight assertions of the post-fix smoke test passed. Every APP 001–005 contract remains intact.

---

## 2. Scope

APP 006 owns, and only owns, the following:

- **Review lifecycle** — the 7-state enum (`draft`, `ready_for_review`, `open`, `in_progress`, `waiting`, `completed`, `cancelled`) and every sanctioned transition path between them, including force-completion, cancellation with mandatory reason, and pause/resume via `set_review_state`.
- **Review rounds** — the linked-review-row chain model (`round_number`, `parent_review_id`, `root_review_id`), the chain-immutability trigger, and the reopen semantics that create Round N+1 as a new row.
- **Reviewer model** — the member/stakeholder XOR identity path (frozen), the required/optional distinction, sequence indexing, soft-remove-on-response semantics, and the coordinator-distinct-from-owner concept.
- **Reviewer policies** — parallel (default), sequential, quorum. Enforced via `reviews.policy` + `reviews.quorum_min` + `review_participants.sequence_index`.
- **Review dashboards** — the workspace-level and project-level dashboard surfaces, their six views (assigned_to_me, waiting_on_others, overdue, completed, recent, bookmarks), and the RPC-driven pagination + filter grammar.
- **Review Detail** — the full-page Review Detail route, its header + actions + version card + timeline + roster editor + tabbed content (Comments / Participants / Activity / Files).
- **Review metrics** — per-review durations, response distribution, open-comment count, newer-version detection, plus workspace/project outstanding + overdue aggregates. All derived server-side.
- **Review capabilities** — `review.coordinate` and `review.reopen` (added), used alongside the frozen `review.view / create / participate / complete`.
- **Review routing** — the four new review routes and the reviewer deep-link route (plus the promotion of `/deep/review/:id` from placeholder to real resolver).
- **Review query architecture** — the ten new append-only query keys and their invalidation helpers.
- **Review events** — the five newly-emitted event types (`review.reopened`, `review.state_changed`, `review.reviewer_added`, `review.reviewer_removed`, `review.reviewer_reassigned`), the four payload extensions to frozen events, and the two RESERVED event names (`review.deadline_approached`, `review.deadline_passed`) reserved for the future cron slice.
- **Review backend contract** — Migrations 012 and 013 in their entirety, plus the `create_review` initialization patch.

Anything outside this scope belongs to a different slice or has been explicitly deferred (see §7).

---

## 3. Dependencies

APP 006 consumes and depends on the frozen contracts of every prior slice. It extends them **additively** without modifying any of their public API, behavior, or invariants.

- **APP 001 — Domain Model.** APP 006 honors the Review + ReviewerAssignment entity semantics, the 7-way XOR comment target, the immutability rules on Version and Annotation, and the roles-as-capability-sets principle. No entity is added, renamed, or redefined.
- **APP 002 — Application Shell.** APP 006 extends the router with additive route entries, the `qk` registry with append-only keys, the `CAPABILITY_KEYS` client array with two additive capabilities, and `DeepLinkResolver` with two additive kinds. `NavItem` receives one backward-compatible optional prop (`badge`). `NavRail` receives additive workspace + project entries. Every existing shell surface is bit-for-bit unchanged in behavior.
- **APP 003 — Projects & Design Workspace.** APP 006 does not modify any APP 003 screen. Reviews integrate into the workspace via a right-panel tab that APP 005 had reserved. Two additive props (`canCreateReview`, `activeVersionPublished`) are threaded through `DesignWorkspaceScreen` to `RightPanel`; every existing prop and behavior is preserved.
- **APP 004 — Files & Viewer.** APP 006 does not modify the viewer dispatcher, upload queue, hash worker, signed-URL cache, publish/discard flows, or any file-related component. The Review Detail Files tab composes `FilesPanel` unchanged.
- **APP 005 — Comments & Annotations.** APP 006 composes `CommentsPanel` unchanged in the Review Detail Comments tab. `StateBadge`, `useCopyLink`, `useWorkspaceHotkeys` are extended additively — every existing call site continues to behave identically because the extensions default to no-op for prior consumers.

**Certification:** APP 006 extends APP 001–005 additively without modifying their contracts.

---

## 4. Backend Contract

Frozen backend surface, in summary form:

- **Migrations:** 012 (`app_006_reviews_schema`) and 013 (`app_006_reviews_authz_and_rpcs`), plus the `create_review` initialization patch applied under the migration name `app_006_create_review_root_init_fix`. All applied cleanly to `hsfporioghapwghrvvzd`. Migration file on disk reflects the deployed state.
- **Schema additions:** 12 new columns on frozen tables (8 on `reviews`, 4 on `review_participants`), 2 new tables (`user_bookmarks`, `user_saved_views`). Every addition is additive; no frozen column was altered.
- **Indexes:** 12 new indexes covering every new FK, dashboard sort/filter predicate, and inbox query pattern. Frozen "FK gets a covering index in the same migration" house rule honored.
- **Constraints:** 1 CHECK enum expansion (`reviews.status` from 5 → 7 values), 5 new CHECK constraints (chain self-consistency, root self-reference, policy consistency, quorum-min positivity, cancellation-reason presence, sequence-index non-negativity, removal-pair tight form), and 5 new composite FKs (chain parent/root, coordinator, bookmarks tenancy, saved-views tenancy).
- **Triggers:** 1 new trigger (`reviews_chain_immutable`, defense-in-depth) and the standard `set_updated_at` on the new `user_saved_views` table.
- **RLS:** 2 new policy sets on the 2 new tables. Zero changes to any existing frozen policy.
- **RPCs:** 16 new SECURITY DEFINER RPCs (open_review, set_review_state, reopen_review, add/remove/reassign/set_reviewer_required, toggle_bookmark, save/delete_dashboard_view, list_reviews_dashboard, get_review, get_review_chain, get_review_inbox_count, get_project_review_metrics, get_workspace_review_metrics) plus additive-tail-param extensions to `create_review` and `complete_review`. Frozen 9-arg and 2-arg overloads preserved for backwards compatibility.
- **Capabilities:** 2 new (`review.coordinate`, `review.reopen`), integrated into the frozen role-preset map (`lead`, `contributor`, `reviewer`, `approver`, `observer`).
- **Events:** 5 new emitted types, 4 additive payload extensions to existing frozen types, 2 RESERVED type names (name-locked, no emitter implemented in APP 006).

Every backend addition is confined to the set enumerated in the Backend Re-freeze proposal. Nothing outside the approved surface was introduced.

---

## 5. Frontend Contract

Frozen frontend surface, in summary form:

- **Routes:** `/workspace/:ws_id/reviews`, `/workspace/:ws_id/project/:proj_id/reviews`, `/workspace/:ws_id/project/:proj_id/review/:review_id`, `.../round/:round_number`, and `/deep/reviewer/:id`. `/deep/review/:id` upgraded from placeholder to real resolver.
- **Query keys:** ten append-only additions (`reviewsList`, `reviewsWorkspaceDashboard`, `reviewsProjectDashboard`, `review`, `reviewChain`, `reviewParticipants`, `reviewMetrics`, `reviewInboxCount`, `savedViews`, `bookmarks`) plus three invalidation helpers (`invalidateReviewsLists`, `invalidateReview`, `invalidateReviewInbox`).
- **Reusable components introduced by APP 006:** `RosterEditor`, `ReviewActions`, `ReviewsDashboardBody`, `ReviewFilterBar`, `ReviewCard`, `ReviewsTabPanel`, `CreateReviewDialog`.
- **Dashboard:** workspace and project screens rendered by `WorkspaceReviewsScreen` / `ProjectReviewsScreen`, both consuming the shared `ReviewsDashboardBody`. Filter bar, search, six saved views, and metrics strip (project scope) delivered.
- **Review Detail:** full-page screen (`ReviewDetailScreen`) with header + actions + newer-version banner + version card + timeline + roster editor + tabbed content (Comments / Participants / Activity / Files).
- **Design Workspace integration:** the previously-disabled `Reviews` tab in APP 005's `RightPanel` is now active. `ReviewsTabPanel` shows per-version review cards and offers a "Start review on this version" affordance gated on `review.create` and version-published status.
- **Navigation:** `NavRail` gains workspace-mode and project-mode `Reviews` entries (icon `ClipboardCheck`) with an inbox badge sourced from `useReviewInboxCount`.
- **Deep links:** `/deep/review/:id` and `/deep/reviewer/:id` resolve to the correct workspace URLs. `useCopyLink` extended additively with `'review'` and `'reviewer'` kinds.
- **URL grammar:** APP 006 owns `?view`, `?status`, `?owner`, `?reviewer`, `?due`, `?round`, `?participant`, `?tab=comments|participants|activity|files`, `?review=<id>`. APP 003 (`?from`, `?discipline`) and APP 005 (`?comment`, `?annotation`, `?comments`) parameters remain unchanged and are honored where they intersect.

---

## 6. Verification

Every verification step required by the freeze governance cycle has been completed and passed:

- **Typecheck:** `npm run typecheck` → EXIT 0.
- **Production build:** `npm run build` → completed in 2.03s; bundle 877 KB (251 KB gzip); +11 KB gzip delta from APP 005.
- **Backend migration success:** Migrations 012 and 013 applied cleanly to `hsfporioghapwghrvvzd` in idempotent chunks; all 16 new RPCs verified via `pg_proc` listing; all 12 new columns verified via `information_schema.columns`; both new tables verified via table listing; chain-immutability trigger verified via `pg_proc` source inspection.
- **Functional smoke tests:** eight assertions executed against the live schema after the critical-fix patch:
  1. Single-INSERT initialization of Round 1 succeeds — **PASS**
  2. `round_number == 1` — **PASS**
  3. `parent_review_id IS NULL` — **PASS**
  4. `root_review_id = self` — **PASS**
  5. Post-creation UPDATE of `round_number` rejected — **PASS**
  6. Post-creation UPDATE of `parent_review_id` rejected — **PASS**
  7. Post-creation UPDATE of `root_review_id` rejected — **PASS**
  8. Round 2 chain INSERT (parent + root inline) succeeds — **PASS**
- **Advisor results:** 59 total lints. 40 pre-existing (39 SECURITY DEFINER on frozen RPCs + 1 auth config notice). 19 net-new (all `authenticated_security_definer_function_executable` on the new APP 006 RPCs — the same frozen platform pattern that governs every RPC in LIGN since AUTH 001). **Zero new warning classes. Zero unexpected security issues.**
- **Critical fix verification:** T-CRIT-1 (chain-immutability trigger vs. `create_review` initialization) was empirically reproduced, resolved with the smallest possible fix (pre-computed id, single-INSERT initialization), and re-verified with the full 8-assertion smoke suite. The chain-immutability trigger remains bit-for-bit identical to Migration 012; the chain model, RPC API, and every other APP 006 surface are unchanged.

---

## 7. Deferred Items

The following are **intentionally deferred** by the approved freeze contract. They are not outstanding defects, not open bugs, and not blockers to certification. Each will be addressed by its own future slice or by an explicit APP 006 amendment.

- **AI extension seams** — reserved as composition slots in Freeze Index §21; no AI code implemented in APP 006 per contract.
- **Realtime subscriptions** — channel-name contract defined in Freeze Index §23; subscription implementation belongs to APP 011.
- **Scheduled deadline emitters** — event type names `review.deadline_approached` and `review.deadline_passed` frozen in the vocabulary; the cron/edge-function emitter belongs to the future cron slice (outside APP 006 scope).
- **Workspace-shared saved views** — `user_saved_views.visibility='workspace'` reserved for v2; APP 006 v1 enforces `visibility='private'` at the RLS layer.
- **Optional §9.2 and §9.3 triggers** — `review_participants_response_terminal_gate` and `reviews_sequential_policy_gate` marked Medium in the Backend Proposal and deferred to Wave 2 opt-in defense; RPC enforcement provides the primary path.
- **Multi-asset reviews and Review Bundles** — v2 per D-10; APP 006 v1 ships single-asset single-version scope.
- **`review.reviewer_responded` `note_snippet` payload extension** — Medium in Backend Proposal §10.3; deferred without impact.
- **Cross-slice invalidation of review metrics from APP 005 comment mutations** — Freeze Index §18 hook; deferred as non-blocking (dashboard `open_comment_count` may show stale values until a manual refetch).
- **Workspace-level analytics** — v2 per Freeze Index §14.
- **Multi-select dashboard filters** — v2 per Freeze Index §9.

All deferrals are explicit and documented. None represents a defect.

---

## 8. Amendment Policy

**APP 006 is permanently frozen.** No implementation may modify APP 006 directly.

Future changes to any APP 006 surface — architecture, backend contract, event vocabulary, capability model, routing grammar, query architecture, ownership boundaries, or schema surface — require an approved amendment document following the sequence:

```
docs/freeze/APP_006_AMENDMENT_001.md
docs/freeze/APP_006_AMENDMENT_002.md
...
```

Each amendment must:

1. State the specific frozen surface being amended and cite the section of this certification (or the underlying freeze documents) that defines the current contract.
2. Preserve backwards compatibility with all APP 001–005 contracts.
3. Preserve backwards compatibility with the existing APP 006 contract unless the amendment explicitly re-freezes the affected surface with a new version identifier (v1.1, v2.0, etc.).
4. Follow the full governance cycle: Architecture Amendment Review → Backend Re-freeze (if backend surfaces are touched) → Implementation → Post-implementation Verification → Amendment Certification.
5. Update this certification's status section with the amendment reference and re-freeze version.

Any change to an APP 006 surface without an approved and certified amendment is a **contract violation**.

---

## 9. Certification

**APP 006 Reviews v1.0 is permanently frozen.**

Future application slices (APP 007+) must extend APP 006 rather than modify it.

No architectural contracts, backend contracts, event vocabulary, capability model, routing grammar, query architecture, ownership boundaries, or schema surface may change without an approved APP 006 amendment and re-freeze.

This document is the final certification record for APP 006 Reviews v1.0.
