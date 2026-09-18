# APP 006 — Freeze Index

**Canonical reference for the Lign review system.**

Implementation has not started. This document consolidates every approved section of the APP 006 architecture review into one navigational reference. It introduces no new decisions and reinterprets no prior freeze. Sections marked *"requires backend re-freeze"* are gated on the additions enumerated in §26 and are not blockers for the architecture freeze itself — only for their respective slice of the implementation.

---

## 1. Purpose

Transform Lign from a collaboration platform into a professional design-review platform capable of scaling to enterprise workflows (Autodesk Construction Cloud, Bluebeam Studio, Figma-review class). APP 006 owns the review lifecycle end-to-end and provides the foundation on which APP 007 (Approvals), APP 008 (Requirements), APP 009 (Releases), APP 010 (Notifications), and APP 011 (Realtime) will build.

---

## 2. Scope

**In:** Draft creation, roster assembly, opening, reviewer response cycle, rounds, completion, cancellation, reopen, roster mutation (add/remove/reassign), workspace + project dashboards + personal inbox, Review Detail screen, Design Workspace right-panel Reviews tab, deep links, capability additions, metrics surface, event vocabulary for APP 010, subscription channels for APP 011, AI extension seams.

**Out (explicitly deferred to other slices):** Approvals workflow, Requirements UI, Releases, Notifications delivery, Realtime subscription implementation, AI implementation, multi-asset review scope (v2), Review Bundles (v2), collection/discipline scope for reviews (v2), workspace-level analytics (v2), scheduled `deadline_approached` / `deadline_passed` emitters (backend cron slice), version-diff engine.

---

## 3. Domain ownership

Canonical owner of:

- Review lifecycle (states, transitions, capability gates).
- Rounds model (linked-review-row chain).
- Reviewer roster and policies (parallel / sequential / quorum).
- Dashboard grammar (views, filters, columns).
- Review Detail screen and its URL structure.
- `review.coordinate` and `review.reopen` capabilities.
- Review-related deep-link kinds and URL parameters.
- Review-related metrics contract (server-side derivation).
- Event subscription channel names for APP 011.

Not-owned surfaces APP 006 only consumes: comments/annotations (APP 005), file/version model (APP 004), project/collection/discipline model (APP 003), shell/router/capability primer/qk conventions (APP 002), domain-model invariants (APP 001), storage layer (STORAGE 001–004).

---

## 4. Lifecycle

Enterprise-facing state graph (7 nodes):

```
draft → ready_for_review → open → in_progress ↔ waiting
                              ↓         ↓          ↓
                         cancelled   completed → (Round N+1 as new row)
```

Terminal states: `completed`, `cancelled`. Reopen is not a reversal — it creates a fresh review row in `draft` state, linked via `parent_review_id`.

Frozen 5-state enum (draft/open/in_progress/completed/cancelled) is a strict subset of the enterprise graph. `ready_for_review` and `waiting` require backend re-freeze (see G-1) — until then, they collapse client-side into `draft` and `in_progress` respectively with a UI badge distinction.

---

## 5. State machine

| From | To | Actor | Capability | Reversible | Frozen path | Gap |
|---|---|---|---|---|---|---|
| ∅ | draft | Any project participant | `review.create` | Yes (cancel) | `create_review` (p_open=false) | — |
| draft | ready_for_review | Owner / coordinator | `review.create` | Yes | — | G-1 |
| ready_for_review | open | Coordinator | `review.create` | No | — | G-2 |
| draft | open | Coordinator | `review.create` | No | `create_review` (p_open=true) | — |
| open | in_progress | Assigned reviewer | `review.participate` | No (auto) | `respond_to_review` | — |
| in_progress | waiting | Coordinator | `review.coordinate` | Yes | — | G-1, G-8 |
| waiting | in_progress | Coordinator | `review.coordinate` | Yes | — | G-1, G-8 |
| open / in_progress / waiting | completed | Coordinator | `review.complete` | No | `complete_review` (terminal='completed') | — |
| any non-terminal | cancelled | Owner or coordinator | `review.complete` | No | `complete_review` (terminal='cancelled') | — |
| completed | Round N+1 (new row) | Owner / coordinator | `review.reopen` | New row; prior preserved | — | G-3, G-4, G-16, G-24 |

Workspace admin can override any transition via `lign_is_workspace_admin` predicate in the RPCs (matches PERMISSIONS.md §5). Force-completion emits event with `payload.forced = true`.

---

## 6. Review rounds

**Model:** each round is a first-class linked review row.

New review columns required:
- `round_number int not null default 1`
- `parent_review_id uuid null` (composite FK to prior review in chain)
- `root_review_id uuid null` (self-reference; convenience for chain lookups)

**Semantics:**
- Reopen creates a new row; old row remains terminal with all its comments and history intact.
- Each round can target a different version. Round 1 on v3 → author uploads v4 → Round 2 on v4. Primary enterprise loop.
- A review chain reports on the `root_review_id`. Dashboard lists show one row per chain with round count.
- Comments on Round N are locked by the frozen `edit_own_comment` gate. New comments belong to Round N+1.
- Round-level events reuse existing `review.*` types with `round_number` in payload — no new event types for rounds themselves.
- Optional per-project `max_open_rounds` (G-6, deferred).

---

## 7. Review scope

**v1 (ships with APP 006):**
- **Entire version** — frozen backend anchors one version.
- **Entire asset** — implicit via the version's asset.
- **Specific files** — filter within the review's version.
- **Specific annotations** — pins on the review's version files (annotations are already file-anchored per APP 005).

**v2 (requires backend re-freeze):**
- **Multiple assets in one review** — G-11.
- **Collection-scoped reviews** — G-12.
- **Discipline-scoped reviews** — G-13.
- **Batch review / Review Bundles** — G-14.

**v1 workaround for grouping:** client-side "Review Bundle" *view* — group by root chain or shared tag — without a backend entity.

---

## 8. Reviewer model

**Identity paths (frozen):** `workspace_member_id` XOR `stakeholder_id` on `review_participants`. Guests are stakeholders with observer role — no new identity type.

**Response vocabulary (frozen):** `pending`, `commented`, `signed_off`, `declined`.

**Required vs optional:** `required boolean not null default true` on `review_participants` (G-7). Required reviewers block completion. Optional are courtesy-notified.

**Policy (G-8, G-15):**
- `reviews.policy text` ∈ `{parallel, sequential, quorum}` (default `parallel`).
- `reviews.quorum_min int null` (used only when `policy = 'quorum'`).
- `review_participants.sequence_index int not null default 0` (used only when `policy = 'sequential'`).

**Roles (G-5):**
- **Owner** = `reviews.created_by_profile_id` (frozen).
- **Coordinator** = `reviews.coordinator_profile_id` (new, nullable, falls back to owner).
- **Reviewer** = row on `review_participants`.
- **Observer** = anyone with `review.view` who is not on the roster.

**Roster mutation (G-9, G-10):** new RPCs `add_reviewer`, `remove_reviewer`, `reassign_reviewer`, `set_reviewer_required`. Gated by new capability `review.coordinate` (G-16). Remove refuses on participants who already responded (soft-mark).

**Late reviewers** inherit current state and respond as if in the original roster.

---

## 9. Dashboard architecture

Two levels:
- **Workspace dashboard** — `/workspace/:ws_id/reviews`. Cross-project inbox for caller.
- **Project dashboard** — `/workspace/:ws_id/project/:proj_id/reviews`. Project-scoped.

**Views (each a saved-view tab):**
- Assigned to me — pending row on non-terminal review where I'm a participant.
- Waiting on me — assigned + (my slot unlocked in sequential OR I'm required).
- Waiting on others — I'm owner/coordinator; reviewers still pending.
- Overdue — `due_at < now()` and not terminal.
- Completed — status=`completed`; I was owner or participant.
- Recent — `updated_at desc`; all visible statuses.
- Bookmarks (G-17) — user-flagged.
- Saved views (G-18) — user-defined filter + column set.

**Table columns:** Round # · Title · Asset · Version · Status · Owner · Coordinator · Reviewers (avatars + response chips) · Due · Age · Open comments · Last activity.

**Filters (client-side over one SELECT):** status (multi), owner, coordinator, reviewer, discipline (APP 003), collection (APP 003), date range, round number.

**Bulk actions:** bookmark/unbookmark, cancel (gated + confirm), reassign reviewer.

**Data source:** dashboard reads flow through a new `list_reviews_dashboard` RPC (G-19) that returns rows with precomputed `open_comment_count`, `open_reviewer_count`, `overdue_flag`, `my_slot_status`.

---

## 10. Review Detail architecture

Full-page route: `/workspace/:ws_id/project/:proj_id/review/:review_id[/round/:round_number]`.

**Layout:**
```
Header:   ← Back · Asset · Review R-# · Round # · [Status badge] · ⋮
Region A: Version card (compact viewer link, "★ current" indicator, "Open workspace")
Region B: Reviewers panel (per-row status + response chip + Remind + coordinator actions)
Region C: Timeline / round chain (jump between rounds)
Tabs:     Comments | Participants | Activity | Files
```

Tabs body:
- **Comments** — reuses APP 005 `CommentsPanel`, scoped to this review (target_review_id + the review's version + its annotations).
- **Participants** — full roster with add/remove/reassign controls, gated by `review.coordinate`.
- **Activity** — filtered `activity_events` for this review chain.
- **Files** — read-only file list of the review's version (reuses APP 005 `FilesPanel`).

**Design Workspace ↔ Review context banner:** when the user navigates from a review to its version in the Design Workspace, show a subtle top banner: *"In review context — R-42, Round 2. Back to review."* (D-18).

---

## 11. Workspace integration

**NavRail additions:**
- Workspace mode: `Reviews` between `Projects` and `People`. Icon `ClipboardCheck`. Badge = inbox count (cap 99+).
- Project mode: `Reviews` promoted from APP 003 stub. Icon + project-scoped count badge.
- Both gated on `review.view`.

**Design Workspace right panel:** APP 005 reserved the `reviews` tab as disabled placeholder. APP 006 fills it in — additive body change, no APP 005 file rewritten. Panel content:
- If version has no reviews: EmptyState + `+ Start review` (gated on `review.create`).
- If ≥1 review: cards summarizing round # · status · owner · reviewer responses · due date + `Open` action.
- Always: `+ Start review on this version` at bottom (gated).

**AssetCard / VersionMenu / VersionBar:** no changes. Reviews surface only in the Reviews tab and dashboard, not on those primitives.

---

## 12. Comments integration

Consumes APP 005 wholesale. No changes to comment/annotation semantics.

**In Review Detail Comments tab, three comment scopes surface with badges:**
- `[Review]` — `comments.target_review_id = review.id`
- `[General]` — `target_version_id = review.version_id`
- `[Pin #n]` — annotation comments on the review's version files

**APP 005 CommentsPanel adjustment (additive):** filter out review-scoped comments from the version-scope view by default; add a small "Include review comments" toggle for context (D-11).

**Resolution rules:** single source of truth is `comments.resolved_at`. Both panels reflect it. Optimistic toggle behavior from APP 005 preserved.

**Completion metric:** every review row exposes `open_comment_count` = review-scoped root comments with `resolved_at IS NULL AND deleted_at IS NULL AND parent_comment_id IS NULL` (D-12).

**Optional per-review flag** `require_comments_resolved boolean default false` (G-20): if set, `complete_review` rejects while any review-scoped root comment is unresolved.

---

## 13. Version interaction

- **Reviewing continues after a new version exists.** Review is anchored to its version (frozen invariant). Reviewers see a badge: *"You're reviewing v3 — v4 is now current."*
- **Version lock is immutable per review.** Composite FK schema-enforces. Moving a review to another version is not allowed; reopen is the mechanism.
- **No automatic comment inheritance across versions.** Review-scoped comments belong to their round.
- **Optional annotation carry-forward on reopen** (G-22): coordinator-opt-in checkbox to copy `active` annotations from the old round's version to the new version.
- **Version compare** is out of scope for APP 006. Review Detail shows a side-by-side thumbnail strip (v(N) and v(N+1)) for context — visual only, not a diff engine.

---

## 14. Metrics

**Per-review** (computed in `get_review` RPC):
- Duration open — `now() - opened_at`
- Time to first comment
- Time to first response
- Time to completion
- Open comment count
- Reviewer response distribution `{signed_off, commented, declined, pending}`

**Workspace / project** (computed in `list_reviews_dashboard`):
- Outstanding review count
- Overdue count
- Reviewer throughput (per user, trailing 30 days)
- Average time-to-completion (trailing 30 days)

**Derivation strategy:** compute from existing `activity_events` (frozen table) at RPC layer; avoid new columns for `opened_at` / `first_responded_at` / `first_commented_at` (G-23 — flagged only in case of perf issue).

**Dashboard metrics UI:** collapsible strip above the dashboard table. Off by default; toggle persisted in saved view.

---

## 15. Deep links

Extends APP 002 `DeepLinkResolver` additively:

| Route | Behavior |
|---|---|
| `/deep/review/:id` | Resolves review → workspace/project/asset/version → navigate to Review Detail |
| `/deep/review/:id/comment/:cid` | Convenience alias; collapses to `/deep/comment/:cid` |
| `/deep/reviewer/:participant_id` | Resolves participant → Review Detail with `?participant=...` param focused |

Existing `/deep/comment/:id` and `/deep/annotation/:id` (APP 005) resolve correctly when the target sits on a review — no changes.

`useCopyLink` (APP 005) extended additively with `LinkKind = 'comment' | 'annotation' | 'review' | 'reviewer'`.

---

## 16. URL ownership

Owned by APP 006 on the review-scoped routes:

| Param | Values | Meaning |
|---|---|---|
| `?view=<saved_view_id \| inbox \| overdue \| ...>` | string | Dashboard view selector |
| `?status=draft,open,...` | comma-list | Status filter |
| `?owner=<profile_id>` | uuid | Owner filter |
| `?reviewer=<profile_id>` | uuid | Reviewer filter |
| `?due=overdue \| week \| month` | keyword | Due-date filter |
| `?round=<n>` | int | Focus specific round in Review Detail |
| `?participant=<participant_id>` | uuid | Focus a reviewer row in Review Detail |
| `?tab=comments \| participants \| activity \| files` | keyword | Review Detail tab |

Reused (unchanged) from APP 003: `?discipline=<id>`, `?from=collection:<id> \| unfiled`.
Reused (unchanged) from APP 005: `?comment=<id>`, `?annotation=<id>`, `?comments=<filter>` — active in Review Detail's Comments tab.

---

## 17. Query architecture

Append-only additions to `qk`:

```ts
qk.reviews.workspaceDashboard(ws_id, view)
qk.reviews.projectDashboard(proj_id, view)
qk.reviews.list(scope, filters)             // low-level, powers all views
qk.review(id)
qk.reviewChain(root_id)
qk.reviewParticipants(review_id)
qk.reviewMetrics(review_id | proj_id | ws_id)
qk.reviewInboxCount(ws_id)
qk.savedViews(ws_id, user_id)
qk.bookmarks(user_id, ws_id)
```

Read RPCs (`SECURITY DEFINER`, read-only, capability-gated) — G-19:
- `list_reviews_dashboard(scope, view, filters, cursor, limit)`
- `get_review(id)`
- `get_review_chain(root_id)`

Rationale: RLS on `review_participants` doesn't compose cleanly with per-row aggregations. RPCs precompute counts and prevent N+1 SELECTs.

Optimistic mutations: only `respond_to_review`. Everything else round-trip.

---

## 18. Cache invalidation

| Mutation | Invalidates |
|---|---|
| `create_review` | `reviews.list(*)`, `reviewInboxCount`, `reviewMetrics(proj)` |
| `open_review` (from ready_for_review) | same |
| `respond_to_review` | `review(id)`, `reviewParticipants(id)`, `reviews.list(*)`, `reviewInboxCount`, `reviewMetrics(*)` |
| `add/remove/reassign_reviewer` | `review(id)`, `reviewParticipants(id)`, `reviews.list(*)` |
| `set_review_state(waiting)` | `review(id)`, `reviews.list(*)` |
| `complete_review` | `review(id)`, `reviews.list(*)`, `reviewChain(root)`, `reviewMetrics(*)`, APP 005 `commentsForVersion(v)` (edit gate now blocks) |
| `reopen_review` | `reviewChain(root)`, `reviews.list(*)`, `review(new_id)` |
| `bookmark / unbookmark` | `bookmarks(user, ws)`, that review's row |
| `save_view` | `savedViews(ws, user)` |

**Cross-slice hooks:**
- APP 005 comment mutation with `target_review_id ≠ null` → additionally invalidate `reviewMetrics(review_id)`. Additive helper `invalidateReviewMetrics` in `src/features/shared/invalidate.ts`.
- APP 004 `publish_version` / `discard_draft_version` → invalidate `reviews.list(*)` (newer-version badge may appear).

---

## 19. Capability model

**Existing (frozen):**
- `review.view`
- `review.create`
- `review.participate`
- `review.complete`

**New (G-16):**
- `review.coordinate` — manage roster mid-review, pause/resume (waiting), reassign, add/remove reviewers.
- `review.reopen` — create a new round from a completed review.

**Role mapping (recommended defaults):**

| Capability | lead | contributor | reviewer | approver | observer |
|---|---|---|---|---|---|
| `review.view` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `review.create` | ✓ | ✓ | | | |
| `review.coordinate` | ✓ | | | | |
| `review.participate` | ✓ | ✓ | ✓ | ✓ | |
| `review.complete` | ✓ | ✓ | | | |
| `review.reopen` | ✓ | ✓ | | | |

Workspace admin: `review.view` only (per PERMISSIONS.md admin-override rule); admins override to write via `lign_is_workspace_admin` predicate in RPCs.

**Gate hierarchy:** `useProjectCapabilities` → `<Guarded capability="...">` → backend RPC re-check.

---

## 20. Navigation ownership

APP 006 introduces exactly two new NavRail entries and one Design Workspace tab body:

- Workspace mode NavRail: `Reviews` (icon + inbox-count badge, `review.view` gate).
- Project mode NavRail: `Reviews` (promoted from APP 003 stub).
- Design Workspace `RightPanel > Reviews` tab: content added; tab was already reserved by APP 005.

No breadcrumb changes. Every APP 003+ handle convention preserved (`navMode`, `crumb` on route handles).

---

## 21. AI extension points

APP 006 does not implement AI. Reserved seams:

| Seam | Where | Purpose |
|---|---|---|
| Review summary | `get_review` payload `ai_summary?: string \| null` | AI-generated summary once review is complete |
| Reviewer suggestion | Create-review composer sidebar | Suggest reviewers by past discipline/asset participation |
| Comment triage | Above Comments panel | Cluster open comments; propose resolutions |
| Auto-round-2 draft | Reopen dialog | Pre-write new-round description from prior comments |
| Overdue prediction | Dashboard row | "Likely to slip 2 days" based on reviewer velocity |
| Discipline routing | Create-review composer | Auto-select discipline from asset content |

Rendered as `<AISlot kind="..." data={...} />`. Default: renders nothing. AI slice fills them.

---

## 22. Notification contracts (APP 010 will consume)

APP 006 emits nothing client-side. Backend RPCs emit these events; APP 010 subscribes.

| Event type | Emitted by | Payload keys |
|---|---|---|
| `review.created` (existing) | `create_review` | review_id, title, owner_id, round_number, is_open |
| `review.opened` (existing) | `create_review` (p_open=true) OR `open_review` (G-2) | review_id, round_number, roster (wm_ids[], sh_ids[]), due_at |
| `review.reviewer_responded` (existing) | `respond_to_review` | review_id, participant_id, response, note_snippet |
| `review.completed` (existing) | `complete_review` | review_id, round_number, forced (bool), outcome_summary |
| `review.cancelled` (existing) | `complete_review` | review_id, round_number, cancellation_reason |
| `review.reopened` (new — G-24) | `reopen_review` | old_review_id, new_review_id, new_round_number |
| `review.state_changed` (new — G-25) | `set_review_state` | review_id, from, to |
| `review.reviewer_added` (new — G-26) | `add_reviewer` | review_id, participant_id, required |
| `review.reviewer_removed` (new — G-27) | `remove_reviewer` | review_id, participant_id, reason |
| `review.reviewer_reassigned` (new — G-28) | `reassign_reviewer` | review_id, participant_id, from_id, to_id |
| `review.deadline_approached` (new — G-29, RESERVED) | Scheduled emitter (backend cron; outside APP 006) | review_id, hours_remaining |
| `review.deadline_passed` (new — G-30, RESERVED) | Scheduled emitter | review_id, hours_overdue |

Existing `comment.*` events (APP 005) with `target_review_id != null` are treated by APP 010 as review-comment events for routing. No new comment events introduced.

---

## 23. Realtime contracts (APP 011 will consume)

APP 006 does not implement subscriptions. Contract:

| Channel | Scope | Invalidates on message |
|---|---|---|
| `workspace:{ws_id}:reviews` | Workspace inbox updates | `reviews.list(ws_id, *)`, `reviewInboxCount(ws_id)` |
| `project:{proj_id}:reviews` | Project dashboard updates | `reviews.list(proj_id, *)` |
| `review:{review_id}` | Roster/state/completion-affecting-comment updates | `review(id)`, `reviewParticipants(id)`, `reviewMetrics(id)` |
| `review-chain:{root_id}` | New round created | `reviewChain(root_id)` |
| `user:{profile_id}:inbox` | Per-user inbox additions | `reviews.list(*, 'assignedToMe')`, `reviewInboxCount(*)` |

**Subscription lifecycle (APP 011 implements):**
- Dashboard mount → subscribe to `workspace:{ws_id}:reviews` + `user:{profile_id}:inbox`.
- Review Detail mount → subscribe to `review:{review_id}`.
- Design Workspace mount (when review context is set) → subscribe to that review.

APP 006 exports channel-name constants from `src/features/reviews/realtime.ts` (constants only, no subscriber). APP 011 imports them.

---

## 24. Desktop / mobile behavior

**Desktop (≥1024px):**
- Full three-column Review Detail (version card + reviewers + timeline).
- Dashboard table full-width.
- Design Workspace Reviews tab renders inline in right panel.

**Tablet (768–1024px):**
- Review Detail collapses to two columns: main + right reviewers panel.
- Dashboard hides low-priority columns (age, activity); keeps title/status/reviewers/due.

**Mobile (<768px):**
- Dashboard becomes stacked cards (status + reviewer avatars + due).
- Review Detail single-column, tabs at top.
- Reviewer responses one-tap in a bottom sheet (Sign off / Comment / Decline).
- Long-press on dashboard card → context menu (bookmark, cancel, copy link).

**Keyboard shortcuts (additive to APP 005 `useWorkspaceHotkeys`):**
- `R` — new review composer for current version.
- `E` — focus reviewer roster picker (in Review Detail).
- `Shift+Enter` — submit reviewer response as `signed_off`.

APP 005 shortcuts (C / P / Esc) unchanged; no key conflicts.

---

## 25. Empty / loading / error states

**Empty states:**
- Workspace dashboard, no reviews: "No reviews yet. Start one from any design version." + button (gated).
- Project dashboard, no reviews: scoped variant.
- Filter yields 0: "No reviews match your filters" + Clear.
- Assigned-to-me empty: "You're all caught up."
- Overdue empty: "Nothing overdue."
- Review Detail — Comments tab: APP 005 `CommentsPanel` empty state reused.
- Review Detail — Participants tab (rare): "No reviewers assigned" + `+ Add reviewer`.
- Review Detail — Activity tab: "No activity yet".
- Design Workspace Reviews tab: "No reviews on this version" + `Start review` (gated).
- Bookmarks: "Bookmark reviews to find them fast."

**Loading states:**
- Dashboard: skeleton rows (5–8) mimicking table shape.
- Review Detail: parallel skeletons per region.
- Metrics strip: shimmer numbers.
- Reviewer submit: inline spinner in button; disable while pending.
- Reviewer picker: skeleton avatars streaming into names.

**Error handling:**
- Fetch errors: inline `EmptyState` with Retry via APP 003 `humanizeError`.
- Specific mutation error messages:
  - `respond_to_review` on completed → "This review is completed. You can no longer respond."
  - `add_reviewer` on terminal → "Roster is locked."
  - `reopen_review` when Round N+1 exists → "A newer round already exists" + link.
  - Optimistic response rollback → "Couldn't record your response. Try again."
- Dashboard wrapped in its own `ErrorBoundary` so a poisoned filter doesn't blank the shell.

---

## 26. Backend gaps

**Schema gaps:**
- **G-1** No `ready_for_review` / `waiting` values in `reviews.status` check.
- **G-2** No `open_review` RPC (opening only via `create_review`).
- **G-3** No `round_number` on `reviews`.
- **G-4** No `parent_review_id` / `root_review_id` on `reviews`.
- **G-5** No `coordinator_profile_id` on `reviews`.
- **G-6** No `max_open_rounds` per-project setting.
- **G-7** No `required boolean` on `review_participants`.
- **G-8** No `policy` column on `reviews`.
- **G-15** No `sequence_index` on `review_participants`.
- **G-11** No multi-asset review support (`design_asset_id` NOT NULL, single value).
- **G-12** No `collection_id` scope on `reviews`.
- **G-13** No `discipline_id` scope on `reviews`.
- **G-14** No `review_bundles` / batch model.
- **G-20** No `require_comments_resolved boolean` on `reviews`.
- **G-21** No `cancellation_reason text` column on `reviews`.
- **G-23** No cached `opened_at` / `first_responded_at` / `first_commented_at` (derive from events).

**RPC / behavior gaps:**
- **G-9** No `add_reviewer` / `remove_reviewer` RPCs.
- **G-10** No `reassign_reviewer` RPC.
- **G-16** No `review.coordinate` / `review.reopen` capabilities.
- **G-19** No dashboard read RPCs (`list_reviews_dashboard`, `get_review`, `get_review_chain`).
- **G-22** No `carry_forward_annotations` option/RPC on reopen.
- **G-24** No `reopen_review` RPC.
- **G-25** No `set_review_state` RPC (waiting ↔ in_progress).
- **G-26 / G-27 / G-28** No add/remove/reassign reviewer event emitters.
- **G-29 / G-30** No scheduled emitter for `review.deadline_approached` / `review.deadline_passed` (requires cron / edge function; type names RESERVED here, emitter deferred).
- **G-17** No `user_bookmarks` table.
- **G-18** No `user_saved_views` table.
- **G-31** No RLS write policy on `review_participants` (roster mutation RPC-only).
- **G-32** No trigger enforcing "reviewer is a project participant" (RPC-side check).
- **G-33** No cross-round visibility model — `review.view` gates the whole chain uniformly (per-round privacy is v2).

**Enterprise-minimum unblockers (prioritization suggestion):** G-1, G-3, G-4, G-5, G-7, G-9, G-16, G-19, G-24.

**Gaps are identified only.** Solutions belong to a backend re-freeze proposal, not this document.

---

## 27. Open decisions

D-1 through D-21 recorded from the architecture review. All at recommendation defaults unless overridden.

| # | Decision | Recommendation |
|---|---|---|
| D-1 | State enum expansion | Add `ready_for_review` and `waiting` |
| D-2 | Rounds as new rows vs counter | New rows with `parent_review_id` |
| D-3 | Owner vs coordinator | Separate `coordinator_profile_id` |
| D-4 | Policy default | `parallel`; sequential/quorum opt-in |
| D-5 | Required-by-default | Yes |
| D-6 | Force-completion | Yes, gated on `review.complete`, `forced=true` in event |
| D-7 | Unresolved-comment completion gate | Opt-in per review, off by default |
| D-8 | Cancellation reason | Required |
| D-9 | Annotation carry-forward on reopen | Coordinator-opt-in checkbox, default off |
| D-10 | Multi-asset review in v1 | No — v2 backend re-freeze |
| D-11 | Hide review comments from APP 005 panel by default | Yes, with toggle |
| D-12 | Open comment count scope | Review-scoped only |
| D-13 | Dashboard RPC vs client joins | RPC |
| D-14 | Saved views scope | Workspace-scoped user views; sharing v2 |
| D-15 | Bookmarks generalized | Yes — `user_bookmarks(subject_kind, subject_id)` |
| D-16 | `review.coordinate` / `review.reopen` split | Yes |
| D-17 | Review Detail: full page vs modal | Full page |
| D-18 | Review context banner | Yes |
| D-19 | NavRail badges | Workspace inbox count + project count; cap 99+ |
| D-20 | Round-per-version enforcement | No hard constraint; UI warns |
| D-21 | v1 vs v2 slice split | v1: dashboard + detail + comments + roster mgmt + reopen + policies. v2: multi-asset + bundles + saved-view sharing + workspace analytics + due-soon cron |

Any decision may be overridden before implementation; each is a one-file-scope change.

---

## 28. Future slice contracts (APP 007–011)

**APP 007 — Approvals**
- Inherits reviewer XOR (member/stakeholder) identity model.
- Inherits coordinator concept, lifecycle enum-extension pattern, dashboard grammar, and roster-mutation RPC style.
- Approval capabilities parallel `review.*` naming.
- May extend `--color-state-*` palette with a new token (e.g. `in-progress`, `approved`, `rejected`) via APP 005's reserved-token slots.

**APP 008 — Requirements**
- Every review carries a "requirements outcome" placeholder (empty in APP 006).
- Requirements can plug per-review assessments in without schema surgery to `reviews`.
- Requirement events observed by dashboard cards where a review's version fails assessment.

**APP 009 — Releases**
- A completed review's `outcome_summary` is one input to release readiness.
- Release UI queries `reviewChain(root)` per asset to show "last review outcome" alongside version.
- Release blockers may include "an open review exists on this version" — check `reviews.list(proj_id, {status: open|in_progress|waiting|ready_for_review, version_id})`.

**APP 010 — Notifications**
- Consumes the event vocabulary in §22 verbatim. No new events required from APP 006 once its RPCs land.
- Routing rules per event type (see architecture review §15.2) are APP 010's territory.
- Recipient rules (roster members for `review.opened`, coordinator for `review.deadline_approached`, etc.) enshrined by APP 010, not APP 006.

**APP 011 — Realtime**
- Consumes the channel-name constants in §23. No new channels required from APP 006 later.
- Subscribes and invalidates via query keys already exported by APP 006.
- Presence signals ("Alice is viewing this review") are additive; do not require APP 006 changes.

---

## Canonical routes

```
/workspace/:ws_id/reviews                                                       workspace dashboard
/workspace/:ws_id/project/:proj_id/reviews                                      project dashboard
/workspace/:ws_id/project/:proj_id/review/:review_id                            review detail (latest round)
/workspace/:ws_id/project/:proj_id/review/:review_id/round/:round_number        deep-link into a specific round
```

Deep-link routes (extend `DeepLinkResolver`):
```
/deep/review/:id
/deep/review/:id/comment/:cid          (convenience; collapses to /deep/comment/:cid)
/deep/reviewer/:participant_id
```

---

## Canonical query keys

```ts
qk.reviews.workspaceDashboard(ws_id, view)
qk.reviews.projectDashboard(proj_id, view)
qk.reviews.list(scope, filters)
qk.review(id)
qk.reviewChain(root_id)
qk.reviewParticipants(review_id)
qk.reviewMetrics(review_id | proj_id | ws_id)
qk.reviewInboxCount(ws_id)
qk.savedViews(ws_id, user_id)
qk.bookmarks(user_id, ws_id)
```

Reused (unchanged): `qk.projectParticipants(id)` (APP 002), `qk.commentsForVersion(id)` (APP 005), `qk.annotationsForVersion(id)` (APP 005), `qk.asset(id)` / `qk.assetVersion(id)` (APP 003).

---

## Canonical URL parameters

Owned by APP 006:
```
?view=<inbox | overdue | completed | recent | bookmarks | saved:<id>>
?status=<draft,open,in_progress,waiting,completed,cancelled>     (comma-list)
?owner=<profile_id>
?reviewer=<profile_id>
?due=<overdue | week | month>
?round=<int>
?participant=<participant_id>
?tab=<comments | participants | activity | files>
```

Reused (owned elsewhere; unchanged):
```
?discipline=<id>                    (APP 003)
?from=collection:<id> | unfiled     (APP 003)
?comment=<id>                       (APP 005)
?annotation=<id>                    (APP 005)
?comments=<all | unresolved | mine | mentions>   (APP 005)
```

---

## Canonical events

Owned by APP 006 (existing + new; see §22 for payload):

Existing (already frozen in backend):
- `review.created`
- `review.opened`
- `review.reviewer_responded`
- `review.completed`
- `review.cancelled`

New (require backend re-freeze):
- `review.reopened` (G-24)
- `review.state_changed` (G-25)
- `review.reviewer_added` (G-26)
- `review.reviewer_removed` (G-27)
- `review.reviewer_reassigned` (G-28)
- `review.deadline_approached` (G-29, RESERVED — name frozen, emitter deferred)
- `review.deadline_passed` (G-30, RESERVED — name frozen, emitter deferred)

No new `comment.*` or `annotation.*` events introduced.

---

## Canonical reusable primitives

Introduced by APP 006 for downstream slices:

- `useReviewMetrics(scope)` — subscribes to the metrics for a review, project, or workspace.
- `useReviewInboxCount(ws_id)` — the NavRail badge source.
- `ReviewerAvatarStack` — grouped avatars with response chips; reusable by Approvals and Releases.
- `RosterEditor` — add/remove/reassign roster manager; reusable by Approvals for approver rosters.
- `DashboardFilterBar` — status/owner/reviewer/date/discipline/collection filters + saved-view chip. Reusable by Approvals, Releases, Requirements dashboards.
- `AISlot` — extension seam for AI slice.
- Channel-name constants (`src/features/reviews/realtime.ts`) for APP 011.
- Additive extension of `useCopyLink` — accepts `LinkKind = 'comment' | 'annotation' | 'review' | 'reviewer'`.
- Additive extension of `useWorkspaceHotkeys` — accepts `onNewReview` (R), `onFocusRoster` (E), `onSignOff` (Shift+Enter).

---

## Canonical design tokens

APP 006 introduces **no new design tokens**. Reuses APP 005's generic `--color-state-*` palette:
- `--color-state-open` — active reviewer slots, open reviews.
- `--color-state-resolved` — signed-off slots, completed reviews.

Reserved placeholders in APP 005's `globals.css` that APP 007+ may fill:
- `--color-state-in-progress` (Reviews may use for `in_progress` badge; also Reviews / Approvals).
- `--color-state-blocked` (Reviews may use for `declined` badge; Changes / Requirements).
- `--color-state-superseded` (Requirements; possibly reopened rounds).

Recommendation: if APP 006 needs `in-progress` styling, it fills that reserved token — no new token names beyond the APP 005 contract.

---

## Canonical extension seams

For APP 007–011 and AI:

| Seam | Location | Consumer |
|---|---|---|
| Event payload `payload.forced` on `review.completed` | Backend event emitter | APP 010 (route differently) |
| Event payload `round_number` on every `review.*` | Backend event emitter | APP 010, APP 011 |
| `AISlot kind="review-summary"` | Review Detail header | AI slice |
| `AISlot kind="reviewer-suggestion"` | Create-review composer sidebar | AI slice |
| `AISlot kind="comment-triage"` | Above Review Comments panel | AI slice |
| `AISlot kind="auto-round-draft"` | Reopen dialog | AI slice |
| `AISlot kind="overdue-prediction"` | Dashboard row | AI slice |
| `AISlot kind="discipline-routing"` | Create-review composer | AI slice |
| Realtime channel constants | `src/features/reviews/realtime.ts` | APP 011 |
| `useReviewMetrics(scope)` | Shared hook | Approvals, Releases dashboards may compose |
| `RosterEditor` component | Shared component | Approvals for approver rosters |
| `DashboardFilterBar` component | Shared component | Approvals, Releases, Requirements dashboards |
| `get_review` payload `outcome_summary` | RPC response | APP 009 Release readiness signal |
| `get_review` payload `requirements_outcome?` | RPC response | APP 008 assessment plug-in |
| `LinkKind` union (APP 005) — accepts `'review'` and `'reviewer'` | `useCopyLink` | Any deep-linkable slice |
| `useWorkspaceHotkeys` — accepts APP 006 handlers additively | Shared hook | Any workspace slice |

---

## Canonical backend additions required

Total: **11 schema additions** (columns / tables / enum values) + **8 new RPCs** + **2 new capability keys** + **7 new event types** + **1 optional scheduled emitter**.

**Schema:**
1. `reviews.status` check enum expansion — add `ready_for_review`, `waiting` (G-1)
2. `reviews.round_number int not null default 1` (G-3)
3. `reviews.parent_review_id uuid null` + composite FK (G-4)
4. `reviews.root_review_id uuid null` (G-4)
5. `reviews.coordinator_profile_id uuid null` + FK (G-5)
6. `reviews.policy text default 'parallel'` + check `parallel | sequential | quorum` (G-8)
7. `reviews.quorum_min int null` (G-8)
8. `reviews.require_comments_resolved boolean default false` (G-20)
9. `reviews.cancellation_reason text null` (G-21)
10. `review_participants.required boolean default true` (G-7)
11. `review_participants.sequence_index int default 0` (G-15)

Plus two new tables:
- `user_bookmarks(user_id, subject_kind, subject_id, workspace_id, created_at)` (G-17)
- `user_saved_views(user_id, workspace_id, scope, name, definition jsonb, visibility, ...)` (G-18)

**Optional per-project setting:**
- `max_open_rounds` on projects (G-6, deferred / opt-in)

**RPCs (all `SECURITY DEFINER`):**
1. `open_review(review_id)` — draft/ready_for_review → open (G-2)
2. `set_review_state(review_id, target: 'waiting' | 'in_progress')` (G-25)
3. `reopen_review(review_id, carry_forward_annotations bool, new_version_id? uuid)` (G-24, G-22)
4. `add_reviewer(review_id, wm_id? uuid, sh_id? uuid, required bool, sequence_index int)` (G-9)
5. `remove_reviewer(participant_id, reason text)` (G-9)
6. `reassign_reviewer(participant_id, new_wm_id? uuid, new_sh_id? uuid)` (G-10)
7. `list_reviews_dashboard(scope, view, filters, cursor, limit)` (G-19 read)
8. `get_review(id)` and `get_review_chain(root_id)` (G-19 reads)

**Capabilities:**
- `review.coordinate` (G-16)
- `review.reopen` (G-16)

**Event types (payload details in §22):**
- `review.reopened` (G-24)
- `review.state_changed` (G-25)
- `review.reviewer_added` (G-26)
- `review.reviewer_removed` (G-27)
- `review.reviewer_reassigned` (G-28)
- `review.deadline_approached` (G-29, RESERVED)
- `review.deadline_passed` (G-30, RESERVED)

**Scheduled emitter (out of APP 006 scope; noted for the cron slice):**
- `review.deadline_approached` / `review.deadline_passed` cron (G-29, G-30). Type names are frozen here; emitter is deferred.

**Enterprise-minimum unblockers to ship APP 006 v1:** G-3, G-4, G-5, G-7, G-16, G-19, G-24, G-9, G-10 (and G-1 if the extra states are wanted from day one). Everything else can incrementally land in APP 006 v1.1 / v2.

---

**APP 006 Architecture is frozen.**

Do not begin implementation.
