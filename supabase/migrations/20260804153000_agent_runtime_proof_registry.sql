-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

create table public.projectos_agent_runtime_proofs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  agent_key text not null check (agent_key ~ '^[a-z0-9][a-z0-9._:-]{0,127}$'),
  vendor text not null check (vendor ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  role text not null check (role in ('planner','builder','reviewer','operator','analyst')),
  repository_scopes text[] not null check (cardinality(repository_scopes) between 1 and 100),
  proven_capabilities text[] not null check (cardinality(proven_capabilities) between 1 and 100),
  phone_only_compatible boolean not null,
  credential_state text not null check (credential_state in ('ready','missing','expired','unknown')),
  quota_state text not null check (quota_state in ('available','limited','exhausted','unknown')),
  health_state text not null check (health_state in ('healthy','degraded','unavailable','unknown')),
  active_leases integer not null default 0 check (active_leases >= 0),
  max_concurrent_leases integer not null check (max_concurrent_leases between 1 and 100),
  cost_class text not null check (cost_class in ('free','subscription-included','metered')),
  verified_by text not null check (verified_by ~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,159}$'),
  evidence_refs jsonb not null default '[]'::jsonb check (jsonb_typeof(evidence_refs) = 'array'),
  verified_at timestamptz not null,
  context_updated_at timestamptz not null,
  expires_at timestamptz not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (active_leases <= max_concurrent_leases),
  check (expires_at > verified_at),
  unique (organization_id, project_id, agent_key, role)
);

create index projectos_agent_runtime_proofs_route_idx
  on public.projectos_agent_runtime_proofs (
    organization_id,
    project_id,
    role,
    expires_at desc
  )
  where is_active;

create index projectos_agent_runtime_proofs_agent_idx
  on public.projectos_agent_runtime_proofs (
    organization_id,
    agent_key,
    verified_at desc
  );

create trigger projectos_agent_runtime_proofs_updated
before update on public.projectos_agent_runtime_proofs
for each row execute function private.set_updated_at();

alter table public.projectos_agent_runtime_proofs enable row level security;

create policy projectos_agent_runtime_proofs_member_read
on public.projectos_agent_runtime_proofs
for select to authenticated
using (private.is_org_member(organization_id));

revoke all on public.projectos_agent_runtime_proofs from anon, authenticated;
grant select on public.projectos_agent_runtime_proofs to authenticated;
grant all on public.projectos_agent_runtime_proofs to service_role;

create or replace function private.projectos_canonical_agent_vendor(p_vendor text)
returns text
language sql
immutable
strict
set search_path = public, private, pg_temp
as $$
  with normalized as (
    select trim(regexp_replace(lower(trim(p_vendor)), '[^a-z0-9]+', ' ', 'g')) as value
  )
  select case
    when value ~ '(^| )(openai|chatgpt|codex)( |$)' then 'openai'
    when value ~ '(^| )(google|gemini|jules)( |$)' then 'google'
    when value ~ '(^| )(anthropic|claude)( |$)' then 'anthropic'
    when value ~ '(^| )(github|copilot)( |$)' then 'github'
    when value ~ '(^| )vercel( |$)' then 'vercel'
    else regexp_replace(value, ' +', '-', 'g')
  end
  from normalized;
$$;

revoke all on function private.projectos_canonical_agent_vendor(text) from public, anon, authenticated;
grant execute on function private.projectos_canonical_agent_vendor(text) to service_role;

create or replace function public.projectos_upsert_agent_runtime_proof(
  p_organization_id uuid,
  p_project_key text,
  p_proof jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_project_id uuid;
  v_agent_key text;
  v_vendor text;
  v_role text;
  v_repository_scopes text[];
  v_capabilities text[];
  v_phone_only boolean;
  v_credential_state text;
  v_quota_state text;
  v_health_state text;
  v_active_leases integer;
  v_max_leases integer;
  v_cost_class text;
  v_verified_by text;
  v_verified_at timestamptz;
  v_context_updated_at timestamptz;
  v_expires_at timestamptz;
  v_evidence_refs jsonb;
  v_unknown_keys text[];
  v_id uuid;
begin
  if auth.role() <> 'service_role'
     and not private.has_org_role(
       p_organization_id,
       array['owner','admin','operator']::public.member_role[]
     ) then
    raise exception using errcode = '42501', message = 'projectos_forbidden';
  end if;

  if jsonb_typeof(p_proof) <> 'object' then
    raise exception using errcode = '22023', message = 'runtime proof must be an object';
  end if;

  select array_agg(key order by key)
  into v_unknown_keys
  from jsonb_object_keys(p_proof) key
  where key <> all (array[
    'agent_key','vendor','role','repository_scopes','proven_capabilities',
    'phone_only_compatible','credential_state','quota_state','health_state',
    'active_leases','max_concurrent_leases','cost_class','verified_by',
    'evidence_refs','verified_at','context_updated_at','expires_at'
  ]::text[]);

  if v_unknown_keys is not null then
    raise exception using
      errcode = '22023',
      message = 'runtime proof contains unsupported fields',
      detail = array_to_string(v_unknown_keys, ',');
  end if;

  select id into strict v_project_id
  from public.projectos_projects
  where organization_id = p_organization_id
    and project_key = p_project_key
    and status <> 'archived';

  v_agent_key := lower(trim(coalesce(p_proof ->> 'agent_key', '')));
  v_vendor := private.projectos_canonical_agent_vendor(coalesce(p_proof ->> 'vendor', ''));
  v_role := lower(trim(coalesce(p_proof ->> 'role', '')));
  v_credential_state := lower(trim(coalesce(p_proof ->> 'credential_state', '')));
  v_quota_state := lower(trim(coalesce(p_proof ->> 'quota_state', '')));
  v_health_state := lower(trim(coalesce(p_proof ->> 'health_state', '')));
  v_cost_class := lower(trim(coalesce(p_proof ->> 'cost_class', '')));
  v_verified_by := trim(coalesce(p_proof ->> 'verified_by', ''));

  if v_agent_key !~ '^[a-z0-9][a-z0-9._:-]{0,127}$' then
    raise exception using errcode = '22023', message = 'runtime proof agent key is invalid';
  end if;
  if v_vendor !~ '^[a-z0-9][a-z0-9._-]{0,63}$' then
    raise exception using errcode = '22023', message = 'runtime proof vendor is invalid';
  end if;
  if v_role not in ('planner','builder','reviewer','operator','analyst') then
    raise exception using errcode = '22023', message = 'runtime proof role is invalid';
  end if;
  if v_credential_state not in ('ready','missing','expired','unknown')
     or v_quota_state not in ('available','limited','exhausted','unknown')
     or v_health_state not in ('healthy','degraded','unavailable','unknown') then
    raise exception using errcode = '22023', message = 'runtime proof state is invalid';
  end if;
  if v_cost_class not in ('free','subscription-included','metered') then
    raise exception using errcode = '22023', message = 'runtime proof cost class is invalid';
  end if;
  if v_verified_by !~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,159}$' then
    raise exception using errcode = '22023', message = 'runtime proof verifier is invalid';
  end if;

  if p_proof -> 'repository_scopes' is null
     or jsonb_typeof(p_proof -> 'repository_scopes') <> 'array' then
    raise exception using errcode = '22023', message = 'runtime proof repository scopes are required';
  end if;
  select coalesce(array_agg(distinct trim(value) order by trim(value)), '{}'::text[])
  into v_repository_scopes
  from jsonb_array_elements_text(p_proof -> 'repository_scopes') item(value)
  where trim(value) <> '';
  if cardinality(v_repository_scopes) not between 1 and 100
     or exists (
       select 1 from unnest(v_repository_scopes) scope
       where scope !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
     ) then
    raise exception using errcode = '22023', message = 'runtime proof repository scopes are invalid';
  end if;

  if p_proof -> 'proven_capabilities' is null
     or jsonb_typeof(p_proof -> 'proven_capabilities') <> 'array' then
    raise exception using errcode = '22023', message = 'runtime proof capabilities are required';
  end if;
  select coalesce(array_agg(distinct trim(value) order by trim(value)), '{}'::text[])
  into v_capabilities
  from jsonb_array_elements_text(p_proof -> 'proven_capabilities') item(value)
  where trim(value) <> '';
  if cardinality(v_capabilities) not between 1 and 100
     or exists (
       select 1 from unnest(v_capabilities) capability
       where char_length(capability) > 160
          or capability !~ '^[A-Za-z0-9][A-Za-z0-9 ._:/-]{0,159}$'
     ) then
    raise exception using errcode = '22023', message = 'runtime proof capabilities are invalid';
  end if;

  if jsonb_typeof(p_proof -> 'phone_only_compatible') <> 'boolean' then
    raise exception using errcode = '22023', message = 'runtime proof phone compatibility is required';
  end if;
  v_phone_only := (p_proof ->> 'phone_only_compatible')::boolean;

  begin
    v_active_leases := (p_proof ->> 'active_leases')::integer;
    v_max_leases := (p_proof ->> 'max_concurrent_leases')::integer;
    v_verified_at := coalesce((p_proof ->> 'verified_at')::timestamptz, now());
    v_context_updated_at := (p_proof ->> 'context_updated_at')::timestamptz;
    v_expires_at := coalesce(
      (p_proof ->> 'expires_at')::timestamptz,
      v_verified_at + interval '30 minutes'
    );
  exception when others then
    raise exception using errcode = '22023', message = 'runtime proof numeric or timestamp field is invalid';
  end;

  if v_active_leases < 0 or v_max_leases not between 1 and 100
     or v_active_leases > v_max_leases then
    raise exception using errcode = '22023', message = 'runtime proof capacity is invalid';
  end if;
  if v_verified_at > now() + interval '5 minutes'
     or v_verified_at < now() - interval '2 hours' then
    raise exception using errcode = '22023', message = 'runtime proof verification time is invalid';
  end if;
  if v_context_updated_at is null
     or v_context_updated_at > v_verified_at + interval '5 minutes'
     or v_context_updated_at < v_verified_at - interval '24 hours' then
    raise exception using errcode = '22023', message = 'runtime proof context time is invalid';
  end if;
  if v_expires_at <= greatest(now(), v_verified_at)
     or v_expires_at > v_verified_at + interval '2 hours' then
    raise exception using errcode = '22023', message = 'runtime proof expiry is invalid';
  end if;

  if p_proof -> 'evidence_refs' is null then
    v_evidence_refs := '[]'::jsonb;
  elsif jsonb_typeof(p_proof -> 'evidence_refs') <> 'array' then
    raise exception using errcode = '22023', message = 'runtime proof evidence references are invalid';
  else
    if jsonb_array_length(p_proof -> 'evidence_refs') > 50
       or exists (
         select 1
         from jsonb_array_elements(p_proof -> 'evidence_refs') ref
         where jsonb_typeof(ref) <> 'object'
            or exists (
              select 1 from jsonb_object_keys(ref) key
              where key <> all (array['provider','external_id','status','observed_at']::text[])
            )
            or coalesce(ref ->> 'provider', '') !~ '^[a-z][a-z0-9_-]{1,63}$'
            or char_length(coalesce(ref ->> 'external_id', '')) not between 1 and 240
            or coalesce(ref ->> 'status', '') !~ '^[a-z][a-z0-9_-]{1,63}$'
       ) then
      raise exception using errcode = '22023', message = 'runtime proof evidence references are invalid';
    end if;
    select coalesce(
      jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'provider', ref ->> 'provider',
          'external_id', ref ->> 'external_id',
          'status', ref ->> 'status',
          'observed_at', nullif(ref ->> 'observed_at', '')
        ))
        order by ref ->> 'provider', ref ->> 'external_id'
      ),
      '[]'::jsonb
    ) into v_evidence_refs
    from jsonb_array_elements(p_proof -> 'evidence_refs') ref;
  end if;

  insert into public.projectos_agent_runtime_proofs (
    organization_id, project_id, agent_key, vendor, role,
    repository_scopes, proven_capabilities, phone_only_compatible,
    credential_state, quota_state, health_state,
    active_leases, max_concurrent_leases, cost_class,
    verified_by, evidence_refs, verified_at, context_updated_at, expires_at, is_active
  ) values (
    p_organization_id, v_project_id, v_agent_key, v_vendor, v_role,
    v_repository_scopes, v_capabilities, v_phone_only,
    v_credential_state, v_quota_state, v_health_state,
    v_active_leases, v_max_leases, v_cost_class,
    v_verified_by, v_evidence_refs, v_verified_at, v_context_updated_at, v_expires_at, true
  )
  on conflict (organization_id, project_id, agent_key, role) do update set
    vendor = excluded.vendor,
    repository_scopes = excluded.repository_scopes,
    proven_capabilities = excluded.proven_capabilities,
    phone_only_compatible = excluded.phone_only_compatible,
    credential_state = excluded.credential_state,
    quota_state = excluded.quota_state,
    health_state = excluded.health_state,
    active_leases = excluded.active_leases,
    max_concurrent_leases = excluded.max_concurrent_leases,
    cost_class = excluded.cost_class,
    verified_by = excluded.verified_by,
    evidence_refs = excluded.evidence_refs,
    verified_at = excluded.verified_at,
    context_updated_at = excluded.context_updated_at,
    expires_at = excluded.expires_at,
    is_active = true
  returning id into v_id;

  return jsonb_build_object(
    'proofId', v_id,
    'projectKey', p_project_key,
    'agentKey', v_agent_key,
    'vendor', v_vendor,
    'role', v_role,
    'repositoryScopes', to_jsonb(v_repository_scopes),
    'provenCapabilities', to_jsonb(v_capabilities),
    'phoneOnlyCompatible', v_phone_only,
    'credentialState', v_credential_state,
    'quotaState', v_quota_state,
    'healthState', v_health_state,
    'activeLeases', v_active_leases,
    'maxConcurrentLeases', v_max_leases,
    'costClass', v_cost_class,
    'verifiedBy', v_verified_by,
    'verifiedAt', v_verified_at,
    'contextUpdatedAt', v_context_updated_at,
    'expiresAt', v_expires_at,
    'evidenceRefs', v_evidence_refs,
    'redacted', true
  );
end;
$$;

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
  if auth.role() <> 'service_role'
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
      and role = v_role
    group by lower(trim(agent_key)), private.projectos_canonical_agent_vendor(vendor), role
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
        + greatest(0, 1 - proof.active_leases::numeric / proof.max_concurrent_leases::numeric) * 0.05
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
    select * from eligible
    order by score desc, observation_count desc, agent_key
    limit greatest(1, least(coalesce(p_limit, 5), 20))
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
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
    ) order by score desc, observation_count desc, agent_key), '[]'::jsonb),
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
    'reason', case when v_count = 0 then 'no_fresh_authorized_agent_runtime_proof' else null end,
    'candidates', v_candidates,
    'redacted', true
  );
end;
$$;

revoke all on function public.projectos_upsert_agent_runtime_proof(uuid,text,jsonb)
  from public, anon;
revoke all on function public.projectos_get_agent_routing_evidence(uuid,text,text,text,text,integer)
  from public, anon;
grant execute on function public.projectos_upsert_agent_runtime_proof(uuid,text,jsonb)
  to authenticated, service_role;
grant execute on function public.projectos_get_agent_routing_evidence(uuid,text,text,text,text,integer)
  to authenticated, service_role;
