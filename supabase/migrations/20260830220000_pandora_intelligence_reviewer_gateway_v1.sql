
-- Pandora intelligence reviewer gateway v1.
-- A model, service-role component, or repository import cannot self-promote an
-- intelligence asset. Promotion requires BOTH an independently issued, exact
-- Worker-E JWT and an Ed25519 signature from an enrolled reviewer whose fresh
-- runtime proof and explicit review scope remain valid at finalization time.

create table if not exists private.intelligence_reviewer_identities (
  reviewer_id text primary key check (reviewer_id ~ '^[a-z0-9][a-z0-9._:-]{2,127}$'),
  authority_organization_id uuid not null references public.organizations(id) on delete restrict,
  runtime_proof_id uuid not null unique references public.projectos_agent_runtime_proofs(id) on delete restrict,
  vendor text not null,
  public_key_b64 text not null check (public_key_b64 ~ '^[A-Za-z0-9+/]{43}=$'),
  key_fingerprint text not null unique check (key_fingerprint ~ '^[0-9a-f]{64}$'),
  status text not null default 'active' check (status in ('active','draining','disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists private.intelligence_reviewer_scope_grants (
  reviewer_id text not null references private.intelligence_reviewer_identities(reviewer_id) on delete cascade,
  scope_key text not null check (scope_key='global' or scope_key ~ '^[0-9a-f-]{36}$'),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (reviewer_id,scope_key),
  check (expires_at > created_at)
);

create table if not exists private.intelligence_review_attestations (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.pandora_intelligence_assets(id) on delete restrict,
  reviewer_id text not null references private.intelligence_reviewer_identities(reviewer_id) on delete restrict,
  scope_key text not null check (scope_key='global' or scope_key ~ '^[0-9a-f-]{36}$'),
  source_digest_sha256 text not null check (source_digest_sha256 ~ '^[0-9a-f]{64}$'),
  content_digest_sha256 text null check (content_digest_sha256 is null or content_digest_sha256 ~ '^[0-9a-f]{64}$'),
  evidence_id text not null check (length(trim(evidence_id)) between 1 and 240),
  request_sha256 text not null check (request_sha256 ~ '^[0-9a-f]{64}$'),
  reviewer_nonce_sha256 text not null check (reviewer_nonce_sha256 ~ '^[0-9a-f]{64}$'),
  signed_timestamp text not null check (signed_timestamp ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$'),
  signed_at timestamptz not null,
  signature_b64 text not null check (signature_b64 ~ '^[A-Za-z0-9+/]{86}==$'),
  signature_basis_sha256 text not null check (signature_basis_sha256 ~ '^[0-9a-f]{64}$'),
  key_fingerprint text not null check (key_fingerprint ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  finalized_at timestamptz null,
  authority_jti_sha256 text null check (authority_jti_sha256 is null or authority_jti_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  unique (reviewer_id,reviewer_nonce_sha256),
  unique (asset_id,evidence_id,reviewer_id)
);

create index if not exists intelligence_review_attestations_pending_idx
  on private.intelligence_review_attestations(asset_id,expires_at)
  where finalized_at is null;

alter table private.intelligence_reviewer_identities enable row level security;
alter table private.intelligence_reviewer_scope_grants enable row level security;
alter table private.intelligence_review_attestations enable row level security;
revoke all on private.intelligence_reviewer_identities from public,anon,authenticated,service_role,projectos_reviewer_ingest;
revoke all on private.intelligence_reviewer_scope_grants from public,anon,authenticated,service_role,projectos_reviewer_ingest;
revoke all on private.intelligence_review_attestations from public,anon,authenticated,service_role,projectos_reviewer_ingest;

create or replace function private.pandora_intelligence_reviewer_proof_is_fresh(
  p_reviewer_id text,
  p_runtime_proof_id uuid
) returns boolean language sql stable security definer set search_path='' as $$
  select exists(
    select 1 from public.projectos_agent_runtime_proofs proof
    where proof.id=p_runtime_proof_id
      and proof.agent_key=p_reviewer_id
      and proof.role='reviewer'
      and proof.is_active
      and proof.expires_at>now()
      and proof.verified_at>=now()-interval '2 hours'
      and proof.context_updated_at>=now()-interval '30 minutes'
      and proof.credential_state='ready'
      and proof.quota_state in ('available','limited')
      and proof.health_state='healthy'
      and proof.verified_by<>proof.agent_key
      and 'pandora-rvw-314296438-20260820/pandoras-box'=any(proof.repository_scopes)
      and 'projectos.intelligence.verify'=any(proof.proven_capabilities)
  );
$$;
revoke all on function private.pandora_intelligence_reviewer_proof_is_fresh(text,uuid)
  from public,anon,authenticated,service_role,projectos_reviewer_ingest;

create or replace function public.pandora_register_intelligence_reviewer(
  p_runtime_proof_id uuid,
  p_reviewer_id text,
  p_public_key_b64 text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_proof public.projectos_agent_runtime_proofs%rowtype;
  v_existing private.intelligence_reviewer_identities%rowtype;
  v_reviewer text := lower(trim(coalesce(p_reviewer_id,'')));
  v_fingerprint text;
  v_vendor text;
begin
  if session_user<>'postgres' then
    raise exception 'database administrator required for intelligence reviewer enrollment' using errcode='42501';
  end if;
  if v_reviewer !~ '^[a-z0-9][a-z0-9._:-]{2,127}$'
     or coalesce(p_public_key_b64,'') !~ '^[A-Za-z0-9+/]{43}=$' then
    raise exception 'invalid intelligence reviewer identity' using errcode='22023';
  end if;
  begin
    if octet_length(decode(p_public_key_b64,'base64'))<>32 then
      raise exception 'invalid reviewer public key length' using errcode='22023';
    end if;
  exception when others then
    raise exception 'invalid reviewer public key' using errcode='22023';
  end;

  select * into v_proof from public.projectos_agent_runtime_proofs
   where id=p_runtime_proof_id for update;
  if v_proof.id is null
     or not private.pandora_intelligence_reviewer_proof_is_fresh(v_reviewer,p_runtime_proof_id) then
    raise exception 'fresh independent intelligence reviewer runtime proof required' using errcode='42501';
  end if;
  v_vendor := private.projectos_canonical_agent_vendor(v_proof.vendor);
  if v_vendor is null then raise exception 'canonical reviewer vendor required' using errcode='42501'; end if;
  v_fingerprint := encode(extensions.digest(decode(p_public_key_b64,'base64'),'sha256'),'hex');

  select * into v_existing from private.intelligence_reviewer_identities
   where reviewer_id=v_reviewer for update;
  if v_existing.reviewer_id is not null then
    if v_existing.runtime_proof_id=p_runtime_proof_id
       and v_existing.authority_organization_id=v_proof.organization_id
       and v_existing.vendor=v_vendor
       and v_existing.public_key_b64=p_public_key_b64
       and v_existing.key_fingerprint=v_fingerprint
       and v_existing.status='active' then
      return jsonb_build_object('reviewerId',v_reviewer,'keyFingerprint',v_fingerprint,'runtimeProofId',p_runtime_proof_id,'idempotentReplay',true);
    end if;
    raise exception 'intelligence reviewer rotation requires a separate governed action' using errcode='55000';
  end if;

  insert into private.intelligence_reviewer_identities(
    reviewer_id,authority_organization_id,runtime_proof_id,vendor,public_key_b64,key_fingerprint
  ) values(v_reviewer,v_proof.organization_id,p_runtime_proof_id,v_vendor,p_public_key_b64,v_fingerprint);
  return jsonb_build_object('reviewerId',v_reviewer,'keyFingerprint',v_fingerprint,'runtimeProofId',p_runtime_proof_id,'idempotentReplay',false);
end; $$;
revoke all on function public.pandora_register_intelligence_reviewer(uuid,text,text)
  from public,anon,authenticated,service_role,projectos_reviewer_ingest;

create or replace function public.pandora_grant_intelligence_reviewer_scope(
  p_reviewer_id text,
  p_scope_key text,
  p_expires_at timestamptz
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_identity private.intelligence_reviewer_identities%rowtype;
  v_scope text := lower(trim(coalesce(p_scope_key,'')));
  v_max_ttl interval;
begin
  if session_user<>'postgres' then
    raise exception 'database administrator required for intelligence reviewer grants' using errcode='42501';
  end if;
  select * into v_identity from private.intelligence_reviewer_identities
   where reviewer_id=lower(trim(coalesce(p_reviewer_id,''))) and status='active' for update;
  if v_identity.reviewer_id is null
     or not private.pandora_intelligence_reviewer_proof_is_fresh(v_identity.reviewer_id,v_identity.runtime_proof_id) then
    raise exception 'active fresh intelligence reviewer required' using errcode='42501';
  end if;
  if v_scope<>'global' then
    begin
      perform 1 from public.organizations where id=v_scope::uuid;
      if not found then raise exception 'review organization does not exist' using errcode='22023'; end if;
    exception when invalid_text_representation then
      raise exception 'invalid intelligence review scope' using errcode='22023';
    end;
  end if;
  v_max_ttl := case when v_scope='global' then interval '30 minutes' else interval '2 hours' end;
  if p_expires_at is null or p_expires_at<=now() or p_expires_at>now()+v_max_ttl then
    raise exception 'review scope expiry exceeds bounded grant window' using errcode='22023';
  end if;
  if p_expires_at>(select expires_at from public.projectos_agent_runtime_proofs where id=v_identity.runtime_proof_id) then
    raise exception 'review scope cannot outlive reviewer runtime proof' using errcode='22023';
  end if;
  insert into private.intelligence_reviewer_scope_grants(reviewer_id,scope_key,expires_at)
  values(v_identity.reviewer_id,v_scope,p_expires_at)
  on conflict(reviewer_id,scope_key) do update
    set expires_at=excluded.expires_at,updated_at=now();
  return jsonb_build_object('reviewerId',v_identity.reviewer_id,'scopeKey',v_scope,'expiresAt',p_expires_at);
end; $$;
revoke all on function public.pandora_grant_intelligence_reviewer_scope(text,text,timestamptz)
  from public,anon,authenticated,service_role,projectos_reviewer_ingest;

create or replace function public.pandora_resolve_intelligence_review_target(
  p_asset_id uuid,
  p_reviewer_id text
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_asset public.pandora_intelligence_assets%rowtype;
  v_identity private.intelligence_reviewer_identities%rowtype;
  v_grant private.intelligence_reviewer_scope_grants%rowtype;
  v_scope text;
begin
  perform private.assert_control_service_role();
  select * into v_asset from public.pandora_intelligence_assets where id=p_asset_id;
  if v_asset.id is null or v_asset.trust_state not in ('DISCOVERED','IMPORTED','EXPERIMENTAL','VERIFIED') then
    raise exception 'reviewable intelligence asset required' using errcode='55000';
  end if;
  v_scope := case when v_asset.organization_id is null then 'global' else v_asset.organization_id::text end;
  select * into v_identity from private.intelligence_reviewer_identities
   where reviewer_id=lower(trim(coalesce(p_reviewer_id,''))) and status='active';
  if v_identity.reviewer_id is null
     or not private.pandora_intelligence_reviewer_proof_is_fresh(v_identity.reviewer_id,v_identity.runtime_proof_id) then
    raise exception 'active fresh intelligence reviewer required' using errcode='42501';
  end if;
  select * into v_grant from private.intelligence_reviewer_scope_grants
   where reviewer_id=v_identity.reviewer_id and scope_key=v_scope and expires_at>now();
  if v_grant.reviewer_id is null then raise exception 'explicit intelligence review scope grant required' using errcode='42501'; end if;
  return jsonb_build_object(
    'assetId',v_asset.id,
    'assetKind',v_asset.asset_kind,
    'assetKey',v_asset.asset_key,
    'version',v_asset.version,
    'scopeKey',v_scope,
    'sourceDigestSha256',v_asset.source_digest_sha256,
    'contentDigestSha256',v_asset.content_digest_sha256,
    'reviewerId',v_identity.reviewer_id,
    'reviewerPublicKeyB64',v_identity.public_key_b64,
    'reviewerKeyFingerprint',v_identity.key_fingerprint,
    'grantExpiresAt',v_grant.expires_at
  );
end; $$;
revoke all on function public.pandora_resolve_intelligence_review_target(uuid,text) from public,anon,authenticated;
grant execute on function public.pandora_resolve_intelligence_review_target(uuid,text) to service_role;

create or replace function public.pandora_record_intelligence_review_attestation(
  p_asset_id uuid,
  p_reviewer_id text,
  p_evidence_id text,
  p_source_digest_sha256 text,
  p_content_digest_sha256 text,
  p_request_sha256 text,
  p_nonce text,
  p_timestamp text,
  p_signature_b64 text,
  p_signature_basis_sha256 text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_target jsonb;
  v_scope text;
  v_source text;
  v_content text;
  v_expected_request text;
  v_expected_basis text;
  v_expected_basis_sha text;
  v_signed_at timestamptz;
  v_nonce_sha text;
  v_identity private.intelligence_reviewer_identities%rowtype;
  v_grant private.intelligence_reviewer_scope_grants%rowtype;
  v_existing private.intelligence_review_attestations%rowtype;
  v_row private.intelligence_review_attestations%rowtype;
begin
  perform private.assert_control_service_role();
  if nullif(trim(coalesce(p_evidence_id,'')),'') is null
     or lower(trim(coalesce(p_source_digest_sha256,''))) !~ '^[0-9a-f]{64}$'
     or (p_content_digest_sha256 is not null and lower(trim(p_content_digest_sha256)) !~ '^[0-9a-f]{64}$')
     or lower(trim(coalesce(p_request_sha256,''))) !~ '^[0-9a-f]{64}$'
     or coalesce(p_nonce,'') !~ '^[A-Za-z0-9._:-]{16,128}$'
     or coalesce(p_timestamp,'') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$'
     or coalesce(p_signature_b64,'') !~ '^[A-Za-z0-9+/]{86}==$'
     or lower(trim(coalesce(p_signature_basis_sha256,''))) !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid intelligence review attestation' using errcode='22023';
  end if;
  begin
    v_signed_at := p_timestamp::timestamptz;
    if octet_length(decode(p_signature_b64,'base64'))<>64
       or abs(extract(epoch from (now()-v_signed_at)))>300 then
      raise exception 'invalid intelligence review signature envelope' using errcode='22023';
    end if;
  exception when others then
    raise exception 'invalid intelligence review signature envelope' using errcode='22023';
  end;

  v_target := public.pandora_resolve_intelligence_review_target(p_asset_id,p_reviewer_id);
  v_scope := v_target->>'scopeKey';
  v_source := lower(trim(p_source_digest_sha256));
  v_content := case when p_content_digest_sha256 is null then null else lower(trim(p_content_digest_sha256)) end;
  if v_source is distinct from v_target->>'sourceDigestSha256'
     or v_content is distinct from nullif(v_target->>'contentDigestSha256','') then
    raise exception 'intelligence review target digest mismatch' using errcode='23514';
  end if;
  v_expected_request := encode(extensions.digest(convert_to(
    'pandora:intelligence-certify:v1'||chr(10)||p_asset_id::text||chr(10)||v_source||chr(10)||coalesce(v_content,'-')||chr(10)||trim(p_evidence_id)||chr(10)||lower(trim(p_reviewer_id))||chr(10)||v_scope,
    'UTF8'),'sha256'),'hex');
  if lower(trim(p_request_sha256))<>v_expected_request then
    raise exception 'intelligence review request digest mismatch' using errcode='23514';
  end if;
  v_expected_basis := 'pandora-intelligence-review-v1'||chr(10)||p_asset_id::text||chr(10)||v_source||chr(10)||coalesce(v_content,'-')||chr(10)||trim(p_evidence_id)||chr(10)||lower(trim(p_reviewer_id))||chr(10)||v_scope||chr(10)||p_nonce||chr(10)||p_timestamp;
  v_expected_basis_sha := encode(extensions.digest(convert_to(v_expected_basis,'UTF8'),'sha256'),'hex');
  if lower(trim(p_signature_basis_sha256))<>v_expected_basis_sha then
    raise exception 'intelligence review signature basis mismatch' using errcode='23514';
  end if;
  v_nonce_sha := encode(extensions.digest(convert_to(p_nonce,'UTF8'),'sha256'),'hex');

  select * into v_existing from private.intelligence_review_attestations
   where reviewer_id=lower(trim(p_reviewer_id)) and reviewer_nonce_sha256=v_nonce_sha for update;
  if v_existing.id is not null then
    if v_existing.asset_id=p_asset_id
       and v_existing.evidence_id=trim(p_evidence_id)
       and v_existing.request_sha256=v_expected_request
       and v_existing.signature_b64=p_signature_b64
       and v_existing.signature_basis_sha256=v_expected_basis_sha then
      return jsonb_build_object('attestationId',v_existing.id,'scopeKey',v_existing.scope_key,'idempotentReplay',true);
    end if;
    raise exception 'intelligence reviewer nonce already used' using errcode='23505';
  end if;

  select * into v_identity from private.intelligence_reviewer_identities
   where reviewer_id=lower(trim(p_reviewer_id)) and status='active' for update;
  select * into v_grant from private.intelligence_reviewer_scope_grants
   where reviewer_id=v_identity.reviewer_id and scope_key=v_scope and expires_at>now() for update;
  if v_identity.reviewer_id is null or v_grant.reviewer_id is null then
    raise exception 'active explicit intelligence review grant required' using errcode='42501';
  end if;

  insert into private.intelligence_review_attestations(
    asset_id,reviewer_id,scope_key,source_digest_sha256,content_digest_sha256,evidence_id,request_sha256,
    reviewer_nonce_sha256,signed_timestamp,signed_at,signature_b64,signature_basis_sha256,key_fingerprint,expires_at
  ) values(
    p_asset_id,v_identity.reviewer_id,v_scope,v_source,v_content,trim(p_evidence_id),v_expected_request,
    v_nonce_sha,p_timestamp,v_signed_at,p_signature_b64,v_expected_basis_sha,v_identity.key_fingerprint,
    least(now()+interval '2 minutes',v_grant.expires_at)
  ) returning * into v_row;
  return jsonb_build_object('attestationId',v_row.id,'scopeKey',v_scope,'keyFingerprint',v_row.key_fingerprint,'idempotentReplay',false);
end; $$;
revoke all on function public.pandora_record_intelligence_review_attestation(uuid,text,text,text,text,text,text,text,text,text)
  from public,anon,authenticated,projectos_reviewer_ingest;
grant execute on function public.pandora_record_intelligence_review_attestation(uuid,text,text,text,text,text,text,text,text,text) to service_role;

create or replace function public.pandora_finalize_intelligence_review_attestation(
  p_attestation_id uuid,
  p_request_sha256 text,
  p_asset_expires_at timestamptz default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_att private.intelligence_review_attestations%rowtype;
  v_identity private.intelligence_reviewer_identities%rowtype;
  v_grant private.intelligence_reviewer_scope_grants%rowtype;
  v_changed integer;
  v_jti text;
  v_jti_sha text;
begin
  select * into v_att from private.intelligence_review_attestations
   where id=p_attestation_id for update;
  if v_att.id is null or v_att.finalized_at is not null or v_att.expires_at<=now() then
    raise exception 'fresh pending intelligence review attestation required' using errcode='55000';
  end if;
  if lower(trim(coalesce(p_request_sha256,'')))<>v_att.request_sha256 then
    raise exception 'intelligence review finalization request mismatch' using errcode='23514';
  end if;
  select * into v_identity from private.intelligence_reviewer_identities
   where reviewer_id=v_att.reviewer_id and status='active' for update;
  select * into v_grant from private.intelligence_reviewer_scope_grants
   where reviewer_id=v_att.reviewer_id and scope_key=v_att.scope_key and expires_at>now() for update;
  if v_identity.reviewer_id is null or v_grant.reviewer_id is null
     or v_identity.key_fingerprint<>v_att.key_fingerprint
     or not private.pandora_intelligence_reviewer_proof_is_fresh(v_att.reviewer_id,v_identity.runtime_proof_id) then
    raise exception 'fresh reviewer identity and scope grant required at finalization' using errcode='42501';
  end if;

  perform private.pandora_assert_intelligence_certifier(v_att.scope_key,v_att.reviewer_id,v_att.request_sha256);
  perform set_config('pandora.worker_e_certification',v_att.asset_id::text,true);
  update public.pandora_intelligence_assets a
     set trust_state='TRUSTED',verification_worker='E',verification_verdict='PASS',verification_evidence_id=v_att.evidence_id,
         verified_at=now(),expires_at=coalesce(p_asset_expires_at,a.expires_at),block_reason=null
   where a.id=v_att.asset_id
     and a.trust_state in ('DISCOVERED','IMPORTED','EXPERIMENTAL','VERIFIED')
     and a.source_digest_sha256=v_att.source_digest_sha256
     and a.content_digest_sha256 is not distinct from v_att.content_digest_sha256;
  get diagnostics v_changed=row_count;
  if v_changed<>1 then raise exception 'Worker E review attestation asset identity/digest mismatch' using errcode='23514'; end if;
  v_jti := coalesce(auth.jwt()->>'jti','');
  if v_jti !~ '^[A-Za-z0-9._:-]{16,128}$' then raise exception 'valid Worker E authority jti required' using errcode='42501'; end if;
  v_jti_sha := encode(extensions.digest(convert_to(v_jti,'UTF8'),'sha256'),'hex');
  update private.intelligence_review_attestations
     set finalized_at=now(),authority_jti_sha256=v_jti_sha where id=v_att.id;
  return jsonb_build_object('assetId',v_att.asset_id,'attestationId',v_att.id,'trustState','TRUSTED','verificationWorker','E','verificationVerdict','PASS');
end; $$;
revoke all on function public.pandora_finalize_intelligence_review_attestation(uuid,text,timestamptz)
  from public,anon,authenticated,service_role;
grant execute on function public.pandora_finalize_intelligence_review_attestation(uuid,text,timestamptz)
  to projectos_reviewer_ingest;

-- Retire the direct reviewer-role path. The function remains for historical
-- source compatibility but no runtime role may call it directly anymore.
revoke execute on function public.pandora_worker_e_certify_intelligence_asset(uuid,text,text,text,text,text,timestamptz)
  from projectos_reviewer_ingest;

comment on table private.intelligence_reviewer_identities is 'Enrolled independent intelligence reviewers. Enrollment grants no review scope.';
comment on table private.intelligence_reviewer_scope_grants is 'Explicit, time-bounded intelligence review scope grants. No global grant is created by migration.';
comment on table private.intelligence_review_attestations is 'Signed Ed25519 review receipts. Only a fresh independent Worker-E JWT may finalize a pending receipt.';
comment on function public.pandora_finalize_intelligence_review_attestation(uuid,text,timestamptz) is 'Only reviewer-role finalization route for intelligence TRUSTED promotion after signed gateway attestation.';
