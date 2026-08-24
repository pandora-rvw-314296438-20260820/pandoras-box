-- Close the remaining privileged worker/context validation boundaries.
-- This migration is forward-safe if the earlier governed migrations have
-- already been applied: malformed durable rows fail validation rather than
-- being silently normalized or grandfathered.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '5min';

create or replace function private.projectos_json_object_has_exact_nonnull_keys(
  p_value jsonb,
  p_required_keys text[]
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select case
    when jsonb_typeof(p_value) is distinct from 'object'
      or coalesce(cardinality(p_required_keys), 0) = 0 then false
    else coalesce(
      (select count(*) from jsonb_object_keys(p_value)) = cardinality(p_required_keys)
      and (
        select count(distinct required.required_key)
        from unnest(p_required_keys) as required(required_key)
      )
        = cardinality(p_required_keys)
      and p_value ?& p_required_keys
      and not exists (
        select 1
        from unnest(p_required_keys) as required(required_key)
        where p_value -> required.required_key is null
          or p_value -> required.required_key = 'null'::jsonb
      ),
      false
    )
  end;
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
  select coalesce(
    p_tool = 'projectos.worker.verify'
    and p_risk = 'write'
    and private.projectos_json_object_has_exact_nonnull_keys(
      p_args,
      array[
        'schemaVersion', 'repository', 'exactSha', 'jobClass',
        'maxRuntimeSeconds', 'productionMutationAllowed'
      ]::text[]
    ) is true
    and p_args -> 'schemaVersion' is not distinct from '1'::jsonb
    and p_args -> 'productionMutationAllowed' is not distinct from 'false'::jsonb
    and p_args ->> 'repository' = 'banataosystems/Pandoras-box'
    and p_args ->> 'exactSha' ~ '^[0-9a-f]{40}$'
    and p_args ->> 'jobClass' in ('node_regression', 'supabase_migration_replay')
    and case
      when p_args ->> 'maxRuntimeSeconds' ~ '^[0-9]{2,4}$'
        then (p_args ->> 'maxRuntimeSeconds')::integer between 30 and 1800
      else false
    end
    and p_payload_hash = private.projectos_worker_plan_payload_hash(p_args),
    false
  );
$$;

revoke all on function private.projectos_json_object_has_exact_nonnull_keys(jsonb, text[])
  from public, anon, authenticated, service_role, projectos_reviewer_ingest;
revoke all on function private.projectos_worker_plan_is_valid(text, text, jsonb, text)
  from public, anon, authenticated, service_role, projectos_reviewer_ingest;

alter table private.execution_dispatch_outbox
  add constraint execution_dispatch_outbox_job_payload_contract
  check (
    job_payload is null
    or private.projectos_json_object_has_exact_nonnull_keys(
      job_payload,
      array[
        'schemaVersion', 'audience', 'organizationId', 'dispatchId', 'planId',
        'repository', 'exactSha', 'jobClass', 'maxRuntimeSeconds', 'issuedAt',
        'expiresAt', 'runnerPolicyHash', 'runnerImageDigest',
        'acquisitionImageDigest', 'networkPolicy', 'isolation',
        'productionMutationAllowed'
      ]::text[]
    ) is true
  ) not valid;

alter table private.execution_dispatch_outbox
  validate constraint execution_dispatch_outbox_job_payload_contract;

alter table private.execution_dispatch_outbox
  add constraint execution_dispatch_outbox_result_summary_contract
  check (
    result_summary is null
    or private.projectos_json_object_has_exact_nonnull_keys(
      result_summary,
      array[
        'schemaVersion', 'organizationId', 'dispatchId', 'planId', 'workerId',
        'jobDigest', 'repository', 'exactSha', 'jobClass', 'outcome', 'exitCode',
        'isolation', 'networkPolicy', 'productionMutationAllowed',
        'runnerPolicyHash', 'runnerImageDigest', 'acquisitionImageDigest',
        'sourceTreeSha', 'testsDiscovered', 'startedAt', 'completedAt',
        'stdoutSha256', 'stderrSha256'
      ]::text[]
    ) is true
  ) not valid;

alter table private.execution_dispatch_outbox
  validate constraint execution_dispatch_outbox_result_summary_contract;

-- Hash provenance is versioned in 20260823163000. Historical evidence keeps
-- its original digest bytes and is validated with its recorded serializer;
-- every new attachment is explicitly stamped with the canonical contract.
alter table private.execution_plan_contexts
  add constraint execution_plan_contexts_hash_matches_envelope
  check (
    canonical_context_hash = private.projectos_context_json_sha256(
      private.projectos_canonical_context_json(context_envelope)
    )
    and private.projectos_context_hash_matches_contract(
      context_hash, context_envelope, hash_contract
    ) is true
  ) not valid;

alter table private.execution_plan_contexts
  validate constraint execution_plan_contexts_hash_matches_envelope;

-- SECURITY DEFINER callers run as their owner, so current_user cannot prove
-- the original API role. Only a direct postgres session or an authenticator
-- session carrying a verified service_role JWT may cross this boundary.
create or replace function private.assert_control_service_role()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if session_user = 'postgres' then
    return;
  end if;
  if session_user <> 'authenticator'
     or coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.assert_control_service_role()
  from public, anon, authenticated, service_role, projectos_reviewer_ingest;

-- Moving this legacy definer to private preserved its old broad configuration.
-- Its body already qualifies every application relation, so pin it empty now.
alter function private.projectos_upsert_agent_runtime_proof(uuid, text, jsonb)
  set search_path = '';

create or replace function private.reject_governed_worker_review_attestation_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'governed worker reviewer attestations are immutable'
    using errcode = '55000';
end;
$$;

revoke all on function private.reject_governed_worker_review_attestation_mutation()
  from public, anon, authenticated, service_role, projectos_reviewer_ingest;

drop trigger if exists governed_worker_review_attestations_immutable
  on private.governed_worker_review_attestations;
create trigger governed_worker_review_attestations_immutable
before update or delete on private.governed_worker_review_attestations
for each row execute function
  private.reject_governed_worker_review_attestation_mutation();

commit;
