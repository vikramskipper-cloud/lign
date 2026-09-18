import * as React from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { invalidateAssetsForProject, invalidateVersionFiles } from '@/features/shared/invalidate'
import { qk } from '@/lib/queryKeys'
import { useHashFile } from './useHashFile'
import { DENYLISTED_MIMES, MAX_UPLOAD_BYTES, type FileRole } from './mime'

export type UploadPhase =
  | 'queued'
  | 'hashing'
  | 'reserving'
  | 'uploading'
  | 'finalizing'
  | 'done'
  | 'error'

export interface UploadItem {
  id: string
  blob: File
  name: string
  size: number
  mime: string
  role: FileRole
  displayName: string
  phase: UploadPhase
  progress: number // 0..1 (either hashing or uploading, whichever is active)
  error?: string
  fileId?: string
  versionFileId?: string
}

interface StartUploadResp {
  out_file_id: string
  out_action: 'upload_required' | 'reused' | 'reclaimed' | 'purged' | 'in_progress'
  out_bucket: string
  out_object_path: string
  out_size_bytes: number
  out_mime_type: string
}

interface FinalizeResp {
  out_file_id: string
  out_version_files_id: string
  out_action: 'attached' | 'already_attached'
}

interface Options {
  versionId: string
  projectId: string
  assetId: string
  /** Concurrency cap for byte-uploads (D8). */
  maxConcurrent?: number
}

interface QueueState {
  items: UploadItem[]
}

const BUCKET = 'lign-files'

/**
 * Per-file upload state machine driving hash → start → upload → finalize.
 * Enforces D8 concurrency (3 parallel byte uploads by default). Hashing
 * routes through the singleton HasherClient (already serialized).
 */
export function useUploadQueue({
  versionId,
  projectId,
  assetId,
  maxConcurrent = 3,
}: Options) {
  const qc = useQueryClient()
  const hash = useHashFile()
  const [state, setState] = React.useState<QueueState>({ items: [] })
  const activeRef = React.useRef(0)
  const stateRef = React.useRef(state)
  React.useEffect(() => {
    stateRef.current = state
  }, [state])

  const patchItem = React.useCallback((id: string, patch: Partial<UploadItem>) => {
    setState((prev) => ({
      items: prev.items.map((it) => (it.id === id ? { ...it, ...patch } : it)),
    }))
  }, [])

  const removeItem = React.useCallback((id: string) => {
    setState((prev) => ({ items: prev.items.filter((it) => it.id !== id) }))
  }, [])

  const enqueue = React.useCallback(
    (files: File[]) => {
      const previouslyHasPrimary =
        stateRef.current.items.some(
          (it) => it.role === 'primary' && (it.phase === 'done' || it.phase !== 'error'),
        ) ?? false
      const additions: UploadItem[] = files.map((f, idx) => {
        const badMime = DENYLISTED_MIMES.has((f.type || '').toLowerCase())
        const tooLarge = f.size > MAX_UPLOAD_BYTES
        const role: FileRole = !previouslyHasPrimary && idx === 0 ? 'primary' : 'reference'
        return {
          id: crypto.randomUUID(),
          blob: f,
          name: f.name,
          size: f.size,
          mime: f.type || 'application/octet-stream',
          role,
          displayName: f.name,
          phase: badMime || tooLarge ? 'error' : 'queued',
          progress: 0,
          error: tooLarge
            ? 'Too large (500 MB max)'
            : badMime
              ? "This file type isn't allowed"
              : undefined,
        }
      })
      setState((prev) => ({ items: [...prev.items, ...additions] }))
      // Kick the scheduler
      queueMicrotask(pump)
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  )

  const setRole = React.useCallback(
    (id: string, role: FileRole) => {
      setState((prev) => ({
        items: prev.items.map((it) => {
          if (it.id === id) return { ...it, role }
          // Enforce single-primary (D4): if we're assigning primary here, demote others.
          if (role === 'primary' && it.role === 'primary') return { ...it, role: 'reference' }
          return it
        }),
      }))
    },
    [],
  )

  const setDisplayName = React.useCallback((id: string, displayName: string) => {
    patchItem(id, { displayName })
  }, [patchItem])

  const retry = React.useCallback((id: string) => {
    patchItem(id, { phase: 'queued', error: undefined, progress: 0 })
    queueMicrotask(pump)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [patchItem])

  const clearFinished = React.useCallback(() => {
    setState((prev) => ({ items: prev.items.filter((it) => it.phase !== 'done') }))
  }, [])

  async function runOne(item: UploadItem) {
    try {
      patchItem(item.id, { phase: 'hashing', progress: 0 })
      const hex = await hash(item.blob, (bytes) => {
        patchItem(item.id, { progress: item.size > 0 ? bytes / item.size : 0 })
      })

      patchItem(item.id, { phase: 'reserving', progress: 1 })
      const { data: startData, error: startErr } = await supabase.rpc(
        'start_version_file_upload',
        {
          p_asset_version_id: versionId,
          p_checksum_hex: hex,
          p_mime_type: item.mime,
          p_size_bytes: item.size,
        },
      )
      if (startErr) throw startErr
      const start = (Array.isArray(startData) ? startData[0] : startData) as StartUploadResp
      if (!start) throw new Error('start_version_file_upload returned no row')

      const fileId = start.out_file_id
      patchItem(item.id, { fileId })

      if (start.out_action === 'upload_required' || start.out_action === 'purged') {
        patchItem(item.id, { phase: 'uploading', progress: 0 })
        const { error: upErr } = await supabase.storage
          .from(BUCKET)
          .upload(start.out_object_path, item.blob, {
            contentType: item.mime,
            upsert: false,
            cacheControl: 'private, max-age=0',
          })
        if (upErr) throw upErr
        patchItem(item.id, { progress: 1 })
      } else if (start.out_action === 'in_progress') {
        // Another client is uploading the same bytes. Poll finalize; the RPC
        // will succeed once the object appears. Small delay avoids a tight loop.
        await new Promise((r) => setTimeout(r, 1500))
      }
      // 'reused' and 'reclaimed' skip the byte-upload entirely.

      patchItem(item.id, { phase: 'finalizing' })
      const { data: finData, error: finErr } = await supabase.rpc(
        'finalize_version_file_upload',
        {
          p_file_id: fileId,
          p_asset_version_id: versionId,
          p_display_name: item.displayName || null,
          p_role: item.role,
          p_sort_order: null,
        },
      )
      if (finErr) throw finErr
      const fin = (Array.isArray(finData) ? finData[0] : finData) as FinalizeResp
      patchItem(item.id, {
        phase: 'done',
        versionFileId: fin.out_version_files_id,
        progress: 1,
      })
      invalidateVersionFiles(qc, versionId)
      qc.invalidateQueries({ queryKey: qk.assetVersion(versionId) })
      // Primary attachment change may swap the AssetCard thumbnail
      invalidateAssetsForProject(qc, projectId)
      qc.invalidateQueries({ queryKey: qk.asset(assetId) })
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Upload failed'
      patchItem(item.id, { phase: 'error', error: message })
    } finally {
      activeRef.current = Math.max(0, activeRef.current - 1)
      queueMicrotask(pump)
    }
  }

  function pump() {
    while (activeRef.current < maxConcurrent) {
      const next = stateRef.current.items.find((it) => it.phase === 'queued')
      if (!next) return
      activeRef.current += 1
      patchItem(next.id, { phase: 'hashing' })
      void runOne(next)
    }
  }

  return {
    items: state.items,
    enqueue,
    setRole,
    setDisplayName,
    retry,
    removeItem,
    clearFinished,
  }
}
