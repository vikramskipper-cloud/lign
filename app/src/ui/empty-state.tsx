import * as React from 'react'
import { cn } from '@/lib/cn'

interface EmptyStateProps {
  icon?: React.ReactNode
  title: string
  description?: string
  action?: React.ReactNode
  className?: string
}

export function EmptyState({ icon, title, description, action, className }: EmptyStateProps) {
  return (
    <div
      className={cn(
        'flex flex-col items-center justify-center gap-3 rounded-[--radius-lg] border border-dashed border-[--color-border] bg-[--color-surface] px-6 py-16 text-center',
        className,
      )}
    >
      {icon && <div className="text-[--color-text-subtle]">{icon}</div>}
      <div className="space-y-1">
        <h3 className="text-sm font-semibold text-[--color-text]">{title}</h3>
        {description && (
          <p className="mx-auto max-w-md text-sm text-[--color-text-muted]">{description}</p>
        )}
      </div>
      {action && <div className="mt-2">{action}</div>}
    </div>
  )
}
