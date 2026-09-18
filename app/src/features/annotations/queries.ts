import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'

export type AnchorKind =
  | 'point'
  | 'region'
  | 'page_point'
  | 'page_region'
  | 'time'
  | 'three_d_node'
  | 'document'

export type AnnotationStatus = 'active' | 'resolved' | 'archived'

/**
 * Client shape for annotation.position by anchor_kind. Persisted as JSONB;
 * the backend enforces only immutability, not shape. Positions are normalized
 * (0..1) fractions so zoom / responsive resizing doesn't corrupt them.
 */
export type PointPosition = { x: number; y: number }
export type RegionPosition = { x: number; y: number; w: number; h: number }
export type TimePosition = { t: number }
export type AnnotationPosition = PointPosition | RegionPosition | TimePosition | Record<string, unknown>

export interface AnnotationRow {
  id: string
  workspace_id: string
  asset_version_id: string
  version_file_id: string | null
  author_profile_id: string | null
  anchor_kind: AnchorKind
  page_number: number | null
  position: AnnotationPosition
  status: AnnotationStatus
  resolved_at: string | null
  archived_at: string | null
  created_at: string
  updated_at: string
}

const SELECT = `
  id, workspace_id, asset_version_id, version_file_id, author_profile_id,
  anchor_kind, page_number, position, status, resolved_at, archived_at,
  created_at, updated_at
`

export function useAnnotationsForVersion(versionId: string | undefined) {
  return useQuery({
    queryKey: versionId
      ? qk.annotationsForVersion(versionId)
      : ['asset-version', 'none', 'annotations'],
    enabled: Boolean(versionId),
    queryFn: async (): Promise<AnnotationRow[]> => {
      const { data, error } = await supabase
        .from('annotations')
        .select(SELECT)
        .eq('asset_version_id', versionId as string)
        .order('created_at', { ascending: true })
      if (error) throw error
      return (data ?? []) as AnnotationRow[]
    },
  })
}

export function useAnnotation(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.annotation(id) : ['annotation', 'none'],
    enabled: Boolean(id),
    queryFn: async (): Promise<AnnotationRow | null> => {
      const { data, error } = await supabase
        .from('annotations')
        .select(SELECT)
        .eq('id', id as string)
        .maybeSingle()
      if (error) throw error
      return (data as AnnotationRow | null) ?? null
    },
  })
}
