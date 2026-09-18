import { Loader2 } from 'lucide-react'
import { cn } from '@/lib/cn'

interface LoadingPageProps {
  label?: string
  className?: string
}

export function LoadingPage({ label = 'Loading…', className }: LoadingPageProps) {
  return (
    <div
      className={cn(
        'flex h-full min-h-[240px] flex-col items-center justify-center gap-2 text-[--color-text-muted]',
        className,
      )}
    >
      <Loader2 className="h-5 w-5 animate-spin" />
      <span className="text-xs">{label}</span>
    </div>
  )
}
