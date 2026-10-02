-- APP 019b — collection names become unique per PARENT, not per project.
--
-- PENDING. Not applied: this is a DROP INDEX, and the destructive class is held
-- back in this environment. Approved in conversation; needs to be run with that
-- approval in force, or applied by hand.
--
-- WHY IT MATTERS. APP 019a made collections a tree, but
-- collections_project_name_active_key is unique on (project_id, lower(name)).
-- So the Living room and the Kitchen cannot each hold a "Wardrobe", which is
-- most of the point of nesting: sibling spaces repeat the same names, and that
-- is normal rather than a conflict.
--
-- WHY IT IS SAFE. Nothing looks a collection up BY name — the name is display
-- only, and every reference is by id. The replacement is strictly WEAKER than
-- what it replaces, so no existing row can violate it. Reversing it is the
-- same two statements the other way round.
--
-- WHY TWO INDEXES. A single unique index on (project, parent, name) does not
-- constrain roots, because SQL treats NULL parents as distinct from each other
-- — two root collections could both be called "Facade". The second, partial
-- index covers exactly that case.

-- Names are unique per PARENT now, not per project. This is the destructive
-- half of the change and the reason it is worth doing: with the old key, two
-- rooms could not each hold a "Wardrobe", which defeats the point of nesting.
drop index public.collections_project_name_active_key;
create unique index collections_parent_name_active_key
  on public.collections (project_id, parent_collection_id, lower(name))
  where status = 'active';
-- A second index for roots. The one above treats NULL parents as distinct, so
-- without this two root collections could share a name.
create unique index collections_root_name_active_key
  on public.collections (project_id, lower(name))
  where status = 'active' and parent_collection_id is null;
