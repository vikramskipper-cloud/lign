/**
 * "Keep me signed in on this device".
 *
 * Supabase's `persistSession: true` writes to localStorage, which survives a
 * browser restart. There is no per-call switch, and the client is a singleton
 * created at module load — so the only honest way to make persistence a user
 * choice is a storage adapter that decides, per operation, which Storage to
 * use.
 *
 * The preference itself lives in localStorage (it must outlive the session it
 * describes). Everything else — the session, the refresh token — goes to
 * whichever store the preference selects.
 *
 * Set the preference BEFORE calling signInWithPassword, so the session is
 * written to the right place the first time rather than migrated afterwards.
 */

const PREFERENCE_KEY = 'lign.session.persist'

function safeGet(store: Storage | undefined, key: string): string | null {
  try {
    return store?.getItem(key) ?? null
  } catch {
    // Storage can throw in private mode or when blocked by policy.
    return null
  }
}

/** true = survive browser restart (localStorage); false = tab/session only. */
export function getSessionPersistence(): boolean {
  if (typeof window === 'undefined') return true
  return safeGet(window.localStorage, PREFERENCE_KEY) !== '0'
}

export function setSessionPersistence(persist: boolean): void {
  if (typeof window === 'undefined') return
  try {
    window.localStorage.setItem(PREFERENCE_KEY, persist ? '1' : '0')
  } catch {
    /* preference is best-effort; the adapter falls back to localStorage */
  }
}

function activeStore(): Storage | undefined {
  if (typeof window === 'undefined') return undefined
  try {
    return getSessionPersistence() ? window.localStorage : window.sessionStorage
  } catch {
    return undefined
  }
}

/**
 * Passed to createClient as `auth.storage`. Reads and writes follow the
 * current preference; removal clears BOTH stores so a toggle can never leave
 * an orphaned session behind in the one that is no longer active.
 */
export const hybridSessionStorage = {
  getItem(key: string): string | null {
    // Read the active store first, then fall back to the other one: a session
    // created before the preference changed is still a valid session.
    const active = safeGet(activeStore(), key)
    if (active !== null) return active
    if (typeof window === 'undefined') return null
    const other = getSessionPersistence() ? window.sessionStorage : window.localStorage
    return safeGet(other, key)
  },
  setItem(key: string, value: string): void {
    try {
      activeStore()?.setItem(key, value)
    } catch {
      /* nothing useful to do; the user simply stays signed out */
    }
    // Keep the inactive store clean so the two can never disagree.
    if (typeof window === 'undefined') return
    try {
      const other = getSessionPersistence() ? window.sessionStorage : window.localStorage
      other.removeItem(key)
    } catch {
      /* ignore */
    }
  },
  removeItem(key: string): void {
    if (typeof window === 'undefined') return
    for (const store of [window.localStorage, window.sessionStorage]) {
      try {
        store.removeItem(key)
      } catch {
        /* ignore */
      }
    }
  },
}
