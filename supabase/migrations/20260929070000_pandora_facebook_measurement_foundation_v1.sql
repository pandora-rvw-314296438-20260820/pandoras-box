-- FB-018..FB-024: provider-bound Facebook measurement foundation.
-- Source may be deployed before privacy or campaign authorization because all
-- customer/provider delivery paths fail closed without explicit rows/verified IDs.

create table if not exists public.pandora_growth_privacy_authorizations (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references private.project_canonical_registry(project_id) on delete cascade,
  policy_version text not null check (policy_version ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'),
  allowed_flows text[] not null default '{}',
  approved_by uuid not null,
  evidence_ref text not null check (length(evidence_ref) between 1 and 500),
  approved_at timestamptz not null,
  expires_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (organization_id,project_id,policy_version),
  check (expires_at is null or expires_at>approved_at),
  check (allowed_flows <@ array[
    'redirect_measurement','browser_analytics','server_outcomes',
    'provider_matching','durable_learning'
  ]::text[])
);
