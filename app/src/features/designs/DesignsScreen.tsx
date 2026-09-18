import * as React from 'react'
import { useParams, useSearchParams } from 'react-router'
import { Layers, Plus, Search } from 'lucide-react'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import { EmptyState } from '@/ui/empty-state'
import { LoadingPage } from '@/ui/loading-page'
import { useProjectCapabilities } from '@/lib/capabilities'
import { CollectionSidebar } from '@/features/collections/CollectionSidebar'
import { DisciplineFilter } from '@/features/disciplines/DisciplineFilter'
import { useDisciplines } from '@/features/disciplines/queries'
import { useAssets } from './queries'
import { AssetGrid } from './AssetGrid'
import { CreateAssetDialog } from './CreateAssetDialog'

export const DesignsHandle = { crumb: 'Designs' }

type CollectionFilter = string | null | 'unfiled'

function useDebounced<T>(value: T, ms: number): T {
  const [v, setV] = React.useState(value)
  React.useEffect(() => {
    const t = setTimeout(() => setV(value), ms)
    return () => clearTimeout(t)
  }, [value, ms])
  return v
}

export function DesignsScreen() {
  const { ws_id, proj_id } = useParams<{ ws_id: string; proj_id: string }>()
  const caps = useProjectCapabilities(proj_id ?? '', ws_id ?? '')
  const [searchParams, setSearchParams] = useSearchParams()
  const [collection, setCollection] = React.useState<CollectionFilter>(() => {
    const from = searchParams.get('from')
    if (from === 'unfiled') return 'unfiled'
    if (from?.startsWith('collection:')) return from.slice('collection:'.length)
    return null
  })
  const [discipline, setDiscipline] = React.useState<string | null>(
    searchParams.get('discipline'),
  )
  const [searchInput, setSearchInput] = React.useState('')
  const search = useDebounced(searchInput, 250)
  const [createOpen, setCreateOpen] = React.useState(false)

  // Reflect filter state in URL for share/back UX (D7 extended).
  React.useEffect(() => {
    const next = new URLSearchParams(searchParams)
    if (collection === 'unfiled') next.set('from', 'unfiled')
    else if (collection) next.set('from', `collection:${collection}`)
    else next.delete('from')
    if (discipline) next.set('discipline', discipline)
    else next.delete('discipline')
    const currentStr = searchParams.toString()
    const nextStr = next.toString()
    if (currentStr !== nextStr) setSearchParams(next, { replace: true })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [collection, discipline])

  const assets = useAssets(proj_id, {
    collection,
    discipline,
    search,
  })
  const disciplines = useDisciplines(proj_id)

  if (!ws_id || !proj_id) return <LoadingPage />

  const canCreateAsset = Boolean(caps.data?.['asset.create'])
  const canCreateCollection = Boolean(caps.data?.['collection.create'])
  const canEditCollection = Boolean(caps.data?.['collection.edit'])
  const canArchiveCollection = Boolean(caps.data?.['collection.archive'])
  const canEditProject = Boolean(caps.data?.['project.edit'])

  const scopeQuery = new URLSearchParams()
  if (collection === 'unfiled') scopeQuery.set('from', 'unfiled')
  else if (collection) scopeQuery.set('from', `collection:${collection}`)
  if (discipline) scopeQuery.set('discipline', discipline)
  const scopeQueryStr = scopeQuery.toString()

  return (
    <div className="flex h-full min-h-0">
      <CollectionSidebar
        workspaceId={ws_id}
        projectId={proj_id}
        value={collection}
        onChange={setCollection}
        canCreate={canCreateCollection}
        canEdit={canEditCollection}
        canArchive={canArchiveCollection}
      />

      <div className="flex flex-1 min-w-0 flex-col">
        <div className="flex items-center gap-2 border-b border-[--color-border] p-3">
          <DisciplineFilter
            workspaceId={ws_id}
            projectId={proj_id}
            value={discipline}
            onChange={setDiscipline}
            canEdit={canEditProject}
          />
          <div className="relative ml-auto max-w-xs flex-1">
            <Search className="pointer-events-none absolute left-2 top-1/2 h-4 w-4 -translate-y-1/2 text-[--color-text-subtle]" />
            <Input
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              placeholder="Search assets"
              className="pl-8"
            />
          </div>
          {canCreateAsset && (
            <Button size="sm" onClick={() => setCreateOpen(true)}>
              <Plus className="mr-1 h-4 w-4" />
              New asset
            </Button>
          )}
        </div>

        <div className="flex-1 overflow-auto p-4">
          {assets.isLoading ? (
            <p className="text-sm text-[--color-text-muted]">Loading…</p>
          ) : assets.isError ? (
            <EmptyState title="Couldn't load assets" description="Try again in a moment." />
          ) : (assets.data ?? []).length === 0 ? (
            <EmptyStateForFilters
              collection={collection}
              search={search}
              canCreate={canCreateAsset}
              onCreate={() => setCreateOpen(true)}
              onClearSearch={() => {
                setSearchInput('')
              }}
            />
          ) : (
            <AssetGrid
              workspaceId={ws_id}
              projectId={proj_id}
              assets={assets.data ?? []}
              disciplines={disciplines.data ?? []}
              hideDisciplineChip={Boolean(discipline)}
              scopeQuery={scopeQueryStr}
            />
          )}
        </div>
      </div>

      <CreateAssetDialog
        workspaceId={ws_id}
        projectId={proj_id}
        presetCollectionId={collection === 'unfiled' ? null : collection}
        canCreateDiscipline={canEditProject}
        open={createOpen}
        onOpenChange={setCreateOpen}
      />
    </div>
  )
}

function EmptyStateForFilters({
  collection,
  search,
  canCreate,
  onCreate,
  onClearSearch,
}: {
  collection: CollectionFilter
  search: string
  canCreate: boolean
  onCreate: () => void
  onClearSearch: () => void
}) {
  if (search) {
    return (
      <EmptyState
        icon={<Search className="h-8 w-8" />}
        title={`No assets match "${search}"`}
        action={
          <Button variant="secondary" size="sm" onClick={onClearSearch}>
            Clear search
          </Button>
        }
      />
    )
  }
  if (collection === 'unfiled') {
    return (
      <EmptyState
        icon={<Layers className="h-8 w-8" />}
        title="No unfiled assets"
        description="Assets without a collection show up here."
      />
    )
  }
  if (collection) {
    return (
      <EmptyState
        icon={<Layers className="h-8 w-8" />}
        title="This collection is empty"
        action={
          canCreate ? (
            <Button size="sm" onClick={onCreate}>
              <Plus className="mr-1 h-4 w-4" />
              New asset here
            </Button>
          ) : undefined
        }
      />
    )
  }
  return (
    <EmptyState
      icon={<Layers className="h-8 w-8" />}
      title="No design assets yet"
      description="Create your first asset to start iterating on designs."
      action={
        canCreate ? (
          <Button size="sm" onClick={onCreate}>
            <Plus className="mr-1 h-4 w-4" />
            New asset
          </Button>
        ) : undefined
      }
    />
  )
}
