/**
 * Frozen capability vocabulary the frontend cares about. Kept in sync with
 * lign_has_capability. Any capability the app checks MUST be listed here so
 * the bulk fetch primes them all in one shot.
 */
export const CAPABILITY_KEYS = [
  // Project scope
  'project.view',
  'project.edit',
  'project.manage_access',
  'project.archive',
  // Collections
  'collection.view',
  'collection.create',
  'collection.edit',
  'collection.archive',
  // Design assets
  'asset.view',
  'asset.create',
  'asset.edit',
  'asset.archive',
  'asset.set_current',
  // Versions
  'version.view',
  'version.upload',
  'version.publish',
  'version.discard_draft',
  // Reviews
  'review.view',
  'review.create',
  'review.participate',
  'review.complete',
  'review.coordinate',
  'review.reopen',
  // Comments / annotations
  'comment.view',
  'comment.create',
  'comment.edit_own',
  'comment.resolve',
  'annotation.view',
  'annotation.create',
  'annotation.resolve',
  // Changes / decisions
  'change.view',
  'change.create',
  'change.resolve',
  'decision.view',
  'decision.create',
  // Approvals
  'approval.view',
  'approval.request',
  'approval.respond',
  'approval.cancel',
  'approval.veto',
  'approval.expire',
  'approval.supersede',
  // Releases
  'release.view',
  'release.create',
  'release.finalize',
  'release.withdraw',
  // Files
  'file.upload',
  'file.attach',
  'file.download',
  'file.remove_orphaned',
  // Audit
  'activity.view',
  // Requirements (REQUIREMENTS 003)
  'requirement.view',
  'requirement.create',
  'requirement.edit',
  'requirement.archive',
  'requirement.assess',
  // Notifications (APP 010) — personal (implicit for every authenticated user)
  'notification.view',
  'notification.manage',
  // People & Access (APP 013) — workspace-scoped. lign_has_capability answers
  // these BEFORE its project-scope validation, so they resolve correctly
  // whether project_id is a real project or null. That means they come back
  // correctly in the per-project map below, and useWorkspaceAccess() can also
  // fetch them alone on screens that have no project in scope.
  'member.invite',
  'member.remove',
  'member.change_role',
  'stakeholder.invite',
  'stakeholder.revoke',
  'workspace.manage',
] as const

export type CapabilityKey = (typeof CAPABILITY_KEYS)[number]
export type CapabilityMap = Record<CapabilityKey, boolean>
