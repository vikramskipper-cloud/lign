import { Link, useNavigate } from 'react-router'
import { LogOut, ShieldCheck, UserRound } from 'lucide-react'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import { Avatar, AvatarFallback } from '@/ui/avatar'
import { Button } from '@/ui/button'
import { useSession } from '@/auth/SessionProvider'
import {
  useIsPlatformAdmin,
  usePendingAccessRequestCount,
} from '@/features/access/accessRequests'

function initials(email: string | null | undefined): string {
  if (!email) return '?'
  const local = email.split('@')[0]
  return local.slice(0, 2).toUpperCase()
}

export function UserMenu() {
  const { user, signOut } = useSession()
  const navigate = useNavigate()

  /**
   * Platform administration lives HERE, in the account menu, and not in the
   * workspace switcher where APP 020 first put it.
   *
   * The switcher is customer furniture — organisations, workspaces, their
   * people. Operating LIGN is not a senior tier of that tree, it is a property
   * of who you are, and putting "Access requests" beside "Organisation people"
   * implied the same authority runs both. It does not: see APP 021.
   *
   * Hidden rather than disabled for everyone else. Nothing leaks either way —
   * RLS and decide_access_request both re-check server-side — but a control
   * you can see and never use reads as a broken feature.
   */
  const isOperator = useIsPlatformAdmin()
  const pending = usePendingAccessRequestCount()

  const handleSignOut = async () => {
    await signOut()
    navigate('/sign-in', { replace: true })
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" aria-label="Account menu">
          <Avatar className="h-7 w-7">
            <AvatarFallback>{initials(user?.email)}</AvatarFallback>
          </Avatar>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="min-w-[14rem]">
        <DropdownMenuLabel className="flex items-center gap-2">
          <UserRound className="h-3.5 w-3.5" />
          <span className="truncate">{user?.email ?? 'Signed in'}</span>
        </DropdownMenuLabel>

        {isOperator.data === true && (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuLabel className="text-[--color-text-muted] text-xs font-normal">
              LIGN platform
            </DropdownMenuLabel>
            <DropdownMenuItem asChild>
              <Link to="/access-requests" className="flex w-full items-center gap-2">
                <ShieldCheck className="h-4 w-4" />
                <span className="flex-1">Access requests</span>
                {pending > 0 && (
                  <span
                    aria-label={`${pending} waiting`}
                    className="grid h-[18px] min-w-[18px] place-items-center rounded-full bg-[--color-brand] px-[5px] text-[11px] font-semibold text-white"
                  >
                    {pending}
                  </span>
                )}
              </Link>
            </DropdownMenuItem>
          </>
        )}

        <DropdownMenuSeparator />
        <DropdownMenuItem onSelect={handleSignOut}>
          <LogOut className="h-4 w-4" />
          Sign out
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
