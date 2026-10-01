-- FB-027/FB-028: genuine, durable growth experiment evaluation.
-- Reads authoritative business-only tracking/cost data and records terminal results.
-- No provider mutation, spend authority, Memory promotion, or winner claim is granted.
begin;

create table if not exists private.pandora_growth_experiment_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  tracking_tenant_id uuid not null,
  tracking_campaign_id uuid not null,
  experiment_key text not null check (experiment_key ~ '^[a-z0-9][a-z0-9._:-]{1,95}$'),
  hypothesis text not null check (char_length(btrim(hypothesis)) between 1 and 1000),
  intended_business_outcome text not null
    check (char_length(btrim(intended_business_outcome)) between 1 and 500),
  window_start timestamptz not null,
  window_end timestamptz not null,
  attribution_method text not null
    check (attribution_method in ('first_party_observed','platform_reported','unattributed')),
  status text not null
    check (status in ('completed','insufficient_evidence','failed')),
  denominator_count bigint not null check (denominator_count >= 0),
  conversion_count bigint not null check (conversion_count >= 0),
  spend numeric(18,4),
  spend_currency text check (spend_currency is null or spend_currency ~ '^[A-Z]{3}$'),
  spend_state text not null check (spend_state in ('known','missing','mixed_currency')),
  conversion_delay_seconds numeric(18,4),
  conversion_delay_state text not null check (conversion_delay_state in ('known','unknown')),
  comparison_conditions jsonb not null check (jsonb_typeof(comparison_conditions)='object'),
  uncertainty jsonb not null check (jsonb_typeof(uncertainty)='object'),
  result jsonb not null check (jsonb_typeof(result)='object'),
  evidence jsonb not null check (jsonb_typeof(evidence)='object'),
  input_sha256 text not null check (input_sha256 ~ '^[0-9a-f]{64}$'),
  result_sha256 text not null check (result_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz not null default clock_timestamp(),
  constraint pandora_growth_experiment_window_v1_check check (window_end > window_start),
  unique(organization_id,project_id,experiment_key,window_start,window_end)
);

create table if not exists private.pandora_growth_experiment_receipts (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references private.pandora_growth_experiment_runs(id) on delete restrict,
  receipt_type text not null check (receipt_type in ('input_snapshot','terminal_result')),
  receipt_sha256 text not null check (receipt_sha256 ~ '^[0-9a-f]{64}$'),
  payload jsonb not null check (jsonb_typeof(payload)='object'),
  created_at timestamptz not null default clock_timestamp(),
  unique(run_id,receipt_type)
);

revoke all on private.pandora_growth_experiment_runs from public,anon,authenticated;
revoke all on private.pandora_growth_experiment_receipts from public,anon,authenticated;
grant select on private.pandora_growth_experiment_runs to service_role;
grant select on private.pandora_growth_experiment_receipts to service_role;

create or replace function public.pandora_growth_evaluate_experiment_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_tracking_campaign_id uuid,
  p_experiment_key text,
  p_hypothesis text,
  p_intended_business_outcome text,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_attribution_method text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','extensions'
as $function$
declare
  v_tenant public.pandora_tracking_tenants%rowtype;
  v_campaign public.pandora_tracking_campaigns%rowtype;
  v_run private.pandora_growth_experiment_runs%rowtype;
  v_input jsonb;
  v_result jsonb;
  v_evidence jsonb;
  v_comparison jsonb;
  v_uncertainty jsonb;
  v_input_sha text;
  v_result_sha text;
  v_denominator bigint:=0;
  v_conversions bigint:=0;
  v_cost_rows bigint:=0;
  v_currency_count bigint:=0;
  v_spend numeric(18,4);
  v_currency text;
  v_spend_state text;
  v_delay numeric(18,4);
  v_delay_state text;
  v_status text;
  v_input_receipt uuid;
  v_result_receipt uuid;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','') <> 'service_role' then
    raise exception 'PANDORA_GROWTH_EXPERIMENT_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_organization_id is null or p_project_id is null or p_tracking_campaign_id is null
    or p_experiment_key !~ '^[a-z0-9][a-z0-9._:-]{1,95}$'
    or char_length(btrim(coalesce(p_hypothesis,''))) not between 1 and 1000
    or char_length(btrim(coalesce(p_intended_business_outcome,''))) not between 1 and 500
    or p_window_start is null or p_window_end is null or p_window_end <= p_window_start
    or p_window_end - p_window_start > interval '90 days'
    or p_attribution_method not in ('first_party_observed','platform_reported','unattributed') then
    raise exception 'PANDORA_GROWTH_EXPERIMENT_INPUT_INVALID' using errcode='22023';
  end if;

  select t.* into v_tenant
  from public.pandora_tracking_tenants t
  join public.pandora_tracking_campaigns c on c.tenant_id=t.id
  where t.organization_id=p_organization_id
    and t.project_id=p_project_id
    and t.status='active'
    and c.id=p_tracking_campaign_id
    and c.status='active'
    and c.provider='meta'
  limit 1;
  if not found then
    raise exception 'PANDORA_GROWTH_EXPERIMENT_SCOPE_DENIED' using errcode='42501';
  end if;

  select * into v_campaign
  from public.pandora_tracking_campaigns c
  where c.id=p_tracking_campaign_id and c.tenant_id=v_tenant.id
  for share;
  if not found then
    raise exception 'PANDORA_GROWTH_EXPERIMENT_CAMPAIGN_DENIED' using errcode='42501';
  end if;

  v_input:=jsonb_build_object(
    'schemaVersion','growth-evaluate-experiment-input-v1',
    'organizationId',p_organization_id,
    'projectId',p_project_id,
    'trackingTenantId',v_tenant.id,
    'trackingCampaignId',p_tracking_campaign_id,
    'experimentKey',p_experiment_key,
    'hypothesis',btrim(p_hypothesis),
    'intendedBusinessOutcome',btrim(p_intended_business_outcome),
    'windowStart',p_window_start,
    'windowEnd',p_window_end,
    'attributionMethod',p_attribution_method,
    'testTrafficExcluded',true
  );
  v_input_sha:=encode(extensions.digest(convert_to(v_input::text,'UTF8'),'sha256'),'hex');

  select r.* into v_run
  from private.pandora_growth_experiment_runs r
  where r.organization_id=p_organization_id
    and r.project_id=p_project_id
    and r.experiment_key=p_experiment_key
    and r.window_start=p_window_start
    and r.window_end=p_window_end
  for update;
  if found then
    if v_run.input_sha256 is distinct from v_input_sha then
      raise exception 'PANDORA_GROWTH_EXPERIMENT_IDEMPOTENCY_CONFLICT' using errcode='23505';
    end if;
    select id into v_input_receipt
      from private.pandora_growth_experiment_receipts
      where run_id=v_run.id and receipt_type='input_snapshot';
    select id into v_result_receipt
      from private.pandora_growth_experiment_receipts
      where run_id=v_run.id and receipt_type='terminal_result';
    return jsonb_build_object(
      'ok',true,'duplicate',true,'runId',v_run.id,'status',v_run.status,
      'inputReceiptId',v_input_receipt,'resultReceiptId',v_result_receipt,
      'resultSha256',v_run.result_sha256,'result',v_run.result,
      'canonicalMemoryWritten',false,'spendAuthorized',false
    );
  end if;

  select count(*)::bigint into v_denominator
  from public.pandora_tracking_clicks c
  where c.tenant_id=v_tenant.id and c.campaign_id=p_tracking_campaign_id
    and c.is_test is false
    and c.occurred_at>=p_window_start and c.occurred_at<p_window_end;

  select count(*)::bigint into v_conversions
  from public.pandora_tracking_events e
  where e.tenant_id=v_tenant.id and e.campaign_id=p_tracking_campaign_id
    and e.is_test is false
    and e.event_type in ('lead','qualified_lead','booking','sale')
    and e.occurred_at>=p_window_start and e.occurred_at<p_window_end;

  select count(*)::bigint,
         count(distinct currency)::bigint,
         case when count(*)>0 and count(distinct currency)=1 then sum(spend)::numeric(18,4) else null end,
         case when count(*)>0 and count(distinct currency)=1 then max(currency) else null end
    into v_cost_rows,v_currency_count,v_spend,v_currency
  from public.pandora_tracking_costs c
  where c.tenant_id=v_tenant.id and c.campaign_id=p_tracking_campaign_id
    and c.bucket_date>=p_window_start::date and c.bucket_date<p_window_end::date + 1;

  v_spend_state:=case
    when v_cost_rows=0 then 'missing'
    when v_currency_count=1 then 'known'
    else 'mixed_currency'
  end;
  if v_spend_state<>'known' then v_spend:=null; v_currency:=null; end if;

  select round(avg(extract(epoch from (e.created_at-e.occurred_at)))::numeric,4)
    into v_delay
  from public.pandora_tracking_events e
  where e.tenant_id=v_tenant.id and e.campaign_id=p_tracking_campaign_id
    and e.is_test is false
    and e.event_type in ('lead','qualified_lead','booking','sale','refund')
    and e.occurred_at>=p_window_start and e.occurred_at<p_window_end;
  v_delay_state:=case when v_delay is null then 'unknown' else 'known' end;

  v_comparison:=jsonb_build_object(
    'design','single_campaign_observation',
    'baseline','not_available',
    'treatment','not_available',
    'sameWindowRequired',true,
    'sameAttributionMethodRequired',true,
    'testTrafficExcluded',true
  );
  v_uncertainty:=jsonb_build_object(
    'kind','insufficient_comparison',
    'denominator',v_denominator,
    'conversions',v_conversions,
    'pointEstimate',null,
    'interval',null,
    'causalInferenceAllowed',false
  );
  v_status:='insufficient_evidence';
  v_result:=jsonb_build_object(
    'schemaVersion','growth-evaluate-experiment-result-v1',
    'terminal',true,
    'status',v_status,
    'winner',null,
    'causalClaim',false,
    'reason','No approved comparison pair with sufficient business-only evidence exists for this window.',
    'spend',v_spend,
    'currency',v_currency,
    'spendState',v_spend_state,
    'denominator',v_denominator,
    'conversions',v_conversions,
    'conversionDelaySeconds',v_delay,
    'conversionDelayState',v_delay_state,
    'attributionMethod',p_attribution_method,
    'windowStart',p_window_start,
    'windowEnd',p_window_end,
    'comparisonConditions',v_comparison,
    'uncertainty',v_uncertainty
  );
  v_evidence:=jsonb_build_object(
    'trackingCampaignId',p_tracking_campaign_id,
    'providerCampaignId',v_campaign.provider_campaign_id,
    'providerAdsetId',v_campaign.provider_adset_id,
    'providerAdId',v_campaign.provider_ad_id,
    'businessKpi',case when v_campaign.metadata ? 'business_kpi'
      then v_campaign.metadata->'business_kpi' else 'true'::jsonb end,
    'testTrafficExcluded',true,
    'costRows',v_cost_rows
  );
  v_result_sha:=encode(extensions.digest(convert_to(v_result::text,'UTF8'),'sha256'),'hex');

  insert into private.pandora_growth_experiment_runs(
    organization_id,project_id,tracking_tenant_id,tracking_campaign_id,
    experiment_key,hypothesis,intended_business_outcome,window_start,window_end,
    attribution_method,status,denominator_count,conversion_count,spend,spend_currency,
    spend_state,conversion_delay_seconds,conversion_delay_state,
    comparison_conditions,uncertainty,result,evidence,input_sha256,result_sha256
  ) values (
    p_organization_id,p_project_id,v_tenant.id,p_tracking_campaign_id,
    p_experiment_key,btrim(p_hypothesis),btrim(p_intended_business_outcome),
    p_window_start,p_window_end,p_attribution_method,v_status,v_denominator,v_conversions,
    v_spend,v_currency,v_spend_state,v_delay,v_delay_state,
    v_comparison,v_uncertainty,v_result,v_evidence,v_input_sha,v_result_sha
  ) returning * into v_run;

  insert into private.pandora_growth_experiment_receipts(run_id,receipt_type,receipt_sha256,payload)
    values(v_run.id,'input_snapshot',v_input_sha,v_input)
    returning id into v_input_receipt;
  insert into private.pandora_growth_experiment_receipts(run_id,receipt_type,receipt_sha256,payload)
    values(v_run.id,'terminal_result',v_result_sha,v_result)
    returning id into v_result_receipt;

  return jsonb_build_object(
    'ok',true,'duplicate',false,'runId',v_run.id,'status',v_status,
    'inputReceiptId',v_input_receipt,'resultReceiptId',v_result_receipt,
    'resultSha256',v_result_sha,'result',v_result,
    'canonicalMemoryWritten',false,'spendAuthorized',false
  );
end;
$function$;

revoke all on function public.pandora_growth_evaluate_experiment_v1(
  uuid,uuid,uuid,text,text,text,timestamptz,timestamptz,text
) from public,anon,authenticated;
grant execute on function public.pandora_growth_evaluate_experiment_v1(
  uuid,uuid,uuid,text,text,text,timestamptz,timestamptz,text
) to service_role;

comment on function public.pandora_growth_evaluate_experiment_v1(
  uuid,uuid,uuid,text,text,text,timestamptz,timestamptz,text
) is 'Genuine service-only growth.evaluate_experiment job. Produces one durable terminal run and hash-bound input/result receipts from business-only evidence; insufficient evidence stays terminal and never becomes a winner claim.';

commit;

