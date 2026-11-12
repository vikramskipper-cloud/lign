import { Badge } from '@/ui/badge'
import type { OrgRole } from '@/shell/orgQueries'
import type { WorkspaceRole, ProjectRole } from './queries'
import { ORG_ROLE_LABELS, ORG_ROLE_DESCRIPTIONS, WORKSPACE_ROLE_LABELS, WORKSPACE_ROLE_DESCRIPTIONS, PROJECT_ROLE_LABELS, PROJECT_ROLE_DESCRIPTIONS } from './roleLabels'

type Props = { scope: 'organization'; role: OrgRole } | { scope: 'workspace'; role: WorkspaceRole } | { scope: 'project'; role: ProjectRole }
export function RoleBadge(props: Props) {
  const [label, description] = props.scope === 'organization'
    ? [ORG_ROLE_LABELS[props.role], ORG_ROLE_DESCRIPTIONS[props.role]]
    : props.scope === 'workspace'
      ? [WORKSPACE_ROLE_LABELS[props.role], WORKSPACE_ROLE_DESCRIPTIONS[props.role]]
      : [PROJECT_ROLE_LABELS[props.role], PROJECT_ROLE_DESCRIPTIONS[props.role]]
  return <Badge variant="outline" title={description}>{label}</Badge>
}
