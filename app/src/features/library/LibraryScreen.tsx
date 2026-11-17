import { useContext, useEffect, useState } from 'react'
import { useParams, useSearchParams } from 'react-router'
import { ArrowLeft, FilePlus2, Upload, StickyNote } from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from '@/ui/dialog'
import { Button } from '@/features/planning/PlanningButton'
import { panel, help } from '@/features/planning/queries'
import FilePreview from '@/features/planning/FilePreview'
import {
  useLibrary,
  useLibraryItems,
  type LibraryItem,
  type LibraryView,
} from './queries'
import {
  LibrarySaveGuard,
  LibrarySaving,
  LibraryUnsaved,
} from './LibraryActivity'
import { CollectionForm, ItemForm } from './LibraryEditors'
import { ReviewControls, statusLabel } from './LibraryReviewControls'
import { LibraryCatalog, kindLabel } from './LibraryCatalog'
import { LibraryUpload } from './LibraryUpload'
import { libraryLayout, type LibraryLayout } from './libraryModel'
import {
  LibrarySetupGuide,
  LibrarySetupFooter,
  LibraryPublicationStatus,
} from './LibrarySetup'
import { toast } from 'sonner'
export function Component() {
  return (
    <LibrarySaveGuard>
      <LibraryPage />
    </LibrarySaveGuard>
  )
}
type Editor = {
  type: 'create' | 'settings' | 'item' | 'upload'
  item?: LibraryItem
  intent?: 'link' | 'note'
} | null
function LibraryPage() {
  const { org_id: org = '' } = useParams(),
    [params, setParams] = useSearchParams(),
    query = useLibrary(org)
  const saving = useContext(LibrarySaving),
    unsaved = useContext(LibraryUnsaved),
    [editor, setEditor] = useState<Editor>(null)
  const all = query.data?.collections ?? [],
    id = params.get('collection') ?? '',
    collection = all.find((c) => c.id === id)
  const view = (
    ['published', 'contributions', 'review'].includes(params.get('view') ?? '')
      ? params.get('view')
      : 'published'
  ) as LibraryView
  const published = Boolean(
    collection?.published &&
      (params.get('mode') === 'published' || !collection.canSeeDraft),
  )
  const draft = Boolean(collection?.canSeeDraft && !published),
    items = useLibraryItems(collection?.id ?? '', draft)
  const display = published ? collection?.published : collection,
    canEdit = Boolean(draft && collection?.canEdit),
    admin = Boolean(query.data?.canManage)
  const guided = Boolean(params.get('setup') && draft)
  const setupStep = params.get('setup') === 'review' ? 'review' : 'content'
  const contentReady = !items.isLoading && !items.isError && Boolean(items.data)
  const toContributions = () => {
    update({
      collection: null,
      item: null,
      mode: null,
      setup: null,
      view: 'contributions',
      q: null,
      kind: null,
      tag: null,
    })
    setEditor(null)
    window.scrollTo(0, 0)
  }
  const finishDraft = () => {
    toContributions()
    toast.success('Draft saved. Continue building it from Contributions.')
  }
  const goSetup = (step: 'content' | 'review') => {
    update({ setup: step })
    window.scrollTo(0, 0)
  }
  const update = (values: Record<string, string | null>, replace = false) => {
    const next = new URLSearchParams(params)
    for (const [key, value] of Object.entries(values)) {
      if (value) next.set(key, value)
      else next.delete(key)
    }
    setParams(next, { preventScrollReset: true, replace })
  }
  const choose = (
    nextId: string,
    item?: string,
    mode?: string,
    setup?: 'content' | 'review',
  ) => {
    update({
      collection: nextId || null,
      setup: setup ?? null,
      item: item ?? null,
      mode: mode ?? (view === 'published' ? 'published' : 'working'),
      ...(mode === 'working'
        ? { view: 'contributions', q: null, kind: null, tag: null }
        : {}),
    })
    setEditor(null)
    window.scrollTo(0, 0)
  }
  const close = () => {
    if (saving) return
    if (unsaved && !window.confirm('Discard unsaved library changes?')) return
    setEditor(null)
  }
  if (query.isLoading)
    return (
      <p role="status" className="p-6">
        Loading library…
      </p>
    )
  if (query.isError)
    return (
      <div className="p-6">
        <h1 className="text-2xl">Library unavailable</h1>
        <p role="alert">
          This library is for active organisation members. Check your
          organisation access or try again.
        </p>
        <button className="auth-link" onClick={() => void query.refetch()}>
          Retry
        </button>
      </div>
    )
  const back = () => {
    update({ collection: null, item: null, mode: null, setup: null })
    setEditor(null)
    window.scrollTo(0, 0)
  }
  const editorTitle =
    editor?.type === 'create'
      ? 'Create a collection'
      : editor?.type === 'settings'
        ? 'Collection settings'
        : editor?.type === 'upload'
          ? 'Add files'
          : editor?.item
            ? 'Edit item'
            : editor?.intent === 'note'
              ? 'Write a note'
              : 'Add a link'
  return (
    <div className="lign-warm mx-auto max-w-6xl space-y-5 p-5 md:p-7">
      {!id ? (
        <LibraryCatalog
          key={view}
          org={org}
          collections={all}
          admin={admin}
          view={view}
          setView={(v) => update({ view: v, tag: null })}
          open={choose}
          resume={(resumeId) =>
            choose(resumeId, undefined, 'working', 'content')
          }
          resumeDrafts={() =>
            update({ view: 'contributions', q: null, kind: null, tag: null })
          }
          onNew={() => setEditor({ type: 'create' })}
          initialSearch={params.get('q') ?? ''}
          initialKind={params.get('kind') ?? 'all'}
          initialTag={params.get('tag') ?? ''}
          onFilters={(q, kind, tag) =>
            update({ q, kind: kind === 'all' ? null : kind, tag }, true)
          }
        />
      ) : !collection || !display ? (
        <section className={panel}>
          <button className="auth-link" onClick={back}>
            ← Back to Library
          </button>
          <h1 className="mt-4 text-xl font-semibold">Collection unavailable</h1>
          <p className={'mt-2 ' + help}>
            It may have been archived or you may not have access to this
            version.
          </p>
        </section>
      ) : (
        <>
          <button
            className="auth-link inline-flex items-center gap-2 text-sm"
            onClick={back}
          >
            <ArrowLeft size={16} aria-hidden="true" />
            Back to Library
          </button>
          <header className="space-y-3">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="text-xs uppercase tracking-widest text-[#786b60]">
                  {kindLabel(display.kind)}
                </p>
                <h1 className="auth-display mt-2 break-words text-3xl">
                  {display.title}
                </h1>
              </div>
              {canEdit && (
                <button
                  className="auth-link text-sm"
                  onClick={() => setEditor({ type: 'settings' })}
                >
                  Collection settings
                </button>
              )}
            </div>
            {display.description && (
              <p className="max-w-3xl whitespace-pre-wrap break-words text-sm text-[#786b60]">
                {display.description}
              </p>
            )}
            <div className="flex flex-wrap items-center gap-2">
              <span className="rounded-full bg-[#eee8df] px-3 py-1 text-xs font-semibold">
                {published ? 'Published' : statusLabel[collection.status]}
              </span>
              <span className={help}>By {collection.authorName}</span>
              {display.tags?.map((tag) => (
                <span
                  key={tag}
                  className="rounded-full border border-[#e5ddd3] px-2 py-1 text-xs"
                >
                  {tag}
                </span>
              ))}
            </div>
            {collection.canSeeDraft && collection.published && (
              <label className="block max-w-sm text-sm">
                Collection view
                <select
                  aria-label="Collection view"
                  className="auth-field mt-1 w-full"
                  value={published ? 'published' : 'working'}
                  onChange={(e) =>
                    update({ mode: e.target.value, item: null, setup: null })
                  }
                >
                  <option value="published">
                    Published revision {collection.published.revision}
                  </option>
                  <option value="working">
                    {collection.status === 'published'
                      ? 'Manage approved collection'
                      : 'Working submission'}
                  </option>
                </select>
              </label>
            )}
            <p className={help}>
              {published || collection.status === 'published'
                ? 'Use this approved collection from a project’s Reference boards → Add from organisation library. Project copies and client feedback stay independent.'
                : collection.status === 'in_review'
                  ? 'Submitted for review. Content is locked until it is withdrawn or changes are requested.'
                  : 'Working collection. Add content, check the details, then submit it for approval below.'}
            </p>
          </header>
          {guided && collection.canEdit ? (
            <LibrarySetupGuide
              collection={collection}
              items={items.data ?? []}
              step={setupStep}
              ready={contentReady}
              editDetails={() => setEditor({ type: 'settings' })}
              setStep={goSetup}
            />
          ) : guided &&
            (collection.status === 'in_review' ||
              collection.status === 'published') ? (
            <LibraryPublicationStatus
              collection={collection}
              org={org}
              toContributions={toContributions}
              toPublished={() => {
                update({
                  collection: null,
                  item: null,
                  mode: null,
                  setup: null,
                  view: 'published',
                  q: null,
                  kind: null,
                  tag: null,
                })
                window.scrollTo(0, 0)
              }}
            />
          ) : canEdit ? (
            <section className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-[#e5ddd3] bg-[#fffdf9] p-4">
              <div>
                <p className="text-sm font-semibold">
                  Continue building your collection
                </p>
                <p className={help}>
                  Add useful content, check the details, then submit it for
                  approval.
                </p>
              </div>
              <Button onClick={() => goSetup('content')}>
                Resume collection
              </Button>
            </section>
          ) : null}
          <LibraryContents
            key={`${id}-${published}-${guided ? setupStep : 'detail'}`}
            items={items.data ?? []}
            loading={items.isLoading}
            error={items.isError}
            retry={() => void items.refetch()}
            canEdit={canEdit && (!guided || setupStep === 'content')}
            focusedId={params.get('item') ?? ''}
            layout={libraryLayout(params.get('layout'))}
            setLayout={(layout) => update({ layout }, true)}
            edit={(item) => setEditor({ type: 'item', item })}
            upload={() => setEditor({ type: 'upload' })}
            add={(intent) => setEditor({ type: 'item', intent })}
          />
          {guided && collection.canEdit && (
            <LibrarySetupFooter
              step={setupStep}
              ready={contentReady}
              hasItems={Boolean(items.data?.length)}
              finishLater={finishDraft}
              setStep={goSetup}
            />
          )}
          {draft &&
            (!guided ||
              (setupStep === 'review' && contentReady) ||
              !collection.canEdit) && (
              <ReviewControls
                key={id}
                org={org}
                collection={collection}
                admin={admin}
                onArchived={back}
              />
            )}
        </>
      )}
      <Dialog
        open={Boolean(editor)}
        onOpenChange={(open) => {
          if (!open) close()
        }}
      >
        <DialogContent className="lign-warm max-h-[90dvh] max-w-[min(36rem,calc(100vw-2rem))] overflow-y-auto rounded-xl border-[#e5ddd3] bg-[#fffdf9]">
          <DialogTitle>{editorTitle}</DialogTitle>
          <DialogDescription>
            {editor?.type === 'create'
              ? 'Start with one useful topic. Save a draft now or continue to add your own content.'
              : editor?.type === 'upload'
                ? 'Add several files to this collection in one step.'
                : 'Saved changes stay in the working collection until owner/admin approval.'}
          </DialogDescription>
          {editor?.type === 'create' ? (
            <CollectionForm
              org={org}
              onSaved={(newId, continueSetup) => {
                if (continueSetup)
                  choose(newId, undefined, 'working', 'content')
                else {
                  finishDraft()
                }
              }}
            />
          ) : editor?.type === 'settings' && collection ? (
            <CollectionForm
              key={collection.id}
              org={org}
              collection={collection}
              onSaved={(savedId) => (savedId ? setEditor(null) : back())}
            />
          ) : editor?.type === 'upload' && collection ? (
            <LibraryUpload
              org={org}
              collectionId={collection.id}
              onDone={() => setEditor(null)}
            />
          ) : editor?.type === 'item' && collection ? (
            <ItemForm
              key={editor.item?.id ?? 'new'}
              org={org}
              collectionId={collection.id}
              item={editor.item}
              intent={editor.intent}
              onSaved={() => setEditor(null)}
            />
          ) : null}
          <button
            className="auth-link justify-self-start text-sm"
            disabled={saving}
            onClick={close}
          >
            Cancel
          </button>
        </DialogContent>
      </Dialog>
    </div>
  )
}
function LibraryContents({
  items,
  loading,
  error,
  retry,
  canEdit,
  focusedId,
  layout,
  setLayout,
  edit,
  upload,
  add,
}: {
  items: LibraryItem[]
  loading: boolean
  error: boolean
  retry: () => void
  canEdit: boolean
  focusedId: string
  layout: LibraryLayout
  setLayout: (layout: LibraryLayout) => void
  edit: (item: LibraryItem) => void
  upload: () => void
  add: (intent: 'link' | 'note') => void
}) {
  const [search, setSearch] = useState(''),
    [format, setFormat] = useState('all')
  const visible = items.filter(
    (item) =>
      (!search ||
        (
          item.title +
          ' ' +
          item.description +
          ' ' +
          (item.url ?? '') +
          ' ' +
          (item.file?.name ?? '')
        )
          .toLowerCase()
          .includes(search.toLowerCase())) &&
      (format === 'all' ||
        (format === 'images'
          ? item.file?.mime.startsWith('image/')
          : format === 'documents'
            ? Boolean(item.file && !item.file.mime.startsWith('image/'))
            : format === 'links'
              ? Boolean(item.url)
              : !item.file && !item.url)),
  )
  useEffect(() => {
    if (!focusedId || loading) return
    const el = document.getElementById(`library-item-${focusedId}`)
    if (el) {
      el.scrollIntoView({ block: 'center' })
      el.focus({ preventScroll: true })
    }
  }, [focusedId, loading, items])
  return (
    <section className="space-y-4" aria-label="Collection content">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold">
            Collection content{' '}
            <span className="text-[#786b60]">({items.length})</span>
          </h2>
          <p className={help}>
            Files, source links and notes in this collection.
          </p>
        </div>
        {canEdit && (
          <div className="flex flex-wrap gap-2">
            <Button onClick={upload}>
              <Upload size={16} aria-hidden="true" />
              Add files
            </Button>
            <Button variant="secondary" onClick={() => add('link')}>
              <FilePlus2 size={16} aria-hidden="true" />
              Add a link
            </Button>
            <Button variant="secondary" onClick={() => add('note')}>
              <StickyNote size={16} aria-hidden="true" />
              Write a note
            </Button>
          </div>
        )}
      </div>
      {items.length > 0 && (
        <div className="flex flex-wrap items-end gap-3">
          <label className="min-w-0 flex-1 basis-60 text-sm">
            Find in this collection
            <input
              className="auth-field mt-1 w-full"
              type="search"
              value={search}
              placeholder="Item title, filename, details or link"
              onChange={(e) => setSearch(e.target.value)}
            />
          </label>
          <label className="text-sm">
            Content format
            <select
              aria-label="Content format"
              className="auth-field mt-1 w-full"
              value={format}
              onChange={(e) => setFormat(e.target.value)}
            >
              <option value="all">All formats</option>
              <option value="images">Images</option>
              <option value="documents">Documents</option>
              <option value="links">Links</option>
              <option value="notes">Notes</option>
            </select>
          </label>
          <div
            className="flex flex-wrap gap-1 pb-1"
            aria-label="Content layout"
          >
            {(['grid', 'list', 'moodboard'] as const).map((value) => (
              <button
                key={value}
                aria-pressed={layout === value}
                className={`rounded-lg px-3 py-2 text-sm ${layout === value ? 'bg-[#3a332d] text-white' : 'border border-[#e5ddd3]'}`}
                onClick={() => setLayout(value)}
              >
                {value === 'grid'
                  ? 'Grid'
                  : value === 'list'
                    ? 'List'
                    : 'Mood board'}
              </button>
            ))}
          </div>
        </div>
      )}
      {layout === 'moodboard' && (
        <p className={help}>
          A visual arrangement of this collection’s items. Use it for any
          category; files, links and notes stay together.
        </p>
      )}
      {loading ? (
        <p role="status">Loading content…</p>
      ) : error ? (
        <p role="alert">
          Could not load content.{' '}
          <button className="auth-link" onClick={retry}>
            Retry
          </button>
        </p>
      ) : !items.length ? (
        <div className={`${panel} py-10 text-center`}>
          <h3 className="font-semibold">This collection is empty</h3>
          <p className={'mt-2 ' + help}>
            {canEdit
              ? 'Add files or a source link to get started. You can edit individual titles and details before submitting for approval.'
              : 'No items are available in this version.'}
          </p>
          {canEdit && (
            <Button className="mt-4" onClick={upload}>
              Add your first files
            </Button>
          )}
        </div>
      ) : !visible.length ? (
        <p className={panel}>
          No items match.{' '}
          <button
            className="auth-link"
            onClick={() => {
              setSearch('')
              setFormat('all')
            }}
          >
            Clear filters
          </button>
        </p>
      ) : (
        <div
          className={
            layout === 'grid'
              ? 'grid items-start gap-4 md:grid-cols-2 xl:grid-cols-3'
              : layout === 'moodboard'
                ? 'columns-1 gap-4 sm:columns-2 xl:columns-3'
                : 'space-y-3'
          }
        >
          {visible.map((item) => (
            <article
              key={item.id}
              id={`library-item-${item.id}`}
              tabIndex={-1}
              className={`${panel} min-w-0 ${layout === 'moodboard' ? 'mb-4 break-inside-avoid' : ''} ${item.id === focusedId ? 'ring-2 ring-[#b64d24]' : ''}`}
            >
              {layout === 'moodboard' &&
                item.file?.mime.startsWith('image/') && (
                  <FilePreview file={item.file} />
                )}
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <h3 className="break-words text-base font-semibold">
                    {item.title}
                  </h3>
                  <p className="mt-1 text-xs text-[#786b60]">
                    {item.file
                      ? item.file.mime.startsWith('image/')
                        ? 'Image'
                        : 'Document'
                      : item.url
                        ? 'Link'
                        : 'Note'}
                  </p>
                </div>
                {canEdit && (
                  <button
                    className="auth-link shrink-0 text-sm"
                    onClick={() => edit(item)}
                  >
                    Edit item
                  </button>
                )}
              </div>
              {item.description && (
                <p className="whitespace-pre-wrap break-words text-sm">
                  {item.description}
                </p>
              )}
              {item.file &&
                !(
                  layout === 'moodboard' && item.file.mime.startsWith('image/')
                ) &&
                (layout !== 'list' ? (
                  <FilePreview file={item.file} />
                ) : (
                  <details>
                    <summary className="auth-link cursor-pointer break-all text-sm">
                      Preview & download · {item.file.name}
                    </summary>
                    <FilePreview file={item.file} />
                  </details>
                ))}{' '}
              {item.url && (
                <a
                  className="auth-link block break-all text-sm"
                  href={item.url}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {item.url} ↗
                </a>
              )}
            </article>
          ))}
        </div>
      )}
    </section>
  )
}
