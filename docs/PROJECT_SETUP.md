# Project setup (APP 030)

Project basics → Gather requirements and references → Review and agree → Design.

## Client information

Creation and Edit project support optional client company, contact name, email
and phone. The project overview displays them. Values are trimmed, email is
lowercased and the database validates formats/lengths. The same project visibility
rules protect these details. Recording a contact creates no account, invitation
or permission; project approvers and People remain the explicit access controls.
This is a contact record per project, not an organisation-wide client directory.

`create_project_with_client` calls the existing atomic `create_project_full`
inside its transaction, then saves client information. Invalid details roll back
the whole creation, including invitations. Existing callers remain supported.
`update_project_details` checks project editing permission and emits the existing
`project.updated` event. Both RPCs reject anonymous callers.

## Project codes

A partial unique expression index enforces case-insensitive, trimmed codes among
unarchived projects within a workspace. Empty codes remain optional. The database
normalises new/edited codes to uppercase and validates the existing 16-character
format. Creation, legacy RPCs, edits, concurrent requests and archive restoration
all meet the same constraint. Archived codes may be reused; restoring a project
then requires resolving any collision. Migration fails on existing collisions
rather than renaming customer data. New creation calls serialise per workspace
to also protect generated slug allocation. Availability checks are advisory.

## Brief agreement gate

An immutable **agreed** decision on a project brief revision unlocks design work.
No brief, draft, awaiting agreement and changes requested all remain locked until
there is an agreed baseline. The existing independent approver rule still applies.
People, project metadata, requirement planning and brief references remain usable
while setting up the project. A recorded client contact is not a brief approver.

Project design routes display the gate and a link to the brief. Capabilities
reject design, upload, review, approval, release and assessment writes before
agreement; reviewer submission permission also requires agreement. Database
triggers on design assets, versions, reviews, approvals, releases and deliverable
submissions protect direct table writes and definer paths. Existing authorization
continues to apply after unlocking; agreement grants no new user role.

Starting a later working revision preserves the immutable agreed baseline and
does not relock ongoing design work. The gate checks agreement history, not just
the mutable working brief status. Users cannot directly write agreement history.
The interface refreshes readiness every 15 seconds and invalidates readiness and
capabilities immediately after its own brief mutations. Project layout and edit
forms are deferred to stay within the existing bundle budget.

## Verification and rollout

Use the isolated local backend on port 58321 and frontend on port 5179. Tests
refuse hosted backend URLs and use synthetic accounts only:

```sh
node tests/access/studio-leadership.mjs
node tests/access/project-setup.mjs
node tests/access/project-setup-browser.mjs
```

Supply external Playwright/Chromium paths as for the existing access browser tests.
Checks cover contact round-trips and atomic failure, unauthorized access,
concurrent code creation via new/legacy RPCs, edits, archive reuse/restoration,
blocked APIs/direct writes, independent agreement, later revisions, browser
creation/editing, protected design routes, mobile layout and page errors.
Existing brief and reviewer-deliverables suites remain valid; design fixtures
obtain a real brief agreement through checked RPCs when needed.

Commit and push GitHub first, apply the exact migration with a guarded baseline
and single transaction, then verify migration checksums, schema provenance and
the Git-triggered Vercel production deployment. Production preflight must check
for existing code collisions and design work without an agreed brief; resolve
such data explicitly before rolling out. No production fixtures are created.
SendGrid welcome/invitation delivery remains separately pending.
