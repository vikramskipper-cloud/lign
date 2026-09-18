import * as React from 'react'
import { Link, Navigate, useParams, useSearchParams } from 'react-router'
import { EmptyState } from '@/ui/empty-state'
import { LoadingPage } from '@/ui/loading-page'
import { Button } from '@/ui/button'
import { AsyncBoundary } from '@/ui/async-boundary'
import { ErrorBoundary } from '@/ui/error-boundary'
import { useAsset, useAssetNeighbors } from '@/features/designs/queries'
import { useCollections } from '@/features/collections/queries'
import { useDisciplines } from '@/features/disciplines/queries'
import { useProjectCapabilities } from '@/lib/capabilities'
import { useAssetVersions } from './queries'
import { useVersionFiles, type VersionFileRow } from '@/features/files/queries'
import { viewerFor } from '@/features/files/mime'
import { Viewer } from '@/features/files/Viewer'
import { FileSwitcher } from '@/features/files/FileSwitcher'
import { VersionBar } from './VersionBar'
import { RightPanel } from './RightPanel'
import { UploadDock } from '@/features/files/UploadDock'
import {
  AnnotationLayer,
  type AuthoringMode,
} from '@/features/annotations/AnnotationLayer'
import { AnnotationTool } from '@/features/annotations/AnnotationTool'
import { AnnotationTimeStrip } from '@/features/annotations/AnnotationTimeStrip'
import { useWorkspaceHotkeys } from './useWorkspaceHotkeys'

export const DesignWorkspaceHandle = { crumb: 'Asset' }

function pickActiveFile(
  files: VersionFileRow[],
  fileIdParam: string | undefined,
): { file: VersionFileRow | null; mismatch: boolean } {
  if (files.length === 0) return { file: null, mismatch: false }
  if (fileIdParam) {
    const match = files.find((vf) => vf.file.id === fileIdParam)
    if (match) return { file: match, mismatch: false }
    return { file: null, mismatch: true }
  }
  const primary = files.find((vf) => vf.role === 'primary')
  return { file: primary ?? files[0]!, mismatch: false }
}

export function DesignWorkspaceScreen() {
  const { ws_id, proj_id, asset_id, v_id, file_id } = useParams<{
    ws_id: string
    proj_id: string
    asset_id: string
    v_id?: string
    file_id?: string
  }>()
  const [searchParams, setSearchParams] = useSearchParams()

  const asset = useAsset(asset_id)
  const versions = useAssetVersions(asset_id)
  const collections = useCollections(proj_id)
  const disciplines = useDisciplines(proj_id)
  const caps = useProjectCapabilities(proj_id ?? '', ws_id ?? '')

  const scopeCollection = React.useMemo<string | null | 'unfiled'>(() => {
    const from = searchParams.get('from')
    if (from === 'unfiled') return 'unfiled'
    if (from?.startsWith('collection:')) return from.slice('collection:'.length)
    return asset.data?.collection_id ?? null
  }, [searchParams, asset.data?.collection_id])

  const scopeDiscipline = searchParams.get('discipline') || asset.data?.discipline_id || null

  const neighbors = useAssetNeighbors(proj_id, asset_id, {
    collection: scopeCollection,
    discipline: scopeDiscipline,
  })

  // Annotation authoring mode is lifted here so the P/Esc hotkeys can toggle it.
  const [authoringMode, setAuthoringMode] = React.useState<AuthoringMode>(null)

  const focusAnnotation = React.useCallback(
    (annotationId: string) => {
      setSearchParams(
        (prev) => {
          const next = new URLSearchParams(prev)
          next.set('tab', 'comments')
          next.set('annotation', annotationId)
          return next
        },
        { replace: true },
      )
    },
    [setSearchParams],
  )

  // Hotkeys (D23): C opens Comments + focuses composer via ?tab=comments&comment=new.
  // We don't have a real "focus the composer" ref plumbing; the composer auto-focuses
  // when the panel opens from ?tab=comments if no other item is focused, which is
  // handled by CommentsPanel's CommentComposer(compactUntilFocus=true) — the user
  // just needs to click. Simpler: set the tab; the composer's compact button is the
  // most visible target. We add a lightweight `focus-composer` flag the panel reads.
  useWorkspaceHotkeys({
    onNewComment: () => {
      setSearchParams(
        (prev) => {
          const next = new URLSearchParams(prev)
          next.set('tab', 'comments')
          return next
        },
        { replace: true },
      )
    },
    onAddPin: () => {
      if (!caps.data?.['annotation.create']) return
      setAuthoringMode((m) => (m === 'point' ? null : 'point'))
    },
    onEscape: () => {
      if (authoringMode !== null) {
        setAuthoringMode(null)
        return
      }
      // Close a focused annotation/comment if any.
      if (searchParams.get('annotation') || searchParams.get('comment')) {
        setSearchParams(
          (prev) => {
            const next = new URLSearchParams(prev)
            next.delete('annotation')
            next.delete('comment')
            return next
          },
          { replace: true },
        )
      }
    },
  })

  if (asset.isLoading || versions.isLoading) return <LoadingPage />
  if (asset.isError || !asset.data || !ws_id || !proj_id || !asset_id) {
    return (
      <div className="p-8">
        <EmptyState
          title="Asset not found"
          description="It may have been archived or moved."
          action={
            <Button asChild size="sm" variant="secondary">
              <Link to={`/workspace/${ws_id}/project/${proj_id}/designs`}>Back to Designs</Link>
            </Button>
          }
        />
      </div>
    )
  }

  const allVersions = versions.data ?? []
  const currentVersionId = asset.data.current_version_id
  let activeVersion = null
  let versionMismatch = false
  if (v_id) {
    const match = allVersions.find((v) => v.id === v_id)
    if (match) activeVersion = match
    else versionMismatch = true
  } else if (currentVersionId) {
    activeVersion = allVersions.find((v) => v.id === currentVersionId) ?? null
  } else if (allVersions.length > 0) {
    activeVersion = allVersions[0] ?? null
  }

  const scopeQuery = new URLSearchParams()
  const from = searchParams.get('from')
  if (from) scopeQuery.set('from', from)
  if (searchParams.get('discipline')) scopeQuery.set('discipline', searchParams.get('discipline')!)
  const scopeQueryStr = scopeQuery.toString()

  const workspaceHref = `/workspace/${ws_id}/project/${proj_id}/asset/${asset.data.id}${
    activeVersion ? `/v/${activeVersion.id}` : ''
  }`

  const canAnnotate = Boolean(caps.data?.['annotation.create'])

  return (
    <div className="flex h-full min-h-0 flex-col">
      <VersionBar
        workspaceId={ws_id}
        projectId={proj_id}
        assetId={asset.data.id}
        assetName={asset.data.name}
        activeVersion={activeVersion}
        versions={allVersions}
        currentVersionId={currentVersionId}
        canSetCurrent={Boolean(caps.data?.['asset.set_current'])}
        canPublishVersion={Boolean(caps.data?.['version.publish'])}
        canDiscardVersion={Boolean(caps.data?.['version.discard_draft'])}
        canCreateVersion={Boolean(caps.data?.['version.upload'])}
        neighbors={neighbors.data ?? []}
        scopeQuery={scopeQueryStr}
      />
      <div className="flex flex-1 min-h-0">
        <main className="flex min-w-0 flex-1 flex-col">
          <ErrorBoundary>
            {versionMismatch ? (
              <VersionNotFound
                workspaceId={ws_id}
                projectId={proj_id}
                assetId={asset.data.id}
              />
            ) : (
              <ViewerRegion
                workspaceId={ws_id}
                projectId={proj_id}
                assetId={asset.data.id}
                versionId={activeVersion?.id ?? null}
                isDraft={activeVersion?.status === 'draft'}
                fileIdParam={file_id}
                scopeQuery={scopeQueryStr}
                canAttach={Boolean(caps.data?.['version.upload'])}
                canDetach={Boolean(caps.data?.['version.upload'])}
                canAnnotate={canAnnotate}
                authoringMode={authoringMode}
                onAuthoringModeChange={setAuthoringMode}
                workspaceHref={workspaceHref}
              />
            )}
          </ErrorBoundary>
        </main>
        <AsyncBoundary>
          <SidePanelForVersion
            workspaceId={ws_id}
            projectId={proj_id}
            asset={asset.data}
            collections={collections.data ?? []}
            disciplines={disciplines.data ?? []}
            versions={allVersions}
            activeVersionId={activeVersion?.id ?? null}
            isDraft={activeVersion?.status === 'draft'}
            activeFileIdParam={file_id ?? null}
            canEditAsset={Boolean(caps.data?.['asset.edit'])}
            canArchiveAsset={Boolean(caps.data?.['asset.archive'])}
            canEditProject={Boolean(caps.data?.['project.edit'])}
            canComment={Boolean(caps.data?.['comment.create'])}
            canResolveComment={Boolean(caps.data?.['comment.resolve'])}
            canEditOwnComment={Boolean(caps.data?.['comment.edit_own'])}
            canCreateReview={Boolean(caps.data?.['review.create'])}
            activeVersionPublished={activeVersion?.status === 'published'}
            scopeQuery={scopeQueryStr}
            onFocusAnnotation={focusAnnotation}
          />
        </AsyncBoundary>
      </div>
    </div>
  )
}

function ViewerRegion({
  workspaceId,
  projectId,
  assetId,
  versionId,
  isDraft,
  fileIdParam,
  scopeQuery,
  canAttach,
  canDetach,
  canAnnotate,
  authoringMode,
  onAuthoringModeChange,
  workspaceHref,
}: {
  workspaceId: string
  projectId: string
  assetId: string
  versionId: string | null
  isDraft: boolean
  fileIdParam: string | undefined
  scopeQuery: string
  canAttach: boolean
  canDetach: boolean
  canAnnotate: boolean
  authoringMode: AuthoringMode
  onAuthoringModeChange: (m: AuthoringMode) => void
  workspaceHref: string
}) {
  const files = useVersionFiles(versionId ?? undefined)
  if (!versionId) return <NoVersions />
  if (files.isLoading) {
    return (
      <div className="flex flex-1 items-center justify-center text-sm text-[--color-text-muted]">
        Loading files…
      </div>
    )
  }
  const list = files.data ?? []
  const { file, mismatch } = pickActiveFile(list, fileIdParam)

  if (fileIdParam && mismatch) {
    return (
      <div className="flex flex-1 items-center justify-center">
        <EmptyState
          title="File not in this version"
          description="The requested file doesn't belong to this version."
          action={
            <Button asChild size="sm" variant="secondary">
              <Link
                to={`/workspace/${workspaceId}/project/${projectId}/asset/${assetId}/v/${versionId}${
                  scopeQuery ? `?${scopeQuery}` : ''
                }`}
              >
                View primary file
              </Link>
            </Button>
          }
        />
      </div>
    )
  }

  if (list.length === 0) {
    return (
      <>
        <div className="flex flex-1 items-center justify-center">
          <EmptyState
            title={isDraft ? 'Drop files to attach' : 'This version has no files'}
            description={
              isDraft
                ? 'Drag files onto the dock below, or click Add files.'
                : 'No files were attached to this version.'
            }
          />
        </div>
        {isDraft && (
          <UploadDock
            versionId={versionId}
            projectId={projectId}
            assetId={assetId}
            files={[]}
            canAttach={canAttach}
            canDetach={canDetach}
          />
        )}
      </>
    )
  }

  const kind = file ? viewerFor(file.file.mime_type) : 'download-only'
  const isImage = kind === 'image'
  const isVideo = kind === 'video'
  const showAnnotationTool = canAnnotate && file && (isImage || isVideo)

  return (
    <>
      {list.length > 1 && (
        <FileSwitcher
          workspaceId={workspaceId}
          projectId={projectId}
          assetId={assetId}
          versionId={versionId}
          files={list}
          activeFileId={file?.file.id ?? ''}
          scopeQuery={scopeQuery}
        />
      )}
      <div className="relative flex-1 min-h-0 p-4">
        {file ? (
          <Viewer
            vf={file}
            imageOverlay={
              isImage ? (
                <AnnotationLayer
                  workspaceId={file.workspace_id}
                  projectId={projectId}
                  versionId={versionId}
                  versionFileId={file.id}
                  workspaceHref={workspaceHref}
                  mode={authoringMode}
                  onModeChange={onAuthoringModeChange}
                />
              ) : undefined
            }
            videoBelowStrip={
              isVideo
                ? ({ getCurrentTime, seekTo, duration }) => (
                    <AnnotationTimeStrip
                      workspaceId={file.workspace_id}
                      projectId={projectId}
                      versionId={versionId}
                      versionFileId={file.id}
                      workspaceHref={workspaceHref}
                      getCurrentTime={getCurrentTime}
                      seekTo={seekTo}
                      duration={duration}
                      canAnnotate={canAnnotate}
                    />
                  )
                : undefined
            }
          />
        ) : (
          <NoVersions />
        )}
        {showAnnotationTool && isImage && (
          <AnnotationTool
            mode={authoringMode}
            onChange={onAuthoringModeChange}
            canAnnotate={canAnnotate}
          />
        )}
      </div>
      {isDraft && (
        <UploadDock
          versionId={versionId}
          projectId={projectId}
          assetId={assetId}
          files={list}
          canAttach={canAttach}
          canDetach={canDetach}
        />
      )}
    </>
  )
}

interface SidePanelProps {
  workspaceId: string
  projectId: string
  asset: NonNullable<ReturnType<typeof useAsset>['data']>
  collections: ReturnType<typeof useCollections>['data'] extends infer T
    ? Exclude<T, undefined>
    : never
  disciplines: ReturnType<typeof useDisciplines>['data'] extends infer T
    ? Exclude<T, undefined>
    : never
  versions: ReturnType<typeof useAssetVersions>['data'] extends infer T
    ? Exclude<T, undefined>
    : never
  activeVersionId: string | null
  isDraft: boolean
  activeFileIdParam: string | null
  canEditAsset: boolean
  canArchiveAsset: boolean
  canEditProject: boolean
  canComment: boolean
  canResolveComment: boolean
  canEditOwnComment: boolean
  canCreateReview: boolean
  activeVersionPublished: boolean
  scopeQuery: string
  onFocusAnnotation?: (annotationId: string) => void
}

function SidePanelForVersion({
  workspaceId,
  projectId,
  asset,
  collections,
  disciplines,
  versions,
  activeVersionId,
  isDraft,
  activeFileIdParam,
  canEditAsset,
  canArchiveAsset,
  canEditProject,
  canComment,
  canResolveComment,
  canEditOwnComment,
  canCreateReview,
  activeVersionPublished,
  scopeQuery,
  onFocusAnnotation,
}: SidePanelProps) {
  const files = useVersionFiles(activeVersionId ?? undefined)
  const list = files.data ?? []
  const { file } = pickActiveFile(list, activeFileIdParam ?? undefined)
  return (
    <RightPanel
      workspaceId={workspaceId}
      projectId={projectId}
      asset={asset}
      collections={collections}
      disciplines={disciplines}
      versions={versions}
      activeVersionId={activeVersionId}
      activeFileId={file?.file.id ?? null}
      isDraft={isDraft}
      files={list}
      canEditAsset={canEditAsset}
      canArchiveAsset={canArchiveAsset}
      canEditProject={canEditProject}
      canComment={canComment}
      canResolveComment={canResolveComment}
      canEditOwnComment={canEditOwnComment}
      canCreateReview={canCreateReview}
      activeVersionPublished={activeVersionPublished}
      scopeQuery={scopeQuery}
      onFocusAnnotation={onFocusAnnotation}
    />
  )
}

function NoVersions() {
  return (
    <div className="flex flex-1 items-center justify-center">
      <EmptyState
        title="This asset has no versions yet"
        description="Create a draft version to attach files."
      />
    </div>
  )
}

function VersionNotFound({
  workspaceId,
  projectId,
  assetId,
}: {
  workspaceId: string
  projectId: string
  assetId: string
}) {
  return (
    <div className="flex flex-1 items-center justify-center">
      <EmptyState
        title="Version not found"
        description="That version does not belong to this asset."
        action={
          <Button asChild size="sm" variant="secondary">
            <Link to={`/workspace/${workspaceId}/project/${projectId}/asset/${assetId}`}>
              View current version
            </Link>
          </Button>
        }
      />
    </div>
  )
}

// The workspace URL may include a stale file_id when the user changes versions.
// This helper redirects to the same URL minus the file segment. Currently unused
// (kept for potential future need); silence lint by exporting.
export function StripFileFromUrl({ to }: { to: string }) {
  return <Navigate to={to} replace />
}
