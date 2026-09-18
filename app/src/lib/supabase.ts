import { createClient } from '@supabase/supabase-js'
import { env } from '@/env'

/**
 * Singleton Supabase client. autoRefreshToken keeps the 1h JWT alive; the
 * SessionProvider observes onAuthStateChange to wire the app's session context.
 * Realtime transport is the browser's native WebSocket — no polyfill in-app.
 */
export const supabase = createClient(env.supabaseUrl, env.supabaseAnonKey, {
  auth: {
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true,
    storageKey: 'lign.session',
  },
  realtime: {
    params: { eventsPerSecond: 30 },
  },
})
