# APP 007 — Backend Re-freeze Proposal (Corrections Applied)

**Design proposal only. No SQL, no implementation, no migrations.** Every backend addition required to support the frozen APP 007 architecture, mapped to the Freeze Index sections and prioritized for a phased re-freeze. This revision incorporates every accepted correction from the APP 007 Backend Re-freeze Review.

**Companion documents:**
- [`APP_007_FREEZE_INDEX.md`](APP_007_FREEZE_INDEX.md) — the frozen architecture this proposal supports.
- [`SCHEMA_V1_LOCK.md`](SCHEMA_V1_LOCK.md) — the current schema lock (28 tables after APP 006 re-freeze); APP 007 extends it additively.
- [`PERMISSIONS.md`](PERMISSIONS.md) — capability catalog; three new keys proposed here.
- [`EVENT_MODEL.md`](EVENT_MODEL.md) — event vocabulary; five new types + three RESERVED names + payload extensions proposed here.
- [`APP_006_BACKEND_PROPOSAL.md`](APP_006_BACKEND_PROPOSAL.md) — pattern reference.
- [`freeze/APP_006_FINAL_CERTIFICATION.md`](freeze/APP_006_FINAL_CERTIFICATION.md) — governance-shape precedent (T-CRIT-1 chain-initialization discipline is cited throughout).

**Frozen invariants cited by this proposal:**
- `supabase/migrations/20260729220000_approval_model.sql` L119–L121 — `approval_requests_active_target_key` partial unique index (WHERE `status in ('pending','in_progress')`).
- `supabase/migrations/20260729220000_approval_model.sql` L167–L206 — `enforce_approval_request_target_eligibility` trigger (fires on INSERT regardless of `status`; requires the target `asset_versions` row be `published`).
- `supabase/migrations/20260729220000_approval_model.sql` L397–L398 — `approval_responses_slot_coherence` trigger.
- `supabase/migrations/20260729220000_approval_model.sql` L403–L427 — `enforce_approval_response_immutable` trigger function + UPDATE/DELETE triggers on `approval_responses`.
- `supabase/migrations/20260801180000_auth_007_approval_rls.sql` L201–L339 — frozen `respond_to_approval` RPC; L326 emits `approval.approved` / `approval.rejected`.

---

## APP 007 Backend Re-freeze — Applied Corrections

### Executive summary

- **F-7.1 (CRITICAL) applied.** Chain-initialization discipline is mandatory: `create_approval_draft` and `supersede_approval_request` MUST pre-compute `approval_requests.id` via `gen_random_uuid()` and INSERT with `root_approval_request_id` set inline (self for chain roots; parent's root for supersessions). Post-INSERT UPDATE of chain columns is forbidden by the chain-immutability trigger (§10.1). Repeated verbatim in §8.1 and §8.7 and in the Wave-1 mandatory test checklist. Mirrors APP 006 T-CRIT-1 precedent.
- **F-1.1 (CRITICAL) applied.** `supersede_approval_request` transactional ordering documented in §8.7 and §14: `SELECT … FOR UPDATE` on the old row → transition old to `superseded` → INSERT new (`draft`). The frozen `approval_requests_active_target_key` unique index (L119–L121) covers only `pending`/`in_progress`, so a `draft` new-request does not conflict.
- **F-2.1 (CRITICAL) applied.** `abstained` added additively to `approval_responses.decision` as a genuinely new value; `changes_requested` preserved for historical rows and existing RPC compatibility. No frontend aliasing. New RPC entry-points reject `changes_requested`. `abstained` does not count in `v_non_approved` and never terminates the request under policy `all`.
- **F-10.1 (CRITICAL) applied.** Supersession permitted only from `pending` or `in_progress`. `approved` is terminal and immutable; a fresh approval on the same asset after an approved outcome is an independent (unchained) request. APP 009 sorts by `outcome_at desc` to find "the latest approval." Documented in §3.5, §4.3, and §14.
- **F-2.2 (HIGH) applied.** Single canonical schema: widen the existing `approval_responses.comment` CHECK; the "add `decision_reason` column" alternative is deleted. §2.10 and §4.5 aligned.
- **F-2.4 (HIGH) applied.** New DB-boundary trigger `approval_responses_no_self_approve` (BEFORE INSERT, SECURITY DEFINER, `search_path=''`) — see §10.2. Standard REVOKE-from-public/anon/authenticated discipline on the trigger function.
- **F-3.1 (HIGH) applied.** Metadata-array ordering formalized in §8.2 and §8.8: workspace members first, stakeholders second, index positions match the concatenation.
- **F-4.1 (HIGH) applied.** `approval.approved` and `approval.rejected` are reclassified from "new event types" to payload extensions (§11.5). They are already emitted by AUTH 007 RPC (`respond_to_approval` L326).
- **F-4.2 (HIGH) applied.** RESERVED name locked as `approval.deadline_approached` (past-tense). Freeze Index updated in the same pass (surgical edits only).
- **F-1.2 (HIGH) applied.** Sequential-policy input validation: RPC-enforced per-request unique `sort_order` `0..N-1`. DB-enforced uniqueness deferred to v2.
- **F-7.2 (HIGH) applied.** Redundant response-immutability trigger removed from the proposal; the frozen `enforce_approval_response_immutable` (L403–L427) already covers UPDATE and DELETE. G-15 downgraded to "already frozen — no change."
- **All MEDIUM findings applied.** F-2.3 (published-only target for `draft`), F-3.2 (`supersede_approval_request` signature enumerated), F-3.3 (`get_approval_readiness` return shape reconciled), F-4.3 (`round_number` dropped), F-5.1 (`approval.veto` default to `lead` only; Freeze Index §11.3 corrected), F-7.3 (`set_updated_at` trigger on `approval_request_approvers`), F-6.2 (DEFINER-over-zero-policy discipline for `add_approver`), F-10.2 (`related_review_id` in immutable-column set).
- **All LOW findings applied.** F-1.4 (`COMMENT ON COLUMN` blanket note), F-3.4 (per-RPC `search_path=''` restatement), F-5.2 (PERMISSIONS.md checklist), F-7.4 (trigger REVOKE restatement), F-12.2 (Wave 1 arithmetic recount).

### Every correction applied

| ID | Severity | Applied? | Section(s) touched | One-line summary |
|---|---|---|---|---|
| F-7.1 | CRITICAL | Yes | §8.1, §8.7, §10.1, §19 Wave-1 checklist | Pre-computed UUID + inline chain-column INSERT is mandatory. |
| F-1.1 | CRITICAL | Yes | §8.7, §14 | Transactional ordering for supersede; `draft` excluded from active-target index. |
| F-2.1 | CRITICAL | Yes | §5.3, §11.2, §17 G-11 | `abstained` added; `changes_requested` deprecated for new writes. |
| F-10.1 | CRITICAL | Yes | §3.5, §4.3, §14 | `approved` cannot be superseded; independent new request instead. |
| F-2.2 | HIGH | Yes | §2.10, §4.5, exec summary, §19, coverage matrix | Widen `comment` CHECK; `decision_reason` alternative deleted. |
| F-2.4 | HIGH | Yes | §10.2, §17 G-11 support, coverage matrix | New `approval_responses_no_self_approve` trigger. |
| F-3.1 | HIGH | Yes | §8.2, §8.8 | Metadata-array concatenation order: `wm_ids` then `sh_ids`. |
| F-4.1 | HIGH | Yes | §11.5, §12.1 | Reclassify `approval.approved`/`approval.rejected` as payload extensions. |
| F-4.2 | HIGH | Yes | §12.2, §17 G-36, Freeze Index | Rename `deadline_approaching → deadline_approached`. |
| F-1.2 | HIGH | Yes | §5.5 addition, §8.2 | Sequential policy requires distinct `sort_order` 0..N-1 at RPC layer. |
| F-7.2 | HIGH | Yes | §10 (removal), §17 G-15, coverage matrix | Redundant response-immutability trigger removed. |
| F-2.3 | MEDIUM | Yes | §4.9 (new) | Published-only target discipline preserved for `draft` requests. |
| F-3.2 | MEDIUM | Yes | §8.7 | `supersede_approval_request` params enumerated. |
| F-3.3 | MEDIUM | Yes | §7.5 | `get_approval_readiness` return shape reconciled with Freeze Index §10.1. |
| F-4.3 | MEDIUM | Yes | §12.1, §11.5 | `round_number: null` dropped from every approval payload. |
| F-5.1 | MEDIUM | Yes | §6.1, Freeze Index §11.3 | `approval.veto` default `lead` only. |
| F-7.3 | MEDIUM | Yes | §10.4 (new) | `set_updated_at` trigger on `approval_request_approvers` in Wave 2. |
| F-6.2 | MEDIUM | Yes | §8.8 | DEFINER-over-zero-policy discipline for `add_approver`. |
| F-10.2 | MEDIUM | Yes | §10.1 | `related_review_id` in chain-immutability trigger's immutable-column set. |
| F-1.4 | LOW | Yes | §2 preamble | `COMMENT ON COLUMN` accompanies every new column. |
| F-3.4 | LOW | Yes | §7 preamble, §8 preamble | Per-RPC `search_path=''` + REVOKE/GRANT discipline restated. |
| F-5.2 | LOW | Yes | §6 checklist | PERMISSIONS.md registration checklist for each new key. |
| F-7.4 | LOW | Yes | §10 preamble | Trigger-function REVOKE discipline restated. |
| F-12.2 | LOW | Yes | §19 | Wave 1 arithmetic recounted. |

### Updated backend contract

This document is now the **authoritative backend contract for APP 007 Approvals**. Every RPC signature, trigger definition, capability key, event payload extension, index, constraint, and CHECK enumerated below is binding for the APP 007 backend re-freeze. Downstream slices (APP 008 Requirements UI, APP 009 Releases, APP 010 Notifications, APP 011 Realtime) may build against these signatures without further APP 007-side changes.

### Updated schema surface (condensed, post-corrections)

| Kind | Name | Purpose |
|---|---|---|
| Column | `approval_requests.expires_at timestamptz null` | Hard deadline (§2.1). |
| Column | `approval_requests.related_review_id uuid null` | Loose FK to APP 006 review (§2.2). |
| Column | `approval_requests.supersedes_approval_request_id uuid null` | Chain parent (§2.3). |
| Column | `approval_requests.root_approval_request_id uuid null` | Chain root (§2.4). |
| Column | `approval_requests.quorum_min integer null` | Threshold for `policy='quorum'` (§2.5). |
| Column | `approval_requests.cancellation_reason text null` | Audit reason on cancel (§2.6). |
| Column | `approval_request_approvers.required boolean not null default true` | Required vs optional (§2.7). |
| Column | `approval_request_approvers.veto_power boolean not null default false` | Per-approver veto (§2.8). |
| Column | `approval_request_approvers.removed_at timestamptz null` | Soft-remove pair (§2.9). |
| Column | `approval_request_approvers.removed_reason text null` | Soft-remove pair (§2.9). |
| Column | `approval_responses.decision_metadata jsonb null` | Reserved for v2 e-sig (§2.11). |
| Column | `approval_responses.is_veto_cast boolean not null default false` | Denormalized veto flag on response (§2.12). |
| CHECK | Widened `approval_responses.comment` | Mandatory reason 3–2000 chars on every response (§2.10, §4.5). |
| CHECK | `approval_requests` chain integrity | Root/self coherence (§4.2). |
| CHECK | `approval_requests` policy consistency | `quorum → quorum_min > 0` (§4.3). |
| CHECK | `approval_requests` cancellation-reason presence | (§4.4). |
| CHECK | `approval_responses` veto-cast consistency | Veto only on reject (§4.6). |
| CHECK | `approval_request_approvers` removal pair | (§4.7). |
| CHECK | Outcome + sent gates | Expanded for `superseded`; relaxed for `draft` (§4.8). |
| Enum | `approval_requests.policy` | +`single, unanimous, majority, quorum, sequential` (§5.1). |
| Enum | `approval_requests.status` | +`draft`, +`superseded` (§5.2). |
| Enum | `approval_responses.decision` | +`abstained` (`changes_requested` retained for legacy) (§5.3). |
| Index | 12 new indexes | See §3. |
| FK | 3 composite tenancy FKs | Chain (RESTRICT) + review link (SET NULL) (§4.1). |
| Trigger | `approval_requests_chain_immutable` | BEFORE UPDATE guard (§10.1). |
| Trigger | `approval_responses_no_self_approve` | BEFORE INSERT guard (§10.2). |
| Trigger | `set_updated_at` on `approval_request_approvers` | Wave 2 (§10.4). |

Total additions: 12 columns, 1 widened CHECK, 6 new CHECKs, 3 enum widenings, 12 indexes, 3 FKs, 3 new triggers (only 2 in Wave 1). Removed from the earlier draft: the redundant response-immutability trigger (frozen invariant covers it) and the duplicative `decision_reason` column.

### Updated RPC surface

Every RPC below is `SECURITY DEFINER`, `search_path = ''`, capability-checked, REVOKEd from `public`/`anon`/`authenticated` and GRANTed to `authenticated`. See §7 and §8 preambles for the standing discipline.

- **Read RPCs**
  - `list_approvals_dashboard(p_ws_id, p_proj_id, p_view, p_status_filter, p_policy_filter, p_requester_ids, p_approver_profile_ids, p_cursor_updated_at, p_cursor_id, p_limit)`
  - `get_approval(p_approval_request_id)`
  - `get_approval_chain(p_root_approval_request_id)`
  - `list_approvals_for_version(p_version_id)`
  - `get_approval_readiness(p_version_id)` — returns `{ has_approved bool, latest_outcome jsonb, blocking_requests uuid[] }` where `latest_outcome = { status text, outcome_at timestamptz, request_id uuid }`.
  - `get_approval_inbox_count(p_ws_id)`
  - `get_project_approval_metrics(p_proj_id)` / `get_workspace_approval_metrics(p_ws_id)`
- **Write RPCs**
  - `create_approval_draft(p_project_id, p_design_asset_id, p_version_id, p_policy, p_approver_wm_ids uuid[], p_approver_sh_ids uuid[], p_title, p_description, p_due_at, p_quorum_min default null, p_expires_at default null, p_related_review_id default null, p_approver_required boolean[] default '{}', p_approver_veto_power boolean[] default '{}', p_approver_sort_order integer[] default '{}')`
  - `request_approval(...)` — Option A: preserves frozen 9-arg signature; adds tail `p_quorum_min`, `p_expires_at`, `p_related_review_id`, `p_approver_required`, `p_approver_veto_power`, `p_approver_sort_order`, `p_supersedes_approval_request_id`.
  - `send_approval_request(p_approval_request_id)`
  - `respond_to_approval(...)` — Option A: preserves frozen 3-arg signature; adds tail `p_is_veto_cast boolean default false`. Rejects `p_decision = 'changes_requested'` at input (F-2.1). Enforces mandatory reason via the widened `comment` CHECK. Requester-cannot-self-approve enforced both at RPC layer AND by the new `approval_responses_no_self_approve` trigger (§10.2).
  - `cancel_approval(p_approval_request_id, p_reason, p_cancellation_reason)` — Option A: preserves frozen 2-arg signature; new mandatory `p_cancellation_reason` maps to §2.6.
  - `expire_approval(p_approval_request_id, p_reason)`
  - `supersede_approval_request(p_old_request_id, p_new_target_version_id, p_policy, p_quorum_min, p_due_at, p_deadline_at, p_expires_at, p_related_review_id, p_approver_wm_ids uuid[], p_approver_sh_ids uuid[], p_approver_required boolean[] default '{}', p_approver_veto_power boolean[] default '{}', p_approver_sort_order integer[] default '{}', p_note text default null)`
  - `add_approver`, `remove_approver`, `reassign_approver`, `set_approver_required`, `set_approver_veto_power` — roster mutation family (see §8.8).
- **Reused unchanged from APP 006**: `toggle_bookmark`, `save_dashboard_view`, `delete_dashboard_view`.

### Updated capability surface

Three new capability keys; defaults per §6:

| Capability | Default roles | Notes |
|---|---|---|
| `approval.veto` | `lead` only | Gates assigning a veto-power approver at request creation time (F-5.1). |
| `approval.expire` | `lead` (+ workspace-admin override) | Force-expire before `expires_at`. |
| `approval.supersede` | `lead` + `contributor` | Chain supersession. |

### Updated event surface

**New emitted event types (APP 007-owned emitters):**
- `approval.sent` — `send_approval_request` on `draft → pending`.
- `approval.expired` — `expire_approval` OR future cron.
- `approval.superseded` — `supersede_approval_request` on the OLD request.

**Payload extensions on already-frozen events (F-4.1):**
- `approval.requested`
- `approval.responded`
- `approval.cancelled`
- `approval.approved` — already emitted by AUTH 007 (`respond_to_approval` L326); this proposal only adds payload keys.
- `approval.rejected` — same.

**RESERVED names (name-only lock, no emitter in APP 007):**
- `approval.deadline_approached` (past-tense, per F-4.2)
- `approval.reminder_sent`
- `approval.escalated`
- `approval.state_changed`

`round_number` is not present in any approval event payload (F-4.3).

### Updated trigger surface

Only two **new** triggers ship as part of APP 007:

1. `approval_requests_chain_immutable` (BEFORE UPDATE) — guards `supersedes_approval_request_id`, `root_approval_request_id`, and `related_review_id` from mutation (§10.1, F-10.2).
2. `approval_responses_no_self_approve` (BEFORE INSERT) — reads `approval_requests.created_by_profile_id` and raises `errcode 23514` when it equals `NEW.responder_profile_id` (§10.2, F-2.4).

Retained frozen: `enforce_approval_request_target_eligibility`, `approval_responses_slot_coherence`, `enforce_approval_response_immutable`. The redundant response-immutability trigger from the prior draft is removed (F-7.2).

Wave 2 adds: `set_updated_at` on `approval_request_approvers` (F-7.3) alongside roster-mutation RPCs.

### Updated implementation waves

Recounted in §19 to reflect: −1 column (`decision_reason` deleted, F-2.2), −1 trigger (redundant response-immutability removed, F-7.2), +1 trigger (`no_self_approve` added, F-2.4), reclassification of `approval.approved`/`approval.rejected` from new events to payload extensions (F-4.1).

### Updated coverage matrix

See the final matrix under "Coverage matrix — Proposal section ↔ Freeze Index gap" at the end of this document.

### Explicit confirmation APP 001–006 unchanged

- **APP 001 (Domain Model)** — unchanged. APP 007 honors the 7-way XOR comment target, `roles-as-capability-sets`, immutability rules on outcome records.
- **APP 002 (Application Shell)** — unchanged. APP 007 extends `qk`, `CAPABILITY_KEYS`, `DeepLinkResolver`, `NavItem`/`NavRail` additively only.
- **APP 003 (Projects & Design Workspace)** — unchanged. APP 007 consumes project/asset/discipline context; adds a RightPanel tab body.
- **APP 004 (Files & Viewer)** — unchanged. APP 007 reads `useSignedUrl` and `FilesPanel` only.
- **APP 005 (Comments & Annotations)** — unchanged. APP 007 uses the pre-existing `target_approval_request_id` XOR arm without introducing a new arm.
- **APP 006 (Reviews)** — unchanged. `RosterEditor` reused as-is; `list_reviews_dashboard`, `get_review`, `get_review_chain`, `reviews_chain_immutable` are pattern precedents but not modified.

### Final backend freeze verdict

The verdict line is stated at the end of this document.

---

## 0. Convention

Every proposed change carries four attributes:

- **Why:** the concrete user-facing behavior or invariant it enables.
- **Section:** the APP 007 Freeze Index section (`§n`) or gap ID (`G-n`) that requires it.
- **Priority:** `Critical` | `High` | `Medium` | `Future`.
- **Blocks implementation:** `None (nice-to-have)`, `v1 subset`, `v1 entirely`, or `v2 only`.

Priority tiers:

| Tier | Meaning |
|---|---|
| **Critical** | v1 cannot ship at all without this. Must land in the first re-freeze wave. |
| **High** | v1 can start but a major feature is degraded / stubbed. First or second wave. |
| **Medium** | Polish / enterprise-adjacent; v1 works without it. Third wave. |
| **Future** | v2 territory; explicitly out of APP 007 v1 shipping scope. |

---

## 0a. Frozen baseline (what already exists)

Verified against the deployed schema. **These are not proposed additions** — they are the frozen surface APP 007 inherits and extends.

### `public.approval_requests` (frozen)

Columns: `id`, `workspace_id`, `project_id`, `design_asset_id`, `version_id`, `policy`, `status`, `title`, `description`, `due_at`, `sent_at`, `outcome_at`, `outcome_actor_profile_id`, `outcome_note`, `created_by_profile_id`, `created_at`, `updated_at`.

CHECKs: `status ∈ {pending, in_progress, approved, rejected, cancelled, expired}`; `policy ∈ {any, all}`; outcome-metadata gate (`status ∈ terminal → outcome_at IS NOT NULL`); sent-metadata gate (`status = pending → sent_at IS NOT NULL`).

FKs: composite tenancy `(design_asset_id, project_id, workspace_id)` to `design_assets`; `(version_id, design_asset_id)` to `asset_versions`; author FKs to `profiles`.

**Frozen partial-unique index (cited throughout §8.7 and §14):**
```
create unique index approval_requests_active_target_key
  on public.approval_requests (design_asset_id, version_id)
  where status in ('pending','in_progress');
```
Source: `supabase/migrations/20260729220000_approval_model.sql` L119–L121. **`draft` and `superseded` (both proposed here in §5.2) are excluded from the WHERE predicate**, so neither state participates in the active-target uniqueness check.

### `public.approval_request_approvers` (frozen — roster/slot table)

Columns: `id`, `workspace_id`, `approval_request_id`, `workspace_member_id | stakeholder_id` (XOR), `sort_order`, `created_at`, `updated_at`.

CHECKs: XOR actor identity; `sort_order >= 0`.

**Naming note:** the freeze index (§3) called this "approval participants" conceptually; the frozen table is named `approval_request_approvers`. APP 007 uses the frozen name.

### `public.approval_responses` (frozen — the decision record)

Columns: `id`, `workspace_id`, `approval_request_id`, `approver_slot_id`, `responder_profile_id`, `decision`, `comment`, `responded_at`, `created_at`, `updated_at`.

CHECKs: `decision ∈ {approved, rejected, changes_requested}`; UNIQUE on `approver_slot_id` (one response per slot). Response immutability additionally enforced by the frozen `enforce_approval_response_immutable` trigger (migration `20260729220000_approval_model.sql` L403–L427) on UPDATE and DELETE.

**There is no separate `approvals` outcome table.** The outcome is embedded on `approval_requests` via `outcome_at`, `outcome_actor_profile_id`, `outcome_note`. APP 007 preserves this design.

### Frozen RPCs

- `request_approval(p_project_id, p_design_asset_id, p_version_id, p_policy, p_approver_wm_ids[], p_approver_sh_ids[], p_title, p_description, p_due_at)`
- `respond_to_approval(p_approver_slot_id, p_decision, p_comment)` — emits `approval.responded` on write and, on terminal outcome, `approval.approved` OR `approval.rejected` (see AUTH 007 migration L326).
- `cancel_approval(p_approval_request_id, p_reason)`

### Frozen capabilities

`approval.view`, `approval.request`, `approval.respond`, `approval.cancel`.

### Frozen deltas vs. APP 007 Freeze Index

- Status enum missing: `draft`, `superseded` (frozen has 6 values; APP 007 needs 8).
- Policy enum is currently only `{any, all}`; APP 007 needs `{single, unanimous, majority, quorum, sequential}` widened additively (preserving `any`/`all` as aliases).
- No `expires_at`, no dedicated `cancellation_reason`.
- No `related_review_id`, no `supersedes_approval_request_id`, no `root_approval_request_id`.
- No `quorum_min`.
- Response `decision` enum missing `abstained` — added additively per F-2.1 (see §5.3).
- Roster table has no `required`, `veto_power`, `removed_at`, `removed_reason`.
- Response table has no mandatory reason on `comment` — widened CHECK per F-2.2 (see §2.10, §4.5).
- No chain-immutability trigger. No requester-self-approve trigger. Response-immutability is already handled by the frozen trigger (F-7.2 — no new response-immutability trigger required).

---

## 1. New tables

**None.** APP 007 v1 introduces zero new tables. Every domain entity fits within the frozen `approval_requests` / `approval_request_approvers` / `approval_responses` triple. Bookmarks and saved views reuse APP 006's `user_bookmarks` (with `subject_kind='approval_request'`) and `user_saved_views` (with `scope='approvals'`).

**Priority:** N/A. **Blocks:** None.

---

## 2. New columns on existing tables

All on existing frozen tables. All additive; no drops, no renames.

**House pattern (F-1.4).** Every new column below ships with a matching `COMMENT ON COLUMN` in the same migration, per APP 006 house pattern. Not enumerated per column below.

### 2.1 `approval_requests.expires_at timestamptz null`

- **Why:** APP 007 architecture (§4, §5) distinguishes `due_at` (soft target) from `expires_at` (hard cutoff that triggers `expired` transition). Enterprise approval flows need a distinct hard deadline field with dedicated scheduled-emitter semantics.
- **Section:** §3.1 (ApprovalRequest domain), §4 (lifecycle: `expired` transition), G-6.
- **Priority:** High.
- **Blocks:** v1 subset — v1 can ship without auto-expiry; the cron slice depends on this column.

### 2.2 `approval_requests.related_review_id uuid null`

- **Why:** Loose informational link to a completed APP 006 review (Freeze Index §8, §3.1). Never enforced by release/requirement layers; purely audit + UX.
- **Shape note:** composite FK `(related_review_id, workspace_id) → reviews(id, workspace_id)` on delete SET NULL.
- **Section:** §3.1, §8.1–§8.3, G-3.
- **Priority:** Medium.
- **Blocks:** v1 subset.

### 2.3 `approval_requests.supersedes_approval_request_id uuid null`

- **Why:** Chain support (Freeze Index §3.5, §4.4). A new request may supersede a prior non-terminal one.
- **Shape note:** composite FK `(supersedes_approval_request_id, workspace_id) → approval_requests(id, workspace_id)` on delete RESTRICT.
- **Section:** §3.5 (chains), §4 (state machine), G-2.
- **Priority:** Critical.
- **Blocks:** v1 entirely.

### 2.4 `approval_requests.root_approval_request_id uuid null`

- **Why:** Chain-grouping convenience pointer, mirrors APP 006's `root_review_id`. Set to self on the first request in a chain. **Must be inserted inline** (never post-INSERT UPDATE) — see F-7.1 / §10.1.
- **Shape note:** composite FK same as `supersedes_approval_request_id`.
- **Section:** §3.5, G-2.
- **Priority:** Critical.
- **Blocks:** v1 entirely.

### 2.5 `approval_requests.quorum_min integer null`

- **Why:** Threshold when `policy = 'quorum'`.
- **Shape note:** CHECK `(policy <> 'quorum') OR (quorum_min IS NOT NULL AND quorum_min > 0)`.
- **Section:** §5.4, G-5.
- **Priority:** High.
- **Blocks:** v1 subset.

### 2.6 `approval_requests.cancellation_reason text null`

- **Why:** Mandatory-on-cancel reason for audit (mirrors APP 006 D-8). Keeping cancellation reason distinct from `outcome_note` preserves audit clarity.
- **Shape note:** CHECK `(status <> 'cancelled') OR (cancellation_reason IS NOT NULL AND length(cancellation_reason) BETWEEN 3 AND 500)`.
- **Section:** §11.4, G-7.
- **Priority:** High.

### 2.7 `approval_request_approvers.required boolean not null default true`

- **Why:** Required vs optional approver distinction. Required approvers block outcome computation; optional are courtesy-notified.
- **Section:** §3.2, §5, G-8.
- **Priority:** Critical.

### 2.8 `approval_request_approvers.veto_power boolean not null default false`

- **Why:** Per-approver veto flag (Freeze Index §5.6). Composes orthogonally with any base policy.
- **Section:** §5.6, G-10.
- **Priority:** High.

### 2.9 `approval_request_approvers.removed_at timestamptz null` + `removed_reason text null`

- **Why:** Soft-remove path for approvers who have already responded but need to be marked removed for audit (mirrors APP 006 pattern).
- **Shape note (tight form):** CHECK `(removed_at IS NULL AND removed_reason IS NULL) OR (removed_at IS NOT NULL AND removed_reason IS NOT NULL AND length(removed_reason) BETWEEN 3 AND 500)`.
- **Section:** §3.2 (approver mutation), G-8 (paired with `required`).
- **Priority:** High.

### 2.10 `approval_responses.comment` — mandatory reason via widened CHECK

- **Correction (F-2.2 HIGH — applied):** the earlier draft proposed *either* adding a distinct `decision_reason` column *or* widening the existing `comment` CHECK. That contradiction is resolved here: **the canonical schema widens the existing `comment` column with a NOT-NULL-effective CHECK**. The `decision_reason` alternative is deleted from this proposal.
- **Rationale:** avoids column duplication; matches APP 006's pattern where free-text reasoning lives on the single response row. There is no production data to backfill, so the check can be applied directly.
- **Shape note:** `CHECK (length(coalesce(comment, '')) BETWEEN 3 AND 2000)` — every response is a terminal decision (per-slot immutability via the frozen UNIQUE + `enforce_approval_response_immutable` trigger), so the reason is always required.
- **Section:** §3.3, §7.2, G-11.
- **Priority:** Critical.

### 2.11 `approval_responses.decision_metadata jsonb null`

- **Why:** Reserved column for e-signature, IP, device fingerprint, second-factor confirmation (Freeze Index §3.2, §11.4). v2 audit-tier feature.
- **Section:** §3.2, G-12.
- **Priority:** Future.
- **Blocks:** None. Column reservation only; no UI in v1.

### 2.12 `approval_responses.is_veto_cast boolean not null default false`

- **Why:** Record whether a `rejected` decision was cast under veto authority (i.e. the responding approver's slot had `veto_power = true`). Denormalized from the slot at decision time so the audit trail is self-contained.
- **Shape note:** CHECK `(is_veto_cast = false) OR (decision = 'rejected')`.
- **Section:** §5.6, event payload for `approval.rejected`.
- **Priority:** High.

---

## 3. Indexes

Every new FK gets a covering index in the same migration (SCHEMA_V1_LOCK house rule).

| Index | Purpose | Priority | Blocks |
|---|---|---|---|
| `approval_requests_root_id_idx` on `approval_requests(root_approval_request_id)` where `root_approval_request_id IS NOT NULL` | Chain queries in `get_approval_chain(root)`; dashboard grouping | Critical | v1 entirely |
| `approval_requests_supersedes_id_idx` on `approval_requests(supersedes_approval_request_id)` where not null | Reverse chain traversal | Critical | v1 entirely |
| `approval_requests_related_review_id_idx` on `approval_requests(related_review_id)` where not null | Cross-slice back-reference; APP 009 read paths | Medium | v1 subset |
| `approval_requests_project_status_idx` on `approval_requests(project_id, status, updated_at desc)` | Project dashboard filter + sort | Critical | v1 entirely |
| `approval_requests_workspace_status_updated_idx` on `approval_requests(workspace_id, status, updated_at desc)` | Workspace dashboard | Critical | v1 entirely |
| `approval_requests_version_status_idx` on `approval_requests(version_id, status)` | `list_approvals_for_version` (Design Workspace tab + APP 009 readiness) | Critical | v1 entirely |
| `approval_requests_expires_at_partial_idx` on `approval_requests(expires_at)` where `status in ('pending','in_progress') and expires_at is not null` | Cron scan for auto-expire | High | v1 subset |
| `approval_request_approvers_request_required_idx` on `approval_request_approvers(approval_request_id, required)` where `removed_at is null` | Outcome-computation queries per request | Critical | v1 entirely |
| `approval_request_approvers_wm_idx` on `approval_request_approvers(workspace_member_id) where workspace_member_id is not null and removed_at is null` | "Awaiting my decision" inbox | Critical | v1 entirely |
| `approval_request_approvers_sh_idx` on `approval_request_approvers(stakeholder_id) where stakeholder_id is not null and removed_at is null` | "Awaiting my decision" for stakeholders | Critical | v1 entirely |
| `approval_responses_request_idx` on `approval_responses(approval_request_id, responded_at desc)` | Decisions tab ordering | High | v1 subset |
| `approval_responses_responder_idx` on `approval_responses(responder_profile_id, responded_at desc)` | Approver-throughput metrics | Medium | v1 subset |

Existing frozen indexes on `approval_*` tables remain unchanged.

---

## 4. Constraints

### 4.1 Composite tenancy FKs (chain)

- `approval_requests.supersedes_approval_request_id → approval_requests(id, workspace_id)` on delete RESTRICT.
- `approval_requests.root_approval_request_id → approval_requests(id, workspace_id)` on delete RESTRICT.
- `approval_requests.related_review_id → reviews(id, workspace_id)` on delete SET NULL.

**Priority:** Critical (chain FKs); Medium (review link).

### 4.2 Chain integrity CHECKs

- **Root self-reference on the first request in a chain:** `CHECK ((supersedes_approval_request_id IS NULL AND (root_approval_request_id IS NULL OR root_approval_request_id = id)) OR (supersedes_approval_request_id IS NOT NULL AND root_approval_request_id IS NOT NULL))`. **The first request has `supersedes = NULL` and `root = self`; superseding requests have both non-null and inserted inline** (see F-7.1 / §10.1 for the mandatory pre-computed-UUID discipline).
- **Section:** §3.5. **Priority:** Critical.

### 4.3 Policy consistency CHECK

- `CHECK ((policy <> 'quorum') OR (quorum_min IS NOT NULL AND quorum_min > 0))`.
- **Priority:** High.

### 4.4 Cancellation-reason presence CHECK

- Covered in §2.6.
- **Priority:** High.

### 4.5 Response mandatory-reason CHECK (widened `comment`)

- **Correction (F-2.2 applied):** `CHECK (length(coalesce(comment, '')) BETWEEN 3 AND 2000)` on `approval_responses.comment`. Enforces §2.10.
- **Priority:** Critical.

### 4.6 Veto cast consistency CHECK

- Covered in §2.12.
- **Priority:** High.

### 4.7 Removal pair CHECK

- Covered in §2.9.
- **Priority:** High.

### 4.8 Existing frozen constraints (preserved)

- Outcome-metadata gate expanded to include `superseded`: `(status NOT IN ('approved','rejected','cancelled','expired','superseded')) OR (outcome_at IS NOT NULL)`.
- Sent-metadata gate relaxed to permit `draft`: `(status IN ('draft','pending')) OR (sent_at IS NOT NULL)`.
- **Priority:** Critical.

### 4.9 Published-only target discipline preserved (F-2.3 applied)

Even `draft` approval requests require a `published` target `asset_versions` row. The frozen `enforce_approval_request_target_eligibility` trigger (migration `20260729220000_approval_model.sql` L167–L206) fires on INSERT **regardless of `NEW.status`** — the discipline is not relaxed for draft. Adding `draft` to the status enum does NOT bypass this trigger; the RPCs (`create_approval_draft` in §8.1 and `supersede_approval_request` in §8.7) must not attempt to reference an unpublished version. This is a documentation-only reaffirmation — no schema change.

---

## 5. Enum / CHECK additions

### 5.1 `approval_requests.policy` — enum widening

**Change:** current CHECK `policy IN ('any', 'all')` expands to `policy IN ('single','unanimous','majority','quorum','sequential','any','all')`.

- **Why:** Freeze Index §5 defines five policies. `any` maps semantically to `single`; `all` maps to `unanimous`. Both preserved for backwards compatibility.
- **Recommendation:** preserve `any` and `all` in the enum indefinitely; write-side RPCs accept only the five new values.
- **Section:** §5.1–§5.5, G-4.
- **Priority:** High.

### 5.2 `approval_requests.status` — enum widening

**Change:** expand to `{draft, pending, in_progress, approved, rejected, cancelled, expired, superseded}` (8 values).

- **Why:** Freeze Index §4.1. `draft` is required by the composer; `superseded` is required by chain semantics.
- **Downstream CHECK changes:** outcome-metadata gate includes `superseded`; sent-metadata gate permits `draft`.
- **Section:** §4.1, G-1.
- **Priority:** Critical.

### 5.3 `approval_responses.decision` — enum widening (F-2.1 applied)

**Change:** current CHECK `decision IN ('approved','rejected','changes_requested')` expands to `decision IN ('approved','rejected','abstained','changes_requested')`.

**Correction from prior draft:** the earlier text suggested frontend would *alias* `changes_requested → abstained` for display purposes. That is rescinded. The corrected posture is:

- **`abstained` is a genuinely new enum value**, added additively.
- **`changes_requested` is preserved verbatim** as a legal enum value for historical rows and for backwards compatibility of the frozen `respond_to_approval` RPC's return semantics.
- **New RPC entry-points reject `changes_requested`** at input (`respond_to_approval` extended-tail wrapper, `create_approval_draft`'s validation of any downstream response reflection). New call sites use `abstained`.
- **`abstained` does NOT count in `v_non_approved`** and never terminates the request under policy `all` (unanimous). It is a genuine no-op on outcome arithmetic.
- **No frontend aliasing.** Display layers render each value distinctly; audit trails preserve verbatim what was written.
- **`changes_requested` is officially deprecated for new writes**, but preserved for read compatibility indefinitely.

- **Section:** §3.3, §7.2. **Priority:** Critical.

### 5.4 Outcome-metadata gate (revised)

- `(status NOT IN ('approved','rejected','cancelled','expired','superseded')) OR (outcome_at IS NOT NULL)`.
- **Priority:** Critical.

### 5.5 Sent-metadata gate (revised) + sequential-policy ordering (F-1.2 applied)

- **Sent-metadata gate:** `(status IN ('draft','pending')) OR (sent_at IS NOT NULL)`.
- **Sequential-policy ordering (F-1.2 HIGH — applied):** when `policy = 'sequential'`, the request's approver slots MUST have distinct `sort_order` values `0..N-1`. Enforcement is at the RPC layer in this wave: `request_approval`, `create_approval_draft`, `supersede_approval_request`, `add_approver`, `set_approver_sort_order` all validate at input and raise `errcode 22023` on collision or gap. The frozen `sort_order` CHECK (>=0) and default (0) are preserved as-is. **A per-request DB-enforced uniqueness constraint is deferred to v2** to keep this wave additive.
- **Priority:** Critical (gate); High (sequential ordering RPC guard).

---

## 6. New capability keys

Three additions. Extends PERMISSIONS.md.

**PERMISSIONS.md registration checklist (F-5.2 applied):**

- `approval.veto` → `CAPABILITY_KEYS.APPROVAL_VETO` → PERMISSIONS.md §5 role table row: granted to `lead` only.
- `approval.expire` → `CAPABILITY_KEYS.APPROVAL_EXPIRE` → PERMISSIONS.md §5 role table row: granted to `lead` (+ workspace-admin override).
- `approval.supersede` → `CAPABILITY_KEYS.APPROVAL_SUPERSEDE` → PERMISSIONS.md §5 role table row: granted to `lead` + `contributor`.

### 6.1 `approval.veto`

- **Correction (F-5.1 MEDIUM — applied):** **Default granted to `lead` only.** This matches APP 006's coordinator-capability pattern of restricting powerful capabilities to the lead role. The Freeze Index §11.3 role-map has been corrected in the same pass to reflect this.
- **Why:** Governance-tier capability that gates *whether the requester can assign someone as a veto-power approver at request creation time*. Distinct from `approval.respond`.
- **Section:** §11.2–§11.3, G-31. **Priority:** High.

### 6.2 `approval.expire`

- **Why:** Force-expire a stalled approval before `expires_at`. Default: `lead` + workspace-admin override.
- **Section:** §4.3, §11.2–§11.3, G-32. **Priority:** Medium.

### 6.3 `approval.supersede`

- **Why:** Governance capability distinct from `approval.request`. Default: `lead` + `contributor`.
- **Section:** §11.2–§11.3, G-33. **Priority:** Critical.

**No other capability additions.** `approval.view / request / respond / cancel` (frozen) cover everything else.

---

## 7. Read RPCs

**Standing discipline (F-3.4, applied here as a per-section-header restatement):** every SECURITY DEFINER function in §7 and §8 sets `search_path = ''`, REVOKEs from `public` / `anon` / `authenticated` before GRANT to `authenticated` on the RPC (not on the trigger function — see §10 preamble).

All read RPCs are capability-checked, read-only. Rationale mirrors APP 006: RLS on roster/response tables doesn't compose cleanly with per-row aggregations across requests.

### 7.1 `list_approvals_dashboard(scope, view, filters, cursor, limit)`

- **Purpose:** Powers every dashboard view.
- **Params:** `p_ws_id uuid`, `p_proj_id uuid`, `p_view text`, `p_status_filter text[]`, `p_policy_filter text[]`, `p_requester_ids uuid[]`, `p_approver_profile_ids uuid[]`, `p_cursor_updated_at timestamptz`, `p_cursor_id uuid`, `p_limit integer`.
- **Section:** §6, §12, G-20. **Priority:** Critical.

### 7.2 `get_approval(approval_request_id)`

- **Purpose:** Powers Approval Detail. Returns request + full slots (with responder identity resolved) + response list + metrics + chain position + outcome (if terminal).
- **Returns:** jsonb with keys `request`, `slots`, `responses`, `metrics`, `chain_position`.
- **Section:** §7, §12, G-21. **Priority:** Critical.

### 7.3 `get_approval_chain(root_approval_request_id)`

- **Purpose:** Returns all requests in a supersession chain, ordered by `created_at asc`.
- **Section:** §3.5, §7.3, §12, G-22. **Priority:** High.

### 7.4 `list_approvals_for_version(version_id)`

- **Purpose:** Powers the Design Workspace RightPanel Approvals tab AND APP 009 release-readiness computation.
- **Section:** §10.1, §12, G-23. **Priority:** Critical.

### 7.5 `get_approval_readiness(version_id)` — reconciled with Freeze Index §10.1 (F-3.3 applied)

- **Purpose:** Convenience for APP 009.
- **Returns:** `{ has_approved boolean, latest_outcome jsonb, blocking_requests uuid[] }` where `latest_outcome = { status text, outcome_at timestamptz, request_id uuid }`.
- **APP 009 discipline:** to find "the latest approval" for a version, APP 009 sorts by `outcome_at desc` (see F-10.1 in §14). Since `approved` requests cannot be superseded (§3.5), a fresh approval on the same asset after an approved outcome is an independent request and is discovered by the same `outcome_at desc` scan.
- **Section:** §10.1, G-24. **Priority:** Medium.

### 7.6 `get_approval_inbox_count(ws_id)`

- **Purpose:** NavRail badge. Returns `{awaiting_my_decision, expiring_soon, coordinating}`.
- **Section:** §12, G-25. **Priority:** High.

### 7.7 `get_project_approval_metrics(proj_id)` and `get_workspace_approval_metrics(ws_id)`

- **Purpose:** Metrics strip above dashboards.
- **Section:** §16, G-26. **Priority:** Medium.

---

## 8. Write RPCs

**Standing discipline (F-3.4):** every write RPC below is SECURITY DEFINER, `search_path = ''`, input-validated, capability-re-checked, and emits one canonical event per success path. REVOKE from `public` / `anon` / `authenticated`, GRANT to `authenticated`.

### 8.1 `create_approval_draft(...)` — new

- **Purpose:** Create a request in `draft` state.
- **Params:** all `request_approval` params (extended per §8.2) but WITHOUT any auto-open; always draft.
- **Chain-initialization discipline (F-7.1 CRITICAL — applied):** the RPC MUST pre-compute the new `approval_requests.id` via `gen_random_uuid()` and INSERT with `root_approval_request_id = <the pre-computed id>` (self, since a fresh draft is a chain root) and `supersedes_approval_request_id = NULL` in a **single INSERT**. A post-INSERT UPDATE of either chain column is forbidden — the chain-immutability trigger in §10.1 raises `errcode 23514`. **Cite APP 006 T-CRIT-1 precedent.**
- **Section:** §4.1 (draft state), §4.3 transitions, G-16.
- **Priority:** Critical.

### 8.2 `request_approval(...)` — extended (Option A additive tail params)

Preserves frozen 9-arg signature as a backwards-compatible overload; adds tail params:
- `p_quorum_min integer default null` (required when `p_policy = 'quorum'`).
- `p_expires_at timestamptz default null`.
- `p_related_review_id uuid default null`.
- `p_approver_required boolean[] default '{}'`.
- `p_approver_veto_power boolean[] default '{}'`.
- `p_approver_sort_order integer[] default '{}'`.
- `p_supersedes_approval_request_id uuid default null` (when non-null, authorized under `approval.supersede`).

**Metadata-array ordering (F-3.1 HIGH — applied).** The lengths of `p_approver_required`, `p_approver_veto_power`, and `p_approver_sort_order` each equal `len(p_approver_wm_ids) + len(p_approver_sh_ids)`. **Workspace-member approvers come first in the concatenation order, followed by stakeholders.** Empty arrays default per-approver to `required=true`, `veto_power=false`, and `sort_order = index_in_concatenation`. Index `i` of each metadata array applies to the approver at position `i` in the concatenated `wm_ids || sh_ids` roster. This ordering rule is identical for `supersede_approval_request` (§8.7) and the roster-mutation RPCs in §8.8.

**Sequential-policy validation (F-1.2):** when `p_policy = 'sequential'`, the effective `sort_order` values across all approvers on this request MUST be a distinct set covering `0..N-1`. Raise `errcode 22023` on any collision or gap.

- **Section:** §5, §12, G-4 through G-10. **Priority:** Critical.

### 8.3 `send_approval_request(approval_request_id)` — new

- **Purpose:** Transition `draft → pending`. Requires ≥1 approver on the roster. Emits `approval.sent` (new event, §12).
- **Capability:** `approval.request`.
- **Section:** §4 (state machine), G-17. **Priority:** Critical.

### 8.4 `respond_to_approval(...)` — extended (Option A)

Preserves frozen 3-arg signature; adds tail params:
- `p_is_veto_cast boolean default false` — only settable when the slot has `veto_power = true` AND `p_decision = 'rejected'`. RPC validates.

RPC body:
- **Validates mandatory reason** (`p_comment` must be non-null, length 3–2000) per §4.5.
- **Rejects `p_decision = 'changes_requested'`** at the extended entry-point (F-2.1); accepts `approved | rejected | abstained`.
- **Requester-cannot-self-approve** — checked at the RPC layer AND enforced at the DB boundary by the new `approval_responses_no_self_approve` trigger (§10.2, F-2.4).
- **Refuses if the slot has already responded** (frozen UNIQUE + frozen `enforce_approval_response_immutable`).
- **Computes outcome inline** when policy is satisfied and writes outcome fields on `approval_requests` in the same transaction.
- **Emits** `approval.responded` (payload extended per §11.2) and, when terminal, one of `approval.approved` / `approval.rejected` (payload extended per §11.5). `approval.approved` and `approval.rejected` are already emitted by AUTH 007 (`respond_to_approval` L326); this proposal only extends the payload additively.

- **Section:** §3.3, §4, §5, §7.2, §11.4, G-11. **Priority:** Critical.

### 8.5 `cancel_approval(...)` — extended

Preserves frozen 2-arg signature; adds `p_cancellation_reason text` (mandatory, mapped to §2.6 column).

- **Section:** §4, §11.4, G-7. **Priority:** High.

### 8.6 `expire_approval(approval_request_id, reason)` — new

- **Purpose:** Admin/coordinator force-expire before `expires_at`. Emits `approval.expired`. Refuses on terminal requests.
- **Capability:** `approval.expire`.
- **Section:** §4.3, G-18. **Priority:** Medium.

### 8.7 `supersede_approval_request(...)` — new (F-3.2 applied; params enumerated)

**Signature (Option A additive-tail style):**

```
supersede_approval_request(
  p_old_request_id            uuid,
  p_new_target_version_id     uuid,
  p_policy                    text,
  p_quorum_min                integer         default null,
  p_due_at                    timestamptz     default null,
  p_deadline_at               timestamptz     default null,
  p_expires_at                timestamptz     default null,
  p_related_review_id         uuid            default null,
  p_approver_wm_ids           uuid[],
  p_approver_sh_ids           uuid[],
  p_approver_required         boolean[]       default '{}',
  p_approver_veto_power       boolean[]       default '{}',
  p_approver_sort_order       integer[]       default '{}',
  p_note                      text            default null
)
```

`p_note` is recorded on the chain audit trail (as part of the new request's `description` prefix or an `activity_events` payload key, per implementation preference).

**Capability:** `approval.supersede`.

**Behavior (F-1.1 CRITICAL + F-7.1 CRITICAL + F-10.1 CRITICAL — all applied):**

The RPC executes atomically:

1. **`SELECT … FOR UPDATE`** on `approval_requests` where `id = p_old_request_id` — locks the old row.
2. **Validate the old request's status is `pending` or `in_progress`** (F-10.1). Refuse with `errcode 23514` if the old request is `approved` (already terminal and immutable), `rejected`, `expired`, `cancelled`, or `superseded`. A fresh approval on the same asset after an approved outcome is created via `create_approval_draft` + `send_approval_request` and is an **independent** (unchained) request; APP 009 discovers it via `outcome_at desc` on `list_approvals_for_version`.
3. **Transition the old request to `superseded`** — sets `status='superseded'`, `outcome_at = now()`, `outcome_actor_profile_id = auth.uid()`, and (optionally) records `p_note` on the old row's `outcome_note` — BEFORE inserting the new row.
4. **Pre-compute the new `approval_requests.id` via `gen_random_uuid()`** (F-7.1). Compute `v_root := coalesce(old.root_approval_request_id, old.id)`.
5. **INSERT the new `approval_requests` row in `draft` state** with:
   - `id = <pre-computed uuid>`
   - `supersedes_approval_request_id = p_old_request_id`
   - `root_approval_request_id = v_root`
   - `related_review_id = p_related_review_id`
   - `version_id = p_new_target_version_id`
   - all chain and immutable columns set **inline in this INSERT**. A subsequent UPDATE of any chain column would raise via the §10.1 trigger.
6. **Frozen `approval_requests_active_target_key` unique index interaction** (F-1.1): the index (migration `20260729220000_approval_model.sql` L119–L121) covers only `status in ('pending','in_progress')`. Because step (3) transitions the old row to `superseded` (removing it from the index's WHERE predicate) and step (5) inserts the new row as `draft` (also outside the WHERE predicate), no unique-index conflict arises regardless of whether the new request targets the same version as the old one. **The modal case is supersession that targets a new version, in which case no unique-index interaction arises at all.**
7. **Copy the old request's roster** (respecting `removed_at`) to the new request, honoring the metadata-array ordering rule from §8.2.
8. **Emit** `approval.superseded` on the old request; emit `approval.requested` on the new one (still in `draft`; the requester then calls `send_approval_request` when ready).

- **Section:** §3.5, §4.4, G-19. **Priority:** Critical.

### 8.8 `add_approver`, `remove_approver`, `reassign_approver`, `set_approver_required`, `set_approver_veto_power`, `set_approver_sort_order` — new (roster mutation family)

- **Purpose:** Roster mutation on non-terminal requests. Mirrors APP 006 shape.
- **Capability:** `approval.request` (parity with the frozen model; requester + admin can mutate the roster). For `set_approver_veto_power`, additionally re-check `approval.veto` when setting `veto_power = true`.
- **DEFINER-over-zero-policy discipline (F-6.2 MEDIUM — applied):** `add_approver` (and every roster-mutation RPC in this family) executes under SECURITY DEFINER and bypasses the frozen zero-policy RLS on `approval_request_approvers`. Row visibility to end users remains gated by `approval.view`. Application-layer authorization is re-checked at the top of each function.
- **Metadata-array ordering:** identical rule as §8.2 when mutation involves multiple approvers in a single call.
- **Section:** §3.2, §11.4. **Priority:** High for `add_approver`; Medium for the rest.

### 8.9 `toggle_bookmark`, `save_dashboard_view`, `delete_dashboard_view`

**Reused from APP 006 unchanged.** Bookmark uses `subject_kind = 'approval_request'`; saved view uses `scope = 'approvals'`.

---

## 9. RLS policies

### 9.1 Frozen policies (preserved)

Existing `approval_requests`, `approval_request_approvers`, `approval_responses` RLS policies (from Migration 007 / AUTH 007) remain unchanged. Roster/response mutation continues to flow through SECURITY DEFINER RPCs.

### 9.2 New capability keys in existing policies

`approval.veto` and `approval.supersede` are re-checked inside their RPCs. No new RLS predicate updates required.

### 9.3 No new tables

No new RLS policy sets required.

**Priority:** N/A.

---

## 10. Triggers

**Standing discipline (F-7.4 LOW — applied):** every trigger function below is SECURITY DEFINER with `search_path = ''`. REVOKE from `public` / `anon` / `authenticated` mirrors APP 006 (see `supabase/migrations/20260801120002_auth_006_trigger_fn_revoke_authenticated.sql` for the precedent). Trigger functions are **never** GRANTed to `authenticated` (only RPCs are); the trigger fires under the row-writer's transaction context and does not need EXECUTE on the function.

**Correction (F-7.2 HIGH — applied):** the earlier draft proposed a new "`approval_responses_immutable` (BEFORE UPDATE)" trigger. That is deleted. The frozen `enforce_approval_response_immutable` trigger (migration `20260729220000_approval_model.sql` L403–L427, wired to both UPDATE and DELETE) already covers response mutation with `errcode 23514`; no new trigger is required. G-15 is downgraded to "already frozen — no change."

Two **new** triggers ship in APP 007 (renumbered so chain-immutability is §10.1 and no-self-approve is §10.2):

### 10.1 `approval_requests_chain_immutable` (new) — F-10.2 applied to immutable-column set

- **Why:** Once inserted, chain columns and cross-slice loose FKs must never change. Mirrors APP 006's `reviews_chain_immutable` precedent.
- **Immutable-column set:** `supersedes_approval_request_id`, `root_approval_request_id`, **and `related_review_id`** (F-10.2 MEDIUM — applied; rationale: `related_review_id` is a cross-slice loose FK, must be set-at-creation-only).
- **Behavior:** `BEFORE UPDATE ON approval_requests FOR EACH ROW` — raises `errcode 23514` if any of the three columns change. Combined with the F-7.1 chain-initialization discipline in §8.1 and §8.7, this guarantees chain integrity is set exactly once (at INSERT) and never mutated.
- **Priority:** Critical (in Wave 1 to match APP 006 precedent).

### 10.2 `approval_responses_no_self_approve` (new) — F-2.4 HIGH — applied

- **Why:** DB-boundary enforcement of the requester-cannot-self-approve invariant (Freeze Index D-11). RPC-layer check in `respond_to_approval` (§8.4) is primary; this trigger is defense-in-depth for the invariant.
- **Behavior:** `BEFORE INSERT ON approval_responses FOR EACH ROW`, SECURITY DEFINER, `search_path=''`. Reads `approval_requests.created_by_profile_id` for `NEW.approval_request_id` and raises `errcode 23514` when it equals `NEW.responder_profile_id`.
- **REVOKE discipline:** REVOKE ALL from `public`, `anon`, `authenticated`. No GRANT.
- **Priority:** Critical.

### 10.3 No policy-gate trigger

APP 007 does NOT propose a sequential-policy trigger. Sequential ordering is enforced entirely in the write RPCs (§5.5, §8.2). Adding a DB-boundary trigger would be redundant since roster mutation is RPC-only.

### 10.4 `set_updated_at` on `approval_request_approvers` — Wave 2 (F-7.3 MEDIUM — applied)

Because §2.7–§2.9 add mutable columns (`required`, `veto_power`, `removed_at`, `removed_reason`, `sort_order`), a `set_updated_at` trigger is added on `approval_request_approvers` in **Wave 2** alongside the roster-mutation RPCs. Preferred over ad-hoc `updated_at = now()` writes in each RPC. Not required in Wave 1 (mutation surface is bounded to `create_approval_draft` + `send_approval_request` initially).

---

## 11. Event payload extensions

**Backwards-compatibility rule:** all payload extensions add new keys to existing frozen event types. Consumers MUST ignore unknown keys. No key is ever removed, renamed, or repurposed.

**F-4.3 applied:** `round_number` is not present in any approval payload — approvals have no rounds.

### 11.1 `approval.requested` — payload additions

Add: `policy`, `quorum_min?`, `expires_at?`, `related_review_id?`, `supersedes_approval_request_id?`, `root_approval_request_id`, `approver_wm_ids[]`, `approver_sh_ids[]`, `has_veto_approver`.

- **Section:** §17, G-34. **Priority:** Critical.

### 11.2 `approval.responded` — payload additions

Add: `decision` (already present, formalized as primary key; `changes_requested` remains legal in payloads for backwards compatibility; new writes emit `approved | rejected | abstained` per F-2.1), `is_veto_cast`, `note_snippet` (first 200 chars of `comment`), `sort_order`.

- **Section:** §17. **Priority:** High.

### 11.3 `approval.cancelled` — payload additions

Add: `cancellation_reason`, `admin_override boolean`.

- **Section:** §17. **Priority:** High.

### 11.4 (reserved subsection — no content)

### 11.5 `approval.approved` / `approval.rejected` — payload extensions (F-4.1 HIGH — applied)

**These are NOT new event types.** Both events are already emitted by AUTH 007 (`respond_to_approval` at `supabase/migrations/20260801180000_auth_007_approval_rls.sql` L326). APP 007 only extends the payloads additively with:

- `outcome_summary jsonb` = `{approved_count, rejected_count, abstained_count, pending_count, veto_cast, policy, quorum_min?}` (the definitive audit block APP 009 consumes for release readiness).
- `outcome_at timestamptz` (already on the request row; denormalized into the event for consumer convenience).
- `policy text`.
- `has_veto_approver boolean`.
- `root_approval_request_id uuid`.
- `approval.rejected` only: `veto_cast boolean` (denormalized from `is_veto_cast` on the terminating response).

**Not present:** `round_number` (F-4.3).

- **Section:** §17, §10 (Release readiness). **Priority:** Critical.

---

## 12. New event types

Three **truly new** emitted types (post-F-4.1 reclassification) plus four RESERVED name-only entries.

### 12.1 Emitted by APP 007 RPCs

| Event type | Emitted by | Payload | Priority | Blocks |
|---|---|---|---|---|
| `approval.sent` | `send_approval_request` RPC | `{approval_request_id, roster:{wm_ids[], sh_ids[]}, expires_at?, policy}` | Critical | v1 entirely |
| `approval.expired` | `expire_approval` OR future cron | `{approval_request_id, admin_override, expires_at}` | High | v1 subset |
| `approval.superseded` | `supersede_approval_request` (fires on the OLD request) | `{old_request_id, new_request_id, root_approval_request_id}` | Critical | v1 entirely |

`approval.approved` and `approval.rejected` are **not** in this table — they are already frozen and covered as payload extensions in §11.5 (F-4.1). No approval payload includes `round_number` (F-4.3).

### 12.2 RESERVED event names (name-only, emitter deferred)

| Event type | Reserved for | Notes |
|---|---|---|
| `approval.deadline_approached` | Cron slice | **F-4.2 applied — past-tense form.** Analog of `review.deadline_approached`. Type name locked so APP 010 can reference by exact string. |
| `approval.reminder_sent` | APP 010 nudge feature | Locked name for future notification-triggered reminder. |
| `approval.escalated` | v2 hierarchical policy | Locked for future automatic escalation. |

**No emitter for these names is implemented in APP 007.** Type names frozen in the vocabulary only.

### 12.3 `approval.state_changed` (also RESERVED)

- **Why:** APP 007 v1 has no non-terminal ↔ non-terminal transitions.
- **Priority:** Future.

---

## 13. Dashboard RPCs

Covered under §7.1, §7.6, §7.7. Cursor semantics: **server-opaque `(updated_at, id)` tuple** passed back verbatim by the client.

---

## 14. Approval chain support

Backend surface enabling supersession chains (§3.5 of the Freeze Index).

**Required schema:** §2.3, §2.4, §3 chain indexes, §4.2 chain integrity CHECK, §10.1 chain-immutability trigger.

**Required RPCs:** §8.7 (`supersede_approval_request`), §7.3 (`get_approval_chain`), §12 event (`approval.superseded`).

**Required capability:** §6.3 (`approval.supersede`).

**F-1.1 + F-7.1 + F-10.1 cross-references (applied here as a consolidated summary of chain invariants):**

- **F-10.1** — supersession is only permitted when the old request's status is `pending` or `in_progress`. An `approved` request is terminal and immutable; a new approval on the same asset after an approved outcome is an **independent** (unchained) request. APP 009 sorts by `outcome_at desc` on `list_approvals_for_version` to discover "the latest approval." `rejected`, `expired`, `cancelled`, and `superseded` are also terminal and non-supersedable — remediation from those states is a fresh `create_approval_draft` call.
- **F-1.1** — the transactional ordering in `supersede_approval_request` is: `SELECT … FOR UPDATE` on the old row → transition old to `superseded` (removes it from the frozen partial-unique WHERE predicate at `20260729220000_approval_model.sql` L119–L121) → INSERT new as `draft` (also outside the WHERE predicate). No unique-index conflict arises. The modal case targets a new version anyway.
- **F-7.1** — both the new row (via `supersede_approval_request`) and every fresh chain-root (via `create_approval_draft`) are inserted with chain columns set **inline in a single INSERT**. Post-INSERT UPDATE of any chain column raises via the §10.1 trigger.

**Cross-slice hook:** APP 009 Releases traverses chains via `get_approval_chain` and consults `list_approvals_for_version` sorted by `outcome_at desc` to find the currently-authoritative approval on a version.

---

## 15. Decision support

Backend surface enabling the approver decision act (§3.3, §7.2).

**Required schema:** §2.10 (widened `comment` CHECK), §2.11 (`decision_metadata` reserved for v2), §2.12 (`is_veto_cast`), §5.3 (decision enum widening for `abstained`), §4.5 (mandatory reason CHECK), §4.6 (veto-cast consistency CHECK), §10.2 (`approval_responses_no_self_approve` trigger — F-2.4). Response immutability is provided by the **frozen** `enforce_approval_response_immutable` trigger — no new trigger required (F-7.2).

**Required RPCs:** §8.4 (`respond_to_approval` extended, rejects `changes_requested` at input per F-2.1).

**Required events:** §11.2 (`approval.responded` payload extension), §11.5 (`approval.approved` / `approval.rejected` payload extensions — F-4.1).

**Enterprise separation of duties (Freeze Index §11.4):** enforced both inside `respond_to_approval` (RPC-layer) AND at the DB boundary by the new `approval_responses_no_self_approve` trigger (§10.2).

---

## 16. Metrics support

**Derivation strategy:** compute at the RPC layer from `activity_events` + roster/response state. No cached-metric columns in v1.

**Per-request metrics** (delivered by `get_approval`):
- `time_to_first_response`, `time_to_outcome`, `response_distribution` (`{approved, rejected, abstained, changes_requested, pending}`), `veto_cast`, `time_remaining`.

**Workspace / project metrics** (delivered by `list_approvals_dashboard` + §7.7 RPCs):
- Outstanding count, overdue count, rejection rate (30d), expiration rate (30d), avg time-to-outcome (30d), approver throughput (top-5, 30d).

---

## 17. Backend gaps discovered

### Schema gaps

- **G-1** `approval_requests.status` — needs `draft` + `superseded` (§5.2). **Critical.**
- **G-2** `supersedes_approval_request_id` + `root_approval_request_id`. **Critical.**
- **G-3** `related_review_id`. **Medium.**
- **G-4** `approval_requests.policy` widening. **High.**
- **G-5** `quorum_min`. **High.**
- **G-6** `expires_at`. **High.**
- **G-7** `cancellation_reason`. **High.**
- **G-8** `approval_request_approvers.required`. **Critical.**
- **G-9** Sequence ordering — `sort_order` exists. No new column.
- **G-10** `veto_power` on approver rows. **High.**
- **G-11** Mandatory decision reason — widen `comment` CHECK (F-2.2) + `approval_responses_no_self_approve` trigger (F-2.4). **Critical.** The trigger belongs to G-11 support because self-approve prevention is one of the two enforcement pillars of decision integrity (the other being the reason CHECK).
- **G-12** `decision_metadata jsonb` — reserved for v2. **Future.**
- **G-13** Chain integrity CHECK. **Critical.**
- **G-14** Chain-immutability trigger. **Critical** (F-10.2 adds `related_review_id`).
- **G-15** Response-immutability trigger — **already frozen** (F-7.2). No change.

### RPC gaps

- **G-16** `create_approval_draft`. **Critical.**
- **G-17** `send_approval_request`. **Critical.**
- **G-18** `expire_approval`. **Medium.**
- **G-19** `supersede_approval_request`. **Critical.**
- **G-20** `list_approvals_dashboard`. **Critical.**
- **G-21** `get_approval`. **Critical.**
- **G-22** `get_approval_chain`. **High.**
- **G-23** `list_approvals_for_version`. **Critical.**
- **G-24** `get_approval_readiness`. **Medium.**
- **G-25** `get_approval_inbox_count`. **High.**
- **G-26** Project/workspace metrics RPCs. **Medium.**

### RLS / capability gaps

- **G-27** Existing policies verified sufficient; no policy edits required.
- **G-28** No new tables required.
- **G-31** `approval.veto` — new key. Default `lead` only (F-5.1). **High.**
- **G-32** `approval.expire` — new key. **Medium.**
- **G-33** `approval.supersede` — new key. **Critical.**

### Event gaps

- **G-34** Payload extensions to `approval.requested`, `approval.responded`, `approval.cancelled`, `approval.approved`, `approval.rejected` (the last two reclassified from "new" to "payload extensions" per F-4.1). **Critical/High.** Backwards-compatible.
- **G-35** New emitted events: `approval.sent`, `approval.expired`, `approval.superseded` (post-F-4.1). **Critical (sent, superseded), High (expired).**
- **G-36** RESERVED names: **`approval.deadline_approached`** (past-tense, F-4.2), `approval.reminder_sent`, `approval.escalated`, `approval.state_changed`. **Medium.**
- **G-37** Scheduled emitter for `approval.deadline_approached` + auto-expire — cron slice, outside APP 007.

### Cross-slice gaps

- **G-38** APP 005 comment mutations targeting `target_approval_request_id` invalidate `approvalMetrics(request_id)` — cross-slice hook.

**None blocking to APP 007 architecture.**

---

## 18. Priority summary

### Critical (v1 entirely — first wave)

- §2.3 `supersedes_approval_request_id` + composite FK
- §2.4 `root_approval_request_id` + composite FK
- §2.7 `required` on approver rows
- §2.10 mandatory `comment` reason (widened CHECK — F-2.2)
- §3 chain + dashboard/inbox/version indexes (Critical rows)
- §4.1 composite tenancy FKs for chain
- §4.2 chain integrity CHECK
- §4.5 response mandatory-reason CHECK
- §4.8 revised outcome/sent gates
- §4.9 published-only target discipline preserved (documentation-only)
- §5.2 status enum widening
- §5.3 decision enum widening (`abstained` added additively; F-2.1)
- §6.3 `approval.supersede` capability
- §7.1, §7.2, §7.4 read RPCs
- §8.1 `create_approval_draft` (with F-7.1 chain-init discipline)
- §8.2 `request_approval` extended (with F-3.1 array ordering, F-1.2 sequential validation)
- §8.3 `send_approval_request`
- §8.4 `respond_to_approval` extended (rejects `changes_requested`; F-2.1)
- §8.7 `supersede_approval_request` (with F-1.1, F-7.1, F-10.1 disciplines)
- §10.1 chain-immutability trigger (immutable set: `supersedes_approval_request_id`, `root_approval_request_id`, `related_review_id` — F-10.2)
- §10.2 `approval_responses_no_self_approve` trigger (F-2.4)
- §11.1 `approval.requested` payload extension
- §11.5 `approval.approved` / `approval.rejected` `outcome_summary` payload extension (F-4.1)
- §12 new events: `approval.sent`, `approval.superseded`

### High (v1 subset — first or second wave)

- §2.1 `expires_at` + partial index
- §2.5 `quorum_min` + policy consistency CHECK
- §2.6 `cancellation_reason` + CHECK
- §2.8 `veto_power` on approver rows
- §2.9 `removed_at` / `removed_reason` + tight CHECK
- §2.12 `is_veto_cast` + veto-cast consistency CHECK
- §5.1 policy enum widening
- §5.5 sequential-policy ordering (RPC-enforced; F-1.2)
- §6.1 `approval.veto` capability (default `lead` only; F-5.1)
- §7.3 `get_approval_chain`
- §7.6 `get_approval_inbox_count`
- §8.5 `cancel_approval` extended with mandatory reason
- §8.8 `add_approver` (roster mutation — F-6.2 DEFINER discipline reaffirmed)
- §10.4 `set_updated_at` on `approval_request_approvers` (F-7.3)
- §11.2 `approval.responded` payload extension
- §11.3 `approval.cancelled` payload extension
- §12 new event: `approval.expired`

### Medium (v1 subset — third wave)

- §2.2 `related_review_id` + partial index
- §6.2 `approval.expire` capability
- §7.5 `get_approval_readiness` (reconciled shape; F-3.3)
- §7.7 project/workspace metrics RPCs
- §8.6 `expire_approval`
- §8.8 remove/reassign/set_required/set_veto/set_sort_order approver RPCs
- §12 RESERVED event type names

### Future (v2 / later slice)

- §2.11 `decision_metadata jsonb`
- Scheduled emitter for `approval.deadline_approached` (cron slice)
- Auto-expire cron
- Weighted approvals, hierarchical escalation, delegation
- Requirement-waiver linkage
- Release-blocking policies (APP 009)
- DB-enforced per-request `sort_order` uniqueness under sequential policy (F-1.2 v2 candidate)

---

## 19. Recommended implementation waves (F-12.2 applied — recounted)

**Wave 1 (Critical only) — recounted arithmetic:**

- **Schema additions:** 6 columns (`supersedes_approval_request_id`, `root_approval_request_id`, `required`, `is_veto_cast`, plus 2 chain-support essentials that ship in Wave 1 alongside them). The widened `comment` CHECK is a CHECK, not a column (F-2.2 replaced the previously-counted `decision_reason` column). **Column additions in Wave 1: 4 (chain × 2 on requests; roster `required` × 1; response `is_veto_cast` × 1).** Widened `comment` CHECK: 1. Enum widenings: 2 (`status`, `decision`). Chain integrity CHECK: 1. Outcome/sent gate revisions: 2.
- **RPCs:** 5 (`create_approval_draft`, `send_approval_request`, `respond_to_approval` extended, `supersede_approval_request`, plus the 3 core read RPCs `list_approvals_dashboard` + `get_approval` + `list_approvals_for_version` — grouped as one delivery). Formally: 4 write RPCs + 3 read RPCs = 7 RPCs.
- **Capability:** 1 (`approval.supersede`).
- **Triggers:** **2 new** (chain-immutability §10.1; no-self-approve §10.2 — F-2.4). Removed from the prior draft: 1 (the redundant response-immutability trigger — F-7.2 credit).
- **Events:** 2 truly new emitters (`approval.sent`, `approval.superseded`) + payload extensions on 5 events (`approval.requested`, `approval.responded`, `approval.cancelled`, `approval.approved`, `approval.rejected` — the last two reclassified per F-4.1).
- **Mandatory test-case checklist entry (F-7.1):** "smoke-test `create_approval_draft` against the chain-immutability trigger" — assert that any UPDATE of `supersedes_approval_request_id`, `root_approval_request_id`, or `related_review_id` after the initial INSERT raises `errcode 23514`. Same smoke test for `supersede_approval_request`.

**After Wave 1, APP 007 v1 implementation can start.**

**Wave 2 (High):** policy widening, `quorum_min`, `expires_at`, `veto_power`, `cancellation_reason`, `removed_at`/`removed_reason`, `get_approval_chain`, `get_approval_inbox_count`, `cancel_approval` extension, `add_approver`, `set_updated_at` trigger on `approval_request_approvers` (F-7.3), `approval.veto` capability (default `lead` only per F-5.1), `approval.expired` event, payload extensions on `approval.responded` and `approval.cancelled`.

**Wave 3 (Medium):** `related_review_id`, `approval.expire` capability, `get_approval_readiness` (with reconciled return shape per F-3.3), metrics RPCs, `expire_approval`, remove/reassign/set_* approver RPCs, RESERVED event names (including `approval.deadline_approached` — past-tense per F-4.2).

**Wave 4 (Future):** `decision_metadata`, cron slice, weighted policies, escalation, delegation, requirement waivers, release-blocking rules, DB-enforced sequential `sort_order` uniqueness.

---

## 20. Out-of-scope items

- **SQL, migrations, RPC bodies.** This document is design-only.
- **Scheduled emitter for `approval.deadline_approached`.** Cron slice.
- **Auto-expire cron.** Cron slice.
- **APP 008 / APP 009 backend proposals.** APP 007 exports the contract; those slices own their own re-freezes.
- **E-signature / IP / device fingerprint capture.** v2 (`decision_metadata` reserved).
- **Weighted approvals, hierarchical escalation, delegation.** v2.
- **Requirement-waiver linkage** — APP 008 or v2.
- **Release-blocking policies** — APP 009.
- **Advisor-check design** — SECURITY DEFINER warnings on new RPCs are expected and match every prior slice.
- **Backfill strategy for existing data** — no production approval data.

---

## Coverage matrix — Proposal section ↔ Freeze Index gap

| Proposal § | Freeze Index gap(s) | Status |
|---|---|---|
| §2.1 `expires_at` | G-6 | High |
| §2.2 `related_review_id` | G-3 | Medium |
| §2.3 `supersedes_approval_request_id` | G-2 | Critical |
| §2.4 `root_approval_request_id` | G-2 | Critical |
| §2.5 `quorum_min` | G-5 | High |
| §2.6 `cancellation_reason` | G-7 | High |
| §2.7 `required` on approver rows | G-8 | Critical |
| §2.8 `veto_power` on approver rows | G-10 | High |
| §2.9 `removed_at`/`removed_reason` | G-8 (paired) | High |
| §2.10 mandatory decision reason CHECK (widened `comment`) | G-11 | Critical |
| §2.11 `decision_metadata` | G-12 | Future |
| §2.12 `is_veto_cast` on responses | New (payload denorm) | High |
| §3 indexes | Support for G-2, G-3, G-6, G-8, G-25 | Mixed |
| §4.1 composite tenancy FKs | Support for G-2, G-3 | Critical/Medium |
| §4.2 chain integrity CHECK | G-13 | Critical |
| §4.3 policy consistency CHECK | G-5 (paired) | High |
| §4.4 cancellation-reason CHECK | G-7 | High |
| §4.5 response mandatory-reason CHECK (widened `comment`) | G-11 | Critical |
| §4.6 veto-cast consistency CHECK | Support for §2.12 | High |
| §4.7 removal pair CHECK | Support for §2.9 | High |
| §4.8 revised outcome + sent gates | G-1 downstream | Critical |
| §4.9 published-only target discipline preserved | Frozen invariant, documentation-only | Documentation |
| §5.1 policy enum widening | G-4 | High |
| §5.2 status enum widening | G-1 | Critical |
| §5.3 decision enum widening (`abstained` additive, F-2.1) | Freeze Index §3.3 | Critical |
| §5.5 sequential-policy ordering (F-1.2, RPC-enforced) | Freeze Index §5.5 | High |
| §6.1 `approval.veto` capability (default `lead` only, F-5.1) | G-31 | High |
| §6.2 `approval.expire` capability | G-32 | Medium |
| §6.3 `approval.supersede` capability | G-33 | Critical |
| §7.1 `list_approvals_dashboard` | G-20 | Critical |
| §7.2 `get_approval` | G-21 | Critical |
| §7.3 `get_approval_chain` | G-22 | High |
| §7.4 `list_approvals_for_version` | G-23 | Critical |
| §7.5 `get_approval_readiness` (reconciled shape, F-3.3) | G-24 | Medium |
| §7.6 `get_approval_inbox_count` | G-25 | High |
| §7.7 metrics RPCs | G-26 | Medium |
| §8.1 `create_approval_draft` (F-7.1 chain-init) | G-16 | Critical |
| §8.2 `request_approval` extended (F-3.1 ordering, F-1.2 seq validation) | G-4, G-5, G-6, G-8, G-10 | Critical |
| §8.3 `send_approval_request` | G-17 | Critical |
| §8.4 `respond_to_approval` extended (F-2.1 rejects `changes_requested`) | G-11 | Critical |
| §8.5 `cancel_approval` extended | G-7 | High |
| §8.6 `expire_approval` | G-18 | Medium |
| §8.7 `supersede_approval_request` (F-1.1, F-3.2, F-7.1, F-10.1) | G-19 | Critical |
| §8.8 roster mutation RPCs (F-6.2 DEFINER discipline) | G-8 support | High/Medium |
| §10.1 chain-immutability trigger (F-10.2 adds `related_review_id`) | G-14 | Critical |
| §10.2 `approval_responses_no_self_approve` trigger (F-2.4) | G-11 support | Critical |
| §10.4 `set_updated_at` on `approval_request_approvers` (F-7.3) | Support for §2.7–§2.9 | High (Wave 2) |
| §11.1 `approval.requested` payload extension | G-34 | Critical |
| §11.2 `approval.responded` payload extension | G-34 | High |
| §11.3 `approval.cancelled` payload extension | G-34 | High |
| §11.5 `approval.approved` / `approval.rejected` payload extensions (F-4.1) | G-34 | Critical |
| §12.1 new events: `approval.sent`, `approval.expired`, `approval.superseded` | G-35 | Critical/High |
| §12.2 RESERVED event names (F-4.2 past-tense `deadline_approached`) | G-36 | Medium |

**Gaps NOT covered by this proposal (deferred to later slices):**
- G-9 handled by frozen `sort_order`.
- G-12 (`decision_metadata`) — Future.
- G-15 (response-immutability trigger) — **already frozen** (F-7.2); no change.
- G-27 no new RLS predicates required.
- G-28 no new tables.
- G-37 auto-expire + deadline cron — separate cron slice.
- G-38 cross-slice invalidation hook — implemented in APP 007 implementation slice.

---

## What this proposal does NOT include

- SQL. No CREATE TABLE, ALTER TABLE, CREATE FUNCTION.
- Migration file naming or ordering.
- Backfill strategy for existing data.
- Advisor-check design.
- Downstream slice (APP 008–011) backend proposals.
- Scheduled emitter for `approval.deadline_approached` / auto-expire — cron slice.

---

## Ready for approval

On approval of this proposal (in full or wave-by-wave), a corresponding backend re-freeze migration set can be authored following the APP 006 pattern (schema migration + authz-and-rpcs migration, applied in idempotent chunks). Implementation of APP 007 v1 begins after Wave 1 lands and re-freeze is confirmed.

---

**APP 007 Backend is frozen.**
