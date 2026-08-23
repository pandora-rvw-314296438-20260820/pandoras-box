-- Keep worker concurrency derived from the durable dispatch ledger and bind every
-- authenticated worker mutation to the exact key that verified the request.
-- This is a forward-only hardening migration; historical migration bytes remain
-- unchanged.

create or replace function private.projectos_worker_active_lease_count(
  p_runtime_proof_id uuid
)
returns integer
language sql
volatile
security definer
set search_path = ''
as $$
  select count(*)::integer
  from private.execution_dispatch_outbox dispatch
  where dispatch.runtime_proof_id = p_runtime_proof_id
    and dispatch.status in ('claimed', 'envelope_ready')
    and dispatch.lease_expires_at > now()
$$;

revoke all on function private.projectos_worker_active_lease_count(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.guard_projectos_runtime_proof_active_leases()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- active_leases is an output of the dispatch ledger, never caller input.
  new.active_leases := private.projectos_worker_active_lease_count(new.id);
  return new;
end;
$$;

revoke all on function private.guard_projectos_runtime_proof_active_leases()
  from public, anon, authenticated, service_role;

drop trigger if exists guard_projectos_runtime_proof_active_leases
  on public.projectos_agent_runtime_proofs;
create trigger guard_projectos_runtime_proof_active_leases
before insert or update on public.projectos_agent_runtime_proofs
for each row execute function private.guard_projectos_runtime_proof_active_leases();

create or replace function private.sync_projectos_worker_active_leases()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.runtime_proof_id is not null then
      update public.projectos_agent_runtime_proofs proof
      set active_leases = private.projectos_worker_active_lease_count(proof.id),
          updated_at = now()
      where proof.id = old.runtime_proof_id;
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE'
     and old.runtime_proof_id is not null
     and old.runtime_proof_id is distinct from new.runtime_proof_id then
    update public.projectos_agent_runtime_proofs proof
    set active_leases = private.projectos_worker_active_lease_count(proof.id),
        updated_at = now()
    where proof.id = old.runtime_proof_id;
  end if;

  if new.runtime_proof_id is not null then
    update public.projectos_agent_runtime_proofs proof
    set active_leases = private.projectos_worker_active_lease_count(proof.id),
        updated_at = now()
    where proof.id = new.runtime_proof_id;
  end if;
  return new;
end;
$$;

revoke all on function private.sync_projectos_worker_active_leases()
  from public, anon, authenticated, service_role;

drop trigger if exists sync_projectos_worker_active_leases
  on private.execution_dispatch_outbox;
create trigger sync_projectos_worker_active_leases
after insert or update or delete on private.execution_dispatch_outbox
for each row execute function private.sync_projectos_worker_active_leases();

-- Repair any counter that was previously supplied by a runtime-proof refresh.
update public.projectos_agent_runtime_proofs proof
set active_leases = private.projectos_worker_active_lease_count(proof.id)
where proof.active_leases is distinct from
  private.projectos_worker_active_lease_count(proof.id);

-- Preserve the existing validated upsert implementation behind a private
-- wrapper, then replace its caller-visible activeLeases echo with the value
-- actually stored by the database-owned lease guard.
alter function public.projectos_upsert_agent_runtime_proof(uuid, text, jsonb)
  set schema private;
revoke all on function private.projectos_upsert_agent_runtime_proof(
  uuid, text, jsonb
) from public, anon, authenticated, service_role;

create or replace function public.projectos_upsert_agent_runtime_proof(
  p_organization_id uuid,
  p_project_key text,
  p_proof jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  result_payload jsonb;
  durable_active_leases integer;
begin
  result_payload := private.projectos_upsert_agent_runtime_proof(
    p_organization_id,
    p_project_key,
    p_proof
  );

  select proof.active_leases into durable_active_leases
  from public.projectos_agent_runtime_proofs proof
  where proof.organization_id = p_organization_id
    and proof.id = (result_payload ->> 'proofId')::uuid;
  if durable_active_leases is null then
    raise exception 'runtime proof refresh readback missing'
      using errcode = '55000';
  end if;

  return jsonb_set(
    result_payload,
    '{activeLeases}',
    to_jsonb(durable_active_leases),
    false
  );
end;
$$;

revoke all on function public.projectos_upsert_agent_runtime_proof(
  uuid, text, jsonb
) from public, anon;
grant execute on function public.projectos_upsert_agent_runtime_proof(
  uuid, text, jsonb
) to authenticated, service_role;

create or replace function public.consume_compute_worker_nonce(
  p_organization_id uuid,
  p_worker_id text,
  p_expected_key_fingerprint text,
  p_nonce text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_worker_id text;
  result_payload jsonb;
begin
  perform private.assert_control_service_role();
  normalized_worker_id := lower(trim(coalesce(p_worker_id, '')));
  if coalesce(p_expected_key_fingerprint, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid expected worker key fingerprint'
      using errcode = '22023';
  end if;

  -- The row lock makes the fingerprint check and nonce mutation one transaction.
  perform 1
  from private.compute_worker_identities worker
  where worker.organization_id = p_organization_id
    and worker.worker_id = normalized_worker_id
    and worker.key_fingerprint = p_expected_key_fingerprint
    and worker.status in ('active', 'draining')
  for update;
  if not found then
    raise exception 'worker key fingerprint changed'
      using errcode = '42501';
  end if;

  result_payload := public.consume_compute_worker_nonce(
    p_organization_id,
    normalized_worker_id,
    p_nonce
  );
  return result_payload;
end;
$$;

create or replace function public.claim_governed_worker_dispatch(
  p_organization_id uuid,
  p_worker_identity text,
  p_expected_key_fingerprint text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_worker_id text;
  result_payload jsonb;
begin
  perform private.assert_control_service_role();
  normalized_worker_id := lower(trim(coalesce(p_worker_identity, '')));
  if coalesce(p_expected_key_fingerprint, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid expected worker key fingerprint'
      using errcode = '22023';
  end if;

  perform 1
  from private.compute_worker_identities worker
  where worker.organization_id = p_organization_id
    and worker.worker_id = normalized_worker_id
    and worker.key_fingerprint = p_expected_key_fingerprint
    and worker.status = 'active'
  for update;
  if not found then
    raise exception 'worker key fingerprint changed'
      using errcode = '42501';
  end if;

  result_payload := public.claim_governed_worker_dispatch(
    p_organization_id,
    normalized_worker_id
  );
  return result_payload;
end;
$$;

create or replace function public.finish_governed_worker_dispatch(
  p_organization_id uuid,
  p_dispatch_id uuid,
  p_plan_id uuid,
  p_worker_identity text,
  p_expected_key_fingerprint text,
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
  normalized_worker_id text;
  result_payload jsonb;
begin
  perform private.assert_control_service_role();
  normalized_worker_id := lower(trim(coalesce(p_worker_identity, '')));
  if coalesce(p_expected_key_fingerprint, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid expected worker key fingerprint'
      using errcode = '22023';
  end if;

  perform 1
  from private.compute_worker_identities worker
  where worker.organization_id = p_organization_id
    and worker.worker_id = normalized_worker_id
    and worker.key_fingerprint = p_expected_key_fingerprint
    and worker.status in ('active', 'draining')
  for update;
  if not found then
    raise exception 'worker key fingerprint changed'
      using errcode = '42501';
  end if;

  -- Also bind the completion to the key that claimed this exact dispatch.
  perform 1
  from private.execution_dispatch_outbox dispatch
  where dispatch.organization_id = p_organization_id
    and dispatch.id = p_dispatch_id
    and dispatch.plan_id = p_plan_id
    and dispatch.worker_identity = normalized_worker_id
    and dispatch.worker_key_fingerprint = p_expected_key_fingerprint
  for update;
  if not found then
    raise exception 'worker completion key binding mismatch'
      using errcode = '42501';
  end if;

  result_payload := public.finish_governed_worker_dispatch(
    p_organization_id,
    p_dispatch_id,
    p_plan_id,
    normalized_worker_id,
    p_outcome,
    p_duration_ms,
    p_job_digest,
    p_evidence_sha256,
    p_result_summary
  );
  return result_payload;
end;
$$;

-- The legacy overloads remain as internal implementation details for the
-- wrappers above, but are no longer callable through the service-role API.
revoke all on function public.consume_compute_worker_nonce(uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_governed_worker_dispatch(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.finish_governed_worker_dispatch(
  uuid, uuid, uuid, text, text, integer, text, text, jsonb
) from public, anon, authenticated, service_role;

revoke all on function public.consume_compute_worker_nonce(
  uuid, text, text, text
) from public, anon, authenticated;
revoke all on function public.claim_governed_worker_dispatch(
  uuid, text, text
) from public, anon, authenticated;
revoke all on function public.finish_governed_worker_dispatch(
  uuid, uuid, uuid, text, text, text, integer, text, text, jsonb
) from public, anon, authenticated;

grant execute on function public.consume_compute_worker_nonce(
  uuid, text, text, text
) to service_role;
grant execute on function public.claim_governed_worker_dispatch(
  uuid, text, text
) to service_role;
grant execute on function public.finish_governed_worker_dispatch(
  uuid, uuid, uuid, text, text, text, integer, text, text, jsonb
) to service_role;
