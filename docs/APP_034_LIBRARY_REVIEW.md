# APP 034 — Member contributions and library approval

Active internal organisation members can create private template, mood board, design and reference collections, with files, URLs and searchable tags. Authors and organisation admins can edit drafts. Other members see approved publications; external stakeholders retain project-only access.

The workflow is **Draft → In review → Published**, with **Changes requested → Resubmit** and withdrawal back to draft. Submission locks metadata and references. Only an organisation owner/admin can publish or request changes; feedback is required when requesting changes. Authors/admins can start a revision of a published collection. An author cannot archive a collection with a published baseline; that requires an administrator.

Publication writes an immutable metadata/reference snapshot, publisher, revision number and publication timestamp. Published file identities are retained in a tenant-constrained revision/file table. Pending draft changes do not replace the approved title, tags, descriptions, references or files that other members and project imports receive. Existing project copies remain independent after later approvals. Existing nonempty administrator-curated collections are backfilled as revision 1; empty collections become drafts.

All saves, transitions and imports serialize on the collection row. Reference edits advance the collection version, so stale review actions fail. Approved files remain immutable; unpublished uploads are readable only by their uploader, the collection author or organisation admins with active membership. External clients can read only files explicitly published into their projects. Raw draft tables use author/admin RLS; checked catalogue and preview RPCs return approved snapshots to other members. Approval and feedback events are immutable and visible to authors/admins. The Library offers stage filters, submission counts, contributor names, review feedback/history and a separate published-version preview.

Migration: `20261113090000_app_034_library_review.sql`. No email delivery is added.

Validation: `tests/access/library-review.mjs` covers draft ownership, raw-table/file privacy, concurrent/stale transitions, locked submissions, feedback/resubmission, admin-only approval, immutable revision/history records and revision-safe imports. `tests/access/library-review-browser.mjs` covers the author → owner → changes requested → approval flow, approved-version preview and project import. Existing organisation library and browser tests now publish collections before importing them.
