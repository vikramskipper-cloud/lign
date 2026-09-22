import * as React from 'react'
import { useParams } from 'react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { supabase } from '@/lib/supabase'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/ui/card'
import { FormRow } from '@/ui/form-row'
import { AsyncBoundary } from '@/ui/async-boundary'
import { Skeleton } from '@/ui/skeleton'
import { useWorkspaceAccess } from '@/lib/capabilities'
import { humanizeError } from '@/features/shared/errors'
import { qk } from '@/lib/queryKeys'
import { absolute } from '@/lib/formatDate'

/**
 * Workspace settings — name and slug only.
 *
 * Owner transfer is deliberately absent: it needs the G-7 bootstrap decision
 * first, because neither existing workspace has an owner and only an owner may
 * grant that role. Shipping a transfer button that can never succeed would be
 * worse than not shipping one.
 */
export function WorkspaceSettingsScreen() {
  const { ws_id: wsId } = useParams<{ ws_id: string }>()
  const qc = useQueryClient()
  const access = useWorkspaceAccess(wsId)
  const canManage = Boolean(access.data?.['workspace.manage'])

  const ws = useQuery({
    queryKey: qk.workspace(wsId ?? ''),
    enabled: Boolean(wsId),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('workspaces')
        .select('id, name, slug, status, created_at')
        .eq('id', wsId as string)
        .single()
      if (error) throw error
      return data as { id: string; name: string; slug: string; status: string; created_at: string }
    },
  })

  const [name, setName] = React.useState('')
  const [slug, setSlug] = React.useState('')
  const [dirty, setDirty] = React.useState(false)

  React.useEffect(() => {
    if (ws.data && !dirty) {
      setName(ws.data.name)
      setSlug(ws.data.slug)
    }
  }, [ws.data, dirty])

  const save = useMutation({
    mutationFn: async () => {
      // No update RPC exists for workspaces; the RLS policy
      // workspaces_update_admin is the gate. If that policy ever tightens,
      // this needs an RPC rather than a looser policy.
      const { error } = await supabase
        .from('workspaces')
        .update({ name: name.trim(), slug: slug.trim() })
        .eq('id', wsId as string)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Workspace updated')
      setDirty(false)
      qc.invalidateQueries({ queryKey: qk.workspace(wsId ?? '') })
      qc.invalidateQueries({ queryKey: qk.workspaces() })
    },
    onError: (e) => toast.error(humanizeError(e)),
  })

  return (
    <div className="mx-auto w-full max-w-2xl space-y-6 p-6">
      <div>
        <h1 className="text-xl font-semibold">Workspace settings</h1>
        <p className="mt-1 text-sm text-[--color-text-muted]">
          Applies to every project in this workspace.
        </p>
      </div>

      <AsyncBoundary>
        <Card>
          <CardHeader>
            <CardTitle className="text-base">General</CardTitle>
            <CardDescription>
              {ws.data ? `Created ${absolute(ws.data.created_at)}` : 'Loading…'}
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {ws.isLoading && <Skeleton className="h-24 w-full" />}
            {ws.data && (
              <form
                className="space-y-4"
                onSubmit={(e) => {
                  e.preventDefault()
                  if (canManage && dirty) save.mutate()
                }}
              >
                <FormRow label="Name" htmlFor="ws-name">
                  <Input
                    id="ws-name"
                    value={name}
                    disabled={!canManage || save.isPending}
                    onChange={(e) => {
                      setName(e.target.value)
                      setDirty(true)
                    }}
                  />
                </FormRow>
                <FormRow
                  label="Slug"
                  htmlFor="ws-slug"
                  hint="Used in URLs. Must be unique across all workspaces."
                >
                  <Input
                    id="ws-slug"
                    value={slug}
                    disabled={!canManage || save.isPending}
                    onChange={(e) => {
                      setSlug(e.target.value)
                      setDirty(true)
                    }}
                  />
                </FormRow>

                {canManage ? (
                  <div className="flex gap-2">
                    <Button type="submit" disabled={!dirty || save.isPending}>
                      {save.isPending ? 'Saving…' : 'Save changes'}
                    </Button>
                    {dirty && (
                      <Button
                        type="button"
                        variant="ghost"
                        onClick={() => {
                          setName(ws.data.name)
                          setSlug(ws.data.slug)
                          setDirty(false)
                        }}
                      >
                        Reset
                      </Button>
                    )}
                  </div>
                ) : (
                  <p className="text-sm text-[--color-text-muted]">
                    Only workspace admins and owners can change these.
                  </p>
                )}
              </form>
            )}
          </CardContent>
        </Card>
      </AsyncBoundary>
    </div>
  )
}

WorkspaceSettingsScreen.handle = { crumb: 'Settings' }
