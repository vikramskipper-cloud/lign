import { Link } from 'react-router'
import { Lock } from 'lucide-react'
import { Button } from '@/ui/button'
import { EmptyState } from '@/ui/empty-state'

export function AccessDeniedPage({ capability }: { capability?: string }) {
  return (
    <div className="p-8">
      <EmptyState
        icon={<Lock className="h-8 w-8" />}
        title="Access denied"
        description={
          capability
            ? `You don't have the required capability (${capability}) for this page.`
            : "You don't have permission to view this page."
        }
        action={
          <Button asChild variant="secondary" size="sm">
            <Link to="/dashboard">Return home</Link>
          </Button>
        }
      />
    </div>
  )
}
