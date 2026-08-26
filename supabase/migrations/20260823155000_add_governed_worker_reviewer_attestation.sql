-- Add a distinct, signed reviewer-attestation boundary for governed worker results.
-- Owners can finalize only evidence created through an enrolled reviewer key.

do $roles$
begin
  if not exists (
    select 1 from pg_roles where rolname = 'projectos_reviewer_ingest'
  ) then
    create role projectos_reviewer_ingest nologin noinherit;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticator') then
    execute 'grant projectos_reviewer_ingest to authenticator';
  end if;
end
$roles$;

grant usage on schema public to projectos_reviewer_ingest;

create table private.compute_reviewer_identities (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  reviewer_id text not null check (reviewer_id ~ '^[a-z0-9][a-z0-9._:-]{2,127}$'),
  runtime_proof_id uuid not null references public.projectos_agent_runtime_proofs(id) on delete restrict,
  vendor text not null check (vendor ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  public_key_b64 text not null check (public_key_b64 ~ '^[A-Za-z0-9+/]{43}=$'),
  key_fingerprint text not null check (key_fingerprint ~ '^[0-9a-f]{64}$'),
  allowed_repositories text[] not null check (cardinality(allowed_repositories) between 1 and 20),
  status text not null default 'active' check (status in ('active', 'draining', 'disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, reviewer_id),
  unique (organization_id, key_fingerprint)
);

create table private.compute_reviewer_nonces (
  organization_id uuid not null,
  reviewer_id text not null,
  nonce_sha256 text not null check (nonce_sha256 ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (organization_id, reviewer_id, nonce_sha256),
  foreign key (organization_id, reviewer_id)
    references private.compute_reviewer_identities(organization_id, reviewer_id)
    on delete cascade
);

create index compute_reviewer_nonces_expiry_idx
  on private.compute_reviewer_nonces (expires_at);

-- Independent authority arrives as a short-lived, exact-request JWT signed
-- outside this candidate repository. PostgREST verifies the JWT signature;
-- the database binds and atomically consumes its jti before any receipt write.
create table private.reviewer_ingest_token_nonces (
  issuer text not null check (issuer = 'pandora-independent-review-authority'),
  jti_sha256 text not null check (jti_sha256 ~ '^[0-9a-f]{64}$'),
  purpose text not null check (purpose in ('worker_review', 'release_review')),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  reviewer_id text not null,
  request_sha256 text not null check (request_sha256 ~ '^[0-9a-f]{64}$'),
  token_issued_at timestamptz not null,
  expires_at timestamptz not null,
  consumed_at timestamptz not null default clock_timestamp(),
  foreign key (organization_id, reviewer_id)
    references private.compute_reviewer_identities(organization_id, reviewer_id)
    on delete cascade,
  check (expires_at > token_issued_at),
  check (consumed_at >= token_issued_at),
  primary key (issuer, jti_sha256)
);

create index reviewer_ingest_token_nonces_expiry_idx
  on private.reviewer_ingest_token_nonces (
    organization_id, reviewer_id, purpose, expires_at
  );

create table private.governed_worker_review_attestations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  request_id uuid not null,
  dispatch_id uuid not null references private.execution_dispatch_outbox(id) on delete restrict,
  plan_id uuid not null references private.execution_plans(id) on delete restrict,
  reviewer_id text not null,
  reviewer_runtime_proof_id uuid not null references public.projectos_agent_runtime_proofs(id) on delete restrict,
  reviewer_key_fingerprint text not null check (reviewer_key_fingerprint ~ '^[0-9a-f]{64}$'),
  reviewer_nonce_sha256 text not null check (reviewer_nonce_sha256 ~ '^[0-9a-f]{64}$'),
  signed_timestamp text not null check (
    signed_timestamp ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$'
  ),
  signed_at timestamptz not null,
  signature_b64 text not null check (signature_b64 ~ '^[A-Za-z0-9+/]{86}==$'),
  signature_basis_sha256 text not null check (signature_basis_sha256 ~ '^[0-9a-f]{64}$'),
  evidence_id uuid not null unique references public.projectos_evidence(id) on delete restrict,
  decision text not null check (decision in ('completed', 'failed')),
  worker_evidence_sha256 text not null check (worker_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  review_artifact_sha256 text not null check (review_artifact_sha256 ~ '^[0-9a-f]{64}$'),
  repository text not null check (repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  exact_sha text not null check (exact_sha ~ '^[0-9a-f]{40}$'),
  source_tree_sha text not null check (source_tree_sha ~ '^[0-9a-f]{40}$'),
  created_at timestamptz not null default now(),
  unique (organization_id, request_id),
  unique (organization_id, dispatch_id),
  unique (organization_id, reviewer_id, reviewer_nonce_sha256),
  foreign key (organization_id, reviewer_id)
    references private.compute_reviewer_identities(organization_id, reviewer_id)
    on delete restrict
);

alter table private.compute_reviewer_identities enable row level security;
alter table private.compute_reviewer_nonces enable row level security;
alter table private.reviewer_ingest_token_nonces enable row level security;
alter table private.governed_worker_review_attestations enable row level security;

revoke all on table private.compute_reviewer_identities
  from public, anon, authenticated, service_role;
revoke all on table private.compute_reviewer_nonces
  from public, anon, authenticated, service_role;
revoke all on table private.reviewer_ingest_token_nonces
  from public, anon, authenticated, service_role, projectos_reviewer_ingest;
revoke all on table private.governed_worker_review_attestations
  from public, anon, authenticated, service_role, projectos_reviewer_ingest;

create or replace function private.assert_reviewer_ingest_role()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if session_user <> 'postgres'
     and coalesce(auth.jwt() ->> 'role', '') <> 'projectos_reviewer_ingest' then
    raise exception 'reviewer ingest role required' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.assert_reviewer_ingest_role()
  from public, anon, authenticated, service_role, projectos_reviewer_ingest;

create or replace function private.assert_reviewer_ingest_request(
  p_purpose text,
  p_organization_id uuid,
  p_reviewer_id text,
  p_request_sha256 text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_reviewer_id text := lower(trim(coalesce(p_reviewer_id, '')));
  claims jsonb := auth.jwt();
  token_issuer text;
  token_jti text;
  token_iat_epoch numeric;
  token_nbf_epoch numeric;
  token_exp_epoch numeric;
  token_iat timestamptz;
  token_nbf timestamptz;
  token_exp timestamptz;
  accepted_jti text;
begin
  token_issuer := coalesce(claims ->> 'iss', '');
  if p_purpose not in ('worker_review', 'release_review')
     or p_organization_id is null
     or normalized_reviewer_id !~ '^[a-z0-9][a-z0-9._:-]{2,127}$'
     or coalesce(p_request_sha256, '') !~ '^[0-9a-f]{64}$'
     or coalesce(claims ->> 'role', '') <> 'projectos_reviewer_ingest'
     or token_issuer <> 'pandora-independent-review-authority'
     or coalesce(claims ->> 'pandora_audience', '') <> 'projectos-reviewer-ingest'
     or coalesce(claims ->> 'pandora_purpose', '') <> p_purpose
     or coalesce(claims ->> 'pandora_organization_id', '') <> p_organization_id::text
     or lower(coalesce(claims ->> 'pandora_reviewer_id', '')) <> normalized_reviewer_id
     or coalesce(claims ->> 'pandora_request_sha256', '') <> p_request_sha256 then
    raise exception 'exact external reviewer authority required' using errcode = '42501';
  end if;
  token_jti := coalesce(claims ->> 'jti', '');
  if token_jti !~ '^[A-Za-z0-9._:-]{16,128}$'
     or coalesce(claims ->> 'iat', '') !~ '^[0-9]+(?:\.[0-9]+)?$'
     or coalesce(claims ->> 'nbf', '') !~ '^[0-9]+(?:\.[0-9]+)?$'
     or coalesce(claims ->> 'exp', '') !~ '^[0-9]+(?:\.[0-9]+)?$' then
    raise exception 'valid short-lived reviewer authority token required' using errcode = '42501';
  end if;
  token_iat_epoch := (claims ->> 'iat')::numeric;
  token_nbf_epoch := (claims ->> 'nbf')::numeric;
  token_exp_epoch := (claims ->> 'exp')::numeric;
  token_iat := to_timestamp(token_iat_epoch);
  token_nbf := to_timestamp(token_nbf_epoch);
  token_exp := to_timestamp(token_exp_epoch);
  if token_iat < statement_timestamp() - interval '2 minutes'
     or token_iat > statement_timestamp() + interval '30 seconds'
     or token_nbf < token_iat - interval '5 seconds'
     or token_nbf > statement_timestamp() + interval '30 seconds'
     or token_exp <= statement_timestamp()
     or token_exp > statement_timestamp() + interval '2 minutes'
     or token_exp - token_iat > interval '2 minutes' then
    raise exception 'valid short-lived reviewer authority token required' using errcode = '42501';
  end if;

  delete from private.reviewer_ingest_token_nonces nonce
  where nonce.expires_at <= statement_timestamp() - interval '5 minutes';
  insert into private.reviewer_ingest_token_nonces (
    issuer, jti_sha256, purpose, organization_id, reviewer_id,
    request_sha256, token_issued_at, expires_at
  ) values (
    token_issuer,
    encode(extensions.digest(convert_to(token_jti, 'UTF8'), 'sha256'), 'hex'),
    p_purpose,
    p_organization_id,
    normalized_reviewer_id,
    p_request_sha256,
    token_iat,
    token_exp
  ) on conflict do nothing
  returning jti_sha256 into accepted_jti;
  if accepted_jti is null then
    raise exception 'reviewer authority token already consumed' using errcode = '23505';
  end if;
end;
$$;

revoke all on function private.assert_reviewer_ingest_request(text,uuid,text,text)
  from public, anon, authenticated, service_role, projectos_reviewer_ingest;

create or replace function public.register_compute_reviewer_identity(
  p_organization_id uuid,
  p_runtime_proof_id uuid,
  p_reviewer_id text,
  p_public_key_b64 text,
  p_allowed_repositories text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  proof public.projectos_agent_runtime_proofs%rowtype;
  identity private.compute_reviewer_identities%rowtype;
  normalized_repositories text[];
  fingerprint text;
  canonical_vendor text;
begin
  if session_user <> 'postgres' then
    raise exception 'database administrator required for reviewer enrollment'
      using errcode = '42501';
  end if;
  p_reviewer_id := lower(trim(coalesce(p_reviewer_id, '')));
  if p_reviewer_id !~ '^[a-z0-9][a-z0-9._:-]{2,127}$'
     or coalesce(p_public_key_b64, '') !~ '^[A-Za-z0-9+/]{43}=$' then
    raise exception 'invalid reviewer identity' using errcode = '22023';
  end if;
  begin
    if octet_length(decode(p_public_key_b64, 'base64')) <> 32 then
      raise exception 'invalid reviewer key length' using errcode = '22023';
    end if;
  exception when others then
    raise exception 'invalid reviewer public key' using errcode = '22023';
  end;

  select coalesce(array_agg(distinct repository order by repository), '{}'::text[])
  into normalized_repositories
  from unnest(coalesce(p_allowed_repositories, '{}'::text[])) repository;
  if normalized_repositories <> coalesce(p_allowed_repositories, '{}'::text[])
     or cardinality(normalized_repositories) <> 1
     or normalized_repositories[1] <> 'pandora-rvw-314296438-20260820/pandoras-box' then
    raise exception 'invalid reviewer repository scopes' using errcode = '22023';
  end if;

  select * into proof
  from public.projectos_agent_runtime_proofs
  where id = p_runtime_proof_id
    and organization_id = p_organization_id
  for update;
  canonical_vendor := private.projectos_canonical_agent_vendor(proof.vendor);
  if proof.id is null
     or proof.agent_key <> p_reviewer_id
     or proof.role <> 'reviewer'
     or proof.verified_by = proof.agent_key
     or not proof.is_active
     or proof.expires_at <= now()
     or proof.verified_at < now() - interval '2 hours'
     or proof.context_updated_at < now() - interval '30 minutes'
     or proof.credential_state <> 'ready'
     or proof.quota_state not in ('available', 'limited')
     or proof.health_state <> 'healthy'
     or canonical_vendor is null
     or not (normalized_repositories <@ proof.repository_scopes)
     or not (
       'projectos.worker.verify.review' = any(proof.proven_capabilities)
       or 'projectos.worker.verify.review:node_regression' = any(proof.proven_capabilities)
       or 'projectos.worker.verify.review:supabase_migration_replay' = any(proof.proven_capabilities)
       or 'projectos.release.review' = any(proof.proven_capabilities)
     ) then
    raise exception 'fresh reviewer runtime proof unavailable'
      using errcode = '42501';
  end if;

  fingerprint := encode(
    extensions.digest(decode(p_public_key_b64, 'base64'), 'sha256'),
    'hex'
  );
  select * into identity
  from private.compute_reviewer_identities
  where organization_id = p_organization_id and reviewer_id = p_reviewer_id
  for update;
  if identity.reviewer_id is not null then
    if identity.runtime_proof_id = p_runtime_proof_id
       and identity.vendor = canonical_vendor
       and identity.public_key_b64 = p_public_key_b64
       and identity.key_fingerprint = fingerprint
       and identity.allowed_repositories = normalized_repositories
       and identity.status = 'active' then
      return jsonb_build_object(
        'reviewerId', identity.reviewer_id,
        'keyFingerprint', identity.key_fingerprint,
        'runtimeProofId', identity.runtime_proof_id,
        'idempotentReplay', true
      );
    end if;
    raise exception 'reviewer identity rotation requires a separate governed action'
      using errcode = '55000';
  end if;

  insert into private.compute_reviewer_identities (
    organization_id, reviewer_id, runtime_proof_id, vendor,
    public_key_b64, key_fingerprint, allowed_repositories
  ) values (
    p_organization_id, p_reviewer_id, p_runtime_proof_id, canonical_vendor,
    p_public_key_b64, fingerprint, normalized_repositories
  ) returning * into identity;

  return jsonb_build_object(
    'reviewerId', identity.reviewer_id,
    'keyFingerprint', identity.key_fingerprint,
    'runtimeProofId', identity.runtime_proof_id,
    'idempotentReplay', false
  );
end;
$$;

create or replace function public.resolve_compute_reviewer_identity(
  p_organization_id uuid,
  p_reviewer_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  identity private.compute_reviewer_identities%rowtype;
begin
  perform private.assert_control_service_role();
  select * into identity
  from private.compute_reviewer_identities
  where organization_id = p_organization_id
    and reviewer_id = lower(trim(coalesce(p_reviewer_id, '')))
    and status = 'active';
  if identity.reviewer_id is null then return null; end if;
  return jsonb_build_object(
    'reviewerId', identity.reviewer_id,
    'runtimeProofId', identity.runtime_proof_id,
    'vendor', identity.vendor,
    'publicKeyB64', identity.public_key_b64,
    'keyFingerprint', identity.key_fingerprint,
    'allowedRepositories', identity.allowed_repositories
  );
end;
$$;

create or replace function public.consume_compute_reviewer_nonce(
  p_organization_id uuid,
  p_reviewer_id text,
  p_expected_key_fingerprint text,
  p_nonce text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_reviewer_id text;
  nonce_hash text;
  accepted_reviewer text;
  active_nonce_count integer;
begin
  perform private.assert_control_service_role();
  normalized_reviewer_id := lower(trim(coalesce(p_reviewer_id, '')));
  if normalized_reviewer_id !~ '^[a-z0-9][a-z0-9._:-]{2,127}$'
     or coalesce(p_expected_key_fingerprint, '') !~ '^[0-9a-f]{64}$'
     or coalesce(p_nonce, '') !~ '^[A-Za-z0-9._:-]{16,128}$' then
    raise exception 'invalid reviewer nonce request' using errcode = '22023';
  end if;

  perform 1
  from private.compute_reviewer_identities identity
  where identity.organization_id = p_organization_id
    and identity.reviewer_id = normalized_reviewer_id
    and identity.key_fingerprint = p_expected_key_fingerprint
    and identity.status = 'active'
  for update;
  if not found then
    raise exception 'reviewer key fingerprint changed' using errcode = '42501';
  end if;

  delete from private.compute_reviewer_nonces
  where expires_at <= now();
  select count(*)::integer into active_nonce_count
  from private.compute_reviewer_nonces
  where organization_id = p_organization_id
    and reviewer_id = normalized_reviewer_id
    and expires_at > now();
  if active_nonce_count >= 2048 then
    raise exception 'reviewer nonce retention cap reached' using errcode = '54000';
  end if;

  nonce_hash := encode(
    extensions.digest(convert_to(p_nonce, 'UTF8'), 'sha256'),
    'hex'
  );
  insert into private.compute_reviewer_nonces (
    organization_id, reviewer_id, nonce_sha256, expires_at
  ) values (
    p_organization_id, normalized_reviewer_id, nonce_hash,
    now() + interval '15 minutes'
  ) on conflict do nothing
  returning reviewer_id into accepted_reviewer;
  if accepted_reviewer is null then
    raise exception 'reviewer nonce already used' using errcode = '23505';
  end if;
  update private.compute_reviewer_identities
  set updated_at = now()
  where organization_id = p_organization_id
    and reviewer_id = normalized_reviewer_id;
  return jsonb_build_object('accepted', true);
end;
$$;

create or replace function public.record_governed_worker_review_attestation(
  p_organization_id uuid,
  p_request_id uuid,
  p_reviewer_id text,
  p_expected_key_fingerprint text,
  p_dispatch_id uuid,
  p_plan_id uuid,
  p_verifier_runtime_proof_id uuid,
  p_worker_evidence_sha256 text,
  p_repository text,
  p_exact_sha text,
  p_source_tree_sha text,
  p_decision text,
  p_review_artifact_sha256 text,
  p_nonce text,
  p_timestamp text,
  p_signature_b64 text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  identity private.compute_reviewer_identities%rowtype;
  dispatch private.execution_dispatch_outbox%rowtype;
  plan private.execution_plans%rowtype;
  intake public.projectos_intake_requests%rowtype;
  proof public.projectos_agent_runtime_proofs%rowtype;
  existing private.governed_worker_review_attestations%rowtype;
  evidence public.projectos_evidence%rowtype;
  require_independent_vendor boolean;
  terminal_decision text;
  evidence_status text;
  evidence_verdict text;
  reviewer_nonce_sha256 text;
  signature_basis text;
  signature_basis_sha256 text;
  signature_sha256 text;
  authority_request_sha256 text;
  signed_at timestamptz;
  accepted_nonce text;
  active_nonce_count integer;
begin
  perform private.assert_reviewer_ingest_role();
  p_reviewer_id := lower(trim(coalesce(p_reviewer_id, '')));
  p_decision := lower(trim(coalesce(p_decision, '')));
  terminal_decision := case p_decision
    when 'pass' then 'completed'
    when 'fail' then 'failed'
    else null
  end;
  if terminal_decision is null
     or p_reviewer_id !~ '^[a-z0-9][a-z0-9._:-]{2,127}$'
     or coalesce(p_expected_key_fingerprint, '') !~ '^[0-9a-f]{64}$'
     or coalesce(p_worker_evidence_sha256, '') !~ '^[0-9a-f]{64}$'
     or coalesce(p_repository, '') <> 'pandora-rvw-314296438-20260820/pandoras-box'
     or coalesce(p_exact_sha, '') !~ '^[0-9a-f]{40}$'
     or coalesce(p_source_tree_sha, '') !~ '^[0-9a-f]{40}$'
     or coalesce(p_review_artifact_sha256, '') !~ '^[0-9a-f]{64}$'
     or coalesce(p_nonce, '') !~ '^[A-Za-z0-9._:-]{16,128}$'
     or coalesce(p_timestamp, '') !~
       '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$'
     or coalesce(p_signature_b64, '') !~ '^[A-Za-z0-9+/]{86}==$' then
    raise exception 'invalid governed worker review attestation'
      using errcode = '22023';
  end if;
  begin
    signed_at := p_timestamp::timestamptz;
    if octet_length(decode(p_signature_b64, 'base64')) <> 64
       or abs(extract(epoch from (now() - signed_at))) > 300 then
      raise exception 'invalid reviewer signature envelope' using errcode = '22023';
    end if;
  exception when others then
    raise exception 'invalid reviewer signature envelope' using errcode = '22023';
  end;

  reviewer_nonce_sha256 := encode(
    extensions.digest(convert_to(p_nonce, 'UTF8'), 'sha256'),
    'hex'
  );
  signature_basis := concat_ws(
    '|',
    'pandora-reviewer-request-v1',
    'attest',
    p_organization_id::text,
    p_reviewer_id,
    p_request_id::text,
    p_nonce,
    p_timestamp,
    p_dispatch_id::text,
    p_plan_id::text,
    p_verifier_runtime_proof_id::text,
    p_worker_evidence_sha256,
    p_repository,
    p_exact_sha,
    p_source_tree_sha,
    p_decision,
    p_review_artifact_sha256
  );
  signature_basis_sha256 := encode(
    extensions.digest(convert_to(signature_basis, 'UTF8'), 'sha256'),
    'hex'
  );
  signature_sha256 := encode(
    extensions.digest(decode(p_signature_b64, 'base64'), 'sha256'),
    'hex'
  );
  authority_request_sha256 := encode(
    extensions.digest(
      convert_to(concat_ws(
        '|',
        'pandora-reviewer-authority-v1',
        signature_basis_sha256,
        p_expected_key_fingerprint,
        signature_sha256
      ), 'UTF8'),
      'sha256'
    ),
    'hex'
  );
  perform private.assert_reviewer_ingest_request(
    'worker_review',
    p_organization_id,
    p_reviewer_id,
    authority_request_sha256
  );

  select * into identity
  from private.compute_reviewer_identities
  where organization_id = p_organization_id
    and reviewer_id = p_reviewer_id
    and key_fingerprint = p_expected_key_fingerprint
    and runtime_proof_id = p_verifier_runtime_proof_id
    and status = 'active'
  for update;
  if identity.reviewer_id is null
     or not (p_repository = any(identity.allowed_repositories)) then
    raise exception 'reviewer identity binding mismatch' using errcode = '42501';
  end if;

  select * into existing
  from private.governed_worker_review_attestations
  where organization_id = p_organization_id
    and (dispatch_id = p_dispatch_id or request_id = p_request_id)
  for update;
  if existing.id is not null then
    if existing.request_id = p_request_id
       and existing.dispatch_id = p_dispatch_id
       and existing.plan_id = p_plan_id
       and existing.reviewer_id = p_reviewer_id
       and existing.reviewer_runtime_proof_id = p_verifier_runtime_proof_id
       and existing.reviewer_key_fingerprint = p_expected_key_fingerprint
       and existing.reviewer_nonce_sha256 = reviewer_nonce_sha256
       and existing.signed_timestamp = p_timestamp
       and existing.signature_b64 = p_signature_b64
       and existing.signature_basis_sha256 = signature_basis_sha256
       and existing.decision = terminal_decision
       and existing.worker_evidence_sha256 = p_worker_evidence_sha256
       and existing.review_artifact_sha256 = p_review_artifact_sha256
       and existing.repository = p_repository
       and existing.exact_sha = p_exact_sha
       and existing.source_tree_sha = p_source_tree_sha then
      return jsonb_build_object(
        'dispatchId', existing.dispatch_id,
        'planId', existing.plan_id,
        'status', 'attested',
        'decision', existing.decision,
        'verificationEvidenceId', existing.evidence_id,
        'verifierRuntimeProofId', existing.reviewer_runtime_proof_id,
        'workerEvidenceSha256', existing.worker_evidence_sha256,
        'reviewArtifactSha256', existing.review_artifact_sha256,
        'signatureBasisSha256', existing.signature_basis_sha256,
        'idempotentReplay', true
      );
    end if;
    raise exception 'terminal reviewer attestation differs' using errcode = '55000';
  end if;

  select * into dispatch
  from private.execution_dispatch_outbox
  where organization_id = p_organization_id
    and id = p_dispatch_id
    and plan_id = p_plan_id
  for update;
  if dispatch.id is null
     or dispatch.status <> 'result_reported'
     or dispatch.worker_reported_at is null
     or dispatch.evidence_sha256 is distinct from p_worker_evidence_sha256
     or dispatch.result_summary is null
     or dispatch.result_summary ->> 'sourceTreeSha' is distinct from p_source_tree_sha then
    raise exception 'reviewed worker result binding mismatch' using errcode = '55000';
  end if;

  select * into plan
  from private.execution_plans
  where organization_id = p_organization_id and id = p_plan_id
  for update;
  if plan.id is null
     or plan.status <> 'executing'
     or not private.projectos_worker_plan_is_valid(
       plan.tool, plan.risk, plan.args, plan.payload_hash
     )
     or plan.args ->> 'repository' is distinct from p_repository
     or plan.args ->> 'exactSha' is distinct from p_exact_sha then
    raise exception 'reviewed worker plan binding mismatch' using errcode = '55000';
  end if;
  if terminal_decision = 'completed'
     and dispatch.result_summary ->> 'outcome' is distinct from 'completed' then
    raise exception 'failed worker result cannot receive a passing review'
      using errcode = '55000';
  end if;

  select * into intake
  from public.projectos_intake_requests
  where organization_id = p_organization_id and id = plan.intake_id;
  if intake.id is null then
    raise exception 'reviewed worker intake missing' using errcode = '55000';
  end if;

  select * into proof
  from public.projectos_agent_runtime_proofs
  where id = p_verifier_runtime_proof_id
    and organization_id = p_organization_id
    and project_id = intake.project_id
    and role = 'reviewer'
    and agent_key = p_reviewer_id
    and agent_key <> dispatch.worker_identity
    and verified_by <> dispatch.worker_identity
    and verified_by <> agent_key
    and is_active
    and expires_at > now()
    and verified_at >= now() - interval '2 hours'
    and context_updated_at >= now() - interval '30 minutes'
    and credential_state = 'ready'
    and quota_state in ('available', 'limited')
    and health_state = 'healthy'
    and p_repository = any(repository_scopes)
    and (
      'projectos.worker.verify.review' = any(proven_capabilities)
      or ('projectos.worker.verify.review:' || (plan.args ->> 'jobClass')) =
        any(proven_capabilities)
    )
  for update;
  if proof.id is null
     or private.projectos_canonical_agent_vendor(proof.vendor) is distinct from identity.vendor then
    raise exception 'fresh bound reviewer runtime proof unavailable'
      using errcode = '42501';
  end if;

  select coalesce(policy.require_independent_vendor_review, true)
  into require_independent_vendor
  from public.projectos_policies policy
  where policy.organization_id = p_organization_id;
  require_independent_vendor := coalesce(require_independent_vendor, true);
  if require_independent_vendor
     and private.projectos_canonical_agent_vendor(proof.vendor) =
       private.projectos_canonical_agent_vendor(dispatch.builder_vendor) then
    raise exception 'reviewer vendor is not independent from worker builder'
      using errcode = '42501';
  end if;

  with expired as (
    select organization_id, reviewer_id, nonce_sha256
    from private.compute_reviewer_nonces
    where expires_at <= now()
    order by expires_at
    for update skip locked
    limit 128
  )
  delete from private.compute_reviewer_nonces nonce
  using expired
  where nonce.organization_id = expired.organization_id
    and nonce.reviewer_id = expired.reviewer_id
    and nonce.nonce_sha256 = expired.nonce_sha256;
  select count(*)::integer into active_nonce_count
  from private.compute_reviewer_nonces
  where organization_id = p_organization_id
    and reviewer_id = p_reviewer_id
    and expires_at > now();
  if active_nonce_count >= 2048 then
    raise exception 'reviewer nonce retention cap reached' using errcode = '54000';
  end if;
  insert into private.compute_reviewer_nonces (
    organization_id, reviewer_id, nonce_sha256, expires_at
  ) values (
    p_organization_id, p_reviewer_id, reviewer_nonce_sha256,
    now() + interval '15 minutes'
  ) on conflict do nothing
  returning reviewer_id into accepted_nonce;
  if accepted_nonce is null then
    raise exception 'reviewer nonce already used' using errcode = '23505';
  end if;

  evidence_status := case when terminal_decision = 'completed' then 'passing' else 'failing' end;
  evidence_verdict := case when terminal_decision = 'completed' then 'pass' else 'fail' end;
  insert into public.projectos_evidence (
    organization_id, project_id, evidence_type, provider, external_id,
    repository, head_sha, status, verdict, payload_redacted, observed_at
  ) values (
    p_organization_id,
    intake.project_id,
    'worker_dispatch_review',
    identity.vendor,
    'governed-worker-review:' || dispatch.id::text,
    p_repository,
    p_exact_sha,
    evidence_status,
    evidence_verdict,
    jsonb_build_object(
      'schemaVersion', 1,
      'dispatchId', dispatch.id,
      'planId', plan.id,
      'workerEvidenceSha256', p_worker_evidence_sha256,
      'reviewerAgent', identity.reviewer_id,
      'reviewerVendor', identity.vendor,
      'reviewerRuntimeProofId', proof.id,
      'reviewerKeyFingerprint', identity.key_fingerprint,
      'reviewerNonceSha256', reviewer_nonce_sha256,
      'signedTimestamp', p_timestamp,
      'signatureB64', p_signature_b64,
      'signatureBasisSha256', signature_basis_sha256,
      'reviewArtifactSha256', p_review_artifact_sha256,
      'sourceTreeSha', p_source_tree_sha,
      'decision', terminal_decision
    ),
    now()
  ) returning * into evidence;

  insert into private.governed_worker_review_attestations (
    organization_id, request_id, dispatch_id, plan_id, reviewer_id,
    reviewer_runtime_proof_id, reviewer_key_fingerprint,
    reviewer_nonce_sha256, signed_timestamp, signed_at,
    signature_b64, signature_basis_sha256, evidence_id,
    decision, worker_evidence_sha256, review_artifact_sha256,
    repository, exact_sha, source_tree_sha
  ) values (
    p_organization_id, p_request_id, p_dispatch_id, p_plan_id, p_reviewer_id,
    p_verifier_runtime_proof_id, p_expected_key_fingerprint,
    reviewer_nonce_sha256, p_timestamp, signed_at,
    p_signature_b64, signature_basis_sha256, evidence.id,
    terminal_decision, p_worker_evidence_sha256, p_review_artifact_sha256,
    p_repository, p_exact_sha, p_source_tree_sha
  ) returning * into existing;

  perform private.append_execution_audit(
    p_organization_id,
    plan.id,
    plan.request_id,
    'worker_dispatch_review_attested',
    plan.status,
    plan.tool,
    plan.risk,
    plan.payload_hash,
    jsonb_build_object(
      'dispatchId', dispatch.id,
      'reviewerAgent', identity.reviewer_id,
      'reviewerVendor', identity.vendor,
      'reviewerRuntimeProofId', proof.id,
      'reviewerKeyFingerprint', identity.key_fingerprint,
      'reviewerNonceSha256', reviewer_nonce_sha256,
      'signedTimestamp', p_timestamp,
      'signatureBasisSha256', signature_basis_sha256,
      'verificationEvidenceId', evidence.id,
      'workerEvidenceSha256', p_worker_evidence_sha256,
      'reviewArtifactSha256', p_review_artifact_sha256,
      'sourceTreeSha', p_source_tree_sha,
      'decision', terminal_decision
    )
  );

  return jsonb_build_object(
    'dispatchId', dispatch.id,
    'planId', plan.id,
    'status', 'attested',
    'decision', terminal_decision,
    'verificationEvidenceId', evidence.id,
    'verifierRuntimeProofId', proof.id,
    'workerEvidenceSha256', p_worker_evidence_sha256,
    'reviewArtifactSha256', p_review_artifact_sha256,
    'signatureBasisSha256', signature_basis_sha256,
    'idempotentReplay', false
  );
end;
$$;

create or replace function private.guard_governed_worker_review_attestation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'finalizing'
     and old.status = 'result_reported'
     and not exists (
       select 1
       from private.governed_worker_review_attestations attestation
       where attestation.organization_id = new.organization_id
         and attestation.dispatch_id = new.id
         and attestation.plan_id = new.plan_id
         and attestation.reviewer_runtime_proof_id = new.verifier_runtime_proof_id
         and attestation.evidence_id = new.verification_evidence_id
         and attestation.decision = new.verified_outcome
         and attestation.worker_evidence_sha256 = new.evidence_sha256
         and attestation.source_tree_sha = new.result_summary ->> 'sourceTreeSha'
     ) then
    raise exception 'signed reviewer attestation required for finalization'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_governed_worker_review_attestation()
  from public, anon, authenticated, service_role;

create trigger guard_governed_worker_review_attestation
before update of status on private.execution_dispatch_outbox
for each row execute function private.guard_governed_worker_review_attestation();

revoke all on function public.register_compute_reviewer_identity(
  uuid, uuid, text, text, text[]
) from public, anon, authenticated, service_role, projectos_reviewer_ingest;
revoke all on function public.resolve_compute_reviewer_identity(uuid, text)
  from public, anon, authenticated, projectos_reviewer_ingest;
revoke all on function public.consume_compute_reviewer_nonce(
  uuid, text, text, text
) from public, anon, authenticated, service_role, projectos_reviewer_ingest;
revoke all on function public.record_governed_worker_review_attestation(
  uuid, uuid, text, text, uuid, uuid, uuid, text, text, text, text, text, text,
  text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.resolve_compute_reviewer_identity(uuid, text)
  to service_role;
grant execute on function public.record_governed_worker_review_attestation(
  uuid, uuid, text, text, uuid, uuid, uuid, text, text, text, text, text, text,
  text, text, text
) to projectos_reviewer_ingest;
