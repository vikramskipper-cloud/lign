# FREEZE_INDEX.md

**Canonical architecture index for the Lign platform.**

This document is purely navigational. It records the current frozen state of every APP layer so future APPs can reference contracts without rediscovering them. It introduces no new decisions and reinterprets no existing freeze.

> **Coverage note (2026-09-18).** The detailed per-APP sections below cover
> **APP 001-005 only**. APP 006-010 are also frozen and certified, but their
> contracts were never folded into this file; each has its own freeze index and
> final certification instead (see the APP ownership table). Writing full
> sections for APP 006-010 here is outstanding work. Until then this file is
> **not** a complete index - check `docs/APP_0NN_FREEZE_INDEX.md` and
> `docs/freeze/APP_0NN_FINAL_CERTIFICATION.md` before assuming a contract is
> absent.

---

## APP 001 — Domain Model & Platform Baseline

- **Status:** Frozen. Authoritative document: [`docs/DOMAIN_MODEL.md`](DOMAIN_MODEL.md).
- **Purpose:** Establish the canonical entity vocabulary, cardinalities, lifecycle rules, and polymorphic-target strategy before any DB / UI / API work.
- **Scope owned:** Entity catalog (User, Workspace, WorkspaceMember, Stakeholder, ProjectParticipant, Project, DesignAsset, Version, File, VersionFile, Review, ReviewerAssignment, Comment, Annotation, Change, Decision, ApprovalRequest, ApprovalResponse, Approval, Release, ReleaseItem, ActivityEvent, Invitation, Tag). Roles-as-capability-sets principle. Immutability rules per entity.
- **Backend surfaces owned:** None (design-only; no SQL, no RPCs, no policies emitted at this layer).
- **Frontend surfaces owned:** None.
- **Database objects owned:** None. Defines the model that later schema migrations implement.
- **RPCs owned:** None.
- **Query keys introduced:** None.
- **Routes introduced:** None.
- **Deep-link routes introduced:** None.
- **URL parameters owned:** None.
- **Capability keys consumed:** None. Names the capability tiers (`project.*`, `asset.*`, `version.*`, `review.*`, `comment.*`, `annotation.*`, `change.*`, `decision.*`, `approval.*`, `release.*`, `file.*`, `activity.*`) that later layers implement.
- **Shared UI primitives introduced:** None.
- **Shared reusable components introduced:** None.
- **Design tokens introduced:** None.
- **Extension points intentionally left:** Milestone/Phase; DesignAsset-to-DesignAsset dependency; Templates; Version comparison/diff; Notification; AI Suggestion/Run; Collaborative locks; per-project custom fields.
- **Explicitly deferred work:** Milestone, Dependency, Template, Comparison, Notification, AI, Locks, Custom fields — all deliberately not modeled in v0.
- **Public contracts future APPs must respect:**
  - **8-way** XOR target on `comments` (version, review, annotation, change, decision, design_asset, approval_request, **requirement**). Originally 7-way in APP 005; APP 008 widened `comments_target_xor_check` with `target_requirement_id` as the eighth arm (`APP_008_BACKEND_PROPOSAL.md` §355). The predicate shape (`= 1`) is unchanged. Verified against the live constraint 2026-09-18.
  - Three independent refs on `design_assets` (`current_version_id`, plus reserved approved/released concepts).
  - Version immutability after publish; a correction is a new version.
  - Files are content-addressed with workspace-scoped dedup; never global.
  - Annotation position is immutable; moving a pin = new annotation.
  - `ActivityEvent` is the single append-only history spine — per-entity history tables are not the pattern.
  - Roles are capability sets, not titles; industry vocabulary lives in tags/metadata.
  - Stakeholders are first-class, scoped by `ProjectParticipant` only.

---

## APP 002 — Application Shell

- **Status:** Frozen.
- **Purpose:** Bootstrap the SPA: Vite + React + TypeScript, router, auth session, capability-aware layouts, sign-in, and stub routes for every non-shell surface.
- **Scope owned:** Application shell, router shape, session lifecycle, capability fetching model, responsive drawer behavior, universal error/loading boundaries.
- **Backend surfaces owned:** None net-new. Consumes frozen `lign_has_capability`, `auth.getSession`, `auth.onAuthStateChange`, `auth.signInWithPassword`.
- **Frontend surfaces owned:** `src/main.tsx`, `src/App.tsx`, `src/router.tsx`, `src/env.ts`, `src/lib/{supabase,queryClient,queryKeys,capabilities,formatDate,cn}.ts`, `src/types/capabilities.ts`, `src/styles/globals.css`, `src/auth/`, `src/shell/` (RootLayout, WorkspaceLayout, ProjectLayout, TopBar, NavRail, Breadcrumb, WorkspaceSwitcher, ProjectBreadcrumbSwitcher, UserMenu, NotFound, AccessDenied), `src/routes/` (RootRedirect, WorkspacePicker, stubs).
- **Database objects owned:** None.
- **RPCs owned:** None.
- **Query keys introduced:** `session`, `profile(id)`, `workspaces`, `workspace(id)`, `workspaceMembers(wsId)`, `projects(wsId)`, `project(id)`, `projectCapabilities(projId, wsId)`, `projectParticipants(id)`.
- **Routes introduced:**
  - `/sign-in`
  - `/invite/:token`
  - `/` (RootRedirect)
  - `/workspace-picker`
  - `/workspace/:ws_id/{projects,people,settings}`
  - `/workspace/:ws_id/project/:proj_id/{overview,designs,requirements,asset/:asset_id,asset/:asset_id/v/:v_id,releases,release/:release_id,people}`
  - `*` (NotFound)
- **Deep-link routes introduced:** `/deep/review/:id`, `/deep/approval/:id` (placeholder implementations).
- **URL parameters owned:** `?returnTo=<safe path>` (sign-in bounce).
- **Capability keys consumed:** The full `CAPABILITY_KEYS` client-side array — every frozen capability is primed via `useProjectCapabilities`. Actively gated in APP 002: `project.view` (ProjectLayout entry gate).
- **Shared UI primitives introduced:** `Button`, `Input`, `Label`, `DropdownMenu` family, `Dialog` family, `Tooltip` family, `Avatar`, `Card` family, `Badge`, `Skeleton`, `Separator`, `EmptyState`, `LoadingPage`, `ErrorBoundary`, `AsyncBoundary`, `Guarded`.
- **Shared reusable components introduced:** `SessionProvider`, `AuthGate`, `DeepLinkResolver` (extensible by kind).
- **Design tokens introduced:** `--color-{bg,surface,surface-2,border,border-strong,text,text-muted,text-subtle,brand,brand-fg,brand-hover,success,warning,danger}`, `--radius-{sm,md,lg}`, `--shadow-{sm,md}`, `--font-{sans,mono}`. 4 px base grid; system font stack; universal focus-visible ring.
- **Extension points intentionally left:** Nav mode via `handle.navMode` on route matches; breadcrumb crumb via `handle.crumb`; `DeepLinkResolver` accepts new `kind` values additively; `qk` registry is append-only.
- **Explicitly deferred work:** RHF + Zod adoption; global UI store; password reset / social auth / email OTP; notifications bell activation; drag-to-resize right panel.
- **Public contracts future APPs must respect:**
  - Router tree shape (all authenticated routes live under `Gated` → `RootLayout`).
  - Nav-mode and crumb pattern (`handle.navMode`, `handle.crumb`).
  - `localStorage` key `lign.lastWorkspaceId`; Supabase session storage key `lign.session`.
  - Sign-in returnTo regex `^\/[^/].*$` (only absolute-path, non-double-slash).
  - React Query defaults: `staleTime = 30_000`, `gcTime = 300_000`, retry skips auth errors.
  - Every capability the app checks MUST appear in `CAPABILITY_KEYS`.

---

## APP 003 — Project & Design Workspace

- **Status:** Frozen (re-freeze applied 2026-08-07 for Discipline addition).
- **Purpose:** Real screens for Projects, Collections, Disciplines, DesignAssets, and the Design Workspace shell (viewer chrome + right panel).
- **Scope owned:** Project list/overview/create/edit/archive; Collections (sidebar, dialogs, archive); Disciplines (filter, manager, combobox, chip); Designs screen (asset grid + filters + search); Design Workspace shell (`VersionBar`, `VersionMenu`, `ViewerPlaceholder` [replaced by APP 004], `RightPanel` with Details/Versions tabs); asset-to-asset navigation; empty states for all above.
- **Backend surfaces owned:**
  - Migration 010 (`app_003_disciplines`): new `public.disciplines` table + `public.design_assets.discipline_id` nullable column + RLS policies. **Re-freeze of Schema V1 lock (approved).**
- **Frontend surfaces owned:** `src/features/{projects,collections,disciplines,designs,design-workspace,shared}/` (all initial files), `src/lib/queryKeys.ts` extended, `src/shell/queries.ts` widened.
- **Database objects owned:**
  - Table `public.disciplines` (project-scoped, `status active|archived`, composite unique target for design_assets).
  - Column `public.design_assets.discipline_id` (nullable, composite FK ON DELETE RESTRICT).
  - Indexes: `disciplines_project_name_active_key` (partial), `disciplines_project_sort_idx`, `design_assets_discipline_idx` (partial).
  - RLS policies: `disciplines_{select,insert,update}` gated on `project.view` / `project.edit`.
- **RPCs owned:** None (reads via SELECT; writes via direct RLS INSERT/UPDATE; consumes frozen `create_project`, `set_current_version`).
- **Query keys introduced:** `collections(projId)`, `collection(id)`, `disciplines(projId)`, `discipline(id)`, `assets(projId, filters)`, `asset(id)`, `assetVersions(assetId)`, `assetVersion(id)`, `assetNeighbors(assetId, scope)`. Types `AssetFilters`, `AssetNeighborScope` exported from `qk`.
- **Routes introduced:** None net-new (replaces APP 002 stubs).
- **Deep-link routes introduced:** None.
- **URL parameters owned:** `?from=collection:<id>|unfiled`, `?discipline=<id>`, `?tab=details|versions` (Design Workspace right panel).
- **Capability keys consumed:** `project.view`, `project.edit`, `project.archive`, `collection.view`, `collection.create`, `collection.edit`, `collection.archive`, `asset.view`, `asset.create`, `asset.edit`, `asset.archive`, `asset.set_current`, `version.view`.
- **Shared UI primitives introduced:** `Tabs` (Radix wrapper), `FormRow` (label + control + hint/error).
- **Shared reusable components introduced:** `StatusBadge` (lifecycle statuses), `DisciplineChip`, `DisciplineCombobox`, `DisciplineManagerPopover`, `DisciplineFilter`, `CollectionSidebar`, `CollectionDialog`, `useCapability`/`useProjectCapabilities` consumption pattern.
- **Design tokens introduced:** None (reuses APP 002 palette).
- **Extension points intentionally left:** `AssetCard` reserved 24×24 favorite slot (fav grid area) for future Favorites slice. Right-panel tab strip designed to accept new tabs (`Files`, `Comments`, etc.). `useAssetNeighbors` scope object accepts additional axes.
- **Explicitly deferred work:** Version creation/upload/publish/discard (APP 004); files/thumbnails (APP 004); comments/annotations (APP 005); reviews (APP 006); approvals (APP 007); releases (APP 009); requirements UI; people management; activity feed; realtime; bulk actions; collection reordering; discipline archive-count guard; favorites.
- **Public contracts future APPs must respect:**
  - `AssetCard` favorite slot must not shrink or disappear.
  - `AssetFilters` shape (`{collection, discipline, search}`) — additions must be additive to the object.
  - Collection archive `SET NULL`s asset `collection_id` (schema-enforced).
  - Discipline archive is RESTRICT on delete — never orphan assets.
  - `?from=` and `?discipline=` params survive through neighbor navigation.
  - Right-panel tabs are addressable via `?tab=<name>`; unknown values fall back to `details`.

---

## APP 004 — File Management & Viewer

- **Status:** Frozen (Migration 011 applied for RLS additions).
- **Purpose:** Multi-file version bundles: upload, hash, finalize, publish, discard, viewer dispatch, signed URLs, per-file metadata edits, and grid thumbnails.
- **Scope owned:** Upload state machine (queued → hashing → reserving → uploading → finalizing → done); draft version lifecycle UI; viewer dispatcher for image/PDF/video/audio/text/download-only; file switcher on multi-file versions; grid thumbnails; per-file role/rename/reorder/detach in draft; signed-URL cache; deep-link `/file/:file_id`.
- **Backend surfaces owned:**
  - Migration 011 (`app_004_version_files_write_rls`): `version_files_update` and `version_files_delete` RLS policies gated on `version.upload`. **Layered with pre-existing draft-only trigger.**
- **Frontend surfaces owned:** `src/features/files/` (mime, MimePlaceholder, queries, useSignedUrl, useHashFile, useUploadQueue, UploadDock, Viewer + six sub-viewers, FileSwitcher, FilesPanel, AssetCardThumb, workers/hasher.worker.ts); `src/features/design-workspace/{PublishDraftButton,DiscardDraftButton}.tsx`; extended `VersionMenu`, `VersionBar`, `RightPanel`, `DesignWorkspaceScreen`, `AssetCard`, router.
- **Database objects owned:** No new tables/columns. Two RLS policies added to `version_files`.
- **RPCs owned:** None net-new. Consumes frozen `create_draft_version`, `start_version_file_upload`, `finalize_version_file_upload`, `publish_version`, `discard_draft_version`, `set_current_version`, and Storage API `.upload()` / `.createSignedUrl()`.
- **Query keys introduced:** `versionFiles(versionId)`, `file(fileId)`, `signedUrl(fileId, purpose='view'|'thumb')`.
- **Routes introduced:** `/workspace/:ws_id/project/:proj_id/asset/:asset_id/v/:v_id/file/:file_id`.
- **Deep-link routes introduced:** None (uses existing scheme; the `/file/:file_id` segment is part of the workspace URL).
- **URL parameters owned:** `?tab=files` extension of the tab param.
- **Capability keys consumed:** `version.upload`, `version.publish`, `version.discard_draft`, `file.attach`, `file.download`.
- **Shared UI primitives introduced:** None.
- **Shared reusable components introduced:** `MimePlaceholder`, `useSignedUrl`, `useHashFile` (singleton Web Worker client), `useUploadQueue`, `FileSwitcher`, `FilesPanel`, `AssetCardThumb`, `Viewer` dispatcher pattern with render-slot props (image overlay, video below-strip).
- **Design tokens introduced:** None (reuses APP 002).
- **Extension points intentionally left:**
  - `ImageViewer.overlay` prop + `VideoViewer.belowStrip` render prop — hosts APP 005 annotations.
  - `Viewer` dispatcher forwards `imageOverlay` / `videoBelowStrip` without inspecting them.
  - `RightPanel` tab strip designed to insert additional tabs.
  - `useSignedUrl.purpose` accepts additional purposes; TTLs configurable per purpose.
- **Explicitly deferred work:** Server-side thumbnails, PDF/CAD/BIM renderers, file replace (=new draft), bulk file actions, workspace-quota UI, sweep/purge operator UI, cross-session realtime file progress, file-download audit beyond frozen events, version compare.
- **Public contracts future APPs must respect:**
  - `role='primary'` attachment drives thumbnails and default viewer file.
  - Annotations must anchor to `(asset_version_id, version_file_id)` — file, not version.
  - Signed URLs are transient; never persisted; refresh 30 s before expiry.
  - Draft-only mutations on `version_files` (schema-trigger enforced).
  - Viewer render slots are the sole insertion point for viewer overlays.
  - `ViewerPlaceholder` no longer exists; new viewers plug in through the dispatcher.

---

## APP 005 — Comments & Annotations (Collaboration Layer)

- **Status:** Frozen.
- **Purpose:** Version-scoped comment threads, annotation threads (point/region/time), plain-text `@`-mentions, right-panel Comments tab, viewer overlays, workspace hotkeys, deep-link and copy-link contracts.
- **Scope owned:** Comment CRUD via RLS + `edit_own_comment` RPC; thread rendering; root-level resolve; annotation CRUD via RLS; overlay + tool on image viewer; time strip on video viewer; mention parsing at render; workflow-state (`Open`/`Resolved`) visualization; Comments tab in right panel; C/P/Esc hotkeys.
- **Backend surfaces owned:** None. Zero migrations, zero RPCs, zero policies, zero triggers, zero capabilities, zero events introduced.
- **Frontend surfaces owned:** `src/features/comments/` (10 files), `src/features/annotations/` (8 files), `src/features/participants/queries.ts`, `src/features/shared/StateBadge.tsx`, `src/features/design-workspace/useWorkspaceHotkeys.ts`; extended `RightPanel`, `DesignWorkspaceScreen`, `ImageViewer`, `VideoViewer`, `Viewer`, `DeepLinkResolver`, `router`, `globals.css`, `queryKeys`, `invalidate`.
- **Database objects owned:** None.
- **RPCs owned:** None (consumes frozen `edit_own_comment`).
- **Query keys introduced:** `commentsForVersion(versionId)`, `commentsForAnnotation(annotationId)`, `comment(id)`, `commentEdits(id)`, `annotationsForVersion(versionId)`, `annotation(id)`. Reuses APP 002's `projectParticipants(id)`.
- **Routes introduced:** None.
- **Deep-link routes introduced:** `/deep/comment/:id`, `/deep/annotation/:id`.
- **URL parameters owned:** `?tab=comments`, `?comment=<comment_id>`, `?annotation=<annotation_id>`, `?comments=unresolved|mine|mentions`.
- **Capability keys consumed:** `comment.view`, `comment.create`, `comment.edit_own`, `comment.resolve`, `annotation.view`, `annotation.create`, `annotation.resolve`.
- **Shared UI primitives introduced:** None.
- **Shared reusable components introduced:** `StateBadge` (workflow-state pill), `useCopyLink` (`/deep/<kind>/:id` clipboard helper), `useProjectParticipants`, `useWorkspaceHotkeys`, `parseMentions` (pure), `useAnnotationNumbering` provider (opaque interface).
- **Design tokens introduced:** `--color-state-open`, `--color-state-open-bg`, `--color-state-resolved`, `--color-state-resolved-bg`. Placeholders reserved (as CSS comments only) for `--color-state-in-progress`, `--color-state-blocked`, `--color-state-superseded`.
- **Extension points intentionally left:**
  - `StateBadge` accepts new `WorkflowState` members (`in-progress`, `blocked`, `superseded`).
  - `useCopyLink` `LinkKind` accepts new kinds (`review`, `approval`, etc.).
  - `useWorkspaceHotkeys` accepts additional handlers (R for review, A for approval, etc.).
  - `DeepLinkResolver` accepts more `kind` values additively.
  - `useAnnotationNumbering` is a swap-in point for a future persistent `annotations.sequence` column.
- **Explicitly deferred work:** Asset-level comments; delete-own comment; PDF/3D/CAD annotations; server-side thumbnails on comments; mention persistence + notification emission; realtime co-authoring; presence; version comparison of comments; comment reactions; markdown/rich text.
- **Public contracts future APPs must respect:**
  - `comments.body` is plain text; no hidden markers.
  - Annotation position is immutable; annotations are anchored to `(asset_version_id, version_file_id)`.
  - Root `resolved_at` is the sole thread-state truth.
  - Annotations are strictly scoped to their origin version + file — never bleed forward.
  - Generic `--color-state-*` tokens are the shared workflow palette; no module may add module-specific state colors.
  - Copy-link URLs are `/deep/<kind>/:id`; new kinds extend, never replace.
  - `useAnnotationNumbering` is the ONLY numbering source; consumers never read `created_at` for numbers.

---

# Dependency Graph

```
APP 001  (Domain Model & Platform Baseline)
   │
   ▼
APP 002  (Application Shell)
   │
   ▼
APP 003  (Project & Design Workspace)
   │
   ▼
APP 004  (File Management & Viewer)
   │
   ▼
APP 005  (Comments & Annotations)
```

**Dependency notes:**

- **APP 002 → APP 001.** Depends on the entity vocabulary and capability tiers named by APP 001. Implements no domain entities directly; consumes `lign_has_capability`, workspace/profile identity, and the `CAPABILITY_KEYS` catalog derived from APP 001's role-map.
- **APP 003 → APP 002.** Slots screens into APP 002's router (`RootLayout` → `WorkspaceLayout` → `ProjectLayout`), reuses every UI primitive, extends `qk` append-only, respects the responsive shell.
- **APP 003 → APP 001.** Implements Project, Collection, DesignAsset, AssetVersion (read-only) — the APP 001 entities in that tier. Also introduces the Discipline concept via an approved schema-lock re-freeze (Migration 010).
- **APP 004 → APP 003.** Extends the Design Workspace shell (VersionBar, VersionMenu, RightPanel) with additive props; swaps `ViewerPlaceholder` for the real `Viewer` dispatcher; replaces `AssetCard`'s dashed placeholder with `AssetCardThumb`. All APP 003 screens outside the workspace are untouched.
- **APP 004 → STORAGE 001–004 (frozen backend).** Consumes the entire storage RPC surface (`create_draft_version`, `start_version_file_upload`, `finalize_version_file_upload`, `publish_version`, `discard_draft_version`) plus Supabase Storage `.upload()` / `.createSignedUrl()`. Adds Migration 011 (`version_files` write RLS) — policies only, not a structural change.
- **APP 005 → APP 004.** Depends on `ImageViewer.overlay` and `VideoViewer.belowStrip` render slots for annotation surfaces; on `Viewer` forwarding those props; on `RightPanel`'s extensible tab strip; on `AssetCardThumb` being unchanged.
- **APP 005 → APP 003.** Uses the DesignWorkspaceScreen as the mount point for hotkeys and authoring state.
- **APP 005 → APP 002.** Extends `DeepLinkResolver` additively with `comment` / `annotation` kinds; extends `router` with two new `/deep/*` entries.
- **APP 005 → APP 001.** Implements the Comment XOR target discipline (7-way as shipped by APP 005; widened to 8-way by APP 008) (using only the `version` and `annotation` targets in this slice), the annotation immutability rule, and the Notification-through-events principle (by deliberately emitting nothing).

---

# Cross-cutting Contracts

For each concern, the APP (or backend layer) that owns the canonical contract.

| Concern | Canonical owner | Notes |
|---|---|---|
| **Authentication** | APP 002 | `SessionProvider`, `AuthGate`, Supabase session lifecycle. Storage key `lign.session`. |
| **Authorization** | AUTH 001–009 (backend, prerequisite) + APP 002 | RLS policies + `lign_has_capability`. UI never trusted; every RPC re-enforces. |
| **Capabilities** | AUTH 001 (backend) + APP 002 (`CAPABILITY_KEYS` client array) | Roles-as-capability-sets per APP 001; capability keys are the sole authorization vocabulary. |
| **Application Shell** | APP 002 | RootLayout, TopBar, NavRail, Breadcrumb, responsive drawer, error/async boundaries. |
| **Routing** | APP 002 | `createBrowserRouter` tree; `handle.navMode` / `handle.crumb` conventions. |
| **Deep Links** | APP 002 (mechanism) · APP 005 (comment/annotation kinds) | `DeepLinkResolver` extensible by kind. |
| **Workspace** | APP 002 | `WorkspaceLayout`, workspace switcher, `lign.lastWorkspaceId`. |
| **Projects** | APP 003 | List, overview, create (`create_project` RPC), edit, archive. |
| **Collections** | APP 003 | Sidebar filter + inline management. Frozen schema table (Migration 003). |
| **Disciplines** | APP 003 | Filter + manager popover + combobox. Migration 010 schema. |
| **Assets** | APP 003 | Grid, dialogs, `AssetFilters`, neighbors navigation. |
| **Versions** | APP 003 (read) · APP 004 (write) | `useAssetVersions` in APP 003; draft/publish/discard in APP 004. |
| **Files** | APP 004 | `version_files` reads; upload state machine; signed URLs; grid thumbnails. |
| **Storage Lifecycle** | STORAGE 001–004 (backend) | Bucket `lign-files`, upload/finalize/publish/discard/sweep/purge. APP 004 consumes; owns no lifecycle logic. |
| **Viewer** | APP 004 | `Viewer` dispatcher + six sub-viewers + render-slot props for overlays. |
| **Comments** | APP 005 | Composer, thread cards, resolve, edit-own, filter bar, right-panel tab. |
| **Annotations** | APP 005 | Overlay layer, tool pill, time strip, numbering provider, generic color contract. |
| **Mentions** | APP 005 (display) — **not persisted** | `parseMentions` client-side; body stored plain. Notification emission deferred. |
| **Design Tokens** | APP 002 (base) · APP 005 (state palette) | `--color-*`, `--radius-*`, `--shadow-*`, `--font-*` in APP 002; `--color-state-*` in APP 005. No module-specific tokens. |
| **Shared Components** | APP 002 (primitives) · APP 003 (`StatusBadge`, `FormRow`, `Tabs`) · APP 004 (`MimePlaceholder`, `useSignedUrl`, `useHashFile`) · APP 005 (`StateBadge`, `useCopyLink`, `useWorkspaceHotkeys`, `useProjectParticipants`, `useAnnotationNumbering`) | Every reusable primitive belongs to exactly one APP and is additive across layers. |
| **Query Architecture** | APP 002 (`qk` registry + defaults) | Each APP appends keys; never renames. `staleTime 30s`, `gcTime 300s`, auth-error-aware retry. |
| **Cache Invalidation** | APP 002 (pattern) · APP 003+ (predicate helpers in `src/features/shared/invalidate.ts`) | Predicate invalidation for filter-variant caches; single-key for others. |
| **Error Handling** | APP 002 (`ErrorBoundary`, `AsyncBoundary`) · APP 003 (`humanizeError`) | Per-mutation toasts via sonner; boundaries scoped to viewer/right panel where needed. |
| **Responsive Layout** | APP 002 | Breakpoints 768 / 1024; drawer/collapsed/full behavior for NavRail. |
| **Accessibility** | APP 002 (baseline focus ring, keyboard-nav primitives) · APP 005 (workspace hotkeys with typing-target guard) | Radix primitives own their focus traps; APP 005 keydown listener skips inputs/textareas/contenteditable. |

---

# APP Ownership

Status verified against the live database and `docs/freeze/` on **2026-09-18**.

| APP | Concern | Status | Authoritative document |
|---|---|---|---|
| **APP 001 — Domain Model** | Entity vocabulary, cardinalities, lifecycle rules | **Frozen** | `DOMAIN_MODEL.md` + §APP 001 below |
| **APP 002 — Application Shell** | Router, session, layouts, capability fetching | **Frozen** | §APP 002 below |
| **APP 003 — Projects & Design Workspace** | Projects, collections, disciplines, assets, workspace shell | **Frozen** (re-freeze 2026-08-07 for Discipline) | §APP 003 below |
| **APP 004 — Files & Viewer** | Upload state machine, viewer dispatch, signed URLs, thumbnails | **Frozen** | §APP 004 below |
| **APP 005 — Comments & Annotations** | Threads, resolve, annotation overlay, mentions (display only) | **Frozen** | §APP 005 below |
| **APP 006 — Reviews** | Review request/response/complete workflow, reviewer roster, review panel | **Frozen** | `APP_006_FREEZE_INDEX.md` · `freeze/APP_006_FINAL_CERTIFICATION.md` |
| **APP 007 — Approvals** | Approval request, response, aggregate outcome; approver picker | **Frozen** | `APP_007_FREEZE_INDEX.md` · `freeze/APP_007_FINAL_CERTIFICATION.md` |
| **APP 008 — Requirements** | Requirements list, applicability, assessments UI | **Frozen** | `APP_008_FREEZE_INDEX.md` · `freeze/APP_008_FINAL_CERTIFICATION.md` |
| **APP 009 — Releases** | Release bundles, detail, item selection, publish/withdraw UI | **Frozen** | `APP_009_FREEZE_INDEX.md` · `freeze/APP_009_FINAL_CERTIFICATION.md` |
| **APP 010 — Notifications** | Router trigger on `activity_events`, `notifications` table, inbox, bell | **Frozen** | `APP_010_FREEZE_INDEX.md` · `freeze/APP_010_FINAL_CERTIFICATION.md` |
| **APP 011 — Realtime** | Live cache invalidation via Supabase channels; presence signals | **Frozen** 2026-09-18 (behavioural sign-off deferred to UI/UX testing) | `APP_011_FREEZE_INDEX.md` · `freeze/APP_011_FINAL_CERTIFICATION.md` |
| **APP 012 — Production Hardening** | CI gates, bundle splitting, DB hardening, ops/scheduling, environment separation | **Freeze Index drafted** 2026-09-18, awaiting approval | `APP_012_FREEZE_INDEX.md` |
| **APP 013 — People & Access** | Invitations, workspace members, stakeholders, project participants, roles | **Freeze Index drafted** 2026-09-20, awaiting approval | `APP_013_FREEZE_INDEX.md` |

Backend layers, same date: **AUTH 001-009** frozen; **STORAGE 001-004** frozen;
**REQUIREMENTS 001-005** frozen; **REALTIME 002 + 003** applied
(`realtime_002_publication_scope` added 8 tables to the `supabase_realtime`
publication - `comments`, `annotations`, `asset_versions`, `reviews`,
`review_participants`, `approval_requests`, `approval_responses`,
`design_assets`; `realtime_003_notifications_publication` added `notifications`
as a 9th under APP 011 wave 1B). APP 011 shipped the client-side subscription on
2026-09-18.

Each future APP must consult this index and the referenced freeze reports before adding architecture. New RPCs, capabilities, events, or tables require an explicit re-freeze note in the affected owner's section.

## Known index gaps

- No §APP 006-010 sections in this file (see coverage note at the top).
- The **Mentions** row in Cross-cutting Contracts says notification emission is
  deferred. That is still true: `comment.mentioned` is consumed by the APP 010
  router but emitted by nothing, so mention notifications never fire. The APP
  010 certification reads as though the path is live; it is not.
- ~~`supabase/migrations/` is not a faithful replay of the deployed database.~~
  **Resolved 2026-09-18.** All 67 files are now byte-identical to the applied
  statements and rule 20 is enforced by `ops/verify_migrations.sh`. See
  `supabase/migrations/RECONCILIATION.md` §3 and
  `docs/freeze/MIGRATION_ARTIFACT_AMENDMENT.md`.

---

# Freeze Rule

Any future APP may **extend** these contracts but must **not modify or reinterpret** a frozen contract without an explicit re-freeze.

Extension is additive: new query keys, new capability keys, new tabs, new deep-link kinds, new state tokens, new hotkeys, new URL params, new tables via a re-freeze migration. Modification is any change to an existing signature, name, semantic, or invariant — those require the current owner APP to reopen its freeze report with an amendment and re-issue the freeze.

This document is purely navigational. It does not redesign, reinterpret, or implement anything.
