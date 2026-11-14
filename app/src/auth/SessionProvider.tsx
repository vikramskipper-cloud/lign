import * as React from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'
import { queryClient } from '@/lib/queryClient'

interface SessionContextValue {
  session: Session | null
  user: User | null
  isLoading: boolean
  signOut: () => Promise<void>
}

const SessionContext = React.createContext<SessionContextValue | null>(null)

/**
 * Wraps the whole app. Reads the current session on mount and subscribes to
 * auth state changes. On sign-out or a change of user it clears the React Query cache so no
 * stale server data survives the session switch.
 */
export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [session, setSession] = React.useState<Session | null>(null)
  const [isLoading, setIsLoading] = React.useState(true)

  React.useEffect(() => {
    let mounted = true
    let authEventReceived=false
    let currentUserId:string|null|undefined
    const applySession=(next:Session|null)=>{
      const nextId=next?.user.id??null
      if(currentUserId!==undefined&&currentUserId!==nextId)queryClient.clear()
      currentUserId=nextId
      setSession(next)
      setIsLoading(false)
    }
    supabase.auth.getSession().then(({data})=>{
      if(!mounted||authEventReceived)return
      applySession(data.session)
    })
    const {data:sub}=supabase.auth.onAuthStateChange((event,next)=>{
      if(!mounted)return
      authEventReceived=true
      if(event==='SIGNED_OUT')queryClient.clear()
      applySession(next)
    })

    return () => {
      mounted = false
      sub.subscription.unsubscribe()
    }
  }, [])

  const value = React.useMemo<SessionContextValue>(
    () => ({
      session,
      user: session?.user ?? null,
      isLoading,
      async signOut() {
        await supabase.auth.signOut()
      },
    }),
    [session, isLoading],
  )

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>
}

export function useSession(): SessionContextValue {
  const ctx = React.useContext(SessionContext)
  if (!ctx) throw new Error('useSession must be used within <SessionProvider>')
  return ctx
}
