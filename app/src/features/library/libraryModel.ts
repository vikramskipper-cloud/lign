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

export const collectionExamples: Record<
  LibraryCategory,
  { name: string; purpose: string; items: string[]; tags: string[] }
> = {
  inspiration: {
    name: 'Calm natural palettes',
    purpose: 'Help the team explore a consistent visual direction.',
    items: [
      'Images showing the palette and style',
      'Links to examples with source credits',
      'A note explaining what makes the direction useful',
    ],
    tags: ['natural', 'calm', 'neutral'],
  },
  materials_products: {
    name: 'Warm timber finishes',
    purpose: 'Help the team choose suitable finishes across projects.',
    items: [
      'Finish photographs or material swatches',
      'Specifications and supplier links',
      'Notes on suitable applications and care',
    ],
    tags: ['timber', 'warm tones', 'finishes'],
  },
  details_solutions: {
    name: 'Proven connection details',
    purpose: 'Reuse a proven technical solution.',
    items: [
      'Detail drawings or assembly diagrams',
      'An explanation of the problem solved',
      'Notes on dimensions, constraints and suitable uses',
    ],
    tags: ['connections', 'assembly', 'proven detail'],
  },
  templates_guides: {
    name: 'Design review checklist',
    purpose: 'Give the team a repeatable starting point.',
    items: [
      'A reusable checklist or document',
      'Instructions for adapting it',
      'An example showing how it can be used',
    ],
    tags: ['review', 'checklist', 'team guide'],
  },
}
