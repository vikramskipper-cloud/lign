# APP 045 — Brief status and next action

The first Review & agree improvement adds a compact status card above the existing decision controls. It distinguishes a working draft from a saved agreement revision, names who acts next, and offers an action appropriate to the viewer:

| State | Next action |
|---|---|
| Draft | Leadership reviews the brief; editable contributors continue editing; other viewers see responsibility information |
| Submitted | Project leadership reviews the brief |
| Awaiting agreement | The assigned responder reviews the requested revision; other project leaders can copy the agreement link |
| Changes requested | The team can read the recorded feedback and update the brief |
| Agreed | Users with server-confirmed proposal-preparation access continue to Design proposal; other viewers open the agreed brief |

Changes requested is a display of an existing draft with a decision on its current request. It does not introduce a backend status. Submitted drafts and later requests do not inherit an unrelated earlier feedback state. A new draft based on an agreed revision explains that the earlier agreement applies to the saved baseline, not the new work. Dates come from the request/decision records or working-brief update timestamp, with absolute local date/time text.

Historical snapshots have a banner across all brief tabs, with their revision number and recorded outcome. An older snapshot is labelled Viewing a previous revision; an explicitly opened current saved request/agreement is labelled Viewing a saved revision. Return to current brief removes a direct-link revision parameter so refreshing does not reopen the old view. The history selector distinguishes the current working draft, current agreement request and current agreed brief. Historical views cannot acquire current agreement/proposal actions from the new card.

Proposal navigation checks the existing `lign_prepare_proposal` RPC using a user/project-scoped query and normal refetch interval. It is not inferred from brief-management or requirement-generation flags. Failed access checks fall back to viewing the agreed brief and offer Retry. The underlying proposal route and all server authorization remain authoritative. An assigned responder takes precedence over a management action if a person has both roles.

Review this revision loads the current requested revision locally and opens Gather needs. If a client has unsaved edits when leadership requests agreement, the client must explicitly confirm discarding those edits before this action loads the saved package. Agreement is disabled while local document/area edits or a stale draft remain. This prevents the client from mistaking unsaved content for the saved revision being agreed. Cancelled discard retains their edits. Existing request, response, revision, generation and activation RPCs are unchanged.

Scope: this is the first of the agreed improvements. It does not add the readiness checklist, consolidated review package or a new approval chain. Leadership may still review and request agreement directly from a saved draft. Existing decision controls and requirements tracking remain available. No database migration or email delivery change is needed.

Validation:

- Twelve `agreementStatus.test.ts` cases cover role priority, frozen recipient identity, missing revisions, current-only feedback, historical isolation, agreed baselines and explicit proposal access.
- `tests/access/brief-agreement-status-browser.mjs`: leadership/contributor/client/viewer actions, unsaved-client review safety, feedback, second-revision agreement, historical return/refresh, access-check failure/retry, preserved baseline and desktop/mobile.
- Existing `tests/access/project-brief-browser.mjs`: client contribution, file upload, leadership review, exact agreement, generated/activated requirements and immutable historical views.
- All 92 unit tests, production build, bundle budget and read-only hosted smoke.
