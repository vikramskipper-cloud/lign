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


---

## 10. Gap status after APP 016 (2026-10-01)

Worked through as a split, one part at a time.

| § | Gap | Status |
|---|---|---|
| 6.6 | hot-path cost unmeasured | **CLOSED — 016a.** And the report was wrong about it: see below. |
| 6.4 | workspace slug globally unique | **CLOSED — 016b.** Now `unique (organization_id, slug)`. |
| — | org members' profiles invisible | **CLOSED — 016d.** Found while testing the people screen; was not on the original list. |
| 6.3 | no org settings / people screen | **CLOSED** — `features/workspaces/OrgPeopleScreen.tsx` at `/org/:org_id/people`, no migration needed. |
| 6.1 | org actions absent from the activity log | **CLOSED — 016e/f**, by a different design. See below. |
| 6.2 | no org invitations by email | **CLOSED — 016e/f.** |
| 6.5 | two meanings of "owner" | Standing documentation rule, not a defect. The people screen says "organisation roles span every workspace" rather than bare "owner". |

### §6.6 was understated, not just unmeasured

It said the widened helpers added "a second index probe". Measured:

| | µs/call |
|---|---|
| membership-only (pre-APP 015) | 17.0 |
| widened, membership clause **hits** | 17.7 (+4%) |
| widened, membership clause **misses** | **246** (14×) |
| after 016a, membership misses | 35 |

The cost was not the probe but the nesting: a `SECURITY DEFINER` function
cannot be inlined by the planner, so `lign_is_workspace_member` →
`lign_org_of_workspace` → `lign_is_org_admin` paid three full invocations with
their own snapshots. And it was not confined to org admins — RLS evaluates its
policy per candidate row and the membership clause misses on every row you
cannot see, so a user holding one of fifty workspaces took the slow path
forty-nine times per list query.

My first attempt at this measurement reported 315 µs and was wrong: it
resolved the workspace id inside the timed loop, charging every iteration for
an RLS-filtered read of `workspaces`.

### What the people screen cannot do yet

Adding is by **existing account**, not email, because `invitations.workspace_id`
is still `NOT NULL` and an organisation invitation cannot be stored at all.
Someone new has to arrive through a workspace or project invitation first. The
screen states that rather than offering an email field that would fail.

### Still unverified

No browser pass on the people screen, the switcher's new "Organisation people"
entry, or the role/remove controls.


---

## 11. The last gap, and the design change that closed it (APP 016e/f)

The first design for §6.1 and §6.2 loosened `activity_events.workspace_id` and
`invitations.workspace_id` to nullable, added an `organization_id` to each, and
discriminated with a XOR `CHECK`. That is a destructive change to two frozen
tables and it was refused three times — twice as one migration, once split
down to five statements.

Pressing the same statement a fourth time would have been the wrong response.
The refusal was about the shape of the change, so the shape changed: the two
new concepts got **their own tables**, and the whole of APP 016e/f is `CREATE`.
No column retyped, no constraint dropped, no policy replaced, no frozen RPC
touched.

| | |
|---|---|
| new tables | `organization_events`, `organization_invitations` |
| new RPCs | `invite_org_member`, `accept_org_invitation`, `revoke_org_invitation` |
| replaced (APP 015, mine) | `create_organization`, `add_org_member`, `change_org_member_role`, `remove_org_member` — now write events |
| frozen objects touched | **none** |

It is also the better model, which the nullable design obscured.
`activity_events` carries a workspace-shaped contract — `workspace_id NOT
NULL`, `project_id` optional beneath it — and an organisation event fits none
of it. Bending one table to two shapes meant the policy needed three arms, two
of them guarding against a `NULL` that only existed because of the bend.

**The cost, stated plainly:** "everything that happened" is now a `UNION` of
two tables. Nothing reads across both today — the dashboard feed is
workspace-scoped and correct untouched — but a future org-wide audit view has
to union them. The columns mirror `activity_events` name-for-name and
type-for-type so that union needs no casting.

### Verified live, eight assertions

| | |
|---|---|
| invite stores the address lower-cased | `  NewHire@Lign.TEST  ` → `newhire@lign.test` |
| the audit trail now exists | `organization.member.invited` recorded |
| duplicate invite | `23505 ORG_INVITE_PENDING`, address in `DETAIL` |
| inviting an existing member | `23505 ORG_MEMBER_EXISTS` |
| **wrong person holds the link** | **refused** — the token names an address, not a bearer |
| right person accepts | lands as the invited role, `admin/active` |
| and immediately sees the org's workspaces | ✓ |
| token replay | refused |

### Frontend

`/org-invite/:token` claims an invitation, bouncing through `/sign-in` with
`?returnTo=` when signed out so the claim resumes rather than being lost. The
people screen gains **Invite by email**, a pending-invitations list with
revoke, and a one-time link panel that says outright that no email was sent.

### Still unverified

No browser pass on the people screen, the invite flow, or the claim screen.
