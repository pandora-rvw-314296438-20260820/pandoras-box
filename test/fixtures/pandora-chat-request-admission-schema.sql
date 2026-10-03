-- Exact live model-run checks and unique request identity captured read-only.
create unique index pandora_model_runs_request_uidx on public.pandora_model_runs(organization_id,request_id);
alter table public.pandora_model_runs add constraint pandora_model_runs_attempt_check CHECK ((((attempt >= 1) AND (attempt <= 100)) AND ((max_attempts >= 1) AND (max_attempts <= 100)) AND (attempt <= max_attempts)));
alter table public.pandora_model_runs add constraint pandora_model_runs_chat_scope_check CHECK (((task = 'chat'::text) OR ((project_id IS NOT NULL) AND (project_spec_id IS NOT NULL))));
alter table public.pandora_model_runs add constraint pandora_model_runs_cost_state_check CHECK (((cost_estimate_status = ANY (ARRAY['unavailable'::text, 'estimated'::text, 'not_applicable'::text])) AND (billing_reconciliation_status = ANY (ARRAY['unavailable'::text, 'pending'::text, 'matched'::text, 'disputed'::text, 'not_applicable'::text]))));
alter table public.pandora_model_runs add constraint pandora_model_runs_error_check CHECK (((error_code IS NULL) OR (error_code = ANY (ARRAY['provider_unavailable'::text, 'timeout'::text, 'rate_limited'::text, 'authentication_failed'::text, 'invalid_request'::text, 'context_too_large'::text, 'structured_output_invalid'::text, 'unsupported_capability'::text, 'budget_exhausted'::text, 'provider_error'::text]))));
alter table public.pandora_model_runs add constraint pandora_model_runs_extended_usage_check CHECK ((((cached_input_tokens IS NULL) OR (cached_input_tokens >= 0)) AND ((reasoning_tokens IS NULL) OR (reasoning_tokens >= 0)) AND ((cached_input_tokens IS NULL) OR (cached_input_tokens <= input_tokens))));
alter table public.pandora_model_runs add constraint pandora_model_runs_failure_domain_check CHECK (((failure_domain IS NULL) OR (failure_domain = ANY (ARRAY['provider'::text, 'transport'::text, 'model'::text, 'tool'::text, 'user_policy'::text, 'infrastructure'::text, 'verifier'::text, 'security'::text, 'unknown'::text]))));
alter table public.pandora_model_runs add constraint pandora_model_runs_hash_check CHECK (((request_sha256 ~ '^[0-9a-f]{64}$'::text) AND ((context_sha256 IS NULL) OR (context_sha256 ~ '^[0-9a-f]{64}$'::text)) AND ((schema_sha256 IS NULL) OR (schema_sha256 ~ '^[0-9a-f]{64}$'::text)) AND ((response_sha256 IS NULL) OR (response_sha256 ~ '^[0-9a-f]{64}$'::text))));
alter table public.pandora_model_runs add constraint pandora_model_runs_latency_check CHECK ((((provider_latency_ms IS NULL) OR (provider_latency_ms >= 0)) AND ((transport_latency_ms IS NULL) OR (transport_latency_ms >= 0)) AND ((time_to_first_token_ms IS NULL) OR (time_to_first_token_ms >= 0)) AND ((stream_completion_latency_ms IS NULL) OR (stream_completion_latency_ms >= 0)) AND ((end_to_end_latency_ms IS NULL) OR (end_to_end_latency_ms >= 0))));
alter table public.pandora_model_runs add constraint pandora_model_runs_output_mode_check CHECK ((output_mode = ANY (ARRAY['text'::text, 'json'::text, 'structured'::text, 'tool_proposals'::text])));
alter table public.pandora_model_runs add constraint pandora_model_runs_routing_shape_check CHECK (((jsonb_typeof(routing_candidates) = 'array'::text) AND (jsonb_typeof(routing_exclusions) = 'array'::text) AND (jsonb_typeof(routing_scores) = 'object'::text) AND (octet_length((routing_candidates)::text) <= 32768) AND (octet_length((routing_exclusions)::text) <= 32768) AND (octet_length((routing_scores)::text) <= 32768) AND ((routing_confidence IS NULL) OR ((routing_confidence >= (0)::numeric) AND (routing_confidence <= (1)::numeric))) AND ((routing_sample_count IS NULL) OR (routing_sample_count >= 0))));
alter table public.pandora_model_runs add constraint pandora_model_runs_selection_check CHECK (((requested_selection_mode = ANY (ARRAY['auto'::text, 'manual'::text])) AND (requested_fallback_mode = ANY (ARRAY['strict'::text, 'allow_fallback'::text])) AND (requested_reasoning_mode = ANY (ARRAY['auto'::text, 'fast'::text, 'deep'::text])) AND (((requested_selection_mode = 'auto'::text) AND (requested_provider IS NULL) AND (requested_model IS NULL)) OR ((requested_selection_mode = 'manual'::text) AND (requested_provider ~ '^[a-z][a-z0-9_-]{1,31}$'::text) AND ((length(TRIM(BOTH FROM requested_model)) >= 1) AND (length(TRIM(BOTH FROM requested_model)) <= 160))))));
alter table public.pandora_model_runs add constraint pandora_model_runs_source_dispatch_attempt_check CHECK (((source_dispatch_attempt IS NULL) OR ((source_dispatch_attempt >= 1) AND (source_dispatch_attempt <= 10))));
alter table public.pandora_model_runs add constraint pandora_model_runs_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'succeeded'::text, 'failed'::text, 'cancelled'::text])));
alter table public.pandora_model_runs add constraint pandora_model_runs_structured_check CHECK (((structured_output_regeneration_count IS NULL) OR ((structured_output_regeneration_count >= 0) AND (structured_output_regeneration_count <= 100))));
alter table public.pandora_model_runs add constraint pandora_model_runs_task_check CHECK ((task = ANY (ARRAY['chat'::text, 'understand_intent'::text, 'compile_project_spec'::text, 'classify_task'::text, 'plan_build'::text, 'design_experience'::text, 'plan_architecture'::text, 'generate_code'::text, 'generate_project_source'::text, 'repair_code'::text, 'inspect_error'::text, 'inspect_visual'::text, 'write_copy'::text, 'summarize_context'::text, 'extract_structure'::text, 'derive_acceptance_tests'::text])));
alter table public.pandora_model_runs add constraint pandora_model_runs_tool_failure_domain_check CHECK (((tool_failure_domain IS NULL) OR (tool_failure_domain = ANY (ARRAY['model_arguments'::text, 'tool_runtime'::text, 'external_dependency'::text, 'authorization'::text, 'policy'::text, 'infrastructure'::text, 'unknown'::text]))));
alter table public.pandora_model_runs add constraint pandora_model_runs_usage_check CHECK (((input_tokens >= 0) AND (output_tokens >= 0) AND (total_tokens >= 0) AND (estimated_cost_micros >= 0) AND (billed_cost_micros >= 0)));
alter table public.pandora_model_runs add constraint pandora_model_runs_usage_source_check CHECK (((usage_source IS NULL) OR (usage_source = ANY (ARRAY['provider_reported'::text, 'locally_estimated'::text, 'legacy_or_unknown'::text]))));
alter table public.pandora_model_runs add constraint pandora_model_runs_verification_outcome_check CHECK (((verification_outcome IS NULL) OR (verification_outcome = ANY (ARRAY['pass'::text, 'fail'::text, 'disagree'::text, 'remediated'::text, 'skipped'::text, 'unavailable'::text]))));
alter table public.pandora_model_runs enable row level security;
revoke all on public.pandora_model_runs from anon,authenticated;
grant select on public.pandora_model_runs to authenticated;
create policy pandora_model_runs_member_read on public.pandora_model_runs for select to authenticated using(private.is_org_member(organization_id));
-- Historical nullable thread project binding is validated, not created or used
-- as an admission/accounting identity. This is only the prior provider helper.
create table public.projectos_projects(id uuid primary key,organization_id uuid not null);
create function private.pandora_control_plane_project_org_matches(p_organization_id uuid,p_project_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from public.projectos_projects p where p.id=p_project_id and p.organization_id=p_organization_id);
$$;

create table public.runtime_rate_limit_buckets(organization_id uuid not null,key_hash text not null,window_started_at timestamptz not null,request_count integer not null,updated_at timestamptz not null default now(),primary key(organization_id,key_hash,window_started_at));
CREATE OR REPLACE FUNCTION public.consume_runtime_rate_limit(p_organization_id uuid, p_key_hash text, p_limit integer, p_window_seconds integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  observed_at timestamptz := clock_timestamp();
  bucket_started_at timestamptz;
  next_count integer;
  reset_at timestamptz;
begin
  if current_user not in ('postgres', 'service_role')
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;

  if p_key_hash is null or p_key_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid rate limit key hash' using errcode = '22023';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 10000 then
    raise exception 'invalid rate limit' using errcode = '22023';
  end if;

  if p_window_seconds is null or p_window_seconds < 1 or p_window_seconds > 3600 then
    raise exception 'invalid rate limit window' using errcode = '22023';
  end if;

  bucket_started_at := to_timestamp(
    floor(extract(epoch from observed_at) / p_window_seconds) * p_window_seconds
  );
  reset_at := bucket_started_at + make_interval(secs => p_window_seconds);

  insert into public.runtime_rate_limit_buckets (
    organization_id,
    key_hash,
    window_started_at,
    request_count,
    updated_at
  ) values (
    p_organization_id,
    p_key_hash,
    bucket_started_at,
    1,
    observed_at
  )
  on conflict (organization_id, key_hash, window_started_at)
  do update set
    request_count = public.runtime_rate_limit_buckets.request_count + 1,
    updated_at = excluded.updated_at
  returning request_count into next_count;

  delete from public.runtime_rate_limit_buckets
  where organization_id = p_organization_id
    and window_started_at < observed_at - interval '1 day';

  return jsonb_build_object(
    'allowed', next_count <= p_limit,
    'limit', p_limit,
    'remaining', greatest(p_limit - next_count, 0),
    'count', next_count,
    'resetAt', reset_at,
    'windowSeconds', p_window_seconds
  );
end;
$function$
;
revoke all on function public.consume_runtime_rate_limit(uuid,text,integer,integer) from public,anon,authenticated;
grant execute on function public.consume_runtime_rate_limit(uuid,text,integer,integer) to service_role;
