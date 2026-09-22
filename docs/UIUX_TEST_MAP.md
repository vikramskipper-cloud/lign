# UI/UX page-by-page test map

Written 2026-09-22, before the first human pass over the app.

**What this is for.** 37 routes, none of which anyone has clicked. This lists
what each should show against the current fixture data, and — more usefully —
where the risk actually sits. Working through it in order means hitting the
cheap failures before the expensive ones.

**Test account:** `demo@lign.test` / `LignDemo!2026` — workspace admin on WS One
*and* project lead on Project One. No fixture has both, so it is the only
account that can exercise every screen.

---

## 0. Read this first: what compiling does not prove

On 2026-09-22 `useProjectParticipants` was found to have failed on **every call
since APP 005 shipped**. It embedded two foreign keys using hint names that do
not exist, so PostgREST rejected the whole select and @-mentions never
populated. It typechecked and built cleanly throughout, and five final
certifications passed over it.

The lesson for this pass: **a screen that renders is not a screen that works.**
An empty list may be an empty list, or it may be a query erroring into a
fallback. Open the browser console on each page. A silent `PGRST` or `42501`
there is the single highest-value thing this pass can find.

All nine FK hints have since been audited, so that specific class is clean. The
general class is not.

---

## 1. Auth — do these first, everything else depends on them

| Route | Expect | Watch for |
|---|---|---|
| `/signin` | Sign-in form, "Create an account" link | — |
| `/signup` | **Never used by a human.** Creates an account | If email confirmation is on, no session comes back and it redirects to sign-in with a toast. Fake addresses dead-end here. |
| `/invite/:token` | Rewritten 2026-09-22 — was a placeholder that displayed the token and called nothing | Signed out: two buttons. Signed in: "Accept invitation" |

**The full journey** — invite from People → open the link in a private window →
sign up → accept → land in the workspace — is the single most valuable test in
this document. It is what "can this product onboard a second person" means, and
it has never been run end to end.

---

## 2. People & Access — newest code, least exercised

| Route | Expect |
|---|---|
| `/workspace/:ws/people` | 7 members, 1 stakeholder, role dropdowns, Invite button, **and an owner-less banner** |
| `/workspace/:ws/project/:proj/people` | 6 participants, member picker, "Invite external" |
| `/workspace/:ws/settings` | Name + slug, editable and saving |

**Try to break it.** As `demo` (admin, not owner) all three of these must refuse
with a readable message:

- change **your own** role
- remove **yourself**
- set anyone to **owner**

Those are database invariants, verified in SQL but never through the UI. A
silent failure or an unhandled error here matters more than any visual issue on
this list.

The **owner-less banner** is G-7 surfacing: neither workspace has an owner, and
only an owner may grant that role, so it cannot be fixed from the UI. Settings
deliberately ships without owner transfer for that reason. Decide G-7 when you
reach this page.

---

## 3. The core loop

| Route | Fixture reality |
|---|---|
| `/workspace/:ws/projects` | 2 projects |
| `.../project/:proj/overview` | — |
| `.../designs` | **1** asset only |
| `.../asset/:id` | 4 versions, 3 files. Viewer, version bar, right panel |
| `.../asset/:id/v/:vid/file/:fid` | File-level deep link |

The Design Workspace is the densest screen in the app — viewer dispatch,
version menu, right-panel tabs, upload dock, annotations. If anything is
visually rough, it will be rough here first.

---

## 4. Mostly empty — judge the empty states, not the lists

| Route | Rows |
|---|---|
| `.../reviews` (workspace + project) | **0** |
| `.../approvals` | 3 requests, 3 responses |
| `.../requirements` | 3 |
| `.../releases` | **0** |
| `/workspace/:ws/inbox` | **0** notifications |

Roughly half the app is empty-state design right now. That is honest data, not
breakage — but it means this pass is partly reviewing empty states rather than
populated UI. Creating a review and a release early would make several later
screens worth looking at.

---

## 5. Deep links — 9 routes, all unverified

`/deep/{review,reviewer,approval,approver,comment,annotation,requirement,release,notification}/:id`

These resolve an id to a canonical location and redirect. They need real ids
from the fixture data, so they are easy to skip — and equally easy to ship
broken, since nothing else exercises them.

---

## 6. Realtime — needs two windows

Open the same asset as `demo` and `p_lead@lign.test` in separate windows.
Changing something in one should refresh the other within ~250 ms without a
reload, and each should see the other in the presence avatars.

APP 011 is certified as built and unit-tested, **explicitly not as working in a
browser**. This is the test that closes that gap.

---

## 7. Known-unverified, carried from the certifications

- Browser end-to-end for APP 011 (§6 above)
- Reconnect sweep under real network loss — verified against a killed container, not a real drop
- Payload shape for `asset_versions`, `approval_requests`, `approval_responses`
- Every mutation in `features/access/mutations.ts` — the RPCs are tested in SQL, the wrappers are not
- `create_review` has two overloads; a 9-argument call fails with `PGRST203`. The app passes all 15 and is fine, but it is a live trap for new code.

---

## 8. Before starting

The Vercel deployment was still serving a pre-wave-2 bundle at last check. Test
against a build that contains the People screens, or against
`npm run dev` locally — otherwise this pass measures the wrong artefact.
