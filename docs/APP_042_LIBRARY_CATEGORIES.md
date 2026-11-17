# APP 042 — Library categories and mood board layout

The Library now groups collections by purpose: **Inspiration**, **Materials & products**, **Details & solutions**, and **Templates & guides**. Collections group related items; items are files, links or notes. Flexible tags describe discipline, style and application. The create/edit form calls this a Collection category, explains the selected category, and defaults to Inspiration. Library item actions consistently say Item title, Item details, Add item, Edit item, Save item and Archive item. Project Reference boards retain their existing name and workflow.

Legacy categories remain readable without rewriting content or approved history:

| Previous category | Current category |
|---|---|
| References | Inspiration |
| Mood boards | Inspiration |
| Designs | Details & solutions |
| Templates | Templates & guides |

Materials & products is a new selectable category. Existing designs are interpreted as reusable detail/solution collections; active project designs are not automatically copied or moved into the Library. Authors/admins can revise and recategorise a collection using the existing approval process.

Mood board is an optional visual layout alongside Grid and List for **any** collection category. It arranges cards in columns and places images ahead of item captions while keeping documents, links, notes, editing and downloads accessible. Layout selection is a view preference carried in the URL and survives refresh. It does not modify a collection, its category or its publication; this is not a freeform canvas or export editor.

The additive migration `20261117040000_app_042_library_categories.sql` adds canonical category values to the existing constraint while retaining legacy values for compatibility. `lign_library_category(text)` maps legacy identifiers. `get_library_catalog` accepts canonical and legacy filters and adds a canonical `category` field; existing raw `kind` values and immutable nested publication metadata remain intact. The frontend normalises working and published metadata independently. Neither published snapshots nor saved collection rows are rewritten by this migration. Existing membership, author/admin access, review locking, version checks, immutable publication and file policies are retained.

Validation: `tests/access/library-categories.mjs` uses an isolated local organisation to check all new category saves/publications, legacy filter equivalence, immutable snapshots, pending revision category privacy, invalid categories and external access denial. Updated Library review/browser regressions exercise Materials & products, Templates & guides, item labels, mood board layout persistence, approved-only project import and desktop/mobile layouts. Build, bundle budget and existing 80 unit tests remain required.
