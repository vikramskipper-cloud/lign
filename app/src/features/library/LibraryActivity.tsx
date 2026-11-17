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
export const LibrarySaving = createContext(false)
export const LibraryUnsaved = createContext(false)
export const LibraryActivity = createContext<(delta: number) => void>(() => {})
const LibraryDrafts = createContext<(id: string, dirty: boolean) => void>(
  () => {},
)
export function useLibraryDirty(dirty: boolean) {
  const id = useId(),
    register = useContext(LibraryDrafts)
  useEffect(() => {
    register(id, dirty)
    return () => register(id, false)
  }, [id, dirty, register])
  return () => register(id, false)
}
/** Guard both incomplete edits and the upload -> file registration transaction. */
export function LibrarySaveGuard({ children }: { children: ReactNode }) {
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
            ? 'A library save is in progress. Leave this page?'
            : 'Discard unsaved library changes?',
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
    <LibrarySaving.Provider value={active > 0}>
      <LibraryUnsaved.Provider value={dirty}>
        <LibraryActivity.Provider value={activity}>
          <LibraryDrafts.Provider value={register}>
            {children}
          </LibraryDrafts.Provider>
        </LibraryActivity.Provider>
      </LibraryUnsaved.Provider>
    </LibrarySaving.Provider>
  )
}
