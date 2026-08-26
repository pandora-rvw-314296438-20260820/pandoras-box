-- Governed owner-command -> Worker-01 exact-source verification lane.
-- The lane is deliberately limited to canonical, exact-SHA, sandboxed verification.
-- Approval, claim, and durable enqueue occur in one database transaction.

alter table private.execution_plans
  drop constraint if exists execution_plans_status_check;
alter table private.execution_plans
  add constraint execution_plans_status_check check (
    status in (
      'pending_approval', 'approved', 'executing', 'completed', 'failed',
      'expired', 'denied'
    )
  );

create table if not exists private.owner_command_bindings (
  organization_id uuid not null references public.organizations(id) on delete restrict,
  idempotency_key text not null check (idempotency_key ~ '^[0-9a-f]{64}$'),
  request_fingerprint text not null check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  operation text not null check (operation = 'verify_exact_source'),
  intake_id uuid unique references public.projectos_intake_requests(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, idempotency_key)
);

create table if not exists private.execution_dispatch_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  plan_id uuid not null references private.execution_plans(id) on delete restrict,
  status text not null default 'staged' check (
    status in (
      'staged', 'queued', 'claimed', 'envelope_ready', 'result_reported',
      'finalizing', 'completed', 'ambiguous', 'failed'
    )
  ),
  worker_identity text,
  worker_key_fingerprint text check (
    worker_key_fingerprint is null or worker_key_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  builder_vendor text,
  runtime_proof_id uuid references public.projectos_agent_runtime_proofs(id) on delete restrict,
  lease_expires_at timestamptz,
  job_digest text check (job_digest is null or job_digest ~ '^[0-9a-f]{64}$'),
  job_payload jsonb check (job_payload is null or jsonb_typeof(job_payload) = 'object'),
  job_signature text,
  evidence_sha256 text check (
    evidence_sha256 is null or evidence_sha256 ~ '^[0-9a-f]{64}$'
  ),
  result_summary jsonb check (
    result_summary is null or jsonb_typeof(result_summary) = 'object'
  ),
  worker_reported_at timestamptz,
  verifier_runtime_proof_id uuid references public.projectos_agent_runtime_proofs(id) on delete restrict,
  verification_evidence_id uuid references public.projectos_evidence(id) on delete restrict,
  verification_summary jsonb check (
    verification_summary is null or jsonb_typeof(verification_summary) = 'object'
  ),
  verified_outcome text check (
    verified_outcome is null or verified_outcome in ('completed', 'failed')
  ),
  verified_at timestamptz,
  error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (plan_id),
  unique (organization_id, id)
);

create index if not exists execution_dispatch_outbox_queue_idx
  on private.execution_dispatch_outbox (organization_id, status, created_at);
create index if not exists execution_dispatch_outbox_worker_idx
  on private.execution_dispatch_outbox (
    organization_id, worker_identity, status, lease_expires_at
  );

create table if not exists private.compute_worker_identities (
  organization_id uuid not null references public.organizations(id) on delete restrict,
  worker_id text not null check (worker_id ~ '^[a-z0-9][a-z0-9._:-]{2,127}$'),
  public_key_b64 text not null check (
    public_key_b64 ~ '^[A-Za-z0-9+/]{43}=$'
    and octet_length(decode(public_key_b64, 'base64')) = 32
  ),
  key_fingerprint text not null check (key_fingerprint ~ '^[0-9a-f]{64}$'),
  status text not null default 'active' check (status in ('active', 'draining', 'disabled')),
  allowed_repositories text[] not null check (
    cardinality(allowed_repositories) between 1 and 20
  ),
  allowed_job_classes text[] not null check (
    cardinality(allowed_job_classes) between 1 and 20
  ),
  registered_by_plan_id uuid not null references private.execution_plans(id) on delete restrict,
  registration_operation text not null check (
    registration_operation in ('enroll', 'rotate')
  ),
  registered_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz,
  primary key (organization_id, worker_id),
  unique (organization_id, key_fingerprint)
);

create table if not exists private.compute_worker_nonces (
  organization_id uuid not null,
  worker_id text not null,
  nonce_sha256 text not null check (nonce_sha256 ~ '^[0-9a-f]{64}$'),
  observed_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '15 minutes'),
  primary key (organization_id, worker_id, nonce_sha256),
  foreign key (organization_id, worker_id)
    references private.compute_worker_identities(organization_id, worker_id)
    on delete cascade
);

create index if not exists compute_worker_nonces_expiry_idx
  on private.compute_worker_nonces (expires_at, organization_id, worker_id);
create index if not exists compute_worker_nonces_worker_active_idx
  on private.compute_worker_nonces (organization_id, worker_id, expires_at);

alter table private.execution_dispatch_outbox enable row level security;
alter table private.owner_command_bindings enable row level security;
alter table private.compute_worker_identities enable row level security;
alter table private.compute_worker_nonces enable row level security;

revoke all on table private.execution_dispatch_outbox
  from public, anon, authenticated;
revoke all on table private.owner_command_bindings
  from public, anon, authenticated;
revoke all on table private.compute_worker_identities
  from public, anon, authenticated;
revoke all on table private.compute_worker_nonces
  from public, anon, authenticated, service_role;
revoke all on table private.execution_dispatch_outbox from service_role;
revoke all on table private.owner_command_bindings from service_role;
revoke all on table private.compute_worker_identities from service_role;

create or replace function private.projectos_worker_plan_payload_hash(p_args jsonb)
returns text
language sql
immutable
strict
security definer
set search_path = ''
as $$
  select encode(
    extensions.digest(
      convert_to(
        concat(
          '{"tool":"projectos.worker.verify","args":{"exactSha":"',
          p_args ->> 'exactSha',
          '","jobClass":"',
          p_args ->> 'jobClass',
          '","maxRuntimeSeconds":',
          p_args ->> 'maxRuntimeSeconds',
          ',"productionMutationAllowed":false,"repository":"',
          p_args ->> 'repository',
          '","schemaVersion":1}}'
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$$;

create or replace function private.projectos_worker_job_digest(p_payload jsonb)
returns text
language sql
immutable
strict
security definer
set search_path = ''
as $$
  select encode(
    extensions.digest(
      convert_to(
        concat_ws(
          '|',
          'projectos-worker-job-v1',
          p_payload ->> 'schemaVersion',
          p_payload ->> 'audience',
          p_payload ->> 'organizationId',
          p_payload ->> 'dispatchId',
          p_payload ->> 'planId',
          p_payload ->> 'repository',
          p_payload ->> 'exactSha',
          p_payload ->> 'jobClass',
          p_payload ->> 'maxRuntimeSeconds',
          p_payload ->> 'issuedAt',
          p_payload ->> 'expiresAt',
          p_payload ->> 'runnerPolicyHash',
          p_payload ->> 'runnerImageDigest',
          p_payload ->> 'acquisitionImageDigest',
          p_payload ->> 'networkPolicy',
          p_payload ->> 'isolation',
          p_payload ->> 'productionMutationAllowed'
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$$;

create or replace function private.projectos_worker_identity_plan_payload_hash(
  p_args jsonb
)
returns text
language sql
immutable
strict
security definer
set search_path = ''
as $$
  select encode(
    extensions.digest(
      convert_to(
        concat(
          '{"tool":"projectos.worker.identity.register","args":{"allowedJobClasses":',
          replace((p_args -> 'allowedJobClasses')::text, ', ', ','),
          ',"allowedRepositories":',
          replace((p_args -> 'allowedRepositories')::text, ', ', ','),
          ',"keyFingerprint":"',
          p_args ->> 'keyFingerprint',
          '","operation":"',
          p_args ->> 'operation',
          '","schemaVersion":1,"workerId":"',
          p_args ->> 'workerId',
          '"}}'
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$$;

create or replace function private.projectos_worker_plan_is_valid(
  p_tool text,
  p_risk text,
  p_args jsonb,
  p_payload_hash text
)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select case
    when jsonb_typeof(p_args) is distinct from 'object' then false
    else coalesce(
      p_tool = 'projectos.worker.verify'
      and p_risk = 'write'
      and p_args ?& array[
        'schemaVersion', 'repository', 'exactSha', 'jobClass',
        'maxRuntimeSeconds', 'productionMutationAllowed'
      ]::text[]
      and (select count(*) from jsonb_object_keys(p_args)) = 6
      and p_args -> 'schemaVersion' is not distinct from '1'::jsonb
      and p_args -> 'productionMutationAllowed' is not distinct from 'false'::jsonb
      and p_args ->> 'repository' = 'pandora-rvw-314296438-20260820/pandoras-box'
      and p_args ->> 'exactSha' ~ '^[0-9a-f]{40}$'
      and p_args ->> 'jobClass' in ('node_regression', 'supabase_migration_replay')
      and case
        when p_args ->> 'maxRuntimeSeconds' ~ '^[0-9]{2,4}$'
          then (p_args ->> 'maxRuntimeSeconds')::integer between 30 and 1800
        else false
      end
      and p_payload_hash = private.projectos_worker_plan_payload_hash(p_args),
      false
    )
  end;
$$;

create or replace function private.projectos_worker_job_payload_is_valid(
  p_payload jsonb
)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select case
    when jsonb_typeof(p_payload) is distinct from 'object' then false
    else coalesce(
      p_payload ?& array[
        'schemaVersion', 'audience', 'organizationId', 'dispatchId', 'planId',
        'repository', 'exactSha', 'jobClass', 'maxRuntimeSeconds', 'issuedAt',
        'expiresAt', 'runnerPolicyHash', 'runnerImageDigest',
        'acquisitionImageDigest', 'networkPolicy', 'isolation',
        'productionMutationAllowed'
      ]::text[]
      and (select count(*) from jsonb_object_keys(p_payload)) = 17
      and p_payload -> 'schemaVersion' is not distinct from '1'::jsonb
      and p_payload ->> 'audience' ~ '^pandora-worker:[a-z0-9][a-z0-9._:-]{2,127}$'
      and p_payload ->> 'organizationId' ~
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and p_payload ->> 'dispatchId' ~
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and p_payload ->> 'planId' ~
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and p_payload ->> 'repository' = 'pandora-rvw-314296438-20260820/pandoras-box'
      and p_payload ->> 'exactSha' ~ '^[0-9a-f]{40}$'
      and p_payload ->> 'jobClass' in ('node_regression', 'supabase_migration_replay')
      and case
        when p_payload ->> 'maxRuntimeSeconds' ~ '^[0-9]{2,4}$'
          then (p_payload ->> 'maxRuntimeSeconds')::integer between 30 and 1800
        else false
      end
      and octet_length(p_payload ->> 'issuedAt') between 20 and 64
      and octet_length(p_payload ->> 'expiresAt') between 20 and 64
      and p_payload ->> 'runnerPolicyHash' ~ '^[0-9a-f]{64}$'
      and p_payload ->> 'runnerImageDigest' ~ '^sha256:[0-9a-f]{64}$'
      and p_payload ->> 'acquisitionImageDigest' ~ '^sha256:[0-9a-f]{64}$'
      and p_payload ->> 'networkPolicy' = 'none'
      and p_payload ->> 'isolation' = 'hyperv_container'
      and p_payload -> 'productionMutationAllowed' is not distinct from 'false'::jsonb,
      false
    )
  end;
$$;

create or replace function private.projectos_worker_result_summary_is_valid(
  p_result jsonb
)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select case
    when jsonb_typeof(p_result) is distinct from 'object' then false
    else coalesce(
      p_result ?& array[
        'schemaVersion', 'organizationId', 'dispatchId', 'planId', 'workerId',
        'jobDigest', 'repository', 'exactSha', 'jobClass', 'outcome', 'exitCode',
        'isolation', 'networkPolicy', 'productionMutationAllowed',
        'runnerPolicyHash', 'runnerImageDigest', 'acquisitionImageDigest',
        'sourceTreeSha', 'testsDiscovered', 'startedAt', 'completedAt',
        'stdoutSha256', 'stderrSha256'
      ]::text[]
      and (select count(*) from jsonb_object_keys(p_result)) = 23
      and p_result -> 'schemaVersion' is not distinct from '1'::jsonb
      and p_result ->> 'organizationId' ~
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and p_result ->> 'dispatchId' ~
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and p_result ->> 'planId' ~
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and p_result ->> 'workerId' ~ '^[a-z0-9][a-z0-9._:-]{2,127}$'
      and p_result ->> 'jobDigest' ~ '^[0-9a-f]{64}$'
      and p_result ->> 'repository' = 'pandora-rvw-314296438-20260820/pandoras-box'
      and p_result ->> 'exactSha' ~ '^[0-9a-f]{40}$'
      and p_result ->> 'jobClass' in ('node_regression', 'supabase_migration_replay')
      and p_result ->> 'outcome' in ('completed', 'failed')
      and case
        when p_result ->> 'exitCode' ~ '^[0-9]{1,3}$'
          then (p_result ->> 'exitCode')::integer between 0 and 255
        else false
      end
      and p_result ->> 'isolation' = 'hyperv_container'
      and p_result ->> 'networkPolicy' = 'none'
      and p_result -> 'productionMutationAllowed' is not distinct from 'false'::jsonb
      and p_result ->> 'runnerPolicyHash' ~ '^[0-9a-f]{64}$'
      and p_result ->> 'runnerImageDigest' ~ '^sha256:[0-9a-f]{64}$'
      and p_result ->> 'acquisitionImageDigest' ~ '^sha256:[0-9a-f]{64}$'
      and p_result ->> 'sourceTreeSha' ~ '^[0-9a-f]{40}$'
      and case
        when p_result ->> 'testsDiscovered' ~ '^[0-9]{1,9}$'
          then (p_result ->> 'testsDiscovered')::integer >= 0
        else false
      end
      and octet_length(p_result ->> 'startedAt') between 20 and 64
      and octet_length(p_result ->> 'completedAt') between 20 and 64
      and p_result ->> 'stdoutSha256' ~ '^[0-9a-f]{64}$'
      and p_result ->> 'stderrSha256' ~ '^[0-9a-f]{64}$',
      false
    )
  end;
$$;

create or replace function private.projectos_worker_evidence_hash(p_result jsonb)
returns text
language sql
immutable
strict
security definer
set search_path = ''
as $$
  select encode(
    extensions.digest(
      convert_to(
        concat_ws(
          '|',
          'projectos-worker-evidence-v1',
          p_result ->> 'schemaVersion',
          p_result ->> 'organizationId',
          p_result ->> 'dispatchId',
          p_result ->> 'planId',
          p_result ->> 'workerId',
          p_result ->> 'jobDigest',
          p_result ->> 'repository',
          p_result ->> 'exactSha',
          p_result ->> 'jobClass',
          p_result ->> 'outcome',
          p_result ->> 'exitCode',
          p_result ->> 'isolation',
          p_result ->> 'networkPolicy',
          p_result ->> 'productionMutationAllowed',
          p_result ->> 'runnerPolicyHash',
          p_result ->> 'runnerImageDigest',
          p_result ->> 'acquisitionImageDigest',
          p_result ->> 'sourceTreeSha',
          p_result ->> 'testsDiscovered',
          p_result ->> 'startedAt',
          p_result ->> 'completedAt',
          p_result ->> 'stdoutSha256',
          p_result ->> 'stderrSha256'
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$$;

revoke all on function private.projectos_worker_plan_payload_hash(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.projectos_worker_job_digest(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.projectos_worker_identity_plan_payload_hash(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.projectos_worker_plan_is_valid(text, text, jsonb, text)
  from public, anon, authenticated, service_role;
revoke all on function private.projectos_worker_job_payload_is_valid(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.projectos_worker_result_summary_is_valid(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.projectos_worker_evidence_hash(jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.projectos_accept_governed_worker_intake(
  p_organization_id uuid,
  p_requester_id uuid,
  p_request_text text,
  p_project_key text,
  p_idempotency_key text,
  p_request_fingerprint text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  binding private.owner_command_bindings%rowtype;
  intake public.projectos_intake_requests%rowtype;
  project public.projectos_projects%rowtype;
  accepted jsonb;
begin
  perform private.assert_control_service_role();
  if p_idempotency_key !~ '^[0-9a-f]{64}$'
     or p_request_fingerprint !~ '^[0-9a-f]{64}$'
     or nullif(trim(coalesce(p_request_text, '')), '') is null
     or char_length(p_request_text) > 4000 then
    raise exception 'invalid governed owner intake' using errcode = '22023';
  end if;

  insert into private.owner_command_bindings (
    organization_id,
    idempotency_key,
    request_fingerprint,
    operation
  ) values (
    p_organization_id,
    p_idempotency_key,
    p_request_fingerprint,
    'verify_exact_source'
  )
  on conflict (organization_id, idempotency_key) do nothing;

  select * into binding
  from private.owner_command_bindings
  where organization_id = p_organization_id
    and idempotency_key = p_idempotency_key
  for update;
  if binding.request_fingerprint <> p_request_fingerprint
     or binding.operation <> 'verify_exact_source' then
    raise exception 'owner_idempotency_conflict' using errcode = '23505';
  end if;

  if binding.intake_id is not null then
    select * into intake
    from public.projectos_intake_requests
    where organization_id = p_organization_id and id = binding.intake_id;
    if intake.id is null then
      raise exception 'bound owner intake missing' using errcode = '55000';
    end if;
    select * into project
    from public.projectos_projects
    where organization_id = p_organization_id and id = intake.project_id;
    return jsonb_build_object(
      'intake', to_jsonb(intake),
      'project', to_jsonb(project),
      'idempotentReplay', true
    );
  end if;

  accepted := public.projectos_accept_intake(
    p_organization_id,
    p_requester_id,
    p_request_text,
    p_project_key,
    null,
    'pandora-rvw-314296438-20260820/pandoras-box',
    'work',
    'api',
    p_idempotency_key
  );
  if coalesce(accepted #>> '{intake,id}', '') !~
    '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'governed owner intake result invalid' using errcode = '55000';
  end if;

  update private.owner_command_bindings
  set intake_id = (accepted #>> '{intake,id}')::uuid,
      updated_at = now()
  where organization_id = p_organization_id
    and idempotency_key = p_idempotency_key;
  return accepted || jsonb_build_object('idempotentReplay', false);
end;
$$;

create or replace function public.projectos_create_or_get_worker_plan(
  p_organization_id uuid,
  p_intake_id uuid,
  p_args jsonb,
  p_payload_hash text,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  binding private.owner_command_bindings%rowtype;
  plan private.execution_plans%rowtype;
  created jsonb;
begin
  perform private.assert_control_service_role();
  select * into binding
  from private.owner_command_bindings
  where organization_id = p_organization_id and intake_id = p_intake_id
  for update;
  if binding.intake_id is null then
    raise exception 'governed owner intake binding missing' using errcode = '55000';
  end if;
  if private.projectos_worker_plan_is_valid(
    'projectos.worker.verify', 'write', p_args, p_payload_hash
  ) is distinct from true then
    raise exception 'worker plan identity invalid' using errcode = '22023';
  end if;

  select * into plan
  from private.execution_plans
  where organization_id = p_organization_id and intake_id = p_intake_id
  for update;
  if plan.id is not null then
    if private.projectos_worker_plan_is_valid(
      plan.tool, plan.risk, plan.args, plan.payload_hash
    ) is distinct from true
       or plan.args <> p_args
       or plan.payload_hash <> p_payload_hash then
      raise exception 'bound worker plan differs' using errcode = '55000';
    end if;
    return jsonb_build_object(
      'planId', plan.id,
      'requestId', plan.request_id,
      'intakeId', plan.intake_id,
      'tool', plan.tool,
      'risk', plan.risk,
      'args', plan.args,
      'payloadHash', plan.payload_hash,
      'status', case
        when plan.status in ('pending_approval', 'approved') and plan.expires_at <= now()
          then 'expired'
        else plan.status
      end,
      'expiresAt', plan.expires_at,
      'idempotentReplay', true
    );
  end if;

  created := public.create_execution_plan(
    p_organization_id,
    p_intake_id,
    p_intake_id,
    'projectos.worker.verify',
    'write',
    p_args,
    p_payload_hash,
    p_expires_at
  );
  return created || jsonb_build_object(
    'args', p_args,
    'idempotentReplay', false
  );
end;
$$;

create or replace function public.register_compute_worker_identity(
  p_organization_id uuid,
  p_registration_plan_id uuid,
  p_worker_id text,
  p_public_key_b64 text,
  p_allowed_repositories text[],
  p_allowed_job_classes text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  worker private.compute_worker_identities%rowtype;
  existing_worker private.compute_worker_identities%rowtype;
  registration_plan private.execution_plans%rowtype;
  fingerprint text;
  operation text;
  normalized_repositories text[];
  normalized_job_classes text[];
  expected_args jsonb;
  transition jsonb;
begin
  perform private.assert_control_service_role();
  p_worker_id := lower(trim(coalesce(p_worker_id, '')));

  if p_worker_id !~ '^[a-z0-9][a-z0-9._:-]{2,127}$'
     or coalesce(p_public_key_b64, '') !~ '^[A-Za-z0-9+/]{43}=$' then
    raise exception 'invalid worker identity' using errcode = '22023';
  end if;
  begin
    if octet_length(decode(p_public_key_b64, 'base64')) <> 32 then
      raise exception 'invalid worker key length' using errcode = '22023';
    end if;
  exception when others then
    raise exception 'invalid worker public key' using errcode = '22023';
  end;
  fingerprint := encode(
    extensions.digest(decode(p_public_key_b64, 'base64'), 'sha256'),
    'hex'
  );
  select coalesce(array_agg(distinct repository order by repository), '{}'::text[])
  into normalized_repositories
  from unnest(coalesce(p_allowed_repositories, '{}'::text[])) repository;
  select coalesce(array_agg(distinct job_class order by job_class), '{}'::text[])
  into normalized_job_classes
  from unnest(coalesce(p_allowed_job_classes, '{}'::text[])) job_class;

  if normalized_repositories <> coalesce(p_allowed_repositories, '{}'::text[])
     or cardinality(normalized_repositories) not between 1 and 20
     or exists (
       select 1 from unnest(normalized_repositories) repository
       where repository <> 'pandora-rvw-314296438-20260820/pandoras-box'
     ) then
    raise exception 'invalid repository scopes' using errcode = '22023';
  end if;
  if normalized_job_classes <> coalesce(p_allowed_job_classes, '{}'::text[])
     or cardinality(normalized_job_classes) not between 1 and 20
     or exists (
       select 1 from unnest(normalized_job_classes) job_class
       where job_class not in ('node_regression', 'supabase_migration_replay')
     ) then
    raise exception 'invalid job classes' using errcode = '22023';
  end if;

  -- A missing registry row cannot be protected by SELECT ... FOR UPDATE.
  -- Serialize the organization+worker enrollment namespace before checking it
  -- so two approved first-enrollment plans cannot race into an implicit key
  -- rotation through the ON CONFLICT path. The xact lock releases on commit or
  -- rollback and only hash collisions broaden serialization.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'projectos:compute-worker:' || p_organization_id::text || ':' || p_worker_id,
      0
    )
  );

  select * into existing_worker
  from private.compute_worker_identities
  where organization_id = p_organization_id and worker_id = p_worker_id
  for update;

  operation := case when existing_worker.worker_id is null then 'enroll' else 'rotate' end;
  if existing_worker.worker_id is not null then
    if existing_worker.public_key_b64 = p_public_key_b64
       and existing_worker.allowed_repositories = normalized_repositories
       and existing_worker.allowed_job_classes = normalized_job_classes then
      operation := existing_worker.registration_operation;
    elsif existing_worker.status <> 'disabled' then
      raise exception 'active worker identity must be disabled before rotation'
        using errcode = '55000';
    elsif exists (
      select 1
      from private.execution_dispatch_outbox dispatch
      where dispatch.organization_id = p_organization_id
        and dispatch.worker_identity = p_worker_id
        and dispatch.status in (
          'claimed', 'envelope_ready', 'result_reported', 'finalizing', 'ambiguous'
        )
    ) then
      raise exception 'worker identity has unresolved dispatches'
        using errcode = '55000';
    end if;
  end if;

  expected_args := jsonb_build_object(
    'schemaVersion', 1,
    'operation', operation,
    'workerId', p_worker_id,
    'keyFingerprint', fingerprint,
    'allowedRepositories', to_jsonb(normalized_repositories),
    'allowedJobClasses', to_jsonb(normalized_job_classes)
  );

  select * into registration_plan
  from private.execution_plans
  where organization_id = p_organization_id and id = p_registration_plan_id
  for update;
  if registration_plan.id is null
     or registration_plan.tool <> 'projectos.worker.identity.register'
     or registration_plan.risk <> 'write'
     or registration_plan.args <> expected_args
     or registration_plan.payload_hash <>
       private.projectos_worker_identity_plan_payload_hash(expected_args)
     or registration_plan.approved_at is null
     or nullif(trim(coalesce(registration_plan.approved_by, '')), '') is null
     or registration_plan.approved_by = 'system:auto-read' then
    raise exception 'worker identity registration plan mismatch'
      using errcode = '55000';
  end if;

  if registration_plan.status = 'completed' then
    if existing_worker.worker_id is not null
       and existing_worker.registered_by_plan_id = registration_plan.id
       and existing_worker.public_key_b64 = p_public_key_b64
       and existing_worker.allowed_repositories = normalized_repositories
       and existing_worker.allowed_job_classes = normalized_job_classes then
      return jsonb_build_object(
        'organizationId', existing_worker.organization_id,
        'workerId', existing_worker.worker_id,
        'keyFingerprint', existing_worker.key_fingerprint,
        'status', existing_worker.status,
        'allowedRepositories', to_jsonb(existing_worker.allowed_repositories),
        'allowedJobClasses', to_jsonb(existing_worker.allowed_job_classes),
        'registrationPlanId', registration_plan.id,
        'idempotentReplay', true
      );
    end if;
    raise exception 'completed worker identity plan does not match registry'
      using errcode = '55000';
  end if;
  if registration_plan.status <> 'approved'
     or registration_plan.expires_at <= now() then
    raise exception 'worker identity registration plan is not executable'
      using errcode = '55000';
  end if;

  transition := public.claim_execution_plan(
    p_organization_id,
    registration_plan.id
  );
  if transition ->> 'status' is distinct from 'executing' then
    raise exception 'worker identity registration claim failed'
      using errcode = '55000';
  end if;

  insert into private.compute_worker_identities (
    organization_id,
    worker_id,
    public_key_b64,
    key_fingerprint,
    status,
    allowed_repositories,
    allowed_job_classes,
    registered_by_plan_id,
    registration_operation
  ) values (
    p_organization_id,
    p_worker_id,
    p_public_key_b64,
    fingerprint,
    'active',
    normalized_repositories,
    normalized_job_classes,
    registration_plan.id,
    operation
  )
  on conflict (organization_id, worker_id) do update set
    public_key_b64 = excluded.public_key_b64,
    key_fingerprint = excluded.key_fingerprint,
    status = 'active',
    allowed_repositories = excluded.allowed_repositories,
    allowed_job_classes = excluded.allowed_job_classes,
    registered_by_plan_id = excluded.registered_by_plan_id,
    registration_operation = excluded.registration_operation,
    registered_at = now(),
    updated_at = now()
  returning * into worker;

  perform private.append_execution_audit(
    p_organization_id,
    registration_plan.id,
    registration_plan.request_id,
    case operation
      when 'enroll' then 'worker_identity_enrolled'
      else 'worker_identity_rotated'
    end,
    'executing',
    registration_plan.tool,
    registration_plan.risk,
    registration_plan.payload_hash,
    jsonb_build_object(
      'workerId', worker.worker_id,
      'keyFingerprint', worker.key_fingerprint,
      'allowedRepositories', to_jsonb(worker.allowed_repositories),
      'allowedJobClasses', to_jsonb(worker.allowed_job_classes)
    )
  );

  perform public.finish_execution_plan(
    p_organization_id,
    registration_plan.id,
    'completed',
    0,
    null,
    jsonb_build_object(
      'workerId', worker.worker_id,
      'keyFingerprint', worker.key_fingerprint,
      'operation', operation
    )
  );

  return jsonb_build_object(
    'organizationId', worker.organization_id,
    'workerId', worker.worker_id,
    'keyFingerprint', worker.key_fingerprint,
    'status', worker.status,
    'allowedRepositories', to_jsonb(worker.allowed_repositories),
    'allowedJobClasses', to_jsonb(worker.allowed_job_classes),
    'registrationPlanId', registration_plan.id,
    'idempotentReplay', false
  );
end;
$$;

create or replace function public.resolve_compute_worker_identity(
  p_organization_id uuid,
  p_worker_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  worker private.compute_worker_identities%rowtype;
begin
  perform private.assert_control_service_role();
  select * into worker
  from private.compute_worker_identities
  where organization_id = p_organization_id
    and worker_id = lower(trim(coalesce(p_worker_id, '')))
    and status in ('active', 'draining');

  if worker.worker_id is null then return null; end if;
  return jsonb_build_object(
    'organizationId', worker.organization_id,
    'workerId', worker.worker_id,
    'publicKeyB64', worker.public_key_b64,
    'keyFingerprint', worker.key_fingerprint,
    'allowedRepositories', to_jsonb(worker.allowed_repositories),
    'allowedJobClasses', to_jsonb(worker.allowed_job_classes)
  );
end;
$$;

create or replace function public.consume_compute_worker_nonce(
  p_organization_id uuid,
  p_worker_id text,
  p_nonce text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  accepted_worker text;
  nonce_hash text;
  active_nonce_count integer;
begin
  perform private.assert_control_service_role();
  p_worker_id := lower(trim(coalesce(p_worker_id, '')));
  if p_nonce is null or p_nonce !~ '^[A-Za-z0-9._:-]{16,128}$' then
    raise exception 'invalid nonce' using errcode = '22023';
  end if;
  perform 1
  from private.compute_worker_identities
  where organization_id = p_organization_id
    and worker_id = p_worker_id
    and status in ('active', 'draining')
  for update;
  if not found then
    raise exception 'worker not enrolled' using errcode = '42501';
  end if;

  with expired as (
    select organization_id, worker_id, nonce_sha256
    from private.compute_worker_nonces
    where expires_at <= now()
    order by expires_at
    for update skip locked
    limit 128
  )
  delete from private.compute_worker_nonces nonce
  using expired
  where nonce.organization_id = expired.organization_id
    and nonce.worker_id = expired.worker_id
    and nonce.nonce_sha256 = expired.nonce_sha256;

  select count(*)::integer into active_nonce_count
  from private.compute_worker_nonces
  where organization_id = p_organization_id
    and worker_id = p_worker_id
    and expires_at > now();
  if active_nonce_count >= 2048 then
    raise exception 'worker nonce retention cap reached' using errcode = '54000';
  end if;

  nonce_hash := encode(
    extensions.digest(convert_to(p_nonce, 'UTF8'), 'sha256'),
    'hex'
  );

  insert into private.compute_worker_nonces (
    organization_id, worker_id, nonce_sha256, expires_at
  )
  values (
    p_organization_id, p_worker_id, nonce_hash, now() + interval '15 minutes'
  )
  on conflict do nothing
  returning worker_id into accepted_worker;

  if accepted_worker is null then
    raise exception 'nonce already used' using errcode = '23505';
  end if;
  update private.compute_worker_identities
  set last_seen_at = now(), updated_at = now()
  where organization_id = p_organization_id and worker_id = p_worker_id;
  return jsonb_build_object('accepted', true);
end;
$$;

create or replace function private.guard_governed_worker_plan_claim()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.tool = 'projectos.worker.verify'
     and new.status = 'executing'
     and old.status is distinct from 'executing'
     and not exists (
       select 1
       from private.execution_dispatch_outbox dispatch
       where dispatch.organization_id = new.organization_id
         and dispatch.plan_id = new.id
         and dispatch.status = 'staged'
     ) then
    raise exception 'worker plan requires an atomically staged dispatch'
      using errcode = '55000';
  end if;
  if new.tool = 'projectos.worker.verify'
     and new.status in ('completed', 'failed')
     and old.status = 'executing'
     and not exists (
       select 1
       from private.execution_dispatch_outbox dispatch
       where dispatch.organization_id = new.organization_id
         and dispatch.plan_id = new.id
         and dispatch.status = 'finalizing'
         and dispatch.verified_outcome = new.status
         and dispatch.verified_at is not null
         and (
           (
             dispatch.verifier_runtime_proof_id is not null
             and dispatch.verification_evidence_id is not null
           )
           or (
             dispatch.job_digest is null
             and dispatch.verification_summary ->> 'reason' =
               'capability_rollback_before_delivery'
           )
         )
     ) then
    raise exception 'worker plan requires reviewer-gated finalization'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_governed_worker_plan_claim()
  from public, anon, authenticated, service_role;

drop trigger if exists guard_governed_worker_plan_claim
  on private.execution_plans;
create trigger guard_governed_worker_plan_claim
before update of status on private.execution_plans
for each row execute function private.guard_governed_worker_plan_claim();

create or replace function public.get_governed_worker_execution(
  p_organization_id uuid,
  p_plan_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  plan private.execution_plans%rowtype;
  dispatch private.execution_dispatch_outbox%rowtype;
begin
  perform private.assert_control_service_role();

  select * into plan
  from private.execution_plans
  where organization_id = p_organization_id
    and id = p_plan_id
    and tool = 'projectos.worker.verify'
  for update;
  if plan.id is null then return null; end if;

  select * into dispatch
  from private.execution_dispatch_outbox
  where organization_id = p_organization_id and plan_id = plan.id
  for update;

  if dispatch.id is not null
     and dispatch.status in ('claimed', 'envelope_ready')
     and dispatch.lease_expires_at <= now() then
    if dispatch.runtime_proof_id is not null then
      update public.projectos_agent_runtime_proofs
      set active_leases = greatest(active_leases - 1, 0),
          updated_at = now()
      where id = dispatch.runtime_proof_id;
    end if;

    if dispatch.status = 'claimed' then
      update private.execution_dispatch_outbox
      set status = 'queued',
          worker_identity = null,
          worker_key_fingerprint = null,
          builder_vendor = null,
          runtime_proof_id = null,
          lease_expires_at = null,
          error_code = 'UNSIGNED_LEASE_EXPIRED_REQUEUED',
          completed_at = null,
          updated_at = now()
      where id = dispatch.id
      returning * into dispatch;
    else
      update private.execution_dispatch_outbox
      set status = 'ambiguous',
          error_code = 'LEASE_EXPIRED_OUTCOME_UNKNOWN',
          completed_at = now(),
          updated_at = now()
      where id = dispatch.id
      returning * into dispatch;
    end if;

    perform private.append_execution_audit(
      p_organization_id,
      plan.id,
      plan.request_id,
      case dispatch.status
        when 'queued' then 'worker_dispatch_unsigned_lease_requeued'
        else 'worker_dispatch_ambiguous'
      end,
      plan.status,
      plan.tool,
      plan.risk,
      plan.payload_hash,
      jsonb_build_object(
        'dispatchId', dispatch.id,
        'reason', dispatch.error_code,
        'leaseExpiresAt', dispatch.lease_expires_at
      )
    );
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'planId', plan.id,
    'intakeId', plan.intake_id,
    'tool', plan.tool,
    'risk', plan.risk,
    'args', plan.args,
    'payloadHash', plan.payload_hash,
    'planStatus', case
      when plan.status in ('pending_approval', 'approved') and plan.expires_at <= now()
        then 'expired'
      else plan.status
    end,
    'dispatchId', dispatch.id,
    'dispatchStatus', dispatch.status,
    'workerIdentity', dispatch.worker_identity,
    'leaseExpiresAt', dispatch.lease_expires_at,
    'jobDigest', dispatch.job_digest,
    'evidenceSha256', dispatch.evidence_sha256,
    'resultSummary', dispatch.result_summary,
    'verifierRuntimeProofId', dispatch.verifier_runtime_proof_id,
    'verificationEvidenceId', dispatch.verification_evidence_id,
    'verifiedOutcome', dispatch.verified_outcome,
    'verifiedAt', dispatch.verified_at,
    'errorCode', dispatch.error_code,
    'completedAt', dispatch.completed_at
  ));
end;
$$;

create or replace function public.decide_governed_worker_execution_plan(
  p_organization_id uuid,
  p_plan_id uuid,
  p_decision text,
  p_decided_by text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  plan private.execution_plans%rowtype;
  dispatch private.execution_dispatch_outbox%rowtype;
  intake public.projectos_intake_requests%rowtype;
  transition jsonb;
begin
  perform private.assert_control_service_role();
  p_decision := lower(trim(coalesce(p_decision, '')));
  if p_decision not in ('approve', 'deny') then
    raise exception 'invalid worker plan decision' using errcode = '22023';
  end if;

  select * into plan
  from private.execution_plans
  where organization_id = p_organization_id and id = p_plan_id
  for update;

  -- A null result tells the owner API to use its ordinary approval lane.
  if plan.id is null or plan.tool <> 'projectos.worker.verify' then
    return null;
  end if;
  if private.projectos_worker_plan_is_valid(
    plan.tool, plan.risk, plan.args, plan.payload_hash
  ) is distinct from true then
    raise exception 'worker plan identity mismatch' using errcode = '55000';
  end if;

  select * into intake
  from public.projectos_intake_requests
  where organization_id = p_organization_id and id = plan.intake_id
  for update;
  if intake.id is null then
    raise exception 'worker plan intake missing' using errcode = '55000';
  end if;

  if plan.status in ('pending_approval', 'approved') and plan.expires_at <= now() then
    update private.execution_plans
    set status = 'expired', updated_at = now()
    where id = plan.id
    returning * into plan;
    perform private.append_execution_audit(
      p_organization_id, plan.id, plan.request_id, 'plan_expired', plan.status,
      plan.tool, plan.risk, plan.payload_hash,
      jsonb_build_object('intakeId', intake.id, 'decisionAttempt', p_decision)
    );
    return jsonb_build_object(
      'kind', 'worker_execution_plan',
      'planId', plan.id,
      'status', plan.status,
      'intakeId', intake.id
    );
  end if;

  if p_decision = 'deny' then
    if plan.status = 'denied' then
      return jsonb_build_object(
        'kind', 'worker_execution_plan',
        'planId', plan.id,
        'status', plan.status,
        'intakeId', intake.id,
        'idempotentReplay', true
      );
    end if;
    if plan.status not in ('pending_approval', 'approved') then
      raise exception 'worker plan cannot be denied from status %', plan.status
        using errcode = '55000';
    end if;

    update private.execution_plans
    set status = 'denied',
        completed_at = now(),
        error = 'owner denied execution',
        updated_at = now()
    where id = plan.id
    returning * into plan;
    update public.projectos_intake_requests
    set status = 'rejected',
        analysis = coalesce(analysis, '{}'::jsonb) || jsonb_build_object(
          'latestExecutionPlanId', plan.id,
          'latestExecutionStatus', plan.status
        ),
        updated_at = now()
    where id = intake.id;
    perform private.append_execution_audit(
      p_organization_id, plan.id, plan.request_id, 'plan_denied', plan.status,
      plan.tool, plan.risk, plan.payload_hash,
      jsonb_build_object(
        'intakeId', intake.id,
        'decidedBy', left(coalesce(p_decided_by, 'owner'), 200)
      )
    );
    return jsonb_build_object(
      'kind', 'worker_execution_plan',
      'planId', plan.id,
      'status', plan.status,
      'intakeId', intake.id,
      'idempotentReplay', false
    );
  end if;

  if plan.status in ('completed', 'failed', 'denied', 'expired') then
    return jsonb_build_object(
      'kind', 'worker_execution_plan',
      'planId', plan.id,
      'status', plan.status,
      'intakeId', intake.id,
      'idempotentReplay', true
    );
  end if;

  if plan.status = 'executing' then
    select * into dispatch
    from private.execution_dispatch_outbox
    where organization_id = p_organization_id and plan_id = plan.id;
    if dispatch.id is null or dispatch.status = 'staged' then
      raise exception 'executing worker plan has no durable dispatch'
        using errcode = '55000';
    end if;
    return jsonb_build_object(
      'kind', 'worker_execution_plan',
      'planId', plan.id,
      'status', plan.status,
      'intakeId', intake.id,
      'dispatchId', dispatch.id,
      'dispatchStatus', dispatch.status,
      'idempotentReplay', true
    );
  end if;

  if plan.status = 'pending_approval' then
    transition := public.approve_execution_plan(
      p_organization_id,
      plan.id,
      left(coalesce(p_decided_by, 'owner'), 200)
    );
    if transition ->> 'status' is distinct from 'approved' then
      return jsonb_build_object(
        'kind', 'worker_execution_plan',
        'planId', plan.id,
        'status', transition ->> 'status',
        'intakeId', intake.id
      );
    end if;
    select * into plan from private.execution_plans where id = plan.id for update;
  end if;

  if plan.status <> 'approved' then
    raise exception 'worker plan cannot dispatch from status %', plan.status
      using errcode = '55000';
  end if;

  insert into private.execution_dispatch_outbox (
    organization_id, plan_id, status
  ) values (
    p_organization_id, plan.id, 'staged'
  )
  on conflict (plan_id) do nothing;

  select * into dispatch
  from private.execution_dispatch_outbox
  where organization_id = p_organization_id and plan_id = plan.id
  for update;
  if dispatch.id is null or dispatch.status <> 'staged' then
    raise exception 'worker dispatch staging conflict' using errcode = '55000';
  end if;

  transition := public.claim_execution_plan(p_organization_id, plan.id);
  if transition ->> 'status' is distinct from 'executing' then
    raise exception 'worker plan claim failed' using errcode = '55000';
  end if;

  update private.execution_dispatch_outbox
  set status = 'queued', updated_at = now()
  where id = dispatch.id and status = 'staged'
  returning * into dispatch;
  if dispatch.id is null then
    raise exception 'worker dispatch queue transition failed' using errcode = '55000';
  end if;

  perform private.append_execution_audit(
    p_organization_id,
    plan.id,
    plan.request_id,
    'worker_dispatch_enqueued',
    'executing',
    plan.tool,
    plan.risk,
    plan.payload_hash,
    jsonb_build_object(
      'dispatchId', dispatch.id,
      'intakeId', intake.id,
      'decidedBy', left(coalesce(p_decided_by, 'owner'), 200)
    )
  );

  return jsonb_build_object(
    'kind', 'worker_execution_plan',
    'planId', plan.id,
    'status', 'executing',
    'intakeId', intake.id,
    'dispatchId', dispatch.id,
    'dispatchStatus', dispatch.status,
    'idempotentReplay', false
  );
end;
$$;

create or replace function public.claim_governed_worker_dispatch(
  p_organization_id uuid,
  p_worker_identity text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  worker private.compute_worker_identities%rowtype;
  dispatch private.execution_dispatch_outbox%rowtype;
  expired_dispatch private.execution_dispatch_outbox%rowtype;
  plan private.execution_plans%rowtype;
  intake public.projectos_intake_requests%rowtype;
  runtime public.projectos_agent_runtime_proofs%rowtype;
  repository text;
  exact_sha text;
  job_class text;
  runtime_seconds integer;
begin
  perform private.assert_control_service_role();
  p_worker_identity := lower(trim(coalesce(p_worker_identity, '')));

  select * into worker
  from private.compute_worker_identities
  where organization_id = p_organization_id
    and worker_id = p_worker_identity
    and status = 'active'
  for update;
  if worker.worker_id is null then
    raise exception 'worker not enrolled' using errcode = '42501';
  end if;

  select * into expired_dispatch
  from private.execution_dispatch_outbox
  where organization_id = p_organization_id
    and status in ('claimed', 'envelope_ready')
    and lease_expires_at <= now()
  order by updated_at
  for update skip locked
  limit 1;
  if expired_dispatch.id is not null then
    if expired_dispatch.runtime_proof_id is not null then
      update public.projectos_agent_runtime_proofs
      set active_leases = greatest(active_leases - 1, 0), updated_at = now()
      where id = expired_dispatch.runtime_proof_id;
    end if;
    if expired_dispatch.status = 'claimed' then
      update private.execution_dispatch_outbox
      set status = 'queued',
          worker_identity = null,
          worker_key_fingerprint = null,
          builder_vendor = null,
          runtime_proof_id = null,
          lease_expires_at = null,
          error_code = 'UNSIGNED_LEASE_EXPIRED_REQUEUED',
          completed_at = null,
          updated_at = now()
      where id = expired_dispatch.id;
    else
      update private.execution_dispatch_outbox
      set status = 'ambiguous',
          error_code = 'LEASE_EXPIRED_OUTCOME_UNKNOWN',
          completed_at = now(),
          updated_at = now()
      where id = expired_dispatch.id;
    end if;
    select * into plan
    from private.execution_plans where id = expired_dispatch.plan_id;
    perform private.append_execution_audit(
      p_organization_id, plan.id, plan.request_id,
      case expired_dispatch.status
        when 'claimed' then 'worker_dispatch_unsigned_lease_requeued'
        else 'worker_dispatch_ambiguous'
      end,
      plan.status, plan.tool, plan.risk,
      plan.payload_hash,
      jsonb_build_object(
        'dispatchId', expired_dispatch.id,
        'reason', case expired_dispatch.status
          when 'claimed' then 'UNSIGNED_LEASE_EXPIRED_REQUEUED'
          else 'LEASE_EXPIRED_OUTCOME_UNKNOWN'
        end,
        'leaseExpiresAt', expired_dispatch.lease_expires_at
      )
    );
  end if;

  select * into dispatch
  from private.execution_dispatch_outbox
  where organization_id = p_organization_id
    and worker_identity = p_worker_identity
    and status in ('claimed', 'envelope_ready')
    and lease_expires_at > now()
  order by updated_at
  for update skip locked
  limit 1;

  if dispatch.id is null then
    select * into dispatch
    from private.execution_dispatch_outbox
    where organization_id = p_organization_id and status = 'queued'
    order by created_at
    for update skip locked
    limit 1;
    if dispatch.id is null then return null; end if;
  elsif dispatch.worker_key_fingerprint is distinct from worker.key_fingerprint then
    raise exception 'worker key changed during active dispatch'
      using errcode = '42501';
  end if;

  select * into plan
  from private.execution_plans
  where id = dispatch.plan_id and organization_id = p_organization_id
  for update;
  if plan.id is null
     or plan.status <> 'executing'
     or private.projectos_worker_plan_is_valid(
       plan.tool, plan.risk, plan.args, plan.payload_hash
     ) is distinct from true then
    raise exception 'invalid worker plan state' using errcode = '55000';
  end if;

  repository := plan.args ->> 'repository';
  exact_sha := plan.args ->> 'exactSha';
  job_class := plan.args ->> 'jobClass';
  runtime_seconds := (plan.args ->> 'maxRuntimeSeconds')::integer;
  if not (repository = any(worker.allowed_repositories))
     or not (job_class = any(worker.allowed_job_classes)) then
    raise exception 'worker scope denied' using errcode = '42501';
  end if;

  if dispatch.status = 'queued' then
    select request.* into intake
    from public.projectos_intake_requests request
    where request.id = plan.intake_id
      and request.organization_id = p_organization_id;
    if intake.id is null then
      raise exception 'worker plan intake missing' using errcode = '55000';
    end if;

    select proof.* into runtime
    from public.projectos_agent_runtime_proofs proof
    where proof.organization_id = p_organization_id
      and proof.project_id = intake.project_id
      and proof.agent_key = p_worker_identity
      and proof.role = 'builder'
      and proof.is_active
      and proof.expires_at > now()
      and proof.verified_at >= now() - interval '2 hours'
      and proof.context_updated_at >= now() - interval '30 minutes'
      and proof.phone_only_compatible
      and proof.credential_state = 'ready'
      and proof.quota_state in ('available', 'limited')
      and proof.health_state = 'healthy'
      and proof.active_leases < proof.max_concurrent_leases
      and repository = any(proof.repository_scopes)
      and (
        'projectos.worker.verify' = any(proof.proven_capabilities)
        or ('projectos.worker.verify:' || job_class) = any(proof.proven_capabilities)
      )
    order by proof.verified_at desc
    for update
    limit 1;
    if runtime.id is null then
      raise exception 'fresh worker runtime proof unavailable'
        using errcode = '42501';
    end if;

    update private.execution_dispatch_outbox
    set status = 'claimed',
        worker_identity = p_worker_identity,
        worker_key_fingerprint = worker.key_fingerprint,
        builder_vendor = runtime.vendor,
        runtime_proof_id = runtime.id,
        lease_expires_at = now() + make_interval(secs => runtime_seconds + 300),
        updated_at = now()
    where id = dispatch.id and status = 'queued'
    returning * into dispatch;
    if dispatch.id is null then
      raise exception 'worker dispatch claim conflict' using errcode = '55000';
    end if;
    update public.projectos_agent_runtime_proofs
    set active_leases = active_leases + 1, updated_at = now()
    where id = runtime.id;
    perform private.append_execution_audit(
      p_organization_id, plan.id, plan.request_id,
      'worker_dispatch_claimed', plan.status, plan.tool, plan.risk,
      plan.payload_hash,
      jsonb_build_object(
        'dispatchId', dispatch.id,
        'workerIdentity', p_worker_identity,
        'runtimeProofId', runtime.id,
        'leaseExpiresAt', dispatch.lease_expires_at
      )
    );
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'organizationId', p_organization_id,
    'dispatchId', dispatch.id,
    'planId', dispatch.plan_id,
    'status', dispatch.status,
    'workerIdentity', dispatch.worker_identity,
    'repository', repository,
    'exactSha', exact_sha,
    'jobClass', job_class,
    'maxRuntimeSeconds', runtime_seconds,
    'leaseExpiresAt', dispatch.lease_expires_at,
    'jobDigest', dispatch.job_digest,
    'jobPayload', dispatch.job_payload,
    'jobSignature', dispatch.job_signature,
    'redelivery', dispatch.status = 'envelope_ready'
  ));
end;
$$;

create or replace function public.record_governed_worker_job_envelope(
  p_organization_id uuid,
  p_dispatch_id uuid,
  p_plan_id uuid,
  p_worker_identity text,
  p_job_digest text,
  p_job_payload jsonb,
  p_job_signature text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  dispatch private.execution_dispatch_outbox%rowtype;
  plan private.execution_plans%rowtype;
  worker private.compute_worker_identities%rowtype;
  issued_at timestamptz;
  expires_at timestamptz;
begin
  perform private.assert_control_service_role();
  p_worker_identity := lower(trim(coalesce(p_worker_identity, '')));
  if coalesce(p_job_digest, '') !~ '^[0-9a-f]{64}$'
     or private.projectos_worker_job_payload_is_valid(p_job_payload)
       is distinct from true
     or coalesce(p_job_signature, '') !~ '^[A-Za-z0-9+/]{86}==$' then
    raise exception 'invalid worker job envelope' using errcode = '22023';
  end if;

  select * into dispatch
  from private.execution_dispatch_outbox
  where organization_id = p_organization_id
    and id = p_dispatch_id
    and plan_id = p_plan_id
    and worker_identity = p_worker_identity
  for update;
  if dispatch.id is null then
    raise exception 'worker dispatch claim not found' using errcode = 'P0002';
  end if;

  select * into worker
  from private.compute_worker_identities
  where organization_id = p_organization_id
    and worker_id = p_worker_identity
    and status = 'active';
  if worker.worker_id is null
     or worker.key_fingerprint is distinct from dispatch.worker_key_fingerprint then
    raise exception 'worker key does not match active dispatch'
      using errcode = '42501';
  end if;

  if dispatch.status = 'envelope_ready' then
    if dispatch.job_digest = p_job_digest
       and dispatch.job_payload = p_job_payload
       and dispatch.job_signature = p_job_signature then
      return jsonb_build_object(
        'dispatchId', dispatch.id,
        'planId', dispatch.plan_id,
        'status', dispatch.status,
        'jobDigest', dispatch.job_digest,
        'idempotentReplay', true
      );
    end if;
    raise exception 'worker envelope replay differs' using errcode = '55000';
  end if;
  if dispatch.status <> 'claimed' or dispatch.lease_expires_at <= now() then
    raise exception 'worker dispatch is not envelope-ready' using errcode = '55000';
  end if;

  select * into plan
  from private.execution_plans
  where organization_id = p_organization_id and id = dispatch.plan_id;
  if plan.id is null
     or plan.status <> 'executing'
     or private.projectos_worker_plan_is_valid(
       plan.tool, plan.risk, plan.args, plan.payload_hash
     ) is distinct from true then
    raise exception 'worker plan identity mismatch' using errcode = '55000';
  end if;

  begin
    issued_at := (p_job_payload ->> 'issuedAt')::timestamptz;
    expires_at := (p_job_payload ->> 'expiresAt')::timestamptz;
  exception when others then
    raise exception 'invalid worker envelope timestamps' using errcode = '22023';
  end;

  if p_job_payload ->> 'schemaVersion' is distinct from '1'
     or p_job_payload ->> 'audience' is distinct from ('pandora-worker:' || p_worker_identity)
     or p_job_payload ->> 'organizationId' is distinct from p_organization_id::text
     or p_job_payload ->> 'dispatchId' is distinct from dispatch.id::text
     or p_job_payload ->> 'planId' is distinct from plan.id::text
     or (p_job_payload ->> 'repository') is distinct from (plan.args ->> 'repository')
     or (p_job_payload ->> 'exactSha') is distinct from (plan.args ->> 'exactSha')
     or (p_job_payload ->> 'jobClass') is distinct from (plan.args ->> 'jobClass')
     or (p_job_payload ->> 'maxRuntimeSeconds') is distinct from
       (plan.args ->> 'maxRuntimeSeconds')
     or p_job_payload ->> 'runnerPolicyHash' !~ '^[0-9a-f]{64}$'
     or p_job_payload ->> 'runnerImageDigest' !~ '^sha256:[0-9a-f]{64}$'
     or p_job_payload ->> 'acquisitionImageDigest' !~ '^sha256:[0-9a-f]{64}$'
     or p_job_payload ->> 'networkPolicy' is distinct from 'none'
     or p_job_payload ->> 'isolation' is distinct from 'hyperv_container'
     or p_job_payload -> 'productionMutationAllowed' is distinct from 'false'::jsonb
     or issued_at is null
     or expires_at is null
     or issued_at < now() - interval '5 minutes'
     or issued_at > now() + interval '2 minutes'
     or expires_at <= now()
     or expires_at > dispatch.lease_expires_at
     or p_job_digest is distinct from private.projectos_worker_job_digest(p_job_payload) then
    raise exception 'worker envelope binding mismatch' using errcode = '55000';
  end if;

  update private.execution_dispatch_outbox
  set status = 'envelope_ready',
      job_digest = p_job_digest,
      job_payload = p_job_payload,
      job_signature = p_job_signature,
      updated_at = now()
  where id = dispatch.id and status = 'claimed'
  returning * into dispatch;
  if dispatch.id is null then
    raise exception 'worker envelope transition conflict' using errcode = '55000';
  end if;

  perform private.append_execution_audit(
    p_organization_id, plan.id, plan.request_id,
    'worker_job_envelope_recorded', plan.status, plan.tool, plan.risk,
    plan.payload_hash,
    jsonb_build_object(
      'dispatchId', dispatch.id,
      'workerIdentity', p_worker_identity,
      'jobDigest', p_job_digest,
      'leaseExpiresAt', dispatch.lease_expires_at
    )
  );

  return jsonb_build_object(
    'dispatchId', dispatch.id,
    'planId', dispatch.plan_id,
    'status', dispatch.status,
    'jobDigest', dispatch.job_digest,
    'idempotentReplay', false
  );
end;
$$;

create or replace function public.finish_governed_worker_dispatch(
  p_organization_id uuid,
  p_dispatch_id uuid,
  p_plan_id uuid,
  p_worker_identity text,
  p_outcome text,
  p_duration_ms integer,
  p_job_digest text,
  p_evidence_sha256 text,
  p_result_summary jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  dispatch private.execution_dispatch_outbox%rowtype;
  plan private.execution_plans%rowtype;
  started_at timestamptz;
  completed_at timestamptz;
  exit_code integer;
  tests_discovered integer;
  final_status text;
  prior_status text;
  was_ambiguous boolean;
begin
  perform private.assert_control_service_role();
  p_worker_identity := lower(trim(coalesce(p_worker_identity, '')));
  p_outcome := lower(trim(coalesce(p_outcome, '')));
  if coalesce(p_outcome, '') not in ('completed', 'failed')
     or coalesce(p_duration_ms, -1) not between 0 and 2100000
     or coalesce(p_job_digest, '') !~ '^[0-9a-f]{64}$'
     or coalesce(p_evidence_sha256, '') !~ '^[0-9a-f]{64}$'
     or private.projectos_worker_result_summary_is_valid(p_result_summary)
       is distinct from true then
    raise exception 'invalid worker completion' using errcode = '22023';
  end if;

  select * into dispatch
  from private.execution_dispatch_outbox
  where organization_id = p_organization_id
    and id = p_dispatch_id
    and plan_id = p_plan_id
    and worker_identity = p_worker_identity
  for update;
  if dispatch.id is null or dispatch.job_digest is distinct from p_job_digest then
    raise exception 'worker completion dispatch mismatch' using errcode = '55000';
  end if;

  final_status := case when p_outcome = 'completed' then 'completed' else 'failed' end;
  prior_status := dispatch.status;
  if dispatch.status in ('completed', 'failed') then
    if dispatch.status = final_status
       and dispatch.evidence_sha256 = p_evidence_sha256
       and dispatch.result_summary = p_result_summary then
      return jsonb_build_object(
        'dispatchId', dispatch.id,
        'planId', dispatch.plan_id,
        'status', dispatch.status,
        'evidenceSha256', dispatch.evidence_sha256,
        'idempotentReplay', true
      );
    end if;
    raise exception 'terminal worker completion differs' using errcode = '55000';
  end if;
  if dispatch.status = 'result_reported' then
    if dispatch.evidence_sha256 = p_evidence_sha256
       and dispatch.result_summary = p_result_summary then
      return jsonb_build_object(
        'dispatchId', dispatch.id,
        'planId', dispatch.plan_id,
        'status', dispatch.status,
        'evidenceSha256', dispatch.evidence_sha256,
        'reviewRequired', true,
        'idempotentReplay', true
      );
    end if;
    raise exception 'reported worker completion differs' using errcode = '55000';
  end if;

  select * into plan
  from private.execution_plans
  where organization_id = p_organization_id and id = dispatch.plan_id
  for update;
  if plan.id is null
     or plan.status <> 'executing'
     or private.projectos_worker_plan_is_valid(
       plan.tool, plan.risk, plan.args, plan.payload_hash
     ) is distinct from true then
    raise exception 'worker completion plan mismatch' using errcode = '55000';
  end if;

  if dispatch.status not in ('envelope_ready', 'ambiguous') then
    raise exception 'worker dispatch is not ready to report a result'
      using errcode = '55000';
  end if;
  was_ambiguous := dispatch.status = 'ambiguous'
    or dispatch.lease_expires_at <= now();

  begin
    started_at := (p_result_summary ->> 'startedAt')::timestamptz;
    completed_at := (p_result_summary ->> 'completedAt')::timestamptz;
    exit_code := (p_result_summary ->> 'exitCode')::integer;
    tests_discovered := (p_result_summary ->> 'testsDiscovered')::integer;
  exception when others then
    raise exception 'invalid worker result values' using errcode = '22023';
  end;

  if p_result_summary ->> 'schemaVersion' is distinct from '1'
     or p_result_summary ->> 'organizationId' is distinct from p_organization_id::text
     or p_result_summary ->> 'dispatchId' is distinct from dispatch.id::text
     or p_result_summary ->> 'planId' is distinct from plan.id::text
     or p_result_summary ->> 'workerId' is distinct from p_worker_identity
     or p_result_summary ->> 'jobDigest' is distinct from dispatch.job_digest
     or (p_result_summary ->> 'repository') is distinct from (plan.args ->> 'repository')
     or (p_result_summary ->> 'exactSha') is distinct from (plan.args ->> 'exactSha')
     or (p_result_summary ->> 'jobClass') is distinct from (plan.args ->> 'jobClass')
     or p_result_summary ->> 'outcome' is distinct from p_outcome
     or p_result_summary ->> 'isolation' is distinct from 'hyperv_container'
     or p_result_summary ->> 'networkPolicy' is distinct from 'none'
     or p_result_summary -> 'productionMutationAllowed' is distinct from 'false'::jsonb
     or (p_result_summary ->> 'runnerPolicyHash') is distinct from
       (dispatch.job_payload ->> 'runnerPolicyHash')
     or (p_result_summary ->> 'runnerImageDigest') is distinct from
       (dispatch.job_payload ->> 'runnerImageDigest')
     or (p_result_summary ->> 'acquisitionImageDigest') is distinct from
        (dispatch.job_payload ->> 'acquisitionImageDigest')
     or p_result_summary ->> 'sourceTreeSha' !~ '^[0-9a-f]{40}$'
     or p_result_summary ->> 'stdoutSha256' !~ '^[0-9a-f]{64}$'
     or p_result_summary ->> 'stderrSha256' !~ '^[0-9a-f]{64}$'
     or started_at is null
     or completed_at is null
     or exit_code is null
     or tests_discovered is null
     or started_at > completed_at
     or completed_at > now() + interval '2 minutes'
     or extract(epoch from (completed_at - started_at)) * 1000 > p_duration_ms + 5000
     or p_evidence_sha256 is distinct from
       private.projectos_worker_evidence_hash(p_result_summary)
     or (p_outcome = 'completed' and (exit_code <> 0 or tests_discovered < 1)) then
    raise exception 'worker completion evidence mismatch' using errcode = '55000';
  end if;

  update private.execution_dispatch_outbox
  set status = 'result_reported',
      evidence_sha256 = p_evidence_sha256,
      result_summary = p_result_summary,
      worker_reported_at = now(),
      error_code = case
        when was_ambiguous then 'LATE_RESULT_REPORTED_AFTER_LEASE_EXPIRY'
        else null
      end,
      completed_at = null,
      updated_at = now()
  where id = dispatch.id and status in ('envelope_ready', 'ambiguous')
  returning * into dispatch;
  if dispatch.id is null then
    raise exception 'worker completion transition conflict' using errcode = '55000';
  end if;
  if prior_status = 'envelope_ready' and dispatch.runtime_proof_id is not null then
    update public.projectos_agent_runtime_proofs
    set active_leases = greatest(active_leases - 1, 0), updated_at = now()
    where id = dispatch.runtime_proof_id;
  end if;

  perform private.append_execution_audit(
    p_organization_id, plan.id, plan.request_id,
    'worker_dispatch_result_reported', plan.status, plan.tool, plan.risk,
    plan.payload_hash,
    jsonb_build_object(
      'dispatchId', dispatch.id,
      'workerIdentity', p_worker_identity,
      'jobDigest', p_job_digest,
      'evidenceSha256', p_evidence_sha256,
      'durationMs', p_duration_ms,
      'workerReportedOutcome', p_outcome,
      'reviewRequired', true,
      'lateResult', was_ambiguous
    )
  );

  return jsonb_build_object(
    'dispatchId', dispatch.id,
    'planId', dispatch.plan_id,
    'status', dispatch.status,
    'evidenceSha256', dispatch.evidence_sha256,
    'reviewRequired', true,
    'idempotentReplay', false
  );
end;
$$;

create or replace function public.verify_governed_worker_dispatch(
  p_organization_id uuid,
  p_dispatch_id uuid,
  p_plan_id uuid,
  p_verifier_runtime_proof_id uuid,
  p_verification_evidence_id uuid,
  p_decision text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  dispatch private.execution_dispatch_outbox%rowtype;
  plan private.execution_plans%rowtype;
  intake public.projectos_intake_requests%rowtype;
  builder_proof public.projectos_agent_runtime_proofs%rowtype;
  verifier_proof public.projectos_agent_runtime_proofs%rowtype;
  verification_evidence public.projectos_evidence%rowtype;
  require_independent_vendor boolean;
  result_duration_ms integer;
begin
  perform private.assert_control_service_role();
  p_decision := lower(trim(coalesce(p_decision, '')));
  if p_decision not in ('completed', 'failed') then
    raise exception 'invalid worker review decision' using errcode = '22023';
  end if;

  select * into dispatch
  from private.execution_dispatch_outbox
  where organization_id = p_organization_id
    and id = p_dispatch_id
    and plan_id = p_plan_id
  for update;
  if dispatch.id is null then
    raise exception 'worker result not found' using errcode = 'P0002';
  end if;
  if dispatch.status in ('completed', 'failed') then
    if dispatch.status = p_decision
       and dispatch.verifier_runtime_proof_id = p_verifier_runtime_proof_id
       and dispatch.verification_evidence_id = p_verification_evidence_id then
      return jsonb_build_object(
        'dispatchId', dispatch.id,
        'planId', dispatch.plan_id,
        'status', dispatch.status,
        'verificationEvidenceId', dispatch.verification_evidence_id,
        'idempotentReplay', true
      );
    end if;
    raise exception 'terminal worker review differs' using errcode = '55000';
  end if;
  if dispatch.status <> 'result_reported'
     or dispatch.worker_reported_at is null
     or dispatch.evidence_sha256 is null
     or dispatch.result_summary is null then
    raise exception 'worker result is not reviewable' using errcode = '55000';
  end if;

  select * into plan
  from private.execution_plans
  where organization_id = p_organization_id and id = dispatch.plan_id
  for update;
  if plan.id is null
     or plan.status <> 'executing'
     or private.projectos_worker_plan_is_valid(
       plan.tool, plan.risk, plan.args, plan.payload_hash
     ) is distinct from true then
    raise exception 'worker review plan mismatch' using errcode = '55000';
  end if;

  select * into intake
  from public.projectos_intake_requests
  where organization_id = p_organization_id and id = plan.intake_id;
  if intake.id is null then
    raise exception 'worker review intake missing' using errcode = '55000';
  end if;

  select * into builder_proof
  from public.projectos_agent_runtime_proofs
  where id = dispatch.runtime_proof_id
    and organization_id = p_organization_id
    and project_id = intake.project_id;
  if builder_proof.id is null
     or builder_proof.agent_key <> dispatch.worker_identity
     or builder_proof.role <> 'builder'
     or private.projectos_canonical_agent_vendor(builder_proof.vendor)
       is distinct from
       private.projectos_canonical_agent_vendor(dispatch.builder_vendor) then
    raise exception 'worker builder identity snapshot mismatch'
      using errcode = '55000';
  end if;

  select * into verifier_proof
  from public.projectos_agent_runtime_proofs proof
  where proof.id = p_verifier_runtime_proof_id
    and proof.organization_id = p_organization_id
    and proof.project_id = intake.project_id
    and proof.role = 'reviewer'
    and proof.agent_key <> dispatch.worker_identity
    and proof.verified_by <> dispatch.worker_identity
    and proof.verified_by <> proof.agent_key
    and proof.is_active
    and proof.expires_at > now()
    and proof.verified_at >= now() - interval '2 hours'
    and proof.context_updated_at >= now() - interval '30 minutes'
    and proof.credential_state = 'ready'
    and proof.quota_state in ('available', 'limited')
    and proof.health_state = 'healthy'
    and (plan.args ->> 'repository') = any(proof.repository_scopes)
    and (
      'projectos.worker.verify.review' = any(proof.proven_capabilities)
      or (
        'projectos.worker.verify.review:' || (plan.args ->> 'jobClass')
      ) = any(proof.proven_capabilities)
    )
  for update;
  if verifier_proof.id is null then
    raise exception 'fresh reviewer runtime proof unavailable'
      using errcode = '42501';
  end if;

  select coalesce(policy.require_independent_vendor_review, true)
  into require_independent_vendor
  from public.projectos_policies policy
  where policy.organization_id = p_organization_id;
  require_independent_vendor := coalesce(require_independent_vendor, true);
  if require_independent_vendor
     and private.projectos_canonical_agent_vendor(verifier_proof.vendor) =
       private.projectos_canonical_agent_vendor(dispatch.builder_vendor) then
    raise exception 'reviewer vendor is not independent from worker builder'
      using errcode = '42501';
  end if;

  select * into verification_evidence
  from public.projectos_evidence evidence
  where evidence.id = p_verification_evidence_id
    and evidence.organization_id = p_organization_id
    and evidence.project_id = intake.project_id
    and evidence.repository = plan.args ->> 'repository'
    and evidence.head_sha = plan.args ->> 'exactSha'
    and evidence.invalidated_at is null
  for update;
  if verification_evidence.id is null
     or verification_evidence.evidence_type <> 'worker_dispatch_review'
     or private.projectos_canonical_agent_vendor(verification_evidence.provider) <>
       private.projectos_canonical_agent_vendor(verifier_proof.vendor)
     or verification_evidence.observed_at <
       dispatch.worker_reported_at - interval '2 minutes'
     or verification_evidence.payload_redacted ->> 'dispatchId'
       is distinct from dispatch.id::text
     or verification_evidence.payload_redacted ->> 'workerEvidenceSha256'
       is distinct from
       dispatch.evidence_sha256
     or verification_evidence.payload_redacted ->> 'reviewerAgent'
       is distinct from
       verifier_proof.agent_key
     or coalesce(private.projectos_canonical_agent_vendor(
       verification_evidence.payload_redacted ->> 'reviewerVendor'
     ), '') <> private.projectos_canonical_agent_vendor(verifier_proof.vendor)
     or verification_evidence.payload_redacted ->> 'decision'
       is distinct from p_decision then
    raise exception 'exact worker review evidence unavailable'
      using errcode = '55000';
  end if;

  if p_decision = 'completed' then
    if dispatch.result_summary ->> 'outcome' is distinct from 'completed'
       or verification_evidence.status not in ('passing', 'complete')
       or lower(trim(coalesce(verification_evidence.verdict, ''))) not in (
         'pass', 'passing', 'approved', 'completed'
       ) then
      raise exception 'passing independent review evidence required'
        using errcode = '55000';
    end if;
  elsif verification_evidence.status not in ('failing', 'blocked', 'complete')
     or lower(trim(coalesce(verification_evidence.verdict, ''))) not in (
       'fail', 'failed', 'rejected', 'blocked'
     ) then
    raise exception 'failing independent review evidence required'
      using errcode = '55000';
  end if;

  update private.execution_dispatch_outbox
  set status = 'finalizing',
      verifier_runtime_proof_id = verifier_proof.id,
      verification_evidence_id = verification_evidence.id,
      verification_summary = jsonb_build_object(
        'schemaVersion', 1,
        'decision', p_decision,
        'reviewerAgent', verifier_proof.agent_key,
        'reviewerVendor', verifier_proof.vendor,
        'verificationEvidenceId', verification_evidence.id,
        'repository', plan.args ->> 'repository',
        'exactSha', plan.args ->> 'exactSha'
      ),
      verified_outcome = p_decision,
      verified_at = now(),
      updated_at = now()
  where id = dispatch.id and status = 'result_reported'
  returning * into dispatch;
  if dispatch.id is null then
    raise exception 'worker review transition conflict' using errcode = '55000';
  end if;

  result_duration_ms := least(
    2100000,
    greatest(
      0,
      round(
        extract(epoch from (
          (dispatch.result_summary ->> 'completedAt')::timestamptz
          - (dispatch.result_summary ->> 'startedAt')::timestamptz
        )) * 1000
      )::integer
    )
  );

  perform public.finish_execution_plan(
    p_organization_id,
    plan.id,
    p_decision,
    result_duration_ms,
    case when p_decision = 'failed'
      then 'independent worker-result review failed'
      else null
    end,
    case when p_decision = 'completed' then jsonb_build_object(
      'dispatchId', dispatch.id,
      'repository', plan.args ->> 'repository',
      'exactSha', plan.args ->> 'exactSha',
      'jobClass', plan.args ->> 'jobClass',
      'workerEvidenceSha256', dispatch.evidence_sha256,
      'verificationEvidenceId', verification_evidence.id,
      'reviewerAgent', verifier_proof.agent_key,
      'reviewerVendor', verifier_proof.vendor
    ) else '{}'::jsonb end
  );

  update private.execution_dispatch_outbox
  set status = p_decision,
      error_code = case when p_decision = 'failed'
        then 'WORKER_RESULT_REVIEW_FAILED'
        else null
      end,
      completed_at = now(),
      updated_at = now()
  where id = dispatch.id and status = 'finalizing'
  returning * into dispatch;
  if dispatch.id is null then
    raise exception 'worker finalization transition conflict' using errcode = '55000';
  end if;

  perform private.append_execution_audit(
    p_organization_id,
    plan.id,
    plan.request_id,
    'worker_dispatch_reviewer_finalized',
    p_decision,
    plan.tool,
    plan.risk,
    plan.payload_hash,
    jsonb_build_object(
      'dispatchId', dispatch.id,
      'workerEvidenceSha256', dispatch.evidence_sha256,
      'verificationEvidenceId', verification_evidence.id,
      'reviewerRuntimeProofId', verifier_proof.id,
      'reviewerAgent', verifier_proof.agent_key,
      'reviewerVendor', verifier_proof.vendor
    )
  );

  return jsonb_build_object(
    'dispatchId', dispatch.id,
    'planId', dispatch.plan_id,
    'status', dispatch.status,
    'verificationEvidenceId', dispatch.verification_evidence_id,
    'idempotentReplay', false
  );
end;
$$;

revoke all on function public.register_compute_worker_identity(
  uuid, uuid, text, text, text[], text[]
) from public, anon, authenticated;
revoke all on function public.projectos_accept_governed_worker_intake(
  uuid, uuid, text, text, text, text
) from public, anon, authenticated;
revoke all on function public.projectos_create_or_get_worker_plan(
  uuid, uuid, jsonb, text, timestamptz
) from public, anon, authenticated;
revoke all on function public.resolve_compute_worker_identity(uuid, text)
  from public, anon, authenticated;
revoke all on function public.consume_compute_worker_nonce(uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.get_governed_worker_execution(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.decide_governed_worker_execution_plan(
  uuid, uuid, text, text
) from public, anon, authenticated;
revoke all on function public.claim_governed_worker_dispatch(uuid, text)
  from public, anon, authenticated;
revoke all on function public.record_governed_worker_job_envelope(
  uuid, uuid, uuid, text, text, jsonb, text
) from public, anon, authenticated;
revoke all on function public.finish_governed_worker_dispatch(
  uuid, uuid, uuid, text, text, integer, text, text, jsonb
) from public, anon, authenticated;
revoke all on function public.verify_governed_worker_dispatch(
  uuid, uuid, uuid, uuid, uuid, text
) from public, anon, authenticated;

grant execute on function public.register_compute_worker_identity(
  uuid, uuid, text, text, text[], text[]
) to service_role;
grant execute on function public.projectos_accept_governed_worker_intake(
  uuid, uuid, text, text, text, text
) to service_role;
grant execute on function public.projectos_create_or_get_worker_plan(
  uuid, uuid, jsonb, text, timestamptz
) to service_role;
grant execute on function public.resolve_compute_worker_identity(uuid, text)
  to service_role;
grant execute on function public.consume_compute_worker_nonce(uuid, text, text)
  to service_role;
grant execute on function public.get_governed_worker_execution(uuid, uuid)
  to service_role;
grant execute on function public.decide_governed_worker_execution_plan(
  uuid, uuid, text, text
) to service_role;
grant execute on function public.claim_governed_worker_dispatch(uuid, text)
  to service_role;
grant execute on function public.record_governed_worker_job_envelope(
  uuid, uuid, uuid, text, text, jsonb, text
) to service_role;
grant execute on function public.finish_governed_worker_dispatch(
  uuid, uuid, uuid, text, text, integer, text, text, jsonb
) to service_role;
grant execute on function public.verify_governed_worker_dispatch(
  uuid, uuid, uuid, uuid, uuid, text
) to service_role;
