import {
  ReferenceSaveGuard,
  ReferenceSaving,
  ReferenceUnsaved,
  ReferenceActivity,
  useReferenceDirty,
} from './ReferenceActivity'
import { useContext, useEffect, useState } from 'react'
import { Link, useParams, useSearchParams } from 'react-router'
import { useInfiniteQuery, useQuery } from '@tanstack/react-query'
import { toast } from 'sonner'
import { useSession } from '@/auth/SessionProvider'
import { useProjectAreas } from '@/features/areas/queries'
import { Button } from './PlanningButton'
import {
  useReferenceBoards,
  usePlanningAction,
  planningRpc,
  type ReferenceCard,
  type ReferenceBoard,
  panel,
  help,
} from './queries'
import ReferenceCardView from './ReferenceCardView'
import ImportLibrary from '@/features/library/ImportLibrary'
function BoardForm({
  projectId,
  board,
  onSaved,
}: {
  projectId: string
  board?: ReferenceBoard
  onSaved: (id: string) => void
}) {
  const areas = useProjectAreas(projectId),
    action = usePlanningAction(projectId),
    [title, setTitle] = useState(board?.title ?? ''),
    [kind, setKind] = useState(board?.kind ?? 'moodboard'),
    [description, setDescription] = useState(board?.description ?? ''),
    [area, setArea] = useState(board?.area_id ?? ''),
    [version, setVersion] = useState(board?.edit_version ?? 0)
  const dirty =
    title !== (board?.title ?? '') ||
    kind !== (board?.kind ?? 'moodboard') ||
    description !== (board?.description ?? '') ||
    area !== (board?.area_id ?? '')
  const clearDirty = useReferenceDirty(dirty)
  useEffect(() => {
    if (board && !dirty) setVersion(board.edit_version)
  }, [board?.edit_version, dirty])
  return (
    <form
      className="space-y-3"
      onSubmit={async (e) => {
        e.preventDefault()
        const r = await action.run<string>('save_reference_board', {
          p_project_id: projectId,
          p_board_id: board?.id ?? null,
          p_expected_version: version,
          p_title: title,
          p_kind: kind,
          p_description: description,
          p_area_id: area || null,
        })
        if (r.ok) {
          clearDirty()
          if (board) setVersion((v) => v + 1)
          if (!board) {
            setTitle('')
            setDescription('')
            setKind('moodboard')
            setArea('')
          }
          onSaved(r.data)
        }
      }}
    >
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <label className="text-sm">
          Board title
          <input
            className="auth-field mt-1 w-full"
            required
            maxLength={160}
            value={title}
            disabled={action.busy}
            onChange={(e) => setTitle(e.target.value)}
          />
        </label>
        <div className="min-w-0 text-sm">
          <label htmlFor={`board-kind-${board?.id ?? 'new'}`}>
            Board layout
          </label>
          <select
            id={`board-kind-${board?.id ?? 'new'}`}
            className="auth-field mt-1 w-full"
            value={kind}
            disabled={action.busy}
            onChange={(e) => setKind(e.target.value as ReferenceBoard['kind'])}
          >
            <option value="moodboard">Mood board</option>
            <option value="references">References</option>
            {board?.kind === 'template' && (
              <option value="template">Existing reusable board</option>
            )}
          </select>
        </div>
        <div className="min-w-0 text-sm">
          <label htmlFor={`board-area-${board?.id ?? 'new'}`}>Board area</label>
          <select
            id={`board-area-${board?.id ?? 'new'}`}
            className="auth-field mt-1 w-full"
            value={area}
            disabled={action.busy}
            onChange={(e) => setArea(e.target.value)}
          >
            <option value="">Project-wide</option>
            {areas.data?.areas
              .filter((a) => !a.archived || a.id === area)
              .map((a) => (
                <option key={a.id} value={a.id}>
                  {a.path}
                  {a.archived ? ' (archived)' : ''}
                </option>
              ))}
          </select>
        </div>
        <label className="text-sm">
          Board description
          <input
            className="auth-field mt-1 w-full"
            maxLength={3000}
            value={description}
            disabled={action.busy}
            onChange={(e) => setDescription(e.target.value)}
          />
        </label>
      </div>
      <Button size="sm" disabled={action.busy || !title.trim()}>
        {board ? 'Save board' : 'Create board'}
      </Button>
      {!board && (
        <button
          type="button"
          className="auth-link ml-3 text-sm"
          disabled={action.busy}
          onClick={() => {
            setTitle('')
            setKind('moodboard')
            setDescription('')
            setArea('')
            clearDirty()
          }}
        >
          Clear draft
        </button>
      )}
      {board && (
        <button
          type="button"
          className="auth-link ml-3 text-xs"
          disabled={action.busy}
          onClick={() => {
            setTitle(board.title)
            setKind(board.kind)
            setDescription(board.description)
            setArea(board.area_id ?? '')
            setVersion(board.edit_version)
            action.clearError()
          }}
        >
          Reload board settings
        </button>
      )}
      {action.error && (
        <p role="alert" className="text-sm text-red-700">
          {action.error}
        </p>
      )}
    </form>
  )
}
function AddReference({
  boardId,
  projectId,
  open = false,
}: {
  boardId: string
  projectId: string
  open?: boolean
}) {
  const action = usePlanningAction(projectId),
    [title, setTitle] = useState(''),
    [description, setDescription] = useState(''),
    [url, setUrl] = useState('')
  const clearDirty = useReferenceDirty(Boolean(title || description || url))
  return (
    <details open={open || undefined} className={panel}>
      <summary className="auth-link cursor-pointer font-medium">
        Suggest or add a reference
      </summary>
      <form
        className="space-y-3"
        onSubmit={async (e) => {
          e.preventDefault()
          if (
            (
              await action.run('save_reference_card', {
                p_board_id: boardId,
                p_title: title,
                p_description: description,
                p_url: url || null,
              })
            ).ok
          ) {
            clearDirty()
            setTitle('')
            setDescription('')
            setUrl('')
          }
        }}
      >
        <label className="block text-sm">
          New reference title
          <input
            className="auth-field mt-1 w-full"
            value={title}
            maxLength={200}
            required
            disabled={action.busy}
            onChange={(e) => setTitle(e.target.value)}
          />
        </label>
        <label className="block text-sm">
          Why this reference?
          <textarea
            className="auth-field mt-1 min-h-20 w-full"
            value={description}
            maxLength={5000}
            disabled={action.busy}
            onChange={(e) => setDescription(e.target.value)}
          />
        </label>
        <label className="block text-sm">
          Source URL (optional)
          <input
            className="auth-field mt-1 w-full"
            type="url"
            value={url}
            maxLength={2000}
            disabled={action.busy}
            onChange={(e) => setUrl(e.target.value)}
          />
        </label>
        <p className={help}>
          Add the reference, then attach an image or document to its card.
          Explain whether you mean its colours, layout, material or another
          detail.
        </p>
        <Button size="sm" disabled={action.busy || !title.trim()}>
          Add reference
        </Button>
        {(title || description || url) && (
          <button
            type="button"
            className="auth-link ml-3 text-sm"
            disabled={action.busy}
            onClick={() => {
              setTitle('')
              setDescription('')
              setUrl('')
              clearDirty()
            }}
          >
            Clear draft
          </button>
        )}
        {action.error && (
          <p role="alert" className="text-sm text-red-700">
            {action.error}
          </p>
        )}
      </form>
    </details>
  )
}
function TemplateCopy({
  board,
  projectId,
  onSaved,
}: {
  board: ReferenceBoard
  projectId: string
  onSaved: (id: string) => void
}) {
  const areas = useProjectAreas(projectId),
    action = usePlanningAction(projectId),
    [title, setTitle] = useState(board.title + ' — direction'),
    [area, setArea] = useState('')
  return (
    <details className={panel}>
      <summary className="auth-link cursor-pointer">Use this template</summary>
      <p className={help}>
        Copies its reference cards into a new mood board in this project.
        Preferences, comments and brief selections start fresh.
      </p>
      <form
        className="space-y-3"
        onSubmit={async (e) => {
          e.preventDefault()
          const r = await action.run<string>('duplicate_reference_template', {
            p_board_id: board.id,
            p_title: title,
            p_area_id: area || null,
          })
          if (r.ok) onSaved(r.data)
        }}
      >
        <label className="block text-sm">
          New mood board title
          <input
            className="auth-field mt-1 w-full"
            value={title}
            maxLength={160}
            required
            disabled={action.busy}
            onChange={(e) => setTitle(e.target.value)}
          />
        </label>
        <div className="text-sm">
          <label htmlFor="template-target-area">Use template for</label>
          <select
            id="template-target-area"
            className="auth-field mt-1 w-full"
            value={area}
            disabled={action.busy}
            onChange={(e) => setArea(e.target.value)}
          >
            <option value="">Project-wide</option>
            {areas.data?.areas
              .filter((a) => !a.archived)
              .map((a) => (
                <option key={a.id} value={a.id}>
                  {a.path}
                </option>
              ))}
          </select>
        </div>
        <Button size="sm" disabled={action.busy || !title.trim()}>
          Create mood board from template
        </Button>
        {action.error && (
          <p role="alert" className="text-sm text-red-700">
            {action.error}
          </p>
        )}
      </form>
    </details>
  )
}
export function Component() {
  return (
    <ReferenceSaveGuard>
      <ReferencePage />
    </ReferenceSaveGuard>
  )
}
function ReferencePage() {
  const { ws_id: workspaceId = '', proj_id: projectId = '' } = useParams(),
    { user } = useSession(),
    query = useReferenceBoards(projectId),
    areas = useProjectAreas(projectId),
    action = usePlanningAction(projectId),
    [params, setParams] = useSearchParams(),
    [scope, setScope] = useState('all'),
    [uploads, setUploads] = useState(0)
  const saving = useContext(ReferenceSaving),
    unsaved = useContext(ReferenceUnsaved),
    activity = useContext(ReferenceActivity)
  const boardId = params.get('board'),
    all = query.data?.boards ?? [],
    isTeam = Boolean(query.data?.isTeam),
    requested = all.find((b) => b.id === boardId),
    stage =
      (['team', 'shared', 'direction'].includes(params.get('stage') ?? '') &&
      (isTeam || params.get('stage') !== 'team')
        ? params.get('stage')
        : null) ??
      (requested
        ? requested.shared_at
          ? 'shared'
          : 'team'
        : isTeam
          ? 'team'
          : 'shared')
  const selectedArea = areas.data?.areas.find((a) => a.id === scope),
    parentIds = new Set<string>()
  let current = selectedArea
  while (current) {
    parentIds.add(current.id)
    current = areas.data?.areas.find((a) => a.id === current?.parent_area_id)
  }
  const visible = all.filter(
    (b) =>
      (stage === 'team'
        ? !b.shared_at
        : stage === 'direction'
          ? Boolean(b.shared_at && b.selectedCount)
          : Boolean(b.shared_at)) &&
      (scope === 'all' ||
        !b.area_id ||
        (scope !== 'project' && parentIds.has(b.area_id))),
  )
  const board = boardId ? visible.find((b) => b.id === boardId) : visible[0]
  const choose = (id: string) => {
    setScope('all')
    const next = new URLSearchParams(params)
    next.set('board', id)
    next.delete('stage')
    next.delete('add')
    setParams(next, { replace: true })
  }
  const cards = useInfiniteQuery({
    queryKey: ['reference-board', user?.id, board?.id],
    enabled: Boolean(user && board && stage !== 'direction'),
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) =>
      planningRpc<{ cards: ReferenceCard[]; nextCursor: string | null }>(
        'get_reference_board',
        { p_board_id: board!.id, p_limit: 24, p_after: pageParam },
      ),
    getNextPageParam: (p) => p.nextCursor ?? undefined,
    refetchInterval: 30000,
  })
  const direction = useQuery({
    queryKey: ['reference-direction', user?.id, projectId],
    enabled: Boolean(user && projectId && stage === 'direction'),
    queryFn: () =>
      planningRpc<ReferenceCard[]>('get_reference_direction', {
        p_project_id: projectId,
      }),
    refetchInterval: 30000,
  })
  const changeStage = (nextStage: string) => {
    const next = new URLSearchParams(params)
    next.set('stage', nextStage)
    next.delete('board')
    next.delete('add')
    setParams(next)
    setScope('all')
  }
  const openClientInput = async () => {
    const result = await action.run<string>(
      'get_or_create_client_reference_board',
      { p_project_id: projectId },
    )
    if (result.ok) {
      const next = new URLSearchParams(params)
      next.set('board', result.data)
      next.set('stage', 'shared')
      next.set('add', '1')
      setParams(next)
      setScope('all')
    }
  }
  if (query.isLoading)
    return (
      <p className="p-6" role="status">
        Loading reference boards…
      </p>
    )
  if (query.isError)
    return (
      <div className="p-6">
        <p role="alert">Could not load reference boards.</p>
        <button className="auth-link" onClick={() => void query.refetch()}>
          Retry
        </button>
      </div>
    )
  return (
    <div className="lign-warm mx-auto max-w-6xl space-y-5 p-5 md:p-7">
      <div>
        <h1 className="auth-display text-3xl">References</h1>
        <p className="mt-2 text-sm">
          Prepare ideas, collect client preferences, then choose the direction
          included in brief agreement.
        </p>
        <Link
          className="auth-link mt-2 inline-block text-sm"
          to={`/workspace/${workspaceId}/project/${projectId}/brief?step=references`}
        >
          Back to project brief
        </Link>
      </div>
      <nav aria-label="Reference stages" className="flex flex-wrap gap-2">
        {[
          ...(isTeam ? [{ id: 'team', label: 'Team preparation' }] : []),
          { id: 'shared', label: 'Client input' },
          { id: 'direction', label: 'Brief direction' },
        ].map((s) => (
          <button
            key={s.id}
            aria-pressed={stage === s.id}
            className={`rounded-lg border px-4 py-2 text-sm ${stage === s.id ? 'border-[#3a332d] bg-[#3a332d] text-white' : 'border-[#e5ddd3] bg-[#fffdf9]'}`}
            onClick={() => changeStage(s.id)}
          >
            {s.label}
          </button>
        ))}
      </nav>
      <section className={panel}>
        <h2 className="font-semibold">
          {stage === 'team'
            ? 'Prepare references with your team'
            : stage === 'direction'
              ? 'Direction selected for the brief'
              : 'Explore and contribute together'}
        </h2>
        <p className={help}>
          {stage === 'team'
            ? 'New boards and Library imports are private to internal project members. Share a board when it is ready for client input. Preparation discussion and preferences stay internal.'
            : stage === 'direction'
              ? 'These are the references explicitly selected by project leadership. Client shortlists help the decision; they do not automatically become the agreed direction.'
              : 'Shared boards are visible to project participants. Add your own references, explain the details you like, and use Like, Shortlist or Not for us to give feedback.'}
        </p>
        {query.data?.canContribute && stage !== 'direction' && (
          <Button
            variant="secondary"
            disabled={action.busy}
            onClick={() => void openClientInput()}
          >
            {isTeam ? 'Open client suggestions' : 'Add your references'}
          </Button>
        )}
        {stage === 'direction' && (
          <Link
            className="auth-link text-sm"
            to={`/workspace/${workspaceId}/project/${projectId}/brief?step=agreement`}
          >
            Continue to review and agree →
          </Link>
        )}
      </section>
      {stage !== 'direction' && query.data?.canManage && (
        <ImportLibrary
          projectId={projectId}
          workspaceId={workspaceId}
          onSaved={choose}
        />
      )}
      {stage !== 'direction' && query.data?.canManage && (
        <details className={panel}>
          <summary className="auth-link cursor-pointer font-medium">
            Create a reference board
          </summary>
          <BoardForm projectId={projectId} onSaved={choose} />
        </details>
      )}
      {stage !== 'direction' && (
        <>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div className="min-w-0 text-sm">
              <label htmlFor="reference-area-filter">Browse area</label>
              <select
                id="reference-area-filter"
                className="auth-field mt-1 w-full"
                value={scope}
                onChange={(e) => setScope(e.target.value)}
              >
                <option value="all">All areas</option>
                <option value="project">Project-wide boards</option>
                {areas.data?.areas
                  .filter((a) => !a.archived)
                  .map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.path}
                    </option>
                  ))}
              </select>
            </div>
            <div className="min-w-0 text-sm">
              <label htmlFor="reference-board-picker">Reference board</label>
              <select
                id="reference-board-picker"
                className="auth-field mt-1 w-full"
                value={board?.id ?? ''}
                onChange={(e) => choose(e.target.value)}
              >
                {!visible.length && <option value="">No boards yet</option>}
                {visible.map((b) => (
                  <option key={b.id} value={b.id}>
                    {b.title} · {b.areaPath ?? 'Project-wide'} · {b.kind}
                  </option>
                ))}
              </select>
            </div>
          </div>
          <p className={help}>
            Area views include project-wide and parent-area boards. A shortlist
            records a preference; the team explicitly selects the direction
            included in brief agreement.
          </p>
          {!board ? (
            <p className={panel}>
              {boardId
                ? 'This board is unavailable in this view.'
                : stage === 'team'
                  ? query.data?.canManage
                    ? 'Create a private board or import an approved Library collection to start preparing.'
                    : 'Project leadership can prepare private boards here.'
                  : query.data?.canContribute
                    ? 'No boards have been shared here yet. You can add your own references using the button above.'
                    : 'No reference boards have been shared with you yet.'}
            </p>
          ) : (
            <>
              <section className={panel}>
                <h2 className="text-xl font-semibold">{board.title}</h2>
                <p className={help}>
                  {board.areaPath ?? 'Project-wide'} ·{' '}
                  {board.shared_at
                    ? 'Shared with project participants'
                    : 'Private team preparation'}
                </p>
                {!board.shared_at && query.data?.canManage && (
                  <div className="space-y-2">
                    <p className={help}>
                      Sharing makes this board’s references and future additions
                      visible to project participants. Existing internal
                      discussion stays private.
                    </p>
                    <Button
                      disabled={action.busy || saving || unsaved || uploads > 0}
                      onClick={async () => {
                        const r = await action.run('share_reference_board', {
                          p_board_id: board.id,
                          p_expected_version: board.edit_version,
                        })
                        if (r.ok) {
                          const next = new URLSearchParams(params)
                          next.set('stage', 'shared')
                          next.set('board', board.id)
                          setParams(next)
                          toast.success('Board shared for client input')
                        }
                      }}
                    >
                      Share with client
                    </Button>
                  </div>
                )}
                {board.shared_at && query.data?.canManage && (
                  <button
                    className="auth-link text-sm"
                    onClick={async () => {
                      try {
                        await navigator.clipboard.writeText(
                          `${window.location.origin}/workspace/${workspaceId}/project/${projectId}/references?stage=shared&board=${board.id}`,
                        )
                        toast.success('Client review link copied')
                      } catch {
                        toast.error('Could not copy review link')
                      }
                    }}
                  >
                    Copy client review link
                  </button>
                )}
                <p className="whitespace-pre-wrap text-sm">
                  {board.description}
                </p>
                {query.data?.canManage && (
                  <details>
                    <summary className="auth-link cursor-pointer text-sm">
                      Board settings
                    </summary>
                    <BoardForm
                      key={board.id}
                      projectId={projectId}
                      board={board}
                      onSaved={choose}
                    />
                    <button
                      className="auth-link mt-3 text-xs"
                      disabled={action.busy}
                      onClick={() => {
                        if (
                          window.confirm(
                            'Archive this board? Reviewed snapshots retain their references.',
                          )
                        )
                          void action.run('archive_reference_board', {
                            p_board_id: board.id,
                            p_expected_version: board.edit_version,
                          })
                      }}
                    >
                      Archive board
                    </button>
                  </details>
                )}
              </section>
              {query.data?.canManage && board.kind === 'template' && (
                <TemplateCopy
                  key={board.id}
                  board={board}
                  projectId={projectId}
                  onSaved={choose}
                />
              )}
              {query.data?.canContribute && (
                <AddReference
                  key={board.id}
                  boardId={board.id}
                  projectId={projectId}
                  open={params.get('add') === '1'}
                />
              )}
              {cards.isLoading ? (
                <p role="status">Loading references…</p>
              ) : cards.isError ? (
                <p role="alert">
                  Could not load references.{' '}
                  <button
                    className="auth-link"
                    onClick={() => void cards.refetch()}
                  >
                    Retry
                  </button>
                </p>
              ) : (
                <div
                  className={
                    board.kind === 'references'
                      ? 'space-y-4'
                      : 'columns-1 gap-4 md:columns-2 xl:columns-3 [&>article]:mb-4 [&>article]:break-inside-avoid'
                  }
                >
                  {cards.data?.pages
                    .flatMap((p) => p.cards)
                    .map((card) => (
                      <ReferenceCardView
                        key={card.id}
                        card={card}
                        projectId={projectId}
                        canManage={Boolean(query.data?.canManage)}
                        canContribute={Boolean(query.data?.canContribute)}
                        shared={Boolean(board.shared_at)}
                        onUploading={(busy) => {
                          setUploads((n) => n + (busy ? 1 : -1))
                          activity(busy ? 1 : -1)
                        }}
                      />
                    ))}
                </div>
              )}
              {board.cardCount === 0 && (
                <p className="text-sm">
                  Add a reference to begin exploring the direction.
                </p>
              )}
              {cards.hasNextPage && (
                <Button
                  variant="secondary"
                  disabled={cards.isFetchingNextPage}
                  onClick={() => void cards.fetchNextPage()}
                >
                  Load more references
                </Button>
              )}
            </>
          )}
        </>
      )}
      {stage === 'direction' &&
        (direction.isLoading ? (
          <p role="status">Loading selected direction…</p>
        ) : direction.isError ? (
          <p role="alert">
            Could not load the selected direction.{' '}
            <button
              className="auth-link"
              onClick={() => void direction.refetch()}
            >
              Retry
            </button>
          </p>
        ) : direction.data?.length ? (
          <div className="grid items-start gap-4 md:grid-cols-2 xl:grid-cols-3">
            {direction.data.map((card) => (
              <ReferenceCardView
                key={card.id}
                card={card}
                projectId={projectId}
                canManage={Boolean(query.data?.canManage)}
                canContribute={false}
                shared
                onUploading={() => {}}
              />
            ))}
          </div>
        ) : (
          <p className={panel}>
            No references have been selected for brief agreement. Project
            leadership can choose Include in brief on shared references.
          </p>
        ))}
      {action.error && (
        <p role="alert" className="text-sm text-red-700">
          {action.error}
        </p>
      )}
    </div>
  )
}
