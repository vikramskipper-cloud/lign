import { useParams, useSearchParams } from 'react-router'
import { useNavigationContext } from '@/shell/navigationContext'

export function useFeedScope() {
  const context = useNavigationContext()
  const { ws_id } = useParams()
  const [params, setParams] = useSearchParams()
  const options = context.workspaces.filter(w => w.organization_id === context.organizationId && w.status === 'active')
  const requested = ws_id ?? params.get('ws')
  const workspaceId = options.some(w => w.id === requested) ? requested! : undefined
  return { ...context, options, workspaceId, setWorkspace: (id: string) => {
    const next = new URLSearchParams(params)
    if (context.organizationId) next.set('org', context.organizationId)
    id ? next.set('ws', id) : next.delete('ws')
    setParams(next)
  } }
}
export function FeedScope({ scope }: { scope: ReturnType<typeof useFeedScope> }) {
  return <label className="overview-small">Viewing <select className="auth-field ml-2" aria-label="Workspace scope" value={scope.workspaceId ?? ''} onChange={e => scope.setWorkspace(e.target.value)}><option value="">All workspaces</option>{scope.options.map(w => <option key={w.id} value={w.id}>{w.name}</option>)}</select></label>
}
