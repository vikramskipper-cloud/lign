# Home screen — build report

Status: built, typecheck clean, 56 tests green, bundle within budget. **Not yet
verified in a browser** — that belongs to the UI/UX testing phase.

Code: `app/src/features/home/` (`queries.ts`, `mutations.ts`, `pins.ts`,
`copy.ts`, `HomeShell.tsx`, `HomeScreen.tsx`, `RequestChangesDialog.tsx`).
Route: `/dashboard` inside `Gated`, as a sibling of `RootLayout`; `/` is a
front-door redirect to it, outside `Gated`.

---

## 1. Table / column mapping

The brief's vocabulary is not the schema's. What each brief noun actually is:

| Brief concept | Table | Columns used |
|---|---|---|
| my projects + role | `project_participants` | `id, role, project_id, workspace_id, status` |
| — who I am in it | `workspace_members` / `stakeholders` | `id, user_id` (XOR: exactly one is set) |
| project name | `projects` | `id, name` |
| approval request | `approval_requests` | `id, title, status, due_at, created_at, sent_at, project_id, version_id, created_by_profile_id` |
| approver slot | `approval_request_approvers` | `id, workspace_member_id, stakeholder_id, removed_at` |
| response | `approval_responses` | `id` (existence only) |
| review | `reviews` | `id, title, status, created_at, project_id` |
| reviewer slot | `review_participants` | `id, responded_at, status, removed_at, workspace_member_id` |
| asset name | `design_assets` | `name` |
| activity | `activity_events` | `id, event_type, subject_label, occurred_at, project_id, actor_profile_id` |
| pins | `user_bookmarks` | `subject_kind='project', subject_id, created_at` |
| display names | `profiles` | `display_name` |
| release | `releases` / `release_items` | *(not read by Home — see §5)* |
| mentions | **does not exist** | — |

**The one substantive re-mapping.** `approval_requests.version_id` is `NOT NULL`
and there is no release-scoped approval path. Per the Gap-1 decision (approvals
stay on versions), the brief's "Releases awaiting my approval" is implemented as
**"Approvals awaiting your response"**, scoped to a version. Release remains the
published end-state, not the approval unit. "Waiting on others" is likewise
approval-request-scoped, not release-scoped.

## 2. Query per section

All five are plain PostgREST selects under RLS — no new RPCs, no schema change.
Each was executed live against the project before any UI was written on it.

| Section | Root table | Filter |
|---|---|---|
| project cards / roles | `project_participants` | `workspace_id`, `status='active'`, then client-filtered to rows whose member/stakeholder `user_id` is me |
| 1a. Approvals awaiting you | `approval_request_approvers` | `workspace_id`, `removed_at is null`, `workspace_member_id in (my approver slots)`, then drop slots that already have a response and requests not `pending`/`in_progress` |
| 1b. Reviews awaiting you | `review_participants` | `workspace_id`, `removed_at is null`, `responded_at is null`, `workspace_member_id in (my reviewer slots)`, review `status in (open, in_progress)` |
| 2. Waiting on others | `approval_requests` | `workspace_id`, `status in (pending, in_progress)`, kept when I raised it or lead the project **and** ≥1 live approver slot has no response |
| 3. Recent activity | `activity_events` | `workspace_id`, ordered `occurred_at desc`, capped at 5 |
| sidebar pins | `user_bookmarks` | `subject_kind='project'` |

Fixed cost: 6 queries regardless of project count. No per-row follow-ups —
unanswered-ness comes from an embedded `approval_responses` / `responded_at`,
not from N extra round-trips.

**FK hints: four of thirteen I wrote were wrong** and only surfaced because I
ran every select live first. `approval_requests_project_fk` and
`reviews_project_fk` **do not exist** — neither table has any direct FK to
`projects` (only a composite `design_asset_fk`), so project names come from the
participation map instead, with a comment in the file explaining why re-adding
the embed breaks the select. `approval_responses_slot_fk` is really
`approval_responses_slot_request_fk`; `approval_request_approvers_member_fk` is
really `..._workspace_member_fk`. This is the same defect class as the APP 005
`useProjectParticipants` bug — caught before shipping this time.

## 3. How "capability to act" is checked, per row type

Home reads. It does not reimplement permissions, and it did not touch
`lign_has_capability`, `lign_project_role`, RLS, or the schema.

| Row type | Gate |
|---|---|
| approval row | user holds an un-removed, unanswered slot in `approval_request_approvers` **and** `project_participants.role = 'approver'` on that project |
| review row | un-removed, unresponded slot in `review_participants` **and** `role = 'reviewer'`/`lead` |
| waiting-on-others row | user raised the request, or holds `role = 'lead'` on the project (read-only row — no action offered) |
| project card | membership in `project_participants` — the row cannot exist otherwise |
| "New project" button | `workspace.manage` via `useWorkspaceAccess` |
| People / Settings nav | `member.invite` / `workspace.manage` |
| activity row | RLS on `activity_events` only; rows are links, never actions |

Participation is the gate for every actionable row because participation is
exactly what `lign_project_role` reads, and that is what `respond_to_approval`
resolves through. Consequence, deliberate: **a workspace admin who is not a
participant sees no actionable rows** — admins hold only the `*.view` keys;
work keys come from participation. That matches the capability model rather
than working around it. RLS still filters every query independently, so the
client-side gate is a UI affordance, not the security boundary.

Orange is used only on the primary action of an actionable row — never for
status, count, or warning. Status uses the `--status-*` tokens.

## 4. Empty states, and the fixtures they were verified against

The workspace had **0 reviews, 0 releases, and every approval request
cancelled**, so six acceptance checks had no data to pass against. I seeded
through the real RPCs (`create_project`, `add_participant`, `create_asset`,
`publish_version`, `request_approval`, `create_review`) — no direct inserts:

- Project Two in Workspace One, `demo` as lead, `p_lead` added as **approver**
- asset "Lobby package" + a published version
- an approval request due in 2 days, `p_lead` unanswered
- an open review on Project One, `p_reviewer` unanswered

| Empty state | Fixture that produces it |
|---|---|
| nothing needs you ("You're clear") | `demo` — raiser and lead, holds no approver/reviewer slot |
| no approvals but reviews pending | `p_reviewer` — reviewer slot only, no approver slot |
| approvals pending | `p_lead` — approver on Project Two |
| nothing waiting on others | `p_reviewer` — raised nothing, leads nothing |
| waiting-on-others populated | `demo` — 1 request, 1 unanswered approver |
| single-project user | `p_reviewer` |
| no workspace at all | redirects to `/no-access` before Home renders (`useAccessCheck`) |

Measured through PostgREST as the signed-in user: participations 6, approvals 3,
reviews 0, activity 5, waiting-on-others 1 request with 1 unanswered approver.

These are fixture-level verifications — the queries return the right rows for
the right user. Rendering, focus order, keyboard paths and the responsive
breakpoints have **not** been checked in a browser.

## 5. Undo on approval: **not supported**

`approval_responses` carries both a `no_update` and a `no_delete` trigger — a
response is immutable by design, and reversing one would require a schema
change I was told not to make. This matches the Gap-3 decision (do not undo
approvals). What Home does instead: the row disappears optimistically on
submit and is restored if the RPC fails. There is no undo affordance, because
offering one that the database would reject is worse than not offering it.

## 6. Schema gaps

1. **Mentions do not exist.** There is no mention table, no mention column, and
   no mention extraction anywhere in the backend. Section 1c ("Comments that
   mention you") is **not built**. Making it real means mentions as a
   first-class concept — flagged, not invented.
2. **Approvals cannot be release-scoped.** `approval_requests.version_id` is
   `NOT NULL` with no release path. Resolved by decision, not by code: approvals
   stay on versions.
3. **No direct project FK** on `approval_requests` or `reviews`. Project names
   are resolved client-side from the participation map. Adding the FK would let
   these become single embedded selects — worth considering, but it is a schema
   change and out of scope here.
4. **Multi-approver rule.** The database already models it
   (`approval_requests.policy` `any|all`, `quorum_min`). `copy.ts isSatisfied()`
   mirrors it **for display only**, defaulting to ALL, and is explicitly not the
   authority — the RPC decides.

## 7. Other things I flagged rather than silently did

- ~~**Home has its own shell.**~~ Resolved: the shell was generalised into
  `shell/AppShell.tsx` and now wraps every authenticated route via
  `RootLayout`. `TopBar`, `NavRail` and `NavItem` are deleted. One navigation
  system.
- **Search renders but is inert** — there is no search surface to wire it to.
  Marked TODO rather than removed, since the brief specifies it.
- **Realtime is not subscribed.** Home polls via TanStack Query staleness.
  APP 011's channels exist and could drive invalidation; wiring them was not in
  scope.
- `RootRedirect.tsx` was deleted in the route cleanup: `/` now redirects to
  `/dashboard`, so nothing routed to it any more.
