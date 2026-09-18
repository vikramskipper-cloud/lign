/**
 * Central query-key registry. Every query key used anywhere in the app comes
 * from here so invalidations are safe and refactors are one-file. Keep this
 * module boring; add keys per vertical slice.
 */

export interface AssetFilters {
  collection: string | null | 'unfiled'
  discipline: string | null
  search: string
}

export interface AssetNeighborScope {
  collection: string | null | 'unfiled'
  discipline: string | null
}

export const qk = {
  session: () => ['session'] as const,
  profile: (id: string) => ['profile', id] as const,

  workspaces: () => ['workspaces'] as const,
  workspace: (id: string) => ['workspace', id] as const,
  workspaceMembers: (wsId: string) => ['workspace', wsId, 'members'] as const,

  projects: (wsId: string) => ['workspace', wsId, 'projects'] as const,
  project: (id: string) => ['project', id] as const,
  projectCapabilities: (projId: string, wsId: string) =>
    ['project', projId, 'capabilities', wsId] as const,
  projectParticipants: (id: string) => ['project', id, 'participants'] as const,

  collections: (projId: string) => ['project', projId, 'collections'] as const,
  collection: (id: string) => ['collection', id] as const,

  disciplines: (projId: string) => ['project', projId, 'disciplines'] as const,
  discipline: (id: string) => ['discipline', id] as const,

  assets: (projId: string, filters: AssetFilters) =>
    ['project', projId, 'assets', filters] as const,
  asset: (id: string) => ['asset', id] as const,

  assetVersions: (assetId: string) => ['asset', assetId, 'versions'] as const,
  assetVersion: (id: string) => ['asset-version', id] as const,

  assetNeighbors: (assetId: string, scope: AssetNeighborScope) =>
    ['asset', assetId, 'neighbors', scope] as const,

  versionFiles: (versionId: string) => ['asset-version', versionId, 'files'] as const,
  file: (fileId: string) => ['file', fileId] as const,
  signedUrl: (fileId: string, purpose: 'view' | 'thumb') =>
    ['signed-url', fileId, purpose] as const,

  // APP 005 — Comments & Annotations
  commentsForVersion: (versionId: string) =>
    ['asset-version', versionId, 'comments'] as const,
  commentsForAnnotation: (annotationId: string) =>
    ['annotation', annotationId, 'comments'] as const,
  comment: (id: string) => ['comment', id] as const,
  commentEdits: (id: string) => ['comment', id, 'edits'] as const,
  annotationsForVersion: (versionId: string) =>
    ['asset-version', versionId, 'annotations'] as const,
  annotation: (id: string) => ['annotation', id] as const,

  // APP 006 — Reviews
  reviewsList: (
    scope: { wsId: string; projId?: string | null },
    view: string,
    filters: Record<string, unknown>,
  ) =>
    ['reviews', 'list', scope.wsId, scope.projId ?? null, view, filters] as const,
  reviewsWorkspaceDashboard: (wsId: string, view: string) =>
    ['reviews', 'ws-dashboard', wsId, view] as const,
  reviewsProjectDashboard: (projId: string, view: string) =>
    ['reviews', 'proj-dashboard', projId, view] as const,
  review: (id: string) => ['review', id] as const,
  reviewChain: (rootId: string) => ['review-chain', rootId] as const,
  reviewParticipants: (reviewId: string) =>
    ['review', reviewId, 'participants'] as const,
  reviewMetrics: (scope: string) => ['review-metrics', scope] as const,
  reviewInboxCount: (wsId: string) => ['review-inbox-count', wsId] as const,
  savedViews: (wsId: string, scope: string) =>
    ['saved-views', wsId, scope] as const,
  bookmarks: (wsId: string, subjectKind: string) =>
    ['bookmarks', wsId, subjectKind] as const,

  // APP 007 — Approvals
  approvalsList: (
    scope: { wsId: string; projId?: string | null },
    view: string,
    filters: Record<string, unknown>,
  ) =>
    ['approvals', 'list', scope.wsId, scope.projId ?? null, view, filters] as const,
  approvalsWorkspaceDashboard: (wsId: string, view: string) =>
    ['approvals', 'ws-dashboard', wsId, view] as const,
  approvalsProjectDashboard: (projId: string, view: string) =>
    ['approvals', 'proj-dashboard', projId, view] as const,
  approvalRequest: (id: string) => ['approval', id] as const,
  approvalChain: (rootId: string) => ['approval-chain', rootId] as const,
  approvalResponses: (requestId: string) =>
    ['approval', requestId, 'responses'] as const,
  approvalMetrics: (scope: string) => ['approval-metrics', scope] as const,
  approvalInboxCount: (wsId: string) => ['approval-inbox-count', wsId] as const,
  approvalsForVersion: (versionId: string) =>
    ['approvals', 'for-version', versionId] as const,
  approvalReadiness: (versionId: string) =>
    ['approval', 'readiness', versionId] as const,

  // APP 008 — Requirements (product surface)
  requirementsList: (
    scope: { wsId: string; projId?: string | null },
    view: string,
    filters: Record<string, unknown>,
  ) =>
    ['requirements', 'list', scope.wsId, scope.projId ?? null, view, filters] as const,
  requirementsWorkspaceDashboard: (wsId: string, view: string) =>
    ['requirements', 'ws-dashboard', wsId, view] as const,
  requirementsProjectDashboard: (projId: string, view: string) =>
    ['requirements', 'proj-dashboard', projId, view] as const,
  requirement: (id: string) => ['requirement', id] as const,
  requirementByCode: (projId: string, code: string) =>
    ['requirement', 'by-code', projId, code] as const,
  requirementChain: (id: string) => ['requirement-chain', id] as const,
  requirementTrace: (id: string) => ['requirement-trace', id] as const,
  requirementAssessments: (id: string) => ['requirement', id, 'assessments'] as const,
  requirementHistory: (id: string) => ['requirement', id, 'history'] as const,
  requirementDiscussions: (id: string) => ['requirement', id, 'discussions'] as const,
  requirementApplicability: (id: string) =>
    ['requirement', id, 'applicability'] as const,
  requirementMetrics: (scope: string) => ['requirement-metrics', scope] as const,
  requirementInboxCount: (wsId: string) =>
    ['requirement-inbox-count', wsId] as const,
  applicableRequirementsForAsset: (assetId: string, versionId?: string | null) =>
    ['requirements', 'for-asset', assetId, versionId ?? null] as const,
  assessmentsForVersion: (versionId: string) =>
    ['requirements', 'for-version-assessments', versionId] as const,
  releaseReadinessForVersion: (versionId: string) =>
    ['requirements', 'release-readiness', versionId] as const,

  // APP 009 — Releases (product surface)
  releasesList: (
    scope: { wsId: string; projId?: string | null },
    view: string,
    filters: Record<string, unknown>,
  ) =>
    ['releases', 'list', scope.wsId, scope.projId ?? null, view, filters] as const,
  releasesWorkspaceDashboard: (wsId: string, view: string) =>
    ['releases', 'ws-dashboard', wsId, view] as const,
  releasesProjectDashboard: (projId: string, view: string) =>
    ['releases', 'proj-dashboard', projId, view] as const,
  release: (id: string) => ['release', id] as const,
  releaseByCode: (projId: string, code: string) =>
    ['release', 'by-code', projId, code] as const,
  releaseChain: (id: string) => ['release-chain', id] as const,
  releaseEvidence: (id: string) => ['release', id, 'evidence'] as const,
  releaseComparison: (id: string, compareToId: string | null) =>
    ['release', id, 'comparison', compareToId ?? null] as const,
  releaseActivity: (id: string) => ['release', id, 'activity'] as const,
  releaseItems: (id: string) => ['release', id, 'items'] as const,
  releaseInboxCount: (wsId: string) => ['release-inbox-count', wsId] as const,
  releaseMetrics: (scope: string) => ['release-metrics', scope] as const,
  releasesForAsset: (assetId: string) =>
    ['releases', 'for-asset', assetId] as const,
  releasesForVersion: (versionId: string) =>
    ['releases', 'for-version', versionId] as const,
  releaseReadinessForPublish: (
    assetId: string,
    versionId: string,
    releaseType: string | null,
  ) =>
    ['release', 'readiness-for-publish', assetId, versionId, releaseType ?? null] as const,

  // APP 010 — Notifications
  notification: (id: string) => ['notification', id] as const,
  notificationsInbox: (
    wsId: string,
    tab: string,
    filters: Record<string, unknown>,
    cursor: { created_at: string; id: string } | null,
  ) => ['notification', 'inbox', wsId, tab, filters, cursor] as const,
  notificationsUnread: (wsId: string) => ['notification', 'unread', wsId] as const,
  notificationCenter: (wsId: string) => ['notification', 'center', wsId] as const,
  notificationBadgeCount: (wsId: string) => ['notification', 'badge', wsId] as const,
  notificationsBySource: (subjectKind: string, subjectId: string) =>
    ['notification', 'subject', subjectKind, subjectId] as const,
  notificationInboxFacets: (wsId: string) =>
    ['notification', 'inbox-facets', wsId] as const,
} as const
