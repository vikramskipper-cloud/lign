# Studio and workspace leadership (APP 025)

The beta remains access-only. An approved studio owner activates their account,
then invites architects through **Studio people**. Once an architect joins, the
owner can assign them to one or more workspaces without another invitation.

## Roles and everyday flow

| Role | Scope and responsibilities |
| --- | --- |
| Studio owner / administrator | Create workspaces, appoint workspace leads, assign architects, and oversee all studio workspaces and projects. |
| Workspace lead | Oversee every project in their workspace, add existing studio architects to its team, create projects, and appoint project leads. |
| Project lead | Manage their project's participants and design workflow. |
| Team member | Work on assigned projects according to their project role. Workspace membership alone does not expose other projects. |

Workspace lead is the display name for the existing workspace `admin` role.
Owners retain their workspace `owner` membership when delegating a lead. A
studio owner or administrator also inherits administrative visibility into
workspaces created by other studio administrators.

Create a workspace with a name, a workspace lead, and optional team members.
Create projects within it and select a project lead from that workspace's team.
Use **Manage team** to change workspace assignments, and **Project team** to
assign junior/senior architects to individual projects. Only studio leadership
can appoint or change workspace leads. Replace a project's last active lead
before demoting or removing them, including through workspace removal.

## Oversight

Studio owners and administrators land on `/org/:org_id/overview`. Workspace
leads land on `/workspace/:ws_id/overview` for the selected workspace. These
screens show projects, leads, statuses, open reviews, pending approvals, and
recent activity. Summaries refresh every 30 seconds and after team/project
changes. **My work** remains available for personal work.

Overview scope is checked in the database. Workspace leads receive only their
workspace's data; contributors cannot retrieve leadership summaries. Existing
project capabilities still govern creative actions such as publishing and
responding to approvals.

## Implementation and verification

Migration `20261112120000_app_025_studio_leadership.sql` adds atomic workspace
team creation, existing-colleague assignment, scoped overview queries, and a
database guard against removal of the last project lead. Activated workspace
colleagues become studio members if no organization membership exists; existing
organization roles and removal decisions are preserved.

The portal's project-creation flow requires workspace administration, as
introduced in APP 018. Older `PERMISSIONS.md` statements about the original
member-level `project.create` preset describe the earlier model; they do not
grant ordinary members access to `create_project_full`.

Local tests refuse hosted URLs and use synthetic accounts on port 58321:

```sh
node tests/access/access-flow.mjs
node tests/access/studio-leadership.mjs
node tests/access/studio-browser.mjs
```

Use Node 22 or later. Save the isolated stack's status JSON to ignored
`ops/.tmp/access-local.json` first. The leadership test writes local fixtures
used by the browser test. Run the frontend on port 5179 against that stack.
Supply `PLAYWRIGHT_MODULE` and `PLAYWRIGHT_CHROMIUM_PATH` when Playwright and
Chromium are installed outside the repository. No test sends email or creates
production users.

Release through GitHub `main` and verify the Vercel Git deployment, following
`ops/DEPLOYMENT.md`. Apply the migration from its exact file and verify the
recorded migration checksum. SendGrid configuration remains a separate rollout
step for email delivery.
