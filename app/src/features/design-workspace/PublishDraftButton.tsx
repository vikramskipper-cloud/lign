import * as React from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { CheckCircle2 } from 'lucide-react'
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
import { invalidateAssetsForProject, invalidateVersionFiles } from '@/features/shared/invalidate'
import { humanizeError } from '@/features/shared/errors'
import { useVersionFiles } from '@/features/files/queries'
import type { AssetVersionRow } from './queries'

interface Props {
  workspaceId: string
  projectId: string
  assetId: string
  version: AssetVersionRow
  currentVersionId: string | null
  canSetCurrent: boolean
}

/**
 * "Publish" button for the active draft. Emits publish_version and, on
 * success, offers the "Also make current?" secondary confirm (D9).
 */
export function PublishDraftButton({
  projectId,
  assetId,
  version,
  currentVersionId,
  canSetCurrent,
}: Props) {
  const qc = useQueryClient()
  const files = useVersionFiles(version.id)
  const [followUpOpen, setFollowUpOpen] = React.useState(false)

  const publish = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc('publish_version', {
        p_asset_version_id: version.id,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success(`v${version.sequence} published`)
      qc.invalidateQueries({ queryKey: qk.assetVersions(assetId) })
      qc.invalidateQueries({ queryKey: qk.assetVersion(version.id) })
      qc.invalidateQueries({ queryKey: qk.asset(assetId) })
      invalidateAssetsForProject(qc, projectId)
      if (canSetCurrent && currentVersionId !== version.id) setFollowUpOpen(true)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const setCurrent = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc('set_current_version', {
        p_design_asset_id: assetId,
        p_version_id: version.id,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Current version updated')
      qc.invalidateQueries({ queryKey: qk.asset(assetId) })
      invalidateAssetsForProject(qc, projectId)
      setFollowUpOpen(false)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const hasFiles = (files.data ?? []).length > 0
  const disabled = !hasFiles || publish.isPending

  return (
    <>
      <Button
        size="sm"
        onClick={() => publish.mutate()}
        disabled={disabled}
        title={hasFiles ? undefined : 'Attach at least one file to publish.'}
      >
        <CheckCircle2 className="mr-1 h-4 w-4" />
        Publish
      </Button>

      <Dialog open={followUpOpen} onOpenChange={setFollowUpOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Make v{version.sequence} the current version?</DialogTitle>
            <DialogDescription>
              The current version is what people see by default when they open this asset. You can
              always change it later from the version menu.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="secondary"
              size="sm"
              onClick={() => setFollowUpOpen(false)}
              disabled={setCurrent.isPending}
            >
              Not now
            </Button>
            <Button size="sm" onClick={() => setCurrent.mutate()} disabled={setCurrent.isPending}>
              {setCurrent.isPending ? 'Saving…' : 'Make current'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Ensure a successful publish also refreshes any versionFiles cache */}
      <Refetcher onSuccessOf={publish.isSuccess} versionId={version.id} qcTrigger={qc} />
    </>
  )
}

function Refetcher({
  onSuccessOf,
  versionId,
  qcTrigger,
}: {
  onSuccessOf: boolean
  versionId: string
  qcTrigger: ReturnType<typeof useQueryClient>
}) {
  React.useEffect(() => {
    if (onSuccessOf) invalidateVersionFiles(qcTrigger, versionId)
  }, [onSuccessOf, versionId, qcTrigger])
  return null
}
