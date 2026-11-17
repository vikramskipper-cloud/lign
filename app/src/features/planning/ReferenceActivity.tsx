import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useId,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { useBlocker } from 'react-router'
export const ReferenceSaving = createContext(false)
export const ReferenceUnsaved = createContext(false)
export const ReferenceActivity = createContext<(delta: number) => void>(
  () => {},
)
const ReferenceDrafts = createContext<(id: string, dirty: boolean) => void>(
  () => {},
)
export function useReferenceDirty(dirty: boolean) {
  const id = useId(),
    register = useContext(ReferenceDrafts)
  useEffect(() => {
    register(id, dirty)
    return () => register(id, false)
  }, [id, dirty, register])
  return () => register(id, false)
}
/** Guard both incomplete edits and the upload -> file registration transaction. */
export function ReferenceSaveGuard({ children }: { children: ReactNode }) {
  const count = useRef(0),
    drafts = useRef(new Set<string>()),
    [active, setActive] = useState(0),
    [dirty, setDirty] = useState(false)
  const activity = useCallback((delta: number) => {
    count.current = Math.max(0, count.current + delta)
    setActive(count.current)
  }, [])
  const register = useCallback((id: string, value: boolean) => {
    if (value) drafts.current.add(id)
    else drafts.current.delete(id)
    setDirty(drafts.current.size > 0)
  }, [])
  const blocker = useBlocker(() => count.current > 0 || drafts.current.size > 0)
  useEffect(() => {
    if (blocker.state === 'blocked') {
      if (
        window.confirm(
          count.current
            ? 'A reference save is in progress. Leave this page?'
            : 'Discard unsaved reference changes?',
        )
      )
        blocker.proceed()
      else blocker.reset()
    }
  }, [blocker])
  useEffect(() => {
    if (!active && !dirty) return
    const warn = (e: BeforeUnloadEvent) => {
      e.preventDefault()
      e.returnValue = ''
    }
    window.addEventListener('beforeunload', warn)
    return () => window.removeEventListener('beforeunload', warn)
  }, [active, dirty])
  return (
    <ReferenceSaving.Provider value={active > 0}>
      <ReferenceUnsaved.Provider value={dirty}>
        <ReferenceActivity.Provider value={activity}>
          <ReferenceDrafts.Provider value={register}>
            {children}
          </ReferenceDrafts.Provider>
        </ReferenceActivity.Provider>
      </ReferenceUnsaved.Provider>
    </ReferenceSaving.Provider>
  )
}
