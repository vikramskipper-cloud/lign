-- APP 008 fix: install pg_trgm in the extensions schema to match project convention
-- and clear the extension_in_public advisor. The trigram index is dropped and
-- recreated with the fully-qualified operator classes.

drop index if exists public.requirements_title_desc_trgm_idx;

alter extension pg_trgm set schema extensions;

create index if not exists requirements_title_desc_trgm_idx
  on public.requirements
  using gin (title extensions.gin_trgm_ops, description extensions.gin_trgm_ops);
