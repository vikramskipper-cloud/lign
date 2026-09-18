import * as React from 'react'
import { Outlet, useMatches } from 'react-router'
import { TopBar } from '@/shell/TopBar'
import { NavRail } from '@/shell/NavRail'
import { AsyncBoundary } from '@/ui/async-boundary'
import { ErrorBoundary } from '@/ui/error-boundary'
import { cn } from '@/lib/cn'

/**
 * Determine which nav mode to render based on which layout is active.
 * ProjectLayout tags its match with handle.navMode = 'project'.
 */
function useNavMode(): 'workspace' | 'project' | 'none' {
  const matches = useMatches()
  for (let i = matches.length - 1; i >= 0; i--) {
    const handle = matches[i]?.handle as { navMode?: 'workspace' | 'project' | 'none' } | undefined
    if (handle?.navMode) return handle.navMode
  }
  return 'none'
}

/**
 * The outer chrome shared by every authenticated route:
 *   TopBar (breadcrumb + switcher + user menu)
 *   NavRail (workspace or project mode)
 *   <Outlet /> (route content)
 *
 * Responsive:
 *   - < 768px: NavRail becomes a drawer opened from the top bar.
 *   - 768–1024px: NavRail collapses to icon-only.
 *   - >=1024px: full labels.
 */
export function RootLayout() {
  const navMode = useNavMode()
  const [drawerOpen, setDrawerOpen] = React.useState(false)
  const [collapsed, setCollapsed] = React.useState(() => window.innerWidth < 1024)

  React.useEffect(() => {
    const onResize = () => {
      const w = window.innerWidth
      setCollapsed(w >= 768 && w < 1024)
      if (w >= 768) setDrawerOpen(false)
    }
    window.addEventListener('resize', onResize)
    return () => window.removeEventListener('resize', onResize)
  }, [])

  return (
    <ErrorBoundary>
      <div className="flex h-full min-h-screen flex-col bg-[--color-bg]">
        <TopBar onOpenNav={navMode !== 'none' ? () => setDrawerOpen(true) : undefined} />
        <div className="flex flex-1 overflow-hidden">
          {navMode !== 'none' && (
            <>
              {/* Desktop / tablet rail */}
              <aside className="hidden md:block">
                <NavRail mode={navMode} collapsed={collapsed} />
              </aside>
              {/* Mobile drawer */}
              {drawerOpen && (
                <div
                  className="fixed inset-0 z-40 md:hidden"
                  onClick={() => setDrawerOpen(false)}
                >
                  <div className="absolute inset-0 bg-black/40" />
                  <div
                    className="relative h-full w-64 shadow-[--shadow-md]"
                    onClick={(e) => e.stopPropagation()}
                  >
                    <NavRail mode={navMode} onNavigate={() => setDrawerOpen(false)} />
                  </div>
                </div>
              )}
            </>
          )}
          <main
            className={cn(
              'flex-1 overflow-auto',
              navMode === 'none' && 'w-full',
            )}
          >
            <AsyncBoundary>
              <Outlet />
            </AsyncBoundary>
          </main>
        </div>
      </div>
    </ErrorBoundary>
  )
}
