import type { PostgrestError } from '@supabase/supabase-js'

/**
 * Translate common Supabase / Postgres errors into user-facing copy.
 * Falls back to the raw message so we never eat information.
 */
export function humanizeError(err: unknown): string {
  const e = err as PostgrestError | Error | undefined
  if (!e) return 'Something went wrong.'
  const msg = 'message' in e ? String(e.message) : ''
  const code = 'code' in e ? String((e as PostgrestError).code ?? '') : ''

  // Postgres: unique_violation
  if (code === '23505') {
    if (msg.includes('projects_workspace_slug_key')) return 'That slug is already used in this workspace.'
    if (msg.includes('collections_project_name_active_key')) return 'A collection with that name already exists in this project.'
    if (msg.includes('disciplines_project_name_active_key')) return 'A discipline with that name already exists in this project.'
    return 'That value is already in use.'
  }
  // Postgres: check_violation
  if (code === '23514') return msg || 'That change is not allowed here.'
  // Postgres: foreign_key_violation
  if (code === '23503') return msg || 'A referenced record does not exist.'
  // insufficient_privilege
  if (code === '42501') return "You don't have permission to do that."
  // RLS block (PostgREST returns 401/403 sometimes with PGRST codes)
  if (code === 'PGRST301' || code === '401' || code === '403') {
    return "You don't have permission to do that."
  }

  return msg || 'Something went wrong.'
}

const SLUG_RE = /^[a-z0-9-]{1,60}$/

export function validateSlug(v: string): string | null {
  if (!v) return 'Required.'
  if (!SLUG_RE.test(v)) return 'Lowercase letters, digits, and dashes only (max 60).'
  return null
}

export function validateName(v: string, max = 200): string | null {
  const t = v.trim()
  if (!t) return 'Required.'
  if (t.length > max) return `Max ${max} characters.`
  return null
}
