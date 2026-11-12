import { Link } from 'react-router'
import { useProjectBrief } from './queries'
import { BRIEF_STATUS_LABELS } from './status'
export function BriefStartCard({workspaceId,projectId}:{workspaceId:string;projectId:string}) {
  const brief=useProjectBrief(projectId)
  return <section className="rounded-xl border border-[--color-border] bg-[--color-surface] p-5">
    <div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="font-semibold">Start with the project brief</h2><p className="mt-1 text-sm text-[--color-text-muted]">Gather needs, clarify requirements and agree a shared starting point.</p></div><Link className="auth-link text-sm" to={`/workspace/${workspaceId}/project/${projectId}/brief`}>{brief.data?.brief ? BRIEF_STATUS_LABELS[brief.data.brief.status]+' · Open brief' : 'Open project brief'}</Link></div>
  </section>
}
