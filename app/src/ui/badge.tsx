import * as React from 'react'
import { cva, type VariantProps } from 'class-variance-authority'
import { cn } from '@/lib/cn'

const badgeVariants = cva(
  'inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium',
  {
    variants: {
      variant: {
        neutral: 'bg-[--color-surface-2] text-[--color-text-muted]',
        brand: 'bg-[--color-brand] text-[--color-brand-fg]',
        success: 'bg-[--color-success]/15 text-[--color-success]',
        warning: 'bg-[--color-warning]/15 text-[--color-warning]',
        danger: 'bg-[--color-danger]/15 text-[--color-danger]',
        outline: 'border border-[--color-border] text-[--color-text-muted]',
      },
    },
    defaultVariants: { variant: 'neutral' },
  },
)

export interface BadgeProps
  extends React.HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof badgeVariants> {}

export function Badge({ className, variant, ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />
}
