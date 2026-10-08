-- PLP Enterprise live PayPal billing closure.
-- Live catalog IDs verified against PayPal live on 2026-10-08.
-- No credentials or tokens are stored in source.

insert into public.pandora_paypal_plan_links (plan_id, paypal_plan_id, currency, active)
values
  ('4975e1a8-535e-4b12-a0ea-2120dd9696b6','P-6HV700307G378832PNLDXSWY','USD',true),
  ('2d95d87b-b41b-4d55-908c-b9889766d04e','P-7D160645N8043213CNLDXSXA','USD',true)
on conflict (plan_id) do update
set paypal_plan_id=excluded.paypal_plan_id,
    currency=excluded.currency,
    active=true,
    updated_at=now();

create or replace function public.pandora_plp_billing_change_plan_v1(
  p_organization_id uuid,
  p_actor uuid,
  p_plan_code text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_sub public.pandora_customer_subscriptions%rowtype;
  v_plan public.pandora_service_plans%rowtype;
  v_link public.pandora_paypal_plan_links%rowtype;
  v_session public.pandora_paypal_plan_change_sessions%rowtype;
  v_response jsonb;
  v_body jsonb;
  v_approval text;
begin
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then
    raise exception 'INVALID_IDEMPOTENCY_KEY' using errcode='22023';
  end if;

  select * into v_sub
  from public.pandora_customer_subscriptions
  where organization_id=p_organization_id;

  if not found or v_sub.state not in ('trial','active','past_due') then
    raise exception 'SUBSCRIPTION_NOT_ACTIVE' using errcode='P0002';
  end if;

  if v_sub.provider_reference is null or v_sub.source_kind <> 'provider_verified' then
    raise exception 'RECONCILIATION_REQUIRED' using errcode='P0001';
  end if;

  select * into v_plan
  from public.pandora_service_plans
  where code=p_plan_code and state='active';

  if not found or v_plan.monthly_fee_micros is null then
    raise exception 'PLAN_NOT_FOUND' using errcode='P0002';
  end if;

  if v_plan.id=v_sub.plan_id then
    raise exception 'PLAN_UNCHANGED' using errcode='22023';
  end if;

  select * into v_link
  from public.pandora_paypal_plan_links
  where plan_id=v_plan.id and active;

  if not found then
    raise exception 'PLAN_PROVIDER_LINK_REQUIRED' using errcode='P0002';
  end if;

  select * into v_session
  from public.pandora_paypal_plan_change_sessions
  where organization_id=p_organization_id
    and idempotency_key=p_idempotency_key
  limit 1;

  if found then
    return jsonb_build_object(
      'replayed',true,
      'status',v_session.status,
      'approvalUrl',v_session.approval_url,
      'providerReference',v_session.provider_reference,
      'verified',v_session.status in ('provider_verified','completed')
    );
  end if;

  insert into public.pandora_paypal_plan_change_sessions (
    organization_id,requested_by,paypal_subscription_id,
    from_plan_id,to_plan_id,from_plan_code,to_plan_code,
    idempotency_key,status
  ) values (
    p_organization_id,p_actor,v_sub.provider_reference,
    v_sub.plan_id,v_plan.id,
    (select code from public.pandora_service_plans where id=v_sub.plan_id),
    v_plan.code,p_idempotency_key,'requested'
  )
  returning * into v_session;

  v_response:=private.pandora_paypal_billing_api_v1(
    'POST',
    '/v1/billing/subscriptions/'||v_sub.provider_reference||'/revise',
    jsonb_build_object('plan_id',v_link.paypal_plan_id),
    v_session.id::text
  );
  v_body:=coalesce(v_response->'body','{}'::jsonb);

  if coalesce((v_response->>'status')::int,0) not between 200 and 299 then
    update public.pandora_paypal_plan_change_sessions
    set status='failed',
        error_message=left(coalesce(v_body->>'message',v_body->>'name','PayPal plan change failed'),500),
        updated_at=now()
    where id=v_session.id;
    raise exception 'PAYPAL_PLAN_CHANGE_FAILED' using errcode='P0001';
  end if;

  select link->>'href' into v_approval
  from jsonb_array_elements(coalesce(v_body->'links','[]'::jsonb)) link
  where link->>'rel'='approve'
  limit 1;

  update public.pandora_paypal_plan_change_sessions
  set status=case when v_approval is null then 'requested' else 'approval_pending' end,
      approval_url=v_approval,
      provider_reference=v_sub.provider_reference,
      updated_at=now()
  where id=v_session.id
  returning * into v_session;

  return jsonb_build_object(
    'replayed',false,
    'status',v_session.status,
    'approvalUrl',v_session.approval_url,
    'providerReference',v_session.provider_reference,
    'verified',false
  );
end;
$function$;