import { useState } from 'react'
import { Link } from 'react-router'
import { attentionLabels, orderAttention, type AttentionItem } from './hub'
import { relative, absolute } from '@/lib/formatDate'

export type ContextAttention = AttentionItem & { context?: string }
export function AttentionList({ items, empty = 'No pending decisions.', initialLimit = 6 }: {
  items: ContextAttention[]; empty?: string; initialLimit?: number
}) {
  const [limit, setLimit] = useState(initialLimit)
  const rows = orderAttention(items)
  if (!rows.length) return <p className="overview-muted">{empty}</p>
  return <>
    <ul className="overview-action-list">{rows.slice(0, limit).map(item => {
      const overdue = Boolean(item.dueAt && new Date(item.dueAt).getTime() < Date.now())
      return <li key={item.id}>
        <div className="overview-row-heading"><span className="overview-tag">{attentionLabels[item.kind]}</span><span className={item.canAct ? 'overview-mine' : 'overview-muted'}>{item.canAct ? 'Needs your action' : item.audience === 'client' ? 'Waiting on approver' : item.audience === 'reviewers' ? 'Waiting on reviewers' : 'Needs the team'}</span></div>
        <Link className="overview-action-title" to={item.to}>{item.title} <span aria-hidden="true">→</span></Link>
        <p className="overview-muted">{item.context ? `${item.context} · ` : ''}{item.responsible}</p>
        <p className={overdue ? 'overview-overdue' : 'overview-small'} title={absolute(item.since)}>Waiting {relative(item.since).replace(/ ago$/,'')}{item.dueAt && <> · {overdue ? 'Overdue · ' : 'Due '}{absolute(item.dueAt)}</>}</p>
      </li>
    })}</ul>
    {rows.length > limit && <button className="auth-link overview-more" onClick={() => setLimit(n => n + 10)}>Show more ({rows.length - limit} remaining)</button>}
  </>
}
