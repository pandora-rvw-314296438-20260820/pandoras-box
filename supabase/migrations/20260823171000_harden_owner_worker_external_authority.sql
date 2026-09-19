-- Remove candidate-controlled service-role authority from governed owner and
-- worker mutations. Ordinary ProjectOS plan decisions remain AAL1-capable,
-- but are bound to auth.uid(), a live unexpired Auth session, and live
-- owner/admin membership. Worker claims and completions require fresh,
-- externally issued, exact-request JWTs whose JTIs are consumed atomically.
-- Job envelopes can be recorded only for the dispatch claimed by that same
-- consumed claim JWT; their Ed25519 control signature is issued outside the
-- candidate deployment and is verified by the physical worker.

do $roles$
begin
  if not exists (
    select 1 from pg_roles where rolname = 'projectos_worker_ingest'
  ) then
    create role projectos_worker_ingest nologin noinherit;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticator') then
    execute 'grant projectos_worker_ingest to authenticator';
  end if;
end
$roles$;

grant usage on schema public to projectos_worker_ingest;

create table private.worker_authority_jtis (
  issuer text not null check (issuer = 'pandora-independent-worker-authority'),
  jti_sha256 text not null check (jti_sha256 ~ '^[0-9a-f]{64}$'),
  purpose text not null check (purpose in ('worker_claim', 'worker_complete')),
  organization_id uuid not null,
  worker_id text not null,
  worker_key_fingerprint text not null
    check (worker_key_fingerprint ~ '^[0-9a-f]{64}$'),
  request_id uuid not null,
  dispatch_id uuid,
  plan_id uuid,
  request_sha256 text not null check (request_sha256 ~ '^[0-9a-f]{64}$'),
  authority_issued_at timestamptz not null,
  authority_expires_at timestamptz not null,
  consumed_at timestamptz not null default clock_timestamp(),
  foreign key (organization_id, worker_id)
    references private.compute_worker_identities(organization_id, worker_id)
    on delete restrict,
  primary key (issuer, jti_sha256),
  check (authority_expires_at > authority_issued_at),
  check (consumed_at >= authority_issued_at - interval '30 seconds'),
  check (
    (purpose = 'worker_claim' and dispatch_id is null and plan_id is null)
    or (purpose = 'worker_complete' and dispatch_id is not null and plan_id is not null)
  )
);

create index worker_authority_jtis_expiry_idx
  on private.worker_authority_jtis (authority_expires_at);

alter table private.worker_authority_jtis enable row level security;
revoke all on table private.worker_authority_jtis
  from public, anon, authenticated, service_role, projectos_worker_ingest;

alter table private.execution_dispatch_outbox
  add column worker_claim_request_id uuid,
  add column worker_claim_jti_sha256 text
    check (worker_claim_jti_sha256 is null or worker_claim_jti_sha256 ~ '^[0-9a-f]{64}$'),
  add column worker_claim_authority_request_sha256 text
    check (
      worker_claim_authority_request_sha256 is null
      or worker_claim_authority_request_sha256 ~ '^[0-9a-f]{64}$'
    ),
  add column worker_completion_request_id uuid,
  add column worker_completion_nonce_sha256 text
    check (worker_completion_nonce_sha256 is null or worker_completion_nonce_sha256 ~ '^[0-9a-f]{64}$'),
  add column worker_completion_signed_timestamp text
    check (
      worker_completion_signed_timestamp is null
      or worker_completion_signed_timestamp ~
        '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$'
    ),
  add column worker_completion_signature_b64 text
    check (
      worker_completion_signature_b64 is null
      or worker_completion_signature_b64 ~ '^[A-Za-z0-9+/]{86}==$'
    ),
  add column worker_completion_signature_basis_sha256 text
    check (
      worker_completion_signature_basis_sha256 is null
      or worker_completion_signature_basis_sha256 ~ '^[0-9a-f]{64}$'
    ),
  add column worker_completion_authority_request_sha256 text
    check (
      worker_completion_authority_request_sha256 is null
      or worker_completion_authority_request_sha256 ~ '^[0-9a-f]{64}$'
    );

alter table private.governed_worker_review_attestations
  add column worker_completion_request_id uuid,
  add column worker_completion_nonce_sha256 text
    check (worker_completion_nonce_sha256 is null or worker_completion_nonce_sha256 ~ '^[0-9a-f]{64}$'),
  add column worker_completion_signed_timestamp text,
  add column worker_completion_signature_b64 text
    check (
      worker_completion_signature_b64 is null
      or worker_completion_signature_b64 ~ '^[A-Za-z0-9+/]{86}==$'
    ),
  add column worker_completion_signature_basis_sha256 text
    check (
      worker_completion_signature_basis_sha256 is null
      or worker_completion_signature_basis_sha256 ~ '^[0-9a-f]{64}$'
    ),
  add column worker_completion_authority_request_sha256 text
    check (
      worker_completion_authority_request_sha256 is null
      or worker_completion_authority_request_sha256 ~ '^[0-9a-f]{64}$'
    );

create or replace function private.assert_worker_ingest_role()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if session_user <> 'postgres'
     and coalesce(auth.jwt() ->> 'role', '') <> 'projectos_worker_ingest' then
    raise exception 'worker ingest role required' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.assert_worker_ingest_role()
  from public, anon, authenticated, service_role, projectos_worker_ingest;

create or replace function private.consume_worker_authority(
  p_purpose text,
  p_organization_id uuid,
  p_worker_id text,
  p_worker_key_fingerprint text,
  p_request_id uuid,
  p_dispatch_id uuid,
  p_plan_id uuid,
  p_request_sha256 text
) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  claims jsonb := auth.jwt();
  token_jti text;
  token_iat_epoch numeric;
  token_nbf_epoch numeric;
  token_exp_epoch numeric;
  token_iat timestamptz;
  token_nbf timestamptz;
  token_exp timestamptz;
  accepted_jti text;
begin
  perform private.assert_worker_ingest_role();
  p_worker_id := lower(trim(coalesce(p_worker_id, '')));
  token_jti := coalesce(claims ->> 'jti', '');
  if p_purpose not in ('worker_claim', 'worker_complete')
     or p_organization_id is null
     or p_worker_id !~ '^[a-z0-9][a-z0-9._:-]{2,127}$'
     or coalesce(p_worker_key_fingerprint, '') !~ '^[0-9a-f]{64}$'
     or p_request_id is null
     or coalesce(p_request_sha256, '') !~ '^[0-9a-f]{64}$'
     or coalesce(claims ->> 'role', '') <> 'projectos_worker_ingest'
     or coalesce(claims ->> 'iss', '') <> 'pandora-independent-worker-authority'
     or coalesce(claims ->> 'aud', '') <> 'projectos_worker_ingest'
     or coalesce(claims ->> 'purpose', '') <> p_purpose
     or coalesce(claims ->> 'sub', '') <> p_request_id::text
     or coalesce(claims ->> 'organization_id', '') <> p_organization_id::text
     or lower(coalesce(claims ->> 'worker_id', '')) <> p_worker_id
     or coalesce(claims ->> 'worker_key_fingerprint', '') <> p_worker_key_fingerprint
     or coalesce(claims ->> 'request_id', '') <> p_request_id::text
     or coalesce(claims ->> 'dispatch_id', '') <> coalesce(p_dispatch_id::text, '')
     or coalesce(claims ->> 'plan_id', '') <> coalesce(p_plan_id::text, '')
     or coalesce(claims ->> 'request_sha256', '') <> p_request_sha256
     or token_jti !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{15,127}$'
     or coalesce(claims ->> 'iat', '') !~ '^[0-9]+(?:\.[0-9]+)?$'
     or coalesce(claims ->> 'exp', '') !~ '^[0-9]+(?:\.[0-9]+)?$'
     or (
       claims ? 'nbf'
       and coalesce(claims ->> 'nbf', '') !~ '^[0-9]+(?:\.[0-9]+)?$'
     ) then
    raise exception 'exact external worker authority required' using errcode = '42501';
  end if;

  token_iat_epoch := (claims ->> 'iat')::numeric;
  token_nbf_epoch := coalesce(nullif(claims ->> 'nbf', '')::numeric, token_iat_epoch);
  token_exp_epoch := (claims ->> 'exp')::numeric;
  token_iat := to_timestamp(token_iat_epoch);
  token_nbf := to_timestamp(token_nbf_epoch);
  token_exp := to_timestamp(token_exp_epoch);
  if token_iat < statement_timestamp() - interval '2 minutes'
     or token_iat > statement_timestamp() + interval '30 seconds'
     or token_nbf < token_iat - interval '5 seconds'
     or token_nbf > statement_timestamp() + interval '5 seconds'
     or token_exp <= statement_timestamp()
     or token_exp > token_iat + interval '2 minutes' then
    raise exception 'fresh short-lived worker authority required' using errcode = '42501';
  end if;

  delete from private.worker_authority_jtis
  where authority_expires_at < statement_timestamp() - interval '5 minutes';
  insert into private.worker_authority_jtis (
    issuer, jti_sha256, purpose, organization_id, worker_id,
    worker_key_fingerprint, request_id, dispatch_id, plan_id, request_sha256,
    authority_issued_at, authority_expires_at
  ) values (
    'pandora-independent-worker-authority',
    encode(extensions.digest(convert_to(token_jti, 'UTF8'), 'sha256'), 'hex'),
    p_purpose, p_organization_id, p_worker_id, p_worker_key_fingerprint,
    p_request_id, p_dispatch_id, p_plan_id, p_request_sha256, token_iat, token_exp
  ) on conflict do nothing
  returning jti_sha256 into accepted_jti;
  if accepted_jti is null then
    raise exception 'worker authority token already consumed' using errcode = '23505';
  end if;
  return accepted_jti;
end;
$$;

revoke all on function private.consume_worker_authority(
  text,uuid,text,text,uuid,uuid,uuid,text
) from public, anon, authenticated, service_role, projectos_worker_ingest;

create or replace function private.consume_worker_signed_nonce(
  p_organization_id uuid,
  p_worker_id text,
  p_nonce text
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  accepted_worker text;
begin
  perform 1
  from private.compute_worker_identities worker
  where worker.organization_id = p_organization_id
    and worker.worker_id = lower(trim(p_worker_id))
    and worker.status in ('active', 'draining')
  for update;
  if not found then
    return false;
  end if;

  delete from private.compute_worker_nonces
  where expires_at <= statement_timestamp();
  if (
    select count(*)
    from private.compute_worker_nonces nonce
    where nonce.organization_id = p_organization_id
      and nonce.worker_id = lower(trim(p_worker_id))
  ) >= 2048 then
    raise exception 'worker nonce retention limit reached' using errcode = '54000';
  end if;
  insert into private.compute_worker_nonces (
    organization_id, worker_id, nonce_sha256, expires_at
  ) values (
    p_organization_id,
    lower(trim(p_worker_id)),
    encode(extensions.digest(convert_to(p_nonce, 'UTF8'), 'sha256'), 'hex'),
    statement_timestamp() + interval '15 minutes'
  ) on conflict do nothing
  returning worker_id into accepted_worker;
  return accepted_worker is not null;
end;
$$;

revoke all on function private.consume_worker_signed_nonce(uuid,text,text)
  from public, anon, authenticated, service_role, projectos_worker_ingest;

create or replace function private.assert_live_plan_approver(
  p_organization_id uuid
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  claims jsonb := auth.jwt();
  owner_user_id uuid := auth.uid();
  current_session_id uuid;
  jwt_aal text := coalesce(auth.jwt() ->> 'aal', '');
  live_session_aal text;
begin
  begin
    current_session_id := nullif(claims ->> 'session_id', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'live owner or admin plan session required' using errcode = '42501';
  end;

  if session_user not in ('authenticator', 'postgres')
     or owner_user_id is null
     or current_session_id is null
     or coalesce(claims ->> 'role', '') <> 'authenticated'
     or jwt_aal not in ('aal1', 'aal2')
     or coalesce(claims ->> 'is_anonymous', 'false') <> 'false' then
    raise exception 'live owner or admin plan authority required' using errcode = '42501';
  end if;

  select session.aal::text into live_session_aal
  from auth.sessions session
  join auth.users owner_user
    on owner_user.id = session.user_id
   and owner_user.is_anonymous = false
  where session.id = current_session_id
    and session.user_id = owner_user_id
    and session.aal in ('aal1'::auth.aal_level, 'aal2'::auth.aal_level)
    and (session.not_after is null or session.not_after > statement_timestamp());
  if live_session_aal is null
     or (jwt_aal = 'aal2' and live_session_aal <> 'aal2') then
    raise exception 'live owner or admin plan session required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.memberships membership
    where membership.organization_id = p_organization_id
      and membership.user_id = owner_user_id
      and membership.status = 'active'
      and membership.role in ('owner', 'admin')
  ) then
    raise exception 'live owner or admin plan authority required' using errcode = '42501';
  end if;
  return owner_user_id;
end;
$$;

revoke all on function private.assert_live_plan_approver(uuid)
  from public, anon, authenticated, service_role, projectos_worker_ingest;

-- The four-argument implementation remains internal. This caller-visible
-- wrapper derives decidedBy from auth.uid() and elevates only for the already
-- authorized exact plan transition.
create or replace function public.decide_governed_worker_execution_plan(
  p_organization_id uuid,
  p_plan_id uuid,
  p_decision text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_user_id uuid;
  prior_claims text;
  result_payload jsonb;
begin
  owner_user_id := private.assert_live_plan_approver(p_organization_id);
  prior_claims := coalesce(current_setting('request.jwt.claims', true), '{}');
  perform set_config(
    'request.jwt.claims',
    (coalesce(nullif(prior_claims, ''), '{}')::jsonb
      || jsonb_build_object('role', 'service_role'))::text,
    true
  );
  result_payload := public.decide_governed_worker_execution_plan(
    p_organization_id,
    p_plan_id,
    p_decision,
    'owner:' || owner_user_id::text
  );
  perform set_config('request.jwt.claims', prior_claims, true);
  return result_payload;
end;
$$;

revoke all on function public.decide_governed_worker_execution_plan(uuid,uuid,text)
  from public, anon, authenticated, service_role, projectos_worker_ingest;
grant execute on function public.decide_governed_worker_execution_plan(uuid,uuid,text)
  to authenticated;

revoke all on function public.decide_governed_worker_execution_plan(uuid,uuid,text,text)
  from public, anon, authenticated, service_role, projectos_worker_ingest;

create or replace function public.claim_governed_worker_dispatch_authorized(
  p_organization_id uuid,
  p_worker_identity text,
  p_expected_key_fingerprint text,
  p_request_id uuid,
  p_nonce text,
  p_timestamp text,
  p_signature_b64 text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  prior_claims text;
  signature_basis text;
  signature_basis_sha256 text;
  signature_sha256 text;
  authority_request_sha256 text;
  authority_jti_sha256 text;
  signed_at timestamptz;
  result_payload jsonb;
  result_dispatch_id uuid;
  result_plan_id uuid;
begin
  perform private.assert_worker_ingest_role();
  p_worker_identity := lower(trim(coalesce(p_worker_identity, '')));
  if p_worker_identity !~ '^[a-z0-9][a-z0-9._:-]{2,127}$'
     or coalesce(p_expected_key_fingerprint, '') !~ '^[0-9a-f]{64}$'
     or p_request_id is null
     or coalesce(p_nonce, '') !~ '^[A-Za-z0-9._:-]{16,128}$'
     or coalesce(p_timestamp, '') !~
       '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$'
     or coalesce(p_signature_b64, '') !~ '^[A-Za-z0-9+/]{86}==$' then
    raise exception 'invalid authorized worker claim' using errcode = '22023';
  end if;
  begin
    signed_at := p_timestamp::timestamptz;
    if abs(extract(epoch from (statement_timestamp() - signed_at))) > 300
       or octet_length(decode(p_signature_b64, 'base64')) <> 64 then
      raise exception 'invalid authorized worker claim';
    end if;
  exception when others then
    raise exception 'invalid authorized worker claim' using errcode = '22023';
  end;

  perform 1
  from private.compute_worker_identities worker
  where worker.organization_id = p_organization_id
    and worker.worker_id = p_worker_identity
    and worker.key_fingerprint = p_expected_key_fingerprint
    and worker.status = 'active'
  for update;
  if not found then
    raise exception 'active exact worker key required' using errcode = '42501';
  end if;

  signature_basis := concat_ws('|',
    'pandora-worker-request-v1', 'claim', p_organization_id::text,
    p_worker_identity, p_request_id::text, p_nonce, p_timestamp
  );
  signature_basis_sha256 := encode(
    extensions.digest(convert_to(signature_basis, 'UTF8'), 'sha256'), 'hex'
  );
  signature_sha256 := encode(
    extensions.digest(decode(p_signature_b64, 'base64'), 'sha256'), 'hex'
  );
  authority_request_sha256 := encode(extensions.digest(convert_to(concat_ws('|',
    'pandora-worker-authority-v1', 'worker_claim', signature_basis_sha256,
    p_expected_key_fingerprint, signature_sha256
  ), 'UTF8'), 'sha256'), 'hex');

  authority_jti_sha256 := private.consume_worker_authority(
    'worker_claim', p_organization_id, p_worker_identity,
    p_expected_key_fingerprint, p_request_id, null, null,
    authority_request_sha256
  );
  if not private.consume_worker_signed_nonce(
    p_organization_id, p_worker_identity, p_nonce
  ) then
    raise exception 'worker signed nonce already consumed' using errcode = '23505';
  end if;

  prior_claims := coalesce(current_setting('request.jwt.claims', true), '{}');
  perform set_config(
    'request.jwt.claims',
    (coalesce(nullif(prior_claims, ''), '{}')::jsonb
      || jsonb_build_object('role', 'service_role'))::text,
    true
  );
  result_payload := public.claim_governed_worker_dispatch(
    p_organization_id, p_worker_identity, p_expected_key_fingerprint
  );

  if result_payload is not null and result_payload <> 'null'::jsonb then
    begin
      result_dispatch_id := (result_payload ->> 'dispatchId')::uuid;
      result_plan_id := (result_payload ->> 'planId')::uuid;
    exception when others then
      raise exception 'worker claim readback identity missing' using errcode = '55000';
    end;
    if coalesce(result_payload ->> 'status', '') = 'claimed' then
      update private.execution_dispatch_outbox dispatch
      set worker_claim_request_id = p_request_id,
          worker_claim_jti_sha256 = authority_jti_sha256,
          worker_claim_authority_request_sha256 = authority_request_sha256,
          updated_at = now()
      where dispatch.organization_id = p_organization_id
        and dispatch.id = result_dispatch_id
        and dispatch.plan_id = result_plan_id
        and dispatch.worker_identity = p_worker_identity
        and dispatch.worker_key_fingerprint = p_expected_key_fingerprint
        and dispatch.status = 'claimed'
        and dispatch.job_digest is null;
      if not found then
        raise exception 'worker claim receipt binding conflict' using errcode = '55000';
      end if;
    end if;
  end if;
  perform set_config('request.jwt.claims', prior_claims, true);
  return result_payload;
end;
$$;

-- The same short-lived claim JWT may record exactly one DB-validated job
-- envelope for the dispatch it just claimed. No second authority token is
-- needed or accepted. The external authority returns only the control
-- signature for this exact envelope; the candidate Edge holds no signing key.
create or replace function public.record_governed_worker_job_envelope_authorized(
  p_organization_id uuid,
  p_dispatch_id uuid,
  p_plan_id uuid,
  p_worker_identity text,
  p_expected_key_fingerprint text,
  p_job_digest text,
  p_job_payload jsonb,
  p_job_signature text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  claims jsonb := auth.jwt();
  prior_claims text;
  token_jti_sha256 text;
  dispatch private.execution_dispatch_outbox%rowtype;
  result_payload jsonb;
begin
  perform private.assert_worker_ingest_role();
  p_worker_identity := lower(trim(coalesce(p_worker_identity, '')));
  if p_worker_identity !~ '^[a-z0-9][a-z0-9._:-]{2,127}$'
     or coalesce(p_expected_key_fingerprint, '') !~ '^[0-9a-f]{64}$'
     or p_dispatch_id is null
     or p_plan_id is null
     or coalesce(p_job_digest, '') !~ '^[0-9a-f]{64}$'
     or private.projectos_worker_job_payload_is_valid(p_job_payload) is distinct from true
     or coalesce(p_job_signature, '') !~ '^[A-Za-z0-9+/]{86}==$' then
    raise exception 'invalid authorized worker job envelope' using errcode = '22023';
  end if;
  begin
    if octet_length(decode(p_job_signature, 'base64')) <> 64 then
      raise exception 'invalid authorized worker job envelope';
    end if;
    token_jti_sha256 := encode(extensions.digest(
      convert_to(coalesce(claims ->> 'jti', ''), 'UTF8'), 'sha256'
    ), 'hex');
  exception when others then
    raise exception 'invalid authorized worker job envelope' using errcode = '22023';
  end;

  select candidate.* into dispatch
  from private.execution_dispatch_outbox candidate
  join private.compute_worker_identities worker
    on worker.organization_id = candidate.organization_id
   and worker.worker_id = candidate.worker_identity
  where candidate.organization_id = p_organization_id
    and candidate.id = p_dispatch_id
    and candidate.plan_id = p_plan_id
    and candidate.worker_identity = p_worker_identity
    and candidate.worker_key_fingerprint = p_expected_key_fingerprint
    and candidate.status in ('claimed', 'envelope_ready')
    and candidate.lease_expires_at > statement_timestamp()
    and candidate.worker_claim_request_id is not null
    and candidate.worker_claim_jti_sha256 = token_jti_sha256
    and candidate.worker_claim_authority_request_sha256 ~ '^[0-9a-f]{64}$'
    and worker.key_fingerprint = p_expected_key_fingerprint
    and worker.status = 'active'
  for update of candidate, worker;
  if dispatch.id is null then
    raise exception 'exact externally authorized worker claim required for job envelope'
      using errcode = '42501';
  end if;

  if coalesce(claims ->> 'role', '') <> 'projectos_worker_ingest'
     or coalesce(claims ->> 'iss', '') <> 'pandora-independent-worker-authority'
     or coalesce(claims ->> 'aud', '') <> 'projectos_worker_ingest'
     or coalesce(claims ->> 'purpose', '') <> 'worker_claim'
     or coalesce(claims ->> 'sub', '') <> dispatch.worker_claim_request_id::text
     or coalesce(claims ->> 'organization_id', '') <> p_organization_id::text
     or lower(coalesce(claims ->> 'worker_id', '')) <> p_worker_identity
     or coalesce(claims ->> 'worker_key_fingerprint', '') <> p_expected_key_fingerprint
     or coalesce(claims ->> 'request_id', '') <> dispatch.worker_claim_request_id::text
     or coalesce(claims ->> 'dispatch_id', '') <> ''
     or coalesce(claims ->> 'plan_id', '') <> ''
     or coalesce(claims ->> 'request_sha256', '')
          <> dispatch.worker_claim_authority_request_sha256
     or not exists (
       select 1
       from private.worker_authority_jtis authority
       where authority.issuer = 'pandora-independent-worker-authority'
         and authority.jti_sha256 = token_jti_sha256
         and authority.purpose = 'worker_claim'
         and authority.organization_id = p_organization_id
         and authority.worker_id = p_worker_identity
         and authority.worker_key_fingerprint = p_expected_key_fingerprint
         and authority.request_id = dispatch.worker_claim_request_id
         and authority.request_sha256 = dispatch.worker_claim_authority_request_sha256
         and authority.authority_expires_at > statement_timestamp()
     ) then
    raise exception 'consumed exact worker claim authority required for job envelope'
      using errcode = '42501';
  end if;

  if p_job_digest is distinct from private.projectos_worker_job_digest(p_job_payload) then
    raise exception 'authorized worker job digest mismatch' using errcode = '55000';
  end if;

  prior_claims := coalesce(current_setting('request.jwt.claims', true), '{}');
  perform set_config(
    'request.jwt.claims',
    (coalesce(nullif(prior_claims, ''), '{}')::jsonb
      || jsonb_build_object('role', 'service_role'))::text,
    true
  );
  result_payload := public.record_governed_worker_job_envelope(
    p_organization_id, p_dispatch_id, p_plan_id, p_worker_identity,
    p_job_digest, p_job_payload, p_job_signature
  );
  perform set_config('request.jwt.claims', prior_claims, true);
  return result_payload;
end;
$$;

create or replace function public.finish_governed_worker_dispatch_authorized(
  p_organization_id uuid,
  p_dispatch_id uuid,
  p_plan_id uuid,
  p_worker_identity text,
  p_expected_key_fingerprint text,
  p_outcome text,
  p_duration_ms integer,
  p_job_digest text,
  p_evidence_sha256 text,
  p_result_summary jsonb,
  p_request_id uuid,
  p_nonce text,
  p_timestamp text,
  p_signature_b64 text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  prior_claims text;
  signature_basis text;
  signature_basis_sha256 text;
  signature_sha256 text;
  authority_request_sha256 text;
  nonce_sha256 text;
  signed_at timestamptz;
  dispatch private.execution_dispatch_outbox%rowtype;
  exact_replay boolean;
  result_payload jsonb;
begin
  perform private.assert_worker_ingest_role();
  p_worker_identity := lower(trim(coalesce(p_worker_identity, '')));
  p_outcome := lower(trim(coalesce(p_outcome, '')));
  if p_worker_identity !~ '^[a-z0-9][a-z0-9._:-]{2,127}$'
     or coalesce(p_expected_key_fingerprint, '') !~ '^[0-9a-f]{64}$'
     or p_request_id is null
     or p_dispatch_id is null
     or p_plan_id is null
     or p_outcome not in ('completed', 'failed')
     or coalesce(p_duration_ms, -1) not between 0 and 2100000
     or coalesce(p_job_digest, '') !~ '^[0-9a-f]{64}$'
     or coalesce(p_evidence_sha256, '') !~ '^[0-9a-f]{64}$'
     or private.projectos_worker_result_summary_is_valid(p_result_summary) is distinct from true
     or coalesce(p_nonce, '') !~ '^[A-Za-z0-9._:-]{16,128}$'
     or coalesce(p_timestamp, '') !~
       '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$'
     or coalesce(p_signature_b64, '') !~ '^[A-Za-z0-9+/]{86}==$' then
    raise exception 'invalid authorized worker completion' using errcode = '22023';
  end if;
  begin
    signed_at := p_timestamp::timestamptz;
    if octet_length(decode(p_signature_b64, 'base64')) <> 64 then
      raise exception 'invalid authorized worker completion';
    end if;
  exception when others then
    raise exception 'invalid authorized worker completion' using errcode = '22023';
  end;

  signature_basis := concat_ws('|',
    'pandora-worker-request-v1', 'complete', p_organization_id::text,
    p_worker_identity, p_request_id::text, p_nonce, p_timestamp,
    p_dispatch_id::text, p_plan_id::text, p_job_digest, p_outcome,
    p_duration_ms::text, p_evidence_sha256
  );
  signature_basis_sha256 := encode(
    extensions.digest(convert_to(signature_basis, 'UTF8'), 'sha256'), 'hex'
  );
  signature_sha256 := encode(
    extensions.digest(decode(p_signature_b64, 'base64'), 'sha256'), 'hex'
  );
  authority_request_sha256 := encode(extensions.digest(convert_to(concat_ws('|',
    'pandora-worker-authority-v1', 'worker_complete', signature_basis_sha256,
    p_expected_key_fingerprint, signature_sha256
  ), 'UTF8'), 'sha256'), 'hex');
  nonce_sha256 := encode(
    extensions.digest(convert_to(p_nonce, 'UTF8'), 'sha256'), 'hex'
  );

  perform private.consume_worker_authority(
    'worker_complete', p_organization_id, p_worker_identity,
    p_expected_key_fingerprint, p_request_id, p_dispatch_id, p_plan_id,
    authority_request_sha256
  );

  select candidate.* into dispatch
  from private.execution_dispatch_outbox candidate
  join private.compute_worker_identities worker
    on worker.organization_id = candidate.organization_id
   and worker.worker_id = candidate.worker_identity
  where candidate.organization_id = p_organization_id
    and candidate.id = p_dispatch_id
    and candidate.plan_id = p_plan_id
    and candidate.worker_identity = p_worker_identity
    and candidate.worker_key_fingerprint = p_expected_key_fingerprint
    and candidate.job_digest = p_job_digest
    and worker.key_fingerprint = p_expected_key_fingerprint
    and worker.status in ('active', 'draining')
  for update of candidate, worker;
  if dispatch.id is null then
    raise exception 'exact active worker dispatch required for completion'
      using errcode = '42501';
  end if;

  exact_replay := dispatch.worker_completion_request_id = p_request_id
    and dispatch.worker_completion_nonce_sha256 = nonce_sha256
    and dispatch.worker_completion_signed_timestamp = p_timestamp
    and dispatch.worker_completion_signature_b64 = p_signature_b64
    and dispatch.worker_completion_signature_basis_sha256 = signature_basis_sha256
    and dispatch.worker_completion_authority_request_sha256 = authority_request_sha256
    and dispatch.evidence_sha256 = p_evidence_sha256
    and dispatch.result_summary = p_result_summary;
  if exact_replay and dispatch.status in (
    'result_reported', 'finalizing', 'completed', 'failed'
  ) then
    return jsonb_build_object(
      'dispatchId', dispatch.id,
      'planId', dispatch.plan_id,
      'status', dispatch.status,
      'evidenceSha256', dispatch.evidence_sha256,
      'reviewRequired', dispatch.status in ('result_reported', 'finalizing'),
      'idempotentReplay', true
    );
  end if;
  if abs(extract(epoch from (statement_timestamp() - signed_at))) > 300 then
    raise exception 'fresh signed worker completion required' using errcode = '42501';
  end if;
  if dispatch.worker_completion_signature_b64 is not null then
    raise exception 'worker completion signature binding differs' using errcode = '55000';
  end if;
  if not private.consume_worker_signed_nonce(
    p_organization_id, p_worker_identity, p_nonce
  ) then
    raise exception 'worker signed nonce already consumed' using errcode = '23505';
  end if;

  prior_claims := coalesce(current_setting('request.jwt.claims', true), '{}');
  perform set_config(
    'request.jwt.claims',
    (coalesce(nullif(prior_claims, ''), '{}')::jsonb
      || jsonb_build_object('role', 'service_role'))::text,
    true
  );
  update private.execution_dispatch_outbox candidate
  set worker_completion_request_id = p_request_id,
      worker_completion_nonce_sha256 = nonce_sha256,
      worker_completion_signed_timestamp = p_timestamp,
      worker_completion_signature_b64 = p_signature_b64,
      worker_completion_signature_basis_sha256 = signature_basis_sha256,
      worker_completion_authority_request_sha256 = authority_request_sha256,
      updated_at = now()
  where candidate.id = dispatch.id
    and candidate.status in ('envelope_ready', 'ambiguous')
    and candidate.worker_completion_signature_b64 is null;
  if not found then
    raise exception 'worker completion signature transition conflict' using errcode = '55000';
  end if;

  result_payload := public.finish_governed_worker_dispatch(
    p_organization_id, p_dispatch_id, p_plan_id, p_worker_identity,
    p_expected_key_fingerprint, p_outcome, p_duration_ms, p_job_digest,
    p_evidence_sha256, p_result_summary
  );
  perform set_config('request.jwt.claims', prior_claims, true);
  return result_payload;
end;
$$;

create or replace function private.guard_worker_authority_receipts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.worker_claim_jti_sha256 is not null
     and (
       old.worker_claim_request_id is distinct from new.worker_claim_request_id
       or old.worker_claim_jti_sha256 is distinct from new.worker_claim_jti_sha256
       or old.worker_claim_authority_request_sha256 is distinct from
          new.worker_claim_authority_request_sha256
     )
     and not (
       old.status = 'claimed' and new.status = 'claimed'
       and old.job_digest is null and new.job_digest is null
     ) then
    raise exception 'worker claim authority receipt is immutable'
      using errcode = '55000';
  end if;

  if old.worker_completion_signature_b64 is not null
     and (
       old.worker_completion_request_id is distinct from new.worker_completion_request_id
       or old.worker_completion_nonce_sha256 is distinct from new.worker_completion_nonce_sha256
       or old.worker_completion_signed_timestamp is distinct from
          new.worker_completion_signed_timestamp
       or old.worker_completion_signature_b64 is distinct from
          new.worker_completion_signature_b64
       or old.worker_completion_signature_basis_sha256 is distinct from
          new.worker_completion_signature_basis_sha256
       or old.worker_completion_authority_request_sha256 is distinct from
          new.worker_completion_authority_request_sha256
     ) then
    raise exception 'worker completion authority receipt is immutable'
      using errcode = '55000';
  end if;

  if new.status in (
       'envelope_ready', 'result_reported', 'finalizing', 'completed', 'failed'
     ) and (
       new.worker_claim_request_id is null
       or new.worker_claim_jti_sha256 is null
       or new.worker_claim_authority_request_sha256 is null
     ) then
    raise exception 'externally authorized worker claim receipt required'
      using errcode = '55000';
  end if;
  if new.status in ('result_reported', 'finalizing', 'completed', 'failed')
     and (
       new.worker_completion_request_id is null
       or new.worker_completion_nonce_sha256 is null
       or new.worker_completion_signed_timestamp is null
       or new.worker_completion_signature_b64 is null
       or new.worker_completion_signature_basis_sha256 is null
       or new.worker_completion_authority_request_sha256 is null
     ) then
    raise exception 'externally authorized signed worker completion required'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_worker_authority_receipts()
  from public, anon, authenticated, service_role, projectos_worker_ingest;

create trigger guard_worker_authority_receipts
before update on private.execution_dispatch_outbox
for each row execute function private.guard_worker_authority_receipts();

-- Copy the exact durable worker completion receipt into both the independent
-- reviewer attestation and its public evidence payload. This prevents a valid
-- reviewer signature from being rebound to an unsigned or differently signed
-- worker result.
create or replace function private.bind_worker_completion_to_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  dispatch private.execution_dispatch_outbox%rowtype;
  bound_evidence_id uuid;
begin
  select candidate.* into dispatch
  from private.execution_dispatch_outbox candidate
  where candidate.organization_id = new.organization_id
    and candidate.id = new.dispatch_id
    and candidate.plan_id = new.plan_id
    and candidate.evidence_sha256 = new.worker_evidence_sha256
    and candidate.status = 'result_reported'
  for share;
  if dispatch.id is null
     or dispatch.worker_completion_request_id is null
     or dispatch.worker_completion_nonce_sha256 is null
     or dispatch.worker_completion_signed_timestamp is null
     or dispatch.worker_completion_signature_b64 is null
     or dispatch.worker_completion_signature_basis_sha256 is null
     or dispatch.worker_completion_authority_request_sha256 is null then
    raise exception 'signed worker completion receipt required for reviewer evidence'
      using errcode = '55000';
  end if;

  new.worker_completion_request_id := dispatch.worker_completion_request_id;
  new.worker_completion_nonce_sha256 := dispatch.worker_completion_nonce_sha256;
  new.worker_completion_signed_timestamp := dispatch.worker_completion_signed_timestamp;
  new.worker_completion_signature_b64 := dispatch.worker_completion_signature_b64;
  new.worker_completion_signature_basis_sha256 :=
    dispatch.worker_completion_signature_basis_sha256;
  new.worker_completion_authority_request_sha256 :=
    dispatch.worker_completion_authority_request_sha256;

  update public.projectos_evidence evidence
  set payload_redacted = evidence.payload_redacted || jsonb_build_object(
    'workerCompletion', jsonb_build_object(
      'requestId', dispatch.worker_completion_request_id,
      'nonceSha256', dispatch.worker_completion_nonce_sha256,
      'signedTimestamp', dispatch.worker_completion_signed_timestamp,
      'signatureB64', dispatch.worker_completion_signature_b64,
      'signatureBasisSha256', dispatch.worker_completion_signature_basis_sha256,
      'authorityRequestSha256', dispatch.worker_completion_authority_request_sha256
    )
  )
  where evidence.id = new.evidence_id
    and evidence.organization_id = new.organization_id
    and evidence.payload_redacted ->> 'dispatchId' = new.dispatch_id::text
    and evidence.payload_redacted ->> 'workerEvidenceSha256' = new.worker_evidence_sha256
  returning evidence.id into bound_evidence_id;
  if bound_evidence_id is null then
    raise exception 'reviewer evidence worker receipt binding failed'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke all on function private.bind_worker_completion_to_review()
  from public, anon, authenticated, service_role, projectos_worker_ingest,
       projectos_reviewer_ingest;

create trigger bind_worker_completion_to_review
before insert on private.governed_worker_review_attestations
for each row execute function private.bind_worker_completion_to_review();

create or replace function private.guard_physical_android_worker_completion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from private.execution_dispatch_outbox dispatch
    join private.governed_worker_review_attestations attestation
      on attestation.organization_id = dispatch.organization_id
     and attestation.dispatch_id = dispatch.id
     and attestation.plan_id = dispatch.plan_id
     and attestation.evidence_id = dispatch.verification_evidence_id
     and attestation.reviewer_runtime_proof_id = dispatch.verifier_runtime_proof_id
    join public.projectos_evidence evidence
      on evidence.organization_id = attestation.organization_id
     and evidence.id = attestation.evidence_id
    where dispatch.organization_id = new.organization_id
      and dispatch.id = new.owner_dispatch_id
      and dispatch.plan_id = new.owner_plan_id
      and dispatch.evidence_sha256 = new.worker_evidence_sha256
      and dispatch.verification_evidence_id = new.verification_evidence_id
      and dispatch.verifier_runtime_proof_id = new.reviewer_runtime_proof_id
      and dispatch.worker_completion_request_id is not null
      and attestation.worker_completion_request_id = dispatch.worker_completion_request_id
      and attestation.worker_completion_nonce_sha256 = dispatch.worker_completion_nonce_sha256
      and attestation.worker_completion_signed_timestamp =
          dispatch.worker_completion_signed_timestamp
      and attestation.worker_completion_signature_b64 =
          dispatch.worker_completion_signature_b64
      and attestation.worker_completion_signature_basis_sha256 =
          dispatch.worker_completion_signature_basis_sha256
      and attestation.worker_completion_authority_request_sha256 =
          dispatch.worker_completion_authority_request_sha256
      and evidence.payload_redacted -> 'workerCompletion' = jsonb_build_object(
        'requestId', dispatch.worker_completion_request_id,
        'nonceSha256', dispatch.worker_completion_nonce_sha256,
        'signedTimestamp', dispatch.worker_completion_signed_timestamp,
        'signatureB64', dispatch.worker_completion_signature_b64,
        'signatureBasisSha256', dispatch.worker_completion_signature_basis_sha256,
        'authorityRequestSha256', dispatch.worker_completion_authority_request_sha256
      )
  ) then
    raise exception 'signed worker completion receipt required for physical Android evidence'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_physical_android_worker_completion()
  from public, anon, authenticated, service_role, projectos_worker_ingest,
       projectos_reviewer_ingest, projectos_physical_android_ingest;

create trigger guard_physical_android_worker_completion
before insert on private.canonical_physical_android_receipts
for each row execute function private.guard_physical_android_worker_completion();

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
       join public.projectos_evidence evidence
         on evidence.id = attestation.evidence_id
        and evidence.organization_id = attestation.organization_id
       where attestation.organization_id = new.organization_id
         and attestation.dispatch_id = new.id
         and attestation.plan_id = new.plan_id
         and attestation.reviewer_runtime_proof_id = new.verifier_runtime_proof_id
         and attestation.evidence_id = new.verification_evidence_id
         and attestation.decision = new.verified_outcome
         and attestation.worker_evidence_sha256 = new.evidence_sha256
         and attestation.source_tree_sha = new.result_summary ->> 'sourceTreeSha'
         and attestation.worker_completion_request_id = new.worker_completion_request_id
         and attestation.worker_completion_nonce_sha256 = new.worker_completion_nonce_sha256
         and attestation.worker_completion_signed_timestamp =
             new.worker_completion_signed_timestamp
         and attestation.worker_completion_signature_b64 =
             new.worker_completion_signature_b64
         and attestation.worker_completion_signature_basis_sha256 =
             new.worker_completion_signature_basis_sha256
         and attestation.worker_completion_authority_request_sha256 =
             new.worker_completion_authority_request_sha256
         and evidence.payload_redacted -> 'workerCompletion' = jsonb_build_object(
           'requestId', new.worker_completion_request_id,
           'nonceSha256', new.worker_completion_nonce_sha256,
           'signedTimestamp', new.worker_completion_signed_timestamp,
           'signatureB64', new.worker_completion_signature_b64,
           'signatureBasisSha256', new.worker_completion_signature_basis_sha256,
           'authorityRequestSha256', new.worker_completion_authority_request_sha256
         )
     ) then
    raise exception 'signed reviewer and worker completion attestations required for finalization'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_governed_worker_review_attestation()
  from public, anon, authenticated, service_role, projectos_worker_ingest,
       projectos_reviewer_ingest;

-- Remove every candidate service-role path that can claim, write a job, or
-- report a result. Only the externally authenticated wrappers are executable.
revoke all on function public.consume_compute_worker_nonce(uuid,text,text)
  from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.consume_compute_worker_nonce(uuid,text,text,text)
  from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.claim_governed_worker_dispatch(uuid,text)
  from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.claim_governed_worker_dispatch(uuid,text,text)
  from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.record_governed_worker_job_envelope(
  uuid,uuid,uuid,text,text,jsonb,text
) from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.finish_governed_worker_dispatch(
  uuid,uuid,uuid,text,text,integer,text,text,jsonb
) from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.finish_governed_worker_dispatch(
  uuid,uuid,uuid,text,text,text,integer,text,text,jsonb
) from public, anon, authenticated, service_role, projectos_worker_ingest;

revoke all on function public.claim_governed_worker_dispatch_authorized(
  uuid,text,text,uuid,text,text,text
) from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.record_governed_worker_job_envelope_authorized(
  uuid,uuid,uuid,text,text,text,jsonb,text
) from public, anon, authenticated, service_role, projectos_worker_ingest;
revoke all on function public.finish_governed_worker_dispatch_authorized(
  uuid,uuid,uuid,text,text,text,integer,text,text,jsonb,uuid,text,text,text
) from public, anon, authenticated, service_role, projectos_worker_ingest;

grant execute on function public.claim_governed_worker_dispatch_authorized(
  uuid,text,text,uuid,text,text,text
) to projectos_worker_ingest;
grant execute on function public.record_governed_worker_job_envelope_authorized(
  uuid,uuid,uuid,text,text,text,jsonb,text
) to projectos_worker_ingest;
grant execute on function public.finish_governed_worker_dispatch_authorized(
  uuid,uuid,uuid,text,text,text,integer,text,text,jsonb,uuid,text,text,text
) to projectos_worker_ingest;
