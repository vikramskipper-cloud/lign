import { useParams } from 'react-router'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/ui/card'

/**
 * Invitation-claim entry point. The real flow (accept_invitation /
 * claim_stakeholder_invitation) lands in APP 010 (stakeholder experience).
 * APP 002 renders the landing so the route resolves.
 */
export function InviteClaimScreen() {
  const { token } = useParams<{ token: string }>()
  return (
    <div className="flex min-h-full items-center justify-center bg-[--color-bg] p-6">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>You've been invited to Lign</CardTitle>
          <CardDescription>
            Invitation claim flow lands in APP 010. Token detected:{' '}
            <code className="font-mono text-xs">{token?.slice(0, 8)}…</code>
          </CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-[--color-text-muted]">
            Sign in with the email that received the invitation to activate your access.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
