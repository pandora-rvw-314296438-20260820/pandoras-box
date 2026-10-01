-- Pandora Capability, Provider Ecosystem & Optimization Activation v1
-- Generalizes existing native routing/execution without replacing it.
-- Selection remains separate from approval; provider availability is organization-scoped.

-- ---------------------------------------------------------------------------
-- PHASE 3: bounded capability vocabulary
-- ---------------------------------------------------------------------------

create table if not exists public.pandora_capability_families (
  family_key text primary key
    check (family_key ~ '^[a-z][a-z0-9_]{1,63}$'),
  display_name text not null,
  family_version text not null default '1.0.0'
    check (family_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  created_at timestamptz not null default clock_timestamp()
);

insert into public.pandora_capability_families(family_key,display_name)
values
  ('compute_data','Compute & Data'),
  ('connectivity_communications','Connectivity & Communications'),
  ('money_commerce','Money & Commerce'),
  ('customers_growth','Customers & Growth'),
  ('physical_operations','Physical Operations'),
  ('trust_identity_government','Trust, Identity & Government')
on conflict(family_key) do nothing;

create table if not exists public.pandora_capability_specs (
  capability_key text not null
    check (capability_key ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  capability_version text not null
    check (capability_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  family_key text not null references public.pandora_capability_families(family_key) on delete restrict,
  operation_mode text not null check (operation_mode in ('read','write')),
  input_schema jsonb not null default '{"type":"object"}'::jsonb
    check (jsonb_typeof(input_schema)='object'),
  output_schema jsonb not null default '{"type":"object"}'::jsonb
    check (jsonb_typeof(output_schema)='object'),
  evidence_required boolean not null default false,
  approval_default text not null default 'policy'
    check (approval_default in ('none','policy','required')),
  lifecycle_state text not null default 'active'
    check (lifecycle_state in ('active','deprecated','retired')),
  created_at timestamptz not null default clock_timestamp(),
  primary key(capability_key,capability_version)
);

insert into public.pandora_capability_specs(
  capability_key,capability_version,family_key,operation_mode,evidence_required,approval_default
) values
  ('compute.run','1.0.0','compute_data','write',true,'policy'),
  ('storage.put','1.0.0','compute_data','write',true,'policy'),
  ('ai.infer','1.0.0','compute_data','write',true,'none'),
  ('database.query','1.0.0','compute_data','read',false,'none'),
  ('database.write','1.0.0','compute_data','write',true,'required'),
  ('edge.deploy','1.0.0','compute_data','write',true,'policy'),
  ('repository.read','1.0.0','compute_data','read',false,'none'),
  ('repository.change','1.0.0','compute_data','write',true,'policy'),
  ('pull_request.read','1.0.0','compute_data','read',false,'none'),
  ('project.read','1.0.0','compute_data','read',false,'none'),
  ('deployment.read','1.0.0','compute_data','read',false,'none'),
  ('deployment.publish','1.0.0','compute_data','write',true,'policy'),
  ('connectivity.provision','1.0.0','connectivity_communications','write',true,'required'),
  ('network.qos.request','1.0.0','connectivity_communications','write',true,'required'),
  ('message.send','1.0.0','connectivity_communications','write',true,'policy'),
  ('voice.call','1.0.0','connectivity_communications','write',true,'policy'),
  ('payment.collect','1.0.0','money_commerce','write',true,'required'),
  ('money.transfer','1.0.0','money_commerce','write',true,'required'),
  ('invoice.issue','1.0.0','money_commerce','write',true,'policy'),
  ('commerce.order.create','1.0.0','money_commerce','write',true,'policy'),
  ('campaign.launch','1.0.0','customers_growth','write',true,'policy'),
  ('lead.sync','1.0.0','customers_growth','write',true,'policy'),
  ('audience.activate','1.0.0','customers_growth','write',true,'policy'),
  ('conversion.measure','1.0.0','customers_growth','read',false,'none'),
  ('ads.read','1.0.0','customers_growth','read',false,'none'),
  ('ads.manage','1.0.0','customers_growth','write',true,'policy'),
  ('analytics.query','1.0.0','customers_growth','read',false,'none'),
  ('drive.read','1.0.0','compute_data','read',false,'none'),
  ('drive.write','1.0.0','compute_data','write',true,'policy'),
  ('sheets.read','1.0.0','compute_data','read',false,'none'),
  ('sheets.write','1.0.0','compute_data','write',true,'policy'),
  ('delivery.quote','1.0.0','physical_operations','read',false,'none'),
  ('delivery.dispatch','1.0.0','physical_operations','write',true,'policy'),
  ('vehicle.book','1.0.0','physical_operations','write',true,'policy'),
  ('shipment.track','1.0.0','physical_operations','read',false,'none'),
  ('device.control','1.0.0','physical_operations','write',true,'required'),
  ('identity.verify','1.0.0','trust_identity_government','read',true,'policy'),
  ('company.lookup','1.0.0','trust_identity_government','read',false,'none'),
  ('permit.submit','1.0.0','trust_identity_government','write',true,'required'),
  ('document.sign','1.0.0','trust_identity_government','write',true,'required'),
  ('compliance.check','1.0.0','trust_identity_government','read',true,'policy')
on conflict(capability_key,capability_version) do nothing;

-- ---------------------------------------------------------------------------
-- PHASE 5: provider manifest + immutable versioned adapter declaration
-- ---------------------------------------------------------------------------

create table if not exists public.pandora_provider_manifests (
  provider_key text not null
    check (provider_key ~ '^[a-z][a-z0-9_.-]{1,127}$'),
  manifest_version text not null
    check (manifest_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  display_name text not null check (char_length(display_name) between 1 and 200),
  lifecycle_state text not null default 'catalog'
    check (lifecycle_state in ('catalog','active','deprecated','retired')),
  auth_scheme text not null,
  regions text[] not null check (cardinality(regions)>0),
  data_residency text[] not null check (cardinality(data_residency)>0),
  data_handling jsonb not null check (jsonb_typeof(data_handling)='object'),
  deprecation_policy jsonb not null check (jsonb_typeof(deprecation_policy)='object'),
  runbook_ref text not null,
  escalation_ref text not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key(provider_key,manifest_version)
);

create table if not exists public.pandora_provider_capabilities (
  provider_key text not null,
  manifest_version text not null,
  capability_key text not null,
  capability_version text not null,
  operation_mode text not null check (operation_mode in ('read','write')),
  implementation_state text not null
    check (implementation_state in ('native','external','catalog')),
  adapter_ref text not null,
  regions text[] not null check (cardinality(regions)>0),
  permissions jsonb not null check (jsonb_typeof(permissions)='object'),
  evidence_modes text[] not null,
  constraints jsonb not null default '{}'::jsonb check (jsonb_typeof(constraints)='object'),
  idempotency_strategy text,
  created_at timestamptz not null default clock_timestamp(),
  primary key(provider_key,manifest_version,capability_key,capability_version),
  constraint pandora_provider_capabilities_manifest_fkey
    foreign key(provider_key,manifest_version)
    references public.pandora_provider_manifests(provider_key,manifest_version)
    on delete restrict,
  constraint pandora_provider_capabilities_spec_fkey
    foreign key(capability_key,capability_version)
    references public.pandora_capability_specs(capability_key,capability_version)
    on delete restrict,
  check (
    operation_mode='read'
    or
    (idempotency_strategy is not null and char_length(idempotency_strategy)>0 and cardinality(evidence_modes)>0)
  )
);

create table if not exists public.pandora_provider_activations (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_key text not null,
  manifest_version text not null,
  activation_state text not null default 'authorized'
    check (activation_state in ('authorized','suspended','revoked')),
  granted_capabilities text[] not null default '{}'::text[],
  granted_scopes text[] not null default '{}'::text[],
  allowed_regions text[] not null default '{}'::text[],
  health_state text not null default 'unknown'
    check (health_state in ('unknown','healthy','degraded','down')),
  activation_source text not null default 'manual'
    check (activation_source in ('manual','native_registry','connector')),
  last_verified_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  primary key(organization_id,provider_key),
  constraint pandora_provider_activations_manifest_fkey
    foreign key(provider_key,manifest_version)
    references public.pandora_provider_manifests(provider_key,manifest_version)
    on delete restrict
);

create table if not exists public.pandora_provider_selection_policies (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  capability_key text not null,
  capability_version text not null,
  selection_mode text not null default 'AUTO'
    check (selection_mode in ('AUTO','PREFERRED','REQUIRED')),
  required_provider text,
  preferred_providers text[] not null default '{}'::text[],
  fallback_providers text[] not null default '{}'::text[],
  allow_required_fallback boolean not null default false,
  required_data_residency text[] not null default '{}'::text[],
  max_cost_per_unit numeric(20,8),
  score_weights jsonb not null default '{"reliability":0.5,"latency":0.25,"cost":0.25}'::jsonb
    check (jsonb_typeof(score_weights)='object'),
  approval_required boolean not null default false,
  updated_at timestamptz not null default clock_timestamp(),
  primary key(organization_id,capability_key,capability_version),
  constraint pandora_provider_selection_policies_spec_fkey
    foreign key(capability_key,capability_version)
    references public.pandora_capability_specs(capability_key,capability_version)
    on delete restrict,
  check (
    selection_mode<>'REQUIRED'
    or required_provider is not null
  )
);

create table if not exists public.pandora_consent_grants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  subject_entity_id uuid,
  purpose text not null check (char_length(purpose) between 1 and 500),
  capability_key text not null,
  capability_version text not null,
  granted_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz,
  revoked_at timestamptz,
  evidence_refs jsonb not null default '[]'::jsonb check (jsonb_typeof(evidence_refs)='array'),
  unique(id,organization_id),
  constraint pandora_consent_grants_entity_org_fkey
    foreign key(subject_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  constraint pandora_consent_grants_spec_fkey
    foreign key(capability_key,capability_version)
    references public.pandora_capability_specs(capability_key,capability_version)
    on delete restrict,
  check (expires_at is null or expires_at>=granted_at),
  check (revoked_at is null or revoked_at>=granted_at)
);

-- ---------------------------------------------------------------------------
-- PHASE 6: comparable verified metrics + explainable selection receipts
-- ---------------------------------------------------------------------------

create table if not exists public.pandora_provider_capability_metrics (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_key text not null,
  capability_key text not null,
  capability_version text not null,
  region text not null default 'global',
  window_start timestamptz not null,
  window_end timestamptz not null,
  accepted_count bigint not null default 0 check (accepted_count>=0),
  pending_verification_count bigint not null default 0 check (pending_verification_count>=0),
  verified_success_count bigint not null default 0 check (verified_success_count>=0),
  verified_failure_count bigint not null default 0 check (verified_failure_count>=0),
  p95_latency_ms numeric(20,6) check (p95_latency_ms is null or p95_latency_ms>=0),
  cost_per_unit numeric(20,8) check (cost_per_unit is null or cost_per_unit>=0),
  observed_at timestamptz not null default clock_timestamp(),
  unique(organization_id,provider_key,capability_key,capability_version,region,window_start,window_end),
  check (window_end>=window_start),
  check (verified_success_count+verified_failure_count<=accepted_count)
);

create table if not exists public.pandora_provider_selection_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  capability_key text not null,
  capability_version text not null,
  requested_mode text not null check (requested_mode in ('AUTO','PREFERRED','REQUIRED')),
  requested_region text,
  selected_provider text,
  result_state text not null check (result_state in ('selected','no_eligible_provider')),
  eligible_providers jsonb not null default '[]'::jsonb check (jsonb_typeof(eligible_providers)='array'),
  excluded_providers jsonb not null default '[]'::jsonb check (jsonb_typeof(excluded_providers)='array'),
  score_components jsonb not null default '[]'::jsonb check (jsonb_typeof(score_components)='array'),
  selection_reason text not null,
  approval_required boolean not null default false,
  created_at timestamptz not null default clock_timestamp(),
  unique(id,organization_id),
  constraint pandora_provider_selection_receipts_spec_fkey
    foreign key(capability_key,capability_version)
    references public.pandora_capability_specs(capability_key,capability_version)
    on delete restrict
);

create index if not exists pandora_provider_metrics_lookup_idx
  on public.pandora_provider_capability_metrics(
    organization_id,capability_key,capability_version,provider_key,window_end desc
  );
create index if not exists pandora_provider_selection_receipts_org_time_idx
  on public.pandora_provider_selection_receipts(organization_id,created_at desc);

create table if not exists public.pandora_provider_conformance_results (
  id uuid primary key default gen_random_uuid(),
  provider_key text not null,
  manifest_version text not null,
  passed boolean not null,
  report jsonb not null check (jsonb_typeof(report)='object'),
  tested_at timestamptz not null default clock_timestamp(),
  constraint pandora_provider_conformance_results_manifest_fkey
    foreign key(provider_key,manifest_version)
    references public.pandora_provider_manifests(provider_key,manifest_version)
    on delete restrict
);

-- ---------------------------------------------------------------------------
-- Provider catalog seed. "catalog" means discoverable but not selectable.
-- Organization activation + implementation_state=native are required for use.
-- ---------------------------------------------------------------------------

insert into public.pandora_provider_manifests(
  provider_key,manifest_version,display_name,lifecycle_state,auth_scheme,regions,data_residency,
  data_handling,deprecation_policy,runbook_ref,escalation_ref
) values
  ('github','1.0.0','GitHub','active','oauth_or_app',array['global'],array['provider_managed'],'{"classification":"provider_managed"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:github','escalation:github'),
  ('supabase','1.0.0','Supabase','active','oauth_or_service',array['global'],array['provider_managed'],'{"classification":"provider_managed"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:supabase','escalation:supabase'),
  ('vercel','1.0.0','Vercel','active','oauth_or_token',array['global'],array['provider_managed'],'{"classification":"provider_managed"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:vercel','escalation:vercel'),
  ('meta','1.0.0','Meta','active','oauth',array['global'],array['provider_managed'],'{"classification":"provider_managed"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:meta','escalation:meta'),
  ('google_workspace','1.0.0','Google Workspace','active','oauth',array['global'],array['provider_managed'],'{"classification":"provider_managed"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:google-workspace','escalation:google-workspace'),
  ('posthog','1.0.0','PostHog','active','oauth_or_api_key',array['global'],array['provider_managed'],'{"classification":"provider_managed"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:posthog','escalation:posthog'),
  ('gemini','1.0.0','Gemini','active','vault_api_key',array['global'],array['provider_managed'],'{"classification":"provider_managed"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:gemini','escalation:gemini'),
  ('openai','1.0.0','OpenAI','active','vault_api_key',array['global'],array['provider_managed'],'{"classification":"provider_managed"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:openai','escalation:openai'),
  ('kimi','1.0.0','Kimi','active','vault_api_key',array['global'],array['provider_managed'],'{"classification":"provider_managed"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:kimi','escalation:kimi'),
  ('grab','1.0.0','Grab','catalog','provider_defined',array['provider_defined'],array['provider_defined'],'{"classification":"provider_defined"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:grab','escalation:grab'),
  ('lalamove','1.0.0','Lalamove','catalog','provider_defined',array['provider_defined'],array['provider_defined'],'{"classification":"provider_defined"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:lalamove','escalation:lalamove'),
  ('pldt','1.0.0','PLDT','catalog','provider_defined',array['provider_defined'],array['provider_defined'],'{"classification":"provider_defined"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:pldt','escalation:pldt'),
  ('smart','1.0.0','Smart','catalog','provider_defined',array['provider_defined'],array['provider_defined'],'{"classification":"provider_defined"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:smart','escalation:smart'),
  ('globe','1.0.0','Globe','catalog','provider_defined',array['provider_defined'],array['provider_defined'],'{"classification":"provider_defined"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:globe','escalation:globe'),
  ('dito','1.0.0','DITO','catalog','provider_defined',array['provider_defined'],array['provider_defined'],'{"classification":"provider_defined"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:dito','escalation:dito'),
  ('vonage','1.0.0','Vonage','catalog','provider_defined',array['provider_defined'],array['provider_defined'],'{"classification":"provider_defined"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:vonage','escalation:vonage'),
  ('twilio','1.0.0','Twilio','catalog','provider_defined',array['provider_defined'],array['provider_defined'],'{"classification":"provider_defined"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:twilio','escalation:twilio'),
  ('maya','1.0.0','Maya','catalog','provider_defined',array['provider_defined'],array['provider_defined'],'{"classification":"provider_defined"}'::jsonb,'{"noticeRequired":true}'::jsonb,'runbook:maya','escalation:maya')
on conflict(provider_key,manifest_version) do nothing;

insert into public.pandora_provider_capabilities(
  provider_key,manifest_version,capability_key,capability_version,operation_mode,implementation_state,
  adapter_ref,regions,permissions,evidence_modes,constraints,idempotency_strategy
) values
  ('github','1.0.0','repository.read','1.0.0','read','native','native:github',array['global'],'{"scope":"repository:read"}'::jsonb,array['readback'],'{}'::jsonb,null),
  ('github','1.0.0','pull_request.read','1.0.0','read','native','native:github',array['global'],'{"scope":"pull_request:read"}'::jsonb,array['readback'],'{}'::jsonb,null),
  ('github','1.0.0','repository.change','1.0.0','write','native','native:github',array['global'],'{"scope":"repository:write"}'::jsonb,array['provider_receipt','read_after_write'],'{}'::jsonb,'request_digest+expected_head'),
  ('supabase','1.0.0','project.read','1.0.0','read','native','native:supabase',array['global'],'{"scope":"project:read"}'::jsonb,array['readback'],'{}'::jsonb,null),
  ('supabase','1.0.0','database.query','1.0.0','read','native','native:supabase',array['global'],'{"scope":"database:read"}'::jsonb,array['readback'],'{}'::jsonb,null),
  ('supabase','1.0.0','database.write','1.0.0','write','native','native:supabase',array['global'],'{"scope":"database:write"}'::jsonb,array['migration_receipt','read_after_write'],'{"supportedSurfaceOnly":true}'::jsonb,'migration_name+payload_digest'),
  ('vercel','1.0.0','deployment.read','1.0.0','read','native','native:vercel',array['global'],'{"scope":"deployment:read"}'::jsonb,array['readback'],'{}'::jsonb,null),
  ('vercel','1.0.0','deployment.publish','1.0.0','write','native','native:vercel',array['global'],'{"scope":"deployment:write"}'::jsonb,array['provider_receipt','read_after_write'],'{}'::jsonb,'deployment_request_digest'),
  ('meta','1.0.0','ads.read','1.0.0','read','native','native:meta',array['global'],'{"scope":"ads:read"}'::jsonb,array['readback'],'{}'::jsonb,null),
  ('meta','1.0.0','ads.manage','1.0.0','write','native','native:meta',array['global'],'{"scope":"ads:manage"}'::jsonb,array['provider_receipt','read_after_write'],'{}'::jsonb,'business_request_digest'),
  ('meta','1.0.0','campaign.launch','1.0.0','write','native','native:meta',array['global'],'{"scope":"ads:manage"}'::jsonb,array['provider_receipt','read_after_write'],'{}'::jsonb,'campaign_request_digest'),
  ('meta','1.0.0','conversion.measure','1.0.0','read','native','native:meta',array['global'],'{"scope":"ads:read"}'::jsonb,array['readback'],'{}'::jsonb,null),
  ('google_workspace','1.0.0','drive.read','1.0.0','read','native','native:google_workspace',array['global'],'{"scope":"drive:read"}'::jsonb,array['readback'],'{}'::jsonb,null),
  ('google_workspace','1.0.0','drive.write','1.0.0','write','native','native:google_workspace',array['global'],'{"scope":"drive:write"}'::jsonb,array['provider_receipt','read_after_write'],'{}'::jsonb,'file_request_digest'),
  ('google_workspace','1.0.0','sheets.read','1.0.0','read','native','native:google_workspace',array['global'],'{"scope":"sheets:read"}'::jsonb,array['readback'],'{}'::jsonb,null),
  ('google_workspace','1.0.0','sheets.write','1.0.0','write','native','native:google_workspace',array['global'],'{"scope":"sheets:write"}'::jsonb,array['provider_receipt','read_after_write'],'{}'::jsonb,'sheet_request_digest'),
  ('posthog','1.0.0','analytics.query','1.0.0','read','native','native:posthog',array['global'],'{"scope":"analytics:read"}'::jsonb,array['readback'],'{}'::jsonb,null),
  ('posthog','1.0.0','conversion.measure','1.0.0','read','native','native:posthog',array['global'],'{"scope":"analytics:read"}'::jsonb,array['readback'],'{}'::jsonb,null),
  ('gemini','1.0.0','ai.infer','1.0.0','write','native','native:gemini',array['global'],'{"scope":"inference"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'request_id+prompt_digest'),
  ('openai','1.0.0','ai.infer','1.0.0','write','native','native:openai',array['global'],'{"scope":"inference"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'request_id+prompt_digest'),
  ('kimi','1.0.0','ai.infer','1.0.0','write','native','native:kimi',array['global'],'{"scope":"inference"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'request_id+prompt_digest'),
  ('grab','1.0.0','delivery.quote','1.0.0','read','catalog','catalog:grab',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_defined'],'{}'::jsonb,null),
  ('grab','1.0.0','delivery.dispatch','1.0.0','write','catalog','catalog:grab',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'provider_declared_required'),
  ('grab','1.0.0','shipment.track','1.0.0','read','catalog','catalog:grab',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_defined'],'{}'::jsonb,null),
  ('lalamove','1.0.0','delivery.quote','1.0.0','read','catalog','catalog:lalamove',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_defined'],'{}'::jsonb,null),
  ('lalamove','1.0.0','delivery.dispatch','1.0.0','write','catalog','catalog:lalamove',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'provider_declared_required'),
  ('lalamove','1.0.0','shipment.track','1.0.0','read','catalog','catalog:lalamove',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_defined'],'{}'::jsonb,null),
  ('pldt','1.0.0','connectivity.provision','1.0.0','write','catalog','catalog:pldt',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'provider_declared_required'),
  ('pldt','1.0.0','network.qos.request','1.0.0','write','catalog','catalog:pldt',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'provider_declared_required'),
  ('smart','1.0.0','connectivity.provision','1.0.0','write','catalog','catalog:smart',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'provider_declared_required'),
  ('globe','1.0.0','connectivity.provision','1.0.0','write','catalog','catalog:globe',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'provider_declared_required'),
  ('dito','1.0.0','connectivity.provision','1.0.0','write','catalog','catalog:dito',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'provider_declared_required'),
  ('vonage','1.0.0','message.send','1.0.0','write','catalog','catalog:vonage',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'provider_declared_required'),
  ('vonage','1.0.0','voice.call','1.0.0','write','catalog','catalog:vonage',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'provider_declared_required'),
  ('twilio','1.0.0','message.send','1.0.0','write','catalog','catalog:twilio',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'provider_declared_required'),
  ('twilio','1.0.0','voice.call','1.0.0','write','catalog','catalog:twilio',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'provider_declared_required'),
  ('maya','1.0.0','payment.collect','1.0.0','write','catalog','catalog:maya',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'provider_declared_required'),
  ('maya','1.0.0','money.transfer','1.0.0','write','catalog','catalog:maya',array['provider_defined'],'{"scope":"provider_defined"}'::jsonb,array['provider_receipt'],'{}'::jsonb,'provider_declared_required')
on conflict(provider_key,manifest_version,capability_key,capability_version) do nothing;

-- ---------------------------------------------------------------------------
-- Immutability/version lifecycle guards
-- ---------------------------------------------------------------------------

create or replace function private.pandora_provider_manifest_version_guard_v1()
returns trigger
language plpgsql
security invoker
set search_path='pg_catalog','public'
as $$
begin
  if tg_op='DELETE' then
    raise exception 'provider_manifest_versions_cannot_be_deleted' using errcode='55000';
  end if;
  if (to_jsonb(new)-'lifecycle_state'-'updated_at')
       is distinct from
     (to_jsonb(old)-'lifecycle_state'-'updated_at') then
    raise exception 'provider_manifest_version_is_immutable' using errcode='55000';
  end if;
  return new;
end;
$$;

drop trigger if exists pandora_provider_manifest_version_guard on public.pandora_provider_manifests;
create trigger pandora_provider_manifest_version_guard
before update or delete on public.pandora_provider_manifests
for each row execute function private.pandora_provider_manifest_version_guard_v1();

create or replace function private.pandora_provider_capability_immutable_v1()
returns trigger
language plpgsql
security invoker
set search_path='pg_catalog','public'
as $$
begin
  raise exception 'provider_capability_manifest_rows_are_immutable' using errcode='55000';
end;
$$;

drop trigger if exists pandora_provider_capability_immutable on public.pandora_provider_capabilities;
create trigger pandora_provider_capability_immutable
before update or delete on public.pandora_provider_capabilities
for each row execute function private.pandora_provider_capability_immutable_v1();

create or replace function private.pandora_provider_receipt_immutable_v1()
returns trigger
language plpgsql
security invoker
set search_path='pg_catalog','public'
as $$
begin
  raise exception 'provider_receipts_are_append_only' using errcode='55000';
end;
$$;

drop trigger if exists pandora_provider_selection_receipts_append_only on public.pandora_provider_selection_receipts;
create trigger pandora_provider_selection_receipts_append_only
before update or delete on public.pandora_provider_selection_receipts
for each row execute function private.pandora_provider_receipt_immutable_v1();

drop trigger if exists pandora_provider_conformance_results_append_only on public.pandora_provider_conformance_results;
create trigger pandora_provider_conformance_results_append_only
before update or delete on public.pandora_provider_conformance_results
for each row execute function private.pandora_provider_receipt_immutable_v1();

-- ---------------------------------------------------------------------------
-- Manifest conformance + catalog
-- ---------------------------------------------------------------------------

create or replace function public.pandora_provider_manifest_conformance_v1(
  p_provider_key text,
  p_manifest_version text
)
returns jsonb
language plpgsql
security invoker
stable
set search_path='pg_catalog','public'
as $$
declare
  v_manifest public.pandora_provider_manifests%rowtype;
  v_errors text[]:='{}'::text[];
  v_cap record;
  v_count integer:=0;
  v_expected_mode text;
begin
  select * into v_manifest
  from public.pandora_provider_manifests
  where provider_key=p_provider_key and manifest_version=p_manifest_version;

  if not found then
    return jsonb_build_object('pass',false,'errors',jsonb_build_array('manifest_not_found'));
  end if;

  if cardinality(v_manifest.regions)=0 then v_errors:=array_append(v_errors,'regions_missing'); end if;
  if cardinality(v_manifest.data_residency)=0 then v_errors:=array_append(v_errors,'data_residency_missing'); end if;
  if jsonb_typeof(v_manifest.data_handling)<>'object' then v_errors:=array_append(v_errors,'data_handling_invalid'); end if;
  if jsonb_typeof(v_manifest.deprecation_policy)<>'object' then v_errors:=array_append(v_errors,'deprecation_policy_invalid'); end if;
  if nullif(v_manifest.runbook_ref,'') is null then v_errors:=array_append(v_errors,'runbook_missing'); end if;
  if nullif(v_manifest.escalation_ref,'') is null then v_errors:=array_append(v_errors,'escalation_missing'); end if;

  for v_cap in
    select pc.*
    from public.pandora_provider_capabilities pc
    where pc.provider_key=p_provider_key and pc.manifest_version=p_manifest_version
  loop
    v_count:=v_count+1;
    select operation_mode into v_expected_mode
    from public.pandora_capability_specs
    where capability_key=v_cap.capability_key and capability_version=v_cap.capability_version;

    if v_expected_mode is null then
      v_errors:=array_append(v_errors,'unknown_capability:'||v_cap.capability_key);
    elsif v_expected_mode<>v_cap.operation_mode then
      v_errors:=array_append(v_errors,'operation_mode_mismatch:'||v_cap.capability_key);
    end if;

    if v_cap.operation_mode='write'
       and (nullif(v_cap.idempotency_strategy,'') is null or cardinality(v_cap.evidence_modes)=0) then
      v_errors:=array_append(v_errors,'write_idempotency_or_evidence_missing:'||v_cap.capability_key);
    end if;
  end loop;

  if v_count=0 then v_errors:=array_append(v_errors,'capabilities_missing'); end if;

  return jsonb_build_object(
    'pass',cardinality(v_errors)=0,
    'providerKey',p_provider_key,
    'manifestVersion',p_manifest_version,
    'capabilityCount',v_count,
    'errors',to_jsonb(v_errors)
  );
end;
$$;

create or replace function public.pandora_provider_catalog_v1(p_organization_id uuid)
returns jsonb
language sql
security invoker
stable
set search_path='pg_catalog','public'
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'providerKey',m.provider_key,
      'manifestVersion',m.manifest_version,
      'displayName',m.display_name,
      'lifecycleState',m.lifecycle_state,
      'authScheme',m.auth_scheme,
      'regions',to_jsonb(m.regions),
      'dataResidency',to_jsonb(m.data_residency),
      'runbookRef',m.runbook_ref,
      'escalationRef',m.escalation_ref,
      'activationState',a.activation_state,
      'healthState',a.health_state,
      'lastVerifiedAt',a.last_verified_at,
      'capabilities',(
        select coalesce(jsonb_agg(jsonb_build_object(
          'capabilityKey',c.capability_key,
          'capabilityVersion',c.capability_version,
          'operationMode',c.operation_mode,
          'implementationState',c.implementation_state,
          'evidenceModes',to_jsonb(c.evidence_modes)
        ) order by c.capability_key),'[]'::jsonb)
        from public.pandora_provider_capabilities c
        where c.provider_key=m.provider_key and c.manifest_version=m.manifest_version
      )
    )
    order by m.display_name,m.manifest_version
  ),'[]'::jsonb)
  from public.pandora_provider_manifests m
  left join public.pandora_provider_activations a
    on a.organization_id=p_organization_id
   and a.provider_key=m.provider_key
   and a.manifest_version=m.manifest_version
  where m.lifecycle_state<>'retired';
$$;

-- ---------------------------------------------------------------------------
-- Explainable eligibility-first selection
-- ---------------------------------------------------------------------------

create or replace function public.pandora_select_provider_v1(
  p_organization_id uuid,
  p_capability_key text,
  p_capability_version text default '1.0.0',
  p_region text default null,
  p_mode text default null
)
returns jsonb
language plpgsql
security invoker
set search_path='pg_catalog','public'
as $$
declare
  v_policy public.pandora_provider_selection_policies%rowtype;
  v_mode text;
  v_required text;
  v_preferred text[]:='{}'::text[];
  v_fallback text[]:='{}'::text[];
  v_allow_required_fallback boolean:=false;
  v_required_residency text[]:='{}'::text[];
  v_max_cost numeric;
  v_weights jsonb:='{"reliability":0.5,"latency":0.25,"cost":0.25}'::jsonb;
  v_approval_required boolean:=false;
  v_eligible jsonb:='[]'::jsonb;
  v_excluded jsonb:='[]'::jsonb;
  v_scores jsonb:='[]'::jsonb;
  v_selected text;
  v_reason text;
  v_receipt_id uuid;
begin
  if not exists(
    select 1 from public.pandora_capability_specs
    where capability_key=p_capability_key
      and capability_version=p_capability_version
      and lifecycle_state='active'
  ) then
    raise exception 'capability_not_active' using errcode='22023';
  end if;

  select * into v_policy
  from public.pandora_provider_selection_policies
  where organization_id=p_organization_id
    and capability_key=p_capability_key
    and capability_version=p_capability_version;

  if found then
    v_mode:=coalesce(p_mode,v_policy.selection_mode);
    v_required:=v_policy.required_provider;
    v_preferred:=v_policy.preferred_providers;
    v_fallback:=v_policy.fallback_providers;
    v_allow_required_fallback:=v_policy.allow_required_fallback;
    v_required_residency:=v_policy.required_data_residency;
    v_max_cost:=v_policy.max_cost_per_unit;
    v_weights:=v_policy.score_weights;
    v_approval_required:=v_policy.approval_required;
  else
    v_mode:=coalesce(p_mode,'AUTO');
  end if;

  if v_mode not in ('AUTO','PREFERRED','REQUIRED') then
    raise exception 'invalid_provider_selection_mode' using errcode='22023';
  end if;

  with universe as (
    select
      pc.provider_key,
      pc.manifest_version,
      pc.implementation_state,
      pm.lifecycle_state,
      pm.data_residency,
      pc.regions,
      pa.activation_state,
      pa.health_state,
      pa.granted_capabilities,
      m.verified_success_count,
      m.verified_failure_count,
      m.p95_latency_ms,
      m.cost_per_unit
    from public.pandora_provider_capabilities pc
    join public.pandora_provider_manifests pm
      on pm.provider_key=pc.provider_key and pm.manifest_version=pc.manifest_version
    left join public.pandora_provider_activations pa
      on pa.organization_id=p_organization_id
     and pa.provider_key=pc.provider_key
     and pa.manifest_version=pc.manifest_version
    left join lateral (
      select mm.*
      from public.pandora_provider_capability_metrics mm
      where mm.organization_id=p_organization_id
        and mm.provider_key=pc.provider_key
        and mm.capability_key=pc.capability_key
        and mm.capability_version=pc.capability_version
        and (p_region is null or mm.region=p_region or mm.region='global')
      order by mm.window_end desc
      limit 1
    ) m on true
    where pc.capability_key=p_capability_key
      and pc.capability_version=p_capability_version
  ), scored0 as (
    select *,
      coalesce(verified_success_count::numeric/nullif(verified_success_count+verified_failure_count,0),0.5) reliability_score,
      1/(1+(coalesce(p95_latency_ms,1000)/1000)) latency_score,
      1/(1+coalesce(cost_per_unit,1)) cost_score,
      (
        lifecycle_state='active'
        and implementation_state='native'
        and activation_state='authorized'
        and coalesce(health_state,'unknown')<>'down'
        and (p_capability_key=any(coalesce(granted_capabilities,'{}'::text[])) or '*'=any(coalesce(granted_capabilities,'{}'::text[])))
        and (p_region is null or p_region=any(regions) or 'global'=any(regions))
        and (cardinality(v_required_residency)=0 or data_residency && v_required_residency)
        and (v_max_cost is null or (cost_per_unit is not null and cost_per_unit<=v_max_cost))
      ) eligible
    from universe
  ), scored as (
    select *,
      (
        coalesce((v_weights->>'reliability')::numeric,0.5)*reliability_score +
        coalesce((v_weights->>'latency')::numeric,0.25)*latency_score +
        coalesce((v_weights->>'cost')::numeric,0.25)*cost_score
      ) total_score,
      array_remove(array[
        case when lifecycle_state<>'active' then 'manifest_not_active' end,
        case when implementation_state<>'native' then 'adapter_not_native' end,
        case when activation_state is distinct from 'authorized' then 'provider_not_authorized' end,
        case when coalesce(health_state,'unknown')='down' then 'provider_down' end,
        case when not (p_capability_key=any(coalesce(granted_capabilities,'{}'::text[])) or '*'=any(coalesce(granted_capabilities,'{}'::text[]))) then 'capability_not_granted' end,
        case when p_region is not null and not (p_region=any(regions) or 'global'=any(regions)) then 'region_ineligible' end,
        case when cardinality(v_required_residency)>0 and not (data_residency && v_required_residency) then 'data_residency_ineligible' end,
        case when v_max_cost is not null and (cost_per_unit is null or cost_per_unit>v_max_cost) then 'cost_constraint_ineligible' end
      ],null) exclusion_reasons
    from scored0
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'providerKey',provider_key,
      'manifestVersion',manifest_version,
      'score',total_score
    ) order by provider_key) filter(where eligible),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object(
      'providerKey',provider_key,
      'reasons',to_jsonb(exclusion_reasons)
    ) order by provider_key) filter(where not eligible),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object(
      'providerKey',provider_key,
      'score',total_score,
      'reliability',reliability_score,
      'latency',latency_score,
      'cost',cost_score
    ) order by provider_key) filter(where eligible),'[]'::jsonb)
  into v_eligible,v_excluded,v_scores
  from scored;

  if v_mode='REQUIRED' then
    if v_required is null then
      v_reason:='required_provider_not_configured';
    elsif exists(select 1 from jsonb_array_elements(v_eligible) e where e->>'providerKey'=v_required) then
      v_selected:=v_required;
      v_reason:='required_provider_selected';
    elsif v_allow_required_fallback then
      select f.provider_key into v_selected
      from unnest(v_fallback) with ordinality f(provider_key,ord)
      where exists(select 1 from jsonb_array_elements(v_eligible) e where e->>'providerKey'=f.provider_key)
      order by f.ord
      limit 1;
      v_reason:=case when v_selected is null then 'required_provider_unavailable_no_eligible_fallback' else 'required_provider_unavailable_explicit_fallback' end;
    else
      v_reason:='required_provider_unavailable_fail_closed';
    end if;
  elsif v_mode='PREFERRED' then
    select p.provider_key into v_selected
    from unnest(v_preferred) with ordinality p(provider_key,ord)
    where exists(select 1 from jsonb_array_elements(v_eligible) e where e->>'providerKey'=p.provider_key)
    order by p.ord
    limit 1;

    if v_selected is not null then
      v_reason:='preferred_provider_selected';
    else
      select f.provider_key into v_selected
      from unnest(v_fallback) with ordinality f(provider_key,ord)
      where exists(select 1 from jsonb_array_elements(v_eligible) e where e->>'providerKey'=f.provider_key)
      order by f.ord
      limit 1;
      v_reason:=case when v_selected is null then 'preferred_provider_unavailable_no_approved_fallback' else 'preferred_provider_unavailable_explicit_fallback' end;
    end if;
  else
    select e->>'providerKey' into v_selected
    from jsonb_array_elements(v_scores) e
    order by (e->>'score')::numeric desc,e->>'providerKey'
    limit 1;
    v_reason:=case when v_selected is null then 'no_eligible_provider' else 'auto_highest_explainable_score' end;
  end if;

  insert into public.pandora_provider_selection_receipts(
    organization_id,capability_key,capability_version,requested_mode,requested_region,
    selected_provider,result_state,eligible_providers,excluded_providers,score_components,
    selection_reason,approval_required
  ) values (
    p_organization_id,p_capability_key,p_capability_version,v_mode,p_region,
    v_selected,case when v_selected is null then 'no_eligible_provider' else 'selected' end,
    v_eligible,v_excluded,v_scores,v_reason,v_approval_required
  ) returning id into v_receipt_id;

  return jsonb_build_object(
    'ok',v_selected is not null,
    'selectionReceiptId',v_receipt_id,
    'mode',v_mode,
    'selectedProvider',v_selected,
    'approvalRequired',v_approval_required,
    'reason',v_reason,
    'eligibleProviders',v_eligible,
    'excludedProviders',v_excluded,
    'scores',v_scores
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Operations: verified-only outcome and reconciliation observability
-- ---------------------------------------------------------------------------

create or replace function public.pandora_execution_outcome_metrics_v1(p_organization_id uuid)
returns jsonb
language plpgsql
security invoker
stable
set search_path='pg_catalog','public','private'
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'workerReported',count(*) filter(where o.worker_reported_at is not null),
    'pendingVerification',count(*) filter(where o.worker_reported_at is not null and o.verified_at is null),
    'verifiedOutcomes',count(*) filter(where o.verified_at is not null),
    'verifiedSuccess',count(*) filter(
      where o.verified_at is not null
        and o.error_code is null
        and lower(coalesce(o.verified_outcome,'')) not in ('failed','failure','rejected','hold')
    ),
    'verifiedFailure',count(*) filter(
      where o.verified_at is not null
        and (o.error_code is not null or lower(coalesce(o.verified_outcome,'')) in ('failed','failure','rejected','hold'))
    )
  ) into v_result
  from private.execution_dispatch_outbox o
  where o.organization_id=p_organization_id;

  return coalesce(v_result,'{}'::jsonb);
end;
$$;

create or replace function public.pandora_reconciliation_backlog_v1(p_organization_id uuid)
returns jsonb
language plpgsql
security invoker
stable
set search_path='pg_catalog','public','private'
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'pendingCount',count(*) filter(where o.worker_reported_at is not null and o.verified_at is null),
    'oldestPendingAt',min(o.worker_reported_at) filter(where o.worker_reported_at is not null and o.verified_at is null),
    'verifiedCount',count(*) filter(where o.verified_at is not null)
  ) into v_result
  from private.execution_dispatch_outbox o
  where o.organization_id=p_organization_id;
  return coalesce(v_result,'{}'::jsonb);
end;
$$;

create or replace function public.pandora_provider_observability_v1(p_organization_id uuid)
returns jsonb
language plpgsql
security invoker
stable
set search_path='pg_catalog','public','private'
as $$
declare
  v_health jsonb;
  v_metrics jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'provider',h.provider,
    'status',h.status,
    'lastEventAt',h.last_event_at,
    'lastSuccessAt',h.last_success_at,
    'staleAfter',h.stale_after
  ) order by h.provider),'[]'::jsonb)
  into v_health
  from public.pandora_provider_health h
  where h.organization_id=p_organization_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'providerKey',m.provider_key,
    'capabilityKey',m.capability_key,
    'capabilityVersion',m.capability_version,
    'region',m.region,
    'acceptedCount',m.accepted_count,
    'pendingVerificationCount',m.pending_verification_count,
    'verifiedSuccessCount',m.verified_success_count,
    'verifiedFailureCount',m.verified_failure_count,
    'p95LatencyMs',m.p95_latency_ms,
    'costPerUnit',m.cost_per_unit,
    'observedAt',m.observed_at
  ) order by m.provider_key,m.capability_key),'[]'::jsonb)
  into v_metrics
  from public.pandora_provider_capability_metrics m
  where m.organization_id=p_organization_id;

  return jsonb_build_object(
    'providerHealth',v_health,
    'capabilityMetrics',v_metrics,
    'reconciliationBacklog',public.pandora_reconciliation_backlog_v1(p_organization_id),
    'executionOutcomes',public.pandora_execution_outcome_metrics_v1(p_organization_id)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS / grants
-- ---------------------------------------------------------------------------

do $$
declare
  v_table text;
  v_read text;
  v_service text;
begin
  foreach v_table in array array[
    'pandora_capability_families',
    'pandora_capability_specs',
    'pandora_provider_manifests',
    'pandora_provider_capabilities',
    'pandora_provider_conformance_results'
  ] loop
    execute format('alter table public.%I enable row level security',v_table);
    execute format('revoke all on table public.%I from public,anon,authenticated',v_table);
    execute format('grant select on table public.%I to authenticated,service_role',v_table);
    execute format('grant insert,update,delete on table public.%I to service_role',v_table);
    v_read:=v_table||'_authenticated_read';
    v_service:=v_table||'_service_all';
    execute format('drop policy if exists %I on public.%I',v_read,v_table);
    execute format('create policy %I on public.%I for select to authenticated using(true)',v_read,v_table);
    execute format('drop policy if exists %I on public.%I',v_service,v_table);
    execute format('create policy %I on public.%I for all to service_role using(true) with check(true)',v_service,v_table);
  end loop;

  foreach v_table in array array[
    'pandora_provider_activations',
    'pandora_provider_selection_policies',
    'pandora_consent_grants',
    'pandora_provider_capability_metrics',
    'pandora_provider_selection_receipts'
  ] loop
    execute format('alter table public.%I enable row level security',v_table);
    execute format('revoke all on table public.%I from public,anon,authenticated',v_table);
    execute format('grant select on table public.%I to authenticated',v_table);
    execute format('grant select,insert,update,delete on table public.%I to service_role',v_table);
    v_read:=v_table||'_member_select';
    v_service:=v_table||'_service_all';
    execute format('drop policy if exists %I on public.%I',v_read,v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using (exists (select 1 from public.memberships m where m.organization_id=%I.organization_id and m.user_id=(select auth.uid()) and m.status=''active''))',
      v_read,v_table,v_table
    );
    execute format('drop policy if exists %I on public.%I',v_service,v_table);
    execute format('create policy %I on public.%I for all to service_role using(true) with check(true)',v_service,v_table);
  end loop;
end;
$$;

revoke update,delete on table public.pandora_provider_selection_receipts,public.pandora_provider_conformance_results from service_role;

revoke all on function public.pandora_provider_manifest_conformance_v1(text,text) from public,anon;
revoke all on function public.pandora_provider_catalog_v1(uuid) from public,anon;
revoke all on function public.pandora_select_provider_v1(uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.pandora_execution_outcome_metrics_v1(uuid) from public,anon,authenticated;
revoke all on function public.pandora_reconciliation_backlog_v1(uuid) from public,anon,authenticated;
revoke all on function public.pandora_provider_observability_v1(uuid) from public,anon,authenticated;

grant execute on function public.pandora_provider_manifest_conformance_v1(text,text) to authenticated,service_role;
grant execute on function public.pandora_provider_catalog_v1(uuid) to authenticated,service_role;
grant execute on function public.pandora_select_provider_v1(uuid,text,text,text,text) to service_role;
grant execute on function public.pandora_execution_outcome_metrics_v1(uuid) to service_role;
grant execute on function public.pandora_reconciliation_backlog_v1(uuid) to service_role;
grant execute on function public.pandora_provider_observability_v1(uuid) to service_role;

