import type { BriefDocument } from './model'
import type { ProjectBriefData, BriefReadinessContext } from './queries'
export type ReadinessTarget =
  | { kind: 'field'; id: string }
  | {
      kind: 'item'
      id: string
      field: 'title' | 'acceptance' | 'resolution' | 'owner' | 'detail'
    }
  | { kind: 'reference'; id: string; field: 'label' | 'url' }
  | { kind: 'approver' }
  | { kind: 'save' }
  | { kind: 'reload' }
  | { kind: 'retry' }
  | { kind: 'retryReferences' }
  | { kind: 'boards' }
  | { kind: 'people' }
  | { kind: 'requirements' }
export interface ReadinessAction {
  label: string
  target: ReadinessTarget
  permission: 'edit' | 'manage' | 'view'
}
export interface ReadinessCheck {
  id: string
  title: string
  detail: string
  state: 'pass' | 'block' | 'pending' | 'suggestion'
  blocksTeam?: boolean
  responsible: string
  actions?: ReadinessAction[]
}
export interface ReadinessInput {
  data: ProjectBriefData
  document: BriefDocument
  respondent: string
  metadata?: BriefReadinessContext
  metadataError?: boolean
  checking?: boolean
  previewLoading?: boolean
  previewError?: boolean
  dirty: boolean
  stale: boolean
  areaDirty: boolean
  uploading: boolean
  loadedVersion: number
}
export function briefReadiness({
  data,
  document,
  respondent,
  metadata,
  metadataError = false,
  checking = false,
  previewLoading = false,
  previewError = false,
  dirty,
  stale,
  areaDirty,
  uploading,
  loadedVersion,
}: ReadinessInput) {
  const checks: ReadinessCheck[] = [],
    commitments = document.items.filter((i) =>
      ['mandatory', 'preference'].includes(i.kind),
    )
  const field = (id: string) => document.fields.find((f) => f.id === id),
    itemActions = (
      items: typeof document.items,
      key: 'title' | 'acceptance' | 'resolution' | 'owner' | 'detail',
      verb: string,
    ): ReadinessAction[] =>
      items.map((i) => ({
        label: `${verb}: ${i.title.trim() || 'Untitled item'} (item ${document.items.indexOf(i) + 1})`,
        target: { kind: 'item', id: i.id, field: key },
        permission: 'edit',
      }))
  const known = Boolean(metadata),
    mismatch = Boolean(
      metadata &&
        metadata.version !== data.brief?.edit_version &&
        !(metadata.version === 0 && !data.brief),
    ),
    targetMatches = Boolean(metadata && metadata.respondentId === respondent)
  const fresh = known && !metadataError && !mismatch
  if (stale || mismatch || loadedVersion !== (data.brief?.edit_version ?? 0))
    checks.push({
      id: 'version',
      title: 'A newer saved brief is available',
      detail:
        'Load the latest version before sending this brief for review or agreement.',
      state: 'block',
      blocksTeam: true,
      responsible: 'Current editor',
      actions: [
        {
          label: 'Load latest brief',
          target: { kind: 'reload' },
          permission: 'view',
        },
      ],
    })
  else
    checks.push({
      id: 'version',
      title: 'You are working with the latest loaded version',
      detail:
        'The server checks the version again when the brief is submitted.',
      state: 'pass',
      responsible: 'Project leadership',
    })
  if (uploading)
    checks.push({
      id: 'uploads',
      title: 'A reference file is still uploading',
      detail: 'Wait for this upload to finish before continuing.',
      state: 'block',
      blocksTeam: true,
      responsible: 'Current uploader',
    })
  if (areaDirty)
    checks.push({
      id: 'areas',
      title: 'Project area changes are not saved',
      detail: 'Save or cancel the area you are editing before continuing.',
      state: 'block',
      blocksTeam: true,
      responsible: 'Current editor',
    })
  checks.push({
    id: 'saved',
    title: !data.brief
      ? 'Save the first draft'
      : dirty
        ? 'Save your latest changes'
        : 'Current edits saved',
    detail:
      dirty || !data.brief
        ? 'Only saved content can be sent for team review or client agreement.'
        : 'The document edits in this view are saved.',
    state: dirty || !data.brief ? 'block' : 'pass',
    blocksTeam: true,
    responsible: 'Current editor',
    actions:
      dirty || !data.brief
        ? [
            {
              label: dirty ? 'Save latest changes' : 'Save first draft',
              target: { kind: 'save' },
              permission: 'edit',
            },
          ]
        : undefined,
  })
  for (const [id, label] of [
    ['objective', 'project objective'],
    ['deliverables', 'expected deliverables'],
  ]) {
    const missing = !field(id)?.answer.trim()
    checks.push({
      id,
      title: missing
        ? `Record the ${label}`
        : `${label[0].toUpperCase() + label.slice(1)} recorded`,
      detail: missing
        ? 'Required before team review and client agreement.'
        : 'The overall needs are recorded.',
      state: missing ? 'block' : 'pass',
      blocksTeam: true,
      responsible: 'Project team',
      actions: missing
        ? [
            {
              label: `Complete ${label}`,
              target: { kind: 'field', id },
              permission: 'edit',
            },
          ]
        : undefined,
    })
  }
  const untitled = document.items.filter((i) => !i.title.trim())
  if (untitled.length)
    checks.push({
      id: 'titles',
      title: `${untitled.length} items need a title`,
      detail: 'Name each item so the draft can be saved.',
      state: 'block',
      blocksTeam: true,
      responsible: 'Project team',
      actions: itemActions(untitled, 'title', 'Add title'),
    })
  const invalidLinks = document.references.filter(
    (r) =>
      !r.label.trim() ||
      !/^https?:\/\/[^\s]+$/.test(r.url) ||
      r.url.length > 2000,
  )
  if (invalidLinks.length)
    checks.push({
      id: 'links',
      title: `${invalidLinks.length} brief links need correction`,
      detail:
        'Each direct brief link needs a label and an HTTP or HTTPS address before saving.',
      state: 'block',
      blocksTeam: true,
      responsible: 'Project team',
      actions: invalidLinks.map((r) => ({
        label: `Fix ${r.label.trim() || 'reference link'}`,
        target: {
          kind: 'reference',
          id: r.id,
          field: r.label.trim() ? 'url' : 'label',
        },
        permission: 'edit',
      })),
    })
  checks.push({
    id: 'commitments',
    title: commitments.length
      ? 'Requirements or preferences recorded'
      : 'Add at least one requirement or preference',
    detail: commitments.length
      ? `${commitments.length} commitments are included.`
      : 'You can still submit the overall needs for team review while these are being defined.',
    state: commitments.length ? 'pass' : 'block',
    responsible: 'Project team',
    actions: !commitments.length
      ? [
          {
            label: 'Add requirements',
            target: { kind: 'requirements' },
            permission: 'edit',
          },
        ]
      : undefined,
  })
  if (commitments.length) {
    const missing = commitments.filter((i) => !i.acceptance?.trim())
    checks.push({
      id: 'acceptance',
      title: missing.length
        ? `${missing.length} ${missing.length === 1 ? 'requirement or preference needs an acceptance check' : 'requirements or preferences need acceptance checks'}`
        : 'Acceptance checks recorded',
      detail: missing.length
        ? 'Describe how each commitment will be checked before client agreement.'
        : 'Each commitment has a recorded check.',
      state: missing.length ? 'block' : 'pass',
      responsible: 'Project team',
      actions: itemActions(missing, 'acceptance', 'Add check'),
    })
  }
  const open = document.items.filter(
    (i) => i.kind === 'question' && !i.resolution?.trim(),
  )
  checks.push({
    id: 'questions',
    title: open.length
      ? `${open.length} ${open.length === 1 ? 'question needs an answer' : 'questions need answers'}`
      : 'No unresolved questions',
    detail: open.length
      ? 'Record answers before requesting client agreement. Open questions can still go to team review.'
      : 'Questions are resolved or none have been recorded.',
    state: open.length ? 'block' : 'pass',
    responsible: 'Project team',
    actions: itemActions(open, 'resolution', 'Resolve'),
  })
  if (!fresh || checking || (!targetMatches && respondent)) {
    checks.push({
      id: 'context',
      title: metadataError
        ? 'Could not verify agreement details'
        : mismatch
          ? 'Refresh the agreement checks'
          : 'Checking current assignments and agreement details',
      detail:
        'Client agreement requires current approver, responsibility and reference-package checks.',
      state: metadataError ? 'block' : 'pending',
      responsible: 'Project leadership',
      actions: metadataError
        ? [
            {
              label: 'Retry checks',
              target: { kind: 'retry' },
              permission: 'view',
            },
          ]
        : undefined,
    })
  }
  if (previewLoading || previewError)
    checks.push({
      id: 'reference-preview',
      title: previewError
        ? 'Selected reference preview unavailable'
        : 'Loading selected references for review',
      detail:
        'Load the selected reference package before leadership requests client agreement.',
      state: previewError ? 'block' : 'pending',
      responsible: 'Project leadership',
      actions: previewError
        ? [
            {
              label: 'Retry reference preview',
              target: { kind: 'retryReferences' },
              permission: 'view',
            },
          ]
        : undefined,
    })
  if (fresh) {
    const lostSubmit =
      data.brief?.status === 'draft' &&
      (data.canEdit || data.canManage) &&
      !metadata!.canSubmit
    if (lostSubmit || (data.canManage && !metadata!.canRequest))
      checks.push({
        id: 'access',
        title: 'Project access has changed',
        detail:
          'Refresh the brief to load your current editing and leadership permissions.',
        state: 'block',
        blocksTeam: lostSubmit,
        responsible: 'Current viewer',
        actions: [
          {
            label: 'Refresh project access',
            target: { kind: 'reload' },
            permission: 'view',
          },
        ],
      })
    if (commitments.length) {
      const invalid = commitments.filter((i) =>
        i.ownerProfileId
          ? !metadata!.people.some((p) => p.id === i.ownerProfileId)
          : !metadata!.defaultOwner,
      )
      checks.push({
        id: 'responsibility',
        title: invalid.length
          ? `${invalid.length} commitments need valid responsibility`
          : 'Responsibility covered',
        detail: invalid.length
          ? 'Choose an active project lead or contributor.'
          : 'Explicit assignments and the automatic fallback match the current project team.',
        state: invalid.length ? 'block' : 'pass',
        responsible: 'Project team',
        actions: itemActions(invalid, 'owner', 'Assign responsibility'),
      })
    }
    const a = metadata!.approver,
      matched = targetMatches && a?.id === respondent
    const ready = Boolean(
      respondent &&
        matched &&
        a?.available &&
        !a.pending &&
        !(data.canManage && a.isRequester),
    )
    checks.push({
      id: 'approver',
      title: !respondent
        ? 'Assign a client approver'
        : !matched
          ? 'The assigned approver is unavailable'
          : a!.pending
            ? `${a!.name} has an invitation pending`
            : !a!.available
              ? 'The assigned approver cannot respond yet'
              : data.canManage && a!.isRequester
                ? 'Choose a different client approver'
                : `${a!.name} is ready to receive the request`,
      detail: !respondent
        ? 'Project leadership chooses a project approver.'
        : !matched
          ? 'Project leadership should check the participant’s access.'
          : a!.pending
            ? 'The invitation must be accepted before leadership can request agreement.'
            : !a!.available
              ? 'Project leadership should check the participant’s access.'
              : data.canManage && a!.isRequester
                ? 'You cannot agree the brief you review. Choose another active approver.'
                : 'Leadership requests agreement; the assigned approver records their own decision.',
      state: ready ? 'pass' : 'block',
      responsible: a?.pending
        ? 'Client accepts invitation; leadership manages access'
        : 'Project leadership',
      actions: ready
        ? undefined
        : [
            {
              label: 'Review approver assignment',
              target: { kind: 'approver' },
              permission: 'manage',
            },
            ...(respondent && (!matched || a?.pending || !a?.available)
              ? [
                  {
                    label: 'Check project access',
                    target: { kind: 'people' as const },
                    permission: 'manage' as const,
                  },
                ]
              : []),
          ],
    })
    checks.push({
      id: 'reference-package',
      title: metadata!.referenceError
        ? 'Selected references need review'
        : 'Selected references fit the agreement package',
      detail:
        metadata!.referenceError ??
        `${metadata!.selectedReferenceCount} shared references selected. References are optional.`,
      state: metadata!.referenceError ? 'block' : 'pass',
      responsible: 'Project leadership',
      actions: metadata!.referenceError
        ? [
            {
              label: 'Review selected references',
              target: { kind: 'boards' },
              permission: 'view',
            },
          ]
        : undefined,
    })
  }
  if (!field('scope')?.answer.trim())
    checks.push({
      id: 'scope',
      title: 'Consider defining scope boundaries',
      detail:
        'Describe what is included and excluded if it will help this project.',
      state: 'suggestion',
      responsible: 'Project team',
      actions: [
        {
          label: 'Add scope boundaries',
          target: { kind: 'field', id: 'scope' },
          permission: 'edit',
        },
      ],
    })
  if (
    fresh &&
    metadata!.selectedReferenceCount === 0 &&
    !document.references.length &&
    !data.files.length
  )
    checks.push({
      id: 'material',
      title: 'Consider supporting references',
      detail:
        'Add useful reference boards, links or files if the project needs them. None are required for agreement.',
      state: 'suggestion',
      responsible: 'Project team',
      actions: [
        {
          label: 'Review reference boards',
          target: { kind: 'boards' },
          permission: 'view',
        },
      ],
    })
  const sparse = commitments.filter((i) => !i.detail?.trim())
  if (sparse.length)
    checks.push({
      id: 'context-detail',
      title: `Consider adding context to ${sparse.length} commitments`,
      detail:
        'Extra detail can help the client and team interpret the requirement consistently.',
      state: 'suggestion',
      responsible: 'Project team',
      actions: itemActions(sparse, 'detail', 'Add context'),
    })
  const blocking = checks.filter((c) => c.state === 'block'),
    pending = checks.some((c) => c.state === 'pending'),
    automatic =
      fresh && metadata!.defaultOwner
        ? {
            person: metadata!.defaultOwner,
            items: commitments.filter((i) => !i.ownerProfileId),
          }
        : null
  return {
    checks,
    teamReady: !checks.some((c) => c.blocksTeam && c.state === 'block'),
    clientReady: !blocking.length && !pending && fresh,
    blocking,
    pending,
    automatic,
  }
}
