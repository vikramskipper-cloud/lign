# LIGN — Storage Architecture (STORAGE 001)

**Status:** frozen 2026-07-30.
**Target:** Supabase Storage on project `hsfporioghapwghrvvzd`.
**Depends on:** frozen structural schema V1 (`docs/DATABASE_SCHEMA.md`), frozen authorization AUTH 001–009 (`docs/AUTHORIZATION_ARCHITECTURE.md`, `docs/PERMISSIONS.md`), frozen `docs/STATE_MACHINES.md` and `docs/EVENT_MODEL.md`.

This document is the single source of truth for how LIGN stores binary content. It is not code and does not stand up any Storage state. STORAGE 002–004 apply it.

---

## 1. Core model

The domain and physical storage remain distinct records that must never be collapsed:

```
DesignAsset  (identity of the design "thing")
    └── AssetVersion  (immutable-after-publish iteration)
            └── VersionFile  (an attachment of a File to a Version)
                    └── File  (workspace-scoped identity + metadata for a binary)
                            └── Supabase Storage object  (the physical bytes)
```

- **`files`** is the database identity/metadata layer. It carries checksum, size, MIME, workspace scope, upload attribution, and lifecycle status. It is content-addressed within a workspace.
- **The Storage object** is the physical binary at a server-derived path.
- **`version_files`** is the many-to-many link between an `asset_version` and a `file`. It records display name, role, and sort order per attachment.

No layer is ever bypassed. The Storage object exists only for a `files` row; a `version_files` row exists only for a finalized (`active`) `files` row.

---

## 2. Bucket model

**One private Supabase Storage bucket:** `lign-files`.

- Private (no public/anonymous access).
- Per-object maximum size: **500 MB**.
- No public bucket for MVP.
- No CDN, no cross-region replication, no lifecycle tiering (see §19).

Rationale for one bucket: LIGN has no public-share flow in MVP; tenant scoping is enforced by object path and by RLS policies that join to `public.files`. Splitting buckets would add operational surface with no security or performance dividend.

---

## 3. Canonical object path

```
{workspace_id}/{file_id}
```

- Two UUIDv4 values, both server-derived.
- No filename, no extension, no `project_id`, no asset/version identifier, no slug, no user-visible name.
- The `files.storage_ref` column stores exactly this string.
- Server generates `storage_ref` at `start_version_file_upload` time. **The client may never supply `storage_ref` and may never choose the path.**
- Display filename (with extension) is stored only in `version_files.display_name` and served to the browser via `Content-Disposition` at download.

Rationale:
- **Tenant unambiguous** — first segment is the workspace UUID.
- **Immutable** — `files.id` is a UUIDv4, unguessable.
- **Rename-safe** — no project or asset name appears; renaming any of them never invalidates a path or an authorization decision.
- **RLS-friendly** — `storage.objects.name` joins directly to `public.files.storage_ref`; no path parsing.
- **No collisions** — UUID leaf. Binary dedup happens in the `files` layer, not by path.
- **Not project-scoped** — a `files` row is workspace-scoped (per checksum dedup); it may be attached from multiple projects via `version_files`. Baking `project_id` into the path would become a lie the moment a second project attaches the same file.

---

## 4. File lifecycle

`files.status` reuses the frozen enum `('uploaded','active','orphaned','purged')` from `DATABASE_SCHEMA.md §3.11` with the semantic reading below (this reading is a documentation reconciliation, not a schema change):

| Status | Meaning |
|---|---|
| `uploaded` | An upload reservation exists: the row was created by `start_version_file_upload`, `storage_ref` has been allocated, the Storage object may or may not yet be present at that path, and no `version_files` attachment exists for this file yet. |
| `active` | `finalize_version_file_upload` has succeeded: the Storage object is confirmed present, and this file is referenced by at least one `version_files` row. |
| `orphaned` | The last `version_files` row referencing this file has been removed; `orphaned_at` is set; the physical Storage object still exists during the retention window. |
| `purged` | Retention has elapsed and the physical Storage object has been deleted (controlled service-role operation). The row is retained permanently for audit; `purged_at` is set. |

Permitted transitions (**terminal:** `purged`):

```
∅         → uploaded    (start_version_file_upload; only when no dedup match)
uploaded  → active      (finalize_version_file_upload succeeds)
uploaded  → orphaned    (stale-upload sweep after TTL; or finalize failure)
active    → orphaned    (last version_files reference deleted; discard_draft_version)
orphaned  → active      (reclaim via dedup while retention has not elapsed; object still present)
orphaned  → purged      (STORAGE 004: eligibility → controlled Storage delete → mark_purged)
```

Constants:
- **Stale-upload TTL** (uploaded → orphaned sweep): **24 hours**.
- **Orphan retention** (orphaned → purged): **30 days**.

Invariants:
- A file is **never** orphaned or purged while any `version_files` row references it.
- The physical Storage object is **never** deleted while the row is not in `purged`.
- The row is **never** deleted, in any status.

---

## 5. Upload workflow

Two-step, server-controlled. `version_files` is created only after physical upload success.

```
Client                                          Server (Postgres RPC)               Supabase Storage
------                                          ---------------------               ----------------
compute SHA-256 →
  start_version_file_upload(...)         ────►  authorize, resolve wsid/pid
                                                dedup dispatch on (wsid, checksum)
                                       ◄────    return {file_id, action, [path]}
if action = upload_required or reclaimed:
  .upload(bucket:'lign-files',
          path:'{wsid}/{file_id}')       ─────────────────────────────────────►      insert object (INSERT RLS)
  finalize_version_file_upload(...)      ────►  re-authorize, re-check draft,
                                                verify object exists,
                                                verify metadata size matches,
                                                files.status → active,
                                                insert version_files
                                       ◄────    return {file_id, version_files.id}
```

### 5.1 `start_version_file_upload(asset_version_id, checksum_hex, mime_type, size_bytes, display_name, role, sort_order) → { file_id, action, bucket?, object_path?, max_bytes?, retry_after_ms? }`

1. Authenticate the caller.
2. Resolve `project_id` and `workspace_id` **from the `asset_version` row** — never from client-supplied context.
3. Verify the parent `asset_version.status = 'draft'`.
4. Verify the caller has both `version.upload` and `file.attach` on the resolved project (via `lign_has_capability`).
5. Validate `mime_type` against the small denylist (§16). Validate `size_bytes ≤ 500 * 1024 * 1024`. Validate `checksum_hex` is 64 hex chars.
6. **Race-safe dedup dispatch** (see §7 for full status matrix): attempt an `INSERT ... ON CONFLICT (workspace_id, checksum_sha256) WHERE status <> 'purged' DO NOTHING RETURNING id`, then read the definitive existing row and dispatch by its `status`.
7. Compute `storage_ref = '{workspace_id}/{file_id}'` **server-side** for new rows.
8. Do not create a `version_files` row yet.
9. Return the dispatch result:
   - `active` match → `{ file_id, action: 'reused' }`. No physical upload.
   - `uploaded` match → `{ file_id, action: 'in_progress', retry_after_ms }`. Client retries.
   - `orphaned` match reclaimed → `{ file_id, action: 'reclaimed' }`. Client calls `finalize_` (object likely present).
   - `purged` match → per §7: not blocked; the partial unique index permits a new row (see §7 amendment).
   - New row → `{ file_id, action: 'upload_required', bucket: 'lign-files', object_path: '{workspace_id}/{file_id}', max_bytes: 500000000 }`.

### 5.2 Direct authenticated Storage upload

Client uploads the binary to `bucket='lign-files'`, `name='{workspace_id}/{file_id}'` using the standard Supabase Storage client with the user's JWT. `storage.objects` INSERT RLS (§10) allows only this exact path for this authenticated caller with a matching `files` row in status `uploaded` and `uploaded_by_profile_id = auth.uid()`.

### 5.3 `finalize_version_file_upload(file_id, asset_version_id) → { file_id, version_files_id }`

1. Re-authenticate.
2. Lock the `files` row `FOR UPDATE`.
3. Re-verify caller has `version.upload` + `file.attach` on the target project.
4. Re-verify the target `asset_version.status = 'draft'`.
5. Verify a `storage.objects` row exists at the reserved path.
6. Verify `storage.objects.metadata.size` matches the declared `size_bytes`. On mismatch: abort, mark the file `orphaned` for later purge (see §11).
7. **No claim of cryptographic byte verification.** Server does not recompute SHA-256 from the stored bytes; §6 clarifies this boundary.
8. Transition `files.status` `uploaded → active` if not already `active`.
9. Insert the `version_files` row (composite FKs enforce workspace / asset-version consistency; existing parent-draft trigger reasserts version is draft).
10. **Idempotent**: if `files.status` is already `active` and a `version_files` row already exists for `(asset_version_id, file_id)`, return success.

### 5.4 Invariant

> Every `version_files` row references a `files` row with `status = 'active'`.

Enforced by construction (finalize is the only path to create `version_files`) and reasserted defensively by `publish_version` (§12).

---

## 6. Checksum semantics

- **SHA-256 is required.**
- **Client computes it** before calling `start_version_file_upload`, and again after upload for `finalize_version_file_upload`.
- The database uses `files.checksum_sha256` for workspace-scoped deduplication (§7) and records it for audit.
- PostgreSQL **cannot independently recompute SHA-256 from bytes in Supabase Storage.** No RPC in MVP claims to. `finalize_` verifies only:
  - the Storage object exists at the reserved path;
  - available `storage.objects.metadata.size` matches the pre-declared `size_bytes`.
- True server-side binary checksum verification is a later hardening option and would require a service-role backend (Edge Function or worker). Explicitly out of scope for MVP.

The threat model this creates: a malicious client could declare a checksum that does not match the bytes it uploaded, causing an incorrect dedup key. Impact is contained: the incorrect checksum only affects re-uploads of the *same claimed hash* within the same workspace, and the incorrect bytes are still only accessible to the same workspace's authorized readers. Documented and accepted for MVP.

---

## 7. Deduplication

**Never dedup across workspaces.** Tenant isolation is stricter than storage efficiency.

Within one workspace, dedup is by `(workspace_id, checksum_sha256)`:

| Existing `files.status` | Behavior | Physical upload? | `version_files` created? |
|---|---|---|---|
| `active` | Reuse existing `file_id`. `finalize_` idempotently creates the `version_files` attachment. | No | Yes, in `finalize_` |
| `uploaded` (concurrent) | Return `action='in_progress'` with `retry_after_ms`. Client retries. Eventually the in-flight upload either finalizes (→ `active`; retry reuses) or is swept stale after 24h (→ `orphaned`; retry reclaims). | No (blocked pending resolution) | No |
| `orphaned` within 30-day retention (object still present) | **Reclaim**: set `status='uploaded'`, clear `orphaned_at`, update `uploaded_by_profile_id = auth.uid()`. Client calls `finalize_`; if the object is still present, promote to `active` without a new upload. If a rare gap has already occurred, client uploads to the same reserved path. | No (usually) / Yes (rare) | Yes, in `finalize_` |
| `purged` | The historical purged row is left untouched (audit). A **new `files` row with a new `id`** is created for the same `(workspace_id, checksum_sha256)`, allocating a new `storage_ref` and a new physical object. | Yes (fresh) | Yes, in `finalize_` |

### 7.1 Approved narrow amendment to V1 (deferred to STORAGE 003)

To permit the `purged → new File identity` behavior, `files_workspace_checksum_key` must be replaced with a **partial unique index** that excludes purged rows. This is the only structural change to V1 introduced by the storage stack.

**Amendment specification (documented here; applied in STORAGE 003):**

- Drop: `constraint files_workspace_checksum_key UNIQUE (workspace_id, checksum_sha256)`.
- Add: `create unique index files_workspace_checksum_key on public.files (workspace_id, checksum_sha256) where status <> 'purged';`
- Same identifier reused for the index → error messages and downstream references stay stable.
- `start_version_file_upload`'s ON CONFLICT clause must match the partial predicate exactly: `on conflict (workspace_id, checksum_sha256) where status <> 'purged' do nothing`.
- Must be applied as a single atomic migration (`DROP` + `CREATE UNIQUE INDEX` in one transaction) to close any TOCTOU window during deploy.
- Zero rows in `status='purged'` today, so no back-population is required.

This is a formally documented, explicitly approved amendment. It does **not** re-open the V1 lock beyond this single, storage-necessary change.

---

## 8. Immutability

- Storage objects are **immutable**. There is no code path — RLS, RPC, or otherwise — through which an authenticated client can overwrite an existing object.
- `storage.objects` has no UPDATE policy for `authenticated` (§10). No UPDATE is possible.
- A new binary always yields a new File identity and a new Storage object, **unless** an active workspace-scoped checksum match exists, in which case the existing File and object are reused via `version_files`.
- Historical published versions are byte-for-byte reproducible: `files.storage_ref` is stable, `checksum_sha256` is recorded at reservation, and no code path mutates the object.

This aligns with the V1 lock invariant "asset_versions content immutability after publish."

---

## 9. Download authorization

**Direct authenticated Supabase Storage downloads for MVP.** No public URLs. No signed URLs.

The client calls `supabase.storage.from('lign-files').download('{workspace_id}/{file_id}')` with the user's JWT. Every request is re-authorized against **current** authorization; a revoked participant or removed stakeholder loses download access on the next request.

Authorization mirrors the frozen `AUTHORIZATION_ARCHITECTURE.md §7 Group E` `files` SELECT rule:

- workspace admin (`lign_is_workspace_admin(workspace_id)`), OR
- authorized project participant with `file.download` on a project that owns an `asset_version` referencing this file (`EXISTS(version_files ⋈ asset_versions WHERE lign_has_capability(project_id, workspace_id, 'file.download'))`).

### 9.1 Approved helper pattern

One SECURITY DEFINER helper (installed in STORAGE 002):

```
public.lign_can_download_storage_object(p_object_name text) returns boolean
```

- Body: resolves the `files` row by `storage_ref = p_object_name`; returns `lign_is_workspace_admin(f.workspace_id) OR EXISTS(SELECT 1 FROM public.version_files vf JOIN public.asset_versions av ON av.id = vf.asset_version_id WHERE vf.file_id = f.id AND public.lign_has_capability(av.project_id, av.workspace_id, 'file.download'))`.
- `SECURITY DEFINER`, `search_path=''`, fully qualified.
- `REVOKE ALL FROM PUBLIC, anon`; `GRANT EXECUTE TO authenticated, service_role`.
- Recursion-safe: DEFINER bypasses `public.files` / `public.version_files` / `public.asset_versions` RLS on the internal joins; the helper does not read back through `storage.objects`.

### 9.2 `storage.objects` SELECT policy (installed in STORAGE 002)

```
bucket_id = 'lign-files'
AND public.lign_can_download_storage_object(name)
```

Rationale for wrapping the join inside the helper (not inlining into the policy): a naive Storage-side EXISTS on `public.files` would hit `public.files` SELECT RLS during evaluation, which itself requires a `version_files` reference — invisible for a reserved `uploaded` file and cascading for other queries. The DEFINER wrapper avoids the cascade entirely and is the canonical Supabase pattern.

---

## 10. Upload Storage authorization

`storage.objects` INSERT must require, together:

- `bucket_id = 'lign-files'`
- exact match to a server-generated `public.files.storage_ref`
- `public.files.status = 'uploaded'`
- `public.files.uploaded_by_profile_id = (select auth.uid())`

### 10.1 Approved helper pattern

One SECURITY DEFINER helper (installed in STORAGE 002):

```
public.lign_can_upload_storage_object(p_object_name text) returns boolean
```

- Body: `EXISTS(SELECT 1 FROM public.files f WHERE f.storage_ref = p_object_name AND f.status = 'uploaded' AND f.uploaded_by_profile_id = (select auth.uid()))`.
- `SECURITY DEFINER`, `search_path=''`, fully qualified.
- `REVOKE ALL FROM PUBLIC, anon`; `GRANT EXECUTE TO authenticated, service_role`.

DEFINER is required so the reserved-but-unattached `files` row is visible to the check (it would otherwise be invisible under `public.files` SELECT RLS, since a reserved file has no `version_files` reference yet).

### 10.2 `storage.objects` INSERT / UPDATE / DELETE policies (STORAGE 002)

- **INSERT:** `bucket_id = 'lign-files' AND public.lign_can_upload_storage_object(name)`
- **UPDATE:** **no policy** — objects are never overwritten via any authenticated path (§8).
- **DELETE:** **no policy** for `authenticated` — only `service_role` (via the STORAGE 004 Edge Function) can delete.

---

## 11. Existing AUTH 004 changes (documented; applied in STORAGE 003)

- **Remove** `public.attach_file_to_version(...)`. Its `p_storage_ref text` parameter is client-supplied and forgery-prone; no amendment can keep it safe. Callers move to `start_version_file_upload` + `finalize_version_file_upload`.
- **Add** `public.start_version_file_upload(...)` and `public.finalize_version_file_upload(...)` per §5.
- **Harden** `public.publish_version(...)` per §12.
- **Extend** `public.discard_draft_version(...)` per §13.
- **Unchanged**: `public.create_draft_version(...)`, `public.set_current_version(...)`.

The frozen capability model is unchanged: `version.upload`, `file.attach`, `file.download`, `file.remove_orphaned` all retain their existing role grants.

---

## 12. Publish invariant

`public.publish_version(p_asset_version_id)` must, before setting `status='published'`, verify that every `version_files` attachment references a file in status `active`:

```
if exists (
  select 1
    from public.version_files vf
    join public.files f on f.id = vf.file_id
   where vf.asset_version_id = p_asset_version_id
     and f.status <> 'active'
) then
  raise exception 'publish_version: version has non-active file attachments'
    using errcode = '23514';
end if;
```

Belt-and-suspenders — the STORAGE 003 flow's invariant (§5.4) should already guarantee this, but publish reasserts at the workflow boundary. Published versions must be byte-for-byte reproducible from `active` files only.

---

## 13. Discard behavior

`public.discard_draft_version(p_asset_version_id)` must, in the same transaction that removes the draft's `version_files` rows:

For each affected `file_id`:
- Count remaining `version_files` rows referencing that file (across all asset_versions, in any project).
- If remaining references > 0: leave `files.status = 'active'`.
- If remaining references = 0: set `files.status = 'orphaned'`, `files.orphaned_at = now()`.

**Never orphan a still-referenced file.** Never touch the physical Storage object during discard — only the DB status changes. Purge is a separate, retention-gated flow (§14).

---

## 14. Physical purge

Physical deletion of Storage objects is **not performed by any PostgreSQL RPC alone**. Three-part separation:

1. **DB eligibility** — `public.list_purgeable_files()` RPC (STORAGE 004): returns file_ids where `status='orphaned' AND now() > orphaned_at + interval '30 days' AND NOT EXISTS(SELECT 1 FROM version_files WHERE file_id = f.id)`. Read-only.
2. **Physical deletion** — a minimal Edge Function (STORAGE 004) using the Supabase `service_role` key deletes each object via the Storage Delete API. Runs outside authenticated paths. Not on upload/download authorization boundary.
3. **DB commit** — `public.mark_file_purged(file_id)` RPC (STORAGE 004): sets `status='purged'`, `purged_at=now()`. Requires `file.remove_orphaned` capability or `service_role`. Idempotent. Called by the Edge Function only after step 2 succeeds for that file.

Rules:
- **Never mark `purged` before physical deletion succeeds.**
- **Never delete an object that remains referenced by any `version_files` row.** The eligibility RPC re-checks this at query time; the Edge Function may re-check before delete.
- The single Edge Function scope is strictly the purge path. It is not on the upload/download data plane.
- **No cron** in MVP. Purge runs manually / on-demand via operator invocation of the Edge Function.
- Purged rows are retained permanently for audit; only the physical bytes are gone.

---

## 15. File security

Explicit threats and mitigations:

| Threat | Mitigation |
|---|---|
| Guessed object paths | Path is two UUIDv4s (~256 bits of unguessability). Even given the path, `storage.objects` SELECT RLS re-checks authorization every request. |
| Cross-workspace access | Helper resolves `files.workspace_id` from `storage_ref`; `lign_can_download_storage_object` requires either admin-of-that-workspace or `file.download` via a version in that workspace's project. |
| Cross-project access | `file.download` is per-project role; `lign_has_capability` gate is per-project. |
| Forged `storage_ref` | `start_version_file_upload` generates the path server-side from `workspace_id` + a fresh `file_id`. The RPC does not accept client-supplied path. `attach_file_to_version` is removed in STORAGE 003. |
| Uploading into another workspace | `start_` derives `workspace_id` from parent `asset_version`; `storage.objects` INSERT RLS requires `files.storage_ref = objects.name` AND `uploaded_by = auth.uid()` — no cross-workspace path can be constructed. |
| Attaching another workspace's File | Composite FK `(file_id, workspace_id) → files(id, workspace_id)` on `version_files` structurally prevents cross-workspace attachment (V1 lock). |
| Object overwrite | No UPDATE policy on `storage.objects` for `authenticated`. No API surface to overwrite. |
| Malicious MIME declaration | Client-declared `mime_type` is metadata only; Storage does not execute content. Downstream renderers must validate before use. Small denylist rejects known-dangerous executables/scripts at reservation time (§16). |
| Oversized files | `bucket.file_size_limit = 500 MB` + `start_` size cap. Storage rejects at ingest. |
| Orphan accumulation | 30-day retention + STORAGE 004 purge path. |
| Stale upload reservations | 24-hour TTL sweep transitions stale `uploaded` rows to `orphaned` (STORAGE 004). |

---

## 16. MVP file policy

- **Maximum individual object size:** 500 MB.
- **Checksum:** SHA-256 required.
- **Format support:** permissive to legitimate design workflow formats — PDFs, images, common CAD (`.dwg`, `.dxf`, `.rvt`, `.skp`, `.step`/`.stp`, `.iges`/`.igs`, `.3dm`, `.ifc`, `.gltf`, `.glb`, `.usdz`), office documents (`.docx`, `.xlsx`, `.pptx`), text (`.md`, `.txt`, `.csv`), archives (`.zip`), video (`.mp4`), audio (`.mp3`, `.wav`), plus generic `application/octet-stream`.
- **Denylist** (rejected at `start_`): `application/x-msdownload`, `application/x-msdos-program`, `application/x-executable`, `application/x-sh`, `application/x-shellscript`, `text/x-shellscript`, and file extensions matching known executable/script binaries. The denylist is intentionally small; sniffing / deep-content validation is out of MVP scope.
- **Signed URLs:** none in MVP (see §9).
- **Public URLs:** none (bucket is private).

Do not over-engineer format validation. Downstream renderers/consumers of files are responsible for their own MIME/content sanity checks.

---

## 17. Component boundaries

| Component | Owns |
|---|---|
| **PostgreSQL RPC / RLS** | Authorization, ownership derivation from `asset_version`, `files` lifecycle transitions, workspace-scoped dedup, `version_files` attachment records, workflow invariants (parent-draft, publish-active-files, discard-orphan), event emission for canonical file events (see EVENT_MODEL §4.6). |
| **Supabase Storage** | Physical binary storage. Authenticated object transfer under `storage.objects` RLS. Object immutability (no UPDATE). Deletion only via `service_role` from the STORAGE 004 Edge Function. |
| **Client** | SHA-256 computation, direct `.upload()` / `.download()` calls, retry/progress UX, display filename rendering. |
| **Edge Function** | **Only** the STORAGE 004 physical orphan purge (service-role Storage Delete). Not on normal upload/download authorization. No other Edge Function in MVP. |

---

## 18. Implementation sequence (frozen)

| Migration | Contents |
|---|---|
| **STORAGE 001** | This document. No code. No Supabase changes. |
| **STORAGE 002** | Create bucket `lign-files` (private, size limit 500 MB). Install `public.lign_can_download_storage_object(text)` and `public.lign_can_upload_storage_object(text)` helpers. Install `storage.objects` SELECT and INSERT policies scoped to `bucket_id='lign-files'`. No UPDATE/DELETE policies. No application-visible RPC. |
| **STORAGE 003** | Apply the narrow V1 amendment (§7.1: drop table constraint → create partial unique index). Add `public.start_version_file_upload(...)`. Add `public.finalize_version_file_upload(...)`. Drop `public.attach_file_to_version(...)`. Harden `public.publish_version(...)` per §12. Extend `public.discard_draft_version(...)` per §13. |
| **STORAGE 004** | Add `public.list_purgeable_files()` RPC. Add `public.mark_file_purged(uuid)` RPC. Add `public.sweep_stale_uploads()` RPC (24-hour uploaded → orphaned sweep). One minimal Edge Function that binds eligibility → service-role Storage delete → mark_purged. No cron. |

No STORAGE 005+ planned for MVP.

---

## 19. MVP non-goals

Explicitly excluded from MVP:

- CDN in front of Storage.
- Virus scanning infrastructure.
- Thumbnail / preview generation pipelines.
- Media transcoding (video, image resize).
- OCR / text extraction.
- AI content extraction.
- Cross-region replication.
- Storage lifecycle tiers (hot / cold / archive).
- Public share links.
- Multipart / resumable upload infrastructure.
- Complex lifecycle automation (scheduled purge via cron, retention overrides per file, per-workspace quotas, etc.).

These are intentionally deferred. Adding any of them without explicit architecture review is a violation of §20.

---

## 20. Modification policy

`STORAGE_ARCHITECTURE.md` becomes frozen after STORAGE 001.

Any future change that affects:

- tenant boundaries,
- object identity or path convention,
- file lifecycle states or transitions,
- deduplication semantics,
- Storage authorization (helpers, policies, RLS predicates),
- object immutability,
- or the `File ↔ Storage object` relationship,

must be reviewed as an **architecture change** and explicitly approved before implementation. It may not be silently introduced during STORAGE 002/003/004 or in any later stage.

Amendments approved by STORAGE 001 that STORAGE 002/003/004 will apply:

- STORAGE 002: bucket creation + Storage helpers + `storage.objects` policies (§9, §10, §18).
- STORAGE 003: `files_workspace_checksum_key` partial-unique-index amendment (§7.1); RPC replacements (§11); publish/discard hardening (§12, §13).
- STORAGE 004: orphan/stale cleanup + minimal Edge Function for physical purge (§14, §18).

The capability vocabulary, role model, authorization semantics, state machines (STATE_MACHINES.md), and event vocabulary (EVENT_MODEL.md) are **not** changed by STORAGE 001. If STORAGE 003/004 emit events, they will emit only canonical `file.attached` / `file.purged` names from EVENT_MODEL.md §4.6.
