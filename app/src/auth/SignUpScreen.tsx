import * as React from 'react'
import { Link, Navigate, useNavigate, useSearchParams } from 'react-router'
import { toast } from 'sonner'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import { Label } from '@/ui/label'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/ui/card'
import { LoadingPage } from '@/ui/loading-page'
import { useSession } from '@/auth/SessionProvider'
import { supabase } from '@/lib/supabase'

const SAFE_REDIRECT_RE = /^\/[^/].*$/

/**
 * APP 013 G-2.
 *
 * Until this existed, an invite link sent to someone without an account was a
 * dead end: sign-in was password-only and there was no way to create an
 * account. That made "onboard your second user" impossible regardless of how
 * good the People screens were.
 *
 * The email entered here must match the invitation's, because both
 * accept_invitation and claim_stakeholder_invitation compare the invitation
 * email against auth.users.email and reject a mismatch. Signing up under a
 * different address produces a valid account that cannot accept the invite, so
 * the form says so before it happens rather than after.
 */
export function SignUpScreen() {
  const { session, isLoading } = useSession()
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const [email, setEmail] = React.useState(searchParams.get('email') ?? '')
  const [displayName, setDisplayName] = React.useState('')
  const [password, setPassword] = React.useState('')
  const [submitting, setSubmitting] = React.useState(false)

  const rawReturnTo = searchParams.get('returnTo') ?? ''
  const returnTo = SAFE_REDIRECT_RE.test(rawReturnTo) ? rawReturnTo : '/'
  const invited = returnTo.startsWith('/invite/')

  if (isLoading) return <LoadingPage label="Loading…" />
  if (session) return <Navigate to={returnTo} replace />

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (submitting) return
    setSubmitting(true)
    const { data, error } = await supabase.auth.signUp({
      email: email.trim(),
      password,
      options: { data: { display_name: displayName.trim() || email.trim().split('@')[0] } },
    })
    setSubmitting(false)

    if (error) {
      toast.error(error.message || 'Could not create the account')
      return
    }
    // With email confirmation enabled Supabase returns a user but no session;
    // there is nowhere to navigate to yet, so say so instead of silently
    // landing on a redirect that bounces back to sign-in.
    if (!data.session) {
      toast.success('Account created — check your email to confirm, then sign in.')
      navigate(`/signin?returnTo=${encodeURIComponent(returnTo)}`, { replace: true })
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
            <CardTitle>Create your account</CardTitle>
          </div>
          <CardDescription>
            {invited
              ? 'Use the same email address the invitation was sent to — the invite will not accept a different one.'
              : 'Design collaboration and version control.'}
          </CardDescription>
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
              <Label htmlFor="name">Name</Label>
              <Input
                id="name"
                autoComplete="name"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                disabled={submitting}
                placeholder="How your name appears on comments"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                autoComplete="new-password"
                required
                minLength={8}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={submitting}
              />
            </div>
            <Button type="submit" className="w-full" disabled={submitting}>
              {submitting ? 'Creating…' : 'Create account'}
            </Button>
          </form>

          <p className="mt-4 text-center text-sm text-[--color-text-muted]">
            Already have an account?{' '}
            <Link
              className="text-[--color-brand] underline-offset-2 hover:underline"
              to={`/signin?returnTo=${encodeURIComponent(returnTo)}`}
            >
              Sign in
            </Link>
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
