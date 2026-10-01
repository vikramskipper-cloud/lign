# APP 015 — Organisations above workspaces: implementation report

**Applied.** Migration `20260923120000_app_015_organizations`, 74/74 migrations
byte-identical to the deployed database. Proposal and approved decisions in
`APP_015_BACKEND_PROPOSAL.md`.

Approved before building: org admins get **read + member administration, no
work capabilities**; first run asks for **one name** and creates both.

---

## 1. What changed

Two tables, one column, three new helper functions, two widened ones, five
RPCs. **No RLS policy was edited and `lign_has_capability` was not touched.**

| | |
|---|---|
| new tables | `organizations`, `organization_members` |
| new column | `workspaces.organization_id` (NOT NULL) |
| new helpers | `lign_is_org_member`, `lign_is_org_admin`, `lign_org_of_workspace` |
| widened helpers | `lign_is_workspace_member`, `lign_is_workspace_admin` |
| new RPCs | `create_organization`, `add_org_member`, `change_org_member_role`, `remove_org_member` |
| changed RPC | `create_workspace` — gained `p_organization_id` |
| RLS policies edited | **0** |

## 2. Why it was two lines of SQL and not a rewrite

I originally told you this would "touch RLS on nearly every table". That was
wrong, and measuring it was the most useful thing I did on this task:

| | count |
|---|---|
| RLS policies in `public` | 69 |
| …resolving through `lign_has_capability` | 52 |
| …through `lign_is_workspace_admin` | 8 |
| …through `lign_is_workspace_member` | 5 |
| …through `lign_project_role` | 1 |
| **…hand-rolling a `workspace_members` check** | **0** |

Because nothing inlines membership, org authority propagates from one clause
added to each of two functions:

```
lign_is_workspace_member(ws) -> <existing> OR lign_is_org_admin(lign_org_of_workspace(ws))
lign_is_workspace_admin(ws)  -> <existing> OR lign_is_org_admin(lign_org_of_workspace(ws))
```

The first gates the `workspaces` SELECT policy, which is literally "the owner
can view all the workspaces". The second is what `lign_has_capability`
consults for the six workspace keys and the nineteen project read keys.

## 3. Verified, under real JWTs

Fixtures seeded in a transaction and rolled back: org A (two workspaces, the
second one with no org person as a workspace member), org B (separate tenant),
and a project inside the workspace the org people were never added to.

| actor | workspaces visible | projects visible | `project.view` | `workspace.manage` | `version.upload` | `approval.respond` |
|---|---|---|---|---|---|---|
| org **owner** | **both** | Northgate Flagship | ✓ | ✓ | **✗** | **✗** |
| org **admin** | **both** | Northgate Flagship | ✓ | ✓ | **✗** | **✗** |
| org **member** | none | none | ✗ | ✗ | ✗ | ✗ |
| workspace admin, **no org** | **its own only** | Northgate Flagship | ✓ | ✓ | ✗ | ✗ |
| other tenant's owner | **Rival Space only** | none | ✗ | ✗ | ✗ | ✗ |

Four things that row set proves: org admins reach workspaces they were never
added to; they hold no work keys; a non-org workspace admin is **unchanged**,
which was the regression risk of widening a shared helper; and tenants are
isolated.

Also verified: a second workspace in the same org succeeds, a repeated name
suffixes its slug (`northgate-team-2`) instead of failing, and calling
`create_workspace` with a null org when you already belong to one is refused
(`22004`) rather than quietly starting a parallel tenant.

## 4. The backfill I said would be free

It wasn't. I wrote `add column … not null` on the strength of having just
cleared the database, and the migration failed: a workspace had been created
through the first-run flow in between. The column is now added nullable, each
existing workspace gets an organisation of its own, then NOT NULL is set —
which is the shape this needed permanently anyway.

Promotion is narrow on purpose: only workspace **owners** become org owners.
Promoting workspace admins too would hand them authority over every workspace
the org gains later, which is not what they were granted. Where a workspace
has no active owner — how every workspace in this database sat until recently
— active admins are promoted instead, and with nobody at all the migration
**aborts** rather than create an organisation no human can administer.

Result: `Atkinson Studio` org owns the `Atkinson Studio` workspace, demo is
its owner.

## 5. Frontend

- `shell/orgQueries.ts` — `useMyOrganizations`, `useAdminOrganizations`, `useCreateWorkspace`.
- `useAccessCheck` now counts **visible workspaces** rather than membership rows, and reports `adminOrgIds` / `orgMemberships`. `needsWorkspace` means "can open no workspace **and** can do something about it", so a plain org member is sent to `/no-access` instead of a form that would always fail.
- `/welcome` branches: no org → one name creates org + first workspace; org admin with no workspace → names a workspace inside the org it already has.
- `features/workspaces/NewWorkspaceDialog.tsx` + **New workspace** in the header switcher, gated on being an org admin. The switcher now opens whenever there is anything in it — previously `all.length > 1` hid the add action from everyone with exactly one workspace, i.e. everyone on day one.
- The switcher menu is headed by the organisation name, so you can see which tenant you are inside.
- `WorkspaceRow` carries `organization_id`.

## 6. Gaps and consequences — flagged, not worked around

1. **Organisation-scoped actions are not in the activity log.**
   `activity_events.workspace_id` is NOT NULL, so `create_organization`,
   `add_org_member` and the role changes write no event. Fixing it means
   making that column nullable or adding `organization_id` — a schema change,
   so it is listed rather than invented. Workspace and project events are
   unaffected.
2. **No org invitations by email.** `invitations.workspace_id` is also NOT
   NULL, so an org invite cannot be represented. `add_org_member` therefore
   takes a `profile_id` and the person must already have an account. Included
   anyway, because without it an org owner could never appoint a second admin
   — the same bootstrap dead end that left every workspace in this database
   ownerless.
3. **No org settings or org people screen.** Org membership is RPC-only for
   now. Deliberately not half-built.
4. **`workspaces_slug_key` is UNIQUE(slug) globally, not per organisation.**
   One tenant's choice of name can block another's. `create_workspace`
   suffixes rather than failing, so nobody is blocked in practice, but making
   it per-org means dropping a frozen unique key.
5. **Two meanings of "owner".** `workspace_members.role='owner'` and
   `organization_members.role='owner'` both exist and differ. The UI must
   always qualify — "workspace owner" vs "organisation owner", never bare
   "owner".
6. **Hot-path cost not yet measured.** The widened helpers run inside RLS on
   every query and now do a second index probe. The indexes are in place
   (`organization_members(user_id, organization_id) where status='active'`,
   `workspaces(organization_id)`) and both helpers stay `stable parallel safe`,
   but I have not benchmarked a representative query before/after. Worth doing
   before there is real data volume.

## 7. Not verified

Typecheck clean, 68 tests, build passes, bundle within budget. **No browser
pass** — the switcher's new menu, both `/welcome` branches and the dialog have
not been clicked through.
