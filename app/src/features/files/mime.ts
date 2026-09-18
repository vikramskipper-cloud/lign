import {
  Archive,
  Code2,
  File as FileIcon,
  FileAudio,
  FileImage,
  FileText,
  FileVideo,
  type LucideIcon,
} from 'lucide-react'

export type ViewerKind =
  | 'image'
  | 'pdf'
  | 'video'
  | 'audio'
  | 'text'
  | 'download-only'

/** Which viewer component handles this mime type. */
export function viewerFor(mime: string | null | undefined): ViewerKind {
  if (!mime) return 'download-only'
  const m = mime.toLowerCase()
  if (m.startsWith('image/')) return 'image'
  if (m === 'application/pdf') return 'pdf'
  if (m.startsWith('video/')) return 'video'
  if (m.startsWith('audio/')) return 'audio'
  if (
    m.startsWith('text/') ||
    m === 'application/json' ||
    m === 'application/xml' ||
    m === 'application/x-yaml' ||
    m === 'application/yaml'
  ) {
    return 'text'
  }
  return 'download-only'
}

/** Human-readable short label ("PDF", "IFC", "DWG", "PNG"). Used on mime chips. */
export function labelFor(mime: string | null | undefined, filename?: string): string {
  const extFromName = filename?.match(/\.([a-z0-9]{1,6})$/i)?.[1]?.toUpperCase()
  if (mime) {
    const m = mime.toLowerCase()
    if (m === 'application/pdf') return 'PDF'
    if (m === 'image/svg+xml') return 'SVG'
    if (m.startsWith('image/')) return m.slice('image/'.length).toUpperCase()
    if (m.startsWith('video/')) return m.slice('video/'.length).toUpperCase()
    if (m.startsWith('audio/')) return m.slice('audio/'.length).toUpperCase()
    if (m === 'application/json') return 'JSON'
    if (m === 'application/zip' || m === 'application/x-7z-compressed') return 'ZIP'
    if (m.startsWith('text/')) return m.slice('text/'.length).toUpperCase()
  }
  return extFromName ?? 'FILE'
}

/** Icon component to render for a mime family. */
export function iconFor(mime: string | null | undefined): LucideIcon {
  if (!mime) return FileIcon
  const m = mime.toLowerCase()
  if (m.startsWith('image/')) return FileImage
  if (m === 'application/pdf') return FileText
  if (m.startsWith('video/')) return FileVideo
  if (m.startsWith('audio/')) return FileAudio
  if (m === 'application/zip' || m === 'application/x-7z-compressed') return Archive
  if (
    m.startsWith('text/') ||
    m === 'application/json' ||
    m === 'application/xml' ||
    m === 'application/x-yaml' ||
    m === 'application/yaml'
  ) {
    return Code2
  }
  return FileIcon
}

const UNITS = ['B', 'KB', 'MB', 'GB', 'TB'] as const
export function formatBytes(n: number | null | undefined): string {
  if (n == null) return ''
  if (n < 1024) return `${n} B`
  let value = n
  let i = 0
  while (value >= 1024 && i < UNITS.length - 1) {
    value /= 1024
    i++
  }
  return `${value.toFixed(value >= 10 || i === 0 ? 0 : 1)} ${UNITS[i]}`
}

export const MAX_UPLOAD_BYTES = 500 * 1024 * 1024

export const DENYLISTED_MIMES = new Set<string>([
  'application/x-msdownload',
  'application/x-msdos-program',
  'application/x-executable',
  'application/x-sh',
  'application/x-shellscript',
  'text/x-shellscript',
])

export type FileRole = 'primary' | 'reference' | 'spec' | 'source' | 'export' | 'other'

export const ROLE_LABELS: Record<FileRole, string> = {
  primary: 'Main preview',
  reference: 'Reference',
  spec: 'Specification',
  source: 'Source file',
  export: 'Export',
  other: 'Other',
}
export const ROLES: FileRole[] = ['primary', 'reference', 'spec', 'source', 'export', 'other']
