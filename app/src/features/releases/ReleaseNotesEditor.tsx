import * as React from 'react'
import { Button } from '@/ui/button'
import { useEditReleaseDraftMetadata } from './mutations'
import type { ReleaseDetail } from './queries'

interface Props {
  workspaceId: string
  projectId: string
  release: ReleaseDetail
  canEdit: boolean
}

/**
 * Draft-time notes editor. Uses the frozen RLS UPDATE policy (no RPC wrapper in
 * v1 — the reserved `edit_release_metadata` RPC is Wave 4 per §14.9). Post-
 * release edits are hidden entirely (Freeze Index G-2).
 */
export function ReleaseNotesEditor({
  workspaceId,
  projectId,
  release,
  canEdit,
}: Props) {
  const [value, setValue] = React.useState(release.notes ?? '')
  const [dirty, setDirty] = React.useState(false)
  const edit = useEditReleaseDraftMetadata(workspaceId, projectId)

  if (release.status !== 'draft') {
    return (
      <div className="rounded-[--radius-sm] border border-[--color-border] p-3 text-xs">
        <div className="mb-1 text-[10px] uppercase tracking-wide text-[--color-text-subtle]">
          Notes
        </div>
        {release.notes ? (
          <p className="whitespace-pre-wrap text-[--color-text]">
            {release.notes}
          </p>
        ) : (
          <p className="text-[--color-text-subtle]">No notes.</p>
        )}
        <p className="mt-2 text-[10px] text-[--color-text-subtle]">
          Notes are frozen once the release leaves draft. Post-release edits will
          become available when the reserved `release.notes_updated` event ships.
        </p>
      </div>
    )
  }

  if (!canEdit) {
    return (
      <div className="rounded-[--radius-sm] border border-[--color-border] p-3 text-xs">
        <p className="text-[--color-text-muted]">
          {release.notes ?? 'No notes.'}
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-2">
      <textarea
        className="min-h-32 w-full rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface] px-2 py-1.5 text-sm outline-none focus-visible:ring-1 focus-visible:ring-[--color-border-strong]"
        value={value}
        onChange={(e) => {
          setValue(e.target.value)
          setDirty(true)
        }}
        placeholder="Changelog, distribution instructions, context…"
      />
      <div className="flex items-center gap-2">
        <Button
          size="sm"
          disabled={!dirty || edit.isPending}
          onClick={async () => {
            await edit.mutateAsync({
              releaseId: release.id,
              notes: value || null,
            })
            setDirty(false)
          }}
        >
          Save notes
        </Button>
        {dirty && (
          <Button
            size="sm"
            variant="ghost"
            onClick={() => {
              setValue(release.notes ?? '')
              setDirty(false)
            }}
          >
            Discard
          </Button>
        )}
      </div>
    </div>
  )
}
