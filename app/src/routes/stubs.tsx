import type { ReactElement } from 'react'
import { Construction } from 'lucide-react'
import { EmptyState } from '@/ui/empty-state'

/**
 * Vertical stubs used by every non-shell route in APP 002. Each is a labelled
 * empty state naming the slice that will replace it. This keeps the router,
 * layouts, and capability gates real while the business layer waits.
 */
type StubComponent = (() => ReactElement) & { handle: { crumb: string } }

function makeStub(title: string, description: string): StubComponent {
  const StubScreen = () => (
    <div className="p-8">
      <EmptyState
        icon={<Construction className="h-8 w-8" />}
        title={title}
        description={description}
      />
    </div>
  )
  return StubScreen as StubComponent
}

// Workspace-level stubs (workspace-mode nav)
export const ProjectListStub = makeStub(
  'Projects',
  'Grid of projects in this workspace — lands in APP 003.',
)
ProjectListStub.handle = { crumb: 'Projects' }

export const WorkspacePeopleStub = makeStub(
  'People',
  'Workspace members and stakeholders admin — lands with the People slice.',
)
WorkspacePeopleStub.handle = { crumb: 'People' }

export const WorkspaceSettingsStub = makeStub(
  'Settings',
  'Workspace name, branding, retention — lands with the Settings slice.',
)
WorkspaceSettingsStub.handle = { crumb: 'Settings' }

// Project-level stubs (project-mode nav)
export const ProjectOverviewStub = makeStub(
  'Overview',
  'Inbox, recent activity, at-risk requirements — lands in APP 003+.',
)
ProjectOverviewStub.handle = { crumb: 'Overview' }

export const DesignsStub = makeStub(
  'Designs',
  'DesignAsset grid + entry to the Design Workspace — lands in APP 003.',
)
DesignsStub.handle = { crumb: 'Designs' }

export const RequirementsStub = makeStub(
  'Requirements',
  'Project requirements catalog and detail — lands after APP 003.',
)
RequirementsStub.handle = { crumb: 'Requirements' }

export const AssetStub = makeStub(
  'Asset',
  'The Design Workspace (version bar + viewer + right sidebar) — lands in APP 003 / APP 004.',
)
AssetStub.handle = { crumb: 'Asset' }

export const ReleasesStub = makeStub(
  'Releases',
  'Release bundle list — lands in APP 009.',
)
ReleasesStub.handle = { crumb: 'Releases' }

export const ReleaseDetailStub = makeStub(
  'Release',
  'Release bundle detail — lands in APP 009.',
)
ReleaseDetailStub.handle = { crumb: 'Release' }

export const ProjectPeopleStub = makeStub(
  'People',
  'Project participants roster — lands with the People slice.',
)
ProjectPeopleStub.handle = { crumb: 'People' }
