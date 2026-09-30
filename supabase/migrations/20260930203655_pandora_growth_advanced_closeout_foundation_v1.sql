
begin;

create table if not exists public.pandora_growth_brand_contexts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  version text not null check (version ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{1,127}$'),
  status text not null check (status in ('draft','approved','retired')),
  product_claims jsonb not null check (jsonb_typeof(product_claims)='array'),
  audience_use_cases jsonb not null check (jsonb_typeof(audience_use_cases)='array'),
  tone jsonb not null check (jsonb_typeof(tone)='object'),
  offers jsonb not null check (jsonb_typeof(offers)='array'),
  prohibited_claims jsonb not null check (jsonb_typeof(prohibited_claims)='array'),
  evidence_refs jsonb not null check (jsonb_typeof(evidence_refs)='array'),
  approved_by text,
  approved_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,version),
  check ((status='approved')=(approved_by is not null and approved_at is not null))
);
alter table public.pandora_growth_brand_contexts enable row level security;
revoke all on public.pandora_growth_brand_contexts from public,anon,authenticated;
grant select on public.pandora_growth_brand_contexts to service_role;

create table if not exists public.pandora_growth_creative_candidates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  brand_context_id uuid not null references public.pandora_growth_brand_contexts(id) on delete restrict,
  candidate_key text not null check (candidate_key ~ '^[a-z][a-z0-9._:-]{2,127}$'),
  version text not null check (version ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$'),
  hypothesis text not null check (char_length(hypothesis) between 20 and 1200),
  intended_business_outcome text not null check (char_length(intended_business_outcome) between 3 and 500),
  creative_concept text not null check (char_length(creative_concept) between 10 and 2000),
  offer_concept text not null check (char_length(offer_concept) between 3 and 1200),
  prompt_version text not null,
  provider_key text not null,
  model_key text not null,
  approval_status text not null check (approval_status in ('draft','approved_for_test','rejected')),
  evidence_basis jsonb not null check (jsonb_typeof(evidence_basis)='array'),
  no_winner_claim boolean not null default true check (no_winner_claim is true),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,candidate_key,version)
);
alter table public.pandora_growth_creative_candidates enable row level security;
revoke all on public.pandora_growth_creative_candidates from public,anon,authenticated;
grant select on public.pandora_growth_creative_candidates to service_role;

create table if not exists public.pandora_growth_funnel_variants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  creative_candidate_id uuid not null references public.pandora_growth_creative_candidates(id) on delete restrict,
  variant_key text not null check (variant_key ~ '^[a-z][a-z0-9._:-]{2,127}$'),
  version text not null,
  offer_version text not null,
  destination_version text not null,
  onboarding_version text not null,
  deployment_version text not null,
  stage_refs jsonb not null check (jsonb_typeof(stage_refs)='object'),
  tracking_campaign_id uuid references public.pandora_tracking_campaigns(id) on delete set null,
  status text not null check (status in ('instrumented_not_launched','active_test','retired')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,variant_key,version)
);
alter table public.pandora_growth_funnel_variants enable row level security;
revoke all on public.pandora_growth_funnel_variants from public,anon,authenticated;
grant select on public.pandora_growth_funnel_variants to service_role;

create table if not exists private.pandora_growth_variant_observations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  variant_id uuid not null references public.pandora_growth_funnel_variants(id) on delete cascade,
  journey_id text not null,
  stage text not null check (stage in ('ad','page','signup','preview','payment')),
  source_ref text not null,
  is_test boolean not null default true,
  observed_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,variant_id,stage,source_ref)
);
alter table private.pandora_growth_variant_observations enable row level security;
revoke all on private.pandora_growth_variant_observations from public,anon,authenticated,service_role;

create table if not exists public.pandora_growth_followup_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  version text not null,
  status text not null check(status in ('draft','approved','retired')),
  eligible_stages text[] not null,
  requires_explicit_consent boolean not null default true check(requires_explicit_consent is true),
  opt_out_enforced boolean not null default true check(opt_out_enforced is true),
  duplicate_suppression boolean not null default true check(duplicate_suppression is true),
  human_handoff_required boolean not null default true check(human_handoff_required is true),
  messaging_authorized boolean not null default false check(messaging_authorized is false),
  publishing_authorized boolean not null default false check(publishing_authorized is false),
  evidence_refs jsonb not null check(jsonb_typeof(evidence_refs)='array'),
  approved_by text,
  approved_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,version),
  check ((status='approved')=(approved_by is not null and approved_at is not null))
);
alter table public.pandora_growth_followup_policies enable row level security;
revoke all on public.pandora_growth_followup_policies from public,anon,authenticated;
grant select on public.pandora_growth_followup_policies to service_role;

create or replace function public.pandora_growth_followup_decision_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_stage text,
  p_has_consent boolean,
  p_opted_out boolean,
  p_duplicate boolean,
  p_safety_flag boolean
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_policy public.pandora_growth_followup_policies%rowtype;
  v_reason text;
  v_eligible boolean:=false;
begin
  select * into v_policy
  from public.pandora_growth_followup_policies
  where organization_id=p_organization_id
    and project_id=p_project_id
    and status='approved'
  order by approved_at desc
  limit 1;
  if not found then
    return jsonb_build_object('ok',false,'eligible',false,'reason','policy_unavailable','sendAuthorized',false);
  end if;
  if not (p_stage=any(v_policy.eligible_stages)) then v_reason:='stage_ineligible';
  elsif coalesce(p_opted_out,false) then v_reason:='opt_out';
  elsif not coalesce(p_has_consent,false) then v_reason:='consent_required';
  elsif coalesce(p_duplicate,false) then v_reason:='duplicate_suppressed';
  elsif coalesce(p_safety_flag,false) then v_reason:='human_safety_review';
  else v_reason:='human_handoff_required'; v_eligible:=true;
  end if;
  return jsonb_build_object(
    'ok',true,'eligible',v_eligible,'reason',v_reason,
    'humanHandoffRequired',true,
    'sendAuthorized',false,
    'publishingAuthorized',false,
    'optOutEnforced',true,
    'duplicateSuppression',true,
    'requiresExplicitConsent',true
  );
end;
$function$;
revoke all on function public.pandora_growth_followup_decision_v1(uuid,uuid,text,boolean,boolean,boolean,boolean)
from public,anon,authenticated;
grant execute on function public.pandora_growth_followup_decision_v1(uuid,uuid,text,boolean,boolean,boolean,boolean)
to service_role;

create table if not exists public.pandora_growth_client_provisioning_templates (
  id uuid primary key default gen_random_uuid(),
  template_key text not null,
  version text not null,
  status text not null check(status in ('draft','approved','retired')),
  asset_requirements jsonb not null check(jsonb_typeof(asset_requirements)='object'),
  credential_model jsonb not null check(jsonb_typeof(credential_model)='object'),
  tracking_model jsonb not null check(jsonb_typeof(tracking_model)='object'),
  memory_model jsonb not null check(jsonb_typeof(memory_model)='object'),
  permission_model jsonb not null check(jsonb_typeof(permission_model)='object'),
  approval_gates jsonb not null check(jsonb_typeof(approval_gates)='array'),
  cross_tenant_allowed boolean not null default false check(cross_tenant_allowed is false),
  approved_by text,
  approved_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(template_key,version),
  check ((status='approved')=(approved_by is not null and approved_at is not null))
);
alter table public.pandora_growth_client_provisioning_templates enable row level security;
revoke all on public.pandora_growth_client_provisioning_templates from public,anon,authenticated;
grant select on public.pandora_growth_client_provisioning_templates to service_role;

create table if not exists public.pandora_growth_client_contexts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  tracking_tenant_id uuid not null references public.pandora_tracking_tenants(id) on delete cascade,
  template_id uuid not null references public.pandora_growth_client_provisioning_templates(id) on delete restrict,
  client_key text not null,
  status text not null check(status in ('provisioned','suspended','erased')),
  metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,client_key)
);
alter table public.pandora_growth_client_contexts enable row level security;
revoke all on public.pandora_growth_client_contexts from public,anon,authenticated;
grant select on public.pandora_growth_client_contexts to service_role;

create table if not exists private.pandora_growth_client_context_events (
  id uuid primary key default gen_random_uuid(),
  context_id uuid not null references public.pandora_growth_client_contexts(id) on delete cascade,
  event_type text not null,
  safe_summary jsonb not null default '{}'::jsonb check(jsonb_typeof(safe_summary)='object'),
  created_at timestamptz not null default clock_timestamp()
);
alter table private.pandora_growth_client_context_events enable row level security;
revoke all on private.pandora_growth_client_context_events from public,anon,authenticated,service_role;

create table if not exists public.pandora_growth_data_lifecycle_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  version text not null,
  status text not null check(status in ('draft','approved','retired')),
  retention_state text not null check(retention_state in ('owner_policy_required','approved')),
  erasure_mode text not null check(erasure_mode='context_cascade'),
  raw_customer_data_cross_tenant boolean not null default false check(raw_customer_data_cross_tenant is false),
  cross_client_learning boolean not null default false check(cross_client_learning is false),
  generalized_learning_requires_separate_approval boolean not null default true check(generalized_learning_requires_separate_approval is true),
  evidence_refs jsonb not null check(jsonb_typeof(evidence_refs)='array'),
  approved_by text,
  approved_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,version),
  check ((status='approved')=(approved_by is not null and approved_at is not null))
);
alter table public.pandora_growth_data_lifecycle_policies enable row level security;
revoke all on public.pandora_growth_data_lifecycle_policies from public,anon,authenticated;
grant select on public.pandora_growth_data_lifecycle_policies to service_role;

insert into public.pandora_growth_brand_contexts(
  organization_id,project_id,version,status,product_claims,audience_use_cases,tone,offers,prohibited_claims,evidence_refs,approved_by,approved_at
) values (
  '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,
  'ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid,
  'pandora-brand-v1','approved',
  '[
    "Pandora is a vendor-neutral business operating layer that requests capabilities through governed provider adapters rather than hard-wiring one vendor.",
    "Marketing & Growth can present verified tracking, Meta and approved Memory evidence while campaign mutation, publishing and spend remain separately gated.",
    "Industry packs configure business workflows while provider authority remains explicit and auditable."
  ]'::jsonb,
  '[
    "Enterprise owners who need one governed interface across business systems and providers.",
    "Operations teams that need verified evidence, approvals and provider readback before consequential actions.",
    "Channel and enterprise partners that need provider services to plug into a common capability layer."
  ]'::jsonb,
  '{"voice":"clear, premium, evidence-led, non-hype","principles":["show verified outcomes","state limits","separate analysis from authority"]}'::jsonb,
  '[
    "Managed enterprise deployment with governed provider integrations.",
    "Provider-connected business operations with contextual Pandora assistance."
  ]'::jsonb,
  '[
    "Guaranteed revenue or guaranteed conversion lift.",
    "Automatic winning-campaign claims without adequate evidence.",
    "Unlimited provider availability or quota.",
    "Campaign spend, publishing or activation without explicit authority.",
    "Causal claims from attribution-only or insufficient-evidence data."
  ]'::jsonb,
  '[
    {"type":"memory","ref":"d6eb2ee3-f8cc-4a10-a28b-0487014da004"},
    {"type":"migration","ref":"pandora_growth_native_chat_fallback_v1"},
    {"type":"tracker","ref":"FB-031..FB-045"}
  ]'::jsonb,
  'owner-current-chat-2026-10-01',clock_timestamp()
)
on conflict(organization_id,project_id,version) do update
set status=excluded.status,product_claims=excluded.product_claims,audience_use_cases=excluded.audience_use_cases,
    tone=excluded.tone,offers=excluded.offers,prohibited_claims=excluded.prohibited_claims,
    evidence_refs=excluded.evidence_refs,approved_by=excluded.approved_by,approved_at=excluded.approved_at,updated_at=clock_timestamp();

insert into public.pandora_growth_creative_candidates(
  organization_id,project_id,brand_context_id,candidate_key,version,hypothesis,intended_business_outcome,
  creative_concept,offer_concept,prompt_version,provider_key,model_key,approval_status,evidence_basis
)
select
  b.organization_id,b.project_id,b.id,'evidence-command-center','v1',
  'Showing Pandora as a governed evidence-first business command center will increase qualified enterprise demo interest compared with generic AI-assistant positioning.',
  'qualified_enterprise_demo_interest',
  'Product-demo concept: show one owner interface reading verified business evidence, approved Memory, provider state and approval gates without pretending that analysis itself grants execution authority.',
  'Managed enterprise deployment with governed provider integrations.',
  'manual-owner-context-v1','manual_owner_context','deterministic-v1','approved_for_test',
  jsonb_build_array(jsonb_build_object('type','brand_context','ref',b.id::text),jsonb_build_object('type','memory','ref','d6eb2ee3-f8cc-4a10-a28b-0487014da004'))
from public.pandora_growth_brand_contexts b
where b.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
  and b.project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid
  and b.version='pandora-brand-v1'
on conflict(organization_id,project_id,candidate_key,version) do update
set hypothesis=excluded.hypothesis,intended_business_outcome=excluded.intended_business_outcome,
creative_concept=excluded.creative_concept,offer_concept=excluded.offer_concept,
prompt_version=excluded.prompt_version,provider_key=excluded.provider_key,model_key=excluded.model_key,
approval_status=excluded.approval_status,evidence_basis=excluded.evidence_basis,updated_at=clock_timestamp();

insert into public.pandora_growth_creative_candidates(
  organization_id,project_id,brand_context_id,candidate_key,version,hypothesis,intended_business_outcome,
  creative_concept,offer_concept,prompt_version,provider_key,model_key,approval_status,evidence_basis
)
select
  b.organization_id,b.project_id,b.id,'provider-plug-in-control','v1',
  'Explaining Pandora as a provider-neutral plug-in operating layer with explicit approval boundaries will increase enterprise integration enquiries compared with feature-list messaging.',
  'qualified_enterprise_integration_enquiry',
  'Architecture-led concept: demonstrate connectivity, AI, communications, logistics and other provider services entering Pandora through governed capability interfaces with visible approval and readback controls.',
  'Provider-connected business operations with contextual Pandora assistance.',
  'manual-owner-context-v1','manual_owner_context','deterministic-v1','approved_for_test',
  jsonb_build_array(jsonb_build_object('type','brand_context','ref',b.id::text),jsonb_build_object('type','runtime','ref','pandora-capability-provider-activation-v1'))
from public.pandora_growth_brand_contexts b
where b.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
  and b.project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid
  and b.version='pandora-brand-v1'
on conflict(organization_id,project_id,candidate_key,version) do update
set hypothesis=excluded.hypothesis,intended_business_outcome=excluded.intended_business_outcome,
creative_concept=excluded.creative_concept,offer_concept=excluded.offer_concept,
prompt_version=excluded.prompt_version,provider_key=excluded.provider_key,model_key=excluded.model_key,
approval_status=excluded.approval_status,evidence_basis=excluded.evidence_basis,updated_at=clock_timestamp();

insert into public.pandora_growth_funnel_variants(
  organization_id,project_id,creative_candidate_id,variant_key,version,offer_version,
  destination_version,onboarding_version,deployment_version,stage_refs,tracking_campaign_id,status
)
select
  c.organization_id,c.project_id,c.id,'evidence-command-center-a','v1','offer-managed-enterprise-v1',
  'landing-command-center-v1','onboarding-enterprise-v1','deployment-current-production',
  '{"ad":"creative:evidence-command-center:v1","page":"landing-command-center-v1","signup":"signup-v1","preview":"preview-v1","payment":"payment-v1"}'::jsonb,
  (select tc.id from public.pandora_tracking_campaigns tc join public.pandora_tracking_tenants tt on tt.id=tc.tenant_id
   where tt.organization_id=c.organization_id and tt.project_id=c.project_id and tc.metadata->>'purpose'='controlled-test' order by tc.created_at limit 1),
  'instrumented_not_launched'
from public.pandora_growth_creative_candidates c
where c.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
  and c.project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid
  and c.candidate_key='evidence-command-center' and c.version='v1'
on conflict(organization_id,project_id,variant_key,version) do update
set creative_candidate_id=excluded.creative_candidate_id,offer_version=excluded.offer_version,
destination_version=excluded.destination_version,onboarding_version=excluded.onboarding_version,
deployment_version=excluded.deployment_version,stage_refs=excluded.stage_refs,
tracking_campaign_id=excluded.tracking_campaign_id,status=excluded.status,updated_at=clock_timestamp();

insert into public.pandora_growth_funnel_variants(
  organization_id,project_id,creative_candidate_id,variant_key,version,offer_version,
  destination_version,onboarding_version,deployment_version,stage_refs,tracking_campaign_id,status
)
select
  c.organization_id,c.project_id,c.id,'provider-plug-in-control-b','v1','offer-provider-connected-v1',
  'landing-provider-layer-v1','onboarding-enterprise-v1','deployment-current-production',
  '{"ad":"creative:provider-plug-in-control:v1","page":"landing-provider-layer-v1","signup":"signup-v1","preview":"preview-v1","payment":"payment-v1"}'::jsonb,
  null,'instrumented_not_launched'
from public.pandora_growth_creative_candidates c
where c.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
  and c.project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid
  and c.candidate_key='provider-plug-in-control' and c.version='v1'
on conflict(organization_id,project_id,variant_key,version) do update
set creative_candidate_id=excluded.creative_candidate_id,offer_version=excluded.offer_version,
destination_version=excluded.destination_version,onboarding_version=excluded.onboarding_version,
deployment_version=excluded.deployment_version,stage_refs=excluded.stage_refs,
tracking_campaign_id=excluded.tracking_campaign_id,status=excluded.status,updated_at=clock_timestamp();

insert into public.pandora_growth_followup_policies(
  organization_id,project_id,version,status,eligible_stages,evidence_refs,approved_by,approved_at
) values (
  '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,
  'ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid,
  'qualified-lead-followup-v1','approved',
  array['qualified']::text[],
  '[{"type":"tracker","ref":"FB-053"},{"type":"authority","ref":"separate-channel-authorization-required"}]'::jsonb,
  'owner-current-chat-2026-10-01',clock_timestamp()
)
on conflict(organization_id,project_id,version) do update
set status=excluded.status,eligible_stages=excluded.eligible_stages,evidence_refs=excluded.evidence_refs,
approved_by=excluded.approved_by,approved_at=excluded.approved_at,updated_at=clock_timestamp();

insert into public.pandora_growth_client_provisioning_templates(
  template_key,version,status,asset_requirements,credential_model,tracking_model,memory_model,
  permission_model,approval_gates,approved_by,approved_at
) values (
  'pandora-enterprise-growth','v1','approved',
  '{"required":["organization","project","tracking_tenant","approved_provider_assets"],"optional":["pixel","campaign_binding","custom_domain"]}'::jsonb,
  '{"ownership":"client_or_explicitly_delegated","storage":"vault_only","crossTenantCredentialReuse":false}'::jsonb,
  '{"tenantIsolated":true,"testTrafficSeparated":true,"unknownValuesRemainUnknown":true}'::jsonb,
  '{"namespace":"real_life","approvedCurrentOnly":true,"crossClientLearning":false}'::jsonb,
  '{"ownerAdminOnly":true,"staffDefault":false,"rawPiiVisible":false,"exportsDefault":false}'::jsonb,
  '[
    {"gate":"privacy","required":true},
    {"gate":"provider_assets","required":true},
    {"gate":"spend","requiredForPaidPilot":true},
    {"gate":"client_approval","requiredForClientPilot":true}
  ]'::jsonb,
  'owner-current-chat-2026-10-01',clock_timestamp()
)
on conflict(template_key,version) do update
set status=excluded.status,asset_requirements=excluded.asset_requirements,credential_model=excluded.credential_model,
tracking_model=excluded.tracking_model,memory_model=excluded.memory_model,permission_model=excluded.permission_model,
approval_gates=excluded.approval_gates,approved_by=excluded.approved_by,approved_at=excluded.approved_at,updated_at=clock_timestamp();

insert into public.pandora_growth_data_lifecycle_policies(
  organization_id,project_id,version,status,retention_state,erasure_mode,evidence_refs,approved_by,approved_at
) values (
  '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,
  'ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid,
  'growth-lifecycle-v1','approved','owner_policy_required','context_cascade',
  '[{"type":"tracker","ref":"FB-060"},{"type":"policy","ref":"no-cross-client-raw-data"}]'::jsonb,
  'owner-current-chat-2026-10-01',clock_timestamp()
)
on conflict(organization_id,project_id,version) do update
set status=excluded.status,retention_state=excluded.retention_state,erasure_mode=excluded.erasure_mode,
evidence_refs=excluded.evidence_refs,approved_by=excluded.approved_by,approved_at=excluded.approved_at,updated_at=clock_timestamp();

create or replace function public.pandora_growth_advanced_foundation_status_v1(
  p_organization_id uuid,
  p_project_id uuid
) returns jsonb
language sql
security definer
set search_path='pg_catalog','public','private'
as $function$
  select jsonb_build_object(
    'ok',true,
    'brandContexts',(select count(*) from public.pandora_growth_brand_contexts b where b.organization_id=p_organization_id and b.project_id=p_project_id and b.status='approved'),
    'creativeCandidates',(select count(*) from public.pandora_growth_creative_candidates c where c.organization_id=p_organization_id and c.project_id=p_project_id and c.approval_status='approved_for_test'),
    'funnelVariants',(select count(*) from public.pandora_growth_funnel_variants v where v.organization_id=p_organization_id and v.project_id=p_project_id),
    'followupPolicies',(select count(*) from public.pandora_growth_followup_policies f where f.organization_id=p_organization_id and f.project_id=p_project_id and f.status='approved'),
    'provisioningTemplates',(select count(*) from public.pandora_growth_client_provisioning_templates t where t.status='approved'),
    'lifecyclePolicies',(select count(*) from public.pandora_growth_data_lifecycle_policies l where l.organization_id=p_organization_id and l.project_id=p_project_id and l.status='approved'),
    'authority',jsonb_build_object(
      'campaignMutation',false,'publishing',false,'spend',false,'messaging',false,
      'crossClientLearning',false,'rawCustomerDataCrossTenant',false
    )
  );
$function$;
revoke all on function public.pandora_growth_advanced_foundation_status_v1(uuid,uuid)
from public,anon,authenticated;
grant execute on function public.pandora_growth_advanced_foundation_status_v1(uuid,uuid)
to service_role;

commit;
;
