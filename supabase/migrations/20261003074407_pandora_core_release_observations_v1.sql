-- Provider observations use Pandora's existing immutable organization audit chain.
-- This changes only the Core release projection. It creates no execution,
-- project, version, deployment ledger, credential, or provider connection.
begin;

create function private.pandora_core_release_payload_valid_v1(p jsonb,p_recorded_at timestamptz)
returns boolean language plpgsql immutable set search_path='' as $$
declare
 v_source jsonb;v_vercel jsonb;v_db jsonb;v_edge jsonb;v_seen text[]:=array[]::text[];
 v_observed timestamptz;v_edge_observed timestamptz;
begin
 if jsonb_typeof(p) is distinct from 'object' or octet_length(p::text)>16000 then return false;end if;
 if (p ?& array['schema_version','observation_kind','repository','observed_at','source','vercel','supabase','edge_functions','verification']
  and p-array['schema_version','observation_kind','repository','observed_at','source','vercel','supabase','edge_functions','verification']='{}'::jsonb
  and p->'schema_version'='1'::jsonb
  and p->>'observation_kind' in ('candidate','canonical_production')
  and p->>'repository'='pandora-rvw-314296438-20260820/pandoras-box'
  and p->>'observed_at'~'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?Z$'
  and p->'verification'='{"runtime_verified":false,"owner_flow_verified":false,"client_flow_verified":false,"production_verified":false}'::jsonb
 ) is not true then return false;end if;
 v_observed:=(p->>'observed_at')::timestamptz;
 if v_observed>p_recorded_at+interval '5 minutes' or v_observed<p_recorded_at-interval '30 days' then return false;end if;
 v_source:=p->'source';v_vercel:=p->'vercel';v_db:=p->'supabase';
 if (jsonb_typeof(v_source)='object' and v_source ?& array['sha','tree_sha']
  and v_source-array['sha','tree_sha']='{}'::jsonb
  and v_source->>'sha'~'^[0-9a-f]{40}$' and v_source->>'tree_sha'~'^[0-9a-f]{40}$'
  and jsonb_typeof(v_source->'sha')='string' and jsonb_typeof(v_source->'tree_sha')='string'
 ) is not true then return false;end if;
 if (jsonb_typeof(v_vercel)='object'
  and v_vercel ?& array['team_id','project_id','deployment_id','url','state','environment','source_sha','canonical_alias']
  and v_vercel-array['team_id','project_id','deployment_id','url','state','environment','source_sha','canonical_alias']='{}'::jsonb
  and v_vercel->>'team_id'='team_3yw1CN59ce4pj5SwyQGCAqN3'
  and v_vercel->>'project_id'='prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk'
  and v_vercel->>'deployment_id'~'^dpl_[A-Za-z0-9]{16,64}$'
  and v_vercel->>'url'~'^https://mcpmaster-[a-z0-9-]{1,100}-mbanatao\.vercel\.app$'
  and v_vercel->>'state' in ('READY','BUILDING','QUEUED','INITIALIZING','ERROR','CANCELED')
  and v_vercel->>'environment' in ('production','preview')
  and v_vercel->>'source_sha'=v_source->>'sha'
  and ((p->>'observation_kind'='candidate' and v_vercel->'canonical_alias'='null'::jsonb)
    or (p->>'observation_kind'='canonical_production' and v_vercel->>'canonical_alias'='mcpmaster.vercel.app'
        and v_vercel->>'environment'='production' and v_vercel->>'state'='READY'))
 ) is not true then return false;end if;
 if (jsonb_typeof(v_db)='object'
  and v_db ?& array['project_ref','migration_version','migration_name','source_file_version','source_sha256','statements_sha256']
  and v_db-array['project_ref','migration_version','migration_name','source_file_version','source_sha256','statements_sha256']='{}'::jsonb
  and v_db->>'project_ref'='jcyqixttuebxqqfkjonq'
  and v_db->>'migration_version'~'^[0-9]{14}$'
  and v_db->>'source_file_version'~'^[0-9]{14}$'
  and v_db->>'migration_name'~'^[a-z][a-z0-9_]{2,99}$'
  and v_db->>'source_sha256'~'^[0-9a-f]{64}$'
  and v_db->>'statements_sha256'=v_db->>'source_sha256'
 ) is not true then return false;end if;
 if jsonb_typeof(p->'edge_functions') is distinct from 'array' then return false;end if;
 if jsonb_array_length(p->'edge_functions')>10 then return false;end if;
 for v_edge in select value from jsonb_array_elements(p->'edge_functions') loop
  if (jsonb_typeof(v_edge)='object'
   and v_edge ?& array['slug','version','source_sha','source_sha256','observed_at']
   and v_edge-array['slug','version','source_sha','source_sha256','observed_at']='{}'::jsonb
   and v_edge->>'slug' in ('pandora-intelligence-chat','pandora-user-admin')
   and not(v_edge->>'slug'=any(v_seen))
   and jsonb_typeof(v_edge->'version')='number'
   and v_edge->>'version'~'^[1-9][0-9]{0,8}$'
   and v_edge->>'source_sha'~'^[0-9a-f]{40}$'
   and v_edge->>'source_sha256'~'^[0-9a-f]{64}$'
   and v_edge->>'observed_at'~'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?Z$'
  ) is not true then return false;end if;
  v_edge_observed:=(v_edge->>'observed_at')::timestamptz;
  if v_edge_observed>v_observed+interval '5 minutes' or v_edge_observed<v_observed-interval '30 days' then return false;end if;
  v_seen:=array_append(v_seen,v_edge->>'slug');
 end loop;
 return true;
exception when others then return false;
end;
$$;
revoke all on function private.pandora_core_release_payload_valid_v1(jsonb,timestamptz) from public,anon,authenticated,service_role;

-- Existing organization/id index serves audit-chain writes. This narrow index
-- serves only the new event-type filter and does not index unrelated audit data.
create index audit_events_core_release_observed_idx on public.audit_events(organization_id,id desc)
 where event_type='core.release_observed' and actor_type='system';

create function private.pandora_core_release_observations_v1(p_organization_id uuid)
returns jsonb language plpgsql stable set search_path='' as $$
declare v_platform uuid;v_rows jsonb;
begin
 -- A client view must never receive Pandora's platform deployment evidence.
 if p_organization_id is not null then return '[]'::jsonb;end if;
 perform private.pandora_core_assert_v1(null,array['owner','operator','support','finance'],false);
 select platform_organization_id into v_platform from private.pandora_core_config where singleton;
 with qualified as (
  select a.id,a.event_hash,a.created_at,a.payload_redacted p
  from public.audit_events a
  where a.organization_id=v_platform and a.event_type='core.release_observed'
   and a.actor_type='system' and a.actor_user_id is null
   and a.run_id is null and a.step_id is null and a.project_id is null
   and private.pandora_core_release_payload_valid_v1(a.payload_redacted,a.created_at)
 ), latest as (
  select distinct on(p->>'observation_kind') *
  from qualified order by p->>'observation_kind',(p->>'observed_at')::timestamptz desc,id desc
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',id,'audit_receipt_id',id,'organization_id',v_platform,
  'title',case p->>'observation_kind' when 'canonical_production' then 'Canonical production' else 'Latest candidate' end,
  'release_observation_kind',p->>'observation_kind',
  'provider','vercel','environment',p#>>'{vercel,environment}',
  'status',p#>>'{vercel,state}','provider_state',p#>>'{vercel,state}',
  'provider_deployment_id',p#>>'{vercel,deployment_id}','deployment_url',p#>>'{vercel,url}',
  'summary',case p->>'observation_kind' when 'canonical_production' then 'Observed serving mcpmaster.vercel.app' else 'Candidate; canonical production remains separate' end,
  'repository',p->>'repository','source_sha',p#>>'{source,sha}',
  'source_commit_sha',p#>>'{source,sha}','source_tree_sha',p#>>'{source,tree_sha}',
  'last_observed_at',p->>'observed_at','last_provider_check_at',p->>'observed_at',
  'recorded_at',created_at,'source_kind','provider_observation',
  'evidence_state',case when (p->>'observed_at')::timestamptz<now()-interval '24 hours' then 'stale'
    when p#>>'{vercel,state}'='READY' then 'deployment_ready' else 'provider_observed' end,
  'verification_state','runtime_not_verified',
  'evidence_ref','audit:'||id::text||':'||event_hash,
  'runtime_verified',false,'owner_flow_verified',false,'client_flow_verified',false,'production_verified',false,
  'supabase_project_ref',p#>>'{supabase,project_ref}',
  'supabase_migration_version',p#>>'{supabase,migration_version}',
  'supabase_migration_name',p#>>'{supabase,migration_name}',
  'supabase_source_file_version',p#>>'{supabase,source_file_version}',
  'supabase_source_sha256',p#>>'{supabase,source_sha256}',
  'supabase_statements_sha256',p#>>'{supabase,statements_sha256}',
  'edge_functions',p->'edge_functions'
 ) order by case p->>'observation_kind' when 'canonical_production' then 0 else 1 end),'[]'::jsonb)
 into v_rows from latest;
 return v_rows;
end;
$$;
revoke all on function private.pandora_core_release_observations_v1(uuid) from public,anon,authenticated,service_role;

-- Preserve every authorization and other projection in the deployed Core RPC.
-- Fail closed if its actual source drifted after the audited Core installation.
do $patch$
declare v_definition text;v_body text;v_old text;
begin
 select pg_get_functiondef(p.oid),p.prosrc into v_definition,v_body
 from pg_proc p where p.oid='public.pandora_core_snapshot_v1(text,uuid)'::regprocedure;
 if encode(extensions.digest(v_body,'sha256'),'hex')<>'9de232d126ba2223044fc0057e3f858dc3b49e74a6f467b4221ec0350adc9336'
 then raise exception 'CORE_SNAPSHOT_SOURCE_DRIFT';end if;
 v_old:=$old$'deployments',coalesce((select jsonb_agg(to_jsonb(q)) from (
    select d.id,d.organization_id,d.provider,d.environment,d.provider_deployment_id,d.source_commit_sha,d.status,d.verification_state,d.provider_state,d.last_provider_check_at,
     case when d.source_commit_sha is null then 'source_unbound' when d.last_provider_check_at<now()-interval '24 hours' then 'stale' else 'provider_evidence_only' end evidence_state
    from public.pandora_project_deployments d where (p_organization_id is null or d.organization_id=p_organization_id) and private.pandora_core_role_v1(d.organization_id) is not null order by d.last_provider_check_at desc nulls last limit 30
   ) q),'[]'::jsonb)$old$;
 if strpos(v_body,v_old)=0 then raise exception 'CORE_RELEASE_PROJECTION_NOT_FOUND';end if;
 execute replace(v_definition,v_old,'''deployments'',private.pandora_core_release_observations_v1(p_organization_id)');
end;
$patch$;

comment on function private.pandora_core_release_observations_v1(uuid) is
 'Latest schema-qualified provider observations from the existing immutable audit chain. READY is not runtime or production acceptance. Service-only audit capture remains the producer boundary.';
commit;
