-- Chat D — provider-neutral model telemetry, economics and health evidence.
-- Additive only. No Kimi routing activation and no raw prompt/response storage.

alter table public.pandora_model_runs
  add column if not exists provider_request_id text null,
  add column if not exists usage_source text null,
  add column if not exists cached_input_tokens bigint null,
  add column if not exists reasoning_tokens bigint null,
  add column if not exists cost_estimate_status text not null default 'unavailable',
  add column if not exists pricing_version text null,
  add column if not exists pricing_source text null,
  add column if not exists billing_reconciliation_status text not null default 'unavailable',
  add column if not exists billed_cost_source text null,
  add column if not exists reasoning_tier text null,
  add column if not exists provider_reasoning_tier text null,
  add column if not exists routing_decision_id uuid null,
  add column if not exists routing_policy_version text null,
  add column if not exists routing_candidates jsonb not null default '[]'::jsonb,
  add column if not exists routing_exclusions jsonb not null default '[]'::jsonb,
  add column if not exists routing_scores jsonb not null default '{}'::jsonb,
  add column if not exists routing_confidence numeric(8,7) null,
  add column if not exists routing_sample_count bigint null,
  add column if not exists session_stickiness_state text null,
  add column if not exists recovery_state text null,
  add column if not exists cohort_key text null,
  add column if not exists provider_latency_ms bigint null,
  add column if not exists transport_latency_ms bigint null,
  add column if not exists time_to_first_token_ms bigint null,
  add column if not exists stream_completion_latency_ms bigint null,
  add column if not exists end_to_end_latency_ms bigint null,
  add column if not exists structured_output_requested boolean null,
  add column if not exists structured_output_returned boolean null,
  add column if not exists structured_output_parseable boolean null,
  add column if not exists structured_output_schema_valid boolean null,
  add column if not exists structured_output_accepted boolean null,
  add column if not exists structured_output_regeneration_count integer null,
  add column if not exists structured_output_repair_succeeded boolean null,
  add column if not exists tool_call_emitted boolean null,
  add column if not exists tool_arguments_valid boolean null,
  add column if not exists tool_invoked boolean null,
  add column if not exists tool_execution_succeeded boolean null,
  add column if not exists tool_state_change_verified boolean null,
  add column if not exists tool_failure_domain text null,
  add column if not exists verification_required boolean null,
  add column if not exists verifier_run_id uuid null,
  add column if not exists verifier_provider text null,
  add column if not exists verifier_model text null,
  add column if not exists verifier_model_revision text null,
  add column if not exists verifier_policy_version text null,
  add column if not exists verification_outcome text null,
  add column if not exists verification_evidence_ref text null,
  add column if not exists final_adjudication text null,
  add column if not exists downstream_outcome_status text null,
  add column if not exists outcome_evidence_ref text null,
  add column if not exists failure_domain text null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='pandora_model_runs_usage_source_check' and conrelid='public.pandora_model_runs'::regclass) then
    alter table public.pandora_model_runs add constraint pandora_model_runs_usage_source_check
      check (usage_source is null or usage_source in ('provider_reported','locally_estimated','legacy_or_unknown'));
  end if;
  if not exists (select 1 from pg_constraint where conname='pandora_model_runs_extended_usage_check' and conrelid='public.pandora_model_runs'::regclass) then
    alter table public.pandora_model_runs add constraint pandora_model_runs_extended_usage_check
      check ((cached_input_tokens is null or cached_input_tokens >= 0)
        and (reasoning_tokens is null or reasoning_tokens >= 0)
        and (cached_input_tokens is null or cached_input_tokens <= input_tokens));
  end if;
  if not exists (select 1 from pg_constraint where conname='pandora_model_runs_cost_state_check' and conrelid='public.pandora_model_runs'::regclass) then
    alter table public.pandora_model_runs add constraint pandora_model_runs_cost_state_check
      check (cost_estimate_status in ('unavailable','estimated','not_applicable')
        and billing_reconciliation_status in ('unavailable','pending','matched','disputed','not_applicable'));
  end if;
  if not exists (select 1 from pg_constraint where conname='pandora_model_runs_routing_shape_check' and conrelid='public.pandora_model_runs'::regclass) then
    alter table public.pandora_model_runs add constraint pandora_model_runs_routing_shape_check
      check (jsonb_typeof(routing_candidates)='array'
        and jsonb_typeof(routing_exclusions)='array'
        and jsonb_typeof(routing_scores)='object'
        and octet_length(routing_candidates::text) <= 32768
        and octet_length(routing_exclusions::text) <= 32768
        and octet_length(routing_scores::text) <= 32768
        and (routing_confidence is null or (routing_confidence >= 0 and routing_confidence <= 1))
        and (routing_sample_count is null or routing_sample_count >= 0));
  end if;
  if not exists (select 1 from pg_constraint where conname='pandora_model_runs_latency_check' and conrelid='public.pandora_model_runs'::regclass) then
    alter table public.pandora_model_runs add constraint pandora_model_runs_latency_check
      check ((provider_latency_ms is null or provider_latency_ms >= 0)
        and (transport_latency_ms is null or transport_latency_ms >= 0)
        and (time_to_first_token_ms is null or time_to_first_token_ms >= 0)
        and (stream_completion_latency_ms is null or stream_completion_latency_ms >= 0)
        and (end_to_end_latency_ms is null or end_to_end_latency_ms >= 0));
  end if;
  if not exists (select 1 from pg_constraint where conname='pandora_model_runs_structured_check' and conrelid='public.pandora_model_runs'::regclass) then
    alter table public.pandora_model_runs add constraint pandora_model_runs_structured_check
      check (structured_output_regeneration_count is null or structured_output_regeneration_count between 0 and 100);
  end if;
  if not exists (select 1 from pg_constraint where conname='pandora_model_runs_verification_outcome_check' and conrelid='public.pandora_model_runs'::regclass) then
    alter table public.pandora_model_runs add constraint pandora_model_runs_verification_outcome_check
      check (verification_outcome is null or verification_outcome in ('pass','fail','disagree','remediated','skipped','unavailable'));
  end if;
  if not exists (select 1 from pg_constraint where conname='pandora_model_runs_failure_domain_check' and conrelid='public.pandora_model_runs'::regclass) then
    alter table public.pandora_model_runs add constraint pandora_model_runs_failure_domain_check
      check (failure_domain is null or failure_domain in ('provider','transport','model','tool','user_policy','infrastructure','verifier','security','unknown'));
  end if;
  if not exists (select 1 from pg_constraint where conname='pandora_model_runs_tool_failure_domain_check' and conrelid='public.pandora_model_runs'::regclass) then
    alter table public.pandora_model_runs add constraint pandora_model_runs_tool_failure_domain_check
      check (tool_failure_domain is null or tool_failure_domain in ('model_arguments','tool_runtime','external_dependency','authorization','policy','infrastructure','unknown'));
  end if;
  if not exists (select 1 from pg_constraint where conname='pandora_model_runs_verifier_run_fk' and conrelid='public.pandora_model_runs'::regclass) then
    alter table public.pandora_model_runs add constraint pandora_model_runs_verifier_run_fk
      foreign key (verifier_run_id) references public.pandora_model_runs(id) on delete restrict;
  end if;
end $$;

create index if not exists pandora_model_runs_routing_decision_idx
  on public.pandora_model_runs (routing_decision_id)
  where routing_decision_id is not null;
create index if not exists pandora_model_runs_provider_health_idx
  on public.pandora_model_runs (provider, model, model_revision, created_at desc);
create index if not exists pandora_model_runs_cohort_idx
  on public.pandora_model_runs (cohort_key, created_at desc)
  where cohort_key is not null;

create table if not exists public.pandora_model_attempts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  run_id uuid not null references public.pandora_model_runs(id) on delete cascade,
  fallback_chain_id uuid not null,
  attempt_index integer not null,
  provider text not null,
  model text not null,
  model_revision text null,
  provider_request_id text null,
  status text not null,
  error_code text null,
  failure_domain text null,
  error_kind text null,
  retryable boolean null,
  provider_http_status integer null,
  fallback_decision text not null default 'none',
  next_provider text null,
  next_model text null,
  provider_latency_ms bigint null,
  transport_latency_ms bigint null,
  observed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint pandora_model_attempts_attempt_check check (attempt_index between 1 and 100),
  constraint pandora_model_attempts_status_check check (status in ('succeeded','failed','cancelled')),
  constraint pandora_model_attempts_error_check check (error_code is null or error_code in ('provider_unavailable','timeout','rate_limited','authentication_failed','invalid_request','context_too_large','structured_output_invalid','unsupported_capability','budget_exhausted','provider_error')),
  constraint pandora_model_attempts_failure_domain_check check (failure_domain is null or failure_domain in ('provider','transport','model','tool','user_policy','infrastructure','verifier','security','unknown')),
  constraint pandora_model_attempts_fallback_check check (fallback_decision in ('none','retry_same_provider','fallback_next_provider','terminal')),
  constraint pandora_model_attempts_http_check check (provider_http_status is null or provider_http_status between 100 and 599),
  constraint pandora_model_attempts_latency_check check ((provider_latency_ms is null or provider_latency_ms >= 0) and (transport_latency_ms is null or transport_latency_ms >= 0)),
  constraint pandora_model_attempts_unique unique (run_id, attempt_index)
);

alter table public.pandora_model_attempts enable row level security;
drop policy if exists pandora_model_attempts_member_read on public.pandora_model_attempts;
create policy pandora_model_attempts_member_read on public.pandora_model_attempts
  for select to authenticated
  using (private.is_org_member(organization_id));
revoke all on public.pandora_model_attempts from anon;
revoke insert, update, delete on public.pandora_model_attempts from authenticated;
grant select on public.pandora_model_attempts to authenticated, service_role;
create index if not exists pandora_model_attempts_chain_idx
  on public.pandora_model_attempts (fallback_chain_id, attempt_index);
create index if not exists pandora_model_attempts_provider_health_idx
  on public.pandora_model_attempts (provider, model, model_revision, observed_at desc);

create table if not exists public.pandora_model_pricing_versions (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  model text not null,
  model_revision text null,
  pricing_version text not null,
  currency text not null default 'USD',
  input_micros_per_million_tokens bigint not null,
  cached_input_micros_per_million_tokens bigint not null,
  output_micros_per_million_tokens bigint not null,
  effective_at timestamptz not null,
  expires_at timestamptz null,
  source_ref text not null,
  source_verified_at timestamptz not null,
  verification_status text not null default 'verified',
  created_at timestamptz not null default now(),
  constraint pandora_model_pricing_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint pandora_model_pricing_rates_check check (
    input_micros_per_million_tokens >= 0
    and cached_input_micros_per_million_tokens >= 0
    and output_micros_per_million_tokens >= 0
  ),
  constraint pandora_model_pricing_window_check check (expires_at is null or expires_at > effective_at),
  constraint pandora_model_pricing_verification_check check (verification_status in ('verified','unverified','retired')),
  constraint pandora_model_pricing_unique unique (provider, model, pricing_version)
);

alter table public.pandora_model_pricing_versions enable row level security;
drop policy if exists pandora_model_pricing_authenticated_read on public.pandora_model_pricing_versions;
create policy pandora_model_pricing_authenticated_read on public.pandora_model_pricing_versions
  for select to authenticated using (true);
revoke all on public.pandora_model_pricing_versions from anon;
revoke insert, update, delete on public.pandora_model_pricing_versions from authenticated;
grant select on public.pandora_model_pricing_versions to authenticated, service_role;

insert into public.pandora_model_pricing_versions (
  provider, model, model_revision, pricing_version, currency,
  input_micros_per_million_tokens, cached_input_micros_per_million_tokens,
  output_micros_per_million_tokens, effective_at, expires_at,
  source_ref, source_verified_at, verification_status
) values (
  'kimi', 'kimi-k3', null, 'kimi-k3-usd-2026-09-02', 'USD',
  3000000, 300000, 15000000,
  '2026-09-02 00:00:00+08'::timestamptz, null,
  'https://platform.kimi.ai/', now(), 'verified'
)
on conflict (provider, model, pricing_version) do update
set input_micros_per_million_tokens = excluded.input_micros_per_million_tokens,
    cached_input_micros_per_million_tokens = excluded.cached_input_micros_per_million_tokens,
    output_micros_per_million_tokens = excluded.output_micros_per_million_tokens,
    source_ref = excluded.source_ref,
    source_verified_at = excluded.source_verified_at,
    verification_status = excluded.verification_status;

create or replace function public.pandora_estimate_model_cost_v1(
  p_provider text,
  p_model text,
  p_input_tokens bigint,
  p_cached_input_tokens bigint default 0,
  p_output_tokens bigint default 0,
  p_at timestamptz default now(),
  p_model_revision text default null
) returns jsonb
language plpgsql
stable
security invoker
set search_path = 'pg_catalog', 'public'
as $$
declare
  v_price public.pandora_model_pricing_versions%rowtype;
  v_uncached bigint;
  v_estimated bigint;
begin
  if nullif(trim(p_provider),'') is null or nullif(trim(p_model),'') is null then
    raise exception 'provider and model are required' using errcode='22023';
  end if;
  if p_input_tokens is null or p_input_tokens < 0
     or p_cached_input_tokens is null or p_cached_input_tokens < 0
     or p_output_tokens is null or p_output_tokens < 0
     or p_cached_input_tokens > p_input_tokens then
    raise exception 'invalid model usage' using errcode='22023';
  end if;

  select p.* into v_price
  from public.pandora_model_pricing_versions p
  where p.provider = p_provider
    and p.model = p_model
    and p.verification_status = 'verified'
    and p.effective_at <= p_at
    and (p.expires_at is null or p_at < p.expires_at)
    and (p.model_revision is null or p.model_revision = p_model_revision)
  order by (p.model_revision is not null) desc, p.effective_at desc, p.created_at desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'status','unavailable',
      'provider',p_provider,
      'model',p_model,
      'modelRevision',p_model_revision,
      'inputTokens',p_input_tokens,
      'cachedInputTokens',p_cached_input_tokens,
      'outputTokens',p_output_tokens,
      'estimatedCostMicros',null,
      'billedCostMicros',null
    );
  end if;

  v_uncached := p_input_tokens - p_cached_input_tokens;
  v_estimated := round((
      v_uncached::numeric * v_price.input_micros_per_million_tokens
    + p_cached_input_tokens::numeric * v_price.cached_input_micros_per_million_tokens
    + p_output_tokens::numeric * v_price.output_micros_per_million_tokens
  ) / 1000000)::bigint;

  return jsonb_build_object(
    'status','estimated',
    'provider',p_provider,
    'model',p_model,
    'modelRevision',p_model_revision,
    'inputTokens',p_input_tokens,
    'cachedInputTokens',p_cached_input_tokens,
    'uncachedInputTokens',v_uncached,
    'outputTokens',p_output_tokens,
    'estimatedCostMicros',v_estimated,
    'billedCostMicros',null,
    'currency',v_price.currency,
    'pricingVersion',v_price.pricing_version,
    'pricingSource',v_price.source_ref,
    'pricingVerifiedAt',v_price.source_verified_at
  );
end;
$$;

revoke all on function public.pandora_estimate_model_cost_v1(text,text,bigint,bigint,bigint,timestamptz,text) from public, anon;
grant execute on function public.pandora_estimate_model_cost_v1(text,text,bigint,bigint,bigint,timestamptz,text) to authenticated, service_role;

create or replace view public.pandora_provider_attempt_health_hourly_v1
with (security_invoker = true)
as
select
  date_trunc('hour', a.observed_at) as window_start,
  a.organization_id,
  a.project_id,
  r.task,
  a.provider,
  a.model,
  a.model_revision,
  r.cohort_key,
  count(*)::bigint as sample_count,
  max(a.observed_at) as freshest_observation_at,
  count(*) filter (where a.status='succeeded')::bigint as success_count,
  count(*) filter (where a.status='failed')::bigint as failure_count,
  count(*) filter (where a.status='failed' and a.retryable is true)::bigint as retryable_failure_count,
  count(*) filter (where a.error_code='rate_limited')::bigint as rate_limited_count,
  count(*) filter (where a.error_code='timeout')::bigint as timeout_count,
  count(*) filter (where a.error_code='provider_unavailable')::bigint as provider_unavailable_count,
  count(*) filter (where a.error_code='authentication_failed' or a.failure_domain='security')::bigint as auth_or_security_failure_count,
  count(*) filter (where a.failure_domain in ('provider','transport'))::bigint as provider_runtime_failure_count,
  count(*) filter (where a.failure_domain in ('user_policy','tool','infrastructure','verifier'))::bigint as non_provider_failure_count,
  count(a.provider_latency_ms)::bigint as latency_sample_count,
  percentile_cont(0.50) within group (order by a.provider_latency_ms) filter (where a.provider_latency_ms is not null) as provider_latency_p50_ms,
  case when count(a.provider_latency_ms) >= 10
    then percentile_cont(0.90) within group (order by a.provider_latency_ms) filter (where a.provider_latency_ms is not null)
    else null end as provider_latency_p90_ms,
  case when count(a.provider_latency_ms) >= 20
    then percentile_cont(0.95) within group (order by a.provider_latency_ms) filter (where a.provider_latency_ms is not null)
    else null end as provider_latency_p95_ms,
  case when count(a.provider_latency_ms) >= 100
    then percentile_cont(0.99) within group (order by a.provider_latency_ms) filter (where a.provider_latency_ms is not null)
    else null end as provider_latency_p99_ms,
  count(*) filter (where a.fallback_decision='fallback_next_provider')::bigint as fallback_trigger_count
from public.pandora_model_attempts a
join public.pandora_model_runs r on r.id=a.run_id
group by date_trunc('hour', a.observed_at), a.organization_id, a.project_id, r.task,
         a.provider, a.model, a.model_revision, r.cohort_key;

create or replace view public.pandora_provider_outcome_health_hourly_v1
with (security_invoker = true)
as
select
  date_trunc('hour', r.created_at) as window_start,
  r.organization_id,
  r.project_id,
  r.task,
  r.provider,
  r.model,
  r.model_revision,
  r.routing_policy_version,
  r.cohort_key,
  count(*)::bigint as sample_count,
  max(r.created_at) as freshest_observation_at,
  count(*) filter (where r.status='succeeded')::bigint as success_count,
  count(*) filter (where r.status='failed')::bigint as failure_count,
  count(*) filter (where r.structured_output_requested is true)::bigint as structured_requested_count,
  count(*) filter (where r.structured_output_schema_valid is true)::bigint as structured_schema_valid_count,
  count(*) filter (where r.structured_output_accepted is true)::bigint as structured_accepted_count,
  count(*) filter (where r.tool_invoked is true)::bigint as tool_invoked_count,
  count(*) filter (where r.tool_execution_succeeded is true)::bigint as tool_success_count,
  count(*) filter (where r.verification_required is true)::bigint as verification_required_count,
  count(*) filter (where r.verification_outcome='pass')::bigint as verifier_pass_count,
  count(*) filter (where r.verification_outcome='fail')::bigint as verifier_fail_count,
  count(*) filter (where r.verification_outcome='disagree')::bigint as verifier_disagree_count,
  count(*) filter (where exists (
    select 1 from public.pandora_model_attempts a
    where a.run_id=r.id and a.attempt_index > 1
  ))::bigint as fallback_run_count,
  count(*) filter (where r.cost_estimate_status='estimated')::bigint as estimated_cost_known_run_count,
  sum(r.estimated_cost_micros) filter (where r.cost_estimate_status='estimated')::bigint as estimated_cost_total_micros,
  case when count(*) filter (where r.status='succeeded' and r.cost_estimate_status='estimated') > 0
    then (sum(r.estimated_cost_micros) filter (where r.status='succeeded' and r.cost_estimate_status='estimated'))::numeric
       / nullif(count(*) filter (where r.status='succeeded' and r.cost_estimate_status='estimated'),0)
    else null end as estimated_cost_per_known_success_micros,
  count(r.provider_latency_ms)::bigint as latency_sample_count,
  percentile_cont(0.50) within group (order by r.provider_latency_ms) filter (where r.provider_latency_ms is not null) as provider_latency_p50_ms,
  case when count(r.provider_latency_ms) >= 20
    then percentile_cont(0.95) within group (order by r.provider_latency_ms) filter (where r.provider_latency_ms is not null)
    else null end as provider_latency_p95_ms,
  case when count(r.provider_latency_ms) >= 100
    then percentile_cont(0.99) within group (order by r.provider_latency_ms) filter (where r.provider_latency_ms is not null)
    else null end as provider_latency_p99_ms
from public.pandora_model_runs r
group by date_trunc('hour', r.created_at), r.organization_id, r.project_id, r.task,
         r.provider, r.model, r.model_revision, r.routing_policy_version, r.cohort_key;

revoke all on public.pandora_provider_attempt_health_hourly_v1 from anon;
revoke all on public.pandora_provider_outcome_health_hourly_v1 from anon;
grant select on public.pandora_provider_attempt_health_hourly_v1 to authenticated, service_role;
grant select on public.pandora_provider_outcome_health_hourly_v1 to authenticated, service_role;

comment on table public.pandora_model_attempts is
  'Append-only provider attempt/fallback evidence. No prompts, raw responses, authorization headers, or provider secrets.';
comment on table public.pandora_model_pricing_versions is
  'Versioned provider pricing authority for estimates only. Billed cost remains separate authoritative evidence.';
comment on view public.pandora_provider_attempt_health_hourly_v1 is
  'Component provider/runtime health metrics with sparse-percentile thresholds; not a universal health score.';
comment on view public.pandora_provider_outcome_health_hourly_v1 is
  'Provider outcome/economics/verification component metrics grouped by task/model/policy/cohort.';
