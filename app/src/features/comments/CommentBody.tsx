import { parseMentions } from './parseMentions'
import type { Participant } from '@/features/participants/queries'

/**
 * Renders a comment body with @-mentions rendered as inline chips.
 * Body is stored plain; parsing happens at display time (APP 005 freeze).
 */
export function CommentBody({
  body,
  participants,
}: {
  body: string
  participants: Participant[]
}) {
  const tokens = parseMentions(body, participants)
  return (
    <div className="whitespace-pre-wrap break-words text-sm text-[--color-text]">
      {tokens.map((t, i) => {
        if (t.kind === 'mention') {
          return (
            <span
              key={i}
              className="mx-0.5 inline-flex items-baseline rounded bg-[--color-state-open-bg] px-1 text-[--color-state-open]"
              title={t.participant.email}
            >
              {t.text}
            </span>
          )
        }
        return <span key={i}>{t.text}</span>
      })}
    </div>
  )
}
