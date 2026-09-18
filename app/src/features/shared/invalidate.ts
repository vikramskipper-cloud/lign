import type { QueryClient, QueryKey } from '@tanstack/react-query'

/** Invalidate every `qk.assets(projId, *)` variant regardless of filter shape. */
export function invalidateAssetsForProject(qc: QueryClient, projId: string) {
  qc.invalidateQueries({
    predicate: (q) => {
      const k = q.queryKey as QueryKey
      return (
        Array.isArray(k) &&
        k[0] === 'project' &&
        k[1] === projId &&
        k[2] === 'assets'
      )
    },
  })
}

/** Invalidate every `qk.assetNeighbors(assetId, *)` variant. */
export function invalidateNeighborsForAsset(qc: QueryClient, assetId: string) {
  qc.invalidateQueries({
    predicate: (q) => {
      const k = q.queryKey as QueryKey
      return Array.isArray(k) && k[0] === 'asset' && k[1] === assetId && k[2] === 'neighbors'
    },
  })
}

/** Invalidate a single version's files list. */
export function invalidateVersionFiles(qc: QueryClient, versionId: string) {
  qc.invalidateQueries({ queryKey: ['asset-version', versionId, 'files'] })
}

/** Invalidate a single version's comment list (all filter/annotation-set variants). */
export function invalidateCommentsForVersion(qc: QueryClient, versionId: string) {
  qc.invalidateQueries({
    predicate: (q) => {
      const k = q.queryKey as QueryKey
      return (
        Array.isArray(k) &&
        k[0] === 'asset-version' &&
        k[1] === versionId &&
        k[2] === 'comments'
      )
    },
  })
}

/** Invalidate a single version's annotation list. */
export function invalidateAnnotationsForVersion(qc: QueryClient, versionId: string) {
  qc.invalidateQueries({ queryKey: ['asset-version', versionId, 'annotations'] })
}

/** APP 006: broad invalidation of any reviews list variant for a workspace or project. */
export function invalidateReviewsLists(qc: QueryClient, wsId?: string, projId?: string) {
  qc.invalidateQueries({
    predicate: (q) => {
      const k = q.queryKey as QueryKey
      if (!Array.isArray(k) || k[0] !== 'reviews') return false
      if (wsId && k[2] !== wsId) return false
      if (projId && k[3] !== projId) return false
      return true
    },
  })
}

/** APP 006: bump per-review caches (detail, chain, participants, metrics). */
export function invalidateReview(qc: QueryClient, reviewId: string, rootId?: string) {
  qc.invalidateQueries({ queryKey: ['review', reviewId] })
  qc.invalidateQueries({ queryKey: ['review', reviewId, 'participants'] })
  qc.invalidateQueries({ queryKey: ['review-metrics', reviewId] })
  if (rootId) qc.invalidateQueries({ queryKey: ['review-chain', rootId] })
}

/** APP 006: bump the workspace inbox badge. */
export function invalidateReviewInbox(qc: QueryClient, wsId: string) {
  qc.invalidateQueries({ queryKey: ['review-inbox-count', wsId] })
}

/** APP 007: broad invalidation of any approvals list variant for a workspace or project. */
export function invalidateApprovalsLists(qc: QueryClient, wsId?: string, projId?: string) {
  qc.invalidateQueries({
    predicate: (q) => {
      const k = q.queryKey as QueryKey
      if (!Array.isArray(k) || k[0] !== 'approvals') return false
      if (wsId && k[2] !== wsId) return false
      if (projId && k[3] !== projId) return false
      return true
    },
  })
}

/** APP 007: bump per-approval caches (detail, chain, responses, metrics, readiness). */
export function invalidateApproval(
  qc: QueryClient,
  requestId: string,
  rootId?: string,
  versionId?: string,
) {
  qc.invalidateQueries({ queryKey: ['approval', requestId] })
  qc.invalidateQueries({ queryKey: ['approval', requestId, 'responses'] })
  qc.invalidateQueries({ queryKey: ['approval-metrics', requestId] })
  if (rootId) qc.invalidateQueries({ queryKey: ['approval-chain', rootId] })
  if (versionId) {
    qc.invalidateQueries({ queryKey: ['approvals', 'for-version', versionId] })
    qc.invalidateQueries({ queryKey: ['approval', 'readiness', versionId] })
  }
}

/** APP 007: bump the workspace inbox badge. */
export function invalidateApprovalInbox(qc: QueryClient, wsId: string) {
  qc.invalidateQueries({ queryKey: ['approval-inbox-count', wsId] })
}

/** APP 008: broad invalidation of any requirements list variant for a workspace or project. */
export function invalidateRequirementsLists(
  qc: QueryClient,
  wsId?: string,
  projId?: string,
) {
  qc.invalidateQueries({
    predicate: (q) => {
      const k = q.queryKey as QueryKey
      if (!Array.isArray(k) || k[0] !== 'requirements') return false
      // list-shape only (skip other 'requirements' sub-namespaces)
      if (k[1] !== 'list' && k[1] !== 'ws-dashboard' && k[1] !== 'proj-dashboard') return false
      if (wsId && k[1] === 'list' && k[2] !== wsId) return false
      if (wsId && k[1] === 'ws-dashboard' && k[2] !== wsId) return false
      if (projId && k[1] === 'list' && k[3] !== projId) return false
      if (projId && k[1] === 'proj-dashboard' && k[2] !== projId) return false
      return true
    },
  })
  // metrics also refresh on any list mutation
  qc.invalidateQueries({
    predicate: (q) => {
      const k = q.queryKey as QueryKey
      return Array.isArray(k) && k[0] === 'requirement-metrics'
    },
  })
}

/** APP 008: bump per-requirement caches (detail, chain, trace, history, discussions, assessments, applicability). */
export function invalidateRequirement(qc: QueryClient, requirementId: string) {
  qc.invalidateQueries({ queryKey: ['requirement', requirementId] })
  qc.invalidateQueries({ queryKey: ['requirement-chain', requirementId] })
  qc.invalidateQueries({ queryKey: ['requirement-trace', requirementId] })
}

/** APP 008: bump the workspace inbox badge. */
export function invalidateRequirementInbox(qc: QueryClient, wsId: string) {
  qc.invalidateQueries({ queryKey: ['requirement-inbox-count', wsId] })
}

/** APP 009: broad invalidation of any releases list variant for a workspace or project. */
export function invalidateReleasesLists(
  qc: QueryClient,
  wsId?: string,
  projId?: string,
) {
  qc.invalidateQueries({
    predicate: (q) => {
      const k = q.queryKey as QueryKey
      if (!Array.isArray(k) || k[0] !== 'releases') return false
      if (k[1] !== 'list' && k[1] !== 'ws-dashboard' && k[1] !== 'proj-dashboard') return false
      if (wsId && k[1] === 'list' && k[2] !== wsId) return false
      if (wsId && k[1] === 'ws-dashboard' && k[2] !== wsId) return false
      if (projId && k[1] === 'list' && k[3] !== projId) return false
      if (projId && k[1] === 'proj-dashboard' && k[2] !== projId) return false
      return true
    },
  })
  qc.invalidateQueries({
    predicate: (q) => {
      const k = q.queryKey as QueryKey
      return Array.isArray(k) && k[0] === 'release-metrics'
    },
  })
}

/** APP 009: bump per-release caches (detail, chain, evidence, items, activity, comparison). */
export function invalidateRelease(qc: QueryClient, releaseId: string) {
  qc.invalidateQueries({ queryKey: ['release', releaseId] })
  qc.invalidateQueries({ queryKey: ['release-chain', releaseId] })
}

/** APP 009: bump the workspace inbox badge. */
export function invalidateReleaseInbox(qc: QueryClient, wsId: string) {
  qc.invalidateQueries({ queryKey: ['release-inbox-count', wsId] })
}

/** APP 010: bump every notification query key across the workspace. */
export function invalidateNotifications(qc: QueryClient, wsId?: string) {
  qc.invalidateQueries({
    predicate: (q) => {
      const k = q.queryKey as QueryKey
      if (!Array.isArray(k) || k[0] !== 'notification') return false
      if (!wsId) return true
      // wsId lives at index 2 for inbox/unread/center/badge/inbox-facets keys.
      if (typeof k[2] === 'string' && k[2] === wsId) return true
      // qk.notification(id) has no wsId — always invalidate on wsId-scoped calls too.
      if (k.length === 2 && typeof k[1] === 'string') return true
      return false
    },
  })
}

/** APP 010: bump only the bell badge for the workspace. */
export function invalidateNotificationBadge(qc: QueryClient, wsId: string) {
  qc.invalidateQueries({ queryKey: ['notification', 'badge', wsId] })
}

/**
 * APP 010 §18.1: cross-slice invalidation helper. Every workflow mutation
 * that may result in an activity_events INSERT (and therefore new notification
 * rows for the caller) should invoke this after success.
 */
export function invalidateNotificationSurfaces(qc: QueryClient, wsId: string) {
  qc.invalidateQueries({ queryKey: ['notification', 'badge', wsId] })
  qc.invalidateQueries({ queryKey: ['notification', 'unread', wsId] })
  qc.invalidateQueries({ queryKey: ['notification', 'center', wsId] })
}

/** Invalidate all asset-neighbor caches in the app (used when the ordering may shift globally). */
export function invalidateAllNeighbors(qc: QueryClient) {
  qc.invalidateQueries({
    predicate: (q) => {
      const k = q.queryKey as QueryKey
      return Array.isArray(k) && k[0] === 'asset' && k[2] === 'neighbors'
    },
  })
}
