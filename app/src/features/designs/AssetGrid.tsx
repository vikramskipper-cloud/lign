import { useAssetVersionsBySequence } from './useAssetVersionsBySequence'
import { AssetCard } from './AssetCard'
import type { AssetRow } from './queries'
import type { DisciplineRow } from '@/features/disciplines/queries'

interface Props {
  workspaceId: string
  projectId: string
  assets: AssetRow[]
  disciplines: DisciplineRow[]
  hideDisciplineChip: boolean
  scopeQuery?: string
}

export function AssetGrid({
  workspaceId,
  projectId,
  assets,
  disciplines,
  hideDisciplineChip,
  scopeQuery,
}: Props) {
  const disciplineMap = new Map(disciplines.map((d) => [d.id, d.name]))
  const currentVersionIds = assets
    .map((a) => a.current_version_id)
    .filter((v): v is string => Boolean(v))
  const versionsBySeq = useAssetVersionsBySequence(currentVersionIds)

  return (
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {assets.map((a) => (
        <AssetCard
          key={a.id}
          workspaceId={workspaceId}
          projectId={projectId}
          asset={a}
          disciplineName={a.discipline_id ? disciplineMap.get(a.discipline_id) : undefined}
          currentVersionSequence={
            a.current_version_id ? versionsBySeq.get(a.current_version_id) : undefined
          }
          hideDisciplineChip={hideDisciplineChip}
          scopeQuery={scopeQuery}
        />
      ))}
    </div>
  )
}
