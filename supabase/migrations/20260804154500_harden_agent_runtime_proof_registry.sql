-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

create or replace function private.projectos_agent_runtime_proof_write_guard()
returns trigger
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role'
     and not private.has_org_role(
       new.organization_id,
       array['owner','admin','operator']::public.member_role[]
     ) then
    raise exception using errcode = '42501', message = 'projectos_forbidden';
  end if;

  if tg_op = 'UPDATE' and new.vendor <> old.vendor then
    raise exception using
      errcode = '22023',
      message = 'runtime proof vendor mismatch';
  end if;

  return new;
end;
$$;

revoke all on function private.projectos_agent_runtime_proof_write_guard()
  from public, anon, authenticated;
grant execute on function private.projectos_agent_runtime_proof_write_guard()
  to service_role;

drop trigger if exists projectos_agent_runtime_proof_write_guard
  on public.projectos_agent_runtime_proofs;
create trigger projectos_agent_runtime_proof_write_guard
before insert or update on public.projectos_agent_runtime_proofs
for each row execute function private.projectos_agent_runtime_proof_write_guard();

create or replace function public.projectos_get_agent_routing_evidence(
  p_organization_id uuid,
  p_project_key text,
  p_role text,
  p_repository text,
  p_capability text,
  p_limit integer default 5
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_project_id uuid;
  v_role text := lower(trim(p_role));
  v_repository text := trim(p_repository);
  v_capability text := trim(p_capability);
  v_candidates jsonb;
  v_count integer;
begin
  if coalesce(auth.role(), '') <> 'service_role'
     and not private.is_org_member(p_organization_id) then
    raise exception using errcode = '42501', message = 'projectos_forbidden';
  end if;
  if v_role not in ('planner','builder','reviewer','operator','analyst') then
    raise exception using errcode = '22023', message = 'routing role is invalid';
  end if;
  if v_repository !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' then
    raise exception using errcode = '22023', message = 'routing repository is invalid';
  end if;
  if char_length(v_capability) not between 1 and 160
     or v_capability !~ '^[A-Za-z0-9][A-Za-z0-9 ._:/-]{0,159}$' then
    raise exception using errcode = '22023', message = 'routing capability is invalid';
  end if;

  select id into strict v_project_id
  from public.projectos_projects
  where organization_id = p_organization_id
    and project_key = p_project_key
    and status <> 'archived';

  with observations as (
    select
      lower(trim(agent_key)) as agent_key,
      private.projectos_canonical_agent_vendor(vendor) as vendor,
      role,
      count(*)::integer as observation_count,
      count(*) filter (where success)::integer as success_count,
      avg(case when success then 1.0 else 0.0 end) as success_rate,
      avg(coalesce(quality_score, case when success then 75 else 25 end)) as average_quality,
      avg(repair_attempts::numeric) as average_repairs,
      max(observed_at) as latest_observed_at
    from public.projectos_agent_observations
    where organization_id = p_organization_id
      and project_id = v_project_id
      and role = v_role
    group by
      lower(trim(agent_key)),
      private.projectos_canonical_agent_vendor(vendor),
      role
  ), eligible as (
    select
      proof.id as proof_id,
      proof.agent_key,
      proof.vendor,
      proof.role,
      proof.repository_scopes,
      proof.proven_capabilities,
      proof.phone_only_compatible,
      proof.credential_state,
      proof.quota_state,
      proof.health_state,
      proof.active_leases,
      proof.max_concurrent_leases,
      proof.cost_class,
      proof.verified_by,
      proof.evidence_refs,
      proof.verified_at,
      proof.context_updated_at,
      proof.expires_at,
      observation.observation_count,
      observation.success_count,
      observation.success_rate,
      observation.average_quality,
      observation.average_repairs,
      observation.latest_observed_at,
      (
        observation.success_rate * 0.35
        + (observation.average_quality / 100.0) * 0.25
        + least(1.0, observation.observation_count::numeric / 10.0) * 0.10
        + case proof.quota_state when 'available' then 0.10 when 'limited' then 0.04 else 0 end
        + case proof.health_state when 'healthy' then 0.10 when 'degraded' then 0.03 else 0 end
        + greatest(
            0,
            1 - proof.active_leases::numeric
              / proof.max_concurrent_leases::numeric
          ) * 0.05
        + case proof.cost_class when 'free' then 0.05 when 'subscription-included' then 0.04 else 0 end
        - least(0.20, observation.average_repairs * 0.04)
      ) as score
    from public.projectos_agent_runtime_proofs proof
    join observations observation
      on observation.agent_key = proof.agent_key
     and observation.vendor = proof.vendor
     and observation.role = proof.role
    where proof.organization_id = p_organization_id
      and proof.project_id = v_project_id
      and proof.role = v_role
      and proof.is_active
      and proof.expires_at > now()
      and proof.verified_at >= now() - interval '2 hours'
      and proof.context_updated_at >= now() - interval '30 minutes'
      and proof.phone_only_compatible
      and proof.credential_state = 'ready'
      and proof.quota_state in ('available','limited')
      and proof.health_state in ('healthy','degraded')
      and proof.active_leases < proof.max_concurrent_leases
      and v_repository = any(proof.repository_scopes)
      and v_capability = any(proof.proven_capabilities)
  ), ranked as (
    select *
    from eligible
    order by score desc, observation_count desc, agent_key
    limit greatest(1, least(coalesce(p_limit, 5), 20))
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'proofId', proof_id,
          'agentKey', agent_key,
          'vendor', vendor,
          'role', role,
          'score', round(score, 4),
          'observationCount', observation_count,
          'successCount', success_count,
          'successRate', round(success_rate, 4),
          'averageQuality', round(average_quality, 2),
          'averageRepairs', round(average_repairs, 2),
          'latestObservedAt', latest_observed_at,
          'repositoryScopes', to_jsonb(repository_scopes),
          'provenCapabilities', to_jsonb(proven_capabilities),
          'phoneOnlyCompatible', phone_only_compatible,
          'credentialState', credential_state,
          'quotaState', quota_state,
          'healthState', health_state,
          'activeLeases', active_leases,
          'maxConcurrentLeases', max_concurrent_leases,
          'costClass', cost_class,
          'verifiedBy', verified_by,
          'verifiedAt', verified_at,
          'contextUpdatedAt', context_updated_at,
          'expiresAt', expires_at,
          'evidenceRefs', evidence_refs,
          'qualified', true
        )
        order by score desc, observation_count desc, agent_key
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_candidates, v_count
  from ranked;

  return jsonb_build_object(
    'schemaVersion', 'projectos-agent-routing-evidence-v1',
    'projectKey', p_project_key,
    'repository', v_repository,
    'capability', v_capability,
    'role', v_role,
    'generatedAt', now(),
    'failClosed', v_count = 0,
    'reason', case
      when v_count = 0 then 'no_fresh_authorized_agent_runtime_proof'
      else null
    end,
    'candidates', v_candidates,
    'redacted', true
  );
end;
$$;

revoke all on function public.projectos_get_agent_routing_evidence(
  uuid,text,text,text,text,integer
) from public, anon;
grant execute on function public.projectos_get_agent_routing_evidence(
  uuid,text,text,text,text,integer
) to authenticated, service_role;
