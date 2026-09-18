import { Download } from 'lucide-react'
import { Button } from '@/ui/button'
import { MimePlaceholder } from '../MimePlaceholder'
import { formatBytes } from '../mime'

interface Props {
  src: string
  mime: string | null
  filename: string
  sizeBytes: number
}

export function DownloadOnly({ src, mime, filename, sizeBytes }: Props) {
  return (
    <div className="flex h-full w-full flex-col items-center justify-center gap-4 p-8">
      <div className="h-40 w-40">
        <MimePlaceholder mime={mime} filename={filename} size="lg" />
      </div>
      <div className="space-y-1 text-center">
        <p className="text-sm font-medium">{filename}</p>
        <p className="text-xs text-[--color-text-subtle]">
          {formatBytes(sizeBytes)} · Preview not available in the browser
        </p>
      </div>
      <Button asChild size="sm" variant="secondary">
        <a href={src} download={filename} target="_blank" rel="noreferrer">
          <Download className="mr-1 h-4 w-4" />
          Download
        </a>
      </Button>
    </div>
  )
}
