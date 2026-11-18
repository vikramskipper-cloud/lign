import { useQuery } from '@tanstack/react-query'
import { useSession } from '@/auth/SessionProvider'
import { planningRpc, type ReferenceCard } from '@/features/planning/queries'
import ReferenceSnapshot from '@/features/planning/ReferenceSnapshot'
import type { BriefDocument, BriefItem } from './model'
import type {
  BriefFile,
  BriefRevision,
  ProjectBriefData,
  BriefReadinessContext,
} from './queries'
import { reviewGroups, type ReviewArea } from './reviewModel'
import type { ReadinessTarget } from './readiness'
import type { ReactNode } from 'react'
const panel = 'space-y-4 rounded-xl border border-[#e5ddd3] bg-[#fffdf9] p-5'
const help = 'text-xs leading-relaxed text-[#786b60]'
export function useBriefDirection(projectId: string, enabled: boolean) {
  const { user } = useSession()
  return useQuery({
    queryKey: ['reference-direction', user?.id, projectId],
    enabled: Boolean(user && enabled),
    staleTime: 0,
    refetchInterval: 30000,
    queryFn: () =>
      planningRpc<ReferenceCard[]>('get_reference_direction', {
        p_project_id: projectId,
      }),
  })
}
export default function BriefReviewPackage({
  areas,
  areaError,
  retryAreas,
  document,
  files,
  references,
  referenceLoading,
  referenceError,
  onRetry,
  revision,
  data,
  metadata,
  canEdit,
  dirty,
  onEdit,
  download,
}: {
  areas: ReviewArea[]
  areaError: boolean
  retryAreas: () => void
  document: BriefDocument
  files: BriefFile[]
  references: ReferenceCard[]
  referenceLoading: boolean
  referenceError: boolean
  onRetry: () => void
  revision?: BriefRevision
  data: ProjectBriefData
  metadata?: BriefReadinessContext
  canEdit: boolean
  dirty: boolean
  onEdit: (target: ReadinessTarget) => void
  download: (file: BriefFile) => ReactNode
}) {
  const commitments = document.items.filter(
      (i) => i.kind === 'mandatory' || i.kind === 'preference',
    ),
    other = document.items.filter(
      (i) => i.kind === 'question' || i.kind === 'assumption',
    )
  const owner = (item: BriefItem) =>
    item.ownerProfileId
      ? (data.owners.find((p) => p.id === item.ownerProfileId)?.name ??
        'Previously assigned team member')
      : metadata?.defaultOwner?.name
        ? `${metadata.defaultOwner.name} (automatic)`
        : 'Automatic project assignment'
  const edit = (label: string, target: ReadinessTarget) =>
    canEdit ? (
      <button className="auth-link text-sm" onClick={() => onEdit(target)}>
        {label}
      </button>
    ) : null
  const renderItem = (item: BriefItem) => (
    <article
      key={item.id}
      className="space-y-2 rounded-lg border border-[#e5ddd3] bg-white p-4"
    >
      <p className={help}>
        {item.kind === 'mandatory'
          ? 'Requirement'
          : item.kind === 'preference'
            ? 'Preference'
            : item.kind === 'question'
              ? 'Question'
              : 'Assumption'}{' '}
        · {item.priority} priority · Source: {item.source.replace('_', ' ')}
      </p>
      <h4 className="break-words font-semibold">
        {item.title || 'Untitled item'}
      </h4>
      {item.detail && (
        <p className="whitespace-pre-wrap break-words text-sm">{item.detail}</p>
      )}
      {(item.kind === 'mandatory' || item.kind === 'preference') && (
        <>
          <p className="text-sm">
            <strong>Responsible:</strong> {owner(item)}
          </p>
          <p className="whitespace-pre-wrap break-words text-sm">
            <strong>Acceptance check:</strong>{' '}
            {item.acceptance || 'Not yet recorded'}
          </p>
        </>
      )}
      {item.kind === 'question' && (
        <p className="whitespace-pre-wrap break-words text-sm">
          <strong>Answer:</strong> {item.resolution || 'Still open'}
        </p>
      )}
      {item.appliesTo && (
        <p className="whitespace-pre-wrap break-words text-sm">
          <strong>Applies to:</strong> {item.appliesTo}
        </p>
      )}
      {edit('Edit ' + (item.title || 'item'), {
        kind: 'item',
        id: item.id,
        field: item.kind === 'question' ? 'resolution' : 'detail',
      })}
    </article>
  )
  return (
    <section
      id="brief-review-package"
      tabIndex={-1}
      aria-label={revision ? 'Saved brief package' : 'Complete brief package'}
      className="space-y-4"
    >
      <header className={panel}>
        <h2 className="text-xl font-semibold">
          {revision
            ? `Saved package · revision ${revision.number}`
            : 'Brief package for review'}
        </h2>
        <p className="text-sm text-[#786b60]">
          {revision
            ? 'This is the exact saved package requested for agreement.'
            : 'Review the overall needs, commitments and selected direction together before requesting agreement.'}
        </p>
        {!revision && dirty && (
          <p role="status" className="text-sm text-[#8a4a17]">
            This preview includes unsaved edits. Save before requesting
            agreement.
          </p>
        )}
        {revision && dirty && (
          <p className="text-sm text-[#8a4a17]">
            Your local draft edits are excluded from this saved package.
          </p>
        )}
        <nav
          aria-label="Brief package sections"
          className="flex flex-wrap gap-x-4 gap-y-2 text-sm"
        >
          {[
            ['overall', 'Overall brief'],
            ['commitments', 'Requirements & preferences'],
            ['questions', 'Assumptions & answers'],
            ['references', 'References & files'],
            ['decision', 'Review decision'],
          ].map(([id, label]) => (
            <a className="auth-link" key={id} href={'#brief-review-' + id}>
              {label}
            </a>
          ))}
        </nav>
      </header>
      <section
        id="brief-review-overall"
        className={panel}
        aria-label="Overall brief review"
      >
        <h3 className="text-lg font-semibold">Overall brief</h3>
        <dl className="space-y-4">
          {document.fields.map((f) => (
            <div
              key={f.id}
              className="space-y-1 border-b border-[#efe8df] pb-3 last:border-0"
            >
              <dt className="text-sm font-semibold">{f.label}</dt>
              <dd className="whitespace-pre-wrap break-words text-sm">
                {f.answer.trim() || 'Not recorded'}
              </dd>
              {edit('Edit ' + f.label, { kind: 'field', id: f.id })}
            </div>
          ))}
        </dl>
      </section>
      <section
        id="brief-review-commitments"
        className={panel}
        aria-label="Requirements and preferences review"
      >
        <h3 className="text-lg font-semibold">
          Requirements and preferences ({commitments.length})
        </h3>
        <p className={help}>
          Items assigned to several areas appear under each applicable area;
          they remain one commitment.
        </p>
        {!revision && areaError && (
          <p role="alert" className={help}>
            Area names could not be refreshed. Saved area labels are shown.{' '}
            <button className="auth-link" onClick={retryAreas}>
              Retry area names
            </button>
          </p>
        )}
        {reviewGroups(commitments, areas, Boolean(revision)).map((g) => (
          <section
            key={g.id}
            aria-label={'Requirements for ' + g.label}
            className="space-y-3"
          >
            <h4 className="font-medium">{g.label}</h4>
            {g.items.map(renderItem)}
          </section>
        ))}
        {!commitments.length && (
          <p className="text-sm">No requirements or preferences recorded.</p>
        )}
        {edit('Edit requirements', { kind: 'requirements' })}
      </section>
      <section
        id="brief-review-questions"
        className={panel}
        aria-label="Assumptions and answers review"
      >
        <h3 className="text-lg font-semibold">
          Assumptions and answers ({other.length})
        </h3>
        {reviewGroups(other, areas, Boolean(revision)).map((g) => (
          <section key={g.id} className="space-y-3">
            <h4 className="font-medium">{g.label}</h4>
            {g.items.map(renderItem)}
          </section>
        ))}
        {!other.length && (
          <p className="text-sm">No assumptions or questions recorded.</p>
        )}
      </section>
      <section
        id="brief-review-references"
        className={panel}
        aria-label="Selected references and files review"
      >
        <h3 className="text-lg font-semibold">
          Selected references and supporting files
        </h3>
        <p className={help}>
          {revision
            ? 'These selected references and files belong to this saved revision.'
            : 'Only selected references from shared boards are included here. Private team preparation is excluded.'}{' '}
          External websites may change. Uploaded files retain the reviewed copy.
        </p>
        {referenceLoading ? (
          <p role="status">Loading selected references…</p>
        ) : referenceError ? (
          <p role="alert">
            Could not load selected references.{' '}
            <button className="auth-link" onClick={onRetry}>
              Retry selected references
            </button>
          </p>
        ) : references.length ? (
          <ReferenceSnapshot cards={references} />
        ) : (
          <p className="text-sm">No visual references selected.</p>
        )}
        <h4 className="font-medium">
          Brief links ({document.references.length})
        </h4>
        {document.references.map((r) => (
          <a
            key={r.id}
            className="auth-link block break-all text-sm"
            href={/^https?:\/\//i.test(r.url) ? r.url : undefined}
            target="_blank"
            rel="noopener noreferrer"
          >
            {r.label || 'Untitled link'}
          </a>
        ))}
        <h4 className="font-medium">Attached files ({files.length})</h4>
        {files.map((f) => (
          <div key={f.id}>{download(f)}</div>
        ))}
        {!files.length && <p className="text-sm">No attached files.</p>}
      </section>
      {revision && (
        <p className={help}>
          Area labels are captured in this revision. Responsible-person names
          use the current project directory; the recorded person assignment
          stays fixed.
        </p>
      )}
    </section>
  )
}
