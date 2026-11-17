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
import { libraryCategories } from './libraryModel'
export function CollectionForm({
  org,
  collection,
  onSaved,
}: {
  org: string
  collection?: Collection
  onSaved: (id: string) => void
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
          onSaved(r.data)
        }
      }}
    >
      <label className="block text-sm">
        Collection title
        <input
          className="auth-field mt-1 w-full"
          required
          maxLength={160}
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
      <label className="block text-sm">
        Description
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
        Tags
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
      {collection && collection.edit_version !== version && (
        <p role="alert" className="text-sm text-[#8a4a17]">
          Saved collection details have changed. Your edits are preserved. Close
          and reopen settings to load the latest version.
        </p>
      )}
      <Button
        disabled={
          action.busy ||
          Boolean(collection && collection.edit_version !== version)
        }
      >
        {collection ? 'Save collection' : 'Create collection'}
      </Button>
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
  onSaved,
}: {
  org: string
  collectionId: string
  item?: LibraryItem
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
          value={description}
          disabled={action.busy}
          onChange={(e) => setDescription(e.target.value)}
        />
      </label>
      <label className="block text-sm">
        Source URL
        <input
          className="auth-field mt-1 w-full"
          type="url"
          maxLength={2000}
          value={url}
          disabled={action.busy}
          onChange={(e) => setUrl(e.target.value)}
        />
      </label>
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
