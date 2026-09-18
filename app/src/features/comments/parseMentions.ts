import type { Participant } from '@/features/participants/queries'

export type MentionToken =
  | { kind: 'text'; text: string }
  | { kind: 'mention'; text: string; participant: Participant }

/**
 * Split a comment body into text/mention tokens.
 *
 * Rules (per APP 005 freeze):
 *   - Body is plain text; no hidden markers.
 *   - `@` followed by an active participant's displayName matches.
 *   - Longest-match wins ("@Alice B" preferred over "@Alice" when both are
 *     participants).
 *   - Duplicate displayNames → rendered as plain text (we don't guess).
 *   - Unrecognised `@`-tokens fall through as plain text.
 */
export function parseMentions(body: string, participants: Participant[]): MentionToken[] {
  if (!body) return []
  if (participants.length === 0) return [{ kind: 'text', text: body }]

  const nameCounts = new Map<string, number>()
  for (const p of participants) {
    nameCounts.set(p.displayName, (nameCounts.get(p.displayName) ?? 0) + 1)
  }
  const uniqueByName = new Map<string, Participant>()
  for (const p of participants) {
    if ((nameCounts.get(p.displayName) ?? 0) === 1) {
      uniqueByName.set(p.displayName, p)
    }
  }
  const names = Array.from(uniqueByName.keys()).sort((a, b) => b.length - a.length)

  const tokens: MentionToken[] = []
  let i = 0
  let buf = ''

  const pushBuf = () => {
    if (buf) {
      tokens.push({ kind: 'text', text: buf })
      buf = ''
    }
  }

  while (i < body.length) {
    if (body[i] === '@') {
      let matched: string | undefined
      for (const name of names) {
        if (body.startsWith(name, i + 1)) {
          matched = name
          break
        }
      }
      if (matched) {
        const participant = uniqueByName.get(matched)!
        pushBuf()
        tokens.push({ kind: 'mention', text: `@${matched}`, participant })
        i += 1 + matched.length
        continue
      }
    }
    buf += body[i]
    i += 1
  }
  pushBuf()
  return tokens
}
