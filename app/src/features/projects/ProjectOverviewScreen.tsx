import * as React from 'react'
import { Link, useNavigate, useParams } from 'react-router'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { MoreVertical, Pencil, Archive } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/ui/button'
import { EmptyState } from '@/ui/empty-state'
import { LoadingPage } from '@/ui/loading-page'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import { StatusBadge } from '@/features/shared/StatusBadge'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { useProject } from '@/shell/queries'
import { useProjectCapabilities } from '@/lib/capabilities'
import { humanizeError } from '@/features/shared/errors'
const EditProjectDialog = React.lazy(() => import('./EditProjectDialog').then(m=>({default:m.EditProjectDialog})))
import { relative, absolute } from '@/lib/formatDate'
import { useProjectSummary, orderAttention, activityLabel } from '@/features/oversight/hub'
import { AttentionList } from '@/features/oversight/AttentionList'
import '@/features/oversight/overview.css'

export const ProjectOverviewHandle = { crumb: 'Overview' }


export function ProjectOverviewScreen() {
  const { ws_id, proj_id } = useParams<{ ws_id: string; proj_id: string }>()
  const navigate = useNavigate()
  const qc = useQueryClient()
  const project = useProject(proj_id)
  const caps = useProjectCapabilities(proj_id ?? '', ws_id ?? '')
  const summary = useProjectSummary(proj_id)
  const [editOpen, setEditOpen] = React.useState(false)

  const archive = useMutation({
    mutationFn: async () => {
      const { error } = await supabase
        .from('projects')
        .update({ status: 'archived', archived_at: new Date().toISOString() })
        .eq('id', proj_id as string)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Project archived')
      qc.invalidateQueries({ queryKey: qk.project(proj_id as string) })
      qc.invalidateQueries({ queryKey: qk.projects(ws_id as string) })
      navigate(`/workspace/${ws_id}/projects`)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  if (project.isLoading) return <LoadingPage />
  if (!project.data || !proj_id || !ws_id) {
    return (
      <div className="p-8">
        <EmptyState title="Project not found" />
      </div>
    )
  }

  const p = project.data
  const data = summary.data
  const base = `/workspace/${ws_id}/project/${proj_id}/`
  const next = data && orderAttention(data.actions)[0]
  const canEdit = Boolean(caps.data?.['project.edit'])
  const canArchive = Boolean(caps.data?.['project.archive'])

  return (
    <div className="overview-page">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0 space-y-1">
          <div className="flex items-center gap-2">
            <h1>Project overview</h1>
            <StatusBadge status={p.status} />
          </div>
          {p.description && <p className="text-sm text-[--color-text-muted]">{p.description}</p>}
          <div className="flex items-center gap-2 text-xs text-[--color-text-subtle]">
            {p.code && <span className="font-mono">{p.code}</span>}
            {p.code && <span aria-hidden>·</span>}
            <span title={absolute(p.updated_at)}>updated {relative(p.updated_at)}</span>
          </div>
        </div>
        {(canEdit || canArchive) && (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon" aria-label="Project actions">
                <MoreVertical className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              {canEdit && (
                <DropdownMenuItem onSelect={() => setEditOpen(true)}>
                  <Pencil className="h-4 w-4" />
                  Edit project
                </DropdownMenuItem>
              )}
              {canArchive && (
                <DropdownMenuItem
                  onSelect={() => {
                    if (window.confirm('Archive this project? It will be hidden from the projects list.')) {
                      archive.mutate()
                    }
                  }}
                  className="text-[--color-danger]"
                >
                  <Archive className="h-4 w-4" />
                  Archive project
                </DropdownMenuItem>
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </div>

      {summary.isLoading && <p role="status" className="overview-panel overview-muted">Checking the project phase and pending decisions…</p>}
      {summary.isError && <div role="alert" className="overview-panel"><p>Could not load the project summary.</p><button className="auth-link mt-3" onClick={() => void summary.refetch()}>Try again</button></div>}
      {data && <>
        <section className="overview-panel overview-phase" aria-label="Current phase and next action">
          <p className="overview-eyebrow">Current phase · {data.phase}</p>
          <h2>{next ? next.title : data.internal ? data.designReady ? 'Continue detailed design' : 'Review the project brief' : 'Your shared project work'}</h2>
          <p className="overview-muted">{next ? `${next.canAct ? 'Ready for your action' : 'Waiting on'} · ${next.responsible}` : data.internal ? 'No pending decisions. Open the project work to continue.' : 'Only work shared with you and decisions assigned to you appear here.'}</p>
          <Link className="overview-button overview-primary" to={next?.to ?? (data.designReady ? data.internal ? base + 'designs' : data.shared[0]?.to ?? base + 'brief' : base + 'brief')}>{next ? next.canAct ? 'Take action' : 'View pending item' : data.designReady && data.internal ? 'Open design work' : data.shared.length ? 'View shared version' : 'Open project brief'}</Link>
          <ol className="overview-journey" aria-label="Project journey">
            <li aria-current={!data.briefReady ? 'step' : undefined}>{data.briefReady ? '✓ ' : ''}Requirements & brief agreement</li>
            <li aria-current={data.briefReady && !data.designReady ? 'step' : undefined}>{data.designReady ? '✓ ' : ''}Proposal acceptance</li>
            <li aria-current={data.designReady ? 'step' : undefined}>Detailed design & decisions</li>
          </ol>
        </section>
        <section className="overview-panel" aria-label="Pending decisions">
          <div className="overview-section-heading"><h2>Pending decisions & next steps</h2><span className="overview-small">{data.actions.filter(a => a.canAct).length} need your action · {data.actions.length} total</span></div>
          <AttentionList items={data.actions} empty="No pending decisions for this project." />
        </section>
        <div className="overview-grid">
          <section className="overview-panel" aria-label="Shared and accepted work">
            <h2>Shared & accepted work</h2>
            <p className="overview-muted">Brief: {data.accepted.brief ? 'Agreed' : 'Not yet agreed'} · Proposal: {data.accepted.proposal ? 'Accepted' : 'Not yet accepted'}</p>
            {data.accepted.briefRevision && <p className="mt-2 text-sm"><Link className="auth-link" to={base + 'brief?step=agreement&revision='+data.accepted.briefRevision.id}>View agreed brief · r{data.accepted.briefRevision.number}</Link></p>}
            {data.accepted.proposalRevision && <p className="mt-2 text-sm"><Link className="auth-link" to={base + 'proposal?revision='+data.accepted.proposalRevision.id}>View accepted proposal · r{data.accepted.proposalRevision.number}</Link></p>}
            <ul className="overview-action-list">{data.shared.map(version => <li key={version.id}>
              <Link className="overview-action-title" to={version.to}>{version.name} · v{version.revision}</Link>
              <p className="overview-small">{version.decisionStatus ? `Approval: ${version.decisionStatus.replaceAll('_',' ')} · ` : 'No design approval request · '}Shared {relative(version.at)}{version.recipients ? ` · ${version.recipients}` : ''}</p>
            </li>)}</ul>
            {!data.shared.length && <p className="overview-muted">{data.internal ? 'No design versions have been shared with project participants yet.' : 'No design versions are currently shared with you.'}</p>}
          </section>
          <section className="overview-panel" aria-label="Project essentials">
            <div className="overview-section-heading"><h2>Project essentials</h2><Link className="auth-link text-sm" to={base + 'people'}>Team & access</Link></div>
            <p className="overview-muted">Project lead: {data.lead}</p>
            {(p.client_company || p.client_contact_name) && <p className="overview-muted">Client: {[p.client_company, p.client_contact_name].filter(Boolean).join(' · ')}</p>}
            <details className="overview-details mt-4"><summary>Client contact & project details</summary><dl>
              {[['Email',p.client_email],['Phone',p.client_phone],['Project code',p.code],['Created',absolute(p.created_at)]].filter(([,value]) => value).map(([label,value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}
            </dl></details>
          </section>
        </div>
        <section className="overview-panel" aria-label="Recent project activity">
          <h2>Recent activity</h2>
          {!data.activity.length && <p className="overview-muted">Project updates will appear here as work progresses.</p>}
          <ul className="overview-action-list">{data.activity.map(event => <li key={event.id}><p className="text-sm">{event.actor} · {activityLabel(event.eventType)}{event.subject ? ` · ${event.subject}` : ''}</p><p className="overview-small">{relative(event.at)}</p></li>)}</ul>
        </section>
      </>}

      {editOpen&&<React.Suspense fallback={null}><EditProjectDialog project={p} open={editOpen} onOpenChange={setEditOpen} /></React.Suspense>}
    </div>
  )
}
