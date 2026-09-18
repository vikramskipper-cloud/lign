import * as React from 'react'
import { ErrorBoundary } from '@/ui/error-boundary'
import { LoadingPage } from '@/ui/loading-page'

interface AsyncBoundaryProps {
  children: React.ReactNode
  fallback?: React.ReactNode
}

/**
 * Suspense + ErrorBoundary composed. Used by every route element so a route's
 * data fetch can suspend without crashing the app and errors are contained.
 */
export function AsyncBoundary({ children, fallback = <LoadingPage /> }: AsyncBoundaryProps) {
  return (
    <ErrorBoundary>
      <React.Suspense fallback={fallback}>{children}</React.Suspense>
    </ErrorBoundary>
  )
}
