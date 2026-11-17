export const libraryCategories = [
  {
    id: 'inspiration',
    label: 'Inspiration',
    description: 'Styles, palettes and examples',
  },
  {
    id: 'materials_products',
    label: 'Materials & products',
    description: 'Materials, finishes and product information',
  },
  {
    id: 'details_solutions',
    label: 'Details & solutions',
    description: 'Technical details and proven methods',
  },
  {
    id: 'templates_guides',
    label: 'Templates & guides',
    description: 'Reusable documents and starting points',
  },
] as const
export type LibraryCategory = (typeof libraryCategories)[number]['id']
/** Interpret legacy metadata without rewriting immutable publication snapshots. */
export function libraryCategory(kind: string): LibraryCategory {
  switch (kind) {
    case 'template':
      return 'templates_guides'
    case 'moodboard':
    case 'references':
      return 'inspiration'
    case 'designs':
      return 'details_solutions'
    default:
      return kind as LibraryCategory
  }
}
export const libraryCategoryLabel = (kind: string) =>
  libraryCategories.find((c) => c.id === libraryCategory(kind))?.label ?? kind
export type LibraryLayout = 'grid' | 'list' | 'moodboard'
export function libraryLayout(value: string | null): LibraryLayout {
  return value === 'list' || value === 'moodboard' ? value : 'grid'
}
