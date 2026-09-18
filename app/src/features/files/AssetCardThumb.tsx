import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { useSignedUrl } from './useSignedUrl'
import { MimePlaceholder } from './MimePlaceholder'
import { viewerFor } from './mime'
import type { FileRole } from './mime'

interface Props {
  currentVersionId: string | null
}

interface PrimaryHit {
  id: string
  display_name: string | null
  role: FileRole
  file: {
    id: string
    mime_type: string
    size_bytes: number
    storage_ref: string
  }
}

/**
 * Fetches the primary attachment of a version (single row) and renders either
 * an inline image thumbnail (image mimes) or a mime placeholder. Grid-safe:
 * per-tile query is small, uses React Query cache, lazily loads image bytes.
 */
export function AssetCardThumb({ currentVersionId }: Props) {
  const q = useQuery({
    queryKey: currentVersionId
      ? [...qk.versionFiles(currentVersionId), 'primary']
      : ['asset-version', 'none', 'files', 'primary'],
    enabled: Boolean(currentVersionId),
    queryFn: async (): Promise<PrimaryHit | null> => {
      const { data, error } = await supabase
        .from('version_files')
        .select(
          'id, display_name, role, sort_order, file:files!version_files_file_fk(id, mime_type, size_bytes, storage_ref)',
        )
        .eq('asset_version_id', currentVersionId as string)
        .order('role', { ascending: true }) // 'primary' < others alphabetically? no — filter below
        .order('sort_order', { ascending: true })
        .limit(50)
      if (error) throw error
      const rows = (data ?? []) as unknown as PrimaryHit[]
      const primary = rows.find((r) => r.role === 'primary')
      return primary ?? rows[0] ?? null
    },
  })

  if (!currentVersionId) return <FallbackPlaceholder />
  if (q.isLoading || !q.data) return <FallbackPlaceholder />

  const hit = q.data
  const kind = viewerFor(hit.file.mime_type)
  if (kind === 'image') {
    return <ImageThumb fileId={hit.file.id} storageRef={hit.file.storage_ref} />
  }
  return (
    <MimePlaceholder mime={hit.file.mime_type} filename={hit.display_name ?? undefined} />
  )
}

function ImageThumb({ fileId, storageRef }: { fileId: string; storageRef: string }) {
  const url = useSignedUrl({ fileId, storageRef, purpose: 'thumb' })
  if (url.isLoading || !url.data) return <FallbackPlaceholder />
  return (
    <img
      src={url.data}
      alt=""
      loading="lazy"
      className="h-full w-full rounded-[--radius-md] object-cover"
      draggable={false}
    />
  )
}

function FallbackPlaceholder() {
  return (
    <div className="h-full w-full rounded-[--radius-md] border border-dashed border-[--color-border] bg-[--color-surface-2]" />
  )
}
