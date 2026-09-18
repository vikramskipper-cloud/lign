import { MimePlaceholder } from '../MimePlaceholder'

interface Props {
  src: string
  mime: string
  filename: string
}

export function AudioViewer({ src, mime, filename }: Props) {
  return (
    <div className="flex h-full w-full flex-col items-center justify-center gap-4 bg-[--color-surface-2] p-8">
      <div className="h-40 w-40">
        <MimePlaceholder mime={mime} filename={filename} size="lg" />
      </div>
      <audio controls className="w-full max-w-md">
        <source src={src} type={mime} />
        Your browser does not support this audio format.
      </audio>
    </div>
  )
}
