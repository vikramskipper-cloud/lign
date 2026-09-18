import { cn } from '@/lib/cn'

interface Props {
  label: string
  tone?: 'neutral' | 'muted'
  className?: string
}

/** APP 008 §11.8 primitive: small chip for source / category / scope. */
export function ScopeChip({ label, tone = 'neutral', className }: Props) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide',
        tone === 'neutral'
          ? 'text-[--color-text-muted] bg-[--color-surface-2] border border-[--color-border]'
          : 'text-[--color-text-subtle] bg-[--color-surface-2] border border-dashed border-[--color-border]',
        className,
      )}
    >
      {label}
    </span>
  )
}
