import { createClient } from '@supabase/supabase-js'
import { env } from '@/env'
import { hybridSessionStorage } from '@/lib/sessionPersistence'

/**
 * Singleton Supabase client. autoRefreshToken keeps the 1h JWT alive; the
 * SessionProvider observes onAuthStateChange to wire the app's session context.
 * Realtime transport is the browser's native WebSocket — no polyfill in-app.
 *
 * `storage` is the hybrid adapter backing "Keep me signed in on this device":
 * it routes to localStorage or sessionStorage per the user's choice. See
 * lib/sessionPersistence.ts. persistSession stays true — the adapter decides
 * WHERE the session lives, not WHETHER it is written.
 */
export const supabase = createClient(env.supabaseUrl, env.supabaseAnonKey, {
  auth: {
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true,
    storageKey: 'lign.session',
    storage: hybridSessionStorage,
  },
  realtime: {
    params: { eventsPerSecond: 30 },
  },
})
