# References and design proposals (APP 032)

The project journey is now:

**Requirements + reference boards → Brief agreement → Proposal preparation →
Internal review → Client acceptance → Detailed design.**

Reference preferences, brief agreement, proposal acceptance and later design-version
approvals are separate actions. A shortlist never grants design permission.

## Reference collaboration

Open **Reference boards** in the project sidebar. Project leadership creates
project-wide boards or boards for an active space/zone. Area browsing includes
project-wide and ancestor-area boards. Choose Mood board, References or Reusable
visual template. Templates can be copied into fresh mood boards within the same
project; votes, comments and brief selections are not copied. A cross-project
organisation template library is not part of this release.

Active participants with existing comment permission can suggest a reference,
add a source URL and upload an image/document to their card. Authors and project
leadership can edit or archive references. Only leadership administers boards
and explicitly selects **Include in brief**. Users can shortlist, like, reject,
clear their own preference and explain why. Preferences retain their user identity
and changes are audited. Discussions are append-only and paginated. Boards/cards
are paginated; the browser does not filter an incomplete page of results.

At brief agreement request, the server snapshots up to 100 team-selected references,
including uploaded file metadata, area paths and named preferences. Clients see
the captured selection in the brief’s References step. Later card edits, preferences,
archiving or attachment replacement do not rewrite old agreement snapshots. Current
working drafts link to the live boards. Previous uploads remain available for
reviewed copies. External website contents can change; upload a copy when exact
visual material needs to be retained. Reference selection metadata is limited to
200 KB; draft brief saves discard obsolete selection snapshots and recapture them
at the next agreement request.

## Design proposal

An agreed brief unlocks proposal preparation, not detailed design. Internal project
leads/contributors and inherited project administrators prepare a draft pinned to
an agreed brief revision. It includes title, summary, scope, indicative budget and
timing, assumptions/exclusions, concept/material sections per area, selected board
references, optional requirement links and separate proposal files. Search source
pickers to find references/requirements; selected entries remain visible across
searches. Sources, areas and the baseline are validated against the same project.

Save incomplete drafts. Submit a complete summary, scope and concept section for
internal review. Leadership returns it to draft or endorses it with **Review and
request client acceptance**. The assigned active project approver must be distinct
from both the proposal author and reviewing actor. Include a file or reference
before requesting acceptance. A new immutable numbered revision captures the exact
proposal document, agreed brief and its attachments, reference/preferences,
requirement text and area paths, proposal files and the internal review record.
Proposal snapshot metadata is limited to 5 MB.

Clients see reviewed packages and revision history, never the working proposal
or unreviewed proposal uploads. Only the current named approver can accept the
exact revision or request changes with a note. Stale/duplicate decisions return
HTTP 409. Changes reopen the working draft; the old reviewed document/files stay
available. A different request creates a new revision. Pending requests can be
withdrawn by leadership by returning to draft. The interface resets confirmation
when the viewed revision changes and offers a protected acceptance-page link.

The first accepted proposal unlocks existing design assets, uploads, reviewer
deliverables, design reviews, design-version approvals and releases. Enforcement
is in checked RPCs, existing capabilities and database triggers, as well as direct
URL gates. Reference boards, people, brief work and requirement planning stay
available. Later brief/proposal drafts do not erase immutable accepted baselines
or freeze ongoing work; new proposal content remains unaccepted until its own
revision is accepted. This is a phase milestone, not a replacement for the existing
per-version approval/release process or automatic requirement assessment.

## Files, history and permissions

The new private `project-planning` bucket accepts PNG/JPEG/WebP, PDF, TXT, DOCX
and XLSX, up to 50 MB each. Uploads use server-generated reservations bound to
project, exact reference/proposal, uploader and edit version. Byte uploads and
finalization re-check current editing rights, including revocation, and match
Storage owner, MIME type and byte size. Paths are unique and registered bytes
cannot be overwritten/deleted by browser users. Unregistered uploads can be
cleaned up only by their uploader. Proposal uploads freeze outside draft status.
Up to 50 active proposal files are supported. Removing or replacing an attachment
changes the working selection while reviewed copies remain readable.

All new tables have RLS and RPC-only writes. Working proposal and file reads
have separate team/reviewed-package policies. Cross-project relationships use
composite foreign keys and covering indexes. Proposal revisions, decisions and
reference comments have immutable-history triggers. New operations emit existing
`project.updated` events with a `planning_action` payload; no new event vocabulary
or real-time publication is introduced. Short-lived private download URLs are used
for files. This release sends no invitation or approval emails; SendGrid remains
pending independently. Existing sign-in and explicit project access still apply.

## Verification and release

Use the isolated LIGN backend on 58321 and frontend on 5179. Tests refuse hosted
backends and use synthetic accounts with no external recipients:

```sh
node tests/access/studio-leadership.mjs
node tests/access/reference-proposal.mjs
node tests/access/reference-proposal-browser.mjs
```

Supply external Playwright and Chromium paths as for existing browser suites.
Backend coverage includes participant permissions, RLS, source isolation, real
private uploads, ownership/size checks, overwrite/deletion protection, revocation,
client draft/file privacy, copied templates, pinned brief/reference evidence,
concurrent saves/decisions, requested changes, stale responses, dual-role self
approval rejection and accepted-baseline continuity. Browser coverage follows the
whole owner/client journey, actual reference and proposal uploads, revision-one
file retention while accepting revision two, both phase gates, SPA unlock and
mobile layouts. Design-focused legacy fixtures now obtain a real accepted proposal.

Release GitHub main first, apply the exact migration transactionally under the
migration-history checksum guard, then verify schema provenance and Vercel’s Git
commit. Production preflight must reconcile any existing detailed design work
before enabling the second gate; do not silently lock an established project or
manufacture acceptance history. No production fixtures are used for verification.
