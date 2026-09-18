import { QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider } from 'react-router/dom'
import { TooltipProvider } from '@/ui/tooltip'
import { Toaster } from 'sonner'
import { SessionProvider } from '@/auth/SessionProvider'
import { queryClient } from '@/lib/queryClient'
import { router } from '@/router'

export function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <SessionProvider>
        <TooltipProvider delayDuration={200}>
          <RouterProvider router={router} />
          <Toaster position="top-right" richColors closeButton />
        </TooltipProvider>
      </SessionProvider>
    </QueryClientProvider>
  )
}
