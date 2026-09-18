import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'

const BUCKET = 'lign-files'

export type SignedUrlPurpose = 'view' | 'thumb'

const TTL: Record<SignedUrlPurpose, number> = {
  view: 15 * 60, // 15 min (D7)
  thumb: 60 * 60, // 60 min (D7)
}

interface Options {
  fileId: string | undefined
  storageRef: string | undefined
  purpose?: SignedUrlPurpose
  enabled?: boolean
}

/**
 * Issues a Supabase Storage signed URL for a file the caller can read.
 * RLS on storage.objects (via lign_can_download_file) is enforced at issue time.
 * Cached in React Query so the same URL is reused within its TTL; auto-refreshes
 * 30s before expiry.
 */
export function useSignedUrl({ fileId, storageRef, purpose = 'view', enabled = true }: Options) {
  const ttl = TTL[purpose]
  return useQuery({
    queryKey: fileId ? qk.signedUrl(fileId, purpose) : ['signed-url', 'none', purpose],
    enabled: enabled && Boolean(fileId && storageRef),
    staleTime: (ttl - 60) * 1000,
    gcTime: ttl * 1000,
    refetchInterval: (ttl - 30) * 1000,
    refetchIntervalInBackground: false,
    queryFn: async (): Promise<string> => {
      const { data, error } = await supabase.storage
        .from(BUCKET)
        .createSignedUrl(storageRef as string, ttl)
      if (error) throw error
      if (!data?.signedUrl) throw new Error('No signed URL returned')
      return data.signedUrl
    },
  })
}
