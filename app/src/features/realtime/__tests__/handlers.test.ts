import { describe, expect, it, beforeEach, vi } from 'vitest'
import { QueryClient } from '@tanstack/react-query'
import { handleRealtimeRow } from '../handlers'
import type { HandlerCtx } from '../handlers'
import type { Coalescer } from '../coalesce'
import { createCoalescer } from '../coalesce'
import { qk } from '@/lib/queryKeys'

/**
 * Behavioural tests for the APP 011 event -> invalidation mapping.
 *
 * These assert the EFFECT, not the call: each test seeds real entries into a
 * real QueryClient, feeds a synthetic payload through the handler, and then
 * asserts which cache entries actually became invalidated. Spying on
 * `invalidateQueries` would only prove the handler called a function.
 */

const WS = 'ws-1'
const immediate: Coalescer = {
  schedule: (_k, run) => run(),
  flush: () => {},
  dispose: () => {},
}

let qc: QueryClient
let unmapped: Array<[string, string]>
let ctx: HandlerCtx

function seed(key: readonly unknown[]) {
  qc.setQueryData(key as unknown[], { seeded: true })
}
const invalidated = (key: readonly unknown[]) =>
  qc.getQueryState(key as unknown[])?.isInvalidated === true

beforeEach(() => {
  qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  unmapped = []
  ctx = {
    qc,
    wsId: WS,
    coalescer: immediate,
    onUnmapped: (t, r) => unmapped.push([t, r]),
  }
})

describe('comments — 8-way XOR dispatch', () => {
  const arms: Array<[string, string, readonly unknown[]]> = [
    ['target_version_id', 'v1', qk.commentsForVersion('v1')],
    ['target_annotation_id', 'a1', qk.commentsForAnnotation('a1')],
    ['target_review_id', 'r1', qk.review('r1')],
    ['target_approval_request_id', 'ar1', qk.approvalRequest('ar1')],
    ['target_requirement_id', 'rq1', qk.requirementDiscussions('rq1')],
    ['target_design_asset_id', 'da1', qk.asset('da1')],
  ]

  it.each(arms)('%s dispatches to its own key', (col, id, key) => {
    seed(key)
    handleRealtimeRow(ctx, 'comments', { id: 'c1', workspace_id: WS, [col]: id })
    expect(invalidated(key)).toBe(true)
    expect(unmapped).toEqual([])
  })

  it('does not invalidate the other arms', () => {
    seed(qk.commentsForVersion('v1'))
    seed(qk.review('r1'))
    seed(qk.requirementDiscussions('rq1'))
    handleRealtimeRow(ctx, 'comments', { id: 'c1', workspace_id: WS, target_version_id: 'v1' })
    expect(invalidated(qk.commentsForVersion('v1'))).toBe(true)
    expect(invalidated(qk.review('r1'))).toBe(false)
    expect(invalidated(qk.requirementDiscussions('rq1'))).toBe(false)
  })

  it('change/decision arms report as unmapped rather than failing silently', () => {
    handleRealtimeRow(ctx, 'comments', { id: 'c1', workspace_id: WS, target_change_id: 'ch1' })
    handleRealtimeRow(ctx, 'comments', { id: 'c2', workspace_id: WS, target_decision_id: 'd1' })
    expect(unmapped).toHaveLength(2)
    expect(unmapped[0][1]).toMatch(/no live surface/)
  })

  it('a row with no target set is reported (would violate the XOR check)', () => {
    handleRealtimeRow(ctx, 'comments', { id: 'c1', workspace_id: WS })
    expect(unmapped[0][1]).toMatch(/no target column set/)
  })
})

describe('per-table mapping', () => {
  it('annotations -> that version only', () => {
    seed(qk.annotationsForVersion('v1'))
    seed(qk.annotationsForVersion('v2'))
    handleRealtimeRow(ctx, 'annotations', { id: 'an1', workspace_id: WS, asset_version_id: 'v1' })
    expect(invalidated(qk.annotationsForVersion('v1'))).toBe(true)
    expect(invalidated(qk.annotationsForVersion('v2'))).toBe(false)
  })

  it('asset_versions -> version list, version detail, project asset list', () => {
    const filters = { collection: null, discipline: null, search: '' }
    seed(qk.assetVersions('da1'))
    seed(qk.assetVersion('v1'))
    seed(qk.assets('p1', filters))
    handleRealtimeRow(ctx, 'asset_versions', {
      id: 'v1', workspace_id: WS, design_asset_id: 'da1', project_id: 'p1',
    })
    expect(invalidated(qk.assetVersions('da1'))).toBe(true)
    expect(invalidated(qk.assetVersion('v1'))).toBe(true)
    expect(invalidated(qk.assets('p1', filters))).toBe(true)
  })

  it('design_assets -> asset detail, project list, neighbours', () => {
    const scope = { collection: null, discipline: null }
    seed(qk.asset('da1'))
    seed(qk.assetNeighbors('da1', scope))
    handleRealtimeRow(ctx, 'design_assets', { id: 'da1', workspace_id: WS, project_id: 'p1' })
    expect(invalidated(qk.asset('da1'))).toBe(true)
    expect(invalidated(qk.assetNeighbors('da1', scope))).toBe(true)
  })

  it('reviews -> detail, list, inbox; chain invalidated when root present', () => {
    seed(qk.review('r1'))
    seed(qk.reviewChain('root1'))
    seed(qk.reviewInboxCount(WS))
    seed(qk.reviewsList({ wsId: WS, projId: 'p1' }, 'all', {}))
    handleRealtimeRow(ctx, 'reviews', {
      id: 'r1', workspace_id: WS, project_id: 'p1', root_review_id: 'root1',
    })
    expect(invalidated(qk.review('r1'))).toBe(true)
    expect(invalidated(qk.reviewChain('root1'))).toBe(true)
    expect(invalidated(qk.reviewInboxCount(WS))).toBe(true)
    expect(invalidated(qk.reviewsList({ wsId: WS, projId: 'p1' }, 'all', {}))).toBe(true)
  })

  it('reviews -> chain is skipped, not guessed, when root_review_id is null', () => {
    seed(qk.reviewChain('root1'))
    handleRealtimeRow(ctx, 'reviews', {
      id: 'r1', workspace_id: WS, project_id: 'p1', root_review_id: null,
    })
    expect(invalidated(qk.reviewChain('root1'))).toBe(false)
  })

  it('review_participants -> roster + inbox', () => {
    seed(qk.reviewParticipants('r1'))
    seed(qk.reviewInboxCount(WS))
    handleRealtimeRow(ctx, 'review_participants', {
      id: 'rp1', workspace_id: WS, review_id: 'r1',
    })
    expect(invalidated(qk.reviewParticipants('r1'))).toBe(true)
    expect(invalidated(qk.reviewInboxCount(WS))).toBe(true)
  })

  it('approval_requests -> detail, readiness, list, inbox', () => {
    seed(qk.approvalRequest('ar1'))
    seed(qk.approvalReadiness('v1'))
    seed(qk.approvalInboxCount(WS))
    handleRealtimeRow(ctx, 'approval_requests', {
      id: 'ar1', workspace_id: WS, project_id: 'p1', version_id: 'v1',
      root_approval_request_id: null,
    })
    expect(invalidated(qk.approvalRequest('ar1'))).toBe(true)
    expect(invalidated(qk.approvalReadiness('v1'))).toBe(true)
    expect(invalidated(qk.approvalInboxCount(WS))).toBe(true)
  })

  it('approval_responses -> parent request + inbox', () => {
    seed(qk.approvalRequest('ar1'))
    seed(qk.approvalInboxCount(WS))
    handleRealtimeRow(ctx, 'approval_responses', {
      id: 'resp1', workspace_id: WS, approval_request_id: 'ar1',
    })
    expect(invalidated(qk.approvalRequest('ar1'))).toBe(true)
    expect(invalidated(qk.approvalInboxCount(WS))).toBe(true)
  })

  it('§6.1 — does NOT fan out to release/requirement readiness', () => {
    seed(qk.releaseReadinessForVersion('v1'))
    seed(qk.assessmentsForVersion('v1'))
    handleRealtimeRow(ctx, 'approval_responses', {
      id: 'resp1', workspace_id: WS, approval_request_id: 'ar1',
    })
    expect(invalidated(qk.releaseReadinessForVersion('v1'))).toBe(false)
    expect(invalidated(qk.assessmentsForVersion('v1'))).toBe(false)
  })
})

describe('safety invariants', () => {
  it('a null row is ignored', () => {
    expect(() => handleRealtimeRow(ctx, 'comments', null)).not.toThrow()
    expect(unmapped).toEqual([])
  })

  it('missing required FK is reported, never guessed', () => {
    handleRealtimeRow(ctx, 'annotations', { id: 'an1', workspace_id: WS })
    handleRealtimeRow(ctx, 'review_participants', { id: 'rp1', workspace_id: WS })
    handleRealtimeRow(ctx, 'approval_responses', { id: 'x', workspace_id: WS })
    expect(unmapped.map((u) => u[0])).toEqual([
      'annotations', 'review_participants', 'approval_responses',
    ])
  })

  it('an unrelated cache entry is never touched', () => {
    seed(qk.workspaces())
    seed(qk.projectCapabilities('p1', WS))
    handleRealtimeRow(ctx, 'comments', { id: 'c1', workspace_id: WS, target_version_id: 'v1' })
    expect(invalidated(qk.workspaces())).toBe(false)
    expect(invalidated(qk.projectCapabilities('p1', WS))).toBe(false)
  })

  it('coalesces a burst on one key into a single invalidation', async () => {
    vi.useFakeTimers()
    const real = createCoalescer(250)
    const spy = vi.spyOn(qc, 'invalidateQueries')
    const c: HandlerCtx = { qc, wsId: WS, coalescer: real }
    for (let i = 0; i < 10; i++) {
      handleRealtimeRow(c, 'review_participants', {
        id: `rp${i}`, workspace_id: WS, review_id: 'r1',
      })
    }
    expect(spy).not.toHaveBeenCalled()
    vi.advanceTimersByTime(250)
    // one scheduled closure ran; it invalidates roster + inbox = 2 calls, not 20
    expect(spy).toHaveBeenCalledTimes(2)
    vi.useRealTimers()
  })
})
