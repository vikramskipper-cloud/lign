import type { QueryClient } from '@tanstack/react-query'
import type { Coalescer } from './coalesce'
import type { RealtimeTable } from './channels'
import {
  invalidateAnnotationsForVersion,
  invalidateApproval,
  invalidateApprovalInbox,
  invalidateApprovalsLists,
  invalidateAssetsForProject,
  invalidateCommentsForVersion,
  invalidateNeighborsForAsset,
  invalidateNotifications,
  invalidateReview,
  invalidateReviewInbox,
  invalidateReviewsLists,
} from '@/features/shared/invalidate'
import { qk } from '@/lib/queryKeys'

/**
 * APP 011 §6 — the event→invalidation mapping.
 *
 * THE RULE (Freeze Index §2): a payload is never written into the cache. It is
 * only ever read for the identifiers needed to invalidate. Three reasons this
 * is structural rather than stylistic:
 *   1. every list/detail surface is fed by an RPC returning a joined, computed
 *      DTO that a raw table row cannot populate;
 *   2. Realtime delivers rows RLS-filtered per subscriber, so a payload is not
 *      guaranteed to be the whole row;
 *   3. dashboard keys embed server-opaque cursors that splicing would corrupt.
 *
 * Every helper called here already existed before APP 011. This module adds no
 * query key.
 */

type Row = Record<string, unknown>

const str = (row: Row, col: string): string | null => {
  const v = row[col]
  return typeof v === 'string' && v.length > 0 ? v : null
}

export interface HandlerCtx {
  qc: QueryClient
  wsId: string
  coalescer: Coalescer
  /** Diagnostics sink; see RealtimeProvider. Never user-facing. */
  onUnmapped?: (table: RealtimeTable, reason: string) => void
}

/** Schedule an invalidation under a coalescing key. */
function bump(ctx: HandlerCtx, key: string, run: () => void) {
  ctx.coalescer.schedule(key, run)
}

export function handleRealtimeRow(
  ctx: HandlerCtx,
  table: RealtimeTable,
  row: Row | null,
): void {
  if (!row) return
  const { qc } = ctx

  switch (table) {
    case 'comments': {
      // All eight target_* columns are nullable because exactly one is set
      // (comments_target_xor_check, verified 8-way on 2026-09-18). This is a
      // dispatch on which arm is populated, not a fallback chain.
      const v = str(row, 'target_version_id')
      if (v) return bump(ctx, `comments:v:${v}`, () => invalidateCommentsForVersion(qc, v))

      const a = str(row, 'target_annotation_id')
      if (a) return bump(ctx, `comments:a:${a}`, () =>
        qc.invalidateQueries({ queryKey: qk.commentsForAnnotation(a) }))

      const r = str(row, 'target_review_id')
      if (r) return bump(ctx, `comments:r:${r}`, () =>
        qc.invalidateQueries({ queryKey: qk.review(r) }))

      const ar = str(row, 'target_approval_request_id')
      if (ar) return bump(ctx, `comments:ar:${ar}`, () =>
        qc.invalidateQueries({ queryKey: qk.approvalRequest(ar) }))

      const rq = str(row, 'target_requirement_id')
      if (rq) return bump(ctx, `comments:rq:${rq}`, () =>
        qc.invalidateQueries({ queryKey: qk.requirementDiscussions(rq) }))

      const da = str(row, 'target_design_asset_id')
      if (da) return bump(ctx, `comments:da:${da}`, () =>
        qc.invalidateQueries({ queryKey: qk.asset(da) }))

      // `changes` and `decisions` are deliberately NOT in the publication, so
      // these arms have no live surface in v1. Reported rather than silently
      // dropped — a silent no-op is how dead code hides.
      if (str(row, 'target_change_id') || str(row, 'target_decision_id')) {
        ctx.onUnmapped?.('comments', 'change/decision target has no live surface in v1')
        return
      }
      ctx.onUnmapped?.('comments', 'no target column set (violates comments_target_xor_check)')
      return
    }

    case 'annotations': {
      const v = str(row, 'asset_version_id')
      if (!v) return ctx.onUnmapped?.(table, 'asset_version_id absent')
      return bump(ctx, `annotations:${v}`, () => invalidateAnnotationsForVersion(qc, v))
    }

    case 'asset_versions': {
      const id = str(row, 'id')
      const assetId = str(row, 'design_asset_id')
      const projId = str(row, 'project_id')
      return bump(ctx, `asset_versions:${id ?? assetId ?? 'all'}`, () => {
        if (assetId) qc.invalidateQueries({ queryKey: qk.assetVersions(assetId) })
        if (id) qc.invalidateQueries({ queryKey: qk.assetVersion(id) })
        if (projId) invalidateAssetsForProject(qc, projId)
      })
    }

    case 'design_assets': {
      const id = str(row, 'id')
      const projId = str(row, 'project_id')
      return bump(ctx, `design_assets:${id ?? projId ?? 'all'}`, () => {
        if (projId) invalidateAssetsForProject(qc, projId)
        if (id) {
          qc.invalidateQueries({ queryKey: qk.asset(id) })
          invalidateNeighborsForAsset(qc, id)
        }
      })
    }

    case 'reviews': {
      const id = str(row, 'id')
      const projId = str(row, 'project_id')
      // root_review_id is nullable; when absent the chain key is skipped, not guessed.
      const rootId = str(row, 'root_review_id') ?? undefined
      return bump(ctx, `reviews:${id ?? 'all'}`, () => {
        if (id) invalidateReview(qc, id, rootId)
        invalidateReviewsLists(qc, ctx.wsId, projId ?? undefined)
        invalidateReviewInbox(qc, ctx.wsId)
      })
    }

    case 'review_participants': {
      const reviewId = str(row, 'review_id')
      if (!reviewId) return ctx.onUnmapped?.(table, 'review_id absent')
      return bump(ctx, `review_participants:${reviewId}`, () => {
        qc.invalidateQueries({ queryKey: qk.reviewParticipants(reviewId) })
        invalidateReviewInbox(qc, ctx.wsId)
      })
    }

    case 'approval_requests': {
      const id = str(row, 'id')
      const projId = str(row, 'project_id')
      const versionId = str(row, 'version_id') ?? undefined
      const rootId = str(row, 'root_approval_request_id') ?? undefined
      return bump(ctx, `approval_requests:${id ?? 'all'}`, () => {
        if (id) invalidateApproval(qc, id, rootId, versionId)
        invalidateApprovalsLists(qc, ctx.wsId, projId ?? undefined)
        invalidateApprovalInbox(qc, ctx.wsId)
      })
    }

    case 'notifications': {
      // REALTIME 003 / wave 1B. The row is recipient-scoped by RLS, so anything
      // that arrives here is already this user's. Coalesced per workspace: a
      // burst from one workflow action fans out to several notifications and
      // should still refresh the bell once.
      return bump(ctx, `notifications:${ctx.wsId}`, () =>
        invalidateNotifications(qc, ctx.wsId))
    }

    case 'approval_responses': {
      const requestId = str(row, 'approval_request_id')
      if (!requestId) return ctx.onUnmapped?.(table, 'approval_request_id absent')
      return bump(ctx, `approval_responses:${requestId}`, () => {
        invalidateApproval(qc, requestId)
        invalidateApprovalInbox(qc, ctx.wsId)
      })
      // §6.1: an approval response can change release readiness (APP 009) and
      // requirement assessment state (APP 008). APP 011 deliberately does NOT
      // encode that fan-out. Guessing at downstream effects is how a transport
      // layer becomes a business-logic layer; those keys refetch on their own
      // staleTime.
    }
  }
}
