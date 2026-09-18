import * as React from 'react'

interface Props {
  src: string
  mime: string
  /** Optional strip rendered directly below the <video> (used for time annotations). */
  belowStrip?: (ctl: {
    getCurrentTime: () => number
    seekTo: (t: number) => void
    duration: number
  }) => React.ReactNode
}

export function VideoViewer({ src, mime, belowStrip }: Props) {
  const videoRef = React.useRef<HTMLVideoElement | null>(null)
  const [duration, setDuration] = React.useState(0)

  const getCurrentTime = React.useCallback(() => videoRef.current?.currentTime ?? 0, [])
  const seekTo = React.useCallback((t: number) => {
    if (videoRef.current) {
      videoRef.current.currentTime = t
    }
  }, [])

  return (
    <div className="flex h-full w-full flex-col bg-black">
      <div className="flex flex-1 items-center justify-center">
        <video
          ref={videoRef}
          controls
          onLoadedMetadata={(e) => setDuration(e.currentTarget.duration || 0)}
          className="max-h-full max-w-full"
        >
          <source src={src} type={mime} />
          Your browser does not support this video format.
        </video>
      </div>
      {belowStrip?.({ getCurrentTime, seekTo, duration })}
    </div>
  )
}
