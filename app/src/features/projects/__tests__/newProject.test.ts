import { describe, it, expect } from 'vitest'
import { CODE_RE, EMAIL_RE, deriveCode, suggestCode } from '../newProject'

describe('deriveCode', () => {
  it('takes the initials of the first three words', () => {
    expect(deriveCode('Northgate Flagship')).toBe('NF')
    expect(deriveCode('Northgate Flagship Tower')).toBe('NFT')
    expect(deriveCode('Northgate Flagship Tower Phase Two')).toBe('NFT')
  })

  it('falls back to the first three letters of a single word', () => {
    expect(deriveCode('Northgate')).toBe('NOR')
    expect(deriveCode('Ab')).toBe('AB')
  })

  it('splits on dashes, slashes and underscores, not only spaces', () => {
    expect(deriveCode('Northgate-Flagship')).toBe('NF')
    // Three words once _ and / are separators, so three initials.
    expect(deriveCode('north_gate/flagship')).toBe('NGF')
  })

  it('ignores punctuation-only fragments rather than emitting empty letters', () => {
    expect(deriveCode('Northgate & Flagship')).toBe('NF')
    expect(deriveCode('  ')).toBe('')
    expect(deriveCode('!!!')).toBe('')
  })

  it('always produces something the code field will accept', () => {
    for (const name of ['Northgate Flagship', 'Ab', '2024 Riverside', 'x']) {
      const code = deriveCode(name)
      if (code) expect(CODE_RE.test(code)).toBe(true)
    }
  })
})

describe('suggestCode', () => {
  it('appends 2 to an unnumbered code', () => {
    expect(suggestCode('NGF')).toBe('NGF2')
  })

  it('increments an existing trailing number instead of appending', () => {
    expect(suggestCode('NGF2')).toBe('NGF3')
    expect(suggestCode('NGF19')).toBe('NGF20')
  })

  it('stays within the 16-character limit the server enforces', () => {
    expect(suggestCode('ABCDEFGHIJKLMNOP').length).toBeLessThanOrEqual(16)
  })
})

describe('CODE_RE', () => {
  it('accepts uppercase letters, digits and dashes', () => {
    for (const ok of ['N', 'NGF', 'NGF-2', '2024', 'A-B-C']) {
      expect(CODE_RE.test(ok)).toBe(true)
    }
  })

  it('rejects what the server rejects', () => {
    // Mirrors ^[A-Z0-9][A-Z0-9-]{0,15}$ in create_project_full.
    for (const bad of ['', 'ngf', '-NGF', 'N GF', 'NGF!', 'ABCDEFGHIJKLMNOPQ']) {
      expect(CODE_RE.test(bad)).toBe(false)
    }
  })
})

describe('EMAIL_RE', () => {
  it('accepts ordinary addresses', () => {
    for (const ok of ['a@b.co', 'client@acme.example', 'first.last+tag@sub.domain.org']) {
      expect(EMAIL_RE.test(ok)).toBe(true)
    }
  })

  it('rejects the shapes people actually mistype', () => {
    for (const bad of ['', 'client', 'client@', '@acme.com', 'client@acme', 'a b@c.com']) {
      expect(EMAIL_RE.test(bad)).toBe(false)
    }
  })
})
