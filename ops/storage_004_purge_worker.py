#!/usr/bin/env python3
"""
STORAGE 004 purge operator — reference implementation.

Runs OUT OF BAND with service-role credentials. Not a cron job; invoke manually
or from an operator harness. Idempotent, safe to re-run. One File at a time.

Environment:
  SUPABASE_URL              e.g. https://<ref>.supabase.co
  SUPABASE_SERVICE_ROLE_KEY service_role JWT (never expose to clients)
  PURGE_WORKER_ID           free-form identity string, default "operator"
  PURGE_BATCH_SIZE          default 50

Flow per candidate (file_id, storage_ref):
  1. claim_file_for_purge(file_id)    → DB reserves the row + returns canonical ref
  2. Storage HTTP DELETE at ref       → physical bytes deleted
     - 200 OK / 204 No Content        → treat as deleted
     - 404 Not Found                  → treat as already-satisfied (§7)
     - other 4xx/5xx / network error  → try release_purge_claim (may itself raise
                                         on reclaim-race, in which case the row is
                                         stranded and a subsequent retry will
                                         re-claim once the object is deleted)
  3. mark_file_purged(file_id)        → DB flips to purged and emits file.purged

The worker MUST NOT construct paths from anywhere but the claim RPC's return
value. The bucket is fixed to lign-files by the DB layer.

Requires: python 3.10+, requests.
"""

import os
import sys
import time
import json
import logging
import urllib.parse
import requests

LOG = logging.getLogger("storage_004_purge_worker")
BUCKET = "lign-files"


def _rpc(base_url: str, key: str, name: str, body: dict) -> requests.Response:
    return requests.post(
        f"{base_url}/rest/v1/rpc/{name}",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        },
        data=json.dumps(body),
        timeout=30,
    )


def _storage_delete(base_url: str, key: str, storage_ref: str) -> int:
    # Storage REST: DELETE /storage/v1/object/{bucket}/{path}
    quoted = urllib.parse.quote(storage_ref, safe="/")
    r = requests.delete(
        f"{base_url}/storage/v1/object/{BUCKET}/{quoted}",
        headers={"apikey": key, "Authorization": f"Bearer {key}"},
        timeout=30,
    )
    return r.status_code


def process_one(base_url: str, key: str, worker_id: str, file_id: str) -> str:
    # 1. Claim
    claim = _rpc(base_url, key, "claim_file_for_purge",
                 {"p_file_id": file_id, "p_worker": worker_id})
    if claim.status_code != 200:
        return f"claim_failed status={claim.status_code} body={claim.text[:200]}"
    row = claim.json()[0]
    storage_ref = row["out_storage_ref"]

    # 2. Physical delete (401/403 are auth failures — abort loudly)
    try:
        status = _storage_delete(base_url, key, storage_ref)
    except requests.RequestException as e:
        LOG.warning("network error deleting %s: %s", storage_ref, e)
        _rpc(base_url, key, "release_purge_claim", {"p_file_id": file_id})
        return "network_error_released"

    if status in (200, 204):
        deletion = "deleted"
    elif status == 404:
        deletion = "already_absent"  # §7: treat as satisfied
    elif status in (401, 403):
        LOG.error("auth failure on storage delete for %s: %s", storage_ref, status)
        _rpc(base_url, key, "release_purge_claim", {"p_file_id": file_id})
        return f"storage_auth_failed_{status}"
    else:
        LOG.warning("storage delete for %s returned %s; releasing", storage_ref, status)
        rel = _rpc(base_url, key, "release_purge_claim", {"p_file_id": file_id})
        if rel.status_code != 200:
            # Release itself raised (probably reclaim-race). The row is stranded.
            # Next run will re-attempt storage delete after DB verifies claim
            # again — safe because the row is still purge_reserved_at NOT NULL
            # from THIS run's claim.
            return f"storage_delete_failed_{status}_release_conflict_{rel.text[:200]}"
        return f"storage_delete_failed_{status}_released"

    # 3. Mark purged
    mark = _rpc(base_url, key, "mark_file_purged", {"p_file_id": file_id})
    if mark.status_code != 200:
        # This is the alarming case: bytes deleted but DB not updated.
        # The row remains status='orphaned' + purge_reserved_at set. A retry
        # will re-run mark_file_purged (idempotent) — but the Storage delete
        # was one-shot. Manual intervention may be needed only if mark
        # keeps failing.
        LOG.error("BYTES DELETED but mark_file_purged failed for %s: %s %s",
                  file_id, mark.status_code, mark.text[:200])
        return f"mark_failed_after_{deletion}"

    return f"purged_{deletion}"


def main():
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    base_url = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    worker_id = os.environ.get("PURGE_WORKER_ID", "operator")
    batch = int(os.environ.get("PURGE_BATCH_SIZE", "50"))

    # 0. Sweep first — moves 24h+ abandoned reservations to orphaned so the
    #    30-day countdown starts. Not strictly required each run.
    sweep = _rpc(base_url, key, "sweep_stale_uploads", {})
    LOG.info("sweep_stale_uploads: %s %s", sweep.status_code, sweep.text[:200])

    # 1. Enumerate candidates
    lst = _rpc(base_url, key, "list_purgeable_files", {"p_limit": batch})
    if lst.status_code != 200:
        LOG.error("list_purgeable_files failed: %s %s", lst.status_code, lst.text[:200])
        sys.exit(1)
    candidates = lst.json()
    LOG.info("candidates: %d", len(candidates))

    # 2. Process one at a time
    results = {}
    for c in candidates:
        fid = c["out_file_id"]
        r = process_one(base_url, key, worker_id, fid)
        results[fid] = r
        LOG.info("%s -> %s", fid, r)

    LOG.info("summary: %s", json.dumps(results))


if __name__ == "__main__":
    main()
