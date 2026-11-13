# Project briefs (APP 028)

The project journey is **Project basics → Gather requirements → Review and agree → Design work**.
The creation form collects the name, code, lead and optional description/approvers;
disciplines, scope, budget, schedule and references belong in the brief.

New projects open at **Project brief**. Design work stays locked until an independent
project approver agrees a brief revision; later working revisions retain that baseline.
See [Project setup](PROJECT_SETUP.md) for client details, code uniqueness and enforcement. Existing projects can open it from the
project sidebar or overview. The same journey supports interiors, architecture,
product design, furniture and fashion: gather needs → clarify → reference →
review and agree → generate requirement drafts.

See [Requirement hierarchy](REQUIREMENT_AREAS.md) for project-wide requirements,
spaces/zones, inherited scope and preserved area paths in agreed revisions.

## Gather and clarify

Start with shared questions about objectives, audience, deliverables, scope,
budget, schedule, success and decision-makers. Choose no discipline template,
one template, or a combination. Templates add questions without deleting existing
answers when deselected. Optional questions can be edited or removed and custom
questions added. Objective and deliverables remain required for submission.

Save incomplete drafts. Project leadership assigns one project approver as the
client/brief respondent. This can be an internal or external approver already
assigned to the project. A pending invite may be selected, but the recipient
must activate and accept access before an agreement can be requested.

Separate mandatory requirements, preferences, assumptions and open questions.
Record the source, priority, relevant space/component/item/garment (or whole
project), responsible person, and acceptance criteria. Criteria can be a
measurement with units, a test, a sample/reference or a person's judgement.
Clarification notes support discussion; the answer belongs in the brief itself.
Resolve open questions and provide acceptance criteria before agreement.

## References

Reference links accept HTTP/HTTPS URLs. Private reference uploads support PDF,
PNG, JPEG, WebP, TXT, CSV, DOCX and XLSX, up to 10 MB each. Save the draft before
uploading/removing files. Upload important source material when an agreed copy
needs to be preserved; external link content can change independently of LIGN.

The `brief-references` bucket is private. Uploads require draft-edit permission;
downloads require project visibility and a registered reference. Download links
expire after 60 seconds. Registered objects cannot be overwritten or deleted by
browser users. Removing a reference from a later draft does not remove the file
from earlier agreement revisions. An unregistered failed upload can be discarded
by its uploader.

## Review and agreement

The respondent or leadership submits the draft for team review. Leadership can
return it to draft to clarify answers. **Review and request agreement** records
the reviewer's endorsement and creates an immutable numbered revision containing
the document and reference-file metadata. It also resolves default requirement
owners to named active internal project leads/contributors.

Only the assigned, active project approver can agree or request changes. The
person requesting agreement cannot also be its respondent. Changes requested
require a note and return the working brief to draft. Leadership can also
withdraw an outstanding request. Each new request creates a fresh revision.
Stale and duplicate responses fail rather than approving a different revision.

An agreed brief is locked. **Start a new revision** opens a working draft while
previous revision content and decisions remain immutable. Read earlier revisions
using the View selector. Brief agreement is distinct from design-version approval.

**Copy agreement link** shares the protected page with the assigned approver.
The recipient signs in through the existing access-only beta route. This release
does not introduce anonymous intake links or automatic brief email notifications.
SendGrid setup for welcome/invitation delivery remains pending separately.

## Requirements handoff

From an agreed revision, leadership with `requirement.create` can generate linked
draft requirements for its mandatory items and preferences. Assumptions and
questions remain in the brief. Existing requirement creation RPCs preserve owner,
source and priority; the requirement description carries kind, applicability text
and acceptance criteria. Repeating generation for a revision creates no duplicates.

The handoff opens the existing Requirements area filtered to drafts. Review a
draft and use **Activate requirement**. Generating drafts from a later agreed
revision does not silently replace existing active requirements; the team uses
the existing supersession/archive workflows as appropriate. Asset applicability,
version assessment, reviews and design approval retain their existing semantics.

The end-to-end check also exposed a pre-existing dashboard pagination bug:
`list_requirements_dashboard` referenced a CTE from a later SQL statement. APP 028
preserves the RPC signature, filters, permissions and saved-view contract while
computing the page and cursor in one statement. Frozen migrations remain intact.

## Permissions and implementation

| Action | Permission |
| --- | --- |
| Read the brief, revisions and references | Existing project visibility, including inherited studio/workspace administration |
| Start a brief, assign its respondent, request agreement or start a revision | Project access management, on an unarchived project |
| Edit draft answers and reference files | Leadership or the assigned active project approver |
| Post clarification notes | Existing project comment permission |
| Respond to agreement | The active approver named on the current request |
| Generate draft requirements | Leadership plus existing requirement creation permission |
| Activate a requirement | Existing requirement editing permission |

Direct browser writes to the new tables are denied. Checked RPCs lock and update
the working brief, with an edit version for optimistic concurrency. Conflicts use
HTTP 409 (`PT409`), avoiding automatic database serialization retries. Agreement
requests and decisions are serialized. Snapshot and decision update/delete
triggers protect history. New tables use project-scoped keys and read policies.
The schema inventory includes LIGN-owned reference-file storage policies.

## Verification

Use Node 22+, the isolated backend on port 58321, and a frontend on port 5179
configured against that backend. Save local Supabase status JSON in ignored
`ops/.tmp/access-local.json`. The tests refuse hosted backends and use synthetic
accounts. Start storage-api as well as Auth, REST and the database.

```sh
node tests/access/studio-leadership.mjs
node tests/access/project-brief.mjs
node tests/access/project-brief-browser.mjs
```

The first two scripts prepare local fixtures for browser checks. Supply
`PLAYWRIGHT_MODULE` and `PLAYWRIGHT_CHROMIUM_PATH` for external installations.
Coverage includes concurrent saves/requests/decisions, role isolation, self-review
rejection, private files, immutable history, requirement generation and pagination.
Browser checks cover interiors, furniture and fashion, mixed templates, client
handoff, active requirements and mobile layout. No production user or project is
created by these tests.

Release through GitHub `main`, apply the exact migration file with recorded
checksums, and verify Vercel's automatic Git deployment, following
`ops/DEPLOYMENT.md`.
