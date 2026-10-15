create or replace function public.pandora_plp_billing_status_v1(p_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_subscription jsonb;
  v_plans jsonb;
  v_change jsonb;
  v_checkout jsonb;
  v_activity jsonb;
  v_configured boolean;
begin
  if p_organization_id is null then
    raise exception 'ORGANIZATION_REQUIRED' using errcode = '22023';
  end if;
  select (
    exists (select 1 from vault.decrypted_secrets where name = 'paypal_client_id' and nullif(btrim(decrypted_secret), '') is not null)
    and exists (select 1 from vault.decrypted_secrets where name = 'paypal_client_secret' and nullif(btrim(decrypted_secret), '') is not null)
  ) into v_configured;
  select jsonb_build_object(
    'plan_id', s.plan_id, 'plan_code', p.code, 'plan_name', p.name, 'state', s.state, 'currency', s.currency,
    'monthly_fee', private.pandora_plp_billing_money(s.monthly_fee_micros), 'monthly_fee_micros', s.monthly_fee_micros,
    'setup_fee', private.pandora_plp_billing_money(s.setup_fee_micros), 'setup_fee_micros', s.setup_fee_micros,
    'discount', private.pandora_plp_billing_money(s.discount_micros), 'discount_micros', s.discount_micros,
    'net_monthly_fee', private.pandora_plp_billing_money(coalesce(s.monthly_fee_micros, 0) - s.discount_micros),
    'starts_on', s.starts_on, 'ends_on', s.ends_on, 'renews_on', s.renews_on, 'source_kind', s.source_kind,
    'provider_reference', s.provider_reference, 'verified_at', s.verified_at, 'updated_at', s.updated_at,
    'verification_label', case when s.source_kind = 'provider_verified' and s.verified_at is not null then 'Verified' when s.provider_reference is not null then 'Reconciliation required' else 'Awaiting provider confirmation' end
  ) into v_subscription
  from public.pandora_customer_subscriptions s
  join public.pandora_service_plans p on p.id = s.plan_id
  where s.organization_id = p_organization_id;
  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.monthly_fee_micros nulls last, x.code), '[]'::jsonb) into v_plans
  from (
    select p.id as plan_id, p.code, p.name, p.currency, private.pandora_plp_billing_money(p.monthly_fee_micros) as monthly_fee, p.monthly_fee_micros, l.paypal_plan_id is not null and l.active as provider_linked
    from public.pandora_service_plans p
    left join public.pandora_paypal_plan_links l on l.plan_id = p.id and l.active
    where p.state = 'active'
  ) x;
  select jsonb_build_object('id', c.id, 'from_plan_id', c.from_plan_id, 'from_plan_code', fp.code, 'from_plan_name', fp.name, 'to_plan_id', c.to_plan_id, 'to_plan_code', tp.code, 'to_plan_name', tp.name, 'provider_subscription', c.provider_subscription, 'status', c.status, 'approval_url', c.approval_url, 'provider_reference', c.provider_reference, 'error_message', c.error_message, 'created_at', c.created_at, 'updated_at', c.updated_at, 'completed_at', c.completed_at, 'price_delta', private.pandora_plp_billing_money(coalesce(tp.monthly_fee_micros, 0) - coalesce(fp.monthly_fee_micros, 0)), 'currency', tp.currency, 'trust', case when c.status in ('provider_verified', 'completed') then 'provider' when c.status = 'approval_pending' then 'pending_action' when c.status = 'failed' then 'failed' else 'local_request' end)
  into v_change
  from public.pandora_paypal_plan_change_sessions c
  join public.pandora_service_plans tp on tp.id = c.to_plan_id
  left join public.pandora_service_plans fp on fp.id = c.from_plan_id
  where c.organization_id = p_organization_id
  order by c.created_at desc limit 1;
  select jsonb_build_object('id', b.id, 'plan_id', b.plan_id, 'plan_code', p.code, 'plan_name', p.name, 'status', b.status, 'provider_reference', b.provider_reference, 'approval_url', b.approval_url, 'error_message', b.error_message, 'created_at', b.created_at, 'updated_at', b.updated_at, 'completed_at', b.completed_at, 'trust', case when b.status in ('provider_verified', 'completed') then 'provider' when b.status = 'approval_pending' then 'pending_action' when b.status = 'failed' then 'failed' else 'local_request' end)
  into v_checkout
  from public.pandora_paypal_billing_sessions b
  join public.pandora_service_plans p on p.id = b.plan_id
  where b.organization_id = p_organization_id
  order by b.created_at desc limit 1;
  select coalesce(jsonb_agg(item order by item->>'occurred_at' desc), '[]'::jsonb) into v_activity
  from (
    select jsonb_build_object('kind','payment','trust', case when pay.source_kind = 'provider_verified' then 'provider' else 'local_request' end, 'title', case pay.payment_kind when 'refund' then 'Refund recorded' else 'Payment recorded' end, 'detail', pay.reference, 'occurred_at', pay.occurred_on, 'verified_at', pay.verified_at, 'amount', private.pandora_plp_billing_money(pay.amount_micros), 'currency', pay.currency) as item
    from public.pandora_customer_payments pay where pay.organization_id = p_organization_id
    union all
    select jsonb_build_object('kind','webhook','trust','provider','title', w.event_type, 'detail', w.summary, 'occurred_at', w.received_at, 'verified_at', w.verified_at, 'provider_reference', w.provider_reference)
    from public.pandora_paypal_billing_webhook_events w where w.organization_id = p_organization_id
    union all
    select jsonb_build_object('kind','plan_change','trust', case when c.status in ('provider_verified','completed') then 'provider' else 'local_request' end, 'title', 'Plan change ' || c.status, 'detail', coalesce(fp.name, 'Current') || ' → ' || tp.name, 'occurred_at', c.updated_at, 'verified_at', case when c.status in ('provider_verified','completed') then c.completed_at else null end, 'status', c.status)
    from public.pandora_paypal_plan_change_sessions c
    join public.pandora_service_plans tp on tp.id = c.to_plan_id
    left join public.pandora_service_plans fp on fp.id = c.from_plan_id
    where c.organization_id = p_organization_id
    union all
    select jsonb_build_object('kind','checkout','trust', case when b.status in ('provider_verified','completed') then 'provider' else 'local_request' end, 'title', 'Checkout ' || b.status, 'detail', p.name, 'occurred_at', b.updated_at, 'verified_at', case when b.status in ('provider_verified','completed') then b.completed_at else null end, 'status', b.status)
    from public.pandora_paypal_billing_sessions b
    join public.pandora_service_plans p on p.id = b.plan_id
    where b.organization_id = p_organization_id
  ) events limit 12;
  return jsonb_build_object('provider', jsonb_build_object('name','paypal','configured', coalesce(v_configured, false), 'label', case when coalesce(v_configured, false) then 'PayPal' else 'Provider state unavailable' end), 'subscription', v_subscription, 'plans', v_plans, 'pendingPlanChange', v_change, 'checkout', v_checkout, 'activity', coalesce(v_activity, '[]'::jsonb));
end;
$$;
revoke all on function public.pandora_plp_billing_status_v1(uuid) from public, anon, authenticated;
grant execute on function public.pandora_plp_billing_status_v1(uuid) to service_role;