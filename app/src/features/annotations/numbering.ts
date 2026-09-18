import * as React from 'react'
import { useAnnotationsForVersion, type AnnotationRow } from './queries'

/**
 * Opaque provider that maps annotation.id → display number. Callers must not
 * reach around this abstraction (do not read created_at directly). A future
 * persistent annotations.sequence column swaps in here without any consumer
 * change.
 */
export interface AnnotationNumbering {
  numberFor(annotationId: string): number | undefined
  hasNumbers: boolean
}

const EMPTY: AnnotationNumbering = {
  numberFor: () => undefined,
  hasNumbers: false,
}

export function useAnnotationNumbering(
  versionId: string | undefined,
): AnnotationNumbering {
  const q = useAnnotationsForVersion(versionId)
  return React.useMemo(() => computeNumbering(q.data), [q.data])
}

/**
 * Pure helper — exported for tests + so a resolver can call it once with a
 * fetched list rather than mounting the hook.
 */
export function computeNumbering(list: AnnotationRow[] | undefined): AnnotationNumbering {
  if (!list || list.length === 0) return EMPTY
  const sorted = [...list].sort((a, b) => a.created_at.localeCompare(b.created_at))
  const map = new Map<string, number>()
  sorted.forEach((a, i) => map.set(a.id, i + 1))
  return {
    numberFor: (id) => map.get(id),
    hasNumbers: true,
  }
}
