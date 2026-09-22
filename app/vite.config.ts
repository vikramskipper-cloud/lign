import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { fileURLToPath, URL } from 'node:url'
import { readFileSync } from 'node:fs'

// Surfaced as the build string on the sign-in page. Falls back to '' so the
// suffix can be omitted entirely when there is nothing meaningful to show.
const pkgVersion: string = JSON.parse(
  readFileSync(new URL('./package.json', import.meta.url), 'utf8'),
).version ?? ''

export default defineConfig({
  define: {
    __APP_VERSION__: JSON.stringify(
      process.env.VITE_BUILD_ID ?? process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 7) ?? pkgVersion,
    ),
  },
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  server: { port: 5173 },
})
