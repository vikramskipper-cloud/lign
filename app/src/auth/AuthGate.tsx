import * as React from 'react'
import { Navigate, useLocation } from 'react-router'
import { useSession } from '@/auth/SessionProvider'
import { LoadingPage } from '@/ui/loading-page'

/**
 * Redirects unauthenticated users to /sign-in with a ?returnTo=<current> query
 * so sign-in can bounce them back. Session boot is treated as loading — we
 * never render the app content while the session state is unknown.
 */
export function AuthGate({ children }: { children: React.ReactNode }) {
  const { session, isLoading } = useSession()
  const location = useLocation()

  if (isLoading) return <LoadingPage label="Signing you in…" />
  if (!session) {
    const returnTo = encodeURIComponent(location.pathname + location.search)
    return <Navigate to={`/sign-in?returnTo=${returnTo}`} replace />
  }
  return <>{children}</>
}
