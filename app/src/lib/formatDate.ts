const rtf = new Intl.RelativeTimeFormat('en', { numeric: 'auto' })

const RANGES: Array<[Intl.RelativeTimeFormatUnit, number]> = [
  ['year', 60 * 60 * 24 * 365],
  ['month', 60 * 60 * 24 * 30],
  ['week', 60 * 60 * 24 * 7],
  ['day', 60 * 60 * 24],
  ['hour', 60 * 60],
  ['minute', 60],
  ['second', 1],
]

/** Relative time like "2 hours ago", "in 3 days", etc. */
export function relative(ts: string | Date | number | null | undefined): string {
  if (ts == null) return ''
  const date = typeof ts === 'string' || typeof ts === 'number' ? new Date(ts) : ts
  const deltaSec = (date.getTime() - Date.now()) / 1000
  for (const [unit, sec] of RANGES) {
    if (Math.abs(deltaSec) >= sec || unit === 'second') {
      return rtf.format(Math.round(deltaSec / sec), unit)
    }
  }
  return ''
}

/** Absolute time like "Aug 6, 2026, 2:14 PM" — used as a tooltip title. */
export function absolute(ts: string | Date | number | null | undefined): string {
  if (ts == null) return ''
  const date = typeof ts === 'string' || typeof ts === 'number' ? new Date(ts) : ts
  return date.toLocaleString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}
