import { Badge } from '@/ui/badge'

type Kind =
  | 'draft'
  | 'active'
  | 'deprecated'
  | 'archived'
  | 'published'
  | 'superseded'
  | 'on_hold'
  | 'closed'

const map: Record<Kind, { label: string; variant: 'neutral' | 'brand' | 'success' | 'warning' | 'danger' | 'outline' }> = {
  draft:      { label: 'Draft',      variant: 'outline' },
  active:     { label: 'Active',     variant: 'success' },
  published:  { label: 'Published',  variant: 'success' },
  superseded: { label: 'Superseded', variant: 'neutral' },
  deprecated: { label: 'Deprecated', variant: 'warning' },
  archived:   { label: 'Archived',   variant: 'neutral' },
  on_hold:    { label: 'On hold',    variant: 'warning' },
  closed:     { label: 'Closed',     variant: 'neutral' },
}

export function StatusBadge({ status }: { status: string }) {
  const key = status as Kind
  const entry = map[key] ?? { label: status, variant: 'neutral' as const }
  return <Badge variant={entry.variant}>{entry.label}</Badge>
}
