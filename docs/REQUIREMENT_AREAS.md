# Requirement hierarchy (APP 031)

This is the first release of the requirements → references → proposal journey:
project-wide needs, optional spaces/groups, and nested zones/components. Visual
reference boards, client shortlists and proposal acceptance are separate next
releases. Existing questionnaire templates and reference uploads remain available.

## Using the hierarchy

Open a project’s **Requirements**, then **Project-wide requirements, spaces and
zones**. The same area manager is available in the brief’s Clarify requirements
step. Project leadership creates named areas, chooses a parent and supplies a
label such as Space, Zone, Product, Component, Collection or Look. Areas are
optional; existing projects and requirements remain project-wide by default.
Existing free-text applicability notes are preserved without guessing areas.

Create or edit an area while there is no brief or the working brief is a draft.
After submission/agreement, return to draft/start a revision first. Parent links
are immutable: create a new area and retarget assignments to reorganise. Up to
eight levels are supported. Names are case-insensitively unique among active
siblings. Empty areas can be archived; active children, current brief references
and draft/active requirement assignments must be removed first. Historical
references remain stored. Archived areas cannot receive new assignments.

## Requirement scope

Select one or more areas when creating a requirement or in its detail Overview.
Leave the selection empty for project-wide scope. Sub-requirements inherit their
root requirement’s areas and cannot override them. Area scope is independent of
the existing design-asset applicability and assessment rules; this release does
not automatically map areas to design assets.

The hierarchy browser filters **on the server**, with cursor pagination. A zone
includes project-wide and ancestor-space requirements as well as its own. A space
includes descendant-zone requirements by default; uncheck Include child areas
for just that space and its ancestors. Unrelated sibling requirements stay out.
Multi-area requirements appear once. Draft/active, historical status filters,
project-wide-only browsing and archived area history are supported. The existing
requirements tracker, filters and asset traceability remain available.

Area assignment uses requirement editing permissions. Structure management uses
project leadership; the assigned brief approver can assign existing areas to
brief items, but cannot administer the hierarchy. Clients and reviewers retain
their existing project visibility and cannot directly write the new tables.

## Brief agreement and handoff

Brief items carry area IDs and server-derived area snapshots. The server rejects
cross-project, archived and malformed IDs and ignores client-supplied snapshots.
Paths are refreshed when requesting agreement, under the same project lock as
area edits. Areas cannot change while agreement is pending or the working brief
is agreed. Historical brief views show their saved item paths, not the current
area manager. A later draft may rename areas without changing old agreements.

Generating requirements from an agreed revision copies its area IDs and records
the agreed area paths in the requirement description. Repeated generation remains
idempotent. Historical generation can retain an archived area reference; ordinary
new assignments cannot target archived areas. The agreed-brief design gate and
independent-approver rule remain in force.

## Backend and checks

`project_areas` and `requirement_areas` have RLS, project/workspace foreign keys
and covering indexes. Browser roles receive SELECT only. Checked RPCs perform
creation, editing, archive and assignment atomically; area changes use the existing
`project.updated` audit event and assignments use `requirement.updated` with
`kind=edit`. A creation wrapper composes the frozen requirement creation RPC and
area assignment in one transaction. Invalid scope rolls back the new requirement.
Project locks serialise hierarchy edits, assignments and brief transitions.
Existing frozen migration files remain unchanged.

Local checks (isolated LIGN backend on 58321 and frontend on 5179):

```sh
node tests/access/studio-leadership.mjs
node tests/access/requirement-areas.mjs
node tests/access/requirement-areas-browser.mjs
```

Supply external Playwright/Chromium paths as for the other browser checks. Tests
cover permissions, cross-project rejection, direct-write denial, sibling races,
depth and parent guards, archiving, inheritance, pagination, atomic rollback,
forged snapshots, agreement history, scoped generation, client UI and mobile.
Run the existing brief regression suite on a separate fresh leadership fixture.
Release through GitHub main first, a guarded atomic migration apply, checksum and
schema provenance checks, then verify Vercel’s automatic Git deployment.
