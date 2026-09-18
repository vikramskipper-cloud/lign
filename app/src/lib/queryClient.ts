import { QueryClient } from '@tanstack/react-query'

function isAuthError(err: unknown): boolean {
  if (!err || typeof err !== 'object') return false
  const e = err as { status?: number; code?: string }
  return e.status === 401 || e.status === 403 || e.code === 'PGRST301'
}

/**
 * The one QueryClient for the app. Defaults per APP 002 §10.
 * Individual queries may override staleTime/gcTime for reasons.
 */
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      gcTime: 300_000,
      retry: (failureCount, error) => failureCount < 3 && !isAuthError(error),
      refetchOnWindowFocus: true,
      refetchOnReconnect: true,
    },
    mutations: {
      retry: false,
    },
  },
})
