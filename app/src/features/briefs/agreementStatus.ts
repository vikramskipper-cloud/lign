import type { BriefRevision, ProjectBriefData } from './queries'
export type AgreementPhase =
  | 'draft'
  | 'submitted'
  | 'awaiting_agreement'
  | 'changes_requested'
  | 'agreed'
export type AgreementAction =
  | 'edit'
  | 'review'
  | 'review_revision'
  | 'copy'
  | 'feedback'
  | 'proposal'
  | 'view_agreed'
  | 'current'
  | null
export interface AgreementStatus {
  phase: AgreementPhase | 'history'
  title: string
  description: string
  revision: string
  next: string
  action: AgreementAction
  actionLabel: string
  at?: string
  atLabel?: string
  feedback?: string
  previous?: boolean
}
export function briefAgreementPhase(data: ProjectBriefData): AgreementPhase {
  const current = data.revisions.find(
    (r) => r.id === data.brief?.current_revision_id,
  )
  return data.brief?.status === 'draft' &&
    current?.decision?.decision === 'changes_requested'
    ? 'changes_requested'
    : (data.brief?.status ?? 'draft')
}
export function briefAgreementStatus(
  data: ProjectBriefData,
  history?: BriefRevision,
  canPrepareProposal = false,
): AgreementStatus {
  const current = data.revisions.find(
      (r) => r.id === data.brief?.current_revision_id,
    ),
    phase = briefAgreementPhase(data)
  if (history) {
    const previous =
      history.id !== data.brief?.current_revision_id ||
      ['draft', 'submitted'].includes(data.brief?.status ?? 'draft')
    const decision = history.decision
    return {
      phase: 'history',
      previous,
      title: previous
        ? 'Viewing a previous revision'
        : 'Viewing a saved revision',
      revision: `Saved revision ${history.number}`,
      description: decision
        ? `${decision.decision === 'agreed' ? 'Agreed' : 'Changes requested'} by ${decision.actorName}. This saved revision is read-only.`
        : 'This saved revision is read-only. Agreement actions are available only on the current brief.',
      next: 'Return to the current brief to see its status and available actions.',
      action: 'current',
      actionLabel: 'Return to current brief',
      at: decision?.created_at ?? history.created_at,
      atLabel: decision ? 'Decision recorded' : 'Requested',
    }
  }
  const approver = data.approvers.find(
    (a) =>
      a.id ===
      (current?.respondent_participant_id ??
        data.brief?.respondent_participant_id),
  )
  const name = approver?.name ?? 'the assigned approver'
  const working = current
    ? `Working draft · based on revision ${current.number}`
    : 'Working draft'
  const canEdit = data.canEdit || data.canManage
  if (phase === 'changes_requested')
    return {
      phase,
      title: `${current!.decision!.actorName} requested changes`,
      description: `Update the brief using the feedback on revision ${current!.number}. Leadership will request agreement on a new saved revision.`,
      revision: working,
      next: 'The project team updates the brief; project leadership requests agreement again.',
      action: canEdit ? 'feedback' : null,
      actionLabel: 'Review requested changes',
      feedback: current!.decision!.comment,
      at: current!.decision!.created_at,
      atLabel: 'Changes requested',
    }
  if (phase === 'draft')
    return {
      phase,
      title: 'Your team is preparing the brief',
      description:
        current?.decision?.decision === 'agreed'
          ? `You are updating agreed revision ${current.number}. The earlier agreement still applies to that saved revision.`
          : 'Capture the needs, clarify requirements and choose references before requesting client agreement.',
      revision: working,
      next: 'The project team prepares the brief, then project leadership reviews it.',
      action: canEdit ? (data.canManage ? 'review' : 'edit') : null,
      actionLabel: data.canManage ? 'Review brief' : 'Continue editing',
      at: data.brief?.updated_at,
      atLabel: 'Updated',
    }
  if (phase === 'submitted')
    return {
      phase,
      title: 'Waiting for project leadership to review',
      description:
        'The team has submitted the brief. Project leadership reviews it before requesting client agreement.',
      revision: working,
      next: 'Project leadership reviews the brief and requests client agreement.',
      action: data.canManage ? 'review' : null,
      actionLabel: 'Review brief',
      at: data.brief?.updated_at,
      atLabel: 'Submitted',
    }
  if (phase === 'awaiting_agreement')
    return {
      phase,
      title: data.canRespond
        ? 'Your agreement is needed'
        : `Waiting for ${name} to review${current ? ` revision ${current.number}` : ''}`,
      description: current
        ? `Agreement applies to saved revision ${current.number}, including its requirements, selected references and attachments.`
        : 'The agreement request has no available saved revision. Refresh the brief before responding.',
      revision: current
        ? `Saved revision ${current.number} · awaiting agreement`
        : 'Agreement request',
      next: `${name} reviews the requested revision and agrees or requests changes.`,
      action: current
        ? data.canRespond
          ? 'review_revision'
          : data.canManage
            ? 'copy'
            : null
        : null,
      actionLabel: data.canRespond
        ? 'Review this revision'
        : 'Copy agreement link',
      at: current?.created_at,
      atLabel: 'Agreement requested',
    }
  return {
    phase: 'agreed',
    title: current ? `Revision ${current.number} was agreed` : 'Brief agreed',
    description:
      current?.decision?.decision === 'agreed'
        ? `Agreed by ${current.decision.actorName}. This saved revision is the project baseline; later changes need a new revision and agreement.`
        : 'The agreed brief is the baseline for preparing the design proposal.',
    revision: current
      ? `Saved revision ${current.number} · agreed`
      : 'Agreed brief',
    next: canPrepareProposal
      ? 'The project team prepares the design proposal. Detailed design follows proposal acceptance.'
      : 'The project team prepares the design proposal. You can view the agreed brief.',
    action: canPrepareProposal ? 'proposal' : current ? 'view_agreed' : null,
    actionLabel: canPrepareProposal
      ? 'Continue to Design proposal'
      : 'View agreed brief',
    at: current?.decision?.created_at,
    atLabel: 'Agreed',
  }
}
