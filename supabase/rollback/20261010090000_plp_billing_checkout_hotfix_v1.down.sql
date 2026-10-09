-- Snapshot of LIVE production function bodies (project jcyqixttuebxqqfkjonq), read via pg_get_functiondef on 2026-10-10 ~06:45 PHT.
-- md5(pg_get_functiondef): checkout ab1e404da8e68ba2913f8bfd7dba00f2, reconcile 4555d1f377d2024c13b9687a2630c0aa, status 1f7a1edbeac89fc88349a1a0982ce7af
-- Purpose: exact rollback target for the PLP checkout hotfix. NOTE: these bodies are the broken ones (checkout 42703 on created_by; reconcile CHECK violation).
begin;
CREATE OR REPLACE FUNCTION public.pandora_plp_billing_checkout_v1(p_organization_id uuid, p_actor uuid, p_plan_code text, p_idempotency_key text, p_return_url text, p_cancel_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_plan public.pandora_service_plans%rowtype; v_link public.pandora_paypal_plan_links%rowtype; v_existing public.pandora_paypal_billing_sessions%rowtype; v_session public.pandora_paypal_billing_sessions%rowtype; v_response jsonb; v_body jsonb; v_approval text; v_reference text;
begin
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then raise exception 'INVALID_IDEMPOTENCY_KEY' using errcode = '22023'; end if;
  if p_return_url is null or p_return_url !~ '^https://' or p_cancel_url is null or p_cancel_url !~ '^https://' then raise exception 'INVALID_RETURN_URL' using errcode = '22023'; end if;
  select * into v_existing from public.pandora_paypal_billing_sessions where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then return jsonb_build_object('replayed', true, 'status', v_existing.status, 'approvalUrl', v_existing.approval_url, 'providerReference', v_existing.provider_reference); end if;
  if exists (select 1 from public.pandora_customer_subscriptions where organization_id = p_organization_id and state in ('trial','active','past_due')) then raise exception 'SUBSCRIPTION_ALREADY_ACTIVE' using errcode = '23505'; end if;
  select * into v_plan from public.pandora_service_plans where code = p_plan_code and state = 'active';
  if not found then raise exception 'PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into v_link from public.pandora_paypal_plan_links where plan_id = v_plan.id and active;
  if not found then raise exception 'PLAN_PROVIDER_LINK_REQUIRED' using errcode = 'P0002'; end if;
  insert into public.pandora_paypal_billing_sessions (organization_id, plan_id, idempotency_key, status, created_by) values (p_organization_id, v_plan.id, p_idempotency_key, 'requested', p_actor) returning * into v_session;
  v_response := private.pandora_paypal_billing_api_v1('POST','/v1/billing/subscriptions', jsonb_build_object('plan_id', v_link.paypal_plan_id, 'custom_id', v_session.id::text, 'application_context', jsonb_build_object('brand_name','PLP Enterprise','user_action','SUBSCRIBE_NOW','return_url', p_return_url,'cancel_url', p_cancel_url)), v_session.id::text);
  v_body := coalesce(v_response->'body','{}'::jsonb);
  if coalesce((v_response->>'status')::int, 0) not between 200 and 299 then
    update public.pandora_paypal_billing_sessions set status='failed', error_message=left(coalesce(v_body->>'message', v_body->>'name', 'PayPal checkout failed'),500), updated_at=now() where id=v_session.id;
    raise exception 'PAYPAL_CHECKOUT_FAILED' using errcode='P0001';
  end if;
  v_reference := nullif(v_body->>'id','');
  select link->>'href' into v_approval from jsonb_array_elements(coalesce(v_body->'links','[]'::jsonb)) link where link->>'rel'='approve' limit 1;
  update public.pandora_paypal_billing_sessions set status=case when v_approval is null then 'requested' else 'approval_pending' end, provider_reference=v_reference, approval_url=v_approval, updated_at=now() where id=v_session.id returning * into v_session;
  return jsonb_build_object('status', v_session.status, 'approvalUrl', v_session.approval_url, 'providerReference', v_session.provider_reference, 'verified', false);
end; $function$;

CREATE OR REPLACE FUNCTION public.pandora_plp_billing_reconcile_v1(p_organization_id uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_sub public.pandora_customer_subscriptions%rowtype;
  v_session public.pandora_paypal_billing_sessions%rowtype;
  v_change public.pandora_paypal_plan_change_sessions%rowtype;
  v_reference text;
  v_response jsonb;
  v_body jsonb;
  v_state text;
  v_plan_id text;
  v_linked public.pandora_paypal_plan_links%rowtype;
begin
  select * into v_sub
  from public.pandora_customer_subscriptions
  where organization_id = p_organization_id;

  select * into v_session
  from public.pandora_paypal_billing_sessions
  where organization_id = p_organization_id
  order by created_at desc
  limit 1;

  select * into v_change
  from public.pandora_paypal_plan_change_sessions
  where organization_id = p_organization_id
  order by created_at desc
  limit 1;

  v_reference := coalesce(
    v_sub.provider_reference,
    v_session.paypal_subscription_id,
    v_change.paypal_subscription_id
  );

  if v_reference is null then
    return jsonb_build_object(
      'verified', false,
      'label', 'Provider state unavailable',
      'reason', 'NO_PROVIDER_REFERENCE'
    );
  end if;

  v_response := private.pandora_paypal_billing_api_v1(
    'GET',
    '/v1/billing/subscriptions/' || v_reference,
    null,
    p_organization_id::text
  );
  v_body := coalesce(v_response->'body', '{}'::jsonb);

  if coalesce((v_response->>'status')::int, 0) not between 200 and 299 then
    return jsonb_build_object(
      'verified', false,
      'label', 'Provider verification failed',
      'reason', left(coalesce(v_body->>'name', 'PAYPAL_READ_FAILED'), 120),
      'providerStatus', v_response->>'status',
      'providerDebugId', v_body->>'debug_id'
    );
  end if;

  v_state := upper(coalesce(v_body->>'status', ''));
  v_plan_id := v_body->>'plan_id';

  select * into v_linked
  from public.pandora_paypal_plan_links
  where paypal_plan_id = v_plan_id and active;

  if v_state = 'ACTIVE' and v_linked.plan_id is not null then
    insert into public.pandora_customer_subscriptions (
      organization_id,
      plan_id,
      state,
      currency,
      monthly_fee_micros,
      setup_fee_micros,
      discount_micros,
      starts_on,
      renews_on,
      source_kind,
      provider_reference,
      verified_at,
      updated_by
    )
    select
      p_organization_id,
      v_linked.plan_id,
      'active',
      v_linked.currency,
      p.monthly_fee_micros,
      0,
      0,
      current_date,
      nullif(v_body->'billing_info'->>'next_billing_time', '')::date,
      'provider_verified',
      v_reference,
      now(),
      p_actor
    from public.pandora_service_plans p
    where p.id = v_linked.plan_id
    on conflict (organization_id) do update set
      plan_id = excluded.plan_id,
      state = 'active',
      currency = excluded.currency,
      monthly_fee_micros = excluded.monthly_fee_micros,
      source_kind = 'provider_verified',
      provider_reference = excluded.provider_reference,
      verified_at = now(),
      renews_on = excluded.renews_on,
      updated_by = excluded.updated_by,
      updated_at = now();

    update public.pandora_paypal_billing_sessions
    set status = 'provider_verified', updated_at = now()
    where organization_id = p_organization_id
      and paypal_subscription_id = v_reference;

    return jsonb_build_object(
      'verified', true,
      'label', 'Verified',
      'providerState', v_state,
      'providerReference', v_reference
    );
  elsif v_state = 'CANCELLED' then
    update public.pandora_customer_subscriptions
    set
      state = 'cancelled',
      source_kind = 'provider_verified',
      verified_at = now(),
      ends_on = current_date,
      updated_by = p_actor,
      updated_at = now()
    where organization_id = p_organization_id;

    return jsonb_build_object(
      'verified', true,
      'label', 'Verified cancellation',
      'providerState', v_state,
      'providerReference', v_reference
    );
  end if;

  return jsonb_build_object(
    'verified', false,
    'label', 'Awaiting provider confirmation',
    'providerState', v_state,
    'providerReference', v_reference
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.pandora_plp_billing_status_v1(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_subscription jsonb; v_plans jsonb; v_change jsonb; v_checkout jsonb; v_activity jsonb; v_configured boolean;
begin
  if p_organization_id is null then raise exception 'ORGANIZATION_REQUIRED' using errcode = '22023'; end if;
  select (exists (select 1 from vault.decrypted_secrets where name = 'paypal_client_id' and nullif(btrim(decrypted_secret), '') is not null) and exists (select 1 from vault.decrypted_secrets where name = 'paypal_client_secret' and nullif(btrim(decrypted_secret), '') is not null)) into v_configured;
  select jsonb_build_object('plan_id', s.plan_id, 'plan_code', p.code, 'plan_name', p.name, 'state', s.state, 'currency', s.currency, 'monthly_fee', private.pandora_plp_billing_money(s.monthly_fee_micros), 'monthly_fee_micros', s.monthly_fee_micros, 'setup_fee', private.pandora_plp_billing_money(s.setup_fee_micros), 'setup_fee_micros', s.setup_fee_micros, 'discount', private.pandora_plp_billing_money(s.discount_micros), 'discount_micros', s.discount_micros, 'net_monthly_fee', private.pandora_plp_billing_money(coalesce(s.monthly_fee_micros, 0) - s.discount_micros), 'starts_on', s.starts_on, 'ends_on', s.ends_on, 'renews_on', s.renews_on, 'source_kind', s.source_kind, 'provider_reference', s.provider_reference, 'verified_at', s.verified_at, 'updated_at', s.updated_at, 'verification_label', case when s.source_kind = 'provider_verified' and s.verified_at is not null then 'Verified' when s.provider_reference is not null then 'Reconciliation required' else 'Awaiting provider confirmation' end) into v_subscription from public.pandora_customer_subscriptions s join public.pandora_service_plans p on p.id = s.plan_id where s.organization_id = p_organization_id;
  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.monthly_fee_micros nulls last, x.code), '[]'::jsonb) into v_plans from (select p.id as plan_id, p.code, p.name, p.currency, private.pandora_plp_billing_money(p.monthly_fee_micros) as monthly_fee, p.monthly_fee_micros, l.paypal_plan_id is not null and l.active as provider_linked from public.pandora_service_plans p left join public.pandora_paypal_plan_links l on l.plan_id = p.id and l.active where p.state = 'active') x;
  select jsonb_build_object('id', c.id, 'from_plan_code', c.from_plan_code, 'to_plan_code', c.to_plan_code, 'provider_subscription', c.paypal_subscription_id, 'status', c.status, 'approval_url', c.approval_url, 'provider_reference', c.provider_reference, 'error_message', c.error_message, 'created_at', c.created_at, 'updated_at', c.updated_at, 'completed_at', c.completed_at, 'trust', case when c.status in ('provider_verified', 'completed') then 'provider' when c.status = 'approval_pending' then 'pending_action' when c.status = 'failed' then 'failed' else 'local_request' end) into v_change from public.pandora_paypal_plan_change_sessions c where c.organization_id = p_organization_id order by c.created_at desc limit 1;
  select jsonb_build_object('id', b.id, 'plan_code', b.plan_code, 'status', b.status, 'provider_reference', b.paypal_subscription_id, 'approval_url', b.approval_url, 'created_at', b.created_at, 'updated_at', b.updated_at, 'trust', case when b.status in ('provider_verified', 'completed') then 'provider' when b.status = 'approval_pending' then 'pending_action' when b.status = 'failed' then 'failed' else 'local_request' end) into v_checkout from public.pandora_paypal_billing_sessions b where b.organization_id = p_organization_id order by b.created_at desc limit 1;
  select coalesce(jsonb_agg(item order by item->>'occurred_at' desc), '[]'::jsonb) into v_activity from (select jsonb_build_object('kind','payment','trust', case when pay.source_kind = 'provider_verified' then 'provider' else 'local_request' end, 'title', case pay.payment_kind when 'refund' then 'Refund recorded' else 'Payment recorded' end, 'detail', pay.reference, 'occurred_at', pay.occurred_on, 'verified_at', pay.verified_at, 'amount', private.pandora_plp_billing_money(pay.amount_micros), 'currency', pay.currency) as item from public.pandora_customer_payments pay where pay.organization_id = p_organization_id union all select jsonb_build_object('kind','webhook','trust', case when w.processed_at is not null then 'provider' else 'local_request' end, 'title', w.event_type, 'detail', w.processing_status, 'occurred_at', w.received_at, 'verified_at', w.processed_at, 'provider_reference', w.provider_event_id) from public.pandora_paypal_billing_webhook_events w where w.organization_id = p_organization_id union all select jsonb_build_object('kind','plan_change','trust', case when c.status in ('provider_verified','completed') then 'provider' else 'local_request' end, 'title', 'Plan change ' || c.status, 'detail', coalesce(c.from_plan_code, 'Current') || ' -> ' || c.to_plan_code, 'occurred_at', c.updated_at, 'status', c.status) from public.pandora_paypal_plan_change_sessions c where c.organization_id = p_organization_id union all select jsonb_build_object('kind','checkout','trust', case when b.status in ('provider_verified','completed') then 'provider' else 'local_request' end, 'title', 'Checkout ' || b.status, 'detail', b.plan_code, 'occurred_at', b.updated_at, 'status', b.status) from public.pandora_paypal_billing_sessions b where b.organization_id = p_organization_id) events limit 12;
  return jsonb_build_object('provider', jsonb_build_object('name','paypal','configured', coalesce(v_configured, false), 'label', case when coalesce(v_configured, false) then 'PayPal' else 'Provider state unavailable' end), 'subscription', v_subscription, 'plans', v_plans, 'pendingPlanChange', v_change, 'checkout', v_checkout, 'activity', coalesce(v_activity, '[]'::jsonb));
end; $function$;
commit;
