
begin;

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
  v_payments bigint:=0;
  v_refunds bigint:=0;
  v_retention_count bigint:=0;
  v_receipts_minor bigint:=0;
  v_refunds_minor bigint:=0;
  v_outcome_currency_count integer:=0;
  v_outcome_currency text;
  v_spend numeric;
  v_spend_currency_count integer:=0;
  v_spend_currency text;
  v_delivery_cost numeric;
  v_retained numeric;
  v_missing text[]:='{}'::text[];
begin
  select
    count(*) filter(where event_name='paid_activation' and is_test=false),
    count(*) filter(where event_name='payment_settled' and is_test=false),
    count(*) filter(where event_name='refund_settled' and is_test=false),
    count(*) filter(where event_name='retention_observed' and is_test=false),
    coalesce(sum(amount_minor) filter(where event_name='payment_settled' and is_test=false),0),
    coalesce(sum(amount_minor) filter(where event_name='refund_settled' and is_test=false),0),
    count(distinct currency) filter(where event_name in ('payment_settled','refund_settled') and is_test=false and currency is not null),
    min(currency) filter(where event_name in ('payment_settled','refund_settled') and is_test=false and currency is not null)
  into v_paid,v_payments,v_refunds,v_retention_count,v_receipts_minor,v_refunds_minor,v_outcome_currency_count,v_outcome_currency
  from public.pandora_growth_outcome_receipts
  where organization_id=p_organization_id and project_id=p_project_id;

  select
    sum(f.spend),
    count(distinct f.currency) filter(where f.currency is not null),
    min(f.currency) filter(where f.currency is not null)
  into v_spend,v_spend_currency_count,v_spend_currency
  from public.pandora_tracking_campaign_financial_daily_v2 f
  join public.pandora_tracking_tenants t on t.id=f.tenant_id
  where t.organization_id=p_organization_id
    and t.project_id=p_project_id;

  if v_paid=0 then v_missing:=array_append(v_missing,'paid_activation'); end if;
  if v_payments=0 then v_missing:=array_append(v_missing,'payment_settled'); end if;
  if v_spend is null then v_missing:=array_append(v_missing,'paid_media_spend'); end if;
  if v_outcome_currency_count>1 or v_spend_currency_count>1
     or (v_outcome_currency is not null and v_spend_currency is not null and v_outcome_currency<>v_spend_currency) then
    v_missing:=array_append(v_missing,'single_currency_reconciliation');
  end if;
  v_missing:=array_append(v_missing,'delivery_cost');
  if v_retention_count=0 then v_missing:=array_append(v_missing,'retention_observation'); end if;

  return jsonb_build_object(
    'ok',true,
    'complete',cardinality(v_missing)=0,
    'paidActivations',v_paid,
    'settledPayments',v_payments,
    'refunds',v_refunds,
    'retentionObservations',v_retention_count,
    'currency',coalesce(v_outcome_currency,v_spend_currency),
    'grossReceiptsMinor',case when v_payments>0 then v_receipts_minor else null end,
    'refundsMinor',case when v_refunds>0 then v_refunds_minor else 0 end,
    'netReceiptsMinor',case when v_payments>0 and v_outcome_currency_count<=1 then v_receipts_minor-v_refunds_minor else null end,
    'paidMediaSpend',v_spend,
    'deliveryCost',v_delivery_cost,
    'retainedValue',v_retained,
    'contribution',null,
    'missingInputs',to_jsonb(v_missing),
    'testTrafficExcluded',true,
    'unknownInputsRemainUnknown',true,
    'mixedCurrencyClaimsDenied',true
  );
end;
$function$;

commit;
;
