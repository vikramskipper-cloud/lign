import { describe, it, expect } from 'vitest'
import {
  reviewGroups,
  withCurrentAreaLabels,
  compareBriefPackages,
  earlierRevisions,
  type ReviewPackage,
} from '../reviewModel'
import { newBriefDocument, type BriefItem } from '../model'
import type { BriefRevision } from '../queries'
import type { ReferenceCard } from '@/features/planning/queries'
const item: BriefItem = {
  id: 'i',
  kind: 'mandatory',
  title: 'Durable finish',
  detail: 'Washable',
  priority: 'high',
  source: 'client',
  ownerProfileId: 'lead',
  acceptance: 'Sample review',
  resolution: '',
  appliesTo: '',
}
function pkg(): ReviewPackage {
  return {
    document: { ...newBriefDocument(), items: [structuredClone(item)] },
    files: [],
    references: [],
  }
}
const card: ReferenceCard = {
  id: 'c',
  title: 'Warm palette',
  description: 'Muted',
  url: 'https://example.test',
  boardId: 'b',
  boardTitle: 'Direction',
  areaId: null,
  areaPath: null,
  authorId: 'u',
  authorName: 'Client',
  editVersion: 1,
  selected: true,
  file: null,
  preferences: [],
  commentCount: 0,
}
describe('consolidated review grouping and historical labels', () => {
  it('puts project-wide commitments first and repeats a multi-area item without duplicating its identity', () => {
    const scoped = { ...item, id: 's', areaIds: ['a', 'b', 'a'] }
    const groups = reviewGroups(
      [scoped, item],
      [
        { id: 'a', path: 'Level / Lounge' },
        { id: 'b', path: 'Level / Kitchen' },
      ],
    )
    expect(groups.map((g) => g.label)).toEqual([
      'Project-wide',
      'Level / Kitchen',
      'Level / Lounge',
    ])
    expect(groups[1].items).toEqual([scoped])
    expect(groups[2].items).toEqual([scoped])
  })
  it('uses saved paths exclusively for a saved package', () => {
    expect(
      reviewGroups(
        [
          {
            ...item,
            areaIds: ['a'],
            areaSnapshot: [{ id: 'a', path: 'Original room' }],
          },
        ],
        [{ id: 'a', path: 'Renamed room' }],
        true,
      )[0].label,
    ).toBe('Original room')
  })
  it('does not reclassify a removed area as project-wide', () => {
    expect(
      reviewGroups([{ ...item, areaIds: ['missing'] }], [], true)[0].label,
    ).toBe('Previously assigned area')
  })
  it('uses live paths for current edits and drops stale area snapshots after reassignment', () => {
    const d = pkg().document
    d.items[0] = {
      ...item,
      areaIds: ['new'],
      areaSnapshot: [{ id: 'old', path: 'Old room' }],
    }
    const result = withCurrentAreaLabels(d, [{ id: 'new', path: 'New room' }])
    expect(result.items[0].areaSnapshot).toEqual([
      { id: 'new', path: 'New room' },
    ])
    expect(d.items[0].areaSnapshot?.[0].id).toBe('old')
  })
  it('restores whole-project scope when all area assignments are cleared', () => {
    const d = pkg().document
    d.items[0] = {
      ...item,
      areaIds: [],
      areaSnapshot: [{ id: 'old', path: 'Old room' }],
    }
    expect(withCurrentAreaLabels(d, []).items[0].areaSnapshot).toEqual([])
  })
})
describe('revision comparison', () => {
  it('is empty for identical packages and does not mutate them', () => {
    const p = pkg(),
      copy = structuredClone(p)
    expect(compareBriefPackages(p, copy)).toEqual([])
    expect(p).toEqual(copy)
  })
  it('reports added, removed and changed questions by stable identity', () => {
    const a = pkg(),
      b = pkg()
    b.document.fields[0].answer = 'New objective'
    b.document.fields.pop()
    b.document.fields.push({
      id: 'custom',
      label: 'New question',
      help: '',
      answer: 'Answer',
    })
    expect(compareBriefPackages(a, b).map((c) => c.kind)).toEqual([
      'Changed',
      'Removed',
      'Added',
    ])
  })
  it('reports requirement acceptance, responsibility and resolution changes with readable names', () => {
    const a = pkg(),
      b = pkg()
    b.document.items[0] = {
      ...item,
      ownerProfileId: 'other',
      acceptance: 'Physical test',
      resolution: 'Answered',
    }
    const diff = compareBriefPackages(a, b, [
      { id: 'lead', name: 'Lead Jane' },
      { id: 'other', name: 'Alex' },
    ])
    expect(diff).toHaveLength(1)
    expect(diff[0].before).toContain('Lead Jane')
    expect(diff[0].after).toContain('Alex')
    expect(diff[0].after).toContain('Physical test')
  })
  it('ignores item/field and area-order changes', () => {
    const a = pkg(),
      b = pkg()
    a.document.items[0].areaIds = ['a', 'b']
    b.document.items[0].areaIds = ['b', 'a']
    b.document.fields.reverse()
    expect(compareBriefPackages(a, b)).toEqual([])
  })
  it('detects selected reference edits, additions and removal', () => {
    const a = pkg(),
      b = pkg()
    a.references = [card]
    b.references = [{ ...card, title: 'Cool palette' }]
    expect(compareBriefPackages(a, b)[0].section).toBe('Selected references')
    b.references = []
    expect(compareBriefPackages(a, b)[0].kind).toBe('Removed')
    expect(compareBriefPackages(b, a)[0].kind).toBe('Added')
  })
  it('detects reference preference notes while ignoring refresh metadata', () => {
    const a = pkg(),
      b = pkg()
    a.references = [card]
    b.references = [
      { ...card, editVersion: 99, commentCount: 6, canEdit: true },
    ]
    expect(compareBriefPackages(a, b)).toEqual([])
    b.references[0].preferences = [
      {
        userId: 'u',
        name: 'Client',
        choice: 'shortlisted',
        note: 'Use for reception',
        at: 'now',
      },
    ]
    expect(compareBriefPackages(a, b)[0].after).toContain('Use for reception')
  })
  it('detects file replacement without exposing storage paths in the rendered change', () => {
    const a = pkg(),
      b = pkg()
    a.files = [
      {
        id: 'f',
        name: 'Plan.pdf',
        storage_path: 'private/old',
        size_bytes: 20,
        created_at: 'then',
      },
    ]
    b.files = [{ ...a.files[0], storage_path: 'private/new' }]
    const diff = compareBriefPackages(a, b)
    expect(diff).toHaveLength(1)
    expect(diff[0].before).not.toContain('private/')
    expect(diff[0].after).not.toContain('private/')
  })
  it('includes added and removed links and disciplines', () => {
    const a = pkg(),
      b = pkg()
    b.document.references = [
      { id: 'r', label: 'Source', url: 'https://example.test' },
    ]
    b.document.disciplines = ['interiors']
    expect(compareBriefPackages(a, b).map((c) => c.title)).toEqual([
      'Source',
      'Project disciplines',
    ])
  })
  it('offers only earlier revisions for a saved view and all saved revisions for a working draft', () => {
    const revisions = [1, 3, 2].map(
      (number) => ({ id: String(number), number }) as BriefRevision,
    )
    expect(
      earlierRevisions(revisions, revisions[1]).map((r) => r.number),
    ).toEqual([2, 1])
    expect(earlierRevisions(revisions).map((r) => r.number)).toEqual([3, 2, 1])
    expect(earlierRevisions(revisions, revisions[0])).toEqual([])
  })
})
