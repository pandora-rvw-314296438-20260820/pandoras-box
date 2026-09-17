-- Harden: anon must not hold write/TRUNCATE/REFERENCES/TRIGGER on public tables.
-- TRUNCATE bypasses RLS; these grants are default leftovers and are not required for PostgREST.
do $$ 
declare
  r record;
begin
  for r in
    select table_schema, table_name
    from information_schema.role_table_grants
    where table_schema = 'public'
      and grantee = 'anon'
      and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')
    group by 1, 2
  loop
    execute format(
      'revoke insert, update, delete, truncate, references, trigger on table %I.%I from anon',
      r.table_schema,
      r.table_name
    );
  end loop;

  -- Also strip TRUNCATE/REFERENCES/TRIGGER from authenticated (unused by PostgREST; TRUNCATE bypasses RLS).
  for r in
    select table_schema, table_name
    from information_schema.role_table_grants
    where table_schema = 'public'
      and grantee = 'authenticated'
      and privilege_type in ('TRUNCATE','REFERENCES','TRIGGER')
    group by 1, 2
  loop
    execute format(
      'revoke truncate, references, trigger on table %I.%I from authenticated',
      r.table_schema,
      r.table_name
    );
  end loop;
end $$;

