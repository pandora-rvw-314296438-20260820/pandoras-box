-- TEST-ONLY, INACTIVE REPLAY FIXTURE.
-- Provider-verified source: Supabase jcyqixttuebxqqfkjonq migration 20260825085155.
-- Applied SQL SHA-256: 87024f81944cdb6eae5b9a65a1e08cf96331683b53deea46de07658f8e2cb23a
-- This reconstructs the intentionally history-only control-plane foundation for local migration replay only.

create table if not exists private.project_canonical_registry (
  project_id uuid primary key references public.projectos_projects(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  canonical_provider text not null default 'github',
  canonical_repository text not null,
  canonical_ref text not null default 'refs/heads/main',
  canonical_sha text not null,
  mirror_provider text,
  mirror_repository text,
  mirror_ref text,
  mirror_sha text,
  mirror_state text not null default 'pending',
  supabase_project_ref text,
  vercel_project_id text,
  production_url text,
  deployed_sha text,
  database_fingerprint text,
  edge_function_fingerprint text,
  last_known_good_sha text,
  rollback_sha text,
  source_state text not null default 'active',
  release_state text not null default 'blocked',
  recovery_state text not null default 'missing',
  last_provider_readback_at timestamptz,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint project_canonical_registry_canonical_sha_check
    check (canonical_sha ~ '^[0-9a-f]{40}([0-9a-f]{24})?$'),
  constraint project_canonical_registry_mirror_sha_check
    check (mirror_sha is null or mirror_sha ~ '^[0-9a-f]{40}([0-9a-f]{24})?$'),
  constraint project_canonical_registry_deployed_sha_check
    check (deployed_sha is null or deployed_sha ~ '^[0-9a-f]{40}([0-9a-f]{24})?$'),
  constraint project_canonical_registry_lkg_sha_check
    check (last_known_good_sha is null or last_known_good_sha ~ '^[0-9a-f]{40}([0-9a-f]{24})?$'),
  constraint project_canonical_registry_rollback_sha_check
    check (rollback_sha is null or rollback_sha ~ '^[0-9a-f]{40}([0-9a-f]{24})?$'),
  constraint project_canonical_registry_mirror_state_check
    check (mirror_state in ('unconfigured','pending','in_sync','out_of_sync','blocked','degraded')),
  constraint project_canonical_registry_source_state_check
    check (source_state in ('active','recovered','degraded','blocked','quarantined')),
  constraint project_canonical_registry_release_state_check
    check (release_state in ('blocked','candidate','ready','released','deployed_unmerged','degraded')),
  constraint project_canonical_registry_recovery_state_check
    check (recovery_state in ('missing','available','verified','degraded')),
  constraint project_canonical_registry_config_object_check
    check (jsonb_typeof(config) = 'object')
);

create unique index if not exists project_canonical_registry_org_project_idx
  on private.project_canonical_registry(organization_id, project_id);
create unique index if not exists project_canonical_registry_org_repository_idx
  on private.project_canonical_registry(organization_id, canonical_provider, canonical_repository);

create table if not exists private.project_source_ref_expectations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  provider text not null,
  repository text not null,
  ref_name text not null,
  ref_role text not null default 'required',
  expected_object_id text not null,
  required boolean not null default true,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint project_source_ref_expectations_object_id_check
    check (expected_object_id ~ '^[0-9a-f]{40}([0-9a-f]{24})?$'),
  constraint project_source_ref_expectations_role_check
    check (ref_role in ('canonical','required','reviewed','candidate','deployment','rollback','archive')),
  constraint project_source_ref_expectations_metadata_check
    check (jsonb_typeof(metadata) = 'object'),
  unique(project_id, provider, repository, ref_name)
);

create index if not exists project_source_ref_expectations_lookup_idx
  on private.project_source_ref_expectations(project_id, provider, repository, active, required);

create table if not exists private.project_provider_observations (
  id uuid primary key default gen_random_uuid(),
  observation_key text not null unique,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  provider text not null,
  observation_kind text not null,
  repository text,
  resource_id text,
  ref_name text,
  expected_object_id text,
  observed_object_id text,
  state text not null,
  evidence_digest text not null,
  source_url text,
  payload_redacted jsonb not null default '{}'::jsonb,
  observed_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  constraint project_provider_observations_expected_id_check
    check (expected_object_id is null or expected_object_id ~ '^[0-9a-f]{40}([0-9a-f]{24})?$'),
  constraint project_provider_observations_observed_id_check
    check (observed_object_id is null or observed_object_id ~ '^[0-9a-f]{40}([0-9a-f]{24})?$'),
  constraint project_provider_observations_digest_check
    check (evidence_digest ~ '^[0-9a-f]{64}$'),
  constraint project_provider_observations_state_check
    check (state in ('matched','passed','verified','ready','healthy','observed','missing','mismatched','failed','blocked','degraded','waived','unavailable')),
  constraint project_provider_observations_payload_check
    check (jsonb_typeof(payload_redacted) = 'object')
);

create index if not exists project_provider_observations_latest_idx
  on private.project_provider_observations(project_id, provider, observation_kind, observed_at desc, recorded_at desc);
create index if not exists project_provider_observations_ref_idx
  on private.project_provider_observations(project_id, provider, repository, ref_name, observed_at desc)
  where ref_name is not null;

create table if not exists private.project_release_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  source_repository text not null,
  source_ref text not null,
  source_sha text not null,
  automation_sha text,
  provider text not null,
  deployment_id text not null,
  deployment_url text,
  environment text not null,
  artifact_manifest_digest text,
  database_fingerprint text,
  edge_function_fingerprint text,
  status text not null,
  health_readback jsonb not null default '{}'::jsonb,
  previous_deployment_id text,
  rollback_deployment_id text,
  receipt_hash text not null unique,
  observed_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint project_release_receipts_source_sha_check
    check (source_sha ~ '^[0-9a-f]{40}([0-9a-f]{24})?$'),
  constraint project_release_receipts_automation_sha_check
    check (automation_sha is null or automation_sha ~ '^[0-9a-f]{40}([0-9a-f]{24})?$'),
  constraint project_release_receipts_artifact_digest_check
    check (artifact_manifest_digest is null or artifact_manifest_digest ~ '^[0-9a-f]{64}$'),
  constraint project_release_receipts_receipt_hash_check
    check (receipt_hash ~ '^[0-9a-f]{64}$'),
  constraint project_release_receipts_status_check
    check (status in ('candidate','ready','verified','failed','superseded','rolled_back')),
  constraint project_release_receipts_health_check
    check (jsonb_typeof(health_readback) = 'object'),
  unique(project_id, provider, deployment_id)
);

create index if not exists project_release_receipts_latest_idx
  on private.project_release_receipts(project_id, environment, observed_at desc);

create table if not exists private.project_recovery_artifacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  artifact_type text not null,
  storage_provider text not null,
  artifact_locator text not null,
  sha256 text not null,
  byte_size bigint not null,
  artifact_format text not null,
  contains_refs jsonb not null default '[]'::jsonb,
  verification_state text not null,
  verification_method text not null,
  verified_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint project_recovery_artifacts_sha_check check (sha256 ~ '^[0-9a-f]{64}$'),
  constraint project_recovery_artifacts_byte_size_check check (byte_size > 0),
  constraint project_recovery_artifacts_refs_check check (jsonb_typeof(contains_refs) = 'array'),
  constraint project_recovery_artifacts_state_check
    check (verification_state in ('pending','available','verified','failed','superseded')),
  constraint project_recovery_artifacts_metadata_check check (jsonb_typeof(metadata) = 'object'),
  unique(project_id, storage_provider, artifact_locator)
);

create index if not exists project_recovery_artifacts_digest_idx
  on private.project_recovery_artifacts(project_id, sha256);

create table if not exists private.project_release_policies (
  project_id uuid primary key references public.projectos_projects(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  mirror_required boolean not null default true,
  recovery_artifact_required boolean not null default true,
  exact_ci_required boolean not null default true,
  production_readback_required boolean not null default true,
  canonical_equals_deployed_required boolean not null default true,
  branch_protection_required boolean not null default true,
  provider_observation_max_age interval not null default interval '24 hours',
  required_ci_checks text[] not null default '{}'::text[],
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint project_release_policies_max_age_check
    check (provider_observation_max_age > interval '0 seconds' and provider_observation_max_age <= interval '30 days'),
  constraint project_release_policies_config_check check (jsonb_typeof(config) = 'object')
);

create table if not exists private.project_aliases (
  alias_project_id uuid primary key references public.projectos_projects(id) on delete cascade,
  canonical_project_id uuid not null references public.projectos_projects(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  reason text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint project_aliases_not_self_check check (alias_project_id <> canonical_project_id)
);

create index if not exists project_aliases_canonical_idx
  on private.project_aliases(canonical_project_id, active);

create or replace function private.projectos_control_plane_touch_updated_at()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function private.projectos_control_plane_reject_mutation()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  raise exception 'immutable_control_plane_evidence' using errcode = '55000';
end;
$$;

drop trigger if exists project_canonical_registry_touch on private.project_canonical_registry;
create trigger project_canonical_registry_touch
before update on private.project_canonical_registry
for each row execute function private.projectos_control_plane_touch_updated_at();

drop trigger if exists project_source_ref_expectations_touch on private.project_source_ref_expectations;
create trigger project_source_ref_expectations_touch
before update on private.project_source_ref_expectations
for each row execute function private.projectos_control_plane_touch_updated_at();

drop trigger if exists project_release_policies_touch on private.project_release_policies;
create trigger project_release_policies_touch
before update on private.project_release_policies
for each row execute function private.projectos_control_plane_touch_updated_at();

drop trigger if exists project_aliases_touch on private.project_aliases;
create trigger project_aliases_touch
before update on private.project_aliases
for each row execute function private.projectos_control_plane_touch_updated_at();

drop trigger if exists project_provider_observations_immutable on private.project_provider_observations;
create trigger project_provider_observations_immutable
before update or delete on private.project_provider_observations
for each row execute function private.projectos_control_plane_reject_mutation();

drop trigger if exists project_release_receipts_immutable on private.project_release_receipts;
create trigger project_release_receipts_immutable
before update or delete on private.project_release_receipts
for each row execute function private.projectos_control_plane_reject_mutation();

drop trigger if exists project_recovery_artifacts_immutable on private.project_recovery_artifacts;
create trigger project_recovery_artifacts_immutable
before update or delete on private.project_recovery_artifacts
for each row execute function private.projectos_control_plane_reject_mutation();

do $$
declare
  target regclass;
begin
  foreach target in array array[
    'private.project_canonical_registry'::regclass,
    'private.project_source_ref_expectations'::regclass,
    'private.project_provider_observations'::regclass,
    'private.project_release_receipts'::regclass,
    'private.project_recovery_artifacts'::regclass,
    'private.project_release_policies'::regclass,
    'private.project_aliases'::regclass
  ]
  loop
    execute format('alter table %s enable row level security', target);
    execute format('revoke all on table %s from public, anon, authenticated', target);
  end loop;
end;
$$;

revoke all on function private.projectos_control_plane_touch_updated_at() from public, anon, authenticated;
revoke all on function private.projectos_control_plane_reject_mutation() from public, anon, authenticated;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'pandora-recovery-artifacts',
  'pandora-recovery-artifacts',
  false,
  104857600,
  array['application/octet-stream','application/zip','text/markdown','text/plain']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types,
    updated_at = now();
