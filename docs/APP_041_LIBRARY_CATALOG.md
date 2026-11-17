# APP 041 — Organised shared library

The organisation Library opens on a browsable catalogue instead of automatically opening the first collection. Published library, My contributions (All contributions for admins), and an admin-only Review queue separate retrieval from contribution and review. Templates, Mood boards, References and Designs have visible type controls; custom tags provide organisation-specific categories without prescribing an industry. Cards show an authorised image cover or type icon, description, contributor, status, tags and item count.

Search includes collection metadata, tags, contributor, item titles/details, source URLs and original filenames. Matching items link directly into their collection. Type, tag and contribution-status filters combine with search. Results are ordered by title/id and paginated in groups of 24. Search and browse context remain in the URL when opening a collection and returning. New collection creation resets unrelated browse filters and opens the new working collection.

Each collection has an explicit Back to Library action, published/working version selection where permitted, searchable content, format filters and grid/list layouts. Focused dialogs replace inline creation/settings/edit forms. Multiple file upload accepts up to 20 files of 50 MB each, with editable titles and individual progress/errors. Retry handles failed entries without repeating successful registrations. Links and notes use the existing single-item editor. Empty states explain the next step. Unsaved edits and active uploads guard route changes, unload and dialog dismissal; publication controls cannot run during incomplete content edits or saves.

The additive `get_library_catalog` RPC checks active organisation membership and admin rights for the review queue. It delegates to existing checked collection/item getters, and filters eligibility before calling private draft getters. Published search, tags, counts and covers come from immutable approved snapshots, including for authors/admins during a pending revision. Contributions include only collections whose working version the caller can already access. External project participants cannot access this catalogue. Existing RLS, file signing, version locks, owner approval, immutable history and independent project imports remain unchanged. No email-provider integration is included.

Migration: `20261117030000_app_041_library_catalog.sql` (one read-only function, authenticated/service-role execute only; empty search path). Legacy null tags are treated as an empty tag list.

Validation:

- `tests/access/library-catalog.mjs`: filename/details/URL search, type/tag filters, image covers, review access, pagination, invalid filters, external denial, author-only drafts and approved-only search during a revision.
- `tests/access/library-review-browser.mjs`: browse/create, guarded dialogs, partial batch failure/retry, formats/list layout, private draft exclusion, changes requested/resubmission/publication, matched-item navigation, type/tag filtering, immutable approved preview/import and desktop/mobile layouts.
- Updated `tests/access/organization-library-browser.mjs`: upload navigation guard, approved import, client image access, catalogue denial and independent source edits.
- Existing `tests/access/library-review.mjs`: ownership, file privacy, version conflicts, review locking, immutable history and publication/import regressions.
- TypeScript/production build, 80 unit tests and initial-bundle budget.

Deliberate scope: types and reusable tags organise collections; nested folders, favourites, drag-and-drop moves and full-text extraction/OCR inside file contents are not added. Search indexes saved metadata and filenames, not the contents of binary documents. Existing 60-second library-preview URLs retain their current expiry.
