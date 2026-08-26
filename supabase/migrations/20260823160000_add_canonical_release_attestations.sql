-- Final release authority is external to the source tree. A signed independent
-- review must follow the live rollback-restoration and physical-device proof;
-- an authenticated AAL2 organization owner may authorize only that exact review.

create table private.canonical_release_review_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  repository text not null check (repository = 'pandora-rvw-314296438-20260820/pandoras-box'),
  source_sha text not null check (source_sha ~ '^[0-9a-f]{40}$'),
  source_tree_sha text not null check (source_tree_sha ~ '^[0-9a-f]{40}$'),
  production_deployment_id text not null check (production_deployment_id ~ '^dpl_[A-Za-z0-9]+$'),
  rollback_deployment_id text not null check (rollback_deployment_id ~ '^dpl_[A-Za-z0-9]+$'),
  supabase_migration_chain_sha256 text not null check (supabase_migration_chain_sha256 ~ '^[0-9a-f]{64}$'),
  request_id uuid not null,
  reviewer_id text not null check (reviewer_id ~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,127}$'),
  reviewer_runtime_proof_id uuid not null references public.projectos_agent_runtime_proofs(id) on delete restrict,
  reviewer_key_fingerprint text not null check (reviewer_key_fingerprint ~ '^[0-9a-f]{64}$'),
  review_external_id text not null check (review_external_id ~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,191}$'),
  review_source_url text not null check (
    length(review_source_url) between 12 and 2048
    and review_source_url ~ '^https://'
  ),
  review_digest text not null check (review_digest ~ '^[0-9a-f]{64}$'),
  signature_b64 text not null check (signature_b64 ~ '^[A-Za-z0-9+/]{86}==$'),
  signature_sha256 text not null check (signature_sha256 ~ '^[0-9a-f]{64}$'),
  request_nonce text not null check (request_nonce ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{15,127}$'),
  reviewed_at timestamptz not null,
  verdict text not null check (verdict = 'approved'),
  receipt_sha256 text not null check (receipt_sha256 ~ '^[0-9a-f]{64}$'),
  captured_at timestamptz not null default clock_timestamp(),
  unique (organization_id, reviewer_key_fingerprint, request_nonce),
  unique (organization_id, request_id),
  unique (organization_id, repository, source_sha, production_deployment_id),
  foreign key (organization_id, reviewer_id)
    references private.compute_reviewer_identities(organization_id, reviewer_id)
    on delete restrict,
  check (production_deployment_id <> rollback_deployment_id),
  check (reviewed_at <= captured_at)
);

create table private.canonical_release_owner_authorizations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  repository text not null check (repository = 'pandora-rvw-314296438-20260820/pandoras-box'),
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  source_sha text not null check (source_sha ~ '^[0-9a-f]{40}$'),
  production_deployment_id text not null check (production_deployment_id ~ '^dpl_[A-Za-z0-9]+$'),
  review_receipt_id uuid not null references private.canonical_release_review_receipts(id) on delete restrict,
  review_receipt_sha256 text not null check (review_receipt_sha256 ~ '^[0-9a-f]{64}$'),
  aal text not null check (aal = 'aal2'),
  session_id uuid not null,
  mfa_verified_at timestamptz not null,
  request_id text not null check (request_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{15,127}$'),
  authorized_at timestamptz not null,
  receipt_sha256 text not null check (receipt_sha256 ~ '^[0-9a-f]{64}$'),
  captured_at timestamptz not null default clock_timestamp(),
  unique (organization_id, owner_user_id, request_id),
  unique (organization_id, repository, source_sha, production_deployment_id),
  check (authorized_at <= captured_at),
  check (
    mfa_verified_at >= authorized_at - interval '5 minutes'
    and mfa_verified_at <= authorized_at + interval '30 seconds'
  )
);

create trigger canonical_release_review_receipts_immutable
before update or delete on private.canonical_release_review_receipts
for each row execute function private.reject_canonical_release_receipt_mutation();

create trigger canonical_release_owner_authorizations_immutable
before update or delete on private.canonical_release_owner_authorizations
for each row execute function private.reject_canonical_release_receipt_mutation();

alter function public.get_canonical_release_status(uuid, text, text)
  rename to get_canonical_release_status_without_final_attestations;

create or replace function public.capture_canonical_release_review_receipt(
  p_organization_id uuid,
  p_request_id uuid,
  p_repository text,
  p_source_sha text,
  p_source_tree_sha text,
  p_production_deployment_id text,
  p_rollback_deployment_id text,
  p_supabase_migration_chain_sha256 text,
  p_reviewer_id text,
  p_verifier_runtime_proof_id uuid,
  p_reviewer_key_fingerprint text,
  p_review_external_id text,
  p_review_source_url text,
  p_review_digest text,
  p_signature_b64 text,
  p_signature_sha256 text,
  p_request_nonce text,
  p_reviewed_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  production public.projectos_evidence%rowtype;
  rollback_transition private.canonical_vercel_rehearsal_receipts%rowtype;
  rollback_restoration private.canonical_vercel_rehearsal_receipts%rowtype;
  migration_receipt private.canonical_supabase_release_receipts%rowtype;
  wifi public.projectos_evidence%rowtype;
  mobile_data public.projectos_evidence%rowtype;
  identity private.compute_reviewer_identities%rowtype;
  proof public.projectos_agent_runtime_proofs%rowtype;
  existing private.canonical_release_review_receipts%rowtype;
  receipt private.canonical_release_review_receipts%rowtype;
  receipt_basis text;
  receipt_sha text;
  nonce_sha text;
  accepted_nonce text;
  authority_request_basis text;
  authority_request_sha256 text;
begin
  perform private.assert_reviewer_ingest_role();

  if p_repository <> 'pandora-rvw-314296438-20260820/pandoras-box'
     or p_request_id is null
     or p_source_sha !~ '^[0-9a-f]{40}$'
     or p_source_tree_sha !~ '^[0-9a-f]{40}$'
     or p_production_deployment_id !~ '^dpl_[A-Za-z0-9]+$'
     or p_rollback_deployment_id !~ '^dpl_[A-Za-z0-9]+$'
     or p_production_deployment_id = p_rollback_deployment_id
     or p_supabase_migration_chain_sha256 !~ '^[0-9a-f]{64}$'
     or p_reviewer_id !~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,127}$'
     or p_reviewer_key_fingerprint !~ '^[0-9a-f]{64}$'
     or p_review_external_id !~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,191}$'
     or length(p_review_source_url) not between 12 and 2048
     or p_review_source_url !~ '^https://'
     or p_review_digest !~ '^[0-9a-f]{64}$'
     or p_signature_b64 !~ '^[A-Za-z0-9+/]{86}==$'
     or p_signature_sha256 !~ '^[0-9a-f]{64}$'
     or p_request_nonce !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{15,127}$'
     or p_reviewed_at > statement_timestamp()
     or p_reviewed_at < statement_timestamp() - interval '5 minutes' then
    raise exception 'invalid canonical release review attestation';
  end if;

  begin
    if octet_length(decode(p_signature_b64, 'base64')) <> 64
       or encode(extensions.digest(decode(p_signature_b64, 'base64'), 'sha256'), 'hex')
          <> p_signature_sha256 then
      raise exception 'invalid canonical release review signature';
    end if;
  exception when others then
    raise exception 'invalid canonical release review signature';
  end;

  authority_request_basis := concat_ws(
    '|',
    'pandora-release-review-authority-v1',
    p_organization_id::text,
    p_request_id::text,
    p_reviewer_id,
    p_verifier_runtime_proof_id::text,
    p_reviewer_key_fingerprint,
    p_request_nonce,
    to_char(p_reviewed_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    p_repository,
    p_source_sha,
    p_source_tree_sha,
    p_production_deployment_id,
    p_rollback_deployment_id,
    p_supabase_migration_chain_sha256,
    p_review_external_id,
    p_review_source_url,
    p_review_digest,
    p_signature_sha256,
    'approved'
  );
  authority_request_sha256 := encode(
    extensions.digest(convert_to(authority_request_basis, 'UTF8'), 'sha256'),
    'hex'
  );
  perform private.assert_reviewer_ingest_request(
    'release_review',
    p_organization_id,
    p_reviewer_id,
    authority_request_sha256
  );

  select candidate.* into identity
  from private.compute_reviewer_identities candidate
  where candidate.organization_id = p_organization_id
    and candidate.reviewer_id = p_reviewer_id
    and candidate.runtime_proof_id = p_verifier_runtime_proof_id
    and candidate.key_fingerprint = p_reviewer_key_fingerprint
    and candidate.status = 'active'
    and p_repository = any(candidate.allowed_repositories)
  for update;

  select candidate.* into proof
  from public.projectos_agent_runtime_proofs candidate
  where candidate.id = p_verifier_runtime_proof_id
    and candidate.organization_id = p_organization_id
    and candidate.agent_key = p_reviewer_id
    and candidate.role = 'reviewer'
    and candidate.is_active
    and candidate.expires_at > statement_timestamp()
    and candidate.verified_at >= statement_timestamp() - interval '2 hours'
    and candidate.context_updated_at >= statement_timestamp() - interval '30 minutes'
    and candidate.credential_state = 'ready'
    and candidate.quota_state in ('available', 'limited')
    and candidate.health_state = 'healthy'
    and p_repository = any(candidate.repository_scopes)
    and 'projectos.release.review' = any(candidate.proven_capabilities)
  for update;

  if identity.reviewer_id is null
     or proof.id is null
     or identity.vendor <> private.projectos_canonical_agent_vendor(proof.vendor) then
    raise exception 'fresh independent release reviewer proof required' using errcode = '42501';
  end if;

  select candidate.* into existing
  from private.canonical_release_review_receipts candidate
  where candidate.organization_id = p_organization_id
    and (
      candidate.request_id = p_request_id
      or (
        candidate.repository = p_repository
        and candidate.source_sha = p_source_sha
        and candidate.production_deployment_id = p_production_deployment_id
      )
    )
  for update;
  if existing.id is not null then
    if existing.request_id = p_request_id
       and existing.repository = p_repository
       and existing.source_sha = p_source_sha
       and existing.source_tree_sha = p_source_tree_sha
       and existing.production_deployment_id = p_production_deployment_id
       and existing.rollback_deployment_id = p_rollback_deployment_id
       and existing.supabase_migration_chain_sha256 = p_supabase_migration_chain_sha256
       and existing.reviewer_id = p_reviewer_id
       and existing.reviewer_runtime_proof_id = p_verifier_runtime_proof_id
       and existing.reviewer_key_fingerprint = p_reviewer_key_fingerprint
       and existing.review_external_id = p_review_external_id
       and existing.review_source_url = p_review_source_url
       and existing.review_digest = p_review_digest
       and existing.signature_b64 = p_signature_b64
       and existing.signature_sha256 = p_signature_sha256
       and existing.request_nonce = p_request_nonce
       and existing.reviewed_at = p_reviewed_at
       and existing.verdict = 'approved' then
      return jsonb_build_object(
        'verified', true,
        'authority', 'INDEPENDENT_REVIEWER',
        'receiptId', existing.id,
        'receiptSha256', existing.receipt_sha256,
        'sourceSha', existing.source_sha,
        'sourceTreeSha', existing.source_tree_sha,
        'productionDeploymentId', existing.production_deployment_id,
        'rollbackDeploymentId', existing.rollback_deployment_id,
        'supabaseMigrationChainSha256', existing.supabase_migration_chain_sha256,
        'reviewerId', existing.reviewer_id,
        'reviewerRuntimeProofId', existing.reviewer_runtime_proof_id,
        'reviewerKeyFingerprint', existing.reviewer_key_fingerprint,
        'reviewExternalId', existing.review_external_id,
        'reviewSourceUrl', existing.review_source_url,
        'reviewDigest', existing.review_digest,
        'reviewedAt', existing.reviewed_at,
        'capturedAt', existing.captured_at,
        'idempotentReplay', true
      );
    end if;
    raise exception 'canonical release review identity already used' using errcode = '23505';
  end if;

  select evidence.* into production
  from public.projectos_evidence evidence
  where evidence.organization_id = p_organization_id
    and evidence.repository = p_repository
    and evidence.head_sha = p_source_sha
    and evidence.evidence_type = 'canonical_vercel_production'
    and evidence.provider = 'vercel'
    and evidence.status in ('passing', 'complete')
    and lower(coalesce(evidence.verdict, '')) in ('pass', 'passed', 'success', 'verified')
    and evidence.invalidated_at is null
    and evidence.external_id = p_production_deployment_id
    and evidence.payload_redacted ->> 'deploymentId' = p_production_deployment_id
    and evidence.payload_redacted ->> 'productionVerifiedDeploymentId' = p_production_deployment_id
    and evidence.payload_redacted ->> 'sourceSha' = p_source_sha
    and evidence.payload_redacted ->> 'gitRepository' = p_repository
    and evidence.payload_redacted -> 'routeProbesPassed' = 'true'::jsonb
    and evidence.observed_at <= statement_timestamp()
  order by evidence.observed_at desc, evidence.id desc
  limit 1;

  select candidate.* into rollback_transition
  from private.canonical_vercel_rehearsal_receipts candidate
  where candidate.organization_id = p_organization_id
    and candidate.repository = p_repository
    and candidate.phase = 'rollback_transition'
    and candidate.candidate_source_sha = p_source_sha
    and candidate.candidate_deployment_id = p_production_deployment_id
    and candidate.rollback_deployment_id = p_rollback_deployment_id
    and candidate.external_id = p_rollback_deployment_id
    and candidate.observed_at > production.observed_at
    and candidate.observed_at <= statement_timestamp()
  order by candidate.observed_at desc, candidate.id desc
  limit 1;

  select candidate.* into rollback_restoration
  from private.canonical_vercel_rehearsal_receipts candidate
  where candidate.organization_id = p_organization_id
    and candidate.repository = p_repository
    and candidate.phase = 'rollback_restoration'
    and candidate.candidate_source_sha = p_source_sha
    and candidate.candidate_deployment_id = p_production_deployment_id
    and candidate.rollback_deployment_id = p_rollback_deployment_id
    and candidate.rollback_source_sha = rollback_transition.rollback_source_sha
    and candidate.external_id = p_production_deployment_id
    and candidate.observed_at > rollback_transition.observed_at
    and candidate.observed_at <= statement_timestamp()
  order by candidate.observed_at desc, candidate.id desc
  limit 1;

  select candidate.* into migration_receipt
  from private.canonical_supabase_release_receipts candidate
  where candidate.organization_id = p_organization_id
    and candidate.repository = p_repository
    and candidate.source_sha = p_source_sha
    and candidate.source_tree_sha = p_source_tree_sha
    and candidate.source_chain_sha256 = p_supabase_migration_chain_sha256
    and candidate.captured_version_chain_sha256 = candidate.expected_version_chain_sha256
    and candidate.captured_at <= statement_timestamp()
  order by candidate.captured_at desc, candidate.id desc
  limit 1;

  select evidence.* into wifi
  from public.projectos_evidence evidence
  where evidence.organization_id = p_organization_id
    and evidence.repository = p_repository
    and evidence.head_sha = p_source_sha
    and evidence.evidence_type = 'canonical_physical_android_wifi'
    and evidence.provider = 'physical_android_observer'
    and evidence.status in ('passing', 'complete')
    and lower(coalesce(evidence.verdict, '')) in ('pass', 'passed', 'success', 'verified')
    and evidence.invalidated_at is null
    and evidence.payload_redacted ->> 'network' = 'wifi'
    and evidence.payload_redacted ->> 'sourceSha' = p_source_sha
    and evidence.payload_redacted ->> 'sourceTreeSha' = p_source_tree_sha
    and evidence.payload_redacted ->> 'deploymentId' = p_production_deployment_id
    and evidence.payload_redacted ->> 'artifactSha256' ~ '^[0-9a-f]{64}$'
    and evidence.payload_redacted ->> 'deviceIdHash' ~ '^[0-9a-f]{64}$'
    and evidence.payload_redacted ->> 'packageName' = 'com.banataosystems.pandora_mobile'
    and evidence.payload_redacted -> 'verified' = 'true'::jsonb
    and evidence.observed_at > rollback_restoration.alias_post_observed_at
  order by evidence.observed_at desc, evidence.id desc
  limit 1;

  select evidence.* into mobile_data
  from public.projectos_evidence evidence
  where evidence.organization_id = p_organization_id
    and evidence.repository = p_repository
    and evidence.head_sha = p_source_sha
    and evidence.evidence_type = 'canonical_physical_android_mobile_data'
    and evidence.provider = 'physical_android_observer'
    and evidence.status in ('passing', 'complete')
    and lower(coalesce(evidence.verdict, '')) in ('pass', 'passed', 'success', 'verified')
    and evidence.invalidated_at is null
    and evidence.payload_redacted ->> 'network' = 'mobile_data'
    and evidence.payload_redacted ->> 'sourceSha' = p_source_sha
    and evidence.payload_redacted ->> 'sourceTreeSha' = p_source_tree_sha
    and evidence.payload_redacted ->> 'deploymentId' = p_production_deployment_id
    and evidence.payload_redacted ->> 'artifactSha256' = wifi.payload_redacted ->> 'artifactSha256'
    and evidence.payload_redacted ->> 'deviceIdHash' = wifi.payload_redacted ->> 'deviceIdHash'
    and evidence.payload_redacted ->> 'packageName' = 'com.banataosystems.pandora_mobile'
    and evidence.payload_redacted -> 'verified' = 'true'::jsonb
    and evidence.observed_at > rollback_restoration.alias_post_observed_at
  order by evidence.observed_at desc, evidence.id desc
  limit 1;

  if production.id is null
     or rollback_transition.id is null
     or rollback_restoration.id is null
     or migration_receipt.id is null
     or wifi.id is null
     or mobile_data.id is null
     or p_reviewed_at <= greatest(
       rollback_restoration.alias_post_observed_at,
       wifi.observed_at,
       mobile_data.observed_at
     ) then
    raise exception 'canonical release evidence is incomplete or mismatched';
  end if;

  nonce_sha := encode(
    extensions.digest(convert_to(p_request_nonce, 'UTF8'), 'sha256'),
    'hex'
  );
  delete from private.compute_reviewer_nonces where expires_at <= statement_timestamp();
  insert into private.compute_reviewer_nonces (
    organization_id,
    reviewer_id,
    nonce_sha256,
    expires_at
  ) values (
    p_organization_id,
    p_reviewer_id,
    nonce_sha,
    statement_timestamp() + interval '15 minutes'
  ) on conflict do nothing
  returning reviewer_id into accepted_nonce;
  if accepted_nonce is null then
    raise exception 'reviewer nonce already used' using errcode = '23505';
  end if;

  receipt_basis := concat_ws('|',
    'canonical-release-review-v1',
    p_organization_id::text,
    p_repository,
    p_source_sha,
    p_source_tree_sha,
    p_production_deployment_id,
    p_rollback_deployment_id,
    p_supabase_migration_chain_sha256,
    p_request_id::text,
    p_reviewer_id,
    p_verifier_runtime_proof_id::text,
    p_reviewer_key_fingerprint,
    p_review_external_id,
    p_review_source_url,
    p_review_digest,
    p_signature_sha256,
    p_request_nonce,
    to_char(p_reviewed_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'approved'
  );
  receipt_sha := encode(
    extensions.digest(convert_to(receipt_basis, 'UTF8'), 'sha256'),
    'hex'
  );

  insert into private.canonical_release_review_receipts (
    organization_id,
    repository,
    source_sha,
    source_tree_sha,
    production_deployment_id,
    rollback_deployment_id,
    supabase_migration_chain_sha256,
    request_id,
    reviewer_id,
    reviewer_runtime_proof_id,
    reviewer_key_fingerprint,
    review_external_id,
    review_source_url,
    review_digest,
    signature_b64,
    signature_sha256,
    request_nonce,
    reviewed_at,
    verdict,
    receipt_sha256
  ) values (
    p_organization_id,
    p_repository,
    p_source_sha,
    p_source_tree_sha,
    p_production_deployment_id,
    p_rollback_deployment_id,
    p_supabase_migration_chain_sha256,
    p_request_id,
    p_reviewer_id,
    p_verifier_runtime_proof_id,
    p_reviewer_key_fingerprint,
    p_review_external_id,
    p_review_source_url,
    p_review_digest,
    p_signature_b64,
    p_signature_sha256,
    p_request_nonce,
    p_reviewed_at,
    'approved',
    receipt_sha
  ) returning * into receipt;

  return jsonb_build_object(
    'verified', true,
    'authority', 'INDEPENDENT_REVIEWER',
    'receiptId', receipt.id,
    'receiptSha256', receipt.receipt_sha256,
    'sourceSha', receipt.source_sha,
    'sourceTreeSha', receipt.source_tree_sha,
    'productionDeploymentId', receipt.production_deployment_id,
    'rollbackDeploymentId', receipt.rollback_deployment_id,
    'supabaseMigrationChainSha256', receipt.supabase_migration_chain_sha256,
    'reviewerId', receipt.reviewer_id,
    'reviewerRuntimeProofId', receipt.reviewer_runtime_proof_id,
    'reviewerKeyFingerprint', receipt.reviewer_key_fingerprint,
    'reviewExternalId', receipt.review_external_id,
    'reviewSourceUrl', receipt.review_source_url,
    'reviewDigest', receipt.review_digest,
    'reviewedAt', receipt.reviewed_at,
    'capturedAt', receipt.captured_at
  );
end;
$$;

create or replace function public.capture_canonical_release_owner_authorization(
  p_organization_id uuid,
  p_repository text,
  p_owner_user_id uuid,
  p_source_sha text,
  p_production_deployment_id text,
  p_review_receipt_id uuid,
  p_review_receipt_sha256 text,
  p_aal text,
  p_request_id text,
  p_authorized_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  review_receipt private.canonical_release_review_receipts%rowtype;
  existing private.canonical_release_owner_authorizations%rowtype;
  receipt private.canonical_release_owner_authorizations%rowtype;
  receipt_basis text;
  receipt_sha text;
  current_session_id uuid;
  latest_mfa_epoch numeric;
  latest_mfa_at timestamptz;
begin
  if coalesce(auth.role(), '') <> 'authenticated'
     or auth.uid() is null
     or auth.uid() <> p_owner_user_id
     or coalesce(auth.jwt() ->> 'aal', '') <> 'aal2'
     or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'authenticated AAL2 owner required' using errcode = '42501';
  end if;

  begin
    current_session_id := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'live recent AAL2 owner session required' using errcode = '42501';
  end;
  if current_session_id is null or not exists (
    select 1
    from auth.sessions session
    where session.id = current_session_id
      and session.user_id = p_owner_user_id
      and session.aal = 'aal2'::auth.aal_level
      and (session.not_after is null or session.not_after > statement_timestamp())
  ) then
    raise exception 'live recent AAL2 owner session required' using errcode = '42501';
  end if;
  select max((entry ->> 'timestamp')::numeric)
  into latest_mfa_epoch
  from jsonb_array_elements(
    case
      when jsonb_typeof(auth.jwt() -> 'amr') = 'array' then auth.jwt() -> 'amr'
      else '[]'::jsonb
    end
  ) entry
  where jsonb_typeof(entry) = 'object'
    and entry ->> 'method' in ('totp', 'mfa/totp', 'mfa/phone', 'mfa/webauthn')
    and coalesce(entry ->> 'timestamp', '') ~ '^[0-9]+(?:\.[0-9]+)?$';
  if latest_mfa_epoch is null then
    raise exception 'live recent AAL2 owner session required' using errcode = '42501';
  end if;
  latest_mfa_at := to_timestamp(latest_mfa_epoch);
  if latest_mfa_at < statement_timestamp() - interval '5 minutes'
     or latest_mfa_at > statement_timestamp() + interval '30 seconds' then
    raise exception 'live recent AAL2 owner session required' using errcode = '42501';
  end if;

  if p_repository <> 'pandora-rvw-314296438-20260820/pandoras-box'
     or p_source_sha !~ '^[0-9a-f]{40}$'
     or p_production_deployment_id !~ '^dpl_[A-Za-z0-9]+$'
     or p_review_receipt_sha256 !~ '^[0-9a-f]{64}$'
     or p_aal <> 'aal2'
     or p_request_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{15,127}$'
     or p_authorized_at > statement_timestamp()
     or p_authorized_at < statement_timestamp() - interval '5 minutes' then
    raise exception 'invalid canonical owner authorization';
  end if;

  if not exists (
    select 1
    from public.memberships membership
    where membership.organization_id = p_organization_id
      and membership.user_id = p_owner_user_id
      and membership.role = 'owner'::public.member_role
      and membership.status = 'active'::public.membership_status
  ) then
    raise exception 'active organization owner required' using errcode = '42501';
  end if;

  select candidate.* into review_receipt
  from private.canonical_release_review_receipts candidate
  where candidate.id = p_review_receipt_id
    and candidate.organization_id = p_organization_id
    and candidate.repository = p_repository
    and candidate.source_sha = p_source_sha
    and candidate.production_deployment_id = p_production_deployment_id
    and candidate.receipt_sha256 = p_review_receipt_sha256
    and candidate.verdict = 'approved';

  select candidate.* into existing
  from private.canonical_release_owner_authorizations candidate
  where candidate.organization_id = p_organization_id
    and (
      (candidate.owner_user_id = p_owner_user_id and candidate.request_id = p_request_id)
      or (
        candidate.repository = p_repository
        and candidate.source_sha = p_source_sha
        and candidate.production_deployment_id = p_production_deployment_id
      )
    )
  for update;
  if existing.id is not null then
    if existing.repository = p_repository
       and existing.owner_user_id = p_owner_user_id
       and existing.source_sha = p_source_sha
       and existing.production_deployment_id = p_production_deployment_id
       and existing.review_receipt_id = p_review_receipt_id
       and existing.review_receipt_sha256 = p_review_receipt_sha256
       and existing.aal = p_aal
       and existing.request_id = p_request_id
       and existing.authorized_at = p_authorized_at then
      return jsonb_build_object(
        'verified', true,
        'authority', 'OWNER_AUTHORIZATION',
        'receiptId', existing.id,
        'receiptSha256', existing.receipt_sha256,
        'ownerUserId', existing.owner_user_id,
        'sourceSha', existing.source_sha,
        'productionDeploymentId', existing.production_deployment_id,
        'reviewReceiptId', existing.review_receipt_id,
        'reviewReceiptSha256', existing.review_receipt_sha256,
        'aal', existing.aal,
        'sessionId', existing.session_id,
        'mfaVerifiedAt', existing.mfa_verified_at,
        'authorizedAt', existing.authorized_at,
        'capturedAt', existing.captured_at,
        'idempotentReplay', true
      );
    end if;
    raise exception 'canonical owner authorization identity already used' using errcode = '23505';
  end if;

  if review_receipt.id is null
     or p_authorized_at <= review_receipt.captured_at then
    raise exception 'exact independent review receipt required';
  end if;

  receipt_basis := concat_ws('|',
    'canonical-release-owner-authorization-v1',
    p_organization_id::text,
    p_repository,
    p_owner_user_id::text,
    p_source_sha,
    p_production_deployment_id,
    p_review_receipt_id::text,
    p_review_receipt_sha256,
    p_aal,
    current_session_id::text,
    to_char(latest_mfa_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    p_request_id,
    to_char(p_authorized_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  );
  receipt_sha := encode(
    extensions.digest(convert_to(receipt_basis, 'UTF8'), 'sha256'),
    'hex'
  );

  insert into private.canonical_release_owner_authorizations (
    organization_id,
    repository,
    owner_user_id,
    source_sha,
    production_deployment_id,
    review_receipt_id,
    review_receipt_sha256,
    aal,
    session_id,
    mfa_verified_at,
    request_id,
    authorized_at,
    receipt_sha256
  ) values (
    p_organization_id,
    p_repository,
    p_owner_user_id,
    p_source_sha,
    p_production_deployment_id,
    p_review_receipt_id,
    p_review_receipt_sha256,
    p_aal,
    current_session_id,
    latest_mfa_at,
    p_request_id,
    p_authorized_at,
    receipt_sha
  ) returning * into receipt;

  return jsonb_build_object(
    'verified', true,
    'authority', 'OWNER_AUTHORIZATION',
    'receiptId', receipt.id,
    'receiptSha256', receipt.receipt_sha256,
    'ownerUserId', receipt.owner_user_id,
    'sourceSha', receipt.source_sha,
    'productionDeploymentId', receipt.production_deployment_id,
    'reviewReceiptId', receipt.review_receipt_id,
    'reviewReceiptSha256', receipt.review_receipt_sha256,
    'aal', receipt.aal,
    'sessionId', receipt.session_id,
    'mfaVerifiedAt', receipt.mfa_verified_at,
    'authorizedAt', receipt.authorized_at,
    'capturedAt', receipt.captured_at
  );
end;
$$;

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
  review_receipt private.canonical_release_review_receipts%rowtype;
  owner_receipt private.canonical_release_owner_authorizations%rowtype;
  review_status jsonb := null;
  owner_status jsonb := null;
begin
  perform private.assert_control_service_role();
  base_status := public.get_canonical_release_status_without_final_attestations(
    p_organization_id,
    p_repository,
    p_source_sha
  );

  select candidate.* into review_receipt
  from private.canonical_release_review_receipts candidate
  where candidate.organization_id = p_organization_id
    and candidate.repository = p_repository
    and candidate.source_sha = p_source_sha
    and candidate.source_tree_sha = base_status #>> '{supabase,sourceArtifactDatabaseReceipt,sourceTreeSha}'
    and candidate.production_deployment_id = base_status #>> '{vercel,deploymentId}'
    and candidate.rollback_deployment_id = base_status #>> '{vercel,rollbackDeploymentId}'
    and candidate.supabase_migration_chain_sha256
        = base_status #>> '{supabase,sourceArtifactDatabaseReceipt,sourceChainSha256}'
    and candidate.reviewed_at > (base_status #>> '{vercel,rollbackRestorationAliasPostObservedAt}')::timestamptz
    and candidate.reviewed_at > (base_status #>> '{android,wifi,observedAt}')::timestamptz
    and candidate.reviewed_at > (base_status #>> '{android,mobileData,observedAt}')::timestamptz
    and candidate.verdict = 'approved'
  order by candidate.captured_at desc, candidate.id desc
  limit 1;

  if review_receipt.id is not null then
    review_status := jsonb_build_object(
      'verified', true,
      'authority', 'INDEPENDENT_REVIEWER',
      'receiptId', review_receipt.id,
      'receiptSha256', review_receipt.receipt_sha256,
      'sourceSha', review_receipt.source_sha,
      'sourceTreeSha', review_receipt.source_tree_sha,
      'productionDeploymentId', review_receipt.production_deployment_id,
      'rollbackDeploymentId', review_receipt.rollback_deployment_id,
      'supabaseMigrationChainSha256', review_receipt.supabase_migration_chain_sha256,
      'reviewerId', review_receipt.reviewer_id,
      'reviewerRuntimeProofId', review_receipt.reviewer_runtime_proof_id,
      'reviewerKeyFingerprint', review_receipt.reviewer_key_fingerprint,
      'reviewExternalId', review_receipt.review_external_id,
      'reviewSourceUrl', review_receipt.review_source_url,
      'reviewDigest', review_receipt.review_digest,
      'reviewedAt', review_receipt.reviewed_at,
      'capturedAt', review_receipt.captured_at
    );

    -- This is authorization-at-capture evidence. Offboarding an owner later
    -- must not rewrite or invalidate an already authorized exact release.
    select candidate.* into owner_receipt
    from private.canonical_release_owner_authorizations candidate
    where candidate.organization_id = p_organization_id
      and candidate.repository = p_repository
      and candidate.source_sha = p_source_sha
      and candidate.production_deployment_id = review_receipt.production_deployment_id
      and candidate.review_receipt_id = review_receipt.id
      and candidate.review_receipt_sha256 = review_receipt.receipt_sha256
      and candidate.aal = 'aal2'
      and candidate.session_id is not null
      and candidate.mfa_verified_at >= candidate.authorized_at - interval '5 minutes'
      and candidate.mfa_verified_at <= candidate.authorized_at + interval '30 seconds'
      and candidate.authorized_at > review_receipt.captured_at
    order by candidate.captured_at desc, candidate.id desc
    limit 1;
  end if;

  if owner_receipt.id is not null then
    owner_status := jsonb_build_object(
      'verified', true,
      'authority', 'OWNER_AUTHORIZATION',
      'receiptId', owner_receipt.id,
      'receiptSha256', owner_receipt.receipt_sha256,
      'ownerUserId', owner_receipt.owner_user_id,
      'sourceSha', owner_receipt.source_sha,
      'productionDeploymentId', owner_receipt.production_deployment_id,
      'reviewReceiptId', owner_receipt.review_receipt_id,
      'reviewReceiptSha256', owner_receipt.review_receipt_sha256,
      'aal', owner_receipt.aal,
      'sessionId', owner_receipt.session_id,
      'mfaVerifiedAt', owner_receipt.mfa_verified_at,
      'authorizedAt', owner_receipt.authorized_at,
      'capturedAt', owner_receipt.captured_at
    );
  end if;

  return base_status || jsonb_build_object(
    'independentReview', review_status,
    'ownerAuthorization', owner_status
  );
end;
$$;

revoke all on table private.canonical_release_review_receipts
  from public, anon, authenticated, service_role;
revoke all on table private.canonical_release_owner_authorizations
  from public, anon, authenticated, service_role;
revoke all on function public.get_canonical_release_status_without_final_attestations(uuid,text,text)
  from public, anon, authenticated;
revoke all on function public.capture_canonical_release_review_receipt(
  uuid,uuid,text,text,text,text,text,text,text,uuid,text,text,text,text,text,text,text,timestamptz
) from public, anon, authenticated, service_role, projectos_reviewer_ingest;
revoke all on function public.capture_canonical_release_owner_authorization(
  uuid,text,uuid,text,text,uuid,text,text,text,timestamptz
) from public, anon, authenticated, service_role;
revoke all on function public.get_canonical_release_status(uuid,text,text)
  from public, anon, authenticated;
grant execute on function public.get_canonical_release_status_without_final_attestations(uuid,text,text)
  to service_role;
grant execute on function public.capture_canonical_release_review_receipt(
  uuid,uuid,text,text,text,text,text,text,text,uuid,text,text,text,text,text,text,text,timestamptz
) to projectos_reviewer_ingest;
grant execute on function public.capture_canonical_release_owner_authorization(
  uuid,text,uuid,text,text,uuid,text,text,text,timestamptz
) to authenticated;
grant execute on function public.get_canonical_release_status(uuid,text,text)
  to service_role;
