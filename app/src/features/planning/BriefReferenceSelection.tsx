import { Link } from 'react-router'
import { type ReferenceCard, help, useReferenceBoards } from './queries'
import ReferenceSnapshot from './ReferenceSnapshot'
export default function BriefReferenceSelection({
  projectId,
  workspaceId,
  snapshot,
}: {
  projectId: string
  workspaceId: string
  snapshot?: ReferenceCard[]
}) {
  const boards = useReferenceBoards(projectId, !snapshot),
    data = boards.data
  return (
    <section className="space-y-3 rounded-xl border border-[#e5ddd3] p-5">
      <h2 className="font-semibold">References for the brief</h2>
      {snapshot ? (
        <>
          <p className={help}>
            These references and preferences were captured for this exact brief
            revision. External websites may change; uploaded files retain the
            reviewed copy.
          </p>
          {snapshot.length ? (
            <ReferenceSnapshot cards={snapshot} />
          ) : (
            <p className="text-sm">
              No visual references were selected for this revision.
            </p>
          )}
        </>
      ) : (
        <>
          <p className="text-sm">
            The team prepares references privately, shares boards for client
            input, then selects the direction included in brief agreement.
            Client shortlists record preferences.
          </p>
          {boards.isLoading ? (
            <p role="status" className={help}>
              Loading reference progress…
            </p>
          ) : boards.isError ? (
            <p role="alert" className={help}>
              Could not load reference progress.{' '}
              <button
                className="auth-link"
                onClick={() => void boards.refetch()}
              >
                Retry
              </button>
            </p>
          ) : (
            <div className="flex flex-wrap gap-3 text-sm">
              {data?.isTeam && (
                <span>
                  {data.boards.filter((b) => !b.shared_at).length} team boards
                </span>
              )}
              <span>
                {data?.boards.filter((b) => b.shared_at).length ?? 0} shared
                boards
              </span>
              <span>
                {data?.boards
                  .filter((b) => b.shared_at)
                  .reduce((n, b) => n + (b.selectedCount ?? 0), 0) ?? 0}{' '}
                references selected for the brief
              </span>
            </div>
          )}
          <Link
            className="auth-link text-sm"
            to={`/workspace/${workspaceId}/project/${projectId}/references`}
          >
            Open reference boards
          </Link>
        </>
      )}
    </section>
  )
}
