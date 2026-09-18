import * as React from 'react'

type WorkerOut =
  | { id: string; kind: 'progress'; bytes: number }
  | { id: string; kind: 'done'; hex: string }
  | { id: string; kind: 'error'; message: string }

interface Job {
  onProgress?: (bytes: number) => void
  resolve: (hex: string) => void
  reject: (err: Error) => void
}

/**
 * Singleton hasher worker with a per-job callback map. Only one worker is
 * spawned across the app; jobs are serialized inside the worker naturally by
 * the message queue (D8: 1 hasher, jobs processed serially).
 */
class HasherClient {
  private worker: Worker | null = null
  private jobs = new Map<string, Job>()

  private ensure(): Worker {
    if (!this.worker) {
      this.worker = new Worker(new URL('./workers/hasher.worker.ts', import.meta.url), {
        type: 'module',
      })
      this.worker.addEventListener('message', (evt: MessageEvent<WorkerOut>) => {
        const { id } = evt.data
        const job = this.jobs.get(id)
        if (!job) return
        if (evt.data.kind === 'progress') {
          job.onProgress?.(evt.data.bytes)
        } else if (evt.data.kind === 'done') {
          job.resolve(evt.data.hex)
          this.jobs.delete(id)
        } else {
          job.reject(new Error(evt.data.message))
          this.jobs.delete(id)
        }
      })
    }
    return this.worker
  }

  hash(blob: Blob, onProgress?: (bytes: number) => void): Promise<string> {
    const id = crypto.randomUUID()
    return new Promise<string>((resolve, reject) => {
      this.jobs.set(id, { resolve, reject, onProgress })
      this.ensure().postMessage({ id, blob })
    })
  }
}

const client = new HasherClient()

export function useHashFile() {
  return React.useCallback(
    (blob: Blob, onProgress?: (bytes: number) => void) => client.hash(blob, onProgress),
    [],
  )
}
