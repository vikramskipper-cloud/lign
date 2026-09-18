/// <reference lib="webworker" />
import { createSHA256 } from 'hash-wasm'

/**
 * Streaming SHA-256 in a Web Worker. Reads a Blob in 8 MB chunks, feeds each
 * chunk to hash-wasm, posts progress at every chunk, and posts the final
 * hex digest when done. All error cases surface as { kind: 'error' }.
 */

const CHUNK_SIZE = 8 * 1024 * 1024

type InMessage = { id: string; blob: Blob }
type OutMessage =
  | { id: string; kind: 'progress'; bytes: number }
  | { id: string; kind: 'done'; hex: string }
  | { id: string; kind: 'error'; message: string }

async function hashBlob(blob: Blob, onProgress: (bytes: number) => void): Promise<string> {
  const hasher = await createSHA256()
  hasher.init()
  const total = blob.size
  let offset = 0
  while (offset < total) {
    const end = Math.min(offset + CHUNK_SIZE, total)
    const buf = await blob.slice(offset, end).arrayBuffer()
    hasher.update(new Uint8Array(buf))
    offset = end
    onProgress(offset)
  }
  return hasher.digest('hex')
}

self.addEventListener('message', async (evt: MessageEvent<InMessage>) => {
  const { id, blob } = evt.data
  try {
    const hex = await hashBlob(blob, (bytes) => {
      const msg: OutMessage = { id, kind: 'progress', bytes }
      ;(self as unknown as Worker).postMessage(msg)
    })
    const msg: OutMessage = { id, kind: 'done', hex }
    ;(self as unknown as Worker).postMessage(msg)
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Hash failed'
    const msg: OutMessage = { id, kind: 'error', message }
    ;(self as unknown as Worker).postMessage(msg)
  }
})
