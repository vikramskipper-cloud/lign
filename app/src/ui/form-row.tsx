import * as React from 'react'
import { Label } from '@/ui/label'
import { cn } from '@/lib/cn'

interface FormRowProps {
  htmlFor?: string
  label: React.ReactNode
  hint?: React.ReactNode
  error?: React.ReactNode
  required?: boolean
  className?: string
  children: React.ReactNode
}

/**
 * Vertical label / control / hint / error stack used by every dialog form.
 * Consistent spacing lives here so forms don't drift.
 */
export function FormRow({
  htmlFor,
  label,
  hint,
  error,
  required,
  className,
  children,
}: FormRowProps) {
  return (
    <div className={cn('space-y-1.5', className)}>
      <Label htmlFor={htmlFor}>
        {label}
        {required && <span className="ml-0.5 text-[--color-danger]">*</span>}
      </Label>
      {children}
      {error ? (
        <p className="text-xs text-[--color-danger]">{error}</p>
      ) : hint ? (
        <p className="text-xs text-[--color-text-subtle]">{hint}</p>
      ) : null}
    </div>
  )
}
