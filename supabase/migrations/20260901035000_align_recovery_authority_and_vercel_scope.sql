-- Forward-only authority convergence after repository recovery and Vercel team transfer.
-- Historical migrations remain immutable; active runtime definitions/configuration move to current authority.

do $$
declare
  fn record;
  definition text;
begin
  for fn in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.prokind in ('f','p')
      and n.nspname in ('public','private')
      and (
        pg_get_functiondef(p.oid) like '%banataosystems/Pandoras-box%'
        or pg_get_functiondef(p.oid) like '%banataosystems/pandoras-box-memory%'
        or pg_get_functiondef(p.oid) like '%team_IcdJUnzLi5wUN1GD8ALHyjF7%'
        or pg_get_functiondef(p.oid) like '%mbanatao-dc676069%'
      )
  loop
    definition := pg_get_functiondef(fn.oid);
    definition := replace(definition,
      'banataosystems/Pandoras-box',
      'pandora-rvw-314296438-20260820/pandoras-box');
    definition := replace(definition,
      'banataosystems/pandoras-box-memory',
      'pandora-rvw-314296438-20260820/pandoras-box-memory');
    definition := replace(definition,
      'team_IcdJUnzLi5wUN1GD8ALHyjF7',
      'team_3yw1CN59ce4pj5SwyQGCAqN3');
    definition := replace(definition, 'mbanatao-dc676069', 'mbanatao');
    execute definition;
  end loop;
end
$$;

update public.connector_installations
set configuration = jsonb_set(
      jsonb_set(
        jsonb_set(
          configuration,
          '{team_id}',
          to_jsonb('team_3yw1CN59ce4pj5SwyQGCAqN3'::text),
          true
        ),
        '{team_slug}',
        to_jsonb('mbanatao'::text),
        true
      ),
      '{project_repo_allowlist,prj_brg3BJDcHfSftHH84NhnFtDJAnDO}',
      to_jsonb('pandora-rvw-314296438-20260820/pandoras-box-memory'::text),
      true
    ),
    updated_at = now()
where provider = 'vercel'
  and status in ('pending','active');

update public.connector_installations
set configuration = jsonb_set(
      configuration,
      '{allowed_repositories}',
      (
        select jsonb_agg(value order by value)
        from (
          select distinct value
          from jsonb_array_elements_text(coalesce(configuration->'allowed_repositories','[]'::jsonb)) as x(value)
          where value not in ('banataosystems/Pandoras-box','banataosystems/pandoras-box-memory')
          union all select 'pandora-rvw-314296438-20260820/pandoras-box'
          union all select 'pandora-rvw-314296438-20260820/pandoras-box-memory'
        ) repos
      ),
      true
    ),
    updated_at = now()
where provider = 'github'
  and status in ('pending','active');

insert into public.pandora_runtime_provider_configs(provider, config_key, config_value, active)
values ('vercel', 'team_id', 'team_3yw1CN59ce4pj5SwyQGCAqN3', true)
on conflict (provider, config_key) do update
set config_value = excluded.config_value,
    active = excluded.active,
    updated_at = now();

-- Fail closed if an active execution function still carries an old authority literal.
do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.prokind in ('f','p')
      and n.nspname in ('public','private')
      and (
        pg_get_functiondef(p.oid) like '%banataosystems/Pandoras-box%'
        or pg_get_functiondef(p.oid) like '%banataosystems/pandoras-box-memory%'
        or pg_get_functiondef(p.oid) like '%team_IcdJUnzLi5wUN1GD8ALHyjF7%'
        or pg_get_functiondef(p.oid) like '%mbanatao-dc676069%'
      )
  ) then
    raise exception 'legacy Pandora authority remains in active database functions';
  end if;
end
$$;
