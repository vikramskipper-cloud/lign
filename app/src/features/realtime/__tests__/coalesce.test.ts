import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { createCoalescer } from '../coalesce'

describe('coalescer (APP 011 §7.3)', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  it('collapses repeated schedules on one key into a single trailing run', () => {
    const c = createCoalescer(250)
    const run = vi.fn()
    for (let i = 0; i < 12; i++) c.schedule('k', run)
    expect(run).not.toHaveBeenCalled()      // trailing, not leading
    vi.advanceTimersByTime(250)
    expect(run).toHaveBeenCalledTimes(1)    // twelve events -> one invalidation
  })

  it('runs the most recently scheduled closure for a key', () => {
    const c = createCoalescer(250)
    const order: string[] = []
    c.schedule('k', () => order.push('first'))
    c.schedule('k', () => order.push('second'))
    vi.advanceTimersByTime(250)
    expect(order).toEqual(['second'])
  })

  it('keys are independent — one key never delays another', () => {
    const c = createCoalescer(250)
    const a = vi.fn()
    const b = vi.fn()
    c.schedule('a', a)
    vi.advanceTimersByTime(200)
    c.schedule('b', b)          // b scheduled late
    vi.advanceTimersByTime(50)  // a's window elapses
    expect(a).toHaveBeenCalledTimes(1)
    expect(b).not.toHaveBeenCalled()
    vi.advanceTimersByTime(200)
    expect(b).toHaveBeenCalledTimes(1)
  })

  it('flush runs everything pending immediately', () => {
    const c = createCoalescer(250)
    const a = vi.fn()
    const b = vi.fn()
    c.schedule('a', a)
    c.schedule('b', b)
    c.flush()
    expect(a).toHaveBeenCalledTimes(1)
    expect(b).toHaveBeenCalledTimes(1)
    vi.advanceTimersByTime(500)
    expect(a).toHaveBeenCalledTimes(1)   // not run twice
  })

  it('dispose drops pending work without running it', () => {
    const c = createCoalescer(250)
    const run = vi.fn()
    c.schedule('k', run)
    c.dispose()
    vi.advanceTimersByTime(500)
    expect(run).not.toHaveBeenCalled()
  })
})
