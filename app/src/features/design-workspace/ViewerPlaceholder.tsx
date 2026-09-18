import { Image } from 'lucide-react'

/**
 * APP 003 viewer surface — deliberately empty of file rendering.
 * APP 004 will swap this component for a real Viewer that resolves
 * VersionFiles and renders images/PDFs/etc.
 */
export function ViewerPlaceholder({ versionSequence }: { versionSequence: number | null }) {
  return (
    <div
      className="flex h-full w-full items-center justify-center border border-dashed border-[--color-border] bg-[--color-surface-2]"
      role="img"
      aria-label="File preview placeholder"
    >
      <div className="flex flex-col items-center gap-3 text-center text-[--color-text-subtle]">
        <Image className="h-10 w-10" />
        <div className="space-y-1">
          <p className="text-sm font-medium text-[--color-text-muted]">
            {versionSequence != null ? `v${versionSequence}` : 'No version'}
          </p>
          <p className="max-w-xs text-xs">File rendering lands in APP 004.</p>
        </div>
      </div>
    </div>
  )
}
