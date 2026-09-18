import * as React from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { toast } from 'sonner'
import { Trash2 } from 'lucide-react'
import { Button } from '@/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/ui/dialog'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { invalidateVersionFiles, invalidateAssetsForProject } from '@/features/shared/invalidate'
import { humanizeError } from '@/features/shared/errors'
import { useVersionFiles } from '@/features/files/queries'
import type { AssetVersionRow } from './queries'

interface Props {
  workspaceId: string
  projectId: string
  assetId: string
  version: AssetVersionRow
  scopeQuery?: string
}

/**
 * "Discard" button for the active draft. Confirms with attachment count and
 * copy per D12; on success, navigates back to the asset root.
 */
export function DiscardDraftButton({
  workspaceId,
  projectId,
  assetId,
  version,
  scopeQuery,
}: Props) {
  const qc = useQueryClient()
  const navigate = useNavigate()
  const [open, setOpen] = React.useState(false)
  const files = useVersionFiles(version.id)
  const count = (files.data ?? []).length

  const discard = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc('discard_draft_version', {
        p_asset_version_id: version.id,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success(`v${version.sequence} discarded`)
      invalidateVersionFiles(qc, version.id)
      qc.invalidateQueries({ queryKey: qk.assetVersions(assetId) })
      qc.invalidateQueries({ queryKey: qk.assetVersion(version.id) })
      qc.invalidateQueries({ queryKey: qk.asset(assetId) })
      invalidateAssetsForProject(qc, projectId)
      setOpen(false)
      const suffix = scopeQuery ? `?${scopeQuery}` : ''
      navigate(`/workspace/${workspaceId}/project/${projectId}/asset/${assetId}${suffix}`)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  return (
    <>
      <Button variant="ghost" size="sm" onClick={() => setOpen(true)}>
        <Trash2 className="mr-1 h-4 w-4" />
        Discard
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Discard v{version.sequence}?</DialogTitle>
            <DialogDescription>
              {count > 0
                ? `Attached files (${count}) will be orphaned and removable by admin after 30 days. This can't be undone.`
                : "This draft version will be removed. It can't be undone."}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="secondary"
              size="sm"
              onClick={() => setOpen(false)}
              disabled={discard.isPending}
            >
              Cancel
            </Button>
            <Button
              size="sm"
              variant="destructive"
              onClick={() => discard.mutate()}
              disabled={discard.isPending}
            >
              {discard.isPending ? 'Discarding…' : 'Discard draft'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
