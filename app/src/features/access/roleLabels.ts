import type { WorkspaceRole, ProjectRole } from './queries'
export const WORKSPACE_ROLE_LABELS: Record<WorkspaceRole, string> = { owner: 'Owner', admin: 'Workspace lead', member: 'Team member' }
export const PROJECT_ROLE_LABELS: Record<ProjectRole, string> = { lead: 'Project lead', contributor: 'Contributor', reviewer: 'Reviewer', approver: 'Approver', observer: 'Viewer' }
