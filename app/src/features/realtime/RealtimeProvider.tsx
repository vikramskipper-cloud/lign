import * as React from 'react'
import type { RealtimeChannel, RealtimePostgresChangesPayload } from '@supabase/supabase-js'
import { useParams } from 'react-router'
import { useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { useSession } from '@/auth/SessionProvider'
import { REALTIME_EVENTS, REALTIME_TABLES, wsChannel } from './channels'
import type { RealtimeTable } from './channels'
import { createCoalescer } from './coalesce'
import { handleRealtimeRow } from './handlers'

export type RealtimeStatus = 'idle' | 'connecting' | 'live' | 'offline'

const RealtimeContext = React.createContext<RealtimeStatus>('idle')

/**
 * APP 011 wave 1A — live cache invalidation.
 *
 * Mounted inside RootLayout rather than beside SessionProvider (as the Freeze
 * Index §5.2 assumed) because the active workspace comes from `useParams`,
 * which only resolves inside the router. RootLayout wraps every authenticated
 * route, so the lifetime is equivalent.
 *
 * This provider NEVER mutates, NEVER emits, and NEVER writes a payload into the
 * cache. It only invalidates. See handlers.ts.
 */
export function RealtimeProvider({ children }: { children: React.ReactNode }) {
  const { ws_id: wsId } = useParams<{ ws_id?: string }>()
  const { session } = useSession()
  const qc = useQueryClient()
  const [status, setStatus] = React.useState<RealtimeStatus>('idle')

  React.useEffect(() => {
    if (!session || !wsId) {
      setStatus('idle')
      return
    }

    const coalescer = createCoalescer()
    let channel: RealtimeChannel | null = null
    let disposed = false
    // Scoped to THIS channel instance, not to the provider. supabase-js rejoins
    // automatically and fires the callback with SUBSCRIBED again, so this is
    // precisely "has this channel connected before" — i.e. a true reconnect.
    // A workspace switch builds a new channel and must NOT count as one.
    let connectedOnce = false

    setStatus('connecting')

    const ctx = {
      qc,
      wsId,
      coalescer,
      onUnmapped: (table: RealtimeTable, reason: string) => {
        // Diagnostics only; never user-facing (Freeze Index §7.4).
        if (import.meta.env.DEV) {
          console.debug(`[realtime] unmapped ${table} event: ${reason}`)
        }
      },
    }

    channel = supabase.channel(wsChannel(wsId))

    for (const table of REALTIME_TABLES) {
      for (const event of REALTIME_EVENTS) {
        channel.on(
          'postgres_changes',
          {
            event,
            schema: 'public',
            table,
            // Performance narrowing only — RLS is the authorization boundary
            // (REALTIME 002 migration comment). Never describe this as access
            // control.
            filter: `workspace_id=eq.${wsId}`,
          },
          (payload: RealtimePostgresChangesPayload<Record<string, unknown>>) => {
            if (disposed) return
            const row = (payload.new ?? null) as Record<string, unknown> | null
            handleRealtimeRow(ctx, table, row)
          },
        )
      }
    }

    channel.subscribe((s) => {
      if (disposed) return
      if (s === 'SUBSCRIBED') {
        setStatus('live')
        if (connectedOnce) {
          // Freeze Index F-7 / §7.2: Postgres Changes has NO replay. Anything
          // that happened while the socket was down is lost permanently, so a
          // reconnect must be treated as "everything may have changed".
          // Without this, realtime is silently and indefinitely staler than
          // polling, which at least self-heals.
          //
          // invalidateQueries() with no filter marks every query stale, but
          // React Query only refetches the ACTIVE ones — so the cost is bounded
          // by what is currently on screen.
          qc.invalidateQueries()
        }
        connectedOnce = true
      } else if (s === 'CHANNEL_ERROR' || s === 'TIMED_OUT' || s === 'CLOSED') {
        setStatus('offline')
      }
    })

    return () => {
      disposed = true
      coalescer.dispose()
      if (channel) void supabase.removeChannel(channel)
      setStatus('idle')
    }
  }, [session, wsId, qc])

  // Tear the socket down on sign-out BEFORE SessionProvider clears the cache,
  // so no in-flight event can repopulate a cleared cache. Listener ordering is
  // not guaranteed, but the residual is harmless: a stray event would only
  // invalidate an already-empty cache.
  React.useEffect(() => {
    const { data: sub } = supabase.auth.onAuthStateChange((event) => {
      if (event === 'SIGNED_OUT') {
        void supabase.removeAllChannels()
        setStatus('idle')
      }
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  return <RealtimeContext.Provider value={status}>{children}</RealtimeContext.Provider>
}

/** APP 011 §8.3 — advisory connection state. Never blocks render. */
export function useRealtimeConnection(): RealtimeStatus {
  return React.useContext(RealtimeContext)
}
