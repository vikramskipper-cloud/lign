import { useNavigate } from 'react-router'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { ChevronDown, Check, Star, MoreVertical, Plus, PenLine } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import { StatusBadge } from '@/features/shared/StatusBadge'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { invalidateAssetsForProject } from '@/features/shared/invalidate'
import { humanizeError } from '@/features/shared/errors'
import { relative } from '@/lib/formatDate'
import type { AssetVersionRow } from './queries'

interface Props {
  workspaceId: string
  projectId: string
  assetId: string
  assetName: string
  activeVersion: AssetVersionRow | null
  versions: AssetVersionRow[]
  currentVersionId: string | null
  canSetCurrent: boolean
  canCreateVersion: boolean
  scopeQuery?: string
}

export function VersionMenu({
  workspaceId,
  projectId,
  assetId,
  assetName,
  activeVersion,
  versions,
  currentVersionId,
  canSetCurrent,
  canCreateVersion,
  scopeQuery,
}: Props) {
  const navigate = useNavigate()
  const qc = useQueryClient()

  const setCurrent = useMutation({
    mutationFn: async (versionId: string) => {
      const { error } = await supabase.rpc('set_current_version', {
        p_design_asset_id: assetId,
        p_version_id: versionId,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Current version updated')
      qc.invalidateQueries({ queryKey: qk.asset(assetId) })
      invalidateAssetsForProject(qc, projectId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const createDraft = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc('create_draft_version', {
        p_project_id: projectId,
        p_design_asset_id: assetId,
        p_label: null,
        p_notes: null,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: (versionId) => {
      toast.success('Draft version created')
      qc.invalidateQueries({ queryKey: qk.assetVersions(assetId) })
      navigate(
        `/workspace/${workspaceId}/project/${projectId}/asset/${assetId}/v/${versionId}${suffix}`,
      )
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const label = activeVersion
    ? `v${activeVersion.sequence}${activeVersion.label ? ` · ${activeVersion.label}` : ''}`
    : 'No version'

  const suffix = scopeQuery ? `?${scopeQuery}` : ''
  const existingDraft = versions.find((v) => v.status === 'draft')

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="secondary" size="sm">
          <span className="truncate max-w-[16rem]">{label}</span>
          {activeVersion && <StatusBadge status={activeVersion.status} />}
          <ChevronDown className="ml-1 h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="min-w-[18rem]">
        {canCreateVersion && (
          <>
            {existingDraft ? (
              <DropdownMenuItem
                onSelect={() =>
                  navigate(
                    `/workspace/${workspaceId}/project/${projectId}/asset/${assetId}/v/${existingDraft.id}${suffix}`,
                  )
                }
              >
                <PenLine className="h-4 w-4" />
                Continue draft v{existingDraft.sequence}
              </DropdownMenuItem>
            ) : (
              <DropdownMenuItem
                onSelect={() => createDraft.mutate()}
                disabled={createDraft.isPending}
              >
                <Plus className="h-4 w-4" />
                New draft version
              </DropdownMenuItem>
            )}
            <DropdownMenuSeparator />
          </>
        )}
        <DropdownMenuLabel>Versions of {assetName}</DropdownMenuLabel>
        {versions.length === 0 ? (
          <div className="px-2 py-3 text-xs text-[--color-text-subtle]">No versions yet.</div>
        ) : (
          versions.map((v) => {
            const isCurrent = v.id === currentVersionId
            const isActive = v.id === activeVersion?.id
            return (
              <div key={v.id} className="flex items-stretch">
                <button
                  type="button"
                  onClick={() =>
                    navigate(
                      `/workspace/${workspaceId}/project/${projectId}/asset/${assetId}/v/${v.id}${suffix}`,
                    )
                  }
                  className="flex flex-1 items-center gap-2 rounded-[--radius-sm] px-2 py-1.5 text-left text-sm hover:bg-[--color-surface-2]"
                >
                  <span className="font-mono text-xs text-[--color-text-muted]">v{v.sequence}</span>
                  {v.label && <span className="truncate">{v.label}</span>}
                  <span className="ml-auto flex items-center gap-1.5">
                    {isCurrent && (
                      <span className="inline-flex items-center gap-0.5 text-xs text-[--color-text-muted]">
                        <Star className="h-3 w-3" />
                        current
                      </span>
                    )}
                    <StatusBadge status={v.status} />
                    {v.published_at && (
                      <span className="text-xs text-[--color-text-subtle]">
                        {relative(v.published_at)}
                      </span>
                    )}
                    {isActive && <Check className="h-3.5 w-3.5 text-[--color-brand]" />}
                  </span>
                </button>
                {canSetCurrent && (
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8"
                        aria-label={`Actions for v${v.sequence}`}
                        onClick={(e) => e.stopPropagation()}
                      >
                        <MoreVertical className="h-3.5 w-3.5" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem
                        disabled={v.status !== 'published' || isCurrent}
                        onSelect={() => setCurrent.mutate(v.id)}
                      >
                        <Star className="h-4 w-4" />
                        {isCurrent ? 'Already current' : 'Mark as current'}
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                )}
              </div>
            )
          })
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
