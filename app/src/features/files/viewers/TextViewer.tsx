import * as React from 'react'
import { Loader2 } from 'lucide-react'
import { formatBytes } from '../mime'

interface Props {
  src: string
  sizeBytes: number
}

const MAX_TEXT_PREVIEW = 256 * 1024

export function TextViewer({ src, sizeBytes }: Props) {
  const [state, setState] = React.useState<
    | { kind: 'loading' }
    | { kind: 'too-large' }
    | { kind: 'error'; message: string }
    | { kind: 'ready'; text: string }
  >(sizeBytes > MAX_TEXT_PREVIEW ? { kind: 'too-large' } : { kind: 'loading' })

  React.useEffect(() => {
    if (state.kind !== 'loading') return
    let cancelled = false
    ;(async () => {
      try {
        const res = await fetch(src)
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        const text = await res.text()
        if (!cancelled) setState({ kind: 'ready', text })
      } catch (err) {
        if (!cancelled) {
          setState({
            kind: 'error',
            message: err instanceof Error ? err.message : 'Failed to load',
          })
        }
      }
    })()
    return () => {
      cancelled = true
    }
  }, [src, state.kind])

  if (state.kind === 'too-large') {
    return (
      <Centered>
        Text preview limited to {formatBytes(MAX_TEXT_PREVIEW)}. Download to view the full file.
      </Centered>
    )
  }
  if (state.kind === 'loading') {
    return (
      <Centered>
        <Loader2 className="h-4 w-4 animate-spin" />
      </Centered>
    )
  }
  if (state.kind === 'error') {
    return <Centered>Couldn't load preview: {state.message}</Centered>
  }
  return (
    <pre className="h-full w-full overflow-auto bg-[--color-surface] p-4 font-mono text-xs text-[--color-text]">
      {state.text}
    </pre>
  )
}

function Centered({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-full w-full items-center justify-center bg-[--color-surface-2] p-6 text-sm text-[--color-text-muted]">
      {children}
    </div>
  )
}
