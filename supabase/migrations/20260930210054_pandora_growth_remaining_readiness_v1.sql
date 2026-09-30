
begin;

create table if not exists public.pandora_growth_experiment_designs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  design_key text not null check (design_key ~ '^[a-z][a-z0-9._:-]{2,127}$'),
  version text not null,
  status text not null check (status in ('approved_not_launched','launched','completed','retired')),
  primary_metric text not null,
  candidate_keys text[] not null check (cardinality(candidate_keys) >= 2),
  allocation jsonb not null check (jsonb_typeof(allocation)='object'),
  holdout_policy jsonb not null check (jsonb_typeof(holdout_policy)='object'),
  randomization_unit text not null,
  duration_days integer not null check (duration_days between 1 and 90),
  stopping_rule jsonb not null check (jsonb_typeof(stopping_rule)='object'),
  minimum_sample_size integer not null check (minimum_sample_size >= 20),
  launch_authorized boolean not null default false check (launch_authorized is false),
  spend_authorized boolean not null default false check (spend_authorized is false),
  causal_claim_allowed boolean not null default false check (causal_claim_allowed is false),
  approved_by text not null,
  approved_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,design_key,version)
);
alter table public.pandora_growth_experiment_designs enable row level security;
revoke all on public.pandora_growth_experiment_designs from public,anon,authenticated;
grant select on public.pandora_growth_experiment_designs to service_role;

insert into public.pandora_growth_experiment_designs(
  organization_id,project_id,design_key,version,status,primary_metric,candidate_keys,
  allocation,holdout_policy,randomization_unit,duration_days,stopping_rule,
  minimum_sample_size,approved_by,approved_at
) values (
  '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,
  'ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid,
  'enterprise-positioning-ab','v1','approved_not_launched',
  'qualified_enterprise_interest',
  array['evidence-command-center','provider-plug-in-control']::text[],
  '{"evidence-command-center":0.5,"provider-plug-in-control":0.5}'::jsonb,
  '{"mode":"where_feasible","holdoutFraction":0.1,"fallback":"randomized_two_arm"}'::jsonb,
  'journey_id',7,
  '{"type":"fixed_window_with_minimum_sample","earlyWinnerForbidden":true,"stopOnSafetyOrAuthorityBreach":true,"reportUncertainty":true}'::jsonb,
  100,
  'owner-current-chat-2026-10-01',clock_timestamp()
)
on conflict(organization_id,project_id,design_key,version) do update
set status=excluded.status,primary_metric=excluded.primary_metric,candidate_keys=excluded.candidate_keys,
    allocation=excluded.allocation,holdout_policy=excluded.holdout_policy,
    randomization_unit=excluded.randomization_unit,duration_days=excluded.duration_days,
    stopping_rule=excluded.stopping_rule,minimum_sample_size=excluded.minimum_sample_size,
    launch_authorized=false,spend_authorized=false,causal_claim_allowed=false,
    approved_by=excluded.approved_by,approved_at=excluded.approved_at,updated_at=clock_timestamp();

create or replace function public.pandora_growth_contribution_status_v1(
  p_organization_id uuid,
  p_project_id uuid
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_paid bigint:=0;
  v_refunds bigint:=0;
  v_revenue numeric:=0;
  v_refund_value numeric:=0;
  v_spend numeric;
  v_delivery_cost numeric;
  v_retained numeric;
  v_missing text[]:='{}'::text[];
begin
  select
    count(*) filter(where event_name='paid_activation' and is_test=false),
    count(*) filter(where event_name='refund_settled' and is_test=false),
    coalesce(sum((money->>'amount')::numeric) filter(where event_name='paid_activation' and is_test=false and money ? 'amount'),0),
    coalesce(sum((money->>'amount')::numeric) filter(where event_name='refund_settled' and is_test=false and money ? 'amount'),0)
  into v_paid,v_refunds,v_revenue,v_refund_value
  from public.pandora_growth_outcome_receipts
  where organization_id=p_organization_id and project_id=p_project_id;

  select sum(spend) into v_spend
  from public.pandora_tracking_daily_metrics m
  join public.pandora_tracking_tenants t on t.id=m.tenant_id
  where t.organization_id=p_organization_id
    and t.project_id=p_project_id
    and m.is_test=false;

  if v_paid=0 then v_missing:=array_append(v_missing,'paid_activation'); end if;
  if v_spend is null then v_missing:=array_append(v_missing,'paid_media_spend'); end if;
  v_missing:=array_append(v_missing,'delivery_cost');
  v_missing:=array_append(v_missing,'retention_observation');

  return jsonb_build_object(
    'ok',true,
    'complete',cardinality(v_missing)=0,
    'paidActivations',v_paid,
    'refunds',v_refunds,
    'netReceipts',case when v_paid>0 then v_revenue-v_refund_value else null end,
    'paidMediaSpend',v_spend,
    'deliveryCost',v_delivery_cost,
    'retainedValue',v_retained,
    'contribution',case
      when v_paid>0 and v_spend is not null and v_delivery_cost is not null
      then (v_revenue-v_refund_value)-v_spend-v_delivery_cost
      else null
    end,
    'missingInputs',to_jsonb(v_missing),
    'testTrafficExcluded',true,
    'unknownInputsRemainUnknown',true
  );
end;
$function$;
revoke all on function public.pandora_growth_contribution_status_v1(uuid,uuid)
from public,anon,authenticated;
grant execute on function public.pandora_growth_contribution_status_v1(uuid,uuid)
to service_role;

create table if not exists public.pandora_growth_provider_benchmark_observations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  workload_key text not null,
  provider_key text not null,
  model_key text not null,
  model_revision text,
  observed_at timestamptz not null,
  availability_status text not null,
  provider_status integer,
  verified_outcome text not null,
  accuracy_score numeric,
  latency_ms bigint,
  estimated_cost_micros bigint,
  failure_code text,
  constraints jsonb not null check(jsonb_typeof(constraints)='object'),
  evidence_refs jsonb not null check(jsonb_typeof(evidence_refs)='array'),
  created_at timestamptz not null default clock_timestamp()
);
alter table public.pandora_growth_provider_benchmark_observations enable row level security;
revoke all on public.pandora_growth_provider_benchmark_observations from public,anon,authenticated;
grant select on public.pandora_growth_provider_benchmark_observations to service_role;

delete from public.pandora_growth_provider_benchmark_observations
where organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
  and project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid
  and workload_key='growth_analysis_health_20261001';

insert into public.pandora_growth_provider_benchmark_observations(
 organization_id,project_id,workload_key,provider_key,model_key,observed_at,
 availability_status,provider_status,verified_outcome,failure_code,constraints,evidence_refs
) values
('2270b266-59da-4c39-bfd9-9f8d08352af0','ee282126-3f61-4058-8c92-2fedbfcecf1f','growth_analysis_health_20261001','gemini','gemini-3.5-flash-lite','2026-09-30T19:18:45Z','unavailable',401,'provider_failed','ACCOUNT_STATE_INVALID','{"spendAuthorized":false}'::jsonb,'[{"type":"provider_probe","ref":"E-FB035-PROVIDER-PROBES-20261001"}]'::jsonb),
('2270b266-59da-4c39-bfd9-9f8d08352af0','ee282126-3f61-4058-8c92-2fedbfcecf1f','growth_analysis_health_20261001','openai','gpt-5.6-terra','2026-09-30T19:18:45Z','unavailable',429,'provider_failed','credit_balance_exhausted','{"spendAuthorized":false}'::jsonb,'[{"type":"provider_probe","ref":"E-FB035-PROVIDER-PROBES-20261001"}]'::jsonb),
('2270b266-59da-4c39-bfd9-9f8d08352af0','ee282126-3f61-4058-8c92-2fedbfcecf1f','growth_analysis_health_20261001','kimi','kimi-k3','2026-09-30T19:18:45Z','unavailable',429,'provider_failed','exceeded_current_quota_error','{"spendAuthorized":false}'::jsonb,'[{"type":"provider_probe","ref":"E-FB035-PROVIDER-PROBES-20261001"}]'::jsonb),
('2270b266-59da-4c39-bfd9-9f8d08352af0','ee282126-3f61-4058-8c92-2fedbfcecf1f','growth_analysis_health_20261001','openrouter','qwen/qwen3-30b-a3b-instruct-2507','2026-09-30T19:18:45Z','unavailable',402,'provider_failed','quota_exhausted','{"spendAuthorized":false}'::jsonb,'[{"type":"provider_probe","ref":"E-FB035-PROVIDER-PROBES-20261001"}]'::jsonb);

create table if not exists public.pandora_growth_shadow_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  version text not null,
  status text not null check(status in ('approved_shadow_only','retired')),
  max_metric_staleness_seconds integer not null check(max_metric_staleness_seconds between 60 and 86400),
  max_write_actions integer not null default 0 check(max_write_actions=0),
  spend_risk_authorized boolean not null default false check(spend_risk_authorized is false),
  stop_on_delayed_conversion boolean not null default true,
  stop_on_provider_failure boolean not null default true,
  stop_on_kill_switch boolean not null default true,
  activation_authorized boolean not null default false check(activation_authorized is false),
  approved_by text not null,
  approved_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,version)
);
alter table public.pandora_growth_shadow_policies enable row level security;
revoke all on public.pandora_growth_shadow_policies from public,anon,authenticated;
grant select on public.pandora_growth_shadow_policies to service_role;

insert into public.pandora_growth_shadow_policies(
 organization_id,project_id,version,status,max_metric_staleness_seconds,approved_by,approved_at
) values (
 '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,
 'ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid,
 'zero-write-shadow-v1','approved_shadow_only',3600,
 'owner-current-chat-2026-10-01',clock_timestamp()
)
on conflict(organization_id,project_id,version) do update
set status='approved_shadow_only',max_metric_staleness_seconds=3600,
    max_write_actions=0,spend_risk_authorized=false,stop_on_delayed_conversion=true,
    stop_on_provider_failure=true,stop_on_kill_switch=true,activation_authorized=false,
    approved_by=excluded.approved_by,approved_at=excluded.approved_at;

create or replace function public.pandora_growth_shadow_decision_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_metric_age_seconds integer,
  p_delayed_conversion boolean,
  p_provider_failure boolean,
  p_kill_switch_active boolean
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $function$
declare
  v public.pandora_growth_shadow_policies%rowtype;
  v_stop text[]:='{}'::text[];
begin
  select * into v from public.pandora_growth_shadow_policies
  where organization_id=p_organization_id and project_id=p_project_id
    and status='approved_shadow_only'
  order by approved_at desc limit 1;
  if not found then
    return jsonb_build_object('ok',false,'shadowAllowed',false,'activationAuthorized',false);
  end if;
  if p_metric_age_seconds>v.max_metric_staleness_seconds then v_stop:=array_append(v_stop,'stale_metrics'); end if;
  if coalesce(p_delayed_conversion,false) and v.stop_on_delayed_conversion then v_stop:=array_append(v_stop,'delayed_conversion'); end if;
  if coalesce(p_provider_failure,false) and v.stop_on_provider_failure then v_stop:=array_append(v_stop,'provider_failure'); end if;
  if coalesce(p_kill_switch_active,false) and v.stop_on_kill_switch then v_stop:=array_append(v_stop,'kill_switch'); end if;
  return jsonb_build_object(
    'ok',true,
    'shadowAllowed',cardinality(v_stop)=0,
    'stopReasons',to_jsonb(v_stop),
    'recommendedWriteActions',0,
    'maxWriteActions',0,
    'spendRiskAuthorized',false,
    'activationAuthorized',false
  );
end;
$function$;
revoke all on function public.pandora_growth_shadow_decision_v1(uuid,uuid,integer,boolean,boolean,boolean)
from public,anon,authenticated;
grant execute on function public.pandora_growth_shadow_decision_v1(uuid,uuid,integer,boolean,boolean,boolean)
to service_role;

create table if not exists public.pandora_growth_incident_runbook (
  check_key text primary key,
  category text not null,
  condition_summary text not null,
  owner_role text not null,
  stop_action text not null,
  reconnect_action text not null,
  retry_policy text not null,
  recovery_evidence text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
alter table public.pandora_growth_incident_runbook enable row level security;
revoke all on public.pandora_growth_incident_runbook from public,anon,authenticated;
grant select on public.pandora_growth_incident_runbook to service_role;

insert into public.pandora_growth_incident_runbook(
 check_key,category,condition_summary,owner_role,stop_action,reconnect_action,retry_policy,recovery_evidence
) values
('auth_expiry','provider_auth','Meta/connector credential is expired, revoked, disabled or unavailable.','THEMIS','Stop consequential provider writes; retain read-only evidence where safe.','Re-authorize only the affected provider identity and re-read exact scopes/assets.','No blind retry on auth failure.','Fresh provider scope/asset readback.'),
('delivery_backlog','delivery','Accepted work is not producing provider/runtime completion receipts within the bounded window.','HEPHAESTUS','Stop new write admissions for the affected lane.','Restore worker/provider path after health readback.','Retry only idempotent work with the same key after reconciliation.','Execution receipt plus provider readback.'),
('spend_divergence','spend','Observed spend exceeds or cannot reconcile to the explicit authorized envelope.','THEMIS','Activate kill switch and block all non-PAUSE actions.','No reconnect until owner authority and provider state are reconciled.','No automatic paid retry.','Budget/spend/provider state receipt.'),
('stale_data','data_freshness','Growth evidence is older than the approved freshness window.','ARTEMIS','Stop optimization decisions and label KPIs stale/unknown.','Refresh exact tenant source and re-evaluate.','Read-only refresh permitted; writes remain denied.','Fresh source timestamps and lineage.'),
('provider_failure','provider_runtime','Provider returns authentication, quota, rate-limit, timeout or transport failure.','HEPHAESTUS','Fail closed for provider-dependent execution; use native read-only evidence route when available.','Restore only the affected provider credential/quota/route.','Cross-provider fallback only when policy and capability allow it.','Provider probe plus successful bounded acceptance.'),
('memory_retrieval','memory','Approved-current Memory context is unavailable, stale or missing required class access.','MNEMOSYNE','Do not substitute pending/rejected/stale Memory or expand authority.','Repair read grant/class compatibility or promote through reviewed append path.','No self-approval or authority expansion.','Approved-current record/version/hash retrieval receipt.')
on conflict(check_key) do update
set category=excluded.category,condition_summary=excluded.condition_summary,
owner_role=excluded.owner_role,stop_action=excluded.stop_action,
reconnect_action=excluded.reconnect_action,retry_policy=excluded.retry_policy,
recovery_evidence=excluded.recovery_evidence,enabled=true,updated_at=clock_timestamp();

create or replace function public.pandora_growth_health_snapshot_v1(
  p_organization_id uuid,
  p_project_id uuid
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_zero jsonb;
  v_memory_count integer:=0;
  v_provider_disabled integer:=0;
  v_latest_click timestamptz;
  v_latest_outcome timestamptz;
begin
  v_zero:=public.pandora_meta_zero_delivery_action_status_v1(p_organization_id,p_project_id);
  select count(*) into v_memory_count
  from private.pandora_growth_memory_retrieval_receipts
  where organization_id=p_organization_id and project_id=p_project_id
    and status='approved_current';

  select count(distinct provider) into v_provider_disabled
  from public.pandora_runtime_provider_configs
  where provider in ('gemini','kimi','openai','openrouter')
    and config_key='routing_eligible' and active=true and config_value='false';

  select max(c.occurred_at) into v_latest_click
  from public.pandora_tracking_clicks c
  join public.pandora_tracking_tenants t on t.id=c.tenant_id
  where t.organization_id=p_organization_id and t.project_id=p_project_id;

  select max(o.occurred_at) into v_latest_outcome
  from public.pandora_growth_outcome_receipts o
  where o.organization_id=p_organization_id and o.project_id=p_project_id;

  return jsonb_build_object(
    'ok',true,
    'authExpiryCheck','provider_specific_readback_required',
    'killSwitchActive',coalesce((v_zero#>>'{control,kill_switch_active}')::boolean,false),
    'spendAuthorized',coalesce((v_zero->>'spendAuthorized')::boolean,false),
    'providerRoutesDisabled',v_provider_disabled,
    'approvedMemoryReceipts',v_memory_count,
    'latestClickAt',v_latest_click,
    'latestOutcomeAt',v_latest_outcome,
    'runbookChecks',(select count(*) from public.pandora_growth_incident_runbook where enabled=true),
    'noMonitoringClaimed',true
  );
end;
$function$;
revoke all on function public.pandora_growth_health_snapshot_v1(uuid,uuid)
from public,anon,authenticated;
grant execute on function public.pandora_growth_health_snapshot_v1(uuid,uuid)
to service_role;

create table if not exists public.pandora_growth_tracker_evidence_runbook (
  id text primary key,
  schema_version text not null,
  steps jsonb not null check(jsonb_typeof(steps)='array'),
  evidence_rules jsonb not null check(jsonb_typeof(evidence_rules)='object'),
  memory_rules jsonb not null check(jsonb_typeof(memory_rules)='object'),
  approved_by text not null,
  approved_at timestamptz not null,
  updated_at timestamptz not null default clock_timestamp()
);
alter table public.pandora_growth_tracker_evidence_runbook enable row level security;
revoke all on public.pandora_growth_tracker_evidence_runbook from public,anon,authenticated;
grant select on public.pandora_growth_tracker_evidence_runbook to service_role;

insert into public.pandora_growth_tracker_evidence_runbook(
 id,schema_version,steps,evidence_rules,memory_rules,approved_by,approved_at
) values (
 'facebook-growth-tracker-v1','1.0.0',
 '[
   "Read provider/runtime state before claiming work.",
   "Update the execution tracker with exact task, dependency, acceptance and next action.",
   "Execute only within current authority; keep spend/client consent separate.",
   "Capture exact provider/runtime evidence ID, source link, verifier and timestamp.",
   "Mark Done only when the Evidence Log delivery row passes the task formula.",
   "Review outcome and promote only meaningful verified lessons through governed Memory."
 ]'::jsonb,
 '{"providerReadbackPreferred":true,"exactSourceRequiredForRelease":true,"noSuccessFromProviderAcceptanceAlone":true,"unknownRemainsUnknown":true,"rawPollingNoiseIsNotEvidence":true}'::jsonb,
 '{"rawEventsStayOutOfDurableMemory":true,"promoteVerifiedLessonsOnly":true,"retainSupersededHistory":true,"memoryDoesNotGrantSpendOrExecution":true}'::jsonb,
 'owner-current-chat-2026-10-01',clock_timestamp()
)
on conflict(id) do update
set schema_version=excluded.schema_version,steps=excluded.steps,evidence_rules=excluded.evidence_rules,
memory_rules=excluded.memory_rules,approved_by=excluded.approved_by,approved_at=excluded.approved_at,updated_at=clock_timestamp();

commit;
;
