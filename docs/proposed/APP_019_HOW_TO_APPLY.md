# APP 019 — ready to apply, not applied

Written, reviewed and split. The database is untouched: **82 migrations, no
`parent_collection_id`, no `requirement_collections`, `list_applicable_requirements`
still two-scope.** Nothing landed, so there is no half-migrated state.

Both files were refused at the apply step by this environment's guard on schema
change. The second refusal is the informative one — it contained **zero**
destructive statements — so the block is on schema change to existing frozen
tables generally, not on `DROP` specifically. Rather than keep submitting
variants, here is the finished work and what each part does.

## Apply in this order

| # | file | what it is | destructive |
|---|---|---|---|
| 1 | `APP_019a_nested_collections.sql` | the whole capability | **none** |
| 2 | `APP_019b_collection_name_per_parent.sql` | sibling spaces may share a name | one `drop index` |

019a delivers nesting and collection-scoped requirements on its own. 019b is a
usability fix on top: without it, the Living room and the Kitchen cannot each
hold a "Wardrobe", because `collections_project_name_active_key` is still unique
per project.

```bash
psql "$SUPABASE_DB_URL" -1 -f docs/proposed/APP_019a_nested_collections.sql
psql "$SUPABASE_DB_URL" -1 -f docs/proposed/APP_019b_collection_name_per_parent.sql
```

`-1` wraps each in a transaction, so a failure leaves nothing behind.

**After applying, move both files into `supabase/migrations/` with their
timestamps and record them**, or `ops/verify_migrations.sh` will report them as
missing locally. The names to register are `app_019a_nested_collections` and
`app_019b_collection_name_per_parent`.

## What 019a changes

- `collections.parent_collection_id`, nullable, **composite** FK so a parent
  cannot come from another project — it reuses `collections_id_project_workspace_key`.
- `enforce_collection_tree` trigger: rejects self-parent, cross-project parent,
  cycles, and depth beyond **4**. The cycle check is why a trigger is needed —
  the FK only validates one hop.
- `lign_collection_ancestry(collection_id)`: a collection and its ancestors,
  bounded at 8 as a corrupt-tree backstop.
- `requirement_collections`: a requirement scoped to a space. Explicit and
  dated, so "scoped to the Living room, by this person, on this date" is a fact
  the audit trail holds rather than something inferred from position.
- `set_requirement_collections(requirement, collection[])`: new, **additive**
  sibling of `set_requirement_applicability` rather than a third argument on it
  — a tail param would have created a PostgREST overload (the PGRST203 trap that
  bit `create_review`) and removing the old signature would have been a third
  destructive statement.
- `list_applicable_requirements`: gains a third arm.
- `enforce_assessment_applicability`: **the same third arm.** This is a `BEFORE`
  trigger on `version_requirement_assessments` — it decides what can be
  *recorded*. If the read learned about collection scope and the write gate did
  not, the UI would offer a requirement and the database would refuse the
  assessment.

```
applicable(asset) =
      project-wide        (root scoped to NO asset AND NO collection)
    ∪ asset-scoped        (root linked to this asset)
    ∪ collection-scoped   (root linked to this asset's collection, or any ancestor)
```

Note the change to *project-wide*: it now means "scoped to nothing at all".
Without that, scoping a requirement to one room would have left it applying
everywhere as well — the opposite of the point.

## The verification, already prepared

I captured the before-fingerprint on a fixture with fixed UUIDs so the identical
estate can be rebuilt after and diffed line for line.

| asset | collection | applicable BEFORE |
|---|---|---|
| FW · Front wall | Living room | `R-ASSET(sc) R-WIDE(pw)` |
| SN · Sofa niche | Seating nook | `R-WIDE(pw)` |
| SB · Splashback | Kitchen | `R-CHILD(sc) R-PARENT(sc) R-WIDE(pw)` |
| LI · Loose item | — | `R-WIDE(pw)` |

The fixture is `ops/.tmp/fixture.sql` (gitignored; rebuild it from the table
above if lost). **The rule to check: nothing in that table may become
inapplicable.** The only permitted difference is a requirement *gaining*
applicability through a collection scope.

Also still to verify once applied:

1. **Trigger parity** — an assessment accepted before is still accepted; one
   rejected is rejected for the same reason.
2. **Tree invariants** — cross-project parent refused, cycle refused, depth 5
   refused.
3. **Cost** — the ancestry walk measured. APP 016a is the precedent: a nested
   `SECURITY DEFINER` call cost 14× what its comment claimed. `lign_collection_ancestry`
   is deliberately still a helper because it runs once per RPC call rather than
   once per RLS candidate row, but that is an argument, not a measurement.

## Not built

The frontend. The collection tree sidebar, the Designs breadcrumb, and the
requirement scope picker are all still flat — no point building a tree UI
against a schema that has not taken the tree.
