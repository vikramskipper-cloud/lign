import { useInfiniteQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useNavigate, useSearchParams } from 'react-router'
import { useSession } from '@/auth/SessionProvider'
import { supabase } from '@/lib/supabase'
import { FeedScope, useFeedScope } from '@/features/oversight/FeedScope'
import { NotificationCard } from './NotificationCard'
import { NotificationFilterBar } from './NotificationFilterBar'
import type { InboxFilters, InboxResponse, InboxTab } from './types'
import '@/features/oversight/overview.css'

const tabs: { key: InboxTab; label: string }[] = [
  { key:'all',label:'All' }, { key:'unread',label:'Unread' }, { key:'mentions',label:'Mentions' },
  { key:'assigned',label:'Assigned' }, { key:'governance',label:'Governance' }, { key:'archived',label:'Archived' },
]
export function Component() {
  const scope = useFeedScope(), { user } = useSession(), navigate = useNavigate(), qc = useQueryClient()
  const [params, setParams] = useSearchParams()
  const tab = tabs.find(t => t.key === params.get('tab'))?.key ?? 'all'
  const split = <T extends string>(key: string) => params.get(key)?.split(',').filter(Boolean) as T[] | undefined
  const filters: InboxFilters = { category:split('category'), priority:split('priority'), source:split('source'), dateFrom:params.get('dateFrom'), dateTo:params.get('dateTo') }
  const query = useInfiniteQuery({
    queryKey: ['notification', 'organization-inbox', user?.id, scope.organizationId, scope.workspaceId, tab, filters],
    enabled: Boolean(user && scope.organizationId), initialPageParam: null as InboxResponse['next_cursor'], refetchInterval: 30_000,
    queryFn: async ({ pageParam }): Promise<InboxResponse> => {
      const { data, error } = await supabase.rpc('list_organization_notifications', {
        p_organization_id: scope.organizationId, p_workspace_id: scope.workspaceId ?? null, p_tab: tab,
        p_filters: filters, p_before: pageParam?.created_at ?? null, p_before_id: pageParam?.id ?? null, p_limit:30,
      })
      if (error) throw error
      return data as InboxResponse
    }, getNextPageParam: page => page.next_cursor ?? undefined,
  })
  const mutation = useMutation({
    mutationFn: async ({ action, id }: { action:'read'|'archive'|'dismiss'|'all'; id?:string }) => {
      const rpc = action==='all' ? 'mark_organization_notifications_read' : action==='read' ? 'mark_notification_read' : action==='archive' ? 'archive_notification' : 'dismiss_notification'
      const args = action==='all' ? {p_organization_id:scope.organizationId,p_workspace_id:scope.workspaceId??null} : {p_notification_id:id}
      const { error } = await supabase.rpc(rpc,args)
      if (error) throw error
    }, onSuccess: () => void qc.invalidateQueries({ queryKey:['notification'] }),
  })
  const applyFilters = (next: InboxFilters) => {
    const p = new URLSearchParams(params)
    for (const key of ['category','priority','source'] as const) next[key]?.length ? p.set(key,next[key]!.join(',')) : p.delete(key)
    for (const key of ['dateFrom','dateTo'] as const) next[key] ? p.set(key,next[key]!) : p.delete(key)
    setParams(p)
  }
  const unread = query.data?.pages[0]?.facets.unread_count ?? 0
  const rows = query.data?.pages.flatMap(p => p.rows) ?? []
  return <div className="overview-page">
    <header className="overview-heading"><div><p className="overview-eyebrow">{scope.organizationName}</p><h1>Inbox</h1><p className="overview-muted">Updates and notifications from your accessible workspaces. Use My work for current actions.</p></div><FeedScope scope={scope}/></header>
    <section className="overview-panel"><div className="overview-section-heading"><div className="flex flex-wrap gap-2" role="group" aria-label="Inbox views">{tabs.map(t=><button key={t.key} aria-pressed={t.key===tab} className={`overview-button ${t.key===tab?'overview-primary':''}`} onClick={()=>{const p=new URLSearchParams(params);p.set('tab',t.key);setParams(p)}}>{t.label}</button>)}</div><button className="auth-link text-sm" disabled={mutation.isPending||!unread} onClick={()=>mutation.mutate({action:'all'})}>Mark all read ({unread})</button></div>
      <NotificationFilterBar filters={filters} onChange={applyFilters}/>
      {mutation.isError&&<p role="alert" className="overview-overdue">Could not update this notification. Try again.</p>}
      {(scope.isLoading||query.isLoading)&&<p role="status" className="overview-muted">Loading notifications…</p>}
      {(scope.isError||query.isError)&&<p role="alert">Could not load notifications. <button className="auth-link" onClick={()=>{void scope.refresh();void query.refetch()}}>Retry</button></p>}
      {!query.isLoading&&!query.isError&&!rows.length&&<p className="overview-muted">No notifications in this view.</p>}
      <div className="mt-4 space-y-3">{rows.map(n=><div key={n.id}><p className="overview-small mb-1">{scope.options.find(w=>w.id===n.workspace_id)?.name ?? 'Shared workspace'}</p><NotificationCard notification={n}
        onOpen={()=>{mutation.mutate({action:'read',id:n.id});const dl=n.payload?.deep_link;if(dl?.kind&&dl.id)navigate(`/deep/${dl.kind}/${dl.id}`)}}
        onMarkRead={n.read_at?undefined:()=>mutation.mutate({action:'read',id:n.id})}
        onArchive={n.archived_at?undefined:()=>mutation.mutate({action:'archive',id:n.id})}
        onDismiss={n.dismissed_at?undefined:()=>mutation.mutate({action:'dismiss',id:n.id})}/></div>)}</div>
      {query.hasNextPage&&<button className="overview-button mt-4" disabled={query.isFetchingNextPage} onClick={()=>void query.fetchNextPage()}>{query.isFetchingNextPage?'Loading…':'Load more notifications'}</button>}
    </section>
  </div>
}
