import * as React from 'react'

interface Props {
  src: string
  alt?: string
  /**
   * Overlay children rendered on top of the *letterboxed* image rect (not the
   * outer container). Used by APP 005 AnnotationLayer to position pins in
   * normalized image coordinates.
   */
  overlay?: React.ReactNode
}

export function ImageViewer({ src, alt, overlay }: Props) {
  const [aspect, setAspect] = React.useState<number | null>(null)
  const onLoad = React.useCallback((e: React.SyntheticEvent<HTMLImageElement>) => {
    const img = e.currentTarget
    if (img.naturalWidth > 0 && img.naturalHeight > 0) {
      setAspect(img.naturalWidth / img.naturalHeight)
    }
  }, [])

  return (
    <div className="flex h-full w-full items-center justify-center bg-[--color-surface-2]">
      <div
        className="relative flex max-h-full max-w-full items-center justify-center"
        style={aspect ? { aspectRatio: String(aspect), width: 'min(100%, 100cqh)' } : undefined}
      >
        <img
          src={src}
          alt={alt ?? ''}
          onLoad={onLoad}
          className="block max-h-full max-w-full object-contain"
          draggable={false}
        />
        {aspect !== null && overlay}
      </div>
    </div>
  )
}
