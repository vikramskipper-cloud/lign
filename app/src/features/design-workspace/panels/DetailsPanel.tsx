import * as React from 'react'
import { useNavigate } from 'react-router'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Pencil, Archive, FolderInput, MoreVertical } from 'lucide-react'
import { Button } from '@/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import * as Popover from '@radix-ui/react-popover'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { invalidateAssetsForProject, invalidateNeighborsForAsset } from '@/features/shared/invalidate'
import { humanizeError } from '@/features/shared/errors'
import { EditAssetDialog } from '@/features/designs/EditAssetDialog'
import { DisciplineCombobox } from '@/features/disciplines/DisciplineCombobox'
import { relative, absolute } from '@/lib/formatDate'
import { StatusBadge } from '@/features/shared/StatusBadge'
import type { AssetRow } from '@/features/designs/queries'
import type { CollectionRow } from '@/features/collections/queries'
import type { DisciplineRow } from '@/features/disciplines/queries'
import { cn } from '@/lib/cn'

interface Props {
  asset: AssetRow
  collections: CollectionRow[]
  disciplines: DisciplineRow[]
  canEdit: boolean
  canArchive: boolean
  canEditProject: boolean
}

export function DetailsPanel({
  asset,
  collections,
  disciplines,
  canEdit,
  canArchive,
  canEditProject,
}: Props) {
  const qc = useQueryClient()
  const navigate = useNavigate()
  const [editOpen, setEditOpen] = React.useState(false)

  const setCollection = useMutation({
    mutationFn: async (collectionId: string | null) => {
      const { error } = await supabase
        .from('design_assets')
        .update({ collection_id: collectionId })
        .eq('id', asset.id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Collection updated')
      qc.invalidateQueries({ queryKey: qk.asset(asset.id) })
      invalidateAssetsForProject(qc, asset.project_id)
      invalidateNeighborsForAsset(qc, asset.id)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const setDiscipline = useMutation({
    mutationFn: async (disciplineId: string | null) => {
      const { error } = await supabase
        .from('design_assets')
        .update({ discipline_id: disciplineId })
        .eq('id', asset.id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Discipline updated')
      qc.invalidateQueries({ queryKey: qk.asset(asset.id) })
      invalidateAssetsForProject(qc, asset.project_id)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const archive = useMutation({
    mutationFn: async () => {
      const { error } = await supabase
        .from('design_assets')
        .update({ status: 'archived', archived_at: new Date().toISOString() })
        .eq('id', asset.id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Asset archived')
      invalidateAssetsForProject(qc, asset.project_id)
      qc.invalidateQueries({ queryKey: qk.asset(asset.id) })
      invalidateNeighborsForAsset(qc, asset.id)
      navigate(`/workspace/${asset.workspace_id}/project/${asset.project_id}/designs`)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const collection = collections.find((c) => c.id === asset.collection_id)
  const discipline = disciplines.find((d) => d.id === asset.discipline_id)

  return (
    <div className="space-y-4 p-3 text-sm">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 space-y-0.5">
          <p className="text-xs uppercase tracking-wide text-[--color-text-subtle]">Asset</p>
          <p className="truncate text-sm font-semibold">{asset.name}</p>
          {asset.code && (
            <p className="font-mono text-xs text-[--color-text-muted]">{asset.code}</p>
          )}
        </div>
        {(canEdit || canArchive) && (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon" aria-label="Asset actions" className="h-7 w-7">
                <MoreVertical className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              {canEdit && (
                <DropdownMenuItem onSelect={() => setEditOpen(true)}>
                  <Pencil className="h-4 w-4" />
                  Edit details
                </DropdownMenuItem>
              )}
              {canArchive && (
                <DropdownMenuItem
                  className="text-[--color-danger]"
                  onSelect={() => {
                    if (window.confirm('Archive this asset?')) archive.mutate()
                  }}
                >
                  <Archive className="h-4 w-4" />
                  Archive asset
                </DropdownMenuItem>
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </div>

      {asset.description && (
        <p className="text-xs text-[--color-text-muted]">{asset.description}</p>
      )}

      <Field label="Status">
        <StatusBadge status={asset.status} />
      </Field>

      <Field label="Discipline">
        {canEdit ? (
          <DisciplineCombobox
            workspaceId={asset.workspace_id}
            projectId={asset.project_id}
            value={asset.discipline_id}
            onChange={(id) => setDiscipline.mutate(id)}
            canCreate={canEditProject}
            allowNone
            disabled={setDiscipline.isPending}
          />
        ) : (
          <span>{discipline?.name ?? <Muted>—</Muted>}</span>
        )}
      </Field>

      <Field label="Collection">
        {canEdit ? (
          <CollectionPicker
            collections={collections}
            value={asset.collection_id}
            onChange={(id) => setCollection.mutate(id)}
            disabled={setCollection.isPending}
          />
        ) : (
          <span>{collection?.name ?? <Muted>Unfiled</Muted>}</span>
        )}
      </Field>

      <Field label="Created">
        <span title={absolute(asset.created_at)}>{relative(asset.created_at)}</span>
      </Field>
      <Field label="Updated">
        <span title={absolute(asset.updated_at)}>{relative(asset.updated_at)}</span>
      </Field>

      <EditAssetDialog asset={asset} open={editOpen} onOpenChange={setEditOpen} />
    </div>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1">
      <p className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">{label}</p>
      <div className="min-h-[24px]">{children}</div>
    </div>
  )
}
function Muted({ children }: { children: React.ReactNode }) {
  return <span className="text-[--color-text-subtle]">{children}</span>
}

function CollectionPicker({
  collections,
  value,
  onChange,
  disabled,
}: {
  collections: CollectionRow[]
  value: string | null
  onChange: (id: string | null) => void
  disabled?: boolean
}) {
  const [open, setOpen] = React.useState(false)
  const selected = collections.find((c) => c.id === value)
  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Popover.Trigger asChild>
        <Button variant="secondary" size="sm" disabled={disabled} className="w-full justify-between font-normal">
          <span className={cn(!selected && 'text-[--color-text-muted]')}>
            {selected?.name ?? 'Unfiled'}
          </span>
          <FolderInput className="ml-1 h-3.5 w-3.5 shrink-0" />
        </Button>
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content
          sideOffset={4}
          align="start"
          className="z-50 w-[--radix-popover-trigger-width] min-w-[12rem] rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-1 shadow-[--shadow-md]"
        >
          <button
            type="button"
            onClick={() => {
              onChange(null)
              setOpen(false)
            }}
            className="flex w-full items-center rounded-[--radius-sm] px-2 py-1.5 text-left text-sm hover:bg-[--color-surface-2]"
          >
            <span className="text-[--color-text-muted]">Unfiled</span>
          </button>
          {collections.length > 0 && <div className="my-1 h-px bg-[--color-border]" />}
          {collections.map((c) => (
            <button
              key={c.id}
              type="button"
              onClick={() => {
                onChange(c.id)
                setOpen(false)
              }}
              className="flex w-full items-center rounded-[--radius-sm] px-2 py-1.5 text-left text-sm hover:bg-[--color-surface-2]"
            >
              {c.name}
            </button>
          ))}
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  )
}
