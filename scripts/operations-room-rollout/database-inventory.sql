-- Read-only catalogue inspection. Transport must bind the actual Supabase project.
-- Never use pg_stat estimates as row counts. Missing objects remain missing.
with expected_tables(name) as (
 values ('pandora_ops_project_bindings'),('pandora_ops_workspaces'),
 ('pandora_ops_workers'),('pandora_ops_tasks'),('pandora_ops_dependencies'),
 ('pandora_ops_leases'),('pandora_ops_dispatch_outbox'),('pandora_ops_events')
), expected_functions(schema_name,name,is_public) as (
 values
 ('public','pandora_ops_project_binding_v1',true),('public','pandora_ops_project_scope_v1',true),
 ('public','pandora_ops_initialize_v1',true),('public','pandora_ops_ingest_v1',true),
 ('public','pandora_ops_register_worker_v1',true),('public','pandora_ops_heartbeat_v1',true),
 ('public','pandora_ops_claim_v1',true),('public','pandora_ops_dispatch_v1',true),
 ('public','pandora_ops_reconcile_required_v1',true),('public','pandora_ops_control_v1',true),
 ('public','pandora_ops_snapshot_v1',true),('public','pandora_ops_handoff_v1',true),
 ('public','pandora_ops_verify_v1',true),('public','pandora_ops_recover_v1',true),
 ('public','pandora_ops_owner_request_v1',true),
 ('private','pandora_ops_event_v1',false),('private','pandora_ops_immutable_event_v1',false),
 ('private','pandora_ops_validate_spec_v1',false),('private','pandora_ops_settle_v1',false)
), role_ids as (
 select (select oid from pg_roles where rolname='anon') as anon,
 (select oid from pg_roles where rolname='authenticated') as authenticated,
 (select oid from pg_roles where rolname='service_role') as service_role
), table_rows as (
 select e.name,c.oid,c.relkind,c.relrowsecurity,r.*,
 case when c.oid is not null and r.anon is not null then
 has_table_privilege(r.anon,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
 or has_any_column_privilege(r.anon,c.oid,'SELECT,INSERT,UPDATE,REFERENCES') end as anon_access,
 case when c.oid is not null and r.authenticated is not null then
 has_table_privilege(r.authenticated,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
 or has_any_column_privilege(r.authenticated,c.oid,'SELECT,INSERT,UPDATE,REFERENCES') end as authenticated_access,
 case when c.oid is not null and r.service_role is not null then
 has_table_privilege(r.service_role,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
 or has_any_column_privilege(r.service_role,c.oid,'SELECT,INSERT,UPDATE,REFERENCES') end as service_access
 from expected_tables e cross join role_ids r
 left join pg_namespace n on n.nspname='private'
 left join pg_class c on c.relnamespace=n.oid and c.relname=e.name
), function_rows as (
 select e.schema_name,e.name,e.is_public,count(p.oid)::integer as overloads,
 bool_and(p.prosecdef) as security_definer,
 min(encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')) as body_sha256,
 bool_and(exists(select 1 from unnest(p.proconfig) cfg where cfg='search_path=""')) as pinned_search_path,
 bool_or(case when r.anon is not null then has_function_privilege(r.anon,p.oid,'EXECUTE') end) as anon_access,
 bool_or(case when r.authenticated is not null then has_function_privilege(r.authenticated,p.oid,'EXECUTE') end) as authenticated_access,
 bool_or(case when r.service_role is not null then has_function_privilege(r.service_role,p.oid,'EXECUTE') end) as service_access
 from expected_functions e cross join role_ids r
 left join pg_namespace n on n.nspname=e.schema_name
 left join pg_proc p on p.pronamespace=n.oid and p.proname=e.name
 group by e.schema_name,e.name,e.is_public
)
select jsonb_build_object(
 'observedAt',clock_timestamp(),
 'rolesReady',(select anon is not null and authenticated is not null and service_role is not null from role_ids),
 'migration',jsonb_build_object(
   'version','20260925101319',
   'count',(select count(*) from supabase_migrations.schema_migrations where version='20260925101319'),
   'name',(select name from supabase_migrations.schema_migrations where version='20260925101319'),
   'statementSha256',(select encode(sha256(convert_to(array_to_string(statements,E'\n'),'UTF8')),'hex') from supabase_migrations.schema_migrations where version='20260925101319'),
   'aliases',coalesce((select jsonb_agg(version order by version) from supabase_migrations.schema_migrations
     where name='pandora_operations_room_runtime_v1' and version<>'20260925101319'),'[]'::jsonb)),
 'tables',(select jsonb_agg(jsonb_build_object(
   'name',name,'exists',oid is not null,'kind',relkind,'rls',relrowsecurity,
   'anonAccess',anon_access,'authenticatedAccess',authenticated_access,'serviceRoleAccess',service_access
 ) order by name) from table_rows),
 'functions',(select jsonb_agg(jsonb_build_object(
   'schema',schema_name,'name',name,'overloads',overloads,'securityDefiner',security_definer,'bodySha256',body_sha256,
   'searchPathPinned',pinned_search_path,'anonExecute',anon_access,
   'authenticatedExecute',authenticated_access,'serviceRoleExecute',service_access
 ) order by schema_name,name) from function_rows),
 'pausedDefault',(select pg_get_expr(d.adbin,d.adrelid)='true' from pg_attrdef d
   join pg_attribute a on a.attrelid=d.adrelid and a.attnum=d.adnum
   where d.adrelid=to_regclass('private.pandora_ops_workspaces') and a.attname='paused'),
 'noProductionDefault',(select pg_get_expr(d.adbin,d.adrelid)='true' from pg_attrdef d
   join pg_attribute a on a.attrelid=d.adrelid and a.attnum=d.adnum
   where d.adrelid=to_regclass('private.pandora_ops_workspaces') and a.attname='no_production')
) as inventory;
