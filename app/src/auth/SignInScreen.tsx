import * as React from 'react'
import { Navigate, useNavigate, useSearchParams } from 'react-router'
import { toast } from 'sonner'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import { Label } from '@/ui/label'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/ui/card'
import { LoadingPage } from '@/ui/loading-page'
import { useSession } from '@/auth/SessionProvider'
import { supabase } from '@/lib/supabase'

const SAFE_REDIRECT_RE = /^\/[^/].*$/

export function SignInScreen() {
  const { session, isLoading } = useSession()
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const [email, setEmail] = React.useState('')
  const [password, setPassword] = React.useState('')
  const [submitting, setSubmitting] = React.useState(false)

  const rawReturnTo = searchParams.get('returnTo') ?? ''
  const returnTo = SAFE_REDIRECT_RE.test(rawReturnTo) ? rawReturnTo : '/'

  if (isLoading) return <LoadingPage label="Loading…" />
  if (session) return <Navigate to={returnTo} replace />

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (submitting) return
    setSubmitting(true)
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    setSubmitting(false)
    if (error) {
      toast.error(error.message || 'Sign-in failed')
      return
    }
    navigate(returnTo, { replace: true })
  }

  return (
    <div className="flex min-h-full items-center justify-center bg-[--color-bg] p-6">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <div className="flex items-center gap-2">
            <div className="grid h-8 w-8 place-items-center rounded-[--radius-md] bg-[--color-text] text-[--color-brand-fg]">
              <span className="font-bold">L</span>
            </div>
            <CardTitle>Sign in to Lign</CardTitle>
          </div>
          <CardDescription>Design collaboration and version control.</CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={onSubmit} className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                disabled={submitting}
                autoFocus
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                autoComplete="current-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={submitting}
              />
            </div>
            <Button type="submit" className="w-full" disabled={submitting}>
              {submitting ? 'Signing in…' : 'Sign in'}
            </Button>
            <p className="text-center text-xs text-[--color-text-muted]">
              Access is invite-only during MVP.
            </p>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
