# APP 013 — Freeze Index

**Canonical architecture reference for People & Access.**

Implementation has not started. Every claim in §1 is measured against the live
database and the shipped frontend on **2026-09-20**.

**Foundational premise:**

> **Today the application cannot add a second person to itself.**
>
> This is not a missing screen. There is no path — RPC or direct write — by
> which any authenticated user can invite someone, remove someone, or change
> anyone's role. The only way to onboard a person is hand-written SQL executed
> as `postgres`. APP 013 closes that.

---

## 1. Measured gap

### 1.1 Every access table is SELECT-only

| Table | Policies that exist | Write path |
|---|---|---|
| `invitations` | `invitations_select_admin_or_invitee` | **none** |
| `workspace_members` | `workspace_members_select_workspace` | **none** |
| `stakeholders` | `stakeholders_select_admin_self_or_shared_project` | **none** |
| `project_participants` | `project_participants_select` | **none** |

No INSERT, UPDATE or DELETE policy exists on any of them. Writes are therefore
possible only through a `SECURITY DEFINER` RPC — which is the correct design
(cheatsheet rule 2) and exactly why the missing RPCs below are fatal rather
than inconvenient.

### 1.2 What the backend actually provides

**Exists and callable by `authenticated`:**

| RPC | Effect |
|---|---|
| `create_workspace(name, slug)` | Creates a workspace, caller becomes owner |
| `accept_invitation(token)` | Consumes a member invitation |
| `claim_stakeholder_invitation(token)` | Consumes a stakeholder invitation |
| `add_project_participant(project, wm_id, sh_id, role)` | Adds a participant |

**Does not exist at all:**

| Missing RPC | Consequence |
|---|---|
| `invite_workspace_member` | **No invitation can ever be created** |
| `invite_stakeholder` | Same, for externals |
| `remove_workspace_member` | Nobody can be removed |
| `change_workspace_member_role` | Roles are frozen at creation |
| `remove_project_participant` | Participants are permanent |
| `change_project_participant_role` | Project roles are frozen |
| `revoke_stakeholder` | External access cannot be withdrawn |

**The invitation flow is orphaned.** `InviteClaimScreen` is built, the route
`/invite/:token` is wired, `accept_invitation` works, and `invitations` has a
`token_hash` column — but nothing in the system can mint a token. A complete
receiving half with no sending half.

### 1.3 Capability vocabulary is absent

`app/src/types/capabilities.ts` declares 58 keys. Exactly **one** covers this
domain: `project.manage_access`. There is no `member.invite`,
`member.remove`, `member.change_role`, `stakeholder.invite`, or
`stakeholder.revoke`. Workspace-level access control has no capability
vocabulary at all.

### 1.4 Frontend

`/workspace/:ws_id/people`, `/workspace/:ws_id/project/:proj_id/people` and
`/workspace/:ws_id/settings` all render stubs. `features/participants/queries.ts`
has read queries and no mutations.

---

## 2. Scope

APP 013 is **not** a frontend slice. It is roughly 60% backend.

### Wave 1 — Backend: capability vocabulary + write RPCs

**New capability keys** (wired, not reserved):
`member.invite`, `member.remove`, `member.change_role`,
`stakeholder.invite`, `stakeholder.revoke`, `workspace.manage`.
Granted to workspace `owner`/`admin`. `project.manage_access` already exists
and is granted to project `lead` plus workspace admins.

**Seven RPCs**, each `SECURITY DEFINER`, `search_path=''`, inline capability
check, one past-tense event, per cheatsheet rules 2/4/5/11.

**Invariants the RPCs must enforce** — these are the reason this is not CRUD:

1. **A workspace always retains at least one active `owner`.** Deferred at
   Migration 002 and never implemented. Removing or demoting the last owner
   must fail.
2. **No self-lockout.** An admin may not remove or demote themselves below the
   capability needed to undo it.
3. **Dual-path participation.** `PERMISSIONS.md` §6.3: the same profile must
   not appear on one project as both a `workspace_member` and a `stakeholder`.
   Not a DB constraint — the RPC owns it.
4. **Removal is soft.** `status → removed/revoked`; authored history keeps its
   attribution (DOMAIN_MODEL §1.1).
5. **A stakeholder never becomes a member.** Claiming links `user_id`; it does
   not promote.

### Wave 2 — Frontend: three screens

- **Workspace People** — members and stakeholders, role editing, invite, remove, pending invitations with copy-link and revoke.
- **Project People** — participants with project roles, add from workspace members or stakeholders, change role, remove.
- **Workspace Settings** — name, slug, and owner transfer.

Reuses `Guarded`, `StatusBadge`, `FormRow`, `Dialog`, existing invalidators. New
`qk` keys namespaced under `access.*`.

### Wave 3 — Invitation delivery

See G-1. Wave 2 ships copy-link; wave 3 is email, if wanted.

---

## 3. Open decisions

| # | Decision | Recommendation |
|---|---|---|
| **G-1** | How does an invitation reach the invitee? **There is no email infrastructure in this project** — no provider, no template, no sending RPC, and `pg_net` is not installed. | **Copy-link for wave 2.** The RPC returns a one-time token, the UI shows a copyable URL, the admin sends it however they already communicate. Honest, shippable, and zero new infrastructure. Email becomes wave 3 and needs a provider decision. |
| **G-2** | Can an invited person sign up, or must an account exist first? Sign-in is password-only; there is no sign-up screen. | **Must be resolved before wave 2 is usable.** A copy-link to someone with no account currently dead-ends. Smallest fix: a sign-up screen on the invite route. This is the true blocker on "onboard your second user". |
| **G-3** | Token generation and hashing. `invitations.token_hash` exists; nothing writes it. | RPC generates a random token, stores only its hash, returns the plaintext **once**. Never store or re-display it. |
| **G-4** | Does removing a member cascade to their project participations? | **Yes** — set them `removed` in the same transaction. A member removed from the workspace who still holds project roles is a security hole. |
| **G-5** | Owner transfer in Wave 2 Settings, or later? | Wave 2. It is the only escape from a single-owner workspace, and G-1's invariant makes that state permanent otherwise. |
| **G-6** | Does this need a re-freeze? | **Yes** — new capability keys extend `lign_has_capability`, and new RLS-adjacent RPCs touch AUTH 002/003 surfaces. Additive only, single-function `CREATE OR REPLACE` with the default-tail pattern (rule 9). |

---

## 4. Non-goals

SSO/SCIM, org hierarchies beyond Workspace→Project, custom roles or per-user
capability overrides (roles stay fixed bundles — cheatsheet rule 18), bulk
import, guest workspace role (deliberately dropped at Migration 002), seat
billing.

---

## 5. Success criteria

- [ ] A workspace admin can invite a member **through the UI**, and that person can join
- [ ] A project lead can add, re-role and remove participants
- [ ] An external stakeholder can be invited, scoped to one project, and revoked
- [ ] The last owner cannot be removed or demoted
- [ ] An admin cannot lock themselves out
- [ ] Removal is soft; authored history keeps attribution
- [ ] Every mutation emits exactly one past-tense event
- [ ] `verify_migrations.sh` passes; advisors show no new issue class
- [ ] **The end-to-end test: a second real person is onboarded with no SQL**
