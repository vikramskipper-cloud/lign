import { useState } from 'react'
import { Button } from '@/features/planning/PlanningButton'
import {
  planningFileAccept,
  planningRpc,
  help,
} from '@/features/planning/queries'
import { humanizeError } from '@/features/shared/errors'
import { useLibraryAction, uploadLibrary } from './queries'
import { useLibraryDirty } from './LibraryActivity'
interface Entry {
  file: File
  title: string
  state: 'ready' | 'uploading' | 'done' | 'failed'
  error?: string
}
export function LibraryUpload({
  org,
  collectionId,
  onDone,
}: {
  org: string
  collectionId: string
  onDone: () => void
}) {
  const [entries, setEntries] = useState<Entry[]>([]),
    [error, setError] = useState(''),
    action = useLibraryAction()
  const pending = entries.filter((e) => e.state !== 'done'),
    clearDirty = useLibraryDirty(pending.length > 0)
  const update = (index: number, value: Partial<Entry>) =>
    setEntries((old) =>
      old.map((e, i) => (i === index ? { ...e, ...value } : e)),
    )
  const upload = async () => {
    await action.run(async () => {
      for (let i = 0; i < entries.length; i++) {
        const entry = entries[i]
        if (entry.state === 'done') continue
        update(i, { state: 'uploading', error: undefined })
        try {
          const fileId = await uploadLibrary(org, entry.file)
          await planningRpc('save_library_item', {
            p_collection_id: collectionId,
            p_title: entry.title.trim(),
            p_description: '',
            p_file_id: fileId,
          })
          update(i, { state: 'done' })
        } catch (e) {
          update(i, { state: 'failed', error: humanizeError(e) })
        }
      }
    })
  }
  return (
    <div className="space-y-4">
      <label className="block text-sm">
        Choose files
        <input
          className="mt-2 block w-full text-sm"
          type="file"
          multiple
          accept={planningFileAccept}
          disabled={action.busy || entries.some((e) => e.state === 'done')}
          onChange={(e) => {
            const files = Array.from(e.target.files ?? [])
            if (
              files.length > 20 ||
              files.some((f) => f.size === 0 || f.size > 52428800)
            ) {
              setError('Choose up to 20 files, each between 1 byte and 50 MB.')
              e.target.value = ''
              return
            }
            setError('')
            setEntries(
              files.map((file) => ({
                file,
                title: file.name.replace(/\.[^.]+$/, '').slice(0, 200),
                state: 'ready',
              })),
            )
          }}
        />
      </label>
      <p className={help}>
        Images, PDFs, text, Word or Excel. Up to 20 files at a time, 50 MB each.
        Each file becomes a separate item in this collection.
      </p>
      <div className="max-h-72 space-y-3 overflow-y-auto" aria-live="polite">
        {entries.map((entry, i) => (
          <div
            key={`${entry.file.name}-${i}`}
            className="rounded-lg border border-[#e5ddd3] p-3"
          >
            <label className="block text-xs text-[#786b60]">
              {entry.file.name}
              <input
                aria-label={`Title for ${entry.file.name}`}
                className="auth-field mt-1 w-full"
                maxLength={200}
                value={entry.title}
                disabled={action.busy || entry.state === 'done'}
                onChange={(e) => update(i, { title: e.target.value })}
              />
            </label>
            <p className="mt-1 text-xs">
              {entry.state === 'done'
                ? 'Added'
                : entry.state === 'uploading'
                  ? 'Uploading…'
                  : entry.state === 'failed'
                    ? 'Failed — retry below'
                    : 'Ready to upload'}
            </p>
            {entry.error && (
              <p role="alert" className="text-sm text-red-700">
                {entry.error}
              </p>
            )}
          </div>
        ))}
      </div>
      {error && (
        <p role="alert" className="text-sm text-red-700">
          {error}
        </p>
      )}
      {action.error && (
        <p role="alert" className="text-sm text-red-700">
          {action.error}
        </p>
      )}
      {entries.length > 0 && !pending.length ? (
        <>
          <p role="status" className="text-sm">
            All {entries.length} files added.
          </p>
          <Button
            onClick={() => {
              clearDirty()
              onDone()
            }}
          >
            Done
          </Button>
        </>
      ) : (
        <Button
          disabled={
            action.busy ||
            !pending.length ||
            pending.some((e) => !e.title.trim())
          }
          onClick={() => void upload()}
        >
          {action.busy
            ? 'Adding files…'
            : entries.some((e) => e.state === 'failed')
              ? 'Retry failed files'
              : `Add ${pending.length || ''} files`}
        </Button>
      )}
    </div>
  )
}
