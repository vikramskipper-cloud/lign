# APP 015 — Organisations above workspaces: backend proposal

**Status: APPROVED AND APPLIED** (2026-10-01). Both decisions in §8 were
confirmed: org admins get read + member administration only, and first run
asks for one name. See `APP_015_IMPLEMENTATION_REPORT.md` for what was built,
what the verification showed, and where §3's "backfill is free" turned out to
be wrong.

## 1. What you asked for

> The owner can view all the workspaces; workspace admins can only view the
> workspaces they are added to.

Today there is no such role. `owner` is a **per-workspace** role: it means
"can hand over the keys to *this* workspace", not "can see everything". For
visibility and capability, owner and admin are byte-identical — the only
differences are four succession rules inside the member-management RPCs.

This adds the missing layer: an **Organisation** that owns workspaces, with
org-level roles that see across them.

## 2. Blast radius — I was wrong about this and the correction matters

I previously said this "touches RLS on nearly every table". Measured against
the deployed database, it does not:

| | count |
|---|---|
| RLS policies in `public` | 69 |
| …that resolve through `lign_has_capability` | 52 |
| …through `lign_is_workspace_admin` | 8 |
| …through `lign_is_workspace_member` | 5 |
| …through `lign_project_role` | 1 |
| **…that hand-roll a `workspace_members` check** | **0** |

Authorization is fully funnelled through four helper functions. **No policy
inlines membership.** That means org authority can be introduced by changing
*two functions*, and all 69 policies inherit it correctly without being
touched.

That is also the main risk — see §6.

## 3. Schema

Two new tables and one column. Nothing existing is dropped or retyped.

```
organizations
  id uuid pk, name text not null, slug citext not null unique,
  status text not null check (status in ('active','suspended')),
  created_at, updated_at

organization_members
  id uuid pk,
  organization_id uuid not null -> organizations(id),
  user_id uuid not null -> profiles(id),
  role text not null check (role in ('owner','admin','member')),
  status text not null check (status in ('invited','active','suspended','removed')),
  invited_at, activated_at, removed_at, created_at, updated_at,
  unique (organization_id, user_id)

workspaces
  + organization_id uuid not null -> organizations(id)
```

Indexes per rule 10 (every FK covered): `organization_members(organization_id)`,
`organization_members(user_id, organization_id)`,
`workspaces(organization_id)`.

**The backfill is free.** The database currently holds zero workspaces, so
`organization_id` can be added `NOT NULL` immediately with no data migration,
no nullable interim, and no risk of a half-migrated row. This is the cheapest
this change will ever be — it gets materially harder the day there is real
data.

## 4. Authorization

Two new helpers:

```sql
lign_org_of_workspace(p_workspace_id uuid) returns uuid   -- stable, definer
lign_is_org_admin(p_organization_id uuid) returns boolean -- role in (owner,admin), active
```

Two modified helpers — **this is the entire propagation mechanism**:

```sql
lign_is_workspace_member(ws)  ->  <existing>  OR lign_is_org_admin(lign_org_of_workspace(ws))
lign_is_workspace_admin(ws)   ->  <existing>  OR lign_is_org_admin(lign_org_of_workspace(ws))
```

What follows automatically:

- `workspaces` SELECT is `lign_is_workspace_member(id) OR lign_is_active_stakeholder(id)` → **org admins see every workspace in their org.** That is the headline requirement, delivered by one clause.
- `lign_has_capability` calls `lign_is_workspace_admin` for the six workspace keys and the nineteen project *read* keys → org admins can read every project in the org and manage its members.
- The 8 policies on `lign_is_workspace_admin` and 5 on `lign_is_workspace_member` inherit it.

`lign_has_capability` itself is **not modified**. `lign_project_role` is **not
modified**.

### The line I propose holding

**Org admins get read + member administration. They do NOT get work
capabilities.** `version.upload`, `version.publish`, `approval.respond`,
`release.create`, `review.create` continue to come only from a
`project_participants` row — for org owners exactly as for workspace admins.

The reason is the audit trail. An approval recorded against someone who was
never a participant is a signature with no basis, and this product exists so
that approvals hold up two years later. Seeing everything and signing anything
are different powers, and only the first one scales upward.

`organization_members.role = 'member'` grants **no** implicit workspace
access. It exists so a person can belong to the company without being handed
every project; they get workspaces through `workspace_members` exactly as
today.

## 5. RPCs

| RPC | Change |
|---|---|
| `create_organization(name, slug)` | **new** — caller becomes org `owner` |
| `create_workspace(name, slug, organization_id)` | **tail param added** (rule 9 default-tail, so the existing 2-arg signature keeps resolving and PostgREST sees no overload). Gated on `lign_is_org_admin`. With a null org and no org membership, creates the org and the workspace together — the first-run path. |
| `invite_org_member`, `change_org_member_role`, `remove_org_member` | **new** — mirroring the workspace equivalents, including last-owner protection |

Existing workspace RPCs are otherwise untouched.

## 6. Risks

1. **One edit changes every policy at once.** Redefining
   `lign_is_workspace_admin` alters the answer for all 69 policies
   simultaneously. Mitigation: capture a full capability matrix (every fixture
   role × every capability key × RLS-visible row counts) **before** and
   **after**, and diff. The only permitted difference is org admins gaining
   access. This is the same behavioural-fingerprint method used for APP 011.
2. **Hot-path cost.** These helpers run inside RLS on every query. Adding a
   lookup through `lign_org_of_workspace` puts a second index probe on the
   critical path. Mitigation: both helpers stay `stable parallel safe security
   definer`, the FK indexes above are mandatory, and I will measure a
   representative query before/after rather than assume.
3. **Two meanings of "owner".** After this, `workspace_members.role='owner'`
   and `organization_members.role='owner'` both exist and mean different
   things. Mitigation: rename is not on the table (it would break the frozen
   member RPCs), so the UI must always qualify — "workspace owner" vs
   "organisation owner", never bare "owner".
4. **First run gets a second concept.** The `/welcome` screen currently asks
   for one name. It will now create an organisation *and* a workspace.
   Proposal: ask for one name, use it for both, and let them add workspaces
   later from the switcher. Asking a brand-new user to distinguish two
   concepts before they have seen either is how first runs get abandoned.

## 7. Frontend

- `/welcome`: creates org + first workspace in one step.
- Workspace switcher: gains **New workspace** for org admins.
- Org settings / org people: **out of scope** for this slice. Org membership
  is manageable by RPC only until there is a screen for it — flagged rather
  than half-built.

## 8. What I need approved

1. The schema in §3.
2. **The line in §4** — org admins read everything, sign nothing. This is the
   one decision that is expensive to reverse.
3. First-run behaviour in §6.4 — one name for both.

Nothing runs until these are agreed.
