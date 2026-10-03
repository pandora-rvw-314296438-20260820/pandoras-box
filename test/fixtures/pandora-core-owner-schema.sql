-- Focused synthetic database fixture for the Core Owner migration.
-- Reused table columns/types/defaults were checked against the canonical live
-- PostgreSQL schema on 2026-10-03. This fixture is not a baseline migration.
-- Unrelated historical project/provider foreign keys and triggers are omitted;
-- identity/membership/property isolation and local constraints are preserved.
-- auth.users/auth.sessions are synthetic; no production token or session exists.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create schema private;
create schema extensions;
create extension pgcrypto with schema extensions;
create type public.member_role as enum ('owner','admin','operator','member','viewer');
create type public.membership_status as enum ('invited','active','suspended','revoked');
create type public.audit_actor_type as enum ('human','system','provider');
create type auth.aal_level as enum ('aal1','aal2','aal3');
create table auth.users (
 id uuid primary key,
 email text unique,
 is_anonymous boolean not null default false,
 email_confirmed_at timestamptz,
 last_sign_in_at timestamptz,
 banned_until timestamptz,
 deleted_at timestamptz,
 raw_app_meta_data jsonb not null default '{}',
 raw_user_meta_data jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table auth.sessions (
 id uuid primary key,
 user_id uuid not null references auth.users(id),
 aal auth.aal_level not null default 'aal2',
 not_after timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 refreshed_at timestamptz not null default now()
);
create function auth.jwt() returns jsonb language sql stable as $$
 select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb
$$;
create function auth.uid() returns uuid language sql stable as $$
 select nullif(auth.jwt()->>'sub','')::uuid
$$;
create function auth.role() returns text language sql stable as $$
 select nullif(auth.jwt()->>'role','')
$$;
grant usage on schema public,auth to anon,authenticated,service_role;
grant execute on all functions in schema auth to anon,authenticated,service_role;


create table public.organizations (
  id uuid default gen_random_uuid() not null,
  name text not null,
  slug text not null,
  status text default 'active'::text not null,
  created_by uuid not null,
  created_at timestamptz default timezone('utc'::text, now()) not null,
  updated_at timestamptz default timezone('utc'::text, now()) not null
);

create table public.memberships (
  organization_id uuid not null,
  user_id uuid not null,
  role public.member_role not null,
  status public.membership_status default 'invited'::membership_status not null,
  invited_by uuid,
  joined_at timestamptz,
  created_at timestamptz default timezone('utc'::text, now()) not null,
  updated_at timestamptz default timezone('utc'::text, now()) not null
);

create table public.enterprise_properties (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  project_id uuid,
  slug text not null,
  display_name text not null,
  timezone text default 'Asia/Manila'::text not null,
  currency text default 'PHP'::text not null,
  source_status text default 'not_connected'::text not null,
  source_observed_at timestamptz,
  source_message text,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);

create table public.audit_events (
  id int8 generated always as identity not null,
  organization_id uuid not null,
  run_id uuid,
  step_id uuid,
  actor_type public.audit_actor_type not null,
  actor_user_id uuid,
  event_type text not null,
  payload_redacted jsonb default '{}'::jsonb not null,
  previous_hash text,
  event_hash text not null,
  created_at timestamptz default timezone('utc'::text, now()) not null,
  project_id uuid,
  request_id text,
  idempotency_key text,
  resource_type text,
  resource_id uuid,
  action_hash text,
  provenance_redacted jsonb default '{}'::jsonb not null
);

create table public.enterprise_devices (
  entity_id uuid not null,
  organization_id uuid not null,
  entity_kind text default 'device'::text not null,
  owner_entity_id uuid,
  model text,
  device_identifier_hmac_sha256 text,
  capabilities jsonb default '[]'::jsonb not null,
  trust_state text default 'unknown'::text not null,
  created_at timestamptz default clock_timestamp() not null,
  updated_at timestamptz default clock_timestamp() not null
);

create table public.enterprise_integration_connections (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  source_system_key text not null,
  display_name text not null,
  connection_key text not null,
  coexistence_mode text default 'observe'::text not null,
  capability_state text default 'configured'::text not null,
  granted_scopes jsonb default '[]'::jsonb not null,
  metadata_redacted jsonb default '{}'::jsonb not null,
  last_synced_at timestamptz,
  last_error_code text,
  revoked_at timestamptz,
  created_at timestamptz default clock_timestamp() not null,
  updated_at timestamptz default clock_timestamp() not null
);

create table public.enterprise_source_connections (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  property_id uuid not null,
  source_type text not null,
  display_name text not null,
  status text default 'not_connected'::text not null,
  last_success_at timestamptz,
  last_attempt_at timestamptz,
  customer_message text,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);

create table public.enterprise_attention_items (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  property_id uuid not null,
  source_key text not null,
  priority text default 'medium'::text not null,
  category text default 'operations'::text not null,
  title text not null,
  summary text,
  action_prompt text,
  status text default 'open'::text not null,
  occurred_at timestamptz default now() not null,
  due_at timestamptz,
  resolved_at timestamptz,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);

create table public.enterprise_business_activity (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  property_id uuid not null,
  activity_key text not null,
  category text default 'operations'::text not null,
  title text not null,
  summary text,
  occurred_at timestamptz not null,
  source_label text,
  created_at timestamptz default now() not null
);

create table public.enterprise_authority_policies (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  entity_kind text not null,
  field_path text default '*'::text not null,
  authority_kind text not null,
  source_connection_id uuid,
  verification_required bool default true not null,
  conflict_action text default 'manual_review'::text not null,
  policy_version text not null,
  conditions_redacted jsonb default '{}'::jsonb not null,
  effective_from timestamptz default clock_timestamp() not null,
  effective_to timestamptz,
  created_at timestamptz default clock_timestamp() not null,
  superseded_at timestamptz
);

create table public.enterprise_tasks (
  entity_id uuid not null,
  organization_id uuid not null,
  entity_kind text default 'task'::text not null,
  task_type text not null,
  owner_entity_id uuid,
  due_at timestamptz,
  task_state text default 'open'::text not null,
  evidence_required bool default false not null,
  evidence_refs jsonb default '[]'::jsonb not null,
  completed_at timestamptz,
  created_at timestamptz default clock_timestamp() not null,
  updated_at timestamptz default clock_timestamp() not null
);

create table public.enterprise_human_work_items (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  task_entity_id uuid,
  work_key text not null,
  work_state text default 'open'::text not null,
  actor_ref text,
  evidence_refs jsonb default '[]'::jsonb not null,
  resulting_state_ref text,
  created_at timestamptz default clock_timestamp() not null,
  completed_at timestamptz
);

create table public.enterprise_entities (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  entity_kind text not null,
  schema_version text default '1.0.0'::text not null,
  lifecycle_state text default 'active'::text not null,
  created_at timestamptz default clock_timestamp() not null,
  updated_at timestamptz default clock_timestamp() not null,
  archived_at timestamptz
);

create table public.enterprise_contracts (
  entity_id uuid not null,
  organization_id uuid not null,
  entity_kind text default 'contract'::text not null,
  contract_type text not null,
  effective_from timestamptz,
  effective_to timestamptz,
  document_entity_id uuid,
  obligations jsonb default '[]'::jsonb not null,
  provider_constraints jsonb default '{}'::jsonb not null,
  contract_state text default 'draft'::text not null,
  created_at timestamptz default clock_timestamp() not null,
  updated_at timestamptz default clock_timestamp() not null
);

create table public.enterprise_documents (
  entity_id uuid not null,
  organization_id uuid not null,
  entity_kind text default 'document'::text not null,
  document_type text not null,
  owner_entity_id uuid,
  version_number int4 default 1 not null,
  source_record_id uuid,
  parent_document_entity_id uuid,
  content_sha256 text not null,
  retention_until timestamptz,
  media_type text,
  created_at timestamptz default clock_timestamp() not null
);

create table public.pandora_workspace_industry_packs (
  organization_id uuid not null,
  pack_key text not null,
  pack_version text not null,
  activation_state text default 'active'::text not null,
  activated_at timestamptz default clock_timestamp() not null,
  updated_at timestamptz default clock_timestamp() not null
);

create table public.pandora_existing_system_inventory (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  system_key text not null,
  display_name text not null,
  system_type text not null,
  owner_ref text,
  access_path text not null,
  authority_scope jsonb default '[]'::jsonb not null,
  risk_level text default 'medium'::text not null,
  coexistence_mode text default 'observe'::text not null,
  connection_id uuid,
  inventory_state text default 'inventoried'::text not null,
  created_at timestamptz default clock_timestamp() not null,
  updated_at timestamptz default clock_timestamp() not null
);

create table public.pandora_activity_jobs (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  requested_by uuid not null,
  thread_id uuid,
  project_id uuid,
  request_id text not null,
  writer_epoch int8 default 1 not null,
  writer_id text default 'pandora-intelligence-chat'::text not null,
  last_sequence int8 default 0 not null,
  terminal_state text,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  expires_at timestamptz default (now() + '30 days'::interval) not null,
  controls_sealed_at timestamptz,
  request_fingerprint text,
  execution_state text default 'ready'::text not null,
  execution_claim_id uuid,
  execution_generation int8 default 0 not null,
  execution_checkpoint text,
  execution_checkpoint_ref text,
  execution_effect_state text default 'none'::text not null,
  execution_result jsonb,
  execution_error_code text,
  execution_started_at timestamptz,
  execution_updated_at timestamptz
);

create table public.pandora_activity_events (
  job_id uuid not null,
  organization_id uuid not null,
  sequence int8 not null,
  event_id text not null,
  writer_epoch int8 not null,
  state text not null,
  message text not null,
  event jsonb not null,
  occurred_at timestamptz not null,
  admitted_at timestamptz default now() not null,
  expires_at timestamptz default (now() + '30 days'::interval) not null
);

create table public.pandora_activity_controls (
  id uuid default gen_random_uuid() not null,
  job_id uuid not null,
  organization_id uuid not null,
  requested_by uuid not null,
  request_id text not null,
  control_sequence int8 not null,
  control_type text not null,
  instruction text,
  status text default 'requested'::text not null,
  requested_at timestamptz default now() not null,
  accepted_at timestamptz,
  applied_at timestamptz,
  rejection_code text
);

create table public.pandora_provider_activations (
  organization_id uuid not null,
  provider_key text not null,
  manifest_version text not null,
  activation_state text default 'authorized'::text not null,
  granted_capabilities text[] default '{}'::text[] not null,
  granted_scopes text[] default '{}'::text[] not null,
  allowed_regions text[] default '{}'::text[] not null,
  health_state text default 'unknown'::text not null,
  activation_source text default 'manual'::text not null,
  last_verified_at timestamptz,
  updated_at timestamptz default clock_timestamp() not null
);

create table public.pandora_provider_selection_receipts (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  capability_key text not null,
  capability_version text not null,
  requested_mode text not null,
  requested_region text,
  selected_provider text,
  result_state text not null,
  eligible_providers jsonb default '[]'::jsonb not null,
  excluded_providers jsonb default '[]'::jsonb not null,
  score_components jsonb default '[]'::jsonb not null,
  selection_reason text not null,
  approval_required bool default false not null,
  created_at timestamptz default clock_timestamp() not null
);

create table public.pandora_provider_capability_metrics (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  provider_key text not null,
  capability_key text not null,
  capability_version text not null,
  region text default 'global'::text not null,
  window_start timestamptz not null,
  window_end timestamptz not null,
  accepted_count int8 default 0 not null,
  pending_verification_count int8 default 0 not null,
  verified_success_count int8 default 0 not null,
  verified_failure_count int8 default 0 not null,
  p95_latency_ms numeric,
  cost_per_unit numeric,
  observed_at timestamptz default clock_timestamp() not null
);

create table public.pandora_connection_verification_observations_v1 (
  organization_id uuid not null,
  provider_key text not null,
  state text not null,
  observed_at timestamptz not null,
  stale_after timestamptz,
  source text not null,
  missing_reason text,
  evidence_redacted jsonb default '{}'::jsonb not null,
  updated_at timestamptz default clock_timestamp() not null
);

create table public.pandora_cost_entries (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  project_id uuid not null,
  project_spec_id uuid,
  build_job_id uuid,
  model_run_id uuid,
  tool_call_id uuid,
  project_version_id uuid,
  budget_limit_id uuid,
  cost_category text not null,
  provider text,
  environment text,
  quantity numeric default 0 not null,
  unit text default 'unit'::text not null,
  estimated_cost_micros int8 default 0 not null,
  billed_cost_micros int8 default 0 not null,
  charged_cost_micros int8 default 0 not null,
  credit_micros int8 default 0 not null,
  currency text default 'USD'::text not null,
  idempotency_key text not null,
  metadata_redacted jsonb default '{}'::jsonb not null,
  occurred_at timestamptz default now() not null,
  created_at timestamptz default now() not null
);

create table public.pandora_budget_limits (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  project_id uuid not null,
  project_spec_id uuid,
  build_job_id uuid,
  budget_kind text not null,
  scope_key text not null,
  currency text default 'USD'::text not null,
  warning_limit_micros int8 default 0 not null,
  hard_limit_micros int8 not null,
  reserved_micros int8 default 0 not null,
  spent_micros int8 default 0 not null,
  status text default 'active'::text not null,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);

create table public.pandora_project_deployments (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  project_id uuid not null,
  version_id uuid not null,
  provider text default 'vercel'::text not null,
  environment text not null,
  provider_project_id text not null,
  provider_deployment_id text,
  url text,
  status text default 'pending'::text not null,
  source_sha256 text not null,
  promoted_from_id uuid,
  metadata jsonb default '{}'::jsonb not null,
  created_at timestamptz default now() not null,
  artifact_digest text,
  source_commit_sha text,
  authorization_ref text,
  verification_ref text,
  idempotency_key text,
  provider_state text,
  immutable_url text,
  stable_url text,
  last_provider_check_at timestamptz,
  retry_after_at timestamptz,
  ready_at timestamptz,
  failed_at timestamptz,
  cancelled_at timestamptz,
  expires_at timestamptz,
  config_digest text,
  verification_state text default 'not_verified'::text not null,
  updated_at timestamptz default now() not null
);

create table public.pandora_model_runs (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  project_id uuid,
  project_spec_id uuid,
  build_job_id uuid,
  build_job_step_id uuid,
  request_id text not null,
  task text not null,
  output_mode text default 'structured'::text not null,
  status text default 'queued'::text not null,
  provider text,
  model text,
  model_revision text,
  request_sha256 text not null,
  context_sha256 text,
  schema_sha256 text,
  response_sha256 text,
  input_tokens int8 default 0 not null,
  output_tokens int8 default 0 not null,
  total_tokens int8 default 0 not null,
  estimated_cost_micros int8 default 0 not null,
  billed_cost_micros int8 default 0 not null,
  attempt int4 default 1 not null,
  max_attempts int4 default 1 not null,
  error_code text,
  error_public_summary text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz default now() not null,
  provider_request_id text,
  usage_source text,
  cached_input_tokens int8,
  reasoning_tokens int8,
  cost_estimate_status text default 'unavailable'::text not null,
  pricing_version text,
  pricing_source text,
  billing_reconciliation_status text default 'unavailable'::text not null,
  billed_cost_source text,
  reasoning_tier text,
  provider_reasoning_tier text,
  routing_decision_id uuid,
  routing_policy_version text,
  routing_candidates jsonb default '[]'::jsonb not null,
  routing_exclusions jsonb default '[]'::jsonb not null,
  routing_scores jsonb default '{}'::jsonb not null,
  routing_confidence numeric,
  routing_sample_count int8,
  session_stickiness_state text,
  recovery_state text,
  cohort_key text,
  provider_latency_ms int8,
  transport_latency_ms int8,
  time_to_first_token_ms int8,
  stream_completion_latency_ms int8,
  end_to_end_latency_ms int8,
  structured_output_requested bool,
  structured_output_returned bool,
  structured_output_parseable bool,
  structured_output_schema_valid bool,
  structured_output_accepted bool,
  structured_output_regeneration_count int4,
  structured_output_repair_succeeded bool,
  tool_call_emitted bool,
  tool_arguments_valid bool,
  tool_invoked bool,
  tool_execution_succeeded bool,
  tool_state_change_verified bool,
  tool_failure_domain text,
  verification_required bool,
  verifier_run_id uuid,
  verifier_provider text,
  verifier_model text,
  verifier_model_revision text,
  verifier_policy_version text,
  verification_outcome text,
  verification_evidence_ref text,
  final_adjudication text,
  downstream_outcome_status text,
  outcome_evidence_ref text,
  failure_domain text,
  source_queue_id uuid,
  source_dispatch_attempt int4,
  thread_id uuid,
  intelligence_project_id uuid,
  requested_selection_mode text default 'auto'::text not null,
  requested_provider text,
  requested_model text,
  requested_fallback_mode text default 'allow_fallback'::text not null,
  requested_reasoning_mode text default 'auto'::text not null,
  fallback_reason text
);

create table public.pandora_model_attempts (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  project_id uuid,
  run_id uuid not null,
  fallback_chain_id uuid not null,
  attempt_index int4 not null,
  provider text not null,
  model text not null,
  model_revision text,
  provider_request_id text,
  status text not null,
  error_code text,
  failure_domain text,
  error_kind text,
  retryable bool,
  provider_http_status int4,
  fallback_decision text default 'none'::text not null,
  next_provider text,
  next_model text,
  provider_latency_ms int8,
  transport_latency_ms int8,
  observed_at timestamptz default now() not null,
  created_at timestamptz default now() not null,
  thread_id uuid,
  intelligence_project_id uuid
);

create table public.pandora_phone_local_ai_turns (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  user_id uuid not null,
  phase text not null,
  outcome text not null,
  reason text,
  model_name text,
  model_sha256 text,
  created_at timestamptz default now() not null
);

create table public.pandora_local_ai_workers (
  worker_id text not null,
  model text not null,
  status text not null,
  last_seen_at timestamptz default now() not null,
  metadata jsonb default '{}'::jsonb not null
);

create table public.pandora_verified_learning_outbox (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  activity_job_id uuid not null,
  thread_id uuid,
  idempotency_key text not null,
  memory_project_id uuid not null,
  namespace text default 'real_life'::text not null,
  learning_kind text not null,
  learning_summary text not null,
  promotion_basis text not null,
  confidence numeric not null,
  execution jsonb not null,
  incident_verification_ref text,
  additional_evidence_refs text[] default '{}'::text[] not null,
  state text default 'pending'::text not null,
  attempt_count int4 default 0 not null,
  lease_until timestamptz,
  memory_candidate_id uuid,
  memory_review_item_id uuid,
  last_error_code text,
  delivered_at timestamptz,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  claim_token uuid
);

create table private.pandora_connection_accounts_v1 (
  id uuid default extensions.gen_random_uuid() not null,
  organization_id uuid not null,
  provider_key text not null,
  manifest_version text not null,
  connected_by uuid not null,
  account_subject_hash text not null,
  account_label text not null,
  tenant_key text not null,
  tenant_label text,
  credential_secret_id uuid not null,
  credential_version int4 default 1 not null,
  granted_scopes text[] default ARRAY[]::text[] not null,
  granted_capabilities text[] default ARRAY[]::text[] not null,
  status text default 'connected'::text not null,
  health_state text default 'unknown'::text not null,
  last_verified_at timestamptz,
  credential_expires_at timestamptz,
  rotation_due_at timestamptz,
  revoked_at timestamptz,
  failure_code text,
  provider_readback_hash text,
  metadata_redacted jsonb default '{}'::jsonb not null,
  created_at timestamptz default clock_timestamp() not null,
  updated_at timestamptz default clock_timestamp() not null
);

create table private.pandora_connection_active_accounts_v1 (
  organization_id uuid not null,
  provider_key text not null,
  connection_id uuid not null,
  tenant_key text not null,
  selected_by uuid not null,
  selected_at timestamptz default clock_timestamp() not null
);

create table private.pandora_ops_tasks (
  organization_id uuid not null,
  project_id uuid not null,
  task_key text not null,
  spec jsonb not null,
  spec_digest text not null,
  status text default 'queued'::text not null,
  revision int8 default 0 not null,
  attempts int4 default 0 not null,
  generation int8 default 0 not null,
  cancel_requested bool default false not null,
  queued_at timestamptz default clock_timestamp() not null,
  builder_worker_key text,
  builder_principal_key text,
  head_sha text,
  handoff jsonb,
  verification jsonb
);

create table private.pandora_ops_human_gates (
  organization_id uuid not null,
  project_id uuid not null,
  task_key text not null,
  gate_kind text not null,
  state text default 'blocked'::text not null,
  evidence_ref text not null,
  decided_at timestamptz,
  updated_at timestamptz default clock_timestamp() not null
);

create table private.pandora_ops_workspaces (
  organization_id uuid not null,
  project_id uuid not null,
  paused bool default true not null,
  no_production bool default true not null,
  revision int8 default 0 not null,
  max_concurrency int4 default 1 not null,
  total_budget_micros int8 default 0 not null,
  reserved_micros int8 default 0 not null,
  spent_micros int8 default 0 not null,
  updated_at timestamptz default clock_timestamp() not null
);

create table private.pandora_ops_workers (
  organization_id uuid not null,
  project_id uuid not null,
  worker_key text not null,
  principal_key text not null,
  engine text not null,
  lanes text[] not null,
  capabilities text[] default '{}'::text[] not null,
  capacity int4 not null,
  acknowledged bool default false not null,
  connected bool default false not null,
  health text default 'offline'::text not null,
  heartbeat_at timestamptz,
  registration_receipt text not null
);

create table private.pandora_ops_events (
  id int8 not null,
  organization_id uuid not null,
  project_id uuid not null,
  event_key text not null,
  task_key text,
  event_type text not null,
  receipt_ref text,
  occurred_at timestamptz default clock_timestamp() not null
);

create table private.pandora_ops_inference_requests (
  id uuid not null,
  organization_id uuid not null,
  project_id uuid not null,
  task_key text not null,
  worker_key text not null,
  principal_key text not null,
  caller_digest text not null,
  lease_id uuid not null,
  generation int8 not null,
  source_sha text not null,
  task_class text not null,
  request_digest text not null,
  metadata jsonb not null,
  max_cost_micros int8 not null,
  state text default 'admitted'::text not null,
  cancel_requested bool default false not null,
  selected_attempt uuid,
  verification_run_id uuid,
  created_at timestamptz default clock_timestamp() not null,
  completed_at timestamptz
);

create table private.pandora_ops_inference_attempts (
  id uuid default gen_random_uuid() not null,
  request_id uuid not null,
  organization_id uuid not null,
  project_id uuid not null,
  ordinal int4 not null,
  model_key text not null,
  model_snapshot jsonb not null,
  policy_digest text not null,
  circuit_generation int8 default 0 not null,
  state text default 'prepared'::text not null,
  reserved_micros int8 not null,
  billed_micros int8,
  receipt jsonb,
  billing_receipt text,
  created_at timestamptz default clock_timestamp() not null,
  completed_at timestamptz
);

create table private.pandora_ops_merged_release_receipts (
  id uuid not null,
  organization_id uuid not null,
  project_id uuid not null,
  task_key text not null,
  prior_generation int8 not null,
  adopted_generation int8 not null,
  prior_revision int8 not null,
  task_spec_digest text not null,
  prior_head_sha text not null,
  head_sha text not null,
  merge_sha text not null,
  canonical_main_sha text not null,
  repository text not null,
  pull_request int4 not null,
  reconciler_worker_key text not null,
  reconciler_principal_key text not null,
  prior_task jsonb not null,
  provider_readback jsonb not null,
  created_at timestamptz default clock_timestamp() not null
);

alter table private.pandora_connection_accounts_v1 add constraint pandora_connection_accounts_v1_account_label_check CHECK (length(account_label) >= 1 AND length(account_label) <= 320);

alter table private.pandora_connection_accounts_v1 add constraint pandora_connection_accounts_v1_account_subject_hash_check CHECK (account_subject_hash ~ '^[0-9a-f]{64}$'::text);

alter table private.pandora_connection_accounts_v1 add constraint pandora_connection_accounts_v1_credential_version_check CHECK (credential_version > 0);

alter table private.pandora_connection_accounts_v1 add constraint pandora_connection_accounts_v1_health_state_check CHECK (health_state = ANY (ARRAY['healthy'::text, 'degraded'::text, 'unhealthy'::text, 'unknown'::text]));

alter table private.pandora_connection_accounts_v1 add constraint pandora_connection_accounts_v1_metadata_redacted_check CHECK (jsonb_typeof(metadata_redacted) = 'object'::text);

alter table private.pandora_connection_accounts_v1 add constraint pandora_connection_accounts_v1_pkey PRIMARY KEY (id);

alter table private.pandora_connection_accounts_v1 add constraint pandora_connection_accounts_v1_provider_readback_hash_check CHECK (provider_readback_hash IS NULL OR provider_readback_hash ~ '^[0-9a-f]{64}$'::text);

alter table private.pandora_connection_accounts_v1 add constraint pandora_connection_accounts_v1_status_check CHECK (status = ANY (ARRAY['connected'::text, 'needs_attention'::text, 'revoked'::text]));

alter table private.pandora_connection_accounts_v1 add constraint pandora_connection_accounts_v1_tenant_key_check CHECK (length(tenant_key) >= 1 AND length(tenant_key) <= 320);

alter table private.pandora_connection_accounts_v1 add constraint pandora_connection_accounts_v_id_organization_id_provider_k_key UNIQUE (id, organization_id, provider_key, tenant_key);

alter table private.pandora_connection_accounts_v1 add constraint pandora_connection_accounts_v_organization_id_provider_key__key UNIQUE (organization_id, provider_key, account_subject_hash, tenant_key);

alter table private.pandora_connection_accounts_v1 add constraint pandora_google_connected_exact_read_scopes_v2 CHECK (provider_key <> 'google_workspace'::text OR status <> 'connected'::text OR cardinality(granted_scopes) = 5 AND array_position(granted_scopes, NULL::text) IS NULL AND ARRAY['openid'::text, 'email'::text, 'profile'::text, 'https://www.googleapis.com/auth/drive.metadata.readonly'::text, 'https://www.googleapis.com/auth/spreadsheets.readonly'::text] <@ granted_scopes AND granted_scopes <@ ARRAY['openid'::text, 'email'::text, 'profile'::text, 'https://www.googleapis.com/auth/drive.metadata.readonly'::text, 'https://www.googleapis.com/auth/spreadsheets.readonly'::text]);

alter table private.pandora_connection_active_accounts_v1 add constraint pandora_connection_active_accounts_v1_pkey PRIMARY KEY (organization_id, provider_key);

alter table private.pandora_connection_active_accounts_v1 add constraint pandora_connection_active_accounts_v1_tenant_key_check CHECK (length(tenant_key) >= 1 AND length(tenant_key) <= 320);

alter table private.pandora_ops_merged_release_receipts add constraint pandora_ops_merged_release_re_organization_id_project_id_ta_key UNIQUE (organization_id, project_id, task_key, prior_generation);

alter table private.pandora_ops_merged_release_receipts add constraint pandora_ops_merged_release_receipts_check CHECK (adopted_generation = (prior_generation + 1));

alter table private.pandora_ops_merged_release_receipts add constraint pandora_ops_merged_release_receipts_check1 CHECK (prior_generation > 0 AND prior_revision >= 0 AND pull_request > 0);

alter table private.pandora_ops_merged_release_receipts add constraint pandora_ops_merged_release_receipts_check2 CHECK (prior_head_sha ~ '^[a-f0-9]{40}$'::text AND head_sha ~ '^[a-f0-9]{40}$'::text AND merge_sha ~ '^[a-f0-9]{40}$'::text AND canonical_main_sha ~ '^[a-f0-9]{40}$'::text);

alter table private.pandora_ops_merged_release_receipts add constraint pandora_ops_merged_release_receipts_pkey PRIMARY KEY (id);

alter table private.pandora_ops_merged_release_receipts add constraint pandora_ops_merged_release_receipts_task_spec_digest_check CHECK (task_spec_digest ~ '^[a-f0-9]{64}$'::text);

alter table public.audit_events add constraint audit_events_event_hash_check CHECK (event_hash ~ '^[0-9a-f]{64}$'::text);

alter table public.audit_events add constraint audit_events_event_hash_key UNIQUE (event_hash);

alter table public.audit_events add constraint audit_events_pkey PRIMARY KEY (id);

alter table public.audit_events add constraint audit_events_previous_hash_check CHECK (previous_hash IS NULL OR previous_hash ~ '^[0-9a-f]{64}$'::text);

alter table public.audit_events add constraint audit_events_worker_a_action_hash_check CHECK (action_hash IS NULL OR action_hash ~ '^[0-9a-f]{64}$'::text);

alter table public.enterprise_attention_items add constraint enterprise_attention_items_pkey PRIMARY KEY (id);

alter table public.enterprise_attention_items add constraint enterprise_attention_items_priority_check CHECK (priority = ANY (ARRAY['critical'::text, 'high'::text, 'medium'::text, 'low'::text]));

alter table public.enterprise_attention_items add constraint enterprise_attention_items_property_id_source_key_key UNIQUE (property_id, source_key);

alter table public.enterprise_attention_items add constraint enterprise_attention_items_status_check CHECK (status = ANY (ARRAY['open'::text, 'acknowledged'::text, 'resolved'::text, 'dismissed'::text]));

alter table public.enterprise_authority_policies add constraint enterprise_authority_policies_authority_kind_check CHECK (authority_kind = ANY (ARRAY['source_of_record'::text, 'pandora_derived'::text, 'advisory'::text, 'fallback_source'::text]));

alter table public.enterprise_authority_policies add constraint enterprise_authority_policies_check CHECK (effective_to IS NULL OR effective_to >= effective_from);

alter table public.enterprise_authority_policies add constraint enterprise_authority_policies_check1 CHECK (authority_kind = 'pandora_derived'::text AND source_connection_id IS NULL OR (authority_kind = ANY (ARRAY['source_of_record'::text, 'advisory'::text, 'fallback_source'::text])) AND source_connection_id IS NOT NULL);

alter table public.enterprise_authority_policies add constraint enterprise_authority_policies_conditions_redacted_check CHECK (jsonb_typeof(conditions_redacted) = 'object'::text);

alter table public.enterprise_authority_policies add constraint enterprise_authority_policies_conflict_action_check CHECK (conflict_action = ANY (ARRAY['block'::text, 'manual_review'::text, 'retain_current'::text, 'recompute'::text]));

alter table public.enterprise_authority_policies add constraint enterprise_authority_policies_field_path_check CHECK (field_path = '*'::text OR field_path ~ '^[a-z][a-z0-9_.]{0,254}$'::text);

alter table public.enterprise_authority_policies add constraint enterprise_authority_policies_id_organization_id_key UNIQUE (id, organization_id);

alter table public.enterprise_authority_policies add constraint enterprise_authority_policies_pkey PRIMARY KEY (id);

alter table public.enterprise_authority_policies add constraint enterprise_authority_policies_policy_version_check CHECK (policy_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'::text);

alter table public.enterprise_business_activity add constraint enterprise_business_activity_pkey PRIMARY KEY (id);

alter table public.enterprise_business_activity add constraint enterprise_business_activity_property_id_activity_key_key UNIQUE (property_id, activity_key);

alter table public.enterprise_contracts add constraint enterprise_contracts_check CHECK (effective_to IS NULL OR effective_from IS NULL OR effective_to >= effective_from);

alter table public.enterprise_contracts add constraint enterprise_contracts_contract_state_check CHECK (contract_state = ANY (ARRAY['draft'::text, 'active'::text, 'expired'::text, 'terminated'::text]));

alter table public.enterprise_contracts add constraint enterprise_contracts_contract_type_check CHECK (contract_type ~ '^[a-z][a-z0-9_]{0,63}$'::text);

alter table public.enterprise_contracts add constraint enterprise_contracts_entity_id_organization_id_key UNIQUE (entity_id, organization_id);

alter table public.enterprise_contracts add constraint enterprise_contracts_entity_kind_check CHECK (entity_kind = 'contract'::text);

alter table public.enterprise_contracts add constraint enterprise_contracts_obligations_check CHECK (jsonb_typeof(obligations) = 'array'::text);

alter table public.enterprise_contracts add constraint enterprise_contracts_pkey PRIMARY KEY (entity_id);

alter table public.enterprise_contracts add constraint enterprise_contracts_provider_constraints_check CHECK (jsonb_typeof(provider_constraints) = 'object'::text);

alter table public.enterprise_devices add constraint enterprise_devices_capabilities_check CHECK (jsonb_typeof(capabilities) = 'array'::text);

alter table public.enterprise_devices add constraint enterprise_devices_device_identifier_hmac_sha256_check CHECK (device_identifier_hmac_sha256 IS NULL OR device_identifier_hmac_sha256 ~ '^[0-9a-f]{64}$'::text);

alter table public.enterprise_devices add constraint enterprise_devices_entity_id_organization_id_key UNIQUE (entity_id, organization_id);

alter table public.enterprise_devices add constraint enterprise_devices_entity_kind_check CHECK (entity_kind = 'device'::text);

alter table public.enterprise_devices add constraint enterprise_devices_pkey PRIMARY KEY (entity_id);

alter table public.enterprise_devices add constraint enterprise_devices_trust_state_check CHECK (trust_state = ANY (ARRAY['unknown'::text, 'trusted'::text, 'restricted'::text, 'revoked'::text]));

alter table public.enterprise_documents add constraint enterprise_documents_content_sha256_check CHECK (content_sha256 ~ '^[0-9a-f]{64}$'::text);

alter table public.enterprise_documents add constraint enterprise_documents_document_type_check CHECK (document_type ~ '^[a-z][a-z0-9_]{0,63}$'::text);

alter table public.enterprise_documents add constraint enterprise_documents_entity_id_organization_id_key UNIQUE (entity_id, organization_id);

alter table public.enterprise_documents add constraint enterprise_documents_entity_kind_check CHECK (entity_kind = 'document'::text);

alter table public.enterprise_documents add constraint enterprise_documents_pkey PRIMARY KEY (entity_id);

alter table public.enterprise_documents add constraint enterprise_documents_version_number_check CHECK (version_number >= 1);

alter table public.enterprise_entities add constraint enterprise_entities_check CHECK (lifecycle_state = 'archived'::text AND archived_at IS NOT NULL OR lifecycle_state <> 'archived'::text AND archived_at IS NULL);

alter table public.enterprise_entities add constraint enterprise_entities_id_organization_id_entity_kind_key UNIQUE (id, organization_id, entity_kind);

alter table public.enterprise_entities add constraint enterprise_entities_id_organization_id_key UNIQUE (id, organization_id);

alter table public.enterprise_entities add constraint enterprise_entities_lifecycle_state_check CHECK (lifecycle_state = ANY (ARRAY['active'::text, 'archived'::text, 'superseded'::text]));

alter table public.enterprise_entities add constraint enterprise_entities_pkey PRIMARY KEY (id);

alter table public.enterprise_entities add constraint enterprise_entities_schema_version_check CHECK (schema_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'::text);

alter table public.enterprise_human_work_items add constraint enterprise_human_work_items_check CHECK (work_state = 'completed'::text AND completed_at IS NOT NULL AND jsonb_array_length(evidence_refs) > 0 OR work_state <> 'completed'::text);

alter table public.enterprise_human_work_items add constraint enterprise_human_work_items_evidence_refs_check CHECK (jsonb_typeof(evidence_refs) = 'array'::text);

alter table public.enterprise_human_work_items add constraint enterprise_human_work_items_id_organization_id_key UNIQUE (id, organization_id);

alter table public.enterprise_human_work_items add constraint enterprise_human_work_items_organization_id_work_key_key UNIQUE (organization_id, work_key);

alter table public.enterprise_human_work_items add constraint enterprise_human_work_items_pkey PRIMARY KEY (id);

alter table public.enterprise_human_work_items add constraint enterprise_human_work_items_work_key_check CHECK (work_key ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,159}$'::text);

alter table public.enterprise_human_work_items add constraint enterprise_human_work_items_work_state_check CHECK (work_state = ANY (ARRAY['open'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text]));

alter table public.enterprise_integration_connections add constraint enterprise_integration_connec_organization_id_source_system_key UNIQUE (organization_id, source_system_key, connection_key);

alter table public.enterprise_integration_connections add constraint enterprise_integration_connections_capability_state_check CHECK (capability_state = ANY (ARRAY['configured'::text, 'connecting'::text, 'healthy'::text, 'stale'::text, 'error'::text, 'revoked'::text]));

alter table public.enterprise_integration_connections add constraint enterprise_integration_connections_check CHECK (capability_state = 'revoked'::text AND revoked_at IS NOT NULL OR capability_state <> 'revoked'::text AND revoked_at IS NULL);

alter table public.enterprise_integration_connections add constraint enterprise_integration_connections_coexistence_mode_check CHECK (coexistence_mode = ANY (ARRAY['observe'::text, 'synchronize'::text, 'coordinate'::text, 'replace'::text]));

alter table public.enterprise_integration_connections add constraint enterprise_integration_connections_connection_key_check CHECK (connection_key ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,159}$'::text);

alter table public.enterprise_integration_connections add constraint enterprise_integration_connections_display_name_check CHECK (char_length(display_name) >= 1 AND char_length(display_name) <= 200);

alter table public.enterprise_integration_connections add constraint enterprise_integration_connections_granted_scopes_check CHECK (jsonb_typeof(granted_scopes) = 'array'::text AND jsonb_array_length(granted_scopes) <= 128);

alter table public.enterprise_integration_connections add constraint enterprise_integration_connections_id_organization_id_key UNIQUE (id, organization_id);

alter table public.enterprise_integration_connections add constraint enterprise_integration_connections_last_error_code_check CHECK (last_error_code IS NULL OR char_length(last_error_code) <= 160);

alter table public.enterprise_integration_connections add constraint enterprise_integration_connections_metadata_redacted_check CHECK (jsonb_typeof(metadata_redacted) = 'object'::text);

alter table public.enterprise_integration_connections add constraint enterprise_integration_connections_pkey PRIMARY KEY (id);

alter table public.enterprise_integration_connections add constraint enterprise_integration_connections_source_system_key_check CHECK (source_system_key ~ '^[a-z][a-z0-9_.:-]{1,127}$'::text);

alter table public.enterprise_properties add constraint enterprise_properties_id_organization_id_key UNIQUE (id, organization_id);

alter table public.enterprise_properties add constraint enterprise_properties_organization_id_slug_key UNIQUE (organization_id, slug);

alter table public.enterprise_properties add constraint enterprise_properties_pkey PRIMARY KEY (id);

alter table public.enterprise_properties add constraint enterprise_properties_source_status_check CHECK (source_status = ANY (ARRAY['not_connected'::text, 'connecting'::text, 'healthy'::text, 'stale'::text, 'error'::text]));

alter table public.enterprise_source_connections add constraint enterprise_source_connections_pkey PRIMARY KEY (id);

alter table public.enterprise_source_connections add constraint enterprise_source_connections_property_id_source_type_key UNIQUE (property_id, source_type);

alter table public.enterprise_source_connections add constraint enterprise_source_connections_status_check CHECK (status = ANY (ARRAY['not_connected'::text, 'connecting'::text, 'healthy'::text, 'stale'::text, 'error'::text]));

alter table public.enterprise_tasks add constraint enterprise_tasks_check CHECK (task_state = 'completed'::text AND completed_at IS NOT NULL OR task_state <> 'completed'::text AND completed_at IS NULL);

alter table public.enterprise_tasks add constraint enterprise_tasks_entity_id_organization_id_key UNIQUE (entity_id, organization_id);

alter table public.enterprise_tasks add constraint enterprise_tasks_entity_kind_check CHECK (entity_kind = 'task'::text);

alter table public.enterprise_tasks add constraint enterprise_tasks_evidence_refs_check CHECK (jsonb_typeof(evidence_refs) = 'array'::text);

alter table public.enterprise_tasks add constraint enterprise_tasks_pkey PRIMARY KEY (entity_id);

alter table public.enterprise_tasks add constraint enterprise_tasks_task_state_check CHECK (task_state = ANY (ARRAY['open'::text, 'in_progress'::text, 'blocked'::text, 'completed'::text, 'cancelled'::text]));

alter table public.enterprise_tasks add constraint enterprise_tasks_task_type_check CHECK (task_type ~ '^[a-z][a-z0-9_]{0,63}$'::text);

alter table public.memberships add constraint memberships_check CHECK (status = 'active'::membership_status AND joined_at IS NOT NULL OR status <> 'active'::membership_status);

alter table public.memberships add constraint memberships_pkey PRIMARY KEY (organization_id, user_id);

alter table public.organizations add constraint organizations_name_check CHECK (char_length(name) >= 1 AND char_length(name) <= 160);

alter table public.organizations add constraint organizations_pkey PRIMARY KEY (id);

alter table public.organizations add constraint organizations_slug_check CHECK (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'::text);

alter table public.organizations add constraint organizations_slug_key UNIQUE (slug);

alter table public.organizations add constraint organizations_status_check CHECK (status = ANY (ARRAY['active'::text, 'suspended'::text, 'closed'::text]));

alter table public.pandora_budget_limits add constraint pandora_budget_limits_amount_check CHECK (warning_limit_micros >= 0 AND hard_limit_micros >= 0 AND warning_limit_micros <= hard_limit_micros AND reserved_micros >= 0 AND spent_micros >= 0 AND (reserved_micros + spent_micros) <= hard_limit_micros);

alter table public.pandora_budget_limits add constraint pandora_budget_limits_currency_check CHECK (currency ~ '^[A-Z]{3}$'::text);

alter table public.pandora_budget_limits add constraint pandora_budget_limits_kind_check CHECK (budget_kind = ANY (ARRAY['project'::text, 'build'::text, 'model'::text, 'verification'::text, 'deployment'::text, 'runtime'::text, 'provider'::text]));

alter table public.pandora_budget_limits add constraint pandora_budget_limits_pkey PRIMARY KEY (id);


alter table public.pandora_budget_limits add constraint pandora_budget_limits_scope_key_check CHECK (length(TRIM(BOTH FROM scope_key)) >= 1 AND length(TRIM(BOTH FROM scope_key)) <= 160);

alter table public.pandora_budget_limits add constraint pandora_budget_limits_status_check CHECK (status = ANY (ARRAY['active'::text, 'exhausted'::text, 'closed'::text]));

alter table public.pandora_connection_verification_observations_v1 add constraint pandora_connection_verification_observa_evidence_redacted_check CHECK (jsonb_typeof(evidence_redacted) = 'object'::text);

alter table public.pandora_connection_verification_observations_v1 add constraint pandora_connection_verification_observations_provider_key_check CHECK (provider_key ~ '^[a-z0-9][a-z0-9._-]{1,79}$'::text);

alter table public.pandora_connection_verification_observations_v1 add constraint pandora_connection_verification_observations_v1_pkey PRIMARY KEY (organization_id, provider_key);

alter table public.pandora_connection_verification_observations_v1 add constraint pandora_connection_verification_observations_v1_source_check CHECK (length(source) >= 3 AND length(source) <= 120);

alter table public.pandora_connection_verification_observations_v1 add constraint pandora_connection_verification_observations_v1_state_check CHECK (state = ANY (ARRAY['verified'::text, 'partial'::text, 'not_connected'::text, 'error'::text]));

alter table public.pandora_cost_entries add constraint pandora_cost_entries_amount_check CHECK (estimated_cost_micros >= 0 AND billed_cost_micros >= 0 AND charged_cost_micros >= 0 AND credit_micros >= 0);

alter table public.pandora_cost_entries add constraint pandora_cost_entries_category_check CHECK (cost_category = ANY (ARRAY['model'::text, 'build_compute'::text, 'verification'::text, 'deployment'::text, 'runtime'::text, 'storage'::text, 'network'::text, 'provider_api'::text, 'other'::text]));

alter table public.pandora_cost_entries add constraint pandora_cost_entries_currency_check CHECK (currency ~ '^[A-Z]{3}$'::text);

alter table public.pandora_cost_entries add constraint pandora_cost_entries_environment_check CHECK (environment IS NULL OR (environment = ANY (ARRAY['development'::text, 'sandbox'::text, 'test'::text, 'preview'::text, 'production'::text])));

alter table public.pandora_cost_entries add constraint pandora_cost_entries_idempotency_check CHECK (length(TRIM(BOTH FROM idempotency_key)) >= 8 AND length(TRIM(BOTH FROM idempotency_key)) <= 200);


alter table public.pandora_cost_entries add constraint pandora_cost_entries_pkey PRIMARY KEY (id);


alter table public.pandora_cost_entries add constraint pandora_cost_entries_quantity_check CHECK (quantity >= 0::numeric);

alter table public.pandora_project_deployments add constraint pandora_project_deployments_artifact_digest_check CHECK (artifact_digest IS NULL OR artifact_digest ~ '^[0-9a-f]{64}$'::text) NOT VALID;

alter table public.pandora_project_deployments add constraint pandora_project_deployments_config_digest_check CHECK (config_digest IS NULL OR config_digest ~ '^[0-9a-f]{64}$'::text) NOT VALID;

alter table public.pandora_project_deployments add constraint pandora_project_deployments_environment_v2_check CHECK (environment = ANY (ARRAY['development'::text, 'preview'::text, 'production'::text])) NOT VALID;

alter table public.pandora_project_deployments add constraint pandora_project_deployments_pkey PRIMARY KEY (id);

alter table public.pandora_project_deployments add constraint pandora_project_deployments_provider_nonempty_check CHECK (provider ~ '^[a-z][a-z0-9_-]{1,31}$'::text) NOT VALID;

alter table public.pandora_project_deployments add constraint pandora_project_deployments_sha_check CHECK (source_sha256 ~ '^[0-9a-f]{64}$'::text);

alter table public.pandora_project_deployments add constraint pandora_project_deployments_source_commit_check CHECK (source_commit_sha IS NULL OR source_commit_sha ~ '^([0-9a-f]{40}|[0-9a-f]{64})$'::text) NOT VALID;

alter table public.pandora_project_deployments add constraint pandora_project_deployments_verification_state_check CHECK (verification_state = ANY (ARRAY['not_verified'::text, 'ready_for_verification'::text, 'live_verified'::text, 'failed'::text, 'stale'::text])) NOT VALID;

alter table public.pandora_provider_capability_metrics add constraint pandora_provider_capability_m_organization_id_provider_key__key UNIQUE (organization_id, provider_key, capability_key, capability_version, region, window_start, window_end);

alter table public.pandora_provider_capability_metrics add constraint pandora_provider_capability_me_pending_verification_count_check CHECK (pending_verification_count >= 0);

alter table public.pandora_provider_capability_metrics add constraint pandora_provider_capability_metric_verified_failure_count_check CHECK (verified_failure_count >= 0);

alter table public.pandora_provider_capability_metrics add constraint pandora_provider_capability_metric_verified_success_count_check CHECK (verified_success_count >= 0);

alter table public.pandora_provider_capability_metrics add constraint pandora_provider_capability_metrics_accepted_count_check CHECK (accepted_count >= 0);

alter table public.pandora_provider_capability_metrics add constraint pandora_provider_capability_metrics_check CHECK (window_end >= window_start);

alter table public.pandora_provider_capability_metrics add constraint pandora_provider_capability_metrics_check1 CHECK ((verified_success_count + verified_failure_count) <= accepted_count);

alter table public.pandora_provider_capability_metrics add constraint pandora_provider_capability_metrics_cost_per_unit_check CHECK (cost_per_unit IS NULL OR cost_per_unit >= 0::numeric);

alter table public.pandora_provider_capability_metrics add constraint pandora_provider_capability_metrics_p95_latency_ms_check CHECK (p95_latency_ms IS NULL OR p95_latency_ms >= 0::numeric);

alter table public.pandora_provider_capability_metrics add constraint pandora_provider_capability_metrics_pkey PRIMARY KEY (id);

alter table public.pandora_activity_jobs add primary key(id);

alter table public.pandora_activity_events add primary key(job_id,sequence);

alter table public.pandora_activity_controls add primary key(id);

alter table public.pandora_workspace_industry_packs add primary key(organization_id,pack_key);

alter table public.pandora_existing_system_inventory add primary key(id);

alter table public.pandora_model_runs add primary key(id);

alter table public.pandora_model_attempts add primary key(id);

alter table public.pandora_phone_local_ai_turns add primary key(id);

alter table public.pandora_local_ai_workers add primary key(worker_id);

alter table public.pandora_verified_learning_outbox add primary key(id);

alter table private.pandora_ops_tasks add primary key(organization_id,project_id,task_key);

alter table private.pandora_ops_human_gates add primary key(organization_id,project_id,task_key,gate_kind);

alter table private.pandora_ops_workspaces add primary key(organization_id,project_id);


alter table public.memberships add foreign key(organization_id) references public.organizations(id);
alter table public.memberships add foreign key(user_id) references auth.users(id);
alter table public.enterprise_properties add foreign key(organization_id) references public.organizations(id);
create function private.set_updated_at() returns trigger language plpgsql set search_path='' as $$begin new.updated_at=now();return new;end$$;


CREATE OR REPLACE FUNCTION private.has_org_role(target_organization_id uuid, allowed_roles member_role[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select (select auth.uid()) is not null
    and coalesce((select auth.jwt() ->> 'is_anonymous'), 'false') <> 'true'
    and exists (
      select 1
      from public.memberships membership
      where membership.organization_id = target_organization_id
        and membership.user_id = (select auth.uid())
        and membership.status = 'active'::public.membership_status
        and membership.role = any(allowed_roles)
    );
$function$;


CREATE OR REPLACE FUNCTION private.is_org_member(target_organization_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select (select auth.uid()) is not null
    and coalesce((select auth.jwt() ->> 'is_anonymous'), 'false') <> 'true'
    and exists (
      select 1
      from public.memberships membership
      where membership.organization_id = target_organization_id
        and membership.user_id = (select auth.uid())
        and membership.status = 'active'::public.membership_status
    );
$function$;


revoke all on function private.is_org_member(uuid), private.has_org_role(uuid,public.member_role[]) from public,anon;
grant execute on function private.is_org_member(uuid), private.has_org_role(uuid,public.member_role[]) to authenticated,service_role;

alter table public.organizations enable row level security;
alter table public.memberships enable row level security;
alter table public.enterprise_properties enable row level security;

create policy enterprise_properties_member_read on public.enterprise_properties as PERMISSIVE for SELECT to authenticated using (private.is_org_member(organization_id));

create policy memberships_delete_admin on public.memberships as PERMISSIVE for DELETE to authenticated using ((private.has_org_role(organization_id, ARRAY['owner'::member_role]) OR (private.has_org_role(organization_id, ARRAY['admin'::member_role]) AND (role = ANY (ARRAY['operator'::member_role, 'member'::member_role, 'viewer'::member_role])))));

create policy memberships_insert_admin on public.memberships as PERMISSIVE for INSERT to authenticated with check ((private.has_org_role(organization_id, ARRAY['owner'::member_role, 'admin'::member_role]) AND (private.has_org_role(organization_id, ARRAY['owner'::member_role]) OR (role = ANY (ARRAY['operator'::member_role, 'member'::member_role, 'viewer'::member_role])))));

create policy memberships_select_org on public.memberships as PERMISSIVE for SELECT to authenticated using (private.is_org_member(organization_id));

create policy memberships_update_admin on public.memberships as PERMISSIVE for UPDATE to authenticated using (private.has_org_role(organization_id, ARRAY['owner'::member_role, 'admin'::member_role])) with check ((private.has_org_role(organization_id, ARRAY['owner'::member_role]) OR (private.has_org_role(organization_id, ARRAY['admin'::member_role]) AND (role = ANY (ARRAY['operator'::member_role, 'member'::member_role, 'viewer'::member_role])))));

create policy organizations_select_member on public.organizations as PERMISSIVE for SELECT to authenticated using (((created_by = ( SELECT auth.uid() AS uid)) OR private.is_org_member(id)));

create policy organizations_update_admin on public.organizations as PERMISSIVE for UPDATE to authenticated using (private.has_org_role(id, ARRAY['owner'::member_role, 'admin'::member_role])) with check (private.has_org_role(id, ARRAY['owner'::member_role, 'admin'::member_role]));

grant select,update on public.organizations to authenticated;
grant select,insert,update,delete on public.memberships to authenticated;
grant select on public.enterprise_properties to authenticated;
grant all on all tables in schema public,private to service_role;

create or replace function private.append_audit_event(
  target_organization_id uuid,
  target_run_id uuid,
  target_step_id uuid,
  target_actor_type public.audit_actor_type,
  target_actor_user_id uuid,
  target_event_type text,
  target_payload jsonb
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  prior_hash text;
  created_timestamp timestamptz := clock_timestamp();
  calculated_hash text;
  inserted_id bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended(target_organization_id::text, 0));

  select event_hash
    into prior_hash
  from public.audit_events
  where organization_id = target_organization_id
  order by id desc
  limit 1;

  calculated_hash := encode(
    extensions.digest(
      concat_ws(
        '|',
        target_organization_id::text,
        coalesce(target_run_id::text, ''),
        coalesce(target_step_id::text, ''),
        target_actor_type::text,
        coalesce(target_actor_user_id::text, ''),
        target_event_type,
        coalesce(target_payload, '{}'::jsonb)::text,
        coalesce(prior_hash, ''),
        created_timestamp::text
      ),
      'sha256'
    ),
    'hex'
  );

  insert into public.audit_events (
    organization_id, run_id, step_id, actor_type, actor_user_id,
    event_type, payload_redacted, previous_hash, event_hash, created_at
  )
  values (
    target_organization_id, target_run_id, target_step_id, target_actor_type,
    target_actor_user_id, target_event_type, coalesce(target_payload, '{}'::jsonb),
    prior_hash, calculated_hash, created_timestamp
  )
  returning id into inserted_id;

  return inserted_id;
end;
$$;



revoke all on function private.append_audit_event(uuid,uuid,uuid,public.audit_actor_type,uuid,text,jsonb) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.pandora_admin_add_organization_member(p_actor_user_id uuid, p_organization_id uuid, p_target_user_id uuid, p_role member_role)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor_user_id uuid := p_actor_user_id;
  actor_role public.member_role;
  target_confirmed boolean;
  target_anonymous boolean;
  existing_membership public.memberships%rowtype;
  desired_status public.membership_status;
  changed_at timestamptz := clock_timestamp();
  audit_event_type text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service-role broker required'
      using errcode = '42501';
  end if;

  if actor_user_id is null
     or not exists (
       select 1
       from auth.users caller
       where caller.id = actor_user_id
         and coalesce(caller.is_anonymous, false) = false
     ) then
    raise exception 'existing non-anonymous administrator required'
      using errcode = '22023';
  end if;

  if p_organization_id is null or p_target_user_id is null or p_role is null then
    raise exception 'organization, target user, and role are required'
      using errcode = '22023';
  end if;

  if p_target_user_id = actor_user_id then
    raise exception 'cannot change your own membership through the add-user workflow'
      using errcode = '42501';
  end if;

  select membership.role
    into actor_role
  from public.memberships membership
  where membership.organization_id = p_organization_id
    and membership.user_id = actor_user_id
    and membership.status = 'active'::public.membership_status;

  if actor_role is null or actor_role not in (
    'owner'::public.member_role,
    'admin'::public.member_role
  ) then
    raise exception 'active owner or administrator membership required'
      using errcode = '42501';
  end if;

  if actor_role = 'admin'::public.member_role
     and p_role not in (
       'operator'::public.member_role,
       'member'::public.member_role,
       'viewer'::public.member_role
     ) then
    raise exception 'administrators cannot grant owner or admin roles'
      using errcode = '42501';
  end if;

  select account.email_confirmed_at is not null,
         coalesce(account.is_anonymous, false)
    into target_confirmed, target_anonymous
  from auth.users account
  where account.id = p_target_user_id;

  if not found or target_anonymous then
    raise exception 'target must be an existing non-anonymous auth user'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text || ':' || p_target_user_id::text, 0)
  );

  select membership.*
    into existing_membership
  from public.memberships membership
  where membership.organization_id = p_organization_id
    and membership.user_id = p_target_user_id
  for update;

  desired_status := case
    when target_confirmed then 'active'::public.membership_status
    else 'invited'::public.membership_status
  end;

  if found then
    if existing_membership.status in (
      'active'::public.membership_status,
      'invited'::public.membership_status
    ) then
      if existing_membership.role <> p_role then
        raise exception 'membership already exists with another role'
          using errcode = '23505';
      end if;

      if existing_membership.status = 'active'::public.membership_status
         or existing_membership.status = desired_status then
        return jsonb_build_object(
          'userId', existing_membership.user_id,
          'organizationId', existing_membership.organization_id,
          'role', existing_membership.role,
          'status', existing_membership.status,
          'created', false,
          'restored', false,
          'idempotent', true
        );
      end if;

      update public.memberships
      set status = 'active'::public.membership_status,
          joined_at = coalesce(joined_at, changed_at),
          invited_by = coalesce(invited_by, actor_user_id),
          updated_at = changed_at
      where organization_id = p_organization_id
        and user_id = p_target_user_id;

      desired_status := 'active'::public.membership_status;
      audit_event_type := 'organization.member.activated';
    else
      update public.memberships
      set role = p_role,
          status = desired_status,
          invited_by = actor_user_id,
          joined_at = case when desired_status = 'active' then changed_at else null end,
          updated_at = changed_at
      where organization_id = p_organization_id
        and user_id = p_target_user_id;

      audit_event_type := 'organization.member.restored';
    end if;
  else
    insert into public.memberships (
      organization_id,
      user_id,
      role,
      status,
      invited_by,
      joined_at,
      created_at,
      updated_at
    ) values (
      p_organization_id,
      p_target_user_id,
      p_role,
      desired_status,
      actor_user_id,
      case when desired_status = 'active' then changed_at else null end,
      changed_at,
      changed_at
    );

    audit_event_type := case
      when desired_status = 'active' then 'organization.member.added'
      else 'organization.member.invited'
    end;
  end if;

  perform private.append_audit_event(
    p_organization_id,
    null,
    null,
    'human'::public.audit_actor_type,
    actor_user_id,
    audit_event_type,
    jsonb_build_object(
      'target_user_id', p_target_user_id,
      'role', p_role,
      'status', desired_status,
      'source', 'pandora-user-admin'
    )
  );

  return jsonb_build_object(
    'userId', p_target_user_id,
    'organizationId', p_organization_id,
    'role', p_role,
    'status', desired_status,
    'created', existing_membership.organization_id is null,
    'restored', existing_membership.organization_id is not null,
    'idempotent', false
  );
end;
$function$;


CREATE OR REPLACE FUNCTION public.pandora_admin_update_organization_member(p_actor_user_id uuid, p_organization_id uuid, p_target_user_id uuid, p_role member_role DEFAULT NULL::member_role, p_status membership_status DEFAULT NULL::membership_status)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor_role public.member_role;
  current_membership public.memberships%rowtype;
  next_role public.member_role;
  next_status public.membership_status;
  changed_at timestamptz := clock_timestamp();
  remaining_active_owners integer;
  event_type text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service-role broker required'
      using errcode = '42501';
  end if;

  if p_actor_user_id is null
     or not exists (
       select 1
       from auth.users caller
       where caller.id = p_actor_user_id
         and coalesce(caller.is_anonymous, false) = false
     ) then
    raise exception 'existing non-anonymous administrator required'
      using errcode = '22023';
  end if;

  if p_organization_id is null or p_target_user_id is null then
    raise exception 'organization and target user are required'
      using errcode = '22023';
  end if;

  if p_role is null and p_status is null then
    raise exception 'role or status change required'
      using errcode = '22023';
  end if;

  if p_target_user_id = p_actor_user_id then
    raise exception 'cannot change your own membership through the user-admin workflow'
      using errcode = '42501';
  end if;

  select membership.role
    into actor_role
  from public.memberships membership
  where membership.organization_id = p_organization_id
    and membership.user_id = p_actor_user_id
    and membership.status = 'active'::public.membership_status;

  if actor_role is null or actor_role not in (
    'owner'::public.member_role,
    'admin'::public.member_role
  ) then
    raise exception 'active owner or administrator membership required'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text || ':' || p_target_user_id::text, 0)
  );

  select membership.*
    into current_membership
  from public.memberships membership
  where membership.organization_id = p_organization_id
    and membership.user_id = p_target_user_id
  for update;

  if not found then
    raise exception 'target membership not found'
      using errcode = 'P0002';
  end if;

  next_role := coalesce(p_role, current_membership.role);
  next_status := coalesce(p_status, current_membership.status);

  if next_status = 'invited'::public.membership_status then
    raise exception 'use invitation workflow for invited membership'
      using errcode = '22023';
  end if;

  if actor_role = 'admin'::public.member_role then
    if current_membership.role in (
      'owner'::public.member_role,
      'admin'::public.member_role
    ) then
      raise exception 'administrators cannot modify owner or admin memberships'
        using errcode = '42501';
    end if;
    if next_role in (
      'owner'::public.member_role,
      'admin'::public.member_role
    ) then
      raise exception 'administrators cannot grant owner or admin roles'
        using errcode = '42501';
    end if;
  end if;

  if current_membership.role = 'owner'::public.member_role
     and current_membership.status = 'active'::public.membership_status
     and (
       next_role <> 'owner'::public.member_role
       or next_status <> 'active'::public.membership_status
     ) then
    select count(*)
      into remaining_active_owners
    from public.memberships membership
    where membership.organization_id = p_organization_id
      and membership.user_id <> p_target_user_id
      and membership.role = 'owner'::public.member_role
      and membership.status = 'active'::public.membership_status;

    if remaining_active_owners < 1 then
      raise exception 'cannot remove the last active owner'
        using errcode = '42501';
    end if;
  end if;

  if current_membership.role = next_role
     and current_membership.status = next_status then
    return jsonb_build_object(
      'userId', current_membership.user_id,
      'organizationId', current_membership.organization_id,
      'previousRole', current_membership.role,
      'role', current_membership.role,
      'previousStatus', current_membership.status,
      'status', current_membership.status,
      'changed', false,
      'idempotent', true
    );
  end if;

  update public.memberships
  set role = next_role,
      status = next_status,
      joined_at = case
        when next_status = 'active'::public.membership_status
          then coalesce(joined_at, changed_at)
        else joined_at
      end,
      updated_at = changed_at
  where organization_id = p_organization_id
    and user_id = p_target_user_id;

  event_type := case
    when next_status = 'revoked'::public.membership_status
      then 'organization.member.revoked'
    when next_status = 'suspended'::public.membership_status
      then 'organization.member.suspended'
    when current_membership.status <> 'active'::public.membership_status
         and next_status = 'active'::public.membership_status
      then 'organization.member.activated'
    when current_membership.role <> next_role
      then 'organization.member.role_changed'
    else 'organization.member.updated'
  end;

  perform private.append_audit_event(
    p_organization_id,
    null,
    null,
    'human'::public.audit_actor_type,
    p_actor_user_id,
    event_type,
    jsonb_build_object(
      'target_user_id', p_target_user_id,
      'previous_role', current_membership.role,
      'role', next_role,
      'previous_status', current_membership.status,
      'status', next_status,
      'source', 'pandora-user-admin'
    )
  );

  return jsonb_build_object(
    'userId', p_target_user_id,
    'organizationId', p_organization_id,
    'previousRole', current_membership.role,
    'role', next_role,
    'previousStatus', current_membership.status,
    'status', next_status,
    'changed', true,
    'idempotent', false
  );
end;
$function$;


revoke all on function public.pandora_admin_add_organization_member(uuid,uuid,uuid,public.member_role), public.pandora_admin_update_organization_member(uuid,uuid,uuid,public.member_role,public.membership_status) from public,anon,authenticated;
grant execute on function public.pandora_admin_add_organization_member(uuid,uuid,uuid,public.member_role), public.pandora_admin_update_organization_member(uuid,uuid,uuid,public.member_role,public.membership_status) to service_role;

-- Existing industry catalog: authoritative static capability definitions, not live connections.
create table if not exists public.pandora_industry_packs (
  pack_key text not null
    check (pack_key ~ '^[a-z][a-z0-9_]{1,63}$'),
  pack_version text not null
    check (pack_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  display_name text not null,
  lifecycle_state text not null default 'active'
    check (lifecycle_state in ('active','deprecated','retired')),
  description text not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key(pack_key,pack_version)
);

insert into public.pandora_industry_packs(pack_key,pack_version,display_name,description)
values
  ('hospitality','1.0.0','Hospitality','Hotel and resort operational extensions.'),
  ('restaurant','1.0.0','Restaurant','Restaurant and food-service operational extensions.'),
  ('legal','1.0.0','Legal','Law-office matter, hearing, filing, and evidence extensions.'),
  ('trade','1.0.0','Import / Export','Import-export, shipment, customs, and trade-document extensions.'),
  ('retail','1.0.0','Retail','Store, sale, return, SKU, and stock-position extensions.'),
  ('custom','1.0.0','Custom Business','Namespaced custom extensions that cannot override Core semantics.')
on conflict(pack_key,pack_version) do nothing;



create table public.pandora_model_pricing_versions (
 id uuid default gen_random_uuid() not null,
 provider text not null,
 model text not null,
 model_revision text,
 pricing_version text not null,
 currency text default 'USD'::text not null,
 input_micros_per_million_tokens int8 not null,
 cached_input_micros_per_million_tokens int8 not null,
 output_micros_per_million_tokens int8 not null,
 effective_at timestamptz not null,
 expires_at timestamptz,
 source_ref text not null,
 source_verified_at timestamptz not null,
 verification_status text default 'verified'::text not null,
 created_at timestamptz default now() not null,
 primary key(id)
);

create table public.pandora_verification_evidence (
 id uuid default gen_random_uuid() not null,
 organization_id uuid not null,
 project_id uuid not null,
 verification_run_id uuid not null,
 verification_check_id uuid,
 artifact_version_id uuid,
 evidence_type text not null,
 media_type text default 'application/json'::text not null,
 content_sha256 text not null,
 storage_provider text,
 storage_path text,
 created_at timestamptz default now() not null,
 primary key(id)
);

-- Exact audited approvals columns, enum and decision checks. The unchanged
-- workflow-run/step foreign-key graph is outside this projection fixture;
-- the full migration replay retains and exercises that canonical graph.
create type public.approval_decision as enum ('pending','approved','denied','expired','revoked');
create table public.approvals (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null,
 run_id uuid not null,
 step_id uuid,
 requested_by uuid not null references auth.users(id),
 assigned_to uuid references auth.users(id),
 decision public.approval_decision not null default 'pending',
 decision_by uuid references auth.users(id),
 action_hash text not null check(action_hash ~ '^[0-9a-f]{64}$'),
 preview_redacted jsonb not null,
 request_reason text,
 decision_reason text,
 expires_at timestamptz not null,
 decided_at timestamptz,
 created_at timestamptz not null default timezone('utc',now()),
 updated_at timestamptz not null default timezone('utc',now()),
 check((decision='pending' and decision_by is null and decided_at is null)
    or (decision<>'pending' and decided_at is not null))
);
create unique index approvals_one_pending_per_step_idx
 on public.approvals(step_id) where step_id is not null and decision='pending';
alter table public.approvals enable row level security;
create policy approvals_select_member on public.approvals for select to authenticated
 using(private.is_org_member(organization_id));
grant select on public.approvals to authenticated;
