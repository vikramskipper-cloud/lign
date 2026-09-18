interface Props {
  src: string
  title: string
}

export function PdfViewer({ src, title }: Props) {
  return (
    <iframe
      src={src}
      title={title}
      className="h-full w-full border-0 bg-[--color-surface-2]"
    />
  )
}
