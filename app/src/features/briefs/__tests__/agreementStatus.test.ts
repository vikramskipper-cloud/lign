import { describe, it, expect } from 'vitest'
import { briefAgreementPhase, briefAgreementStatus } from '../agreementStatus'
import type { ProjectBriefData, BriefRevision } from '../queries'
import type { BriefDocument } from '../model'
const document: BriefDocument = {
  disciplines: [],
  fields: [],
  items: [],
  references: [],
}
const revision = (id = 'r1', number = 1): BriefRevision => ({
  id,
  number,
  document,
  attachments: [],
  created_at: '2026-11-17T10:00:00Z',
  requested_by: 'lead',
  respondent_participant_id: 'alice',
  decision: null,
  generatedCount: 0,
})
function fixture(
  status: NonNullable<ProjectBriefData['brief']>['status'] = 'draft',
): ProjectBriefData {
  return {
    brief: {
      id: 'b',
      project_id: 'p',
      status,
      document,
      edit_version: 1,
      revision_number: 1,
      current_revision_id: 'r1',
      respondent_participant_id: 'alice',
      updated_at: '2026-11-17T10:01:00Z',
    },
    canManage: true,
    canEdit: status === 'draft',
    canRespond: false,
    canComment: true,
    canGenerate: true,
    approvers: [
      { id: 'alice', name: 'Alice', pending: false },
      { id: 'bob', name: 'Bob', pending: false },
    ],
    owners: [],
    files: [],
    revisions: [revision()],
    notes: [],
  }
}
describe('brief status and role-specific next action', () => {
  it('keeps working drafts distinct from saved request revisions', () => {
    const d = fixture()
    expect(briefAgreementStatus(d).revision).toBe(
      'Working draft · based on revision 1',
    )
    expect(briefAgreementStatus(d).action).toBe('review')
    d.canManage = false
    expect(briefAgreementStatus(d).action).toBe('edit')
    d.canEdit = false
    expect(briefAgreementStatus(d).action).toBeNull()
  })
  it('leaves submitted team review with leadership', () => {
    const d = fixture('submitted')
    expect(briefAgreementStatus(d).action).toBe('review')
    d.canManage = false
    expect(briefAgreementStatus(d).action).toBeNull()
  })
  it('uses the frozen request recipient instead of a different working assignment', () => {
    const d = fixture('awaiting_agreement')
    d.brief!.respondent_participant_id = 'bob'
    expect(briefAgreementStatus(d).title).toContain('Alice')
    expect(briefAgreementStatus(d).title).not.toContain('Bob')
    expect(briefAgreementStatus(d).action).toBe('copy')
  })
  it('prioritises the assigned responder even when that person also manages the project', () => {
    const d = fixture('awaiting_agreement')
    d.canRespond = true
    expect(briefAgreementStatus(d).action).toBe('review_revision')
    expect(briefAgreementStatus(d).title).toBe('Your agreement is needed')
  })
  it('offers no response action without the requested saved revision', () => {
    const d = fixture('awaiting_agreement')
    d.canRespond = true
    d.revisions = []
    expect(briefAgreementStatus(d).action).toBeNull()
    expect(briefAgreementStatus(d).revision).not.toContain('undefined')
  })
  it('does not give another viewer the assigned client action', () => {
    const d = fixture('awaiting_agreement')
    d.canManage = false
    expect(briefAgreementStatus(d).action).toBeNull()
  })
  it('derives changes requested only from the current request and draft status', () => {
    const d = fixture()
    d.revisions[0].decision = {
      decision: 'changes_requested',
      actorName: 'Alice',
      comment: 'Revise the dimensions',
      created_at: '2026-11-17T11:00:00Z',
    }
    expect(briefAgreementPhase(d)).toBe('changes_requested')
    expect(briefAgreementStatus(d).feedback).toBe('Revise the dimensions')
    d.brief!.status = 'submitted'
    expect(briefAgreementPhase(d)).toBe('submitted')
    d.brief!.status = 'draft'
    d.brief!.current_revision_id = 'r2'
    d.revisions.push(revision('r2', 2))
    expect(briefAgreementPhase(d)).toBe('draft')
  })
  it('historical views cannot inherit live response or proposal actions', () => {
    const d = fixture('awaiting_agreement')
    d.canRespond = true
    const h = revision('older', 0)
    const s = briefAgreementStatus(d, h, true)
    expect(s.action).toBe('current')
    expect(s.previous).toBe(true)
    expect(s.title).toBe('Viewing a previous revision')
  })
  it('labels an explicitly opened current saved revision without calling it previous', () => {
    const d = fixture('awaiting_agreement')
    const s = briefAgreementStatus(d, d.revisions[0])
    expect(s.action).toBe('current')
    expect(s.title).toBe('Viewing a saved revision')
  })
  it('recognises an agreed baseline as previous once a new draft starts', () => {
    const d = fixture()
    d.revisions[0].decision = {
      decision: 'agreed',
      actorName: 'Alice',
      comment: '',
      created_at: '2026-11-17T11:00:00Z',
    }
    expect(briefAgreementStatus(d).phase).toBe('draft')
    expect(briefAgreementStatus(d).description).toContain('earlier agreement')
    expect(briefAgreementStatus(d, d.revisions[0]).previous).toBe(true)
  })
  it('requires explicit proposal access rather than inferring it from brief management', () => {
    const d = fixture('agreed')
    expect(briefAgreementStatus(d).action).toBe('view_agreed')
    expect(briefAgreementStatus(d, undefined, true).action).toBe('proposal')
    d.canManage = false
    expect(briefAgreementStatus(d).action).toBe('view_agreed')
  })
  it('dates agreement using the decision record rather than the working brief timestamp', () => {
    const d = fixture('agreed')
    d.revisions[0].decision = {
      decision: 'agreed',
      actorName: 'Alice',
      comment: '',
      created_at: '2026-11-17T11:00:00Z',
    }
    expect(briefAgreementStatus(d).at).toBe('2026-11-17T11:00:00Z')
  })
})
