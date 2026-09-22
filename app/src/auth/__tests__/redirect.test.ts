import { describe, expect, it } from 'vitest'
import { isSafeRedirect, resolveRedirect } from '../redirect'

/**
 * An open redirect on a login page is a phishing primitive: the victim really
 * does sign in to Lign, then gets handed to an attacker page. These cases are
 * the ones that get past naive "starts with /" checks.
 */
describe('isSafeRedirect', () => {
  it.each([
    '/',
    '/projects/abc',
    '/workspace/123/project/456/designs',
    '/a?b=c#d',
  ])('allows same-origin path %s', (v) => {
    expect(isSafeRedirect(v)).toBe(true)
  })

  it.each([
    ['absolute http', 'http://evil.com'],
    ['absolute https', 'https://evil.com'],
    ['protocol-relative', '//evil.com'],
    ['protocol-relative, triple', '///evil.com'],
    ['backslash variant', '/\\evil.com'],
    ['scheme after slash', '/javascript:alert(1)'],
    ['data URL', 'data:text/html,<script>'],
    ['javascript scheme', 'javascript:alert(1)'],
    ['no leading slash', 'projects/abc'],
    ['empty', ''],
    ['tab smuggling', '/\tevil'],
    ['newline smuggling', '/\nevil'],
    ['leading space', ' /projects'],
  ])('rejects %s', (_label, v) => {
    expect(isSafeRedirect(v)).toBe(false)
  })

  it('rejects null and undefined', () => {
    expect(isSafeRedirect(null)).toBe(false)
    expect(isSafeRedirect(undefined)).toBe(false)
  })
})

describe('resolveRedirect', () => {
  const at = (qs: string) => resolveRedirect(new URLSearchParams(qs))

  it('honours a safe next', () => {
    expect(at('next=/projects/abc')).toBe('/projects/abc')
  })

  it('falls back to Home for a hostile next', () => {
    expect(at('next=https://evil.com')).toBe('/')
    expect(at('next=//evil.com')).toBe('/')
  })

  it('accepts returnTo, which is what AuthGate emits', () => {
    expect(at('returnTo=%2Fworkspace%2F1%2Fprojects')).toBe('/workspace/1/projects')
  })

  it('prefers next over returnTo when both are present', () => {
    expect(at('next=/a&returnTo=/b')).toBe('/a')
  })

  it('falls through to returnTo when next is unsafe, rather than to Home', () => {
    expect(at('next=//evil.com&returnTo=/safe')).toBe('/safe')
  })

  it('decodes percent-encoded values before judging them', () => {
    // %2F%2Fevil.com decodes to //evil.com and must still be rejected.
    expect(at('next=%2F%2Fevil.com')).toBe('/')
  })

  it('does not throw on malformed percent-encoding', () => {
    expect(() => at('next=%E0%A4%A')).not.toThrow()
    expect(at('next=%E0%A4%A')).toBe('/')
  })

  it('returns Home when nothing is supplied', () => {
    expect(at('')).toBe('/')
  })
})
