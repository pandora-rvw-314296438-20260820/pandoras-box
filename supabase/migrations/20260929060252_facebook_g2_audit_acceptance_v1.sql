-- G2 acceptance audit: make edge cases and discrepancies explicit.
-- Read-only projection. No provider mutation, privacy grant, spend authority or campaign activation.
begin;

create or replace function public.pandora_facebook_g2_audit_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_tracking_campaign_id uuid
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_tenant_id uuid;
  v_campaign public.pandora_tracking_campaigns%rowtype;
  v_binding private.pandora_meta_measurement_bindings%rowtype;
  v_test_clicks bigint:=0;
  v_test_events bigint:=0;
  v_test_outcomes bigint:=0;
  v_business_kpi_rows bigint:=0;
  v_late_receipts bigint:=0;
  v_refund_receipts bigint:=0;
  v_marketing_withheld_events bigint:=0;
  v_consent_leaks bigint:=0;
  v_cost_rows bigint:=0;
  v_currencies jsonb:='[]'::jsonb;
  v_currency_count integer:=0;
  v_discrepancies jsonb:='[]'::jsonb;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_G2_AUDIT_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  select c.* into v_campaign
  from public.pandora_tracking_campaigns c
  join public.pandora_tracking_tenants t on t.id=c.tenant_id
  where c.id=p_tracking_campaign_id
    and t.organization_id=p_organization_id
    and t.project_id=p_project_id
    and t.status='active';
  if not found then
    raise exception 'PANDORA_G2_AUDIT_SCOPE_DENIED' using errcode='42501';
  end if;
  v_tenant_id:=v_campaign.tenant_id;

  select * into v_binding
  from private.pandora_meta_measurement_bindings b
  where b.organization_id=p_organization_id
    and b.project_id=p_project_id
    and b.tracking_tenant_id=v_tenant_id
    and b.tracking_campaign_id=p_tracking_campaign_id;

  select count(*) into v_test_clicks
  from public.pandora_tracking_clicks
  where tenant_id=v_tenant_id and campaign_id=p_tracking_campaign_id and is_test is true;

  select count(*) into v_test_events
  from public.pandora_tracking_events
  where tenant_id=v_tenant_id and campaign_id=p_tracking_campaign_id and is_test is true;

  select count(*) into v_test_outcomes
  from public.pandora_growth_outcome_receipts
  where organization_id=p_organization_id and project_id=p_project_id
    and tracking_tenant_id=v_tenant_id and is_test is true
    and (
      attribution#>>'{kind}'<>'observed'
      or exists (
        select 1 from public.pandora_tracking_clicks c
        where c.tenant_id=v_tenant_id
          and c.campaign_id=p_tracking_campaign_id
          and c.click_id=public.pandora_growth_outcome_receipts.attribution->>'click_id'
      )
    );

  select count(*) into v_business_kpi_rows
  from public.pandora_tracking_campaign_daily_v1
  where tenant_id=v_tenant_id and campaign_id=p_tracking_campaign_id;

  select count(*) into v_late_receipts
  from public.pandora_growth_outcome_receipts
  where organization_id=p_organization_id and project_id=p_project_id
    and tracking_tenant_id=v_tenant_id and is_test is true
    and received_at>occurred_at+interval '15 minutes';

  select count(*) into v_refund_receipts
  from public.pandora_growth_outcome_receipts
  where organization_id=p_organization_id and project_id=p_project_id
    and tracking_tenant_id=v_tenant_id and is_test is true
    and event_name='refund_settled';

  select count(*) into v_marketing_withheld_events
  from public.pandora_tracking_events e
  where e.tenant_id=v_tenant_id and e.campaign_id=p_tracking_campaign_id
    and e.is_test is true
    and e.source='server'
    and e.event_type in ('lead','qualified_lead','booking','sale')
    and coalesce((e.consent->>'marketing')::boolean,false) is false;

  select count(*) into v_consent_leaks
  from private.pandora_meta_conversion_outbox o
  join public.pandora_tracking_events e on e.id=o.tracking_event_id
  where o.organization_id=p_organization_id and o.project_id=p_project_id
    and e.tenant_id=v_tenant_id and e.campaign_id=p_tracking_campaign_id
    and coalesce((e.consent->>'marketing')::boolean,false) is false;

  select count(*) into v_cost_rows
  from public.pandora_tracking_costs
  where tenant_id=v_tenant_id and campaign_id=p_tracking_campaign_id;

  select coalesce(jsonb_agg(x.currency order by x.currency),'[]'::jsonb),count(*)::integer
  into v_currencies,v_currency_count
  from (
    select distinct currency
    from (
      select v_binding.account_currency as currency
      union all
      select currency from public.pandora_tracking_costs
        where tenant_id=v_tenant_id and campaign_id=p_tracking_campaign_id
      union all
      select currency from public.pandora_growth_outcome_receipts
        where organization_id=p_organization_id and project_id=p_project_id
          and tracking_tenant_id=v_tenant_id and is_test is false
    ) q
    where currency is not null
  ) x;

  select coalesce(jsonb_agg(flag order by flag),'[]'::jsonb)
  into v_discrepancies
  from (
    select flag from (values
      (case when v_binding.id is null then 'provider_binding_missing' end),
      (case when v_business_kpi_rows>0 then 'controlled_test_leaked_into_business_kpi' end),
      (case when v_consent_leaks>0 then 'consent_withdrawal_leak' end),
      (case when v_cost_rows=0 then 'provider_cost_data_missing_or_not_delivered' end),
      (case when v_currency_count>1 then 'mixed_currency_requires_separate_reporting' end),
      (case when v_late_receipts>0 then 'late_delivery_present' end)
    ) f(flag) where flag is not null
  ) d;

  return jsonb_build_object(
    'ok',true,
    'organizationId',p_organization_id,
    'projectId',p_project_id,
    'trackingCampaignId',p_tracking_campaign_id,
    'providerBinding',case when v_binding.id is null then null else jsonb_build_object(
      'bindingId',v_binding.id,
      'state',v_binding.binding_state,
      'campaignId',v_binding.meta_campaign_id,
      'adsetId',v_binding.meta_adset_id,
      'adId',v_binding.meta_ad_id,
      'currency',v_binding.account_currency,
      'timezone',v_binding.account_timezone
    ) end,
    'testTraffic',jsonb_build_object(
      'clicks',v_test_clicks,'events',v_test_events,'outcomes',v_test_outcomes,
      'businessKpiRows',v_business_kpi_rows,
      'excludedFromBusinessKpis',v_business_kpi_rows=0
    ),
    'lateDelivery',jsonb_build_object(
      'lateReceiptCount',v_late_receipts,
      'thresholdMinutes',15,
      'lateIsVisibleNotZeroed',true
    ),
    'refundCoverage',jsonb_build_object(
      'testRefundReceiptCount',v_refund_receipts,
      'refundIsSeparateOutcome',true
    ),
    'consentWithdrawal',jsonb_build_object(
      'eligibleEventCountWithMarketingFalse',v_marketing_withheld_events,
      'providerOutboxLeakCount',v_consent_leaks,
      'withheld',v_consent_leaks=0
    ),
    'currency',jsonb_build_object(
      'values',v_currencies,
      'state',case when v_currency_count=0 then 'unknown'
                   when v_currency_count=1 then 'single'
                   else 'mixed' end,
      'crossCurrencyAggregationAllowed',false
    ),
    'timezone',case when v_binding.id is null then null else v_binding.account_timezone end,
    'costData',jsonb_build_object(
      'rowCount',v_cost_rows,
      'missingIsZero',false,
      'state',case when v_cost_rows=0 then 'missing_or_not_delivered' else 'present' end
    ),
    'discrepancyFlags',v_discrepancies,
    'causalWinnerClaimed',false,
    'roasWinnerClaimed',false
  );
end;
$function$;

revoke all on function public.pandora_facebook_g2_audit_v1(uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.pandora_facebook_g2_audit_v1(uuid,uuid,uuid)
  to service_role;

comment on function public.pandora_facebook_g2_audit_v1(uuid,uuid,uuid) is
  'Read-only G2 acceptance projection. Makes late delivery, refunds, consent withholding, currency/timezone and discrepancy state explicit without inferring missing data or causality.';

commit;

