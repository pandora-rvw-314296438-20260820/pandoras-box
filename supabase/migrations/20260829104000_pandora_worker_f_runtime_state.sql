-- Worker F: durable provider runtime state and Vault-backed Vercel execution boundary.
-- Provider credentials never leave Vault. Worker F stores provider truth and exact lineage only.

create table if not exists public.pandora_runtime_provider_configs (
  provider text not null,
  config_key text not null,
  config_value text not null,
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (provider, config_key),
  constraint pandora_runtime_provider_configs_provider_check check (provider ~ '^[a-z][a-z0-9_-]{1,31}$'),
  constraint pandora_runtime_provider_configs_key_check check (config_key ~ '^[a-z][a-z0-9_.-]{1,63}$'),
  constraint pandora_runtime_provider_configs_value_check check (length(config_value) between 1 and 500)
);
alter table public.pandora_runtime_provider_configs enable row level security;
revoke all on public.pandora_runtime_provider_configs from anon, authenticated;
grant select, insert, update, delete on public.pandora_runtime_provider_configs to service_role;

insert into public.pandora_runtime_provider_configs(provider, config_key, config_value, active)
values ('vercel', 'team_id', 'team_3yw1CN59ce4pj5SwyQGCAqN3', true)
on conflict (provider, config_key) do update
set config_value = excluded.config_value, active = excluded.active, updated_at = now();

alter table public.pandora_project_deployments
  add column if not exists artifact_digest text,
  add column if not exists source_commit_sha text,
  add column if not exists authorization_ref text,
  add column if not exists verification_ref text,
  add column if not exists idempotency_key text,
  add column if not exists provider_state text,
  add column if not exists immutable_url text,
  add column if not exists stable_url text,
  add column if not exists last_provider_check_at timestamptz,
  add column if not exists retry_after_at timestamptz,
  add column if not exists ready_at timestamptz,
  add column if not exists failed_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists expires_at timestamptz,
  add column if not exists config_digest text,
  add column if not exists verification_state text not null default 'not_verified',
  add column if not exists updated_at timestamptz not null default now();

alter table public.pandora_project_deployments
  drop constraint if exists pandora_project_deployments_provider_check,
  drop constraint if exists pandora_project_deployments_environment_check;

alter table public.pandora_project_deployments
  add constraint pandora_project_deployments_provider_nonempty_check
    check (provider ~ '^[a-z][a-z0-9_-]{1,31}$') not valid,
  add constraint pandora_project_deployments_environment_v2_check
    check (environment in ('development','preview','production')) not valid,
  add constraint pandora_project_deployments_artifact_digest_check
    check (artifact_digest is null or artifact_digest ~ '^[0-9a-f]{64}$') not valid,
  add constraint pandora_project_deployments_source_commit_check
    check (source_commit_sha is null or source_commit_sha ~ '^([0-9a-f]{40}|[0-9a-f]{64})$') not valid,
  add constraint pandora_project_deployments_config_digest_check
    check (config_digest is null or config_digest ~ '^[0-9a-f]{64}$') not valid,
  add constraint pandora_project_deployments_verification_state_check
    check (verification_state in ('not_verified','ready_for_verification','live_verified','failed','stale')) not valid;

create unique index if not exists pandora_project_deployments_idempotency_uidx
  on public.pandora_project_deployments(provider, idempotency_key)
  where idempotency_key is not null;
create index if not exists pandora_project_deployments_reconcile_idx
  on public.pandora_project_deployments(status, last_provider_check_at)
  where status in ('pending','requested','queued','building','deploying','uncertain');

alter table public.pandora_project_domains
  add column if not exists environment text not null default 'production',
  add column if not exists provider_project_id text,
  add column if not exists ownership_verified boolean not null default false,
  add column if not exists dns_configured boolean not null default false,
  add column if not exists tls_ready boolean not null default false,
  add column if not exists routing_ready boolean not null default false,
  add column if not exists runtime_healthy boolean not null default false,
  add column if not exists provider_payload jsonb not null default '{}'::jsonb,
  add column if not exists last_checked_at timestamptz,
  add column if not exists failed_at timestamptz;

alter table public.pandora_project_domains
  drop constraint if exists pandora_project_domains_provider_check;
alter table public.pandora_project_domains
  add constraint pandora_project_domains_provider_nonempty_check
    check (provider ~ '^[a-z][a-z0-9_-]{1,31}$') not valid,
  add constraint pandora_project_domains_environment_check
    check (environment in ('preview','production')) not valid;

create table if not exists public.pandora_runtime_environments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  environment text not null,
  provider text not null,
  provider_project_id text,
  status text not null default 'unprovisioned',
  config_digest text,
  secret_scope_ref text,
  current_version_id uuid references public.pandora_project_versions(id) on delete restrict,
  current_deployment_id uuid references public.pandora_project_deployments(id) on delete set null,
  verification_state text not null default 'not_verified',
  last_reconciled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pandora_runtime_environments_environment_check check (environment in ('development','preview','production')),
  constraint pandora_runtime_environments_provider_check check (provider ~ '^[a-z][a-z0-9_-]{1,31}$'),
  constraint pandora_runtime_environments_status_check check (status in ('unprovisioned','provisioning','ready','degraded','failed','archived')),
  constraint pandora_runtime_environments_config_digest_check check (config_digest is null or config_digest ~ '^[0-9a-f]{64}$'),
  constraint pandora_runtime_environments_verification_check check (verification_state in ('not_verified','ready_for_verification','live_verified','failed','stale')),
  unique (project_id, environment)
);
alter table public.pandora_runtime_environments enable row level security;
revoke all on public.pandora_runtime_environments from anon, authenticated;
grant select, insert, update, delete on public.pandora_runtime_environments to service_role;

create table if not exists public.pandora_runtime_operations (
  id uuid primary key default gen_random_uuid(),
  idempotency_key text not null,
  action text not null,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  project_version_id uuid references public.pandora_project_versions(id) on delete restrict,
  environment text not null,
  provider text not null,
  authorization_ref text not null,
  verification_ref text,
  provider_project_id text,
  provider_operation_id text,
  provider_resource_id text,
  status text not null default 'claimed',
  ambiguous boolean not null default false,
  retry_after_at timestamptz,
  normalized_error jsonb not null default '{}'::jsonb,
  result_facts jsonb not null default '{}'::jsonb,
  claimed_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  last_reconciled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pandora_runtime_operations_key_check check (idempotency_key ~ '^[0-9a-f]{64}$'),
  constraint pandora_runtime_operations_action_check check (action in ('create_preview','publish_version','attach_domain','provision_runtime','migration_execute','rollback','delete_runtime','delete_preview')),
  constraint pandora_runtime_operations_environment_check check (environment in ('development','preview','production')),
  constraint pandora_runtime_operations_status_check check (status in ('claimed','running','uncertain','succeeded','failed','cancelled')),
  unique (provider, idempotency_key)
);
create unique index if not exists pandora_runtime_one_active_production_publish_uidx
  on public.pandora_runtime_operations(project_id)
  where action = 'publish_version' and environment = 'production' and status in ('claimed','running','uncertain');
create index if not exists pandora_runtime_operations_reconcile_idx
  on public.pandora_runtime_operations(status, retry_after_at, updated_at)
  where status in ('claimed','running','uncertain');
alter table public.pandora_runtime_operations enable row level security;
revoke all on public.pandora_runtime_operations from anon, authenticated;
grant select, insert, update, delete on public.pandora_runtime_operations to service_role;

create table if not exists public.pandora_runtime_provider_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_event_id text not null,
  event_type text not null,
  organization_id uuid references public.organizations(id) on delete cascade,
  project_id uuid references public.projectos_projects(id) on delete cascade,
  provider_project_id text,
  provider_resource_id text,
  payload_sha256 text not null,
  safe_summary jsonb not null default '{}'::jsonb,
  provider_occurred_at timestamptz,
  status text not null default 'received',
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  constraint pandora_runtime_provider_events_payload_check check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  constraint pandora_runtime_provider_events_status_check check (status in ('received','processed','ignored','rejected','failed')),
  unique (provider, provider_event_id)
);
alter table public.pandora_runtime_provider_events enable row level security;
revoke all on public.pandora_runtime_provider_events from anon, authenticated;
grant select, insert, update on public.pandora_runtime_provider_events to service_role;

create table if not exists public.pandora_runtime_environment_variables (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  environment text not null,
  provider text not null,
  variable_key text not null,
  secret boolean not null default true,
  secret_ref text,
  value_digest text,
  provider_variable_id text,
  config_version bigint generated always as identity,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pandora_runtime_envvars_environment_check check (environment in ('development','preview','production')),
  constraint pandora_runtime_envvars_key_check check (variable_key ~ '^[A-Za-z_][A-Za-z0-9_]{0,127}$'),
  constraint pandora_runtime_envvars_secret_check check ((secret and secret_ref is not null and value_digest is null) or (not secret and secret_ref is null and value_digest ~ '^[0-9a-f]{64}$')),
  unique(project_id, environment, variable_key)
);
alter table public.pandora_runtime_environment_variables enable row level security;
revoke all on public.pandora_runtime_environment_variables from anon, authenticated;
grant select, insert, update, delete on public.pandora_runtime_environment_variables to service_role;

create or replace function private.pandora_worker_f_vercel_api_20260829(
  p_method text,
  p_path text,
  p_body jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'private', 'vault', 'extensions', 'public'
as $$
declare
  v_token text;
  v_team_id text;
  v_response extensions.http_response;
  v_body jsonb;
  v_method extensions.http_method;
  v_url text;
  v_base_path text;
begin
  if upper(coalesce(p_method,'')) not in ('GET','POST','PATCH','DELETE') then
    raise exception 'unsupported Vercel method' using errcode='22023';
  end if;
  if p_path is null or p_path like '%..%' or p_path ~ E'[\\r\\n]' then
    raise exception 'invalid Vercel path' using errcode='22023';
  end if;

  select config_value into strict v_team_id
  from public.pandora_runtime_provider_configs
  where provider='vercel' and config_key='team_id' and active=true;

  if not (p_path ~ ('[?&]teamId=' || v_team_id || '(&|$)')) then
    raise exception 'Vercel request is not scoped to the configured team' using errcode='22023';
  end if;

  v_base_path := split_part(p_path,'?',1);
  if not (
    (upper(p_method)='POST' and v_base_path = '/v11/projects')
    or (upper(p_method)='GET' and v_base_path ~ '^/v9/projects/(prj_[A-Za-z0-9]+|[a-z0-9][a-z0-9-]{0,99})$')
    or (upper(p_method) in ('GET','POST') and v_base_path = '/v13/deployments')
    or (upper(p_method)='GET' and v_base_path = '/v6/deployments')
    or (upper(p_method)='GET' and v_base_path ~ '^/v13/deployments/dpl_[A-Za-z0-9]+$')
    or (upper(p_method)='PATCH' and v_base_path ~ '^/v12/deployments/dpl_[A-Za-z0-9]+/cancel$')
    or (upper(p_method)='DELETE' and v_base_path ~ '^/v13/deployments/dpl_[A-Za-z0-9]+$')
    or (upper(p_method)='POST' and v_base_path ~ '^/v10/projects/prj_[A-Za-z0-9]+/promote/dpl_[A-Za-z0-9]+$')
    or (upper(p_method)='POST' and v_base_path ~ '^/v1/projects/prj_[A-Za-z0-9]+/rollback/dpl_[A-Za-z0-9]+$')
    or (upper(p_method)='POST' and v_base_path ~ '^/v10/projects/prj_[A-Za-z0-9]+/domains$')
    or (upper(p_method)='GET' and v_base_path ~ '^/v9/projects/prj_[A-Za-z0-9]+/domains/[A-Za-z0-9.-]+$')
    or (upper(p_method)='GET' and v_base_path ~ '^/v6/domains/[A-Za-z0-9.-]+/config$')
  ) then
    raise exception 'Vercel path is outside Worker F runtime lane' using errcode='22023';
  end if;

  select decrypted_secret into strict v_token
  from vault.decrypted_secrets
  where name='vercel'
  limit 1;
  if nullif(trim(v_token),'') is null then
    raise exception 'Vercel provider credential unavailable' using errcode='55000';
  end if;

  v_method := upper(p_method)::extensions.http_method;
  v_url := 'https://api.vercel.com'||p_path;
  select * into v_response
  from extensions.http((
    v_method,
    v_url::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('content-type','application/json'),
      extensions.http_header('user-agent','Pandora-Worker-F-Runtime/1.0')
    ]::extensions.http_header[],
    case when p_body is null then null else 'application/json' end::varchar,
    case when p_body is null then null else p_body::text end::varchar
  )::extensions.http_request);

  begin
    v_body := nullif(v_response.content,'')::jsonb;
  exception when others then
    v_body := case when nullif(v_response.content,'') is null then null
      else jsonb_build_object('raw',left(v_response.content,5000)) end;
  end;

  return jsonb_build_object(
    'status',v_response.status,
    'contentType',v_response.content_type,
    'body',v_body
  );
end;
$$;

revoke all on function private.pandora_worker_f_vercel_api_20260829(text,text,jsonb) from public, anon, authenticated;
grant execute on function private.pandora_worker_f_vercel_api_20260829(text,text,jsonb) to service_role;

create or replace function public.pandora_worker_f_vercel_request_20260829(
  p_method text,
  p_path text,
  p_body jsonb default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.pandora_worker_f_vercel_api_20260829(p_method,p_path,p_body);
$$;
revoke all on function public.pandora_worker_f_vercel_request_20260829(text,text,jsonb) from public, anon, authenticated;
grant execute on function public.pandora_worker_f_vercel_request_20260829(text,text,jsonb) to service_role;
