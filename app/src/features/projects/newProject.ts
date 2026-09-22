import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'

/**
 * Write + read layer for the New project dialog.
 *
 * One RPC does the whole creation. The alternative — create_project, then
 * add_project_participant, then invite_stakeholder per client, from the
 * browser — cannot be made atomic: any failure after the first call leaves a
 * project with no lead, or a lead with no invited client, and no way to tell
 * which. create_project_full() does all of it in a single transaction.
 */

export interface CreatedInvite {
  email: string
  /** 'member' resolved to an existing workspace member; 'stakeholder' is external. */
  kind: 'member' | 'stakeholder'
  displayName?: string | null
  /** Present for stakeholders only. Shown ONCE — only its sha256 is stored. */
  token?: string | null
  expiresAt?: string | null
}

export interface CreateProjectResult {
  projectId: string
  slug: string
  code: string | null
  invites: CreatedInvite[]
}

export interface CreateProjectInput {
  name: string
  code: string | null
  description: string | null
  /** workspace_members.id of the lead. Null means the caller. */
  leadMemberId: string | null
  clientEmails: string[]
}

/** Raised when the server rejects the code. Carries the colliding project. */
export class CodeTakenError extends Error {
  constructor(public readonly conflictName: string | null) {
    super('PROJECT_CODE_TAKEN')
    this.name = 'CodeTakenError'
  }
}

/** Raised when the caller lacks workspace.manage. */
export class PermissionError extends Error {
  constructor() {
    super('forbidden')
    this.name = 'PermissionError'
  }
}

export function useCreateProject(workspaceId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: CreateProjectInput): Promise<CreateProjectResult> => {
      const { data, error } = await supabase.rpc('create_project_full', {
        p_workspace_id: workspaceId,
        p_name: input.name,
        p_code: input.code,
        p_description: input.description,
        p_lead_member_id: input.leadMemberId,
        p_client_emails: input.clientEmails,
      })
      if (error) {
        // The server distinguishes these two by errcode. Everything else is
        // surfaced as an unknown failure rather than as a raw database string.
        if (error.code === '23505' && error.message?.includes('PROJECT_CODE_TAKEN')) {
          throw new CodeTakenError(error.details ?? null)
        }
        if (error.code === '42501') throw new PermissionError()
        throw error
      }
      const row = (Array.isArray(data) ? data[0] : data) as {
        out_project_id: string
        out_slug: string
        out_code: string | null
        out_invites: CreatedInvite[] | null
      }
      return {
        projectId: row.out_project_id,
        slug: row.out_slug,
        code: row.out_code,
        invites: row.out_invites ?? [],
      }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: qk.projects(workspaceId) })
      qc.invalidateQueries({ queryKey: ['home'] })
    },
  })
}

/**
 * Availability probe for the code field, on blur.
 *
 * Advisory only. projects.code has no unique index, so this cannot be the
 * guarantee — the RPC re-checks inside the transaction and is what actually
 * rejects. See the gap note in the APP 014 report.
 */
export function useCodeAvailability(workspaceId: string, code: string) {
  const probe = code.trim().toUpperCase()
  return useQuery({
    queryKey: ['project-code', workspaceId, probe],
    enabled: Boolean(workspaceId) && probe.length > 0,
    staleTime: 30_000,
    retry: false,
    queryFn: async (): Promise<{ available: boolean; conflictName: string | null }> => {
      const { data, error } = await supabase.rpc('check_project_code', {
        p_workspace_id: workspaceId,
        p_code: probe,
      })
      if (error) throw error
      const row = (Array.isArray(data) ? data[0] : data) as {
        out_available: boolean
        out_conflict_name: string | null
      }
      return { available: row.out_available, conflictName: row.out_conflict_name }
    },
  })
}

/** Active members of the workspace, for the lead picker. */
export function useWorkspaceMemberOptions(workspaceId: string | undefined) {
  return useQuery({
    queryKey: ['workspace-member-options', workspaceId ?? ''],
    enabled: Boolean(workspaceId),
    staleTime: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('workspace_members')
        .select('id, user_id, role, profile:profiles!workspace_members_user_id_fkey(display_name, email)')
        .eq('workspace_id', workspaceId as string)
        .eq('status', 'active')
      if (error) throw error
      type Raw = {
        id: string
        user_id: string
        role: string
        profile: { display_name: string | null; email: string } | null
      }
      return ((data ?? []) as unknown as Raw[])
        .map((m) => ({
          memberId: m.id,
          userId: m.user_id,
          name: m.profile?.display_name ?? m.profile?.email ?? 'Unknown',
          email: (m.profile?.email ?? '').toLowerCase(),
        }))
        .sort((a, b) => a.name.localeCompare(b.name))
    },
  })
}

/**
 * Uppercase initials of the first three words: "Northgate Flagship" -> NGF.
 *
 * The codebase had no project-code convention to follow — projects.slug is the
 * URL identifier and is lowercase-hyphenated, which is a different thing — so
 * this is the initials rule from the brief.
 */
export function deriveCode(name: string): string {
  const words = name
    .trim()
    .split(/[\s\-_/]+/)
    .filter((w) => /[a-z0-9]/i.test(w))
  if (words.length === 0) return ''
  const letters =
    words.length === 1
      ? words[0]!.replace(/[^a-z0-9]/gi, '').slice(0, 3)
      : words.slice(0, 3).map((w) => w.replace(/[^a-z0-9]/gi, '')[0] ?? '').join('')
  return letters.toUpperCase().slice(0, 16)
}

export const CODE_RE = /^[A-Z0-9][A-Z0-9-]{0,15}$/
export const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

/** "NGF" taken -> "NGF2"; "NGF2" taken -> "NGF3". */
export function suggestCode(code: string): string {
  const m = code.match(/^(.*?)(\d+)$/)
  if (m) return `${m[1]}${Number(m[2]) + 1}`.slice(0, 16)
  return `${code}2`.slice(0, 16)
}
