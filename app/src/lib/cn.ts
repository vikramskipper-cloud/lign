import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

/** Merge Tailwind classes safely (last-write-wins for conflicting utilities). */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs))
}
