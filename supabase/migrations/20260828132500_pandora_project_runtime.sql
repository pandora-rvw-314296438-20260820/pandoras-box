-- Pandora customer project runtime: immutable versions, deployments, and domains.
-- This preserves ProjectOS as the internal project model while exposing Projects
-- as the customer-facing lifecycle.

create table if not exists public.pandora_project_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  sequence_no bigint generated always as identity,
  kind text not null default 'preview',
  source_payload jsonb not null default '{}'::jsonb,
  source_sha256 text not null,
  created_by uuid null references auth.users(id) on delete set null,
  approved_at timestamptz null,
  created_at timestamptz not null default now(),
  constraint pandora_project_versions_kind_check
    check (kind in ('preview', 'production_candidate')),
  constraint pandora_project_versions_sha_check
    check (source_sha256 ~ '^[0-9a-f]{64}$')
);

create index if not exists pandora_project_versions_project_created_idx
  on public.pandora_project_versions(project_id, created_at desc);
create index if not exists pandora_project_versions_org_project_idx
  on public.pandora_project_versions(organization_id, project_id);

create table if not exists public.pandora_project_deployments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  version_id uuid not null references public.pandora_project_versions(id) on delete restrict,
  provider text not null default 'vercel',
  environment text not null,
  provider_project_id text not null,
  provider_deployment_id text null,
  url text null,
  status text not null default 'pending',
  source_sha256 text not null,
  promoted_from_id uuid null references public.pandora_project_deployments(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint pandora_project_deployments_provider_check
    check (provider in ('vercel')),
  constraint pandora_project_deployments_environment_check
    check (environment in ('preview', 'production')),
  constraint pandora_project_deployments_sha_check
    check (source_sha256 ~ '^[0-9a-f]{64}$')
);

create index if not exists pandora_project_deployments_project_created_idx
  on public.pandora_project_deployments(project_id, created_at desc);
create index if not exists pandora_project_deployments_provider_deployment_idx
  on public.pandora_project_deployments(provider, provider_deployment_id)
  where provider_deployment_id is not null;
create index if not exists pandora_project_deployments_org_project_idx
  on public.pandora_project_deployments(organization_id, project_id);

create table if not exists public.pandora_project_domains (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  provider text not null default 'vercel',
  domain text not null,
  status text not null default 'pending',
  verified boolean not null default false,
  primary_domain boolean not null default false,
  verification jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pandora_project_domains_provider_check
    check (provider in ('vercel')),
  constraint pandora_project_domains_domain_check
    check (length(domain) between 1 and 253)
);

create unique index if not exists pandora_project_domains_project_domain_uidx
  on public.pandora_project_domains(project_id, lower(domain));
create unique index if not exists pandora_project_domains_one_primary_uidx
  on public.pandora_project_domains(project_id)
  where primary_domain = true;
create index if not exists pandora_project_domains_org_project_idx
  on public.pandora_project_domains(organization_id, project_id);

alter table public.pandora_project_versions enable row level security;
alter table public.pandora_project_deployments enable row level security;
alter table public.pandora_project_domains enable row level security;

drop policy if exists pandora_project_versions_member_read on public.pandora_project_versions;
create policy pandora_project_versions_member_read
  on public.pandora_project_versions
  for select
  to authenticated
  using (private.is_org_member(organization_id));

drop policy if exists pandora_project_versions_operator_write on public.pandora_project_versions;
create policy pandora_project_versions_operator_write
  on public.pandora_project_versions
  for all
  to authenticated
  using (
    private.has_org_role(
      organization_id,
      array['owner'::member_role, 'admin'::member_role, 'operator'::member_role]
    )
  )
  with check (
    private.has_org_role(
      organization_id,
      array['owner'::member_role, 'admin'::member_role, 'operator'::member_role]
    )
  );

drop policy if exists pandora_project_deployments_member_read on public.pandora_project_deployments;
create policy pandora_project_deployments_member_read
  on public.pandora_project_deployments
  for select
  to authenticated
  using (private.is_org_member(organization_id));

drop policy if exists pandora_project_deployments_operator_write on public.pandora_project_deployments;
create policy pandora_project_deployments_operator_write
  on public.pandora_project_deployments
  for all
  to authenticated
  using (
    private.has_org_role(
      organization_id,
      array['owner'::member_role, 'admin'::member_role, 'operator'::member_role]
    )
   )
  with check (
    private.has_org_role(
      organization_id,
      array['owner'::member_role, 'admin'::member_role, 'operator'::member_role]
    )
  );

drop policy if exists pandora_project_domains_member_read on public.pandora_project_domains;
create policy pandora_project_domains_member_read
  on public.pandora_project_domains
  for select
  to authenticated
  using (private.is_org_member(organization_id));

drop policy if exists pandora_project_domains_operator_write on public.pandora_project_domains;
create policy pandora_project_domains_operator_write
  on public.pandora_project_domains
  for all
  to authenticated
  using (
    private.has_org_role(
      organization_id,
      array['owner'::member_role, 'admin'::member_role, 'operator'::member_role]
    )
  )
  with check (
    private.has_org_role(
      organization_id,
      array['owner'::member_role, 'admin'::member_role, 'operator'::member_role]
    )
  );

grant select, insert, update on public.pandora_project_versions to authenticated;
grant select, insert, update on public.pandora_project_deployments to authenticated;
grant select, insert, update on public.pandora_project_domains to authenticated;
grant usage, select on sequence public.pandora_project_versions_sequence_no_seq to authenticated;
