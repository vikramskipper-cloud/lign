import * as React from 'react'
import { Loader2 } from 'lucide-react'
import { EmptyState } from '@/ui/empty-state'
import { Button } from '@/ui/button'
import { useSignedUrl } from './useSignedUrl'
import { viewerFor } from './mime'
import { ImageViewer } from './viewers/ImageViewer'
import { PdfViewer } from './viewers/PdfViewer'
import { VideoViewer } from './viewers/VideoViewer'
import { AudioViewer } from './viewers/AudioViewer'
import { TextViewer } from './viewers/TextViewer'
import { DownloadOnly } from './viewers/DownloadOnly'
import type { VersionFileRow } from './queries'

interface Props {
  vf: VersionFileRow
  /**
   * Optional overlay rendered inside the letterboxed image rect (APP 005).
   * Ignored for non-image kinds.
   */
  imageOverlay?: React.ReactNode
  /**
   * Optional companion strip rendered directly under the <video> (APP 005).
   * Ignored for non-video kinds.
   */
  videoBelowStrip?: (ctl: {
    getCurrentTime: () => number
    seekTo: (t: number) => void
    duration: number
  }) => React.ReactNode
}

export function Viewer({ vf, imageOverlay, videoBelowStrip }: Props) {
  const filename = vf.display_name || `file-${vf.file.id.slice(0, 8)}`
  const kind = viewerFor(vf.file.mime_type)
  const url = useSignedUrl({ fileId: vf.file.id, storageRef: vf.file.storage_ref })

  if (url.isLoading) {
    return (
      <div className="flex h-full w-full items-center justify-center text-[--color-text-muted]">
        <Loader2 className="h-4 w-4 animate-spin" />
      </div>
    )
  }
  if (url.isError || !url.data) {
    return (
      <div className="flex h-full w-full items-center justify-center p-6">
        <EmptyState
          title="Couldn't load this file"
          description="The signed URL couldn't be issued. Retry, or reload if this keeps happening."
          action={
            <Button size="sm" variant="secondary" onClick={() => url.refetch()}>
              Retry
            </Button>
          }
        />
      </div>
    )
  }

  const src = url.data
  switch (kind) {
    case 'image':
      return <ImageViewer src={src} alt={filename} overlay={imageOverlay} />
    case 'pdf':
      return <PdfViewer src={src} title={filename} />
    case 'video':
      return <VideoViewer src={src} mime={vf.file.mime_type} belowStrip={videoBelowStrip} />
    case 'audio':
      return <AudioViewer src={src} mime={vf.file.mime_type} filename={filename} />
    case 'text':
      return <TextViewer src={src} sizeBytes={vf.file.size_bytes} />
    case 'download-only':
    default:
      return (
        <DownloadOnly
          src={src}
          mime={vf.file.mime_type}
          filename={filename}
          sizeBytes={vf.file.size_bytes}
        />
      )
  }
}
