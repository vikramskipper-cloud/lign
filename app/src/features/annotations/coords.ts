import type { PointPosition, RegionPosition } from './queries'

/**
 * Given a pointer event and the rendered rect of the media element, return
 * the normalized (0..1) position. Values are clamped so an off-edge click
 * still lands inside.
 */
export function eventToNormalizedPoint(
  clientX: number,
  clientY: number,
  rect: DOMRect,
): PointPosition {
  const x = clamp01((clientX - rect.left) / rect.width)
  const y = clamp01((clientY - rect.top) / rect.height)
  return { x, y }
}

/**
 * Two normalized points define a region. Order-independent (the smaller of x1/x2
 * is x, larger minus smaller is w; same for y/h). Zero-area regions get a
 * minimum ~1% size so they remain interactable.
 */
export function pointsToRegion(a: PointPosition, b: PointPosition): RegionPosition {
  const x = Math.min(a.x, b.x)
  const y = Math.min(a.y, b.y)
  const w = Math.max(0.01, Math.abs(a.x - b.x))
  const h = Math.max(0.01, Math.abs(a.y - b.y))
  return { x, y, w, h }
}

function clamp01(v: number): number {
  if (v < 0) return 0
  if (v > 1) return 1
  return v
}
