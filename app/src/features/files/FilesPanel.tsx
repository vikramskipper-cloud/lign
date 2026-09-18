import { Link } from 'react-router'
import { Download } from 'lucide-react'
import { Button } from '@/ui/button'
import { EmptyState } from '@/ui/empty-state'
import { iconFor, formatBytes, labelFor, ROLE_LABELS } from './mime'
import type { VersionFileRow } from './queries'
import { cn } from '@/lib/cn'

interface Props {
  workspaceId: string
  projectId: string
  assetId: string
  versionId: string | null
  files: VersionFileRow[]
  activeFileId: string | null
  isDraft: boolean
  scopeQuery?: string
  actions?: (vf: VersionFileRow) => React.ReactNode
}

/**
 * Read-only list of a version's attachments for the right-panel Files tab.
 * When `isDraft`, callers may pass `actions` to render per-row draft controls
 * (see UploadDock for the writable variant).
 */
export function FilesPanel({
  workspaceId,
  projectId,
  assetId,
  versionId,
  files,
  activeFileId,
  isDraft,
  scopeQuery,
  actions,
}: Props) {
  if (!versionId) {
    return (
      <EmptyState
        title="No version selected"
        description="Pick a version to see its files."
        className="mx-3 mt-3"
      />
    )
  }
  if (files.length === 0) {
    return (
      <EmptyState
        title={isDraft ? 'No files attached yet' : 'No files in this version'}
        description={
          isDraft
            ? 'Drop files onto the viewer or use "Add files" below.'
            : 'This version has no attachments.'
        }
        className="mx-3 mt-3"
      />
    )
  }
  const suffix = scopeQuery ? `?${scopeQuery}` : ''

  return (
    <ul className="space-y-1 p-3">
      {files.map((vf) => {
        const Icon = iconFor(vf.file.mime_type)
        const active = vf.file.id === activeFileId
        const filename = vf.display_name || `file-${vf.file.id.slice(0, 8)}`
        return (
          <li key={vf.id}>
            <div
              className={cn(
                'group flex items-start gap-2 rounded-[--radius-sm] border border-transparent p-2 text-sm hover:bg-[--color-surface-2]',
                active && 'border-[--color-border-strong] bg-[--color-surface-2]',
              )}
            >
              <div className="h-8 w-8 shrink-0">
                <Icon className="h-8 w-8 rounded-[--radius-sm] bg-[--color-surface-2] p-1.5 text-[--color-text-muted]" />
              </div>
              <div className="min-w-0 flex-1">
                <Link
                  to={`/workspace/${workspaceId}/project/${projectId}/asset/${assetId}/v/${versionId}/file/${vf.file.id}${suffix}`}
                  className="block truncate font-medium outline-none"
                  title={filename}
                >
                  {filename}
                </Link>
                <div className="mt-0.5 flex flex-wrap items-center gap-1.5 text-[11px] text-[--color-text-subtle]">
                  <span className="rounded bg-[--color-surface] px-1 py-0.5 font-mono text-[10px]">
                    {labelFor(vf.file.mime_type, filename)}
                  </span>
                  <span>{ROLE_LABELS[vf.role]}</span>
                  <span aria-hidden>·</span>
                  <span>{formatBytes(vf.file.size_bytes)}</span>
                </div>
              </div>
              {actions ? (
                actions(vf)
              ) : (
                <Button
                  asChild
                  variant="ghost"
                  size="icon"
                  className="h-7 w-7 opacity-0 group-hover:opacity-100 focus-visible:opacity-100"
                  aria-label={`Open ${filename}`}
                >
                  <Link
                    to={`/workspace/${workspaceId}/project/${projectId}/asset/${assetId}/v/${versionId}/file/${vf.file.id}${suffix}`}
                  >
                    <Download className="h-3.5 w-3.5" />
                  </Link>
                </Button>
              )}
            </div>
          </li>
        )
      })}
    </ul>
  )
}
