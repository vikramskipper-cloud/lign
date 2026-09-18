-- Full object inventory of the public schema, consumed by
-- ops/audit_schema_provenance.py.
--
--   psql "$SUPABASE_DB_URL" -At -F$'\t' -f ops/schema_inventory.sql > /tmp/inventory.tsv
--   ops/audit_schema_provenance.py /tmp/inventory.tsv
--
-- Columns: kind, name, parent, def
--   TABLE    -> parent '', def = column list
--   POLICY   -> parent = table,  def = cmd/roles/using/check
--   TRIGGER  -> parent = table,  def = pg_get_triggerdef
--   INDEX    -> parent = table,  def = indexdef
--   FUNCTION -> parent = identity args, def = md5(prosrc)
--
-- Target project: hsfporioghapwghrvvzd (Lign). Never nuesync.

select kind, name, parent, regexp_replace(coalesce(def,''), '[\n\t ]+', ' ', 'g') as def
from (
select 'TABLE' as kind, c.relname as name, ''::text as parent,
       string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ', ' order by a.attnum) as def
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
where n.nspname = 'public' and c.relkind = 'r'
group by c.relname
union all
select 'POLICY', policyname, tablename,
       cmd || ' roles=' || array_to_string(roles, '+') ||
       ' using=' || coalesce(qual, '-') || ' check=' || coalesce(with_check, '-')
from pg_policies where schemaname = 'public'
union all
select 'TRIGGER', t.tgname, c.relname, pg_get_triggerdef(t.oid)
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname in ('public', 'auth') and not t.tgisinternal
union all
select 'INDEX', indexname, tablename, indexdef from pg_indexes where schemaname = 'public'
union all
select 'FUNCTION', p.proname, pg_get_function_identity_arguments(p.oid), md5(p.prosrc)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
) s
order by 1, 2, 3;
