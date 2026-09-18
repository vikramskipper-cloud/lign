import { useNavigate } from 'react-router'
import { iconFor } from './mime'
import { cn } from '@/lib/cn'
import type { VersionFileRow } from './queries'

interface Props {
  workspaceId: string
  projectId: string
  assetId: string
  versionId: string
  files: VersionFileRow[]
  activeFileId: string
  scopeQuery?: string
}

/**
 * Chip strip for switching between attachments of a version. Rendered only
 * when a version has ≥2 files. Uses <button> children that navigate via
 * react-router (preserving scopeQuery + tab).
 */
export function FileSwitcher({
  workspaceId,
  projectId,
  assetId,
  versionId,
  files,
  activeFileId,
  scopeQuery,
}: Props) {
  const navigate = useNavigate()
  const suffix = scopeQuery ? `?${scopeQuery}` : ''
  return (
    <div
      className="flex items-center gap-1 overflow-x-auto border-b border-[--color-border] bg-[--color-surface] px-3 py-1.5"
      role="tablist"
      aria-label="Version files"
    >
      {files.map((vf) => {
        const Icon = iconFor(vf.file.mime_type)
        const active = vf.file.id === activeFileId
        const label = vf.display_name || `file-${vf.file.id.slice(0, 8)}`
        return (
          <button
            key={vf.id}
            type="button"
            role="tab"
            aria-selected={active}
            onClick={() =>
              navigate(
                `/workspace/${workspaceId}/project/${projectId}/asset/${assetId}/v/${versionId}/file/${vf.file.id}${suffix}`,
              )
            }
            className={cn(
              'inline-flex shrink-0 items-center gap-1.5 rounded-[--radius-sm] border px-2 py-1 text-xs',
              active
                ? 'border-[--color-border-strong] bg-[--color-surface-2] text-[--color-text]'
                : 'border-transparent text-[--color-text-muted] hover:bg-[--color-surface-2]',
            )}
            title={label}
          >
            <Icon className="h-3.5 w-3.5" />
            <span className="max-w-[10rem] truncate">{label}</span>
            {vf.role === 'primary' && (
              <span className="rounded-full bg-[--color-brand] px-1.5 py-0.5 text-[9px] font-medium uppercase text-[--color-brand-fg]">
                Main
              </span>
            )}
          </button>
        )
      })}
    </div>
  )
}
