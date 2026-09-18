import * as React from 'react'
import type { RealtimeChannel } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'
import { useSession } from '@/auth/SessionProvider'
import { versionPresenceChannel } from './channels'

/**
 * APP 011 wave 2 — "who else is looking at this version".
 *
 * Presence is ephemeral by construction: it lives in the Realtime server's
 * in-memory state, never touches Postgres, and is never a source of truth.
 * Nothing here reads or writes a table.
 *
 * Deviation from Freeze Index §8, deliberate: the payload carries `email`
 * rather than `display_name`/`avatar_url`. Nothing in the shell fetches
 * `profiles` today — `UserMenu` derives initials from `user.email` — so
 * carrying a display name would mean adding a profile query for cosmetics.
 * Resolving real names and avatars belongs to the UI/UX pass.
 */
export interface PresencePeer {
  profileId: string
  email: string
  joinedAt: string
}

interface TrackedPayload {
  profile_id: string
  email: string
  joined_at: string
}

export function useVersionPresence(versionId: string | null): PresencePeer[] {
  const { session } = useSession()
  const [peers, setPeers] = React.useState<PresencePeer[]>([])
  const myId = session?.user?.id ?? null
  const myEmail = session?.user?.email ?? ''

  React.useEffect(() => {
    if (!versionId || !myId) {
      setPeers([])
      return
    }

    let disposed = false
    // Keying the channel by profile id means a user with the same version open
    // in three tabs is one peer, not three.
    const channel: RealtimeChannel = supabase.channel(versionPresenceChannel(versionId), {
      config: { presence: { key: myId } },
    })

    const sync = () => {
      if (disposed) return
      const state = channel.presenceState<TrackedPayload>()
      const next: PresencePeer[] = []
      for (const entries of Object.values(state)) {
        const first = entries[0]
        if (!first || first.profile_id === myId) continue // "who ELSE is here"
        next.push({
          profileId: first.profile_id,
          email: first.email,
          joinedAt: first.joined_at,
        })
      }
      next.sort((a, b) => a.joinedAt.localeCompare(b.joinedAt))
      setPeers(next)
    }

    channel.on('presence', { event: 'sync' }, sync)
    channel.on('presence', { event: 'join' }, sync)
    channel.on('presence', { event: 'leave' }, sync)

    channel.subscribe((status) => {
      if (disposed || status !== 'SUBSCRIBED') return
      void channel.track({
        profile_id: myId,
        email: myEmail,
        joined_at: new Date().toISOString(),
      } satisfies TrackedPayload)
    })

    return () => {
      disposed = true
      setPeers([])
      void supabase.removeChannel(channel)
    }
  }, [versionId, myId, myEmail])

  return peers
}
