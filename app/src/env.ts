/**
 * Typed accessor for VITE_ env vars. Fails loudly on missing values so a
 * misconfigured deploy doesn't ship with silent undefined values.
 */

function required(name: string, value: string | undefined): string {
  if (!value) throw new Error(`Missing required env var: ${name}`)
  return value
}

export const env = {
  supabaseUrl: required('VITE_SUPABASE_URL', import.meta.env.VITE_SUPABASE_URL),
  supabaseAnonKey: required('VITE_SUPABASE_ANON_KEY', import.meta.env.VITE_SUPABASE_ANON_KEY),
  isDev: import.meta.env.DEV,
} as const
