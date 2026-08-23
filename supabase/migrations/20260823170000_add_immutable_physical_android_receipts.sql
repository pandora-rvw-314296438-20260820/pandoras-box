-- Canonical physical Android proof is accepted only through an enrolled,
-- signed observer boundary. Generic projectos_evidence rows are historical
-- context and cannot authorize a release review after this migration.

do $roles$
begin
  if not exists (
    select 1 from pg_roles where rolname = 'projectos_physical_android_ingest'
  ) then
    create role projectos_physical_android_ingest nologin noinherit;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticator') then
    execute 'grant projectos_physical_android_ingest to authenticator';
  end if;
end
$roles$;

grant usage on schema public to projectos_physical_android_ingest;

create table private.physical_android_observer_identities (
  organization_id uuid not null references public.organizations(id) on delete restrict,
  observer_id text not null check (observer_id ~ '^[a-z0-9][a-z0-9._:-]{2,127}$'),
  public_key_b64 text not null check (
    public_key_b64 ~ '^[A-Za-z0-9+/]{43}=$'
    and octet_length(decode(public_key_b64, 'base64')) = 32
  ),
  key_fingerprint text not null check (key_fingerprint ~ '^[0-9a-f]{64}$'),
  allowed_repositories text[] not null check (
    allowed_repositories = array['banataosystems/Pandoras-box']::text[]
  ),
  status text not null default 'active' check (status in ('active', 'draining', 'disabled')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (organization_id, observer_id),
  unique (organization_id, key_fingerprint)
);

-- PostgREST validates a short-lived JWT signed by the external physical-device
-- authority. The authority and signing key are deliberately outside this
-- repository and candidate runtime. Each exact issuer/JTI is consumed once.
create table private.physical_android_authority_jtis (
  issuer text not null check (issuer = 'pandora-physical-android-authority-v1'),
  jti text not null check (jti ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{15,127}$'),
  organization_id uuid not null,
  observer_id text not null,
  request_id uuid not null,
  request_sha256 text not null check (request_sha256 ~ '^[0-9a-f]{64}$'),
  authority_issued_at timestamptz not null,
  authority_expires_at timestamptz not null,
  consumed_at timestamptz not null default clock_timestamp(),
  foreign key (organization_id, observer_id)
    references private.physical_android_observer_identities(organization_id, observer_id)
    on delete restrict,
  primary key (issuer, jti),
  check (authority_expires_at > authority_issued_at),
  check (consumed_at >= authority_issued_at - interval '30 seconds')
);

create index physical_android_authority_jtis_expiry_idx
  on private.physical_android_authority_jtis (authority_expires_at);

create table private.physical_android_authority_rate_limits (
  organization_id uuid not null references public.organizations(id) on delete restrict,
  purpose_sha256 text not null check (purpose_sha256 ~ '^[0-9a-f]{64}$'),
  window_started_at timestamptz not null,
  request_count integer not null check (request_count > 0),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (organization_id, purpose_sha256, window_started_at)
);

create table private.canonical_physical_android_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  request_id uuid not null,
  observer_id text not null,
  observer_key_fingerprint text not null check (observer_key_fingerprint ~ '^[0-9a-f]{64}$'),
  repository text not null check (repository = 'banataosystems/Pandoras-box'),
  source_sha text not null check (source_sha ~ '^[0-9a-f]{40}$'),
  source_tree_sha text not null check (source_tree_sha ~ '^[0-9a-f]{40}$'),
  production_deployment_id text not null check (production_deployment_id ~ '^dpl_[A-Za-z0-9]+$'),
  production_origin text not null check (production_origin = 'https://mcpmaster.vercel.app'),
  ci_artifact_external_id text not null check (ci_artifact_external_id ~ '^[1-9][0-9]{0,19}$'),
  ci_artifact_url text not null,
  ci_artifact_name text not null,
  ci_artifact_sha256 text not null check (ci_artifact_sha256 ~ '^[0-9a-f]{64}$'),
  apk_sha256 text not null check (apk_sha256 ~ '^[0-9a-f]{64}$'),
  device_id_hash text not null check (device_id_hash ~ '^[0-9a-f]{64}$'),
  package_name text not null check (package_name = 'com.banataosystems.pandora_mobile'),
  network text not null check (network in ('wifi', 'mobile_data')),
  provider_observation_index smallint not null check (
    (network = 'wifi' and provider_observation_index = 1)
    or (network = 'mobile_data' and provider_observation_index = 2)
  ),
  completed_steps text[] not null check (
    completed_steps = array[
      'owner_authenticate',
      'submit_owner_command',
      'observe_durable_dispatch',
      'observe_worker_01_claim',
      'observe_exact_provider_result',
      'observe_proof_in_owner_read'
    ]::text[]
  ),
  owner_plan_id uuid not null references private.execution_plans(id) on delete restrict,
  owner_dispatch_id uuid not null references private.execution_dispatch_outbox(id) on delete restrict,
  worker_evidence_sha256 text not null check (worker_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  verification_evidence_id uuid not null references public.projectos_evidence(id) on delete restrict,
  reviewer_runtime_proof_id uuid not null references public.projectos_agent_runtime_proofs(id) on delete restrict,
  request_nonce text not null check (request_nonce ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{15,127}$'),
  nonce_sha256 text not null check (nonce_sha256 ~ '^[0-9a-f]{64}$'),
  signed_timestamp text not null check (
    signed_timestamp ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$'
  ),
  provider_observed_at timestamptz not null,
  signature_b64 text not null check (signature_b64 ~ '^[A-Za-z0-9+/]{86}==$'),
  signature_basis_sha256 text not null check (signature_basis_sha256 ~ '^[0-9a-f]{64}$'),
  receipt_sha256 text not null check (receipt_sha256 ~ '^[0-9a-f]{64}$'),
  captured_at timestamptz not null default clock_timestamp(),
  foreign key (organization_id, observer_id)
    references private.physical_android_observer_identities(organization_id, observer_id)
    on delete restrict,
  unique (organization_id, request_id),
  unique (organization_id, observer_id, nonce_sha256),
  unique (
    organization_id, repository, source_sha, production_deployment_id,
    device_id_hash, network
  ),
  check (provider_observed_at <= captured_at),
  check (
    ci_artifact_url =
      'https://api.github.com/repos/banataosystems/Pandoras-box/actions/artifacts/'
      || ci_artifact_external_id
  ),
  check (ci_artifact_name = 'pandora-mobile-android-validation-' || source_sha)
);

create trigger canonical_physical_android_receipts_immutable
before update or delete on private.canonical_physical_android_receipts
for each row execute function private.reject_canonical_release_receipt_mutation();

alter table private.physical_android_observer_identities enable row level security;
alter table private.physical_android_authority_jtis enable row level security;
alter table private.physical_android_authority_rate_limits enable row level security;
alter table private.canonical_physical_android_receipts enable row level security;

revoke all on table private.physical_android_observer_identities
  from public, anon, authenticated, service_role, projectos_physical_android_ingest;
revoke all on table private.physical_android_authority_jtis
  from public, anon, authenticated, service_role, projectos_physical_android_ingest;
revoke all on table private.physical_android_authority_rate_limits
  from public, anon, authenticated, service_role, projectos_physical_android_ingest;
revoke all on table private.canonical_physical_android_receipts
  from public, anon, authenticated, service_role, projectos_physical_android_ingest;

create or replace function private.assert_physical_android_ingest_role()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if session_user <> 'postgres'
     and coalesce(auth.jwt() ->> 'role', '') <> 'projectos_physical_android_ingest' then
    raise exception 'physical Android ingest role required' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.consume_physical_android_authority_rate_limit(
  p_organization_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  claims jsonb := auth.jwt();
  observed_at timestamptz := clock_timestamp();
  bucket_started_at timestamptz;
  purpose_hash text;
  next_count integer;
begin
  perform private.assert_physical_android_ingest_role();
  if coalesce(claims ->> 'iss', '') <> 'pandora-physical-android-authority-v1'
     or coalesce(claims ->> 'aud', '') <> 'projectos_physical_android_ingest'
     or coalesce(claims ->> 'purpose', '') <> 'canonical_physical_android_capture'
     or coalesce(claims ->> 'organization_id', '') <> p_organization_id::text then
    raise exception 'external physical Android authority required'
      using errcode = '42501';
  end if;
  purpose_hash := encode(extensions.digest(convert_to(
    concat_ws('|', claims ->> 'iss', p_organization_id::text,
      claims ->> 'purpose'), 'UTF8'
  ), 'sha256'), 'hex');
  bucket_started_at := to_timestamp(
    floor(extract(epoch from observed_at) / 60) * 60
  );
  insert into private.physical_android_authority_rate_limits (
    organization_id, purpose_sha256, window_started_at, request_count,
    updated_at
  ) values (
    p_organization_id, purpose_hash, bucket_started_at, 1, observed_at
  ) on conflict (organization_id, purpose_sha256, window_started_at)
  do update set
    request_count = private.physical_android_authority_rate_limits.request_count + 1,
    updated_at = excluded.updated_at
  returning request_count into next_count;
  delete from private.physical_android_authority_rate_limits
  where organization_id = p_organization_id
    and window_started_at < observed_at - interval '1 day';
  return jsonb_build_object(
    'allowed', next_count <= 20,
    'remaining', greatest(20 - next_count, 0),
    'resetAt', bucket_started_at + interval '60 seconds'
  );
end;
$$;

create or replace function public.register_physical_android_observer_identity(
  p_organization_id uuid,
  p_observer_id text,
  p_public_key_b64 text,
  p_allowed_repositories text[]
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  identity private.physical_android_observer_identities%rowtype;
  fingerprint text;
begin
  if session_user <> 'postgres' then
    raise exception 'database administrator required for physical observer enrollment'
      using errcode = '42501';
  end if;
  p_observer_id := lower(trim(coalesce(p_observer_id, '')));
  if p_observer_id !~ '^[a-z0-9][a-z0-9._:-]{2,127}$'
     or coalesce(p_public_key_b64, '') !~ '^[A-Za-z0-9+/]{43}=$'
     or p_allowed_repositories is distinct from array['banataosystems/Pandoras-box']::text[] then
    raise exception 'invalid physical Android observer identity' using errcode = '22023';
  end if;
  begin
    if octet_length(decode(p_public_key_b64, 'base64')) <> 32 then
      raise exception 'invalid physical Android observer key';
    end if;
  exception when others then
    raise exception 'invalid physical Android observer key' using errcode = '22023';
  end;
  fingerprint := encode(
    extensions.digest(decode(p_public_key_b64, 'base64'), 'sha256'), 'hex'
  );
  select * into identity
  from private.physical_android_observer_identities
  where organization_id = p_organization_id and observer_id = p_observer_id
  for update;
  if identity.observer_id is not null then
    if identity.public_key_b64 = p_public_key_b64
       and identity.key_fingerprint = fingerprint
       and identity.allowed_repositories = p_allowed_repositories
       and identity.status = 'active' then
      return jsonb_build_object(
        'observerId', identity.observer_id,
        'keyFingerprint', identity.key_fingerprint,
        'idempotentReplay', true
      );
    end if;
    raise exception 'physical Android observer rotation requires a governed action'
      using errcode = '55000';
  end if;
  insert into private.physical_android_observer_identities (
    organization_id, observer_id, public_key_b64, key_fingerprint,
    allowed_repositories
  ) values (
    p_organization_id, p_observer_id, p_public_key_b64, fingerprint,
    p_allowed_repositories
  ) returning * into identity;
  return jsonb_build_object(
    'observerId', identity.observer_id,
    'keyFingerprint', identity.key_fingerprint,
    'idempotentReplay', false
  );
end;
$$;

create or replace function public.resolve_physical_android_observer_identity(
  p_organization_id uuid,
  p_observer_id text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  identity private.physical_android_observer_identities%rowtype;
begin
  perform private.assert_control_service_role();
  select * into identity
  from private.physical_android_observer_identities
  where organization_id = p_organization_id
    and observer_id = lower(trim(coalesce(p_observer_id, '')))
    and status = 'active';
  if identity.observer_id is null then return null; end if;
  return jsonb_build_object(
    'observerId', identity.observer_id,
    'publicKeyB64', identity.public_key_b64,
    'keyFingerprint', identity.key_fingerprint,
    'allowedRepositories', identity.allowed_repositories
  );
end;
$$;

create or replace function public.capture_canonical_physical_android_receipt(
  p_organization_id uuid,
  p_request_id uuid,
  p_observer_id text,
  p_observer_key_fingerprint text,
  p_repository text,
  p_source_sha text,
  p_source_tree_sha text,
  p_production_deployment_id text,
  p_production_origin text,
  p_ci_artifact_external_id text,
  p_ci_artifact_url text,
  p_ci_artifact_name text,
  p_ci_artifact_sha256 text,
  p_apk_sha256 text,
  p_device_id_hash text,
  p_package_name text,
  p_network text,
  p_completed_steps text[],
  p_owner_plan_id uuid,
  p_owner_dispatch_id uuid,
  p_worker_evidence_sha256 text,
  p_verification_evidence_id uuid,
  p_reviewer_runtime_proof_id uuid,
  p_nonce text,
  p_timestamp text,
  p_signature_b64 text,
  p_signature_basis_sha256 text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  identity private.physical_android_observer_identities%rowtype;
  plan private.execution_plans%rowtype;
  dispatch private.execution_dispatch_outbox%rowtype;
  worker_review private.governed_worker_review_attestations%rowtype;
  wifi private.canonical_physical_android_receipts%rowtype;
  existing private.canonical_physical_android_receipts%rowtype;
  receipt private.canonical_physical_android_receipts%rowtype;
  authority_claims jsonb := auth.jwt();
  authority_issuer text;
  authority_jti text;
  authority_request_sha text;
  authority_iat_epoch numeric;
  authority_exp_epoch numeric;
  authority_nbf_epoch numeric;
  authority_issued_at timestamptz;
  authority_expires_at timestamptz;
  provider_observed_at timestamptz;
  signature_basis text;
  calculated_basis_sha text;
  nonce_sha text;
  receipt_sha text;
  observation_index smallint;
begin
  perform private.assert_physical_android_ingest_role();
  p_observer_id := lower(trim(coalesce(p_observer_id, '')));
  if p_request_id is null
     or p_observer_id !~ '^[a-z0-9][a-z0-9._:-]{2,127}$'
     or p_observer_key_fingerprint !~ '^[0-9a-f]{64}$'
     or p_repository <> 'banataosystems/Pandoras-box'
     or p_source_sha !~ '^[0-9a-f]{40}$'
     or p_source_tree_sha !~ '^[0-9a-f]{40}$'
     or p_production_deployment_id !~ '^dpl_[A-Za-z0-9]+$'
     or p_production_origin <> 'https://mcpmaster.vercel.app'
     or p_ci_artifact_external_id !~ '^[1-9][0-9]{0,19}$'
     or p_ci_artifact_url <> 'https://api.github.com/repos/banataosystems/Pandoras-box/actions/artifacts/' || p_ci_artifact_external_id
     or p_ci_artifact_name <> 'pandora-mobile-android-validation-' || p_source_sha
     or p_ci_artifact_sha256 !~ '^[0-9a-f]{64}$'
     or p_apk_sha256 !~ '^[0-9a-f]{64}$'
     or p_device_id_hash !~ '^[0-9a-f]{64}$'
     or p_package_name <> 'com.banataosystems.pandora_mobile'
     or p_network not in ('wifi', 'mobile_data')
     or p_completed_steps is distinct from array[
       'owner_authenticate', 'submit_owner_command', 'observe_durable_dispatch',
       'observe_worker_01_claim', 'observe_exact_provider_result',
       'observe_proof_in_owner_read'
     ]::text[]
     or p_owner_plan_id is null
     or p_owner_dispatch_id is null
     or p_worker_evidence_sha256 !~ '^[0-9a-f]{64}$'
     or p_verification_evidence_id is null
     or p_reviewer_runtime_proof_id is null
     or p_nonce !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{15,127}$'
     or p_timestamp !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$'
     or p_signature_b64 !~ '^[A-Za-z0-9+/]{86}==$'
     or p_signature_basis_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid canonical physical Android receipt' using errcode = '22023';
  end if;
  begin
    provider_observed_at := p_timestamp::timestamptz;
    if provider_observed_at > statement_timestamp() + interval '30 seconds'
       or provider_observed_at < statement_timestamp() - interval '5 minutes'
       or octet_length(decode(p_signature_b64, 'base64')) <> 64 then
      raise exception 'invalid canonical physical Android timestamp or signature';
    end if;
  exception when others then
    raise exception 'invalid canonical physical Android timestamp or signature'
      using errcode = '22023';
  end;

  observation_index := case p_network when 'wifi' then 1 else 2 end;
  signature_basis := concat_ws('|',
    'pandora-physical-android-request-v1', 'capture', p_organization_id::text,
    p_observer_id, p_observer_key_fingerprint, p_request_id::text,
    p_nonce, p_timestamp, p_repository,
    p_source_sha, p_source_tree_sha, p_production_deployment_id,
    p_production_origin, p_ci_artifact_external_id, p_ci_artifact_url,
    p_ci_artifact_name, p_ci_artifact_sha256, p_apk_sha256, p_device_id_hash,
    p_package_name, p_network, observation_index::text,
    array_to_string(p_completed_steps, ','), p_owner_plan_id::text,
    p_owner_dispatch_id::text, p_worker_evidence_sha256,
    p_verification_evidence_id::text, p_reviewer_runtime_proof_id::text
  );
  calculated_basis_sha := encode(
    extensions.digest(convert_to(signature_basis, 'UTF8'), 'sha256'), 'hex'
  );
  if calculated_basis_sha <> p_signature_basis_sha256 then
    raise exception 'physical Android signature basis mismatch' using errcode = '42501';
  end if;

  authority_request_sha := encode(extensions.digest(convert_to(
    signature_basis || '|' || p_signature_b64, 'UTF8'
  ), 'sha256'), 'hex');
  authority_issuer := coalesce(authority_claims ->> 'iss', '');
  authority_jti := coalesce(authority_claims ->> 'jti', '');
  if coalesce(authority_claims ->> 'role', '') <> 'projectos_physical_android_ingest'
     or authority_issuer <> 'pandora-physical-android-authority-v1'
     or coalesce(authority_claims ->> 'aud', '') <> 'projectos_physical_android_ingest'
     or coalesce(authority_claims ->> 'purpose', '') <> 'canonical_physical_android_capture'
     or coalesce(authority_claims ->> 'sub', '') <> p_observer_id
     or authority_jti !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{15,127}$'
     or coalesce(authority_claims ->> 'organization_id', '') <> p_organization_id::text
     or coalesce(authority_claims ->> 'observer_id', '') <> p_observer_id
     or coalesce(authority_claims ->> 'observer_key_fingerprint', '') <> p_observer_key_fingerprint
     or coalesce(authority_claims ->> 'request_id', '') <> p_request_id::text
     or coalesce(authority_claims ->> 'request_sha256', '') <> authority_request_sha
     or coalesce(authority_claims ->> 'network', '') <> p_network
     or coalesce(authority_claims ->> 'provider_observation_index', '') <> observation_index::text
     or coalesce(authority_claims ->> 'device_id_hash', '') <> p_device_id_hash
     or coalesce(authority_claims ->> 'iat', '') !~ '^[0-9]+(?:\.[0-9]+)?$'
     or coalesce(authority_claims ->> 'exp', '') !~ '^[0-9]+(?:\.[0-9]+)?$'
     or (
       authority_claims ? 'nbf'
       and coalesce(authority_claims ->> 'nbf', '') !~ '^[0-9]+(?:\.[0-9]+)?$'
     ) then
    raise exception 'external physical Android authority JWT required'
      using errcode = '42501';
  end if;
  authority_iat_epoch := (authority_claims ->> 'iat')::numeric;
  authority_exp_epoch := (authority_claims ->> 'exp')::numeric;
  authority_nbf_epoch := coalesce(
    nullif(authority_claims ->> 'nbf', '')::numeric,
    authority_iat_epoch
  );
  authority_issued_at := to_timestamp(authority_iat_epoch);
  authority_expires_at := to_timestamp(authority_exp_epoch);
  if authority_issued_at < statement_timestamp() - interval '2 minutes'
     or authority_issued_at > statement_timestamp() + interval '30 seconds'
     or to_timestamp(authority_nbf_epoch) > statement_timestamp() + interval '5 seconds'
     or authority_expires_at <= statement_timestamp()
     or authority_expires_at > authority_issued_at + interval '2 minutes' then
    raise exception 'fresh short-lived physical Android authority JWT required'
      using errcode = '42501';
  end if;

  select * into identity
  from private.physical_android_observer_identities
  where organization_id = p_organization_id
    and observer_id = p_observer_id
    and key_fingerprint = p_observer_key_fingerprint
    and status = 'active'
    and p_repository = any(allowed_repositories)
  for update;
  if identity.observer_id is null then
    raise exception 'active physical Android observer identity required'
      using errcode = '42501';
  end if;

  select * into plan
  from private.execution_plans
  where organization_id = p_organization_id
    and id = p_owner_plan_id
    and tool = 'projectos.worker.verify'
    and status in ('completed', 'failed')
    and args ->> 'repository' = p_repository
    and args ->> 'exactSha' = p_source_sha;
  select * into dispatch
  from private.execution_dispatch_outbox
  where organization_id = p_organization_id
    and id = p_owner_dispatch_id
    and plan_id = p_owner_plan_id
    and status in ('completed', 'failed')
    and worker_identity is not null
    and evidence_sha256 = p_worker_evidence_sha256
    and result_summary ->> 'repository' = p_repository
    and result_summary ->> 'exactSha' = p_source_sha
    and result_summary ->> 'sourceTreeSha' = p_source_tree_sha
    and verification_evidence_id = p_verification_evidence_id
    and verifier_runtime_proof_id = p_reviewer_runtime_proof_id
    and verified_outcome = status;
  select * into worker_review
  from private.governed_worker_review_attestations
  where organization_id = p_organization_id
    and dispatch_id = p_owner_dispatch_id
    and plan_id = p_owner_plan_id
    and evidence_id = p_verification_evidence_id
    and reviewer_runtime_proof_id = p_reviewer_runtime_proof_id
    and worker_evidence_sha256 = p_worker_evidence_sha256
    and repository = p_repository
    and exact_sha = p_source_sha
    and source_tree_sha = p_source_tree_sha
    and decision = dispatch.verified_outcome;
  if plan.id is null or dispatch.id is null or worker_review.id is null then
    raise exception 'exact owner plan, Worker-01 result, and reviewer proof required'
      using errcode = '42501';
  end if;

  delete from private.physical_android_authority_jtis consumed
  where consumed.authority_expires_at
    < statement_timestamp() - interval '5 minutes';
  insert into private.physical_android_authority_jtis (
    issuer, jti, organization_id, observer_id, request_id, request_sha256,
    authority_issued_at, authority_expires_at
  ) values (
    authority_issuer, authority_jti, p_organization_id, p_observer_id,
    p_request_id, authority_request_sha, authority_issued_at,
    authority_expires_at
  );

  select * into existing
  from private.canonical_physical_android_receipts candidate
  where candidate.organization_id = p_organization_id
    and (
      candidate.request_id = p_request_id
      or (candidate.repository = p_repository
        and candidate.source_sha = p_source_sha
        and candidate.production_deployment_id = p_production_deployment_id
        and candidate.device_id_hash = p_device_id_hash
        and candidate.network = p_network)
    )
  for update;
  if existing.id is not null then
    if existing.request_id = p_request_id
       and existing.observer_id = p_observer_id
       and existing.observer_key_fingerprint = p_observer_key_fingerprint
       and existing.repository = p_repository
       and existing.source_sha = p_source_sha
       and existing.source_tree_sha = p_source_tree_sha
       and existing.production_deployment_id = p_production_deployment_id
       and existing.ci_artifact_external_id = p_ci_artifact_external_id
       and existing.ci_artifact_sha256 = p_ci_artifact_sha256
       and existing.apk_sha256 = p_apk_sha256
       and existing.device_id_hash = p_device_id_hash
       and existing.network = p_network
       and existing.owner_plan_id = p_owner_plan_id
       and existing.owner_dispatch_id = p_owner_dispatch_id
       and existing.worker_evidence_sha256 = p_worker_evidence_sha256
       and existing.verification_evidence_id = p_verification_evidence_id
       and existing.reviewer_runtime_proof_id = p_reviewer_runtime_proof_id
       and existing.request_nonce = p_nonce
       and existing.signed_timestamp = p_timestamp
       and existing.signature_b64 = p_signature_b64
       and existing.signature_basis_sha256 = p_signature_basis_sha256 then
      return jsonb_build_object(
        'verified', true,
        'authority', 'PHYSICAL_ANDROID_OBSERVER',
        'storageAuthority', 'IMMUTABLE_PHYSICAL_ANDROID_RECEIPT',
        'receiptId', existing.id,
        'receiptSha256', existing.receipt_sha256,
        'network', existing.network,
        'providerObservationIndex', existing.provider_observation_index,
        'providerObservedAt', existing.provider_observed_at,
        'capturedAt', existing.captured_at,
        'idempotentReplay', true
      );
    end if;
    raise exception 'canonical physical Android receipt identity already used'
      using errcode = '23505';
  end if;

  if p_network = 'mobile_data' then
    select * into wifi
    from private.canonical_physical_android_receipts candidate
    where candidate.organization_id = p_organization_id
      and candidate.repository = p_repository
      and candidate.source_sha = p_source_sha
      and candidate.source_tree_sha = p_source_tree_sha
      and candidate.production_deployment_id = p_production_deployment_id
      and candidate.production_origin = p_production_origin
      and candidate.ci_artifact_external_id = p_ci_artifact_external_id
      and candidate.ci_artifact_sha256 = p_ci_artifact_sha256
      and candidate.apk_sha256 = p_apk_sha256
      and candidate.device_id_hash = p_device_id_hash
      and candidate.package_name = p_package_name
      and candidate.network = 'wifi'
      and candidate.owner_plan_id = p_owner_plan_id
      and candidate.owner_dispatch_id = p_owner_dispatch_id
      and candidate.worker_evidence_sha256 = p_worker_evidence_sha256
      and candidate.verification_evidence_id = p_verification_evidence_id
      and candidate.reviewer_runtime_proof_id = p_reviewer_runtime_proof_id
    for update;
    if wifi.id is null
       or provider_observed_at <= wifi.provider_observed_at
       or clock_timestamp() <= wifi.captured_at then
      raise exception 'ordered Wi-Fi observation required before mobile-data observation'
        using errcode = '55000';
    end if;
  elsif exists (
    select 1 from private.canonical_physical_android_receipts candidate
    where candidate.organization_id = p_organization_id
      and candidate.repository = p_repository
      and candidate.source_sha = p_source_sha
      and candidate.production_deployment_id = p_production_deployment_id
      and candidate.device_id_hash = p_device_id_hash
      and candidate.network = 'mobile_data'
  ) then
    raise exception 'Wi-Fi observation cannot be appended after mobile data'
      using errcode = '55000';
  end if;

  nonce_sha := encode(
    extensions.digest(convert_to(p_nonce, 'UTF8'), 'sha256'), 'hex'
  );
  receipt_sha := encode(extensions.digest(convert_to(concat_ws('|',
    'canonical-physical-android-receipt-v1', p_organization_id::text,
    p_request_id::text, p_observer_id, p_observer_key_fingerprint,
    p_repository, p_source_sha, p_source_tree_sha, p_production_deployment_id,
    p_production_origin, p_ci_artifact_external_id, p_ci_artifact_url,
    p_ci_artifact_name, p_ci_artifact_sha256, p_apk_sha256, p_device_id_hash,
    p_package_name, p_network, observation_index::text,
    array_to_string(p_completed_steps, ','), p_owner_plan_id::text,
    p_owner_dispatch_id::text, p_worker_evidence_sha256,
    p_verification_evidence_id::text, p_reviewer_runtime_proof_id::text,
    nonce_sha, p_timestamp, p_signature_basis_sha256,
    encode(extensions.digest(decode(p_signature_b64, 'base64'), 'sha256'), 'hex')
  ), 'UTF8'), 'sha256'), 'hex');

  insert into private.canonical_physical_android_receipts (
    organization_id, request_id, observer_id, observer_key_fingerprint,
    repository, source_sha, source_tree_sha, production_deployment_id,
    production_origin, ci_artifact_external_id, ci_artifact_url,
    ci_artifact_name, ci_artifact_sha256, apk_sha256, device_id_hash,
    package_name, network, provider_observation_index, completed_steps,
    owner_plan_id, owner_dispatch_id, worker_evidence_sha256,
    verification_evidence_id, reviewer_runtime_proof_id, request_nonce,
    nonce_sha256, signed_timestamp, provider_observed_at, signature_b64,
    signature_basis_sha256, receipt_sha256
  ) values (
    p_organization_id, p_request_id, p_observer_id,
    p_observer_key_fingerprint, p_repository, p_source_sha, p_source_tree_sha,
    p_production_deployment_id, p_production_origin, p_ci_artifact_external_id,
    p_ci_artifact_url, p_ci_artifact_name, p_ci_artifact_sha256, p_apk_sha256,
    p_device_id_hash, p_package_name, p_network, observation_index,
    p_completed_steps, p_owner_plan_id, p_owner_dispatch_id,
    p_worker_evidence_sha256, p_verification_evidence_id,
    p_reviewer_runtime_proof_id, p_nonce, nonce_sha, p_timestamp,
    provider_observed_at, p_signature_b64, p_signature_basis_sha256, receipt_sha
  ) returning * into receipt;

  return jsonb_build_object(
    'verified', true,
    'authority', 'PHYSICAL_ANDROID_OBSERVER',
    'storageAuthority', 'IMMUTABLE_PHYSICAL_ANDROID_RECEIPT',
    'receiptId', receipt.id,
    'receiptSha256', receipt.receipt_sha256,
    'network', receipt.network,
    'providerObservationIndex', receipt.provider_observation_index,
    'providerObservedAt', receipt.provider_observed_at,
    'capturedAt', receipt.captured_at,
    'ownerPlanId', receipt.owner_plan_id,
    'ownerDispatchId', receipt.owner_dispatch_id,
    'workerEvidenceSha256', receipt.worker_evidence_sha256,
    'verificationEvidenceId', receipt.verification_evidence_id,
    'reviewerRuntimeProofId', receipt.reviewer_runtime_proof_id
  );
end;
$$;

create or replace function public.get_canonical_physical_android_release_status(
  p_organization_id uuid,
  p_repository text,
  p_source_sha text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  wifi private.canonical_physical_android_receipts%rowtype;
  mobile private.canonical_physical_android_receipts%rowtype;
begin
  perform private.assert_control_service_role();
  select * into mobile
  from private.canonical_physical_android_receipts candidate
  where candidate.organization_id = p_organization_id
    and candidate.repository = p_repository
    and candidate.source_sha = p_source_sha
    and candidate.network = 'mobile_data'
  order by candidate.captured_at desc, candidate.id desc
  limit 1;
  if mobile.id is null then return null; end if;
  select * into wifi
  from private.canonical_physical_android_receipts candidate
  where candidate.organization_id = p_organization_id
    and candidate.repository = mobile.repository
    and candidate.source_sha = mobile.source_sha
    and candidate.source_tree_sha = mobile.source_tree_sha
    and candidate.production_deployment_id = mobile.production_deployment_id
    and candidate.production_origin = mobile.production_origin
    and candidate.ci_artifact_external_id = mobile.ci_artifact_external_id
    and candidate.ci_artifact_url = mobile.ci_artifact_url
    and candidate.ci_artifact_name = mobile.ci_artifact_name
    and candidate.ci_artifact_sha256 = mobile.ci_artifact_sha256
    and candidate.apk_sha256 = mobile.apk_sha256
    and candidate.device_id_hash = mobile.device_id_hash
    and candidate.package_name = mobile.package_name
    and candidate.owner_plan_id = mobile.owner_plan_id
    and candidate.owner_dispatch_id = mobile.owner_dispatch_id
    and candidate.worker_evidence_sha256 = mobile.worker_evidence_sha256
    and candidate.verification_evidence_id = mobile.verification_evidence_id
    and candidate.reviewer_runtime_proof_id = mobile.reviewer_runtime_proof_id
    and candidate.network = 'wifi'
    and candidate.provider_observed_at < mobile.provider_observed_at
    and candidate.captured_at < mobile.captured_at
  order by candidate.captured_at desc, candidate.id desc
  limit 1;
  if wifi.id is null then return null; end if;

  return jsonb_build_object(
    'authority', 'PHYSICAL_ANDROID_OBSERVER',
    'storageAuthority', 'IMMUTABLE_PHYSICAL_ANDROID_RECEIPT',
    'providerReadback', true,
    'sourceSha', mobile.source_sha,
    'sourceTreeSha', mobile.source_tree_sha,
    'deploymentId', mobile.production_deployment_id,
    'productionOrigin', mobile.production_origin,
    'artifactSha256', mobile.apk_sha256,
    'deviceIdHash', mobile.device_id_hash,
    'packageName', mobile.package_name,
    'ownerPlanId', mobile.owner_plan_id,
    'ownerDispatchId', mobile.owner_dispatch_id,
    'workerEvidenceSha256', mobile.worker_evidence_sha256,
    'verificationEvidenceId', mobile.verification_evidence_id,
    'reviewerRuntimeProofId', mobile.reviewer_runtime_proof_id,
    'ciArtifactDatabaseReceipt', jsonb_build_object(
      'databaseCaptured', true,
      'storageAuthority', 'IMMUTABLE_PHYSICAL_ANDROID_RECEIPT',
      'externalId', mobile.ci_artifact_external_id,
      'sourceUrl', mobile.ci_artifact_url,
      'artifactName', mobile.ci_artifact_name,
      'artifactSha256', mobile.ci_artifact_sha256,
      'apkSha256', mobile.apk_sha256,
      'sourceSha', mobile.source_sha,
      'sourceTreeSha', mobile.source_tree_sha,
      'productionOrigin', mobile.production_origin,
      'wifiEvidenceId', wifi.id,
      'mobileDataEvidenceId', mobile.id,
      'capturedAt', mobile.captured_at
    ),
    'wifi', jsonb_build_object(
      'network', wifi.network,
      'verified', true,
      'receiptId', wifi.id,
      'receiptSha256', wifi.receipt_sha256,
      'observerId', wifi.observer_id,
      'observerKeyFingerprint', wifi.observer_key_fingerprint,
      'signatureBasisSha256', wifi.signature_basis_sha256,
      'providerObservationIndex', wifi.provider_observation_index,
      'observedAt', wifi.provider_observed_at,
      'capturedAt', wifi.captured_at,
      'artifactSha256', wifi.apk_sha256,
      'completedSteps', to_jsonb(wifi.completed_steps)
    ),
    'mobileData', jsonb_build_object(
      'network', mobile.network,
      'verified', true,
      'receiptId', mobile.id,
      'receiptSha256', mobile.receipt_sha256,
      'observerId', mobile.observer_id,
      'observerKeyFingerprint', mobile.observer_key_fingerprint,
      'signatureBasisSha256', mobile.signature_basis_sha256,
      'providerObservationIndex', mobile.provider_observation_index,
      'observedAt', mobile.provider_observed_at,
      'capturedAt', mobile.captured_at,
      'artifactSha256', mobile.apk_sha256,
      'completedSteps', to_jsonb(mobile.completed_steps)
    )
  );
end;
$$;

alter table private.canonical_release_review_receipts
  add column physical_wifi_receipt_id uuid
    references private.canonical_physical_android_receipts(id) on delete restrict,
  add column physical_mobile_data_receipt_id uuid
    references private.canonical_physical_android_receipts(id) on delete restrict,
  add column physical_receipt_binding_sha256 text
    check (physical_receipt_binding_sha256 is null or physical_receipt_binding_sha256 ~ '^[0-9a-f]{64}$');

create or replace function private.bind_release_review_to_physical_android_receipts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  wifi private.canonical_physical_android_receipts%rowtype;
  mobile private.canonical_physical_android_receipts%rowtype;
begin
  select * into mobile
  from private.canonical_physical_android_receipts candidate
  where candidate.organization_id = new.organization_id
    and candidate.repository = new.repository
    and candidate.source_sha = new.source_sha
    and candidate.source_tree_sha = new.source_tree_sha
    and candidate.production_deployment_id = new.production_deployment_id
    and candidate.network = 'mobile_data'
    and candidate.provider_observed_at < new.reviewed_at
    and candidate.captured_at < new.reviewed_at
  order by candidate.captured_at desc, candidate.id desc
  limit 1;
  select * into wifi
  from private.canonical_physical_android_receipts candidate
  where candidate.organization_id = new.organization_id
    and candidate.repository = new.repository
    and candidate.source_sha = new.source_sha
    and candidate.source_tree_sha = new.source_tree_sha
    and candidate.production_deployment_id = new.production_deployment_id
    and candidate.production_origin = mobile.production_origin
    and candidate.ci_artifact_external_id = mobile.ci_artifact_external_id
    and candidate.ci_artifact_sha256 = mobile.ci_artifact_sha256
    and candidate.apk_sha256 = mobile.apk_sha256
    and candidate.device_id_hash = mobile.device_id_hash
    and candidate.owner_plan_id = mobile.owner_plan_id
    and candidate.owner_dispatch_id = mobile.owner_dispatch_id
    and candidate.worker_evidence_sha256 = mobile.worker_evidence_sha256
    and candidate.verification_evidence_id = mobile.verification_evidence_id
    and candidate.reviewer_runtime_proof_id = mobile.reviewer_runtime_proof_id
    and candidate.network = 'wifi'
    and candidate.provider_observed_at < mobile.provider_observed_at
    and candidate.captured_at < mobile.captured_at
  order by candidate.captured_at desc, candidate.id desc
  limit 1;
  if wifi.id is null or mobile.id is null then
    raise exception 'immutable ordered physical Android receipts required for release review'
      using errcode = '42501';
  end if;
  new.physical_wifi_receipt_id := wifi.id;
  new.physical_mobile_data_receipt_id := mobile.id;
  new.physical_receipt_binding_sha256 := encode(extensions.digest(convert_to(
    concat_ws('|', 'canonical-release-physical-binding-v1', wifi.id::text,
      wifi.receipt_sha256, mobile.id::text, mobile.receipt_sha256), 'UTF8'
  ), 'sha256'), 'hex');
  return new;
end;
$$;

create trigger bind_release_review_to_physical_android_receipts
before insert on private.canonical_release_review_receipts
for each row execute function private.bind_release_review_to_physical_android_receipts();

alter function public.get_canonical_release_status(uuid, text, text)
  rename to get_canonical_release_status_without_physical_android_authority;

create or replace function public.get_canonical_release_status(
  p_organization_id uuid,
  p_repository text,
  p_source_sha text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  base_status jsonb;
  android_status jsonb;
  review private.canonical_release_review_receipts%rowtype;
  owner private.canonical_release_owner_authorizations%rowtype;
  independent_review jsonb := null;
  owner_authorization jsonb := null;
begin
  perform private.assert_control_service_role();
  base_status := public.get_canonical_release_status_without_physical_android_authority(
    p_organization_id, p_repository, p_source_sha
  );
  android_status := public.get_canonical_physical_android_release_status(
    p_organization_id, p_repository, p_source_sha
  );
  if android_status is not null then
    select * into review
    from private.canonical_release_review_receipts candidate
    where candidate.organization_id = p_organization_id
      and candidate.repository = p_repository
      and candidate.source_sha = p_source_sha
      and candidate.source_tree_sha = android_status ->> 'sourceTreeSha'
      and candidate.production_deployment_id = android_status ->> 'deploymentId'
      and candidate.physical_wifi_receipt_id::text = android_status #>> '{wifi,receiptId}'
      and candidate.physical_mobile_data_receipt_id::text = android_status #>> '{mobileData,receiptId}'
      and candidate.physical_receipt_binding_sha256 ~ '^[0-9a-f]{64}$'
      and candidate.reviewed_at > (android_status #>> '{mobileData,observedAt}')::timestamptz
      and candidate.verdict = 'approved'
    order by candidate.captured_at desc, candidate.id desc
    limit 1;
    if review.id is not null then
      independent_review := jsonb_build_object(
        'verified', true,
        'authority', 'INDEPENDENT_REVIEWER',
        'receiptId', review.id,
        'receiptSha256', review.receipt_sha256,
        'sourceSha', review.source_sha,
        'sourceTreeSha', review.source_tree_sha,
        'productionDeploymentId', review.production_deployment_id,
        'rollbackDeploymentId', review.rollback_deployment_id,
        'supabaseMigrationChainSha256', review.supabase_migration_chain_sha256,
        'reviewerId', review.reviewer_id,
        'reviewerRuntimeProofId', review.reviewer_runtime_proof_id,
        'reviewerKeyFingerprint', review.reviewer_key_fingerprint,
        'reviewExternalId', review.review_external_id,
        'reviewSourceUrl', review.review_source_url,
        'reviewDigest', review.review_digest,
        'reviewedAt', review.reviewed_at,
        'capturedAt', review.captured_at,
        'physicalWifiReceiptId', review.physical_wifi_receipt_id,
        'physicalMobileDataReceiptId', review.physical_mobile_data_receipt_id,
        'physicalReceiptBindingSha256', review.physical_receipt_binding_sha256
      );
      select * into owner
      from private.canonical_release_owner_authorizations candidate
      where candidate.organization_id = p_organization_id
        and candidate.repository = p_repository
        and candidate.source_sha = p_source_sha
        and candidate.production_deployment_id = review.production_deployment_id
        and candidate.review_receipt_id = review.id
        and candidate.review_receipt_sha256 = review.receipt_sha256
        and candidate.aal = 'aal2'
        and candidate.authorized_at > review.captured_at
      order by candidate.captured_at desc, candidate.id desc
      limit 1;
      if owner.id is not null then
        owner_authorization := jsonb_build_object(
          'verified', true,
          'authority', 'OWNER_AUTHORIZATION',
          'receiptId', owner.id,
          'receiptSha256', owner.receipt_sha256,
          'ownerUserId', owner.owner_user_id,
          'sourceSha', owner.source_sha,
          'productionDeploymentId', owner.production_deployment_id,
          'reviewReceiptId', owner.review_receipt_id,
          'reviewReceiptSha256', owner.review_receipt_sha256,
          'aal', owner.aal,
          'sessionId', owner.session_id,
          'mfaVerifiedAt', owner.mfa_verified_at,
          'authorizedAt', owner.authorized_at,
          'capturedAt', owner.captured_at
        );
      end if;
    end if;
  end if;
  return (base_status - 'android' - 'independentReview' - 'ownerAuthorization')
    || jsonb_build_object(
      'android', android_status,
      'independentReview', independent_review,
      'ownerAuthorization', owner_authorization
    );
end;
$$;

revoke all on function private.assert_physical_android_ingest_role()
  from public, anon, authenticated, service_role, projectos_physical_android_ingest;
revoke all on function private.bind_release_review_to_physical_android_receipts()
  from public, anon, authenticated, service_role, projectos_physical_android_ingest;
revoke all on function public.consume_physical_android_authority_rate_limit(uuid)
  from public, anon, authenticated, service_role, projectos_physical_android_ingest;
revoke all on function public.register_physical_android_observer_identity(uuid,text,text,text[])
  from public, anon, authenticated, service_role, projectos_physical_android_ingest;
revoke all on function public.resolve_physical_android_observer_identity(uuid,text)
  from public, anon, authenticated, projectos_physical_android_ingest;
revoke all on function public.capture_canonical_physical_android_receipt(
  uuid,uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text[],uuid,uuid,text,uuid,uuid,text,text,text,text
) from public, anon, authenticated, service_role, projectos_physical_android_ingest;
revoke all on function public.get_canonical_physical_android_release_status(uuid,text,text)
  from public, anon, authenticated, projectos_physical_android_ingest;
revoke all on function public.get_canonical_release_status_without_physical_android_authority(uuid,text,text)
  from public, anon, authenticated;
revoke all on function public.get_canonical_release_status(uuid,text,text)
  from public, anon, authenticated;

grant execute on function public.resolve_physical_android_observer_identity(uuid,text)
  to service_role;
grant execute on function public.capture_canonical_physical_android_receipt(
  uuid,uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text[],uuid,uuid,text,uuid,uuid,text,text,text,text
) to projectos_physical_android_ingest;
grant execute on function public.consume_physical_android_authority_rate_limit(uuid)
  to projectos_physical_android_ingest;
grant execute on function public.get_canonical_physical_android_release_status(uuid,text,text)
  to service_role;
grant execute on function public.get_canonical_release_status_without_physical_android_authority(uuid,text,text)
  to service_role;
grant execute on function public.get_canonical_release_status(uuid,text,text)
  to service_role;
