# APP 046 — Live brief readiness

Review & agree now separates blockers for client agreement, optional improvements and completed checks. Team review remains possible once the saved objective and deliverables are present; unresolved questions, missing commitments or acceptance checks do not block that internal review. Leadership can still request client agreement directly from a ready saved draft.

Client agreement checks saved edits, current version, completed uploads/area edits, at least one requirement or preference, acceptance checks, resolved questions, active responsibility, an accepted approver other than the requester, and the selected-reference package limits. Optional scope boundaries, supporting references and additional context never become agreement requirements. The existing server transitions remain authoritative and unchanged.

Each incomplete item has a direct action that opens the relevant brief tab, clears requirements filters, expands the exact item and focuses its missing field. Leadership manages approver assignment/access; editable participants resolve document issues; viewers receive explanations. A submitted brief offers leadership a return-to-draft action for corrections. Unsaved work requires confirmation before loading a newer server version.

The new read-only `get_project_brief_readiness` RPC checks project access and returns the current automatic responsibility fallback using exactly the transition's ordering: active project leads first, then contributors, ordered by participant ID. It also checks active explicit assignees, approver availability and requester identity, and shared selected-reference count/package size. It returns no private references or reference contents. Anonymous callers cannot execute it. The query is scoped to user/project/respondent/version, refreshes every 30 seconds, and is invalidated by brief and reference mutations. Failed or refreshing context prevents an optimistic agreement action and offers Retry where appropriate; it does not unnecessarily prevent team review.

Awaiting agreement, agreed and historical views display a saved-package summary from the immutable revision rather than recalculating live readiness. Subsequent participant/reference/draft changes do not rewrite that package. Existing decision, revision and requirements activation controls remain available. This release completes the readiness step; a consolidated review of the full brief package is still the next planned improvement. Email delivery is unchanged.

Validation:

- Sixteen readiness unit cases, with 108 unit tests total.
- `tests/access/brief-readiness.mjs`: read-only/access boundaries, active/pending identities, exact automatic assignee, permissive team review, strict agreement, selected-reference count/size limits and actual saved assignment.
- `tests/access/brief-readiness-browser.mjs`: live fixes/focus, filtered items, save, team review, role actions, metadata failure/retry, pending invitation, stale local edits, exact agreement/history and desktop/mobile.
- Existing agreement-status and project-brief browser journeys, production build, bundle budget, schema provenance and read-only hosted smoke.
