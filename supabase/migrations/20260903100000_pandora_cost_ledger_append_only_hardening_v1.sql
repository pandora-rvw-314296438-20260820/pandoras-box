
begin;

revoke update, delete, truncate, references, trigger
  on table public.pandora_cost_entries
  from public, anon, authenticated, service_role;

grant select, insert
  on table public.pandora_cost_entries
  to service_role;

drop trigger if exists pandora_cost_entries_block_truncate
  on public.pandora_cost_entries;

create trigger pandora_cost_entries_block_truncate
before truncate on public.pandora_cost_entries
for each statement
execute function private.pandora_control_plane_prevent_history_mutation();

do $guard$
begin
  if has_table_privilege('service_role', 'public.pandora_cost_entries', 'UPDATE')
    or has_table_privilege('service_role', 'public.pandora_cost_entries', 'DELETE')
    or has_table_privilege('service_role', 'public.pandora_cost_entries', 'TRUNCATE')
    or has_table_privilege('service_role', 'public.pandora_cost_entries', 'REFERENCES')
    or has_table_privilege('service_role', 'public.pandora_cost_entries', 'TRIGGER') then
    raise exception 'PANDORA_COST_LEDGER_APPEND_ONLY_PRIVILEGE_DRIFT';
  end if;

  if not has_table_privilege('service_role', 'public.pandora_cost_entries', 'SELECT')
    or not has_table_privilege('service_role', 'public.pandora_cost_entries', 'INSERT') then
    raise exception 'PANDORA_COST_LEDGER_REQUIRED_PRIVILEGE_MISSING';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'pandora_cost_entries'
      and t.tgname = 'pandora_cost_entries_block_truncate'
      and not t.tgisinternal
  ) then
    raise exception 'PANDORA_COST_LEDGER_TRUNCATE_GUARD_MISSING';
  end if;
end
$guard$;

commit;
