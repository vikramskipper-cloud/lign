# Reviewer deliverables (APP 029)

Project and workspace leadership can grant **Can submit deliverables** to an
active project reviewer. This is an additional, project-scoped permission; it
does not change the five project role presets. A consultant remains a reviewer
and gains no general asset editing, publishing, approval or team-management
capabilities. Invited reviewers use it once their project invitation is claimed.

**Professional label** is a separate free-text description (up to 80 characters),
such as Structural consultant, Design consultant, Client or Fabric supplier.
It grants no access. Labels are assigned per project, allowing the same person
to have different responsibilities in different projects. Project people,
workspace external assignments and the owner access directory display the label
alongside the actual project role and submission permission.

## Assigning access

In Project people, expand **Professional label and submission access**, enter a
label and enable the reviewer permission. External invitations can include both
settings atomically through `invite_project_participant`; existing invitation
RPCs remain available. Only callers with `project.manage_access` can configure
these settings. Contributors and reviewers cannot grant themselves permission.
Changing a participant away from Reviewer or removing their participation clears
the extra grant. Restoring Reviewer requires a fresh, explicit grant.

## Author workflow

1. Open **Deliverables** in the project sidebar and create a new draft.
2. Give it a title and details. Create a design asset or choose an existing asset
   within this project; a new draft version is created with the author's identity.
3. Upload drawings, calculations, specifications, samples or other files using
   the existing private upload pipeline (500 MB per file and existing MIME rules).
4. Submit completed files for team review. Files and version details are frozen
   while the submission is under review.
5. If changes are requested, create a revised draft. It uses a new version of the
   same design asset, linked to the earlier submission. The previous submission
   and its file attachments remain unchanged.

Reviewers can edit or remove files only in their own permitted submission drafts.
They cannot edit another author's draft, change existing design versions or use
the general New asset/New version controls. Authors can withdraw an unreviewed
draft or submitted package; withdrawal retains its files and history.

Revocation blocks new upload, finalize, edit and submit requests. It does not
delete previous work or prevent the authorized team from reviewing it.

## Team review and publication

A project lead or contributor opens the submission and its version/files, then
accepts it for publication or requests changes with a note. Authors cannot review
their own submissions, even if their role is later upgraded. Review decisions
are serialized so concurrent actions cannot both succeed.

An accepted submission still has a draft version. The project team uses
**Publish accepted version** (the existing `publish_version` RPC). Publication
does not change the current design pointer. **Set as current design** is an
explicit, separately authorized action using the existing workflow.

The normal design workspace links submission versions back to their review
history. It hides publishing until acceptance and prevents discarding retained
submission versions. The database enforces those controls independently of UI.
Normal design versions outside this flow retain their existing permissions and
lifecycle behavior. Publishing a consultant version records the team publisher
while retaining the submission's original author and professional label.

## Storage and security boundaries

The standard hash → reserve → private Storage upload → finalize pipeline remains
in use. The new permission is checked against the exact submission version.
File/version/uploader reservations prevent a reviewer from attaching arbitrary
file IDs, including files in other projects. No broad `version.upload` or
`file.attach` capability is added to the Reviewer role.

Submission files have `files.submission_scope_id`. Their checksum uniqueness is
partitioned per submission, separate from ordinary team-upload deduplication.
An external author's claimed checksum cannot shadow a later ordinary team upload.
Legacy attachment and purge recovery also respect the new checksum scope.
Removed, unattached draft files enter the existing orphan/reclaim lifecycle.
Reviewed files retain their version references and remain part of history.

New submission/event tables are read through existing project visibility; direct
browser writes are denied. Upload reservations and the private upload helper
are not exposed to browser roles. Triggers freeze submitted/reviewed files,
require acceptance before publication, retain submission versions and record
publication history. Archived projects cannot receive new submission actions.

The shared upload scheduler now updates its scheduling state synchronously before
microtasks run. This prevents queued files being missed or scheduled repeatedly.
Upload components reset per version, respect an existing primary attachment and
can resume finalization after a successful byte upload whose response was lost.

## Verification and release

Use Node 22+ and the isolated LIGN stack on port 58321 with storage-api running.
Store local status JSON in ignored `ops/.tmp/access-local.json`; run the frontend
on port 5179 against that stack. The tests refuse hosted backends and use synthetic
accounts, actual private file uploads and no external email recipients.

```sh
node tests/access/studio-leadership.mjs
node tests/access/reviewer-deliverables.mjs
node tests/access/reviewer-deliverables-browser.mjs
```

Backend checks cover professional labels, grants, revocation, file-ID and checksum
isolation, retained revisions, self/concurrent review, publication and explicit
current-version selection. Browser checks cover configuration, atomic invitations,
two-file upload scheduling, review/revision/publication, owner directory labels
and mobile layouts. Supply `PLAYWRIGHT_MODULE` and `PLAYWRIGHT_CHROMIUM_PATH` for
external installations.

Commit/push GitHub `main` first, apply the exact migration file with recorded
checksums and verify Vercel's automatic Git deployment, as in `ops/DEPLOYMENT.md`.
SendGrid welcome/invitation delivery remains a separate pending integration.
