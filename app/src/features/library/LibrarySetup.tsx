import { useContext } from 'react'
import { Link } from 'react-router'
import { Button } from '@/features/planning/PlanningButton'
import { panel, help } from '@/features/planning/queries'
import { LibrarySaving, LibraryUnsaved } from './LibraryActivity'
import { collectionExamples, libraryCategoryLabel } from './libraryModel'
import type { Collection, LibraryItem } from './queries'

export function LibrarySetupProgress({
  step,
  onName,
  onContent,
  onReview,
  disabled = false,
  canReview = false,
}: {
  step: 1 | 2 | 3
  onName?: () => void
  onContent?: () => void
  onReview?: () => void
  disabled?: boolean
  canReview?: boolean
}) {
  const steps = [
    { name: 'Name collection', action: onName },
    { name: 'Add content', action: onContent },
    { name: 'Check & submit', action: onReview },
  ]
  return (
    <ol
      aria-label="Collection setup progress"
      className="grid grid-cols-3 gap-2"
    >
      {steps.map((s, i) => (
        <li
          key={s.name}
          aria-current={step === i + 1 ? 'step' : undefined}
          className={`rounded-lg border px-2 py-2 text-xs sm:px-3 sm:text-sm ${step === i + 1 ? 'border-[#b64d24] bg-[#fff3e9] font-semibold' : 'border-[#e5ddd3] text-[#786b60]'}`}
        >
          {s.action ? (
            <button
              className="w-full text-left"
              disabled={disabled || (i === 2 && !canReview)}
              onClick={s.action}
            >
              {i + 1}. {s.name}
            </button>
          ) : (
            <span>
              {i + 1}. {s.name}
            </span>
          )}
        </li>
      ))}
    </ol>
  )
}
export function CollectionExample({
  kind,
  onUseName,
  compact = false,
}: {
  kind: Collection['kind']
  onUseName?: (name: string) => void
  compact?: boolean
}) {
  const example = collectionExamples[kind]
  return (
    <aside
      aria-label="Collection example"
      className="space-y-2 rounded-lg bg-[#f3eee6] p-4 text-sm"
    >
      <p className="text-xs font-semibold uppercase tracking-wide text-[#786b60]">
        Example · {libraryCategoryLabel(kind)}
      </p>
      <p>
        <strong>{example.name}</strong> — {example.purpose}
      </p>
      <details open={compact ? undefined : true}>
        <summary className="auth-link cursor-pointer text-sm">
          What to add
        </summary>
        <ul className="mt-2 list-disc space-y-1 pl-5 text-[#786b60]">
          {example.items.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ul>
        <p className={help}>Suggested tags: {example.tags.join(', ')}.</p>
      </details>
      {onUseName && (
        <button
          type="button"
          className="auth-link text-sm"
          onClick={() => onUseName(example.name)}
        >
          Use example name
        </button>
      )}
      <p className={help}>
        Build your collection with your own files, links and notes.
      </p>
    </aside>
  )
}
export function LibrarySetupGuide({
  collection,
  items,
  step,
  ready,
  editDetails,
  setStep,
}: {
  collection: Collection
  items: LibraryItem[]
  step: 'content' | 'review'
  ready: boolean
  editDetails: () => void
  setStep: (step: 'content' | 'review') => void
}) {
  const saving = useContext(LibrarySaving),
    dirty = useContext(LibraryUnsaved),
    disabled = saving || dirty
  return (
    <section
      aria-label="Build your collection"
      className={`${panel} space-y-4`}
    >
      <LibrarySetupProgress
        step={step === 'content' ? 2 : 3}
        onName={editDetails}
        onContent={() => setStep('content')}
        onReview={() => setStep('review')}
        disabled={disabled}
        canReview={ready && items.length > 0}
      />
      <div>
        <p className="text-xs font-semibold uppercase tracking-wide text-[#786b60]">
          Draft saved
        </p>
        <h2 className="mt-1 text-xl font-semibold">
          {step === 'content'
            ? 'Add useful content'
            : 'Check your collection before submitting'}
        </h2>
        <p className={'mt-2 ' + help}>
          {step === 'content'
            ? 'Upload files, add source links or write guidance your team can reuse. Each item is saved when you add it. You can finish this collection later.'
            : 'Preview the items below, check their titles and sources, then submit the collection for organisation owner/admin approval.'}
        </p>
      </div>
      {step === 'content' && !items.length && (
        <CollectionExample kind={collection.kind} />
      )}
      {step === 'content' && collection.review_note && (
        <p className="rounded-lg bg-[#fbf0dd] p-3 text-sm">
          <strong>Changes requested:</strong> {collection.review_note}
        </p>
      )}
      {step === 'review' && (
        <>
          {ready && !items.length && (
            <p className="text-sm">
              Add at least one saved item before submitting.{' '}
              <button className="auth-link" onClick={() => setStep('content')}>
                Add content
              </button>
            </p>
          )}
          <p className="text-sm">
            <strong>
              {items.length} {items.length === 1 ? 'item' : 'items'}
            </strong>{' '}
            · Files: {items.filter((i) => i.file).length} · Links:{' '}
            {items.filter((i) => i.url).length} · Notes:{' '}
            {items.filter((i) => !i.file && !i.url).length}
          </p>
          <div className="rounded-lg bg-[#f3eee6] p-3">
            <h3 className="text-sm font-semibold">
              Make it useful for the next project
            </h3>
            <ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-[#786b60]">
              <li>
                Use clear item titles and check that sources and attachments are
                correct.
              </li>
              {!collection.description.trim() && (
                <li>
                  Add a description explaining when to reuse this collection.{' '}
                  <button
                    className="auth-link"
                    disabled={disabled}
                    onClick={editDetails}
                  >
                    Add description
                  </button>
                </li>
              )}
              {!collection.tags?.length && (
                <li>
                  Add tags so teammates can find it again.{' '}
                  <button
                    className="auth-link"
                    disabled={disabled}
                    onClick={editDetails}
                  >
                    Add tags
                  </button>
                </li>
              )}
              {items.some((i) => i.file && !i.description.trim()) && (
                <li>
                  Consider adding notes explaining how to use your files.{' '}
                  <button
                    className="auth-link"
                    disabled={disabled}
                    onClick={() => setStep('content')}
                  >
                    Edit content
                  </button>
                </li>
              )}
            </ul>
            <p className={'mt-2 ' + help}>
              These suggestions are optional. A named collection with at least
              one saved item can be submitted.
            </p>
          </div>
        </>
      )}
    </section>
  )
}
export function LibrarySetupFooter({
  step,
  ready,
  hasItems,
  finishLater,
  setStep,
}: {
  step: 'content' | 'review'
  ready: boolean
  hasItems: boolean
  finishLater: () => void
  setStep: (step: 'content' | 'review') => void
}) {
  const saving = useContext(LibrarySaving),
    dirty = useContext(LibraryUnsaved),
    disabled = saving || dirty
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-[#e5ddd3] bg-[#fffdf9] p-4">
      <div>
        <p className="text-sm font-medium">
          Your saved draft is available in Contributions.
        </p>
        <p className={help}>Only saved changes will be kept when you leave.</p>
      </div>
      <div className="flex flex-wrap gap-2">
        <Button variant="secondary" disabled={disabled} onClick={finishLater}>
          Save draft & finish later
        </Button>
        {step === 'content' ? (
          <Button
            disabled={disabled || !ready || !hasItems}
            onClick={() => setStep('review')}
          >
            Continue to check & submit
          </Button>
        ) : (
          <Button
            variant="secondary"
            disabled={disabled}
            onClick={() => setStep('content')}
          >
            Back to content
          </Button>
        )}
      </div>
    </div>
  )
}
export function LibraryPublicationStatus({
  collection,
  org,
  toContributions,
  toPublished,
}: {
  collection: Collection
  org: string
  toContributions: () => void
  toPublished: () => void
}) {
  return (
    <section
      aria-label="Collection publication status"
      className={`${panel} space-y-3`}
    >
      <h2 className="text-xl font-semibold">
        {collection.status === 'published'
          ? 'Published and ready to reuse'
          : 'Waiting for organisation admin approval'}
      </h2>
      <p className="text-sm text-[#786b60]">
        {collection.status === 'published'
          ? 'Your collection is available to every workspace in the organisation. Open a project, go to Reference boards, and choose Add from organisation library.'
          : 'Your saved collection has been submitted. An organisation owner or admin will review it before it appears in the Published library. You can track its status in Contributions.'}
      </p>
      {collection.status === 'in_review' && collection.canReview && (
        <p className={help}>
          As an organisation owner/admin, you can review and publish this
          submission using the controls below.
        </p>
      )}
      <div className="flex flex-wrap gap-3">
        {collection.status === 'published' ? (
          <>
            <Button onClick={toPublished}>View published library</Button>
            <Link
              className="auth-link self-center text-sm"
              to={`/workspaces?org=${org}`}
            >
              Choose a workspace and project →
            </Link>
          </>
        ) : (
          <Button variant="secondary" onClick={toContributions}>
            Back to contributions
          </Button>
        )}
      </div>
    </section>
  )
}
