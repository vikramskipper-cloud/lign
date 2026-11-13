# Navigation layout

The root shell contains global destinations only: role-aware Overview,
Workspaces, My work, Inbox and administrator-only People & access. Workspace,
project, workflow and pinned-project links no longer accumulate in the sidebar.
The organisation picker names the current tenant; shared access is distinguished
without guessing an organisation membership. Account and platform actions remain
in the existing avatar menu. No placeholder organisation-settings page is added.

## Workspace and project context

`/workspaces` is a searchable directory over the existing RLS-filtered workspace
query. Organisation selection filters that directory. Administrators can launch
the existing New workspace dialog with the selected organisation. The old
`/workspace-picker` URL redirects while preserving query strings and hashes.

A workspace has in-content Overview (leadership), Projects, Work queue and Team
(leadership) navigation. Work queue exposes the existing Reviews, Approvals,
Requirements and Releases screens. Workspace settings is a local header action.
Entering a project removes the workspace header/tabs; only the project context
remains, with an explicit **Back to workspace** link returning to its workspace’s
project list, alongside the workspace picker. This works on desktop/mobile and
for externally assigned clients, including direct/deep-linked project pages.

Project navigation has five sections, filtered by existing read capabilities:

- Overview.
- Brief & requirements: Brief, Spaces & zones, Reference boards, Requirements tracker.
- Design: Proposal, Design assets, Deliverables.
- Review & delivery: Reviews, Approvals, Releases.
- Team & access: existing project people and permissions.

Workspace/project pickers live inside the context header, with the project picker
beside its title rather than repeating the name in the breadcrumb. Pinned projects
appear first in that picker. Section and page links use existing canonical URLs;
detail aliases (assets/versions, submissions, individual requirements, reviews,
approvals and releases) select the correct parent section. Longest route matches
keep Spaces & zones separate from the Requirements tracker.

A phase indicator reflects the existing journey RPC. Stage locks stay navigable
and explain the earliest prerequisite. The project header remains present on
locked/error/loading workflow pages. Server permissions and both acceptance gates
remain authoritative and unchanged.

## Responsive behaviour

Desktop uses a compact stable global rail and sticky contextual tabs. On small
screens the rail becomes a modal drawer with focus trapping, Escape/close/backdrop
handling and focus restoration. Crossing to desktop closes the drawer. Project
or workspace sections become a native selector on phones; secondary pages scroll
horizontally and automatically reveal the active page without scrolling the whole
page vertically. Only one workspace/project navigation level is rendered at once.

## Scope deliberately deferred

This release changes navigation and presentation only. My work and Inbox continue
to use their existing selected-workspace data. A **Viewing workspace** selector
makes that scope explicit within each page. Notification counts also retain their
current workspace scope. Organisation-wide aggregation and brief/proposal task
coverage are separate follow-up work; no new backend RPC, migration, permission
or notification behaviour is introduced here. Existing role-aware landing pages
remain in place.

## Verification

`tests/access/navigation-browser.mjs` uses the populated isolated local planning
demo (port 58321 backend, 5179 frontend). It checks global/context separation,
role visibility, workspace directory/queues/settings, canonical/deep-link active
states, stage gates, preserved feed filters and legacy URLs, mobile overflow,
drawer keyboard focus and active-tab visibility. It creates no business records.
The existing reference/proposal browser suite verifies the workflow under the new
layout. Run unit tests, typecheck/build and the unchanged bundle budget before
pushing GitHub main. Verify Vercel's resulting Git deployment and read-only public
smoke checks. No database rollout is required for this release.
