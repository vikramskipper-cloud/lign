import { useEffect, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  BookOpen,
  FileImage,
  Layers,
  LayoutTemplate,
  Palette,
  Package,
  Search,
} from 'lucide-react'
import { useSession } from '@/auth/SessionProvider'
import { supabase } from '@/lib/supabase'
import { Button } from '@/features/planning/PlanningButton'
import { help, panel, type PlanningFile } from '@/features/planning/queries'
import { useLibraryCatalog, type Collection, type LibraryView } from './queries'
import { statusLabel } from './LibraryReviewControls'
import {
  libraryCategories,
  libraryCategory,
  libraryCategoryLabel,
} from './libraryModel'
const categoryIcons = {
  inspiration: Palette,
  materials_products: Package,
  details_solutions: FileImage,
  templates_guides: LayoutTemplate,
}
export const libraryKinds = [
  { id: 'all', label: 'All categories', icon: Layers, description: '' },
  ...libraryCategories.map((c) => ({ ...c, icon: categoryIcons[c.id] })),
]
export const kindLabel = libraryCategoryLabel
export function LibraryCover({
  file,
  kind,
}: {
  file: PlanningFile | null
  kind: string
}) {
  const { user } = useSession(),
    url = useQuery({
      queryKey: [
        'planning-image',
        user?.id,
        file?.bucket ?? 'organization-library',
        file?.path,
      ],
      enabled: Boolean(user && file),
      staleTime: 45000,
      refetchInterval: 50000,
      queryFn: async () => {
        const result = await supabase.storage
          .from(file?.bucket ?? 'organization-library')
          .createSignedUrl(file!.path, 60)
        if (result.error) throw result.error
        return result.data.signedUrl
      },
    })
  const Icon =
    libraryKinds.find((k) => k.id === libraryCategory(kind))?.icon ?? BookOpen
  return (
    <div className="flex h-40 items-center justify-center overflow-hidden rounded-t-xl bg-[#eee8df]">
      {url.data ? (
        <img
          src={url.data}
          alt=""
          loading="lazy"
          className="h-full w-full object-cover"
        />
      ) : (
        <Icon aria-hidden="true" size={36} className="text-[#9a8a79]" />
      )}
    </div>
  )
}
export function LibraryCatalog({
  org,
  collections,
  admin,
  view,
  setView,
  open,
  resume,
  resumeDrafts,
  onNew,
  initialSearch,
  initialKind,
  initialTag,
  onFilters,
}: {
  org: string
  collections: Collection[]
  admin: boolean
  view: LibraryView
  setView: (view: LibraryView) => void
  open: (id: string, item?: string) => void
  resume: (id: string) => void
  resumeDrafts: () => void
  onNew: () => void
  initialSearch: string
  initialKind: string
  initialTag: string
  onFilters: (search: string, kind: string, tag: string) => void
}) {
  const [search, setSearch] = useState(initialSearch),
    [debounced, setDebounced] = useState(initialSearch),
    [kind, setKind] = useState(
      initialKind === 'all' ? 'all' : libraryCategory(initialKind),
    ),
    [tag, setTag] = useState(initialTag),
    [stage, setStage] = useState('all'),
    [offset, setOffset] = useState(0)
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(search.trim()), 250)
    return () => clearTimeout(timer)
  }, [search])
  const query = useLibraryCatalog(org, {
      view,
      search: debounced,
      kind,
      tag,
      stage,
      offset,
    }),
    data = query.data
  const changeView = (next: LibraryView) => {
    setView(next)
    setStage('all')
    setOffset(0)
    setTag('')
  }
  const clear = () => {
    setSearch('')
    setDebounced('')
    setKind('all')
    setTag('')
    setStage('all')
    setOffset(0)
    onFilters('', 'all', '')
  }
  const views: { id: LibraryView; label: string; count: number }[] = [
    {
      id: 'published',
      label: 'Published library',
      count: collections.filter((c) => c.published).length,
    },
    {
      id: 'contributions',
      label: admin ? 'All contributions' : 'My contributions',
      count: collections.filter((c) => c.canSeeDraft).length,
    },
    ...(admin
      ? [
          {
            id: 'review' as const,
            label: 'Review queue',
            count: collections.filter((c) => c.canReview).length,
          },
        ]
      : []),
  ]
  return (
    <>
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-xs uppercase tracking-widest text-[#786b60]">
            Shared across your organisation
          </p>
          <h1 className="auth-display mt-2 text-3xl">Library</h1>
          <p className="mt-2 max-w-2xl text-sm text-[#786b60]">
            Your studio’s templates, inspiration and design knowledge, organised
            in reusable collections. Each collection groups related files, links
            and notes for future projects.
          </p>
        </div>
        <Button onClick={onNew}>+ New collection</Button>
      </header>
      <nav
        aria-label="Library views"
        className="flex flex-wrap gap-2 border-b border-[#e5ddd3] pb-3"
      >
        {views.map((v) => (
          <button
            key={v.id}
            aria-pressed={view === v.id}
            className={`rounded-lg px-4 py-2 text-sm ${view === v.id ? 'bg-[#3a332d] text-white' : 'bg-white text-[#786b60] hover:bg-[#eee8df]'}`}
            onClick={() => changeView(v.id)}
          >
            {v.label} <span className="ml-1 opacity-75">{v.count}</span>
          </button>
        ))}
      </nav>
      <p className={help}>
        {view === 'published'
          ? 'Approved collections ready to use in any project. Open a collection to browse its files, links and notes.'
          : view === 'review'
            ? 'Check submitted content, then publish it for everyone or request changes.'
            : admin
              ? 'Manage contributions from across the organisation. Drafts remain private to authors and organisation admins.'
              : 'Create and manage your contributions. Submit a finished collection for owner/admin approval.'}
      </p>
      {view === 'published' && collections.some((c) => c.canEdit) && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-[#f3eee6] p-4">
          <div>
            <p className="text-sm font-semibold">Continue where you left off</p>
            <p className={help}>
              {collections.filter((c) => c.canEdit).length} working collections
              can be finished and submitted for approval.
            </p>
          </div>
          <Button variant="secondary" onClick={resumeDrafts}>
            View unfinished collections
          </Button>
        </div>
      )}
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 xl:grid-cols-5">
        {libraryKinds.map((k) => (
          <button
            key={k.id}
            aria-pressed={kind === k.id}
            className={`flex items-center gap-3 rounded-xl border p-3 text-left ${kind === k.id ? 'border-[#b64d24] bg-[#fff3e9]' : 'border-[#e5ddd3] bg-[#fffdf9] hover:bg-[#f3eee6]'}`}
            onClick={() => {
              setKind(k.id)
              setOffset(0)
              onFilters(search, k.id, tag)
            }}
          >
            <k.icon aria-hidden="true" size={20} />
            <span>
              <span className="block text-sm font-semibold">{k.label}</span>
              {k.description && (
                <span className="mt-1 hidden text-xs text-[#786b60] xl:block">
                  {k.description}
                </span>
              )}
            </span>
          </button>
        ))}
      </div>
      <div className="flex flex-wrap items-end gap-3">
        <label className="min-w-0 flex-1 basis-72 text-sm">
          <span className="flex items-center gap-2">
            <Search size={15} aria-hidden="true" />
            Search the library
          </span>
          <input
            type="search"
            maxLength={160}
            className="auth-field mt-1 w-full"
            placeholder="Collection, item, filename, tag or source link…"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value)
              setOffset(0)
              onFilters(e.target.value, kind, tag)
            }}
          />
        </label>
        <label className="min-w-40 text-sm">
          Tag
          <select
            aria-label="Tag"
            className="auth-field mt-1 w-full"
            value={tag}
            onChange={(e) => {
              setTag(e.target.value)
              setOffset(0)
              onFilters(search, kind, e.target.value)
            }}
          >
            <option value="">All tags</option>
            {Array.from(
              new Set([...(data?.tags ?? []), ...(tag ? [tag] : [])]),
            ).map((t) => (
              <option key={t}>{t}</option>
            ))}
          </select>
        </label>
        {view === 'contributions' && (
          <label className="min-w-40 text-sm">
            Status
            <select
              aria-label="Status"
              className="auth-field mt-1 w-full"
              value={stage}
              onChange={(e) => {
                setStage(e.target.value)
                setOffset(0)
              }}
            >
              <option value="all">All statuses</option>
              {Object.entries(statusLabel).map(([id, label]) => (
                <option key={id} value={id}>
                  {label}
                </option>
              ))}
            </select>
          </label>
        )}
        {(search || kind !== 'all' || tag || stage !== 'all') && (
          <button className="auth-link pb-2 text-sm" onClick={clear}>
            Clear filters
          </button>
        )}
      </div>
      {query.isLoading || search.trim() !== debounced ? (
        <p role="status" className={panel}>
          Finding collections…
        </p>
      ) : query.isError ? (
        <div role="alert" className={panel}>
          Could not load the library.{' '}
          <button className="auth-link" onClick={() => void query.refetch()}>
            Retry
          </button>
        </div>
      ) : (
        <>
          <p className={help} role="status">
            {data?.total ?? 0}{' '}
            {(data?.total ?? 0) === 1 ? 'collection' : 'collections'}
            {search ? ` matching “${search}”` : ''}
            {tag ? ` · ${tag}` : ''}
          </p>
          {!data?.total ? (
            <section className={`${panel} py-12 text-center`}>
              <BookOpen
                className="mx-auto text-[#9a8a79]"
                aria-hidden="true"
                size={32}
              />
              <h2 className="mt-3 text-lg font-semibold">
                {search || kind !== 'all' || tag || stage !== 'all'
                  ? 'No matching collections'
                  : view === 'review'
                    ? 'You’re all caught up'
                    : view === 'published'
                      ? 'Build your shared library'
                      : 'Your first collection starts here'}
              </h2>
              <p className="mx-auto mt-2 max-w-md text-sm text-[#786b60]">
                {search || kind !== 'all' || tag || stage !== 'all'
                  ? 'Try a different search, category or tag.'
                  : view === 'review'
                    ? 'Submitted collections will appear here for review.'
                    : view === 'published'
                      ? 'Create a collection, add files or links, then submit it for approval. Published content will be available to every workspace.'
                      : 'Group related files, links and notes into a collection. Choose a category and add tags so your team can find it later.'}
              </p>
              {view !== 'review' && (
                <Button className="mt-4" onClick={onNew}>
                  Create a collection
                </Button>
              )}
            </section>
          ) : (
            <div className="grid items-start gap-5 sm:grid-cols-2 xl:grid-cols-3">
              {data.collections.map((c) => (
                <article
                  key={c.id}
                  className="min-w-0 overflow-hidden rounded-xl border border-[#e5ddd3] bg-[#fffdf9]"
                >
                  <button
                    className="block w-full text-left hover:bg-[#f8f3eb]"
                    onClick={() => open(c.id)}
                    aria-label={`Open ${c.title}`}
                  >
                    <LibraryCover file={c.cover} kind={c.kind} />
                    <div className="space-y-2 p-4">
                      <div className="flex flex-wrap justify-between gap-2 text-xs text-[#786b60]">
                        <span>{kindLabel(c.kind)}</span>
                        <span>
                          {view === 'published'
                            ? 'Published'
                            : statusLabel[c.status]}
                        </span>
                      </div>
                      <h2 className="break-words text-lg font-semibold">
                        {c.title}
                      </h2>
                      <p className="line-clamp-2 text-sm text-[#786b60]">
                        {c.description ||
                          'Files, links and notes for your team.'}
                      </p>
                      <p className="text-xs text-[#786b60]">
                        {c.itemCount} {c.itemCount === 1 ? 'item' : 'items'} ·{' '}
                        {c.authorName || 'Organisation collection'}
                      </p>
                    </div>
                  </button>
                  {view === 'contributions' && c.canEdit && (
                    <div className="px-4 pb-4">
                      <Button variant="secondary" onClick={() => resume(c.id)}>
                        Resume collection
                      </Button>
                    </div>
                  )}
                  {Boolean(c.tags?.length) && (
                    <div className="flex flex-wrap gap-1 px-4 pb-4">
                      {c.tags?.map((t) => (
                        <button
                          key={t}
                          className="rounded-full bg-[#eee8df] px-2 py-1 text-xs hover:bg-[#dfd4c5]"
                          onClick={() => {
                            setTag(t)
                            setOffset(0)
                            onFilters(search, kind, t)
                          }}
                        >
                          {t}
                        </button>
                      ))}
                    </div>
                  )}
                  {c.matchCount > 0 && (
                    <div className="border-t border-[#e5ddd3] px-4 py-3">
                      <p className="mb-1 text-xs text-[#786b60]">
                        {c.matchCount} matching{' '}
                        {c.matchCount === 1 ? 'item' : 'items'}
                      </p>
                      {c.matches.map((m) => (
                        <button
                          key={m.id}
                          className="auth-link block w-full truncate py-1 text-left text-sm"
                          onClick={() => open(c.id, m.id)}
                        >
                          {m.title}
                          {m.fileName ? ` · ${m.fileName}` : ''}
                        </button>
                      ))}
                    </div>
                  )}
                </article>
              ))}
            </div>
          )}
          {(offset > 0 || (data?.total ?? 0) > 24) && (
            <div className="flex items-center justify-center gap-4">
              <Button
                variant="secondary"
                disabled={!offset}
                onClick={() => setOffset(Math.max(0, offset - 24))}
              >
                Previous
              </Button>
              <span className={help}>
                {offset + 1}–{Math.min(offset + 24, data?.total ?? 0)} of{' '}
                {data?.total}
              </span>
              <Button
                variant="secondary"
                disabled={offset + 24 >= (data?.total ?? 0)}
                onClick={() => setOffset(offset + 24)}
              >
                Next
              </Button>
            </div>
          )}
        </>
      )}
    </>
  )
}
