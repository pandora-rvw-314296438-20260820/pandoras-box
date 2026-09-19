
-- Pandora automatic Vercel project + stable domain provisioning v1.
-- Keeps provider credentials behind the existing Vault-backed Worker F broker.

create or replace function private.pandora_customer_vercel_project_name_20260901(
  p_name text,
  p_project_id uuid
)
returns text
language plpgsql
immutable
set search_path = 'pg_catalog'
as $$
declare
  v_slug text;
begin
  v_slug := regexp_replace(lower(coalesce(p_name,'')), '[^a-z0-9]+', '-', 'g');
  v_slug := trim(both '-' from v_slug);
  if v_slug = '' then v_slug := 'project'; end if;
  v_slug := left(v_slug,42);
  return 'pandora-' || v_slug || '-' || left(replace(p_project_id::text,'-',''),8);
end;
$$;

create or replace function private.pandora_provision_customer_vercel_project_20260901(
  p_name text,
  p_project_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'private', 'public'
as $$
declare
  v_team_id text;
  v_project_name text;
  v_response jsonb;
  v_body jsonb;
  v_status integer;
  v_project_id text;
  v_provider_name text;
begin
  if p_project_id is null then
    raise exception 'project identity is required before Vercel provisioning' using errcode='55000';
  end if;
  select config_value into strict v_team_id
  from public.pandora_runtime_provider_configs
  where provider='vercel' and config_key='team_id' and active=true
  limit 1;
  if nullif(trim(v_team_id),'') is null then
    raise exception 'Vercel team configuration unavailable' using errcode='55000';
  end if;

  v_project_name := private.pandora_customer_vercel_project_name_20260901(p_name,p_project_id);
  v_response := private.pandora_worker_f_vercel_api_20260829(
    'POST',
    '/v11/projects?teamId=' || v_team_id,
    jsonb_build_object(
      'name',v_project_name,
      'framework',null,
      'skipGitConnectDuringLink',true,
      'enablePreviewFeedback',true,
      'enableProductionFeedback',true
    )
  );
  v_status := coalesce((v_response->>'status')::integer,0);
  v_body := coalesce(v_response->'body','{}'::jsonb);

  if v_status = 409 then
    v_response := private.pandora_worker_f_vercel_api_20260829(
      'GET',
      '/v9/projects/' || v_project_name || '?teamId=' || v_team_id,
      null
    );
    v_status := coalesce((v_response->>'status')::integer,0);
    v_body := coalesce(v_response->'body','{}'::jsonb);
  end if;
  if v_status not in (200,201) then
    raise exception 'Vercel project provisioning failed' using errcode='55000';
  end if;

  v_project_id := coalesce(v_body->>'id','');
  v_provider_name := coalesce(v_body->>'name',v_project_name);
  if v_project_id !~ '^prj_[A-Za-z0-9]+$'
     or v_provider_name <> v_project_name
     or coalesce(v_body->>'accountId','') <> v_team_id then
    raise exception 'Vercel returned an invalid project identity' using errcode='55000';
  end if;

  return jsonb_build_object(
    'id',v_project_id,
    'name',v_provider_name,
    'default_domain',v_provider_name || '.vercel.app',
    'team_id',v_team_id
  );
end;
$$;

create or replace function private.pandora_project_auto_vercel_20260901()
returns trigger
language plpgsql
security definer
set search_path = 'pg_catalog', 'private', 'public'
as $$
declare
  v_journey jsonb;
  v_provider jsonb;
begin
  if coalesce(new.config #>> '{customerJourney,createdFrom}','') <> 'simple_mode' then
    return new;
  end if;
  v_journey := coalesce(new.config->'customerJourney','{}'::jsonb);
  if nullif(v_journey->>'vercelProjectId','') is not null then
    return new;
  end if;
  v_provider := private.pandora_provision_customer_vercel_project_20260901(new.name,new.id);
  v_journey := v_journey || jsonb_build_object(
    'vercelProjectId',v_provider->>'id',
    'vercelProjectName',v_provider->>'name',
    'vercelDefaultDomain',v_provider->>'default_domain',
    'vercelDefaultDomainStatus','reserved',
    'runtimeStatus','ready',
    'runtimeUpdatedAt',now()
  );
  new.config := jsonb_set(coalesce(new.config,'{}'::jsonb),'{customerJourney}',v_journey,true);
  return new;
end;
$$;

drop trigger if exists pandora_project_auto_vercel_v1 on public.projectos_projects;
create trigger pandora_project_auto_vercel_v1
before insert on public.projectos_projects
for each row
when (coalesce(new.config #>> '{customerJourney,createdFrom}','') = 'simple_mode')
execute function private.pandora_project_auto_vercel_20260901();

create or replace function private.pandora_project_verified_vercel_domain_20260901()
returns trigger
language plpgsql
security definer
set search_path = 'pg_catalog', 'private', 'public'
as $$
declare
  v_journey jsonb;
  v_env record;
  v_deployment record;
  v_team_id text;
  v_response jsonb;
  v_body jsonb;
  v_status integer;
  v_provider_name text;
  v_default_domain text;
  v_custom_domain text;
  v_live_url text;
begin
  v_journey := coalesce(new.config->'customerJourney','{}'::jsonb);
  if coalesce(v_journey->>'productionVerificationState','') <> 'live_verified' then
    return new;
  end if;

  select e.current_deployment_id, e.provider_project_id
    into v_env
  from public.pandora_runtime_environments e
  where e.organization_id=new.organization_id
    and e.project_id=new.id
    and e.environment='production'
    and e.provider='vercel'
    and e.verification_state='live_verified'
  limit 1;
  if not found or v_env.current_deployment_id is null then return new; end if;

  select d.provider_project_id,d.provider_deployment_id,d.verification_state
    into v_deployment
  from public.pandora_project_deployments d
  where d.id=v_env.current_deployment_id
    and d.organization_id=new.organization_id
    and d.project_id=new.id
    and d.environment='production'
    and d.provider='vercel'
  limit 1;
  if not found or v_deployment.verification_state <> 'live_verified' then return new; end if;

  select config_value into strict v_team_id
  from public.pandora_runtime_provider_configs
  where provider='vercel' and config_key='team_id' and active=true
  limit 1;
  v_response := private.pandora_worker_f_vercel_api_20260829(
    'GET',
    '/v9/projects/' || v_deployment.provider_project_id || '?teamId=' || v_team_id,
    null
  );
  v_status := coalesce((v_response->>'status')::integer,0);
  v_body := coalesce(v_response->'body','{}'::jsonb);
  if v_status <> 200 then return new; end if;
  if coalesce(v_body->'targets'->'production'->>'id','') <> v_deployment.provider_deployment_id then
    return new;
  end if;
  v_provider_name := coalesce(v_body->>'name',v_journey->>'vercelProjectName','');
  if v_provider_name = '' then return new; end if;
  v_default_domain := v_provider_name || '.vercel.app';

  select d.domain into v_custom_domain
  from public.pandora_project_domains d
  where d.organization_id=new.organization_id
    and d.project_id=new.id
    and d.environment='production'
    and d.primary_domain=true
    and d.ownership_verified=true
    and d.dns_configured=true
    and d.tls_ready=true
    and d.routing_ready=true
    and d.runtime_healthy=true
  order by d.updated_at desc
  limit 1;

  v_live_url := case
    when nullif(v_custom_domain,'') is not null then 'https://' || v_custom_domain
    else 'https://' || v_default_domain
  end;
  v_journey := v_journey || jsonb_build_object(
    'vercelProjectId',v_deployment.provider_project_id,
    'vercelProjectName',v_provider_name,
    'vercelDefaultDomain',v_default_domain,
    'vercelDefaultDomainStatus','live_verified',
    'liveUrl',v_live_url
  );
  new.config := jsonb_set(coalesce(new.config,'{}'::jsonb),'{customerJourney}',v_journey,true);
  return new;
end;
$$;

drop trigger if exists pandora_project_verified_vercel_domain_v1 on public.projectos_projects;
create trigger pandora_project_verified_vercel_domain_v1
before update of config on public.projectos_projects
for each row
when (coalesce(new.config #>> '{customerJourney,productionVerificationState}','') = 'live_verified')
execute function private.pandora_project_verified_vercel_domain_20260901();

revoke all on function private.pandora_customer_vercel_project_name_20260901(text,uuid) from public,anon,authenticated;
revoke all on function private.pandora_provision_customer_vercel_project_20260901(text,uuid) from public,anon,authenticated;
revoke all on function private.pandora_project_auto_vercel_20260901() from public,anon,authenticated;
revoke all on function private.pandora_project_verified_vercel_domain_20260901() from public,anon,authenticated;
grant execute on function private.pandora_customer_vercel_project_name_20260901(text,uuid) to service_role;
