import * as React from 'react'
import { AlertTriangle, RefreshCw } from 'lucide-react'
import { Button } from '@/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/ui/card'

interface State {
  error: Error | null
}

interface Props {
  children: React.ReactNode
  fallback?: (error: Error, reset: () => void) => React.ReactNode
}

/**
 * Top-level error boundary used by RootLayout. Also composable inside routes
 * to isolate failures. Keeps rendering surface simple; deeper diagnostics
 * belong in the console + telemetry, not the UI.
 */
export class ErrorBoundary extends React.Component<Props, State> {
  state: State = { error: null }

  static getDerivedStateFromError(error: Error): State {
    return { error }
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    // eslint-disable-next-line no-console
    console.error('ErrorBoundary caught:', error, info)
  }

  reset = () => this.setState({ error: null })

  render() {
    if (this.state.error) {
      if (this.props.fallback) return this.props.fallback(this.state.error, this.reset)
      return (
        <div className="flex h-full min-h-[240px] items-center justify-center p-6">
          <Card className="max-w-md">
            <CardHeader>
              <div className="flex items-center gap-2 text-[--color-danger]">
                <AlertTriangle className="h-4 w-4" />
                <CardTitle>Something went wrong</CardTitle>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <p className="text-sm text-[--color-text-muted]">
                {this.state.error.message || 'An unexpected error occurred.'}
              </p>
              <Button variant="secondary" size="sm" onClick={this.reset}>
                <RefreshCw className="h-4 w-4" />
                Try again
              </Button>
            </CardContent>
          </Card>
        </div>
      )
    }
    return this.props.children
  }
}
