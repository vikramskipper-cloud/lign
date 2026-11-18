import type { BriefDocument, BriefItem } from './model'
import type { BriefFile, BriefRevision } from './queries'
import type { ReferenceCard } from '@/features/planning/queries'
export interface ReviewArea {
  id: string
  path: string
}
export function reviewGroups(
  items: BriefItem[],
  areas: ReviewArea[] = [],
  frozen = false,
) {
  const groups = new Map<
    string,
    { id: string; label: string; items: BriefItem[] }
  >()
  for (const item of items) {
    const ids = [
      ...new Set(item.areaIds ?? item.areaSnapshot?.map((a) => a.id) ?? []),
    ]
    const scopes = ids.length
      ? ids.map((id) => ({
          id,
          label:
            (frozen
              ? item.areaSnapshot?.find((a) => a.id === id)?.path
              : (areas.find((a) => a.id === id)?.path ??
                item.areaSnapshot?.find((a) => a.id === id)?.path)) ??
            'Previously assigned area',
        }))
      : [{ id: 'project', label: 'Project-wide' }]
    for (const scope of scopes) {
      if (!groups.has(scope.id))
        groups.set(scope.id, { id: scope.id, label: scope.label, items: [] })
      groups.get(scope.id)!.items.push(item)
    }
  }
  return [...groups.values()].sort((a, b) =>
    a.id === 'project'
      ? -1
      : b.id === 'project'
        ? 1
        : a.label.localeCompare(b.label),
  )
}
export function withCurrentAreaLabels(
  document: BriefDocument,
  areas: ReviewArea[],
): BriefDocument {
  return {
    ...document,
    items: document.items.map((item) => ({
      ...item,
      areaSnapshot: [
        ...new Set(item.areaIds ?? item.areaSnapshot?.map((a) => a.id) ?? []),
      ].map((id) => ({
        id,
        path:
          areas.find((a) => a.id === id)?.path ??
          item.areaSnapshot?.find((a) => a.id === id)?.path ??
          'Previously assigned area',
      })),
    })),
  }
}
export interface ReviewPackage {
  document: BriefDocument
  files: BriefFile[]
  references: ReferenceCard[]
}
export interface BriefChange {
  section: string
  kind: 'Added' | 'Removed' | 'Changed'
  title: string
  before: string
  after: string
}
const itemText = (i: BriefItem, owners: { id: string; name: string }[]) =>
  [
    `Type: ${i.kind === 'mandatory' ? 'Requirement' : i.kind}`,
    `Title: ${i.title}`,
    i.detail && `Details: ${i.detail}`,
    `Priority: ${i.priority}`,
    `Source: ${i.source}`,
    `Responsibility: ${i.ownerProfileId ? (owners.find((o) => o.id === i.ownerProfileId)?.name ?? 'Recorded team member (not in current directory)') : 'Automatic project assignment'}`,
    `Scope: ${[...(i.areaSnapshot?.map((a) => a.path) ?? i.areaIds ?? [])].sort().join(', ') || 'Project-wide'}`,
    i.appliesTo && `Applies to: ${i.appliesTo}`,
    i.acceptance && `Acceptance check: ${i.acceptance}`,
    i.resolution && `Answer: ${i.resolution}`,
  ]
    .filter(Boolean)
    .join('\n')
const referenceText = (c: ReferenceCard) =>
  [
    c.title,
    c.description,
    c.url,
    `Suggested by: ${c.authorName}`,
    `Board: ${c.boardTitle}`,
    `Area: ${c.areaPath ?? 'Project-wide'}`,
    c.file && `File: ${c.file.name} (${c.file.size} bytes)`,
    ...[...c.preferences]
      .sort((a, b) => a.userId.localeCompare(b.userId))
      .map((p) => `${p.name}: ${p.choice}${p.note ? ' — ' + p.note : ''}`),
  ]
    .filter(Boolean)
    .join('\n')
export function compareBriefPackages(
  before: ReviewPackage,
  after: ReviewPackage,
  owners: { id: string; name: string }[] = [],
): BriefChange[] {
  const changes: BriefChange[] = []
  function compare<T>(
    section: string,
    old: T[],
    next: T[],
    id: (x: T) => string,
    title: (x: T) => string,
    text: (x: T) => string,
    signature: (x: T) => string = text,
  ) {
    const oldMap = new Map(old.map((x) => [id(x), x])),
      nextMap = new Map(next.map((x) => [id(x), x]))
    for (const key of new Set([...oldMap.keys(), ...nextMap.keys()])) {
      const a = oldMap.get(key),
        b = nextMap.get(key),
        aText = a === undefined ? '' : text(a),
        bText = b === undefined ? '' : text(b)
      if (a === undefined || b === undefined || signature(a) !== signature(b))
        changes.push({
          section,
          kind:
            a === undefined ? 'Added' : b === undefined ? 'Removed' : 'Changed',
          title: title((b ?? a)!),
          before: aText,
          after: bText,
        })
    }
  }
  compare(
    'Overall brief',
    before.document.fields,
    after.document.fields,
    (x) => x.id,
    (x) => x.label,
    (x) => [x.label, x.help, x.answer].filter(Boolean).join('\n'),
  )
  compare(
    'Requirements, preferences and questions',
    before.document.items,
    after.document.items,
    (x) => x.id,
    (x) => x.title || 'Untitled item',
    (x) => itemText(x, owners),
    (x) =>
      itemText(x, owners) +
      '\n' +
      x.ownerProfileId +
      '\n' +
      [...(x.areaIds ?? [])].sort().join(','),
  )
  compare(
    'Brief links',
    before.document.references,
    after.document.references,
    (x) => x.id,
    (x) => x.label,
    (x) => `${x.label}\n${x.url}`,
  )
  compare(
    'Selected references',
    before.references,
    after.references,
    (x) => x.id,
    (x) => x.title,
    referenceText,
    (x) => referenceText(x) + '\n' + (x.file?.path ?? ''),
  )
  compare(
    'Attached files',
    before.files,
    after.files,
    (x) => x.id,
    (x) => x.name,
    (x) => `${x.name}\n${x.size_bytes} bytes`,
    (x) => `${x.name}\n${x.size_bytes}\n${x.storage_path}`,
  )
  const old = [...before.document.disciplines].sort().join(', '),
    next = [...after.document.disciplines].sort().join(', ')
  if (old !== next)
    changes.push({
      section: 'Overall brief',
      kind: 'Changed',
      title: 'Project disciplines',
      before: old,
      after: next,
    })
  return changes
}
export function earlierRevisions(
  revisions: BriefRevision[],
  shown?: BriefRevision,
) {
  return revisions
    .filter((r) => !shown || r.number < shown.number)
    .sort((a, b) => b.number - a.number)
}
