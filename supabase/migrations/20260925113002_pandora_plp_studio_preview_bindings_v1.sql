
begin;

create table if not exists public.pandora_plp_studio_preview_bindings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  version_id uuid not null references public.pandora_project_versions(id) on delete cascade,
  provider_project_id text not null,
  provider_deployment_id text not null check (provider_deployment_id ~ '^dpl_[A-Za-z0-9]+$'),
  source_commit text not null check (source_commit ~ '^[0-9a-f]{40}$'),
  hosted_url text not null check (hosted_url ~ '^https://'),
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  status text not null default 'active' check (status in ('active','expired','revoked')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(project_id,version_id,provider_deployment_id)
);

create index if not exists pandora_plp_studio_preview_bindings_lookup_idx
  on public.pandora_plp_studio_preview_bindings(token_hash,status,expires_at);

alter table public.pandora_plp_studio_preview_bindings enable row level security;
revoke all on public.pandora_plp_studio_preview_bindings from public,anon,authenticated;
grant select,insert,update on public.pandora_plp_studio_preview_bindings to service_role;

commit;

