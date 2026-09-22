/**
 * Route module for React Router's `lazy`, which wants `Component` and
 * `handle` from one dynamic import. Without this the handle would have to be
 * imported statically, which would pull the whole screen into the initial
 * bundle and defeat the split.
 */
export { ReleaseDetailScreen as Component, ReleaseDetailHandle as handle } from '@/features/releases/ReleaseDetailScreen'
