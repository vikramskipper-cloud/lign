import { useNavigate } from 'react-router'
import { FolderOpen, Mail } from 'lucide-react'
import { Button } from '@/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/ui/card'
import { LoadingPage } from '@/ui/loading-page'
import { EmptyState } from '@/ui/empty-state'
import { useWorkspaces } from '@/shell/queries'
import { persistLastWorkspace } from '@/shell/WorkspaceSwitcher'

/**
 * Shown to users with 0 workspaces (invite-only landing) or >1 (pick-one).
 * "Create workspace" and "Accept invitation" flows land in later slices; this
 * screen makes the state legible for now.
 */
export function WorkspacePicker() {
  const { data, isLoading } = useWorkspaces()
  const navigate = useNavigate()

  if (isLoading) return <LoadingPage />

  const workspaces = data ?? []

  if (workspaces.length === 0) {
    return (
      <div className="mx-auto max-w-lg p-8">
        <EmptyState
          icon={<Mail className="h-8 w-8" />}
          title="You don't belong to any workspaces yet"
          description="Lign is invite-only during MVP. Ask a workspace admin to invite you, or accept an invitation you've received by email."
        />
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-2xl space-y-4 p-8">
      <div className="space-y-1">
        <h1 className="text-xl font-semibold">Choose a workspace</h1>
        <p className="text-sm text-[--color-text-muted]">
          You belong to {workspaces.length} workspaces.
        </p>
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        {workspaces.map((ws) => (
          <Card key={ws.id} className="cursor-default transition-colors hover:border-[--color-border-strong]">
            <CardHeader>
              <div className="flex items-center gap-2">
                <FolderOpen className="h-4 w-4 text-[--color-text-muted]" />
                <CardTitle className="truncate">{ws.name}</CardTitle>
              </div>
              <CardDescription className="truncate">{ws.slug}</CardDescription>
            </CardHeader>
            <CardContent>
              <Button
                size="sm"
                onClick={() => {
                  persistLastWorkspace(ws.id)
                  navigate(`/workspace/${ws.id}/projects`)
                }}
              >
                Open workspace
              </Button>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  )
}
