import { Link } from 'react-router'
import { Button } from '@/ui/button'
import { EmptyState } from '@/ui/empty-state'
import { Compass } from 'lucide-react'

export function NotFound() {
  return (
    <div className="p-8">
      <EmptyState
        icon={<Compass className="h-8 w-8" />}
        title="Page not found"
        description="The route you tried to reach doesn't exist, or you don't have access to it."
        action={
          <Button asChild variant="secondary" size="sm">
            <Link to="/">Return home</Link>
          </Button>
        }
      />
    </div>
  )
}
