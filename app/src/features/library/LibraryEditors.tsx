import { useState } from 'react'
import { Button } from '@/features/planning/PlanningButton'
import {
  planningRpc,
  help,
  planningFileAccept,
} from '@/features/planning/queries'
import {
  useLibraryAction,
  uploadLibrary,
  type Collection,
  type LibraryItem,
} from './queries'
import { useLibraryDirty } from './LibraryActivity'
import { libraryCategories, collectionExamples } from './libraryModel'
import { CollectionExample, LibrarySetupProgress } from './LibrarySetup'
export function CollectionForm({
  org,
  collection,
  onSaved,
}: {
  org: string
  collection?: Collection
  onSaved: (id: string, continueSetup?: boolean) => void
}) {
  const [title, setTitle] = useState(collection?.title ?? ''),
    [kind, setKind] = useState(collection?.kind ?? 'inspiration'),
    [description, setDescription] = useState(collection?.description ?? ''),
    [tags, setTags] = useState(collection?.tags?.join(', ') ?? ''),
    [version, setVersion] = useState(collection?.edit_version ?? 0),
    action = useLibraryAction()
  const [initial] = useState(() =>
    JSON.stringify([title, kind, description, tags]),
  )
  const clearDirty = useLibraryDirty(
    JSON.stringify([title, kind, description, tags]) !== initial,
  )
  return (
    <form
      className="space-y-3"
      onSubmit={async (e) => {
        e.preventDefault()
        const continueSetup =
          (e.nativeEvent as SubmitEvent).submitter?.getAttribute('value') !==
          'draft'
        const r = await action.run(() =>
          planningRpc<string>('save_library_draft', {
            p_organization_id: org,
            p_title: title,
            p_kind: kind,
            p_description: description,
            p_id: collection?.id ?? null,
            p_expected_version: version,
            p_tags: tags
              .split(',')
              .map((t) => t.trim())
              .filter(Boolean),
          }),
        )
        if (r.ok) {
          clearDirty()
          if (collection) setVersion((v) => v + 1)
          if (!collection) {
            setTitle('')
            setDescription('')
            setTags('')
          }
          onSaved(r.data, continueSetup)
        }
      }}
    >
      {!collection && (
        <>
          <LibrarySetupProgress step={1} />
          <p className="text-sm text-[#786b60]">
            A collection groups related files, links and notes your team can
            reuse across projects.
          </p>
        </>
      )}
      <label className="block text-sm">
        Collection title
        <input
          className="auth-field mt-1 w-full"
          required
          maxLength={160}
          placeholder={collectionExamples[kind].name}
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          disabled={action.busy}
        />
      </label>
      <label className="block text-sm">
        Collection category
        <select
          aria-label="Collection category"
          className="auth-field mt-1 w-full"
          value={kind}
          onChange={(e) => setKind(e.target.value as Collection['kind'])}
          disabled={action.busy}
        >
          {libraryCategories.map((category) => (
            <option key={category.id} value={category.id}>
              {category.label}
            </option>
          ))}
        </select>
        <span className={help}>
          {
            libraryCategories.find((category) => category.id === kind)
              ?.description
          }
          . Use tags for style, discipline or application.
        </span>
      </label>
      {!collection && (
        <CollectionExample kind={kind} onUseName={setTitle} compact />
      )}
      <details open={collection ? true : undefined} className="space-y-3">
        <summary className="auth-link cursor-pointer text-sm">
          Description and tags (optional)
        </summary>
        <label className="block text-sm">
          Description (optional)
          <textarea
            aria-label="Description"
            className="auth-field mt-1 w-full"
            maxLength={3000}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            disabled={action.busy}
          />
        </label>
        <label className="block text-sm">
          Tags (optional)
          <input
            aria-label="Tags"
            className="auth-field mt-1 w-full"
            value={tags}
            maxLength={500}
            disabled={action.busy}
            placeholder="e.g. timber, residential, minimal"
            onChange={(e) => setTags(e.target.value)}
          />
          <span className={help}>Comma-separated; up to 12 tags.</span>
        </label>
      </details>
      {collection && collection.edit_version !== version && (
        <p role="alert" className="text-sm text-[#8a4a17]">
          Saved collection details have changed. Your edits are preserved. Close
          and reopen settings to load the latest version.
        </p>
      )}
      <div
        className={
          collection
            ? 'flex flex-wrap gap-2'
            : 'sticky bottom-0 z-10 flex flex-wrap gap-2 border-t border-[#e5ddd3] bg-[#fffdf9] py-3'
        }
      >
        <Button
          className={!collection ? 'w-full sm:w-auto' : undefined}
          disabled={
            action.busy ||
            Boolean(collection && collection.edit_version !== version)
          }
        >
          {action.busy
            ? 'Saving…'
            : collection
              ? 'Save collection'
              : 'Continue to add content'}
        </Button>
        {!collection && (
          <Button
            type="submit"
            variant="secondary"
            className="w-full sm:w-auto"
            value="draft"
            disabled={action.busy}
          >
            Save draft & exit
          </Button>
        )}
      </div>
      {collection && !collection.published && (
        <button
          type="button"
          className="auth-link ml-3 text-sm"
          disabled={action.busy}
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
            if (r.ok) {
              clearDirty()
              onSaved('')
            }
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
    </form>
  )
}
export function ItemForm({
  org,
  collectionId,
  item,
  intent,
  onSaved,
}: {
  org: string
  collectionId: string
  item?: LibraryItem
  intent?: 'link' | 'note'
  onSaved: () => void
}) {
  const [title, setTitle] = useState(item?.title ?? ''),
    [description, setDescription] = useState(item?.description ?? ''),
    [url, setUrl] = useState(item?.url ?? ''),
    [file, setFile] = useState<File | null>(null),
    [remove, setRemove] = useState(false),
    [version] = useState(item?.edit_version ?? 0),
    action = useLibraryAction()
  const [initial] = useState(() => JSON.stringify([title, description, url]))
  const clearDirty = useLibraryDirty(
    Boolean(file || remove) ||
      JSON.stringify([title, description, url]) !== initial,
  )
  const save = (archive = false) =>
    action.run(async () => {
      const fileId =
        !archive && file
          ? await uploadLibrary(org, file)
          : remove
            ? null
            : (item?.file_id ?? null)
      return planningRpc('save_library_item', {
        p_collection_id: collectionId,
        p_title: title,
        p_description: description,
        p_url: url || null,
        p_id: item?.id ?? null,
        p_expected_version: version,
        p_file_id: fileId,
        p_archive: archive,
      })
    })
  return (
    <form
      className="space-y-3"
      onSubmit={async (e) => {
        e.preventDefault()
        if ((await save()).ok) {
          clearDirty()
          if (!item) {
            setTitle('')
            setDescription('')
            setUrl('')
            setFile(null)
            ;(e.target as HTMLFormElement).reset()
          }
          onSaved()
        }
      }}
    >
      <label className="block text-sm">
        Item title
        <input
          className="auth-field mt-1 w-full"
          required
          maxLength={200}
          value={title}
          disabled={action.busy}
          onChange={(e) => setTitle(e.target.value)}
        />
      </label>
      <label className="block text-sm">
        Item details
        <textarea
          aria-label="Item details"
          className="auth-field mt-1 w-full"
          maxLength={5000}
          required={!item && intent === 'note'}
          placeholder={
            intent === 'note'
              ? 'Explain how and when your team should use this guidance.'
              : 'Explain why this item is useful and when to use it.'
          }
          value={description}
          disabled={action.busy}
          onChange={(e) => setDescription(e.target.value)}
        />
      </label>
      {(item || intent !== 'note') && (
        <label className="block text-sm">
          Source URL
          <input
            className="auth-field mt-1 w-full"
            type="url"
            required={!item && intent === 'link'}
            maxLength={2000}
            value={url}
            disabled={action.busy}
            onChange={(e) => setUrl(e.target.value)}
          />
        </label>
      )}
      {(item || !intent) && (
        <>
          <label className="block text-sm">
            Image or document
            <input
              className="mt-2 block w-full text-sm"
              type="file"
              accept={planningFileAccept}
              disabled={action.busy}
              onChange={(e) => setFile(e.target.files?.[0] ?? null)}
            />
          </label>
          <p className={help}>
            PNG, JPEG, WebP, PDF, text, Word or Excel. Up to 50 MB per file.
          </p>
        </>
      )}
      {item?.file && !file && (
        <label className="block text-sm">
          <input
            type="checkbox"
            checked={remove}
            disabled={action.busy}
            onChange={(e) => setRemove(e.target.checked)}
          />{' '}
          Remove current attachment
        </label>
      )}
      {item && item.edit_version !== version && (
        <p role="alert" className="text-sm text-[#8a4a17]">
          A newer saved item is available. Your edits are preserved. Close and
          reopen the editor to reload it.
        </p>
      )}
      <Button
        disabled={action.busy || Boolean(item && item.edit_version !== version)}
      >
        {action.busy ? 'Saving…' : item ? 'Save item' : 'Add item'}
      </Button>
      {item && (
        <button
          type="button"
          className="auth-link ml-3 text-sm"
          disabled={action.busy}
          onClick={async () => {
            if (
              window.confirm(
                'Archive this item? Existing project copies remain available.',
              ) &&
              (await save(true)).ok
            ) {
              clearDirty()
              onSaved()
            }
          }}
        >
          Archive item
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
