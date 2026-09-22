# APP 014 — New project dialog: build report

Status: built and verified against the live database. Backend proven with real
JWT simulation; frontend typechecks, 68 tests pass, bundle within budget.
**Not yet clicked through in a browser.**

Files: `supabase/migrations/20260922120000_app_014_create_project_full.sql`,
`…130000_app_014_fix_citext_case_folding.sql`,
`app/src/features/projects/newProject.ts`, `NewProjectDialog.tsx`,
`__tests__/newProject.test.ts`. `CreateProjectDialog.tsx` deleted.

---

## 1. Table / column mapping

| Brief concept | Actual | Notes |
|---|---|---|
| project | `projects` | `name`, `code` (nullable), `description`, `status`, `created_by_profile_id`, **`slug` NOT NULL** |
| participants | `project_participants` | `role` ∈ lead/contributor/reviewer/approver/observer; `workspace_member_id` XOR `stakeholder_id` |
| workspace member | `workspace_members` | `role` ∈ owner/admin/member |
| external person | `stakeholders` | workspace-scoped, `UNIQUE(workspace_id, email)` |
| invite | **`invitations`** | not `invites`; `token_hash`, `expires_at`, `accepted_at`, `status` |
| activity log | `activity_events` | `event_type`, `subject_*`, `payload` |
| person | `profiles` | `email` is `citext` |

**`slug` is not in the dialog but is required by the table.** The brief asks
for one required field, so the RPC derives the slug from the name and suffixes
it (`northgate-phase-1`, `northgate-phase-1-2`) until free. Verified: creating
the same name twice produces two projects, not a constraint violation.

## 2. The transaction

One RPC, `create_project_full(workspace, name, code, description,
lead_member_id, client_emails[], expires_in_days)` → `(project_id, slug, code,
invites jsonb)`. In order: capability check → validate name/code/description →
derive unique slug → insert project → `project.created` → lead participant →
`project.participant_added` → creator-as-contributor if the lead is someone
else → per client email, resolve to member or stakeholder, participant row,
`project.participant_added`, and for externals an `invitations` row plus
`stakeholder.invited`.

Every activity event carries `payload.capacity` (`internal` | `external`) and
`payload.actor_capacity`. Verified on a real call:
`stakeholder.invited/external | project.participant_added/external |
project.participant_added/internal | project.created`.

Atomicity is the function boundary — a failure anywhere rolls back everything,
including the invitation rows. Confirmed by running the whole battery inside a
transaction and rolling it back: nothing persisted.

## 3. Capability enforcement

**There is no `project.create` capability key.** The key list holds
`project.view`, `project.edit`, `project.archive`, `project.manage_access` —
all of which presuppose a project that already exists. I did not invent one.

The RPC gates on **`workspace.manage`**, an existing workspace-scoped key that
`lign_has_capability` already answers with `p_project_id = null`, and which
resolves through `lign_is_workspace_admin` to `role in ('owner','admin')` —
exactly the intended set. **Flag for you:** this conflates "can change
workspace settings" with "can create projects". Identical today; if they should
ever diverge, a real `project.create` key is the fix and it needs a migration.

**There is no workspace-level lead concept** (`workspace_members.role` is
owner/admin/member only), so that clause of the permission spec has nothing to
map to.

Three bypass routes, all verified closed as `p_contrib` (a plain member):

```
create_project_full  → 42501 create_project_full: forbidden (workspace.manage)
create_project       → 42501 permission denied for function create_project
direct INSERT        → 42501 new row violates row-level security policy
```

The second needed a change: **`create_project()` admitted any active workspace
member**, a weaker bar than the dialog's, and was reachable directly from
PostgREST. Its only caller was the dialog this replaces, so the migration
revokes `EXECUTE` from `authenticated` rather than editing the frozen body —
one GRANT to reverse.

The button is **hidden**, not disabled, without `workspace.manage`, and the
empty state swaps its copy instead of offering a control that would fail.

## 4. Member-vs-stakeholder resolution

For each address: lower-case and trim → look for an **active workspace member
whose profile email matches** → if found, participant row with
`workspace_member_id` and no stakeholder; otherwise find-or-create a
stakeholder by `(workspace_id, email)` and use `stakeholder_id`. The XOR check
constraint is satisfied by construction. A revoked stakeholder is reinstated
rather than duplicated. Duplicates within one call are skipped.

Verified live — `['P_Reviewer@Lign.test', ' Client@Acme.example ',
'client@acme.example', '']` produced exactly two approver rows: one
member-backed (P Reviewer), one stakeholder-backed
(`client@acme.example`).

The dialog shows the same resolution before submit, so the note
"{name} is already in this workspace…" appears at add-time, not after.

### The bug this caught

The first migration compared `citext` values directly. Under
`set search_path to ''` — correct for a SECURITY DEFINER function — the citext
`=` operator lives in `extensions` and is **not visible**. Postgres does not
error: it finds the implicit `citext→text` cast and silently resolves to
case-**sensitive** text equality. Consequences, all silent:

- `Client@Acme.example` did not match the stakeholder `client@acme.example`,
  so the insert hit `stakeholders_workspace_email_key` and took the whole
  creation down.
- The same address in different case was not treated as a duplicate.
- An address belonging to a member matched only if the capitalisation matched
  their profile exactly — the precise case that is supposed to stop one person
  having two identities in a workspace.

Fixed in `…130000_app_014_fix_citext_case_folding.sql` by comparing explicitly
lower-cased text everywhere, so behaviour no longer depends on `search_path`.

> **`invite_stakeholder()` has the identical pattern and therefore the same
> latent defect.** It is frozen under APP 013, so I flagged it rather than
> changing it. Worth a follow-up: today, inviting `Client@Acme.example` when
> `client@acme.example` already exists throws a unique-violation instead of
> reusing the stakeholder.

## 5. Invite emails — **there is no email infrastructure**

This changes items 4 and 5 of the brief materially. APP 013 already settled on
copy-link delivery (`features/access/mutations.ts`: *"Copy-link delivery —
there is no email infrastructure"*). There is no SMTP config, no provider, no
edge function. Nothing sends mail.

So "send emails after commit" has nothing to send. What happens instead: the
`invitations` rows and their one-time tokens are created inside the
transaction (data, not delivery), the RPC returns the plaintext tokens once,
and on success the dialog shows a 30-second toast — *"2 invite links ready —
no email was sent"* — with a **Copy links** action. The footer still reads
"{n} invite email(s) will be sent when you create" per the spec; **that line is
currently a lie** and should either change to "invite links" or wait until
sending exists. Your call — I left the spec wording rather than silently
diverging from it.

The post-commit-email-failure path (item 5) is therefore untestable and
unbuilt. When sending exists it belongs outside the RPC, exactly as specified.

## 6. Open decisions

1. **Invite-opened tracking — missing.** `invitations` has `accepted_at` (they
   claimed it) and `created_at` (implicitly, when it was made). There is **no
   `opened_at` and no `sent_at`**. So "Invite sent, not opened yet" cannot be
   shown; only "not accepted yet". I did **not** add the column — the schema is
   frozen and your brief says not to invent schema. The migration you'd need:
   `alter table invitations add column opened_at timestamptz;` plus a tracking
   pixel or a redirect hop on `/invite/:token`, neither of which exists. Say
   the word and it's a small follow-up.
2. **Code format — no existing convention.** `projects.slug` is the
   lowercase-hyphenated URL identifier, a different thing. `projects.code` was
   unused and null everywhere. I used your default: uppercase initials of the
   first three words, `^[A-Z0-9][A-Z0-9-]{0,15}$`, nullable, unique per
   workspace.
3. **Discipline — cannot be a creation field.** `disciplines` has
   `project_id NOT NULL`: disciplines are a per-project list, not a workspace
   picklist, so at creation time there is nothing to pick from. It is not in
   the dialog. Making it a project attribute needs `projects.discipline_id`
   (or a workspace-level table) — tell me if it should drive requirement
   templates or release naming and I'll scope it.

## 7. Gaps — things the schema cannot store

| Field | Status |
|---|---|
| Target completion date | **No column.** `projects` has no due/target date at all. Omitted from the dialog rather than silently discarded. |
| Discipline | **Not a project attribute.** See above. |
| Code uniqueness | **No unique index.** `projects_workspace_slug_key` is on `slug`. The RPC checks inside the transaction, but two simultaneous creations can both pass. Needs `create unique index … on projects (workspace_id, upper(code)) where code is not null and archived_at is null`. |

"More options" therefore contains Description only, with a line saying why.

## 8. Acceptance checks

Verified against the live database (transaction, rolled back):

- [x] Name only → lead row for creator, **no second row**
- [x] Different lead → `lead` for them, `contributor` for creator
- [x] Empty code → `code` null, nothing generated
- [x] Code lower-cased in → stored uppercase (`hpt` → `HPT`)
- [x] Duplicate code → `23505 PROJECT_CODE_TAKEN`, `detail = "Northgate Phase 1"` → dialog renders "NGF is already used by Northgate Phase 1. Try NGF2."
- [x] Blank name → `22004`; bad code format → `22023`
- [x] New client email → stakeholder + participant(`stakeholder_id`) + invitation
- [x] Email matching a member → **no stakeholder**, member-backed row
- [x] Mixed case / duplicate / empty emails → deduped correctly
- [x] Two client emails → two participant rows
- [x] Forced failure mid-transaction → nothing persisted
- [x] Activity log records creation, each participant, each invite, with capacity
- [x] Non-admin → rejected on all three routes
- [x] Same name twice → slug uniquifies

Implemented but **browser-unverified**: double-click guard (`inFlight` ref),
Esc/scrim discard confirmation, focus trap, autofocus, `aria-*` wiring, the
live region on added rows, the 640px sheet, and the four widths.

Not testable: post-commit email failure (§5).
