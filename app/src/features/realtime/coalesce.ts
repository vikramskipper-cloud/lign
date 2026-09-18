/**
 * APP 011 §7.3 / G-3 — keyed trailing coalescer.
 *
 * A bulk operation (a roster edit touching a dozen `review_participants` rows)
 * arrives as a dozen WAL events within milliseconds. Without coalescing that is
 * a dozen invalidations of the same key and a dozen refetches.
 *
 * Keyed, not global: a comment insert must never delay a review update.
 */
export const COALESCE_WINDOW_MS = 250

export interface Coalescer {
  /** Schedule `run` for `key`, replacing any pending run for the same key. */
  schedule(key: string, run: () => void): void
  /** Run everything pending immediately (used on teardown). */
  flush(): void
  /** Drop everything pending without running it. */
  dispose(): void
}

export function createCoalescer(windowMs: number = COALESCE_WINDOW_MS): Coalescer {
  const timers = new Map<string, ReturnType<typeof setTimeout>>()
  const pending = new Map<string, () => void>()

  const fire = (key: string) => {
    timers.delete(key)
    const run = pending.get(key)
    pending.delete(key)
    run?.()
  }

  return {
    schedule(key, run) {
      pending.set(key, run)
      const existing = timers.get(key)
      if (existing !== undefined) clearTimeout(existing)
      timers.set(key, setTimeout(() => fire(key), windowMs))
    },
    flush() {
      for (const key of [...timers.keys()]) {
        const t = timers.get(key)
        if (t !== undefined) clearTimeout(t)
        fire(key)
      }
    },
    dispose() {
      for (const t of timers.values()) clearTimeout(t)
      timers.clear()
      pending.clear()
    },
  }
}
