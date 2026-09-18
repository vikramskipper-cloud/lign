import * as React from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Plus, X, Loader2, CircleAlert, CheckCircle2, Trash2, GripVertical } from 'lucide-react'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import { supabase } from '@/lib/supabase'
import { invalidateVersionFiles, invalidateAssetsForProject } from '@/features/shared/invalidate'
import { humanizeError } from '@/features/shared/errors'
import { qk } from '@/lib/queryKeys'
import { useUploadQueue, type UploadItem } from './useUploadQueue'
import { formatBytes, iconFor, labelFor, ROLES, ROLE_LABELS, type FileRole } from './mime'
import type { VersionFileRow } from './queries'
import { cn } from '@/lib/cn'

interface Props {
  versionId: string
  projectId: string
  assetId: string
  files: VersionFileRow[]
  canAttach: boolean
  canDetach: boolean
}

/**
 * Persistent dock at the bottom of the workspace during a draft. Renders:
 *   - list of currently-attached files (row = read/edit inline)
 *   - in-flight uploads with per-file progress
 *   - "+ Add files" button and drag-drop target
 */
export function UploadDock({ versionId, projectId, assetId, files, canAttach, canDetach }: Props) {
  const inputRef = React.useRef<HTMLInputElement | null>(null)
  const [isDragOver, setIsDragOver] = React.useState(false)
  const queue = useUploadQueue({ versionId, projectId, assetId })
  const qc = useQueryClient()

  const detach = useMutation({
    mutationFn: async (vfId: string) => {
      const { error } = await supabase.from('version_files').delete().eq('id', vfId)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('File removed from draft')
      invalidateVersionFiles(qc, versionId)
      qc.invalidateQueries({ queryKey: qk.assetVersion(versionId) })
      invalidateAssetsForProject(qc, projectId)
      qc.invalidateQueries({ queryKey: qk.asset(assetId) })
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const setRole = useMutation({
    mutationFn: async ({
      vfId,
      role,
      demoteOthers,
    }: {
      vfId: string
      role: FileRole
      demoteOthers: boolean
    }) => {
      // D4: single-primary UI invariant. If promoting, demote all existing
      // primaries in the same version to 'reference' first.
      if (demoteOthers) {
        const otherPrimaries = files
          .filter((f) => f.id !== vfId && f.role === 'primary')
          .map((f) => f.id)
        if (otherPrimaries.length > 0) {
          const { error } = await supabase
            .from('version_files')
            .update({ role: 'reference' })
            .in('id', otherPrimaries)
          if (error) throw error
        }
      }
      const { error } = await supabase
        .from('version_files')
        .update({ role })
        .eq('id', vfId)
      if (error) throw error
    },
    onSuccess: () => {
      invalidateVersionFiles(qc, versionId)
      invalidateAssetsForProject(qc, projectId)
      qc.invalidateQueries({ queryKey: qk.asset(assetId) })
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const rename = useMutation({
    mutationFn: async ({ vfId, name }: { vfId: string; name: string }) => {
      const { error } = await supabase
        .from('version_files')
        .update({ display_name: name || null })
        .eq('id', vfId)
      if (error) throw error
    },
    onSuccess: () => invalidateVersionFiles(qc, versionId),
    onError: (err) => toast.error(humanizeError(err)),
  })

  const reorder = useMutation({
    mutationFn: async (orderedIds: string[]) => {
      // Two-phase to dodge the UNIQUE (asset_version_id, sort_order) constraint:
      // first bump every affected row to a high offset (id order stable), then
      // rewrite to the final compact values.
      const offset = 10_000
      for (let i = 0; i < orderedIds.length; i++) {
        const { error } = await supabase
          .from('version_files')
          .update({ sort_order: offset + i })
          .eq('id', orderedIds[i]!)
        if (error) throw error
      }
      for (let i = 0; i < orderedIds.length; i++) {
        const { error } = await supabase
          .from('version_files')
          .update({ sort_order: i })
          .eq('id', orderedIds[i]!)
        if (error) throw error
      }
    },
    onSuccess: () => invalidateVersionFiles(qc, versionId),
    onError: (err) => toast.error(humanizeError(err)),
  })

  const [dragId, setDragId] = React.useState<string | null>(null)

  function onDragStart(id: string) {
    setDragId(id)
  }
  function onDragOverRow(e: React.DragEvent, targetId: string) {
    if (!dragId || dragId === targetId) return
    e.preventDefault()
  }
  function onDropRow(e: React.DragEvent, targetId: string) {
    e.preventDefault()
    if (!dragId || dragId === targetId) return
    const orderedIds = files.map((f) => f.id)
    const from = orderedIds.indexOf(dragId)
    const to = orderedIds.indexOf(targetId)
    if (from < 0 || to < 0) return
    const next = [...orderedIds]
    next.splice(from, 1)
    next.splice(to, 0, dragId)
    setDragId(null)
    reorder.mutate(next)
  }

  const openPicker = () => inputRef.current?.click()

  const onPickerChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const list = e.target.files
    if (!list || list.length === 0) return
    queue.enqueue(Array.from(list))
    e.target.value = ''
  }

  const onDrop = (e: React.DragEvent) => {
    e.preventDefault()
    setIsDragOver(false)
    if (!canAttach) return
    const list = e.dataTransfer.files
    if (!list || list.length === 0) return
    queue.enqueue(Array.from(list))
  }

  const uploading = queue.items.filter((it) => it.phase !== 'done')

  return (
    <div
      className={cn(
        'flex max-h-[40vh] flex-col border-t border-[--color-border] bg-[--color-surface]',
        isDragOver && canAttach && 'ring-2 ring-inset ring-[--color-brand]',
      )}
      onDragOver={(e) => {
        if (!canAttach) return
        e.preventDefault()
        setIsDragOver(true)
      }}
      onDragLeave={() => setIsDragOver(false)}
      onDrop={onDrop}
    >
      <div className="flex items-center justify-between border-b border-[--color-border] px-3 py-1.5 text-xs">
        <div className="flex items-center gap-2">
          <span className="font-medium text-[--color-text]">Draft files</span>
          <span className="text-[--color-text-subtle]">
            {files.length} attached
            {uploading.length > 0 ? ` · ${uploading.length} uploading` : ''}
          </span>
        </div>
        <div className="flex items-center gap-1">
          {uploading.length === 0 && queue.items.length > 0 && (
            <Button variant="ghost" size="sm" onClick={queue.clearFinished}>
              Clear
            </Button>
          )}
          {canAttach && (
            <Button size="sm" variant="secondary" onClick={openPicker}>
              <Plus className="mr-1 h-3.5 w-3.5" />
              Add files
            </Button>
          )}
          <input
            ref={inputRef}
            type="file"
            multiple
            className="hidden"
            onChange={onPickerChange}
          />
        </div>
      </div>

      <div className="flex-1 overflow-y-auto">
        {files.length === 0 && queue.items.length === 0 && (
          <p className="px-3 py-4 text-xs text-[--color-text-subtle]">
            Drop files here or click "Add files" to attach.
          </p>
        )}

        {files.length > 0 && (
          <ul className="space-y-0.5 p-2">
            {files.map((vf) => (
              <AttachedRow
                key={vf.id}
                vf={vf}
                onSetRole={(role) =>
                  setRole.mutate({ vfId: vf.id, role, demoteOthers: role === 'primary' })
                }
                onRename={(name) => rename.mutate({ vfId: vf.id, name })}
                onDetach={canDetach ? () => detach.mutate(vf.id) : undefined}
                onDragStart={() => onDragStart(vf.id)}
                onDragOver={(e) => onDragOverRow(e, vf.id)}
                onDrop={(e) => onDropRow(e, vf.id)}
                isDragging={dragId === vf.id}
              />
            ))}
          </ul>
        )}

        {queue.items.length > 0 && (
          <ul className="space-y-0.5 border-t border-[--color-border] p-2">
            {queue.items.map((it) => (
              <UploadRow
                key={it.id}
                item={it}
                onRetry={() => queue.retry(it.id)}
                onRemove={() => queue.removeItem(it.id)}
                onSetRole={(role) => queue.setRole(it.id, role)}
              />
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}

function AttachedRow({
  vf,
  onSetRole,
  onRename,
  onDetach,
  onDragStart,
  onDragOver,
  onDrop,
  isDragging,
}: {
  vf: VersionFileRow
  onSetRole: (role: FileRole) => void
  onRename: (name: string) => void
  onDetach?: () => void
  onDragStart: () => void
  onDragOver: (e: React.DragEvent) => void
  onDrop: (e: React.DragEvent) => void
  isDragging: boolean
}) {
  const [name, setName] = React.useState(vf.display_name ?? '')
  const [editing, setEditing] = React.useState(false)
  const Icon = iconFor(vf.file.mime_type)
  const filename = vf.display_name || `file-${vf.file.id.slice(0, 8)}`
  React.useEffect(() => setName(vf.display_name ?? ''), [vf.display_name])

  return (
    <li
      draggable
      onDragStart={onDragStart}
      onDragOver={onDragOver}
      onDrop={onDrop}
      className={cn(
        'flex items-center gap-2 rounded-[--radius-sm] px-2 py-1.5 text-xs hover:bg-[--color-surface-2]',
        isDragging && 'opacity-50',
      )}
    >
      <GripVertical className="h-3.5 w-3.5 shrink-0 cursor-grab text-[--color-text-subtle]" />
      <Icon className="h-4 w-4 shrink-0 text-[--color-text-muted]" />
      <div className="min-w-0 flex-1">
        {editing ? (
          <Input
            className="h-6 text-xs"
            value={name}
            onChange={(e) => setName(e.target.value)}
            autoFocus
            onBlur={() => {
              setEditing(false)
              if ((name || '') !== (vf.display_name ?? '')) onRename(name)
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                setEditing(false)
                if ((name || '') !== (vf.display_name ?? '')) onRename(name)
              }
              if (e.key === 'Escape') {
                setName(vf.display_name ?? '')
                setEditing(false)
              }
            }}
          />
        ) : (
          <button
            type="button"
            onClick={() => setEditing(true)}
            className="truncate text-left font-medium"
            title="Rename"
          >
            {filename}
          </button>
        )}
        <p className="text-[10px] text-[--color-text-subtle]">
          {labelFor(vf.file.mime_type, filename)} · {formatBytes(vf.file.size_bytes)}
        </p>
      </div>
      <RoleDropdown value={vf.role} onChange={onSetRole} />
      {onDetach && (
        <Button
          variant="ghost"
          size="icon"
          className="h-7 w-7 text-[--color-text-muted]"
          aria-label={`Remove ${filename}`}
          onClick={() => {
            if (window.confirm(`Remove "${filename}" from this draft?`)) onDetach()
          }}
        >
          <Trash2 className="h-3.5 w-3.5" />
        </Button>
      )}
    </li>
  )
}

function UploadRow({
  item,
  onRetry,
  onRemove,
  onSetRole,
}: {
  item: UploadItem
  onRetry: () => void
  onRemove: () => void
  onSetRole: (role: FileRole) => void
}) {
  const Icon = iconFor(item.mime)
  return (
    <li className="flex items-center gap-2 rounded-[--radius-sm] px-2 py-1.5 text-xs">
      <Icon className="h-4 w-4 shrink-0 text-[--color-text-muted]" />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate font-medium">{item.name}</span>
          <PhaseChip phase={item.phase} />
        </div>
        {item.phase !== 'error' && item.phase !== 'done' && (
          <div className="mt-1 h-1 w-full overflow-hidden rounded-full bg-[--color-surface-2]">
            <div
              className="h-full bg-[--color-brand] transition-[width]"
              style={{ width: `${Math.round((item.progress ?? 0) * 100)}%` }}
            />
          </div>
        )}
        {item.error && (
          <p className="mt-0.5 text-[10px] text-[--color-danger]">{item.error}</p>
        )}
        {item.phase !== 'error' && (
          <p className="mt-0.5 text-[10px] text-[--color-text-subtle]">
            {formatBytes(item.size)}
          </p>
        )}
      </div>
      {(item.phase === 'queued' || item.phase === 'error') && (
        <RoleDropdown value={item.role} onChange={onSetRole} />
      )}
      {item.phase === 'error' && (
        <Button variant="ghost" size="sm" onClick={onRetry}>
          Retry
        </Button>
      )}
      {item.phase !== 'done' && item.phase !== 'uploading' && item.phase !== 'finalizing' && (
        <Button
          variant="ghost"
          size="icon"
          className="h-7 w-7"
          aria-label="Remove from queue"
          onClick={onRemove}
        >
          <X className="h-3.5 w-3.5" />
        </Button>
      )}
    </li>
  )
}

function PhaseChip({ phase }: { phase: UploadItem['phase'] }) {
  if (phase === 'done') {
    return (
      <span className="inline-flex items-center gap-0.5 text-[10px] text-[--color-success]">
        <CheckCircle2 className="h-3 w-3" />
        Attached
      </span>
    )
  }
  if (phase === 'error') {
    return (
      <span className="inline-flex items-center gap-0.5 text-[10px] text-[--color-danger]">
        <CircleAlert className="h-3 w-3" />
        Failed
      </span>
    )
  }
  return (
    <span className="inline-flex items-center gap-1 text-[10px] text-[--color-text-muted]">
      <Loader2 className="h-3 w-3 animate-spin" />
      {phase[0]!.toUpperCase() + phase.slice(1)}
    </span>
  )
}

function RoleDropdown({
  value,
  onChange,
}: {
  value: FileRole
  onChange: (role: FileRole) => void
}) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="sm" className="h-7 whitespace-nowrap px-2 text-[10px]">
          {ROLE_LABELS[value]}
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {ROLES.map((r) => (
          <DropdownMenuItem key={r} onSelect={() => onChange(r)}>
            {ROLE_LABELS[r]}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
