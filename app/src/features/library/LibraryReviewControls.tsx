import { useContext, useState } from 'react'
import { Button } from '@/features/planning/PlanningButton'
import { planningRpc, panel, help } from '@/features/planning/queries'
import { useLibraryHistory, useLibraryAction, type Collection } from './queries'
import { LibrarySaving, LibraryUnsaved } from './LibraryActivity'
export const statusLabel = {
  draft: 'Draft',
  in_review: 'In review',
  changes_requested: 'Changes requested',
  published: 'Published',
}
export function ReviewControls({
  org,
  collection,
  admin,
  onArchived,
}: {
  org: string
  collection: Collection
  admin: boolean
  onArchived: () => void
}) {
  const savingNow = useContext(LibrarySaving),
    unsaved = useContext(LibraryUnsaved),
    saving = savingNow || unsaved,
    action = useLibraryAction(),
    [note, setNote] = useState(''),
    history = useLibraryHistory(collection.id, collection.canSeeDraft)
  const transition = async (p_action: string) => {
    const r = await action.run(() =>
      planningRpc('transition_library_collection', {
        p_collection_id: collection.id,
        p_expected_version: collection.edit_version,
        p_action,
        p_note: note,
      }),
    )
    if (r.ok) setNote('')
  }
  return (
    <section className={panel}>
      <div className="flex flex-wrap items-center gap-2">
        <span className="rounded-full bg-[#eee6dc] px-3 py-1 text-xs font-semibold">
          {statusLabel[collection.status]}
        </span>
        <span className={help}>Contributed by {collection.authorName}</span>
        {collection.published && (
          <span className={help}>
            Published revision {collection.published.revision} remains available
            to projects.
          </span>
        )}
      </div>
      {collection.review_note && collection.canSeeDraft && (
        <p className="rounded-lg bg-[#fbf0dd] p-3 text-sm">
          <strong>Review feedback:</strong> {collection.review_note}
        </p>
      )}
      {collection.canSeeDraft && (
        <>
          <p className={help}>
            {collection.status === 'in_review'
              ? 'This submission is locked while it is reviewed. Withdraw it to make further edits.'
              : collection.status === 'published'
                ? 'Start a revision to propose changes. The current published version stays available until the revision is approved.'
                : 'Add references and save your changes, then submit the collection for owner/admin approval.'}
          </p>
          <div className="flex flex-wrap gap-2">
            {collection.canEdit && (
              <Button
                disabled={saving || action.busy || !collection.itemCount}
                onClick={() => void transition('submit')}
              >
                Submit for review
              </Button>
            )}
            {collection.status === 'published' && (
              <Button
                disabled={saving || action.busy}
                onClick={() => void transition('revise')}
              >
                Start a revision
              </Button>
            )}
            {collection.status === 'in_review' && (
              <Button
                variant="secondary"
                disabled={saving || action.busy}
                onClick={() => void transition('withdraw')}
              >
                Withdraw submission
              </Button>
            )}
          </div>
          {collection.canReview && (
            <div className="space-y-3 border-t border-[#e5ddd3] pt-3">
              <h3 className="font-semibold">Review this submission</h3>
              <p className={help}>
                Check the collection title, description, references and attached
                files below before publishing.
              </p>
              <label className="block text-sm">
                Review feedback
                <textarea
                  aria-label="Review feedback"
                  className="auth-field mt-1 w-full"
                  value={note}
                  maxLength={3000}
                  disabled={saving || action.busy}
                  onChange={(e) => setNote(e.target.value)}
                />
              </label>
              <div className="flex flex-wrap gap-2">
                <Button
                  disabled={saving || action.busy}
                  onClick={() => void transition('publish')}
                >
                  Approve & publish
                </Button>
                <Button
                  variant="secondary"
                  disabled={saving || action.busy || !note.trim()}
                  onClick={() => void transition('request_changes')}
                >
                  Request changes
                </Button>
              </div>
            </div>
          )}
          <details>
            <summary className="auth-link cursor-pointer text-sm">
              Review history
            </summary>
            {history.isLoading ? (
              <p role="status">Loading review history…</p>
            ) : history.isError ? (
              <p role="alert">
                Could not load history.{' '}
                <button
                  className="auth-link"
                  onClick={() => void history.refetch()}
                >
                  Retry
                </button>
              </p>
            ) : (
              <ol className="mt-3 space-y-2">
                {history.data?.map((e) => (
                  <li key={e.id} className="text-sm">
                    <strong>{e.action.replaceAll('_', ' ')}</strong> · {e.name}{' '}
                    · {new Date(e.created_at).toLocaleString()}
                    {e.note && <p className="whitespace-pre-wrap">{e.note}</p>}
                  </li>
                ))}
              </ol>
            )}
          </details>
        </>
      )}
      {admin && (
        <button
          type="button"
          className="auth-link text-sm"
          disabled={saving || action.busy}
          onClick={async () => {
            if (
              !window.confirm(
                'Archive this collection? Existing project copies remain available.',
              )
            )
              return
            const r = await action.run(() =>
              planningRpc('save_library_collection', {
                p_organization_id: org,
                p_id: collection.id,
                p_title: collection.title,
                p_kind: collection.kind,
                p_description: collection.description,
                p_expected_version: collection.edit_version,
                p_archive: true,
              }),
            )
            if (r.ok) onArchived()
          }}
        >
          Archive collection
        </button>
      )}
      {action.error && (
        <p role="alert" className="text-sm text-red-700">
          {action.error}
        </p>
      )}
    </section>
  )
}
