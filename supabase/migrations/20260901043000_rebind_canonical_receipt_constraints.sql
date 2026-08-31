-- Forward-only constraint convergence for canonical release receipts.
-- Historical rows are preserved as evidence. Rebound CHECK constraints are
-- NOT VALID so existing recovery-era rows are grandfathered while every new
-- row must use the current canonical repository and Vercel team identities.

do $$
declare
  constraint_row record;
  rebound_definition text;
begin
  for constraint_row in
    select
      namespace.nspname as schema_name,
      relation.relname as table_name,
      constraint_def.conname as constraint_name,
      pg_get_constraintdef(constraint_def.oid, true) as definition
    from pg_constraint constraint_def
    join pg_class relation on relation.oid = constraint_def.conrelid
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where constraint_def.contype = 'c'
      and namespace.nspname = 'private'
      and relation.relname in (
        'canonical_supabase_release_receipts',
        'canonical_vercel_rehearsal_receipts'
      )
      and (
        pg_get_constraintdef(constraint_def.oid, true) like '%banataosystems/Pandoras-box%'
        or pg_get_constraintdef(constraint_def.oid, true) like '%team_IcdJUnzLi5wUN1GD8ALHyjF7%'
      )
  loop
    rebound_definition := replace(
      constraint_row.definition,
      'banataosystems/Pandoras-box',
      'pandora-rvw-314296438-20260820/pandoras-box'
    );
    rebound_definition := replace(
      rebound_definition,
      'team_IcdJUnzLi5wUN1GD8ALHyjF7',
      'team_3yw1CN59ce4pj5SwyQGCAqN3'
    );

    execute format(
      'alter table %I.%I drop constraint %I',
      constraint_row.schema_name,
      constraint_row.table_name,
      constraint_row.constraint_name
    );
    execute format(
      'alter table %I.%I add constraint %I %s not valid',
      constraint_row.schema_name,
      constraint_row.table_name,
      constraint_row.constraint_name,
      rebound_definition
    );
  end loop;

  if exists (
    select 1
    from pg_constraint constraint_def
    join pg_class relation on relation.oid = constraint_def.conrelid
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where constraint_def.contype = 'c'
      and namespace.nspname = 'private'
      and relation.relname in (
        'canonical_supabase_release_receipts',
        'canonical_vercel_rehearsal_receipts'
      )
      and (
        pg_get_constraintdef(constraint_def.oid, true) like '%banataosystems/Pandoras-box%'
        or pg_get_constraintdef(constraint_def.oid, true) like '%team_IcdJUnzLi5wUN1GD8ALHyjF7%'
      )
  ) then
    raise exception 'legacy canonical receipt constraints remain active';
  end if;
end
$$;
