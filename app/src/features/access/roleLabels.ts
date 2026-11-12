import type { WorkspaceRole, ProjectRole } from './queries'
import type { OrgRole } from '@/shell/orgQueries'
export const ORG_ROLE_LABELS: Record<OrgRole, string> = { owner: 'Studio owner', admin: 'Studio admin', member: 'Studio member' }
export const WORKSPACE_ROLE_LABELS: Record<WorkspaceRole, string> = { owner: 'Owner', admin: 'Workspace lead', member: 'Team member' }
export const PROJECT_ROLE_LABELS: Record<ProjectRole, string> = { lead: 'Project lead', contributor: 'Contributor', reviewer: 'Reviewer', approver: 'Approver', observer: 'Viewer' }
export const ORG_ROLE_DESCRIPTIONS: Record<OrgRole, string> = {
  owner: 'Administers every workspace and project; controls studio ownership. Creative actions require a project role.',
  admin: 'Administers every workspace and project. Creative actions require a project role.',
  member: 'Studio membership alone grants no project access. Workspace and project assignments determine access.',
}
export const WORKSPACE_ROLE_DESCRIPTIONS: Record<WorkspaceRole, string> = {
  owner: 'Administers this workspace and every project in it. Creative actions require a project role.',
  admin: 'Oversees every project in this workspace, manages its team and assigns project leads. Creative actions require a project role.',
  member: 'Works on assigned projects according to their project role; cannot see unassigned projects.',
}
export const PROJECT_ROLE_DESCRIPTIONS: Record<ProjectRole, string> = {
  lead: 'Manages this project, its participants and design workflow; can invite external reviewers and approvers.',
  contributor: 'Creates and publishes design work, comments and coordinates reviews and approval requests in this project.',
  reviewer: 'Views designs, comments, annotates and participates in reviews they are assigned to.',
  approver: 'Views designs, comments and responds to approval requests they are assigned to.',
  observer: 'Views project designs and history; cannot add comments, edit designs or approve.',
}
