import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import type { FileRole } from './mime'

export type FileStatus = 'uploaded' | 'active' | 'orphaned' | 'purged'

export interface FileRow {
  id: string
  workspace_id: string
  mime_type: string
  size_bytes: number
  storage_ref: string
  status: FileStatus
}

export interface VersionFileRow {
  id: string
  workspace_id: string
  asset_version_id: string
  file_id: string
  display_name: string | null
  role: FileRole
  sort_order: number
  created_at: string
  file: FileRow
}

const SELECT = `
  id, workspace_id, asset_version_id, file_id, display_name, role, sort_order, created_at,
  file:files!version_files_file_fk (
    id, workspace_id, mime_type, size_bytes, storage_ref, status
  )
`

export function useVersionFiles(versionId: string | undefined) {
  return useQuery({
    queryKey: versionId ? qk.versionFiles(versionId) : ['asset-version', 'none', 'files'],
    enabled: Boolean(versionId),
    queryFn: async (): Promise<VersionFileRow[]> => {
      const { data, error } = await supabase
        .from('version_files')
        .select(SELECT)
        .eq('asset_version_id', versionId as string)
        .order('sort_order', { ascending: true })
      if (error) throw error
      return (data ?? []) as unknown as VersionFileRow[]
    },
  })
}
