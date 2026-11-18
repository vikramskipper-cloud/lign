import { describe, it, expect } from 'vitest'
import { briefReadiness, type ReadinessInput } from '../readiness'
import type { BriefDocument } from '../model'
const document: BriefDocument = {
  disciplines: [],
  fields: [
    {
      id: 'objective',
      label: 'Objective',
      help: '',
      answer: 'A useful design',
    },
    { id: 'deliverables', label: 'Deliverables', help: '', answer: 'Drawings' },
  ],
  items: [
    {
      id: 'need',
      title: 'Durable finish',
      detail: 'Useful context',
      kind: 'mandatory',
      priority: 'high',
      source: 'client',
      ownerProfileId: '',
      acceptance: 'Check material samples',
      resolution: '',
      appliesTo: 'Whole project',
    },
  ],
  references: [],
}
function fixture(): ReadinessInput {
  return structuredClone({
    document,
    respondent: 'client',
    loadedVersion: 1,
    dirty: false,
    stale: false,
    areaDirty: false,
    uploading: false,
    data: {
      brief: {
        id: 'b',
        project_id: 'p',
        status: 'draft',
        document,
        edit_version: 1,
        revision_number: 0,
        current_revision_id: null,
        respondent_participant_id: 'client',
      },
      canManage: true,
      canEdit: true,
      canRespond: false,
      canComment: true,
      canGenerate: true,
      approvers: [{ id: 'client', name: 'Priya', pending: false }],
      owners: [{ id: 'wrong-first', name: 'Alphabetically first' }],
      files: [],
      revisions: [],
      notes: [],
    },
    metadata: {
      version: 1,
      respondentId: 'client',
      people: [{ id: 'lead', name: 'Jane', role: 'lead' }],
      defaultOwner: { id: 'lead', name: 'Jane', role: 'lead' },
      approver: {
        id: 'client',
        name: 'Priya',
        pending: false,
        available: true,
        isRequester: false,
      },
      selectedReferenceCount: 0,
      referenceError: null,
      canRequest: true,
      canSubmit: true,
    },
  } as ReadinessInput)
}
describe('brief readiness matches the review/agreement boundary', () => {
  it('blocks agreement but permits team review when selected reference preview fails', () => {
    const f = fixture()
    f.previewError = true
    const r = briefReadiness(f)
    expect(r.teamReady).toBe(true)
    expect(r.clientReady).toBe(false)
    expect(
      r.checks.find((c) => c.id === 'reference-preview')?.actions?.[0].target
        .kind,
    ).toBe('retryReferences')
  })
  it('keeps agreement pending while the selected reference preview refreshes', () => {
    const f = fixture()
    f.previewLoading = true
    const r = briefReadiness(f)
    expect(r.teamReady).toBe(true)
    expect(r.clientReady).toBe(false)
    expect(r.pending).toBe(true)
  })
  it('does not use a cached pass while the latest metadata is being refreshed', () => {
    const f = fixture()
    f.checking = true
    const r = briefReadiness(f)
    expect(r.clientReady).toBe(false)
    expect(r.pending).toBe(true)
    expect(r.teamReady).toBe(true)
  })
  it('allows client agreement with optional scope/material absent and the exact server fallback', () => {
    const f = fixture(),
      r = briefReadiness(f)
    expect(r.clientReady).toBe(true)
    expect(r.teamReady).toBe(true)
    expect(r.automatic?.person.id).toBe('lead')
    expect(r.automatic?.person.id).not.toBe(f.data.owners[0].id)
    expect(
      r.checks.filter((c) => c.state === 'suggestion').map((c) => c.id),
    ).toEqual(['scope', 'material'])
  })
  it('lets unresolved questions and incomplete acceptance checks go to team review', () => {
    const f = fixture()
    f.document.items[0].acceptance = ''
    f.document.items.push({
      ...f.document.items[0],
      id: 'q',
      kind: 'question',
      title: 'What size?',
      resolution: '',
    })
    const r = briefReadiness(f)
    expect(r.teamReady).toBe(true)
    expect(r.clientReady).toBe(false)
    expect(r.blocking.map((c) => c.id)).toEqual(['acceptance', 'questions'])
  })
  it('lets leadership review overall needs before requirements have been defined', () => {
    const f = fixture()
    f.document.items = []
    const r = briefReadiness(f)
    expect(r.teamReady).toBe(true)
    expect(r.clientReady).toBe(false)
    expect(r.blocking.map((c) => c.id)).toEqual(['commitments'])
  })
  it('blocks both stages on unsaved changes, uploads, area edits or a newer version', () => {
    for (const flag of ['dirty', 'uploading', 'areaDirty', 'stale'] as const) {
      const f = fixture()
      f[flag] = true
      expect(briefReadiness(f).teamReady).toBe(false)
      expect(briefReadiness(f).clientReady).toBe(false)
    }
  })
  it('detects a server version newer than the locally loaded brief', () => {
    const f = fixture()
    f.metadata!.version = 2
    const r = briefReadiness(f)
    expect(r.teamReady).toBe(false)
    expect(r.clientReady).toBe(false)
    expect(
      r.checks.find((c) => c.id === 'version')?.actions?.[0].target.kind,
    ).toBe('reload')
  })
  it('does not declare client readiness while context is unknown or failed', () => {
    const f = fixture()
    f.metadata = undefined
    expect(briefReadiness(f).pending).toBe(true)
    expect(briefReadiness(f).clientReady).toBe(false)
    f.metadataError = true
    const r = briefReadiness(f)
    expect(r.clientReady).toBe(false)
    expect(r.teamReady).toBe(true)
    expect(
      r.blocking.find((c) => c.id === 'context')?.actions?.[0].target.kind,
    ).toBe('retry')
  })
  it('blocks a leadership requester assigned as their own approver', () => {
    const f = fixture()
    f.metadata!.approver!.isRequester = true
    expect(briefReadiness(f).clientReady).toBe(false)
    f.data.canManage = false
    f.metadata!.canRequest = false
    expect(briefReadiness(f).clientReady).toBe(true)
  })
  it('requires the selected recipient to match current checked metadata', () => {
    const f = fixture()
    f.respondent = 'different'
    const r = briefReadiness(f)
    expect(r.clientReady).toBe(false)
    expect(r.pending).toBe(true)
  })
  it('does not treat a pending or missing approver as ready', () => {
    const f = fixture()
    f.metadata!.approver!.pending = true
    f.metadata!.approver!.available = false
    expect(briefReadiness(f).clientReady).toBe(false)
    f.metadata!.approver = null
    expect(briefReadiness(f).clientReady).toBe(false)
  })
  it('requires unavailable explicit assignments to be corrected, rather than silently falling back', () => {
    const f = fixture()
    f.document.items[0].ownerProfileId = 'removed'
    const r = briefReadiness(f)
    expect(r.clientReady).toBe(false)
    expect(
      r.checks.find((c) => c.id === 'responsibility')?.actions?.[0].target,
    ).toEqual({ kind: 'item', id: 'need', field: 'owner' })
    expect(r.automatic?.items.length).toBe(0)
  })
  it('blocks empty automatic assignments when no active lead/contributor exists', () => {
    const f = fixture()
    f.metadata!.defaultOwner = null
    f.metadata!.people = []
    expect(briefReadiness(f).clientReady).toBe(false)
  })
  it('counts item-level issues and preserves stable target IDs', () => {
    const f = fixture()
    f.document.items[0].acceptance = ''
    f.document.items.push({
      ...f.document.items[0],
      id: 'second',
      title: 'Another finish',
    })
    const r = briefReadiness(f),
      c = r.checks.find((c) => c.id === 'acceptance')
    expect(c?.title).toContain('2')
    expect(c?.actions?.map((a) => a.target)).toEqual([
      { kind: 'item', id: 'need', field: 'acceptance' },
      { kind: 'item', id: 'second', field: 'acceptance' },
    ])
  })
  it('keeps reference package size limits blocking while reference absence remains optional', () => {
    const f = fixture()
    f.metadata!.referenceError = 'Select at most 100 references'
    const r = briefReadiness(f)
    expect(r.clientReady).toBe(false)
    expect(r.teamReady).toBe(true)
    expect(r.blocking.map((c) => c.id)).toEqual(['reference-package'])
  })
  it('checks the saved-draft boundary for incomplete item titles and URLs', () => {
    const f = fixture()
    f.document.items[0].title = ' '
    f.document.references = [
      { id: 'link', label: '', url: 'javascript:alert(1)' },
    ]
    const r = briefReadiness(f)
    expect(r.teamReady).toBe(false)
    expect(r.blocking.map((c) => c.id)).toContain('titles')
    expect(r.blocking.map((c) => c.id)).toContain('links')
  })
  it('does not report readiness using a leadership permission that has been revoked', () => {
    const f = fixture()
    f.metadata!.canRequest = false
    f.metadata!.canSubmit = false
    const r = briefReadiness(f)
    expect(r.clientReady).toBe(false)
    expect(r.teamReady).toBe(false)
    expect(r.blocking.map((c) => c.id)).toContain('access')
  })
})
