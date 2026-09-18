import * as React from 'react'
import { useQuery } from '@tanstack/react-query'
import { Check, Loader2 } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import { useSetRequirementApplicability } from './mutations'

interface Props {
  workspaceId: string
  projectId: string
  requirementId: string
  parentRequirementId: string | null
  currentAssetIds: string[]
  canEdit: boolean
}

interface AssetPickRow {
  id: string
  name: string
  code: string | null
  status: string
}

/**
 * APP 008 §11.3 primitive: root-only applicability editor. Sub-requirements
 * inherit from the parent (frozen guard); the UI renders a read-only notice
 * for those cases and a link back to the parent.
 */
export function RequirementApplicabilityEditor({
  workspaceId,
  projectId,
  requirementId,
  parentRequirementId,
  currentAssetIds,
  canEdit,
}: Props) {
  const isSub = Boolean(parentRequirementId)

  const [selected, setSelected] = React.useState<Set<string>>(
    () => new Set(currentAssetIds),
  )
  const [search, setSearch] = React.useState('')

  React.useEffect(() => {
    setSelected(new Set(currentAssetIds))
  }, [currentAssetIds])

  const assetsQ = useQuery({
    queryKey: ['project', projectId, 'assets-picker'],
    enabled: Boolean(projectId) && !isSub,
    queryFn: async (): Promise<AssetPickRow[]> => {
      const { data, error } = await supabase
        .from('design_assets')
        .select('id, name, code, status')
        .eq('project_id', projectId)
        .eq('workspace_id', workspaceId)
        .neq('status', 'archived')
        .order('name', { ascending: true })
      if (error) throw error
      return (data ?? []) as AssetPickRow[]
    },
  })

  const setApp = useSetRequirementApplicability(workspaceId, projectId)

  if (isSub) {
    return (
      <div className="rounded-[--radius-md] border border-dashed border-[--color-border] bg-[--color-surface-2] p-4 text-sm text-[--color-text-muted]">
        <p>
          Sub-requirements inherit applicability from their parent.
        </p>
      </div>
    )
  }

  const filtered = (assetsQ.data ?? []).filter((a) => {
    if (!search.trim()) return true
    const needle = search.trim().toLowerCase()
    return (
      a.name.toLowerCase().includes(needle) ||
      (a.code ?? '').toLowerCase().includes(needle)
    )
  })

  const toggle = (id: string) => {
    if (!canEdit) return
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  const dirty =
    selected.size !== currentAssetIds.length ||
    currentAssetIds.some((id) => !selected.has(id))

  const save = () => {
    setApp.mutate({
      requirementId,
      designAssetIds: Array.from(selected),
    })
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2 text-xs text-[--color-text-muted]">
        <span>
          {selected.size === 0
            ? 'Project-wide (applies to every design asset in the project).'
            : `Scoped to ${selected.size} asset${
                selected.size === 1 ? '' : 's'
              }.`}
        </span>
        {canEdit && (
          <div className="ml-auto flex gap-2">
            <Button
              size="sm"
              variant="secondary"
              disabled={!dirty}
              onClick={() => setSelected(new Set())}
            >
              Clear (project-wide)
            </Button>
            <Button
              size="sm"
              disabled={!dirty || setApp.isPending}
              onClick={save}
            >
              {setApp.isPending ? (
                <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" />
              ) : null}
              Save
            </Button>
          </div>
        )}
      </div>
      <Input
        placeholder="Search assets"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />
      {assetsQ.isLoading ? (
        <p className="text-sm text-[--color-text-muted]">Loading assets…</p>
      ) : filtered.length === 0 ? (
        <p className="text-sm text-[--color-text-muted]">
          No assets in this project.
        </p>
      ) : (
        <ul className="max-h-96 divide-y divide-[--color-border] overflow-auto rounded-[--radius-md] border border-[--color-border]">
          {filtered.map((a) => {
            const isSel = selected.has(a.id)
            return (
              <li
                key={a.id}
                className={
                  'flex cursor-pointer items-center gap-2 px-3 py-2 text-sm ' +
                  (isSel
                    ? 'bg-[--color-surface-2] hover:bg-[--color-surface-2]'
                    : 'hover:bg-[--color-surface-2]')
                }
                onClick={() => toggle(a.id)}
                aria-checked={isSel}
                role="checkbox"
              >
                <span
                  className={
                    'flex h-4 w-4 items-center justify-center rounded border ' +
                    (isSel
                      ? 'border-[--color-state-open] bg-[--color-state-open] text-white'
                      : 'border-[--color-border]')
                  }
                >
                  {isSel && <Check className="h-3 w-3" />}
                </span>
                <span className="flex-1 truncate">{a.name}</span>
                {a.code && (
                  <span className="font-mono text-[10px] text-[--color-text-subtle]">
                    {a.code}
                  </span>
                )}
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
