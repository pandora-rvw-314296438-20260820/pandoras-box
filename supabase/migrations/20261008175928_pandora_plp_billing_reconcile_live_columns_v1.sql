create or replace function public.pandora_plp_billing_reconcile_v1(p_organization_id uuid, p_actor uuid) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, private as $$
declare v_sub public.pandora_customer_subscriptions%rowtype; v_session public.pandora_paypal_billing_sessions%rowtype; v_change public.pandora_paypal_plan_change_sessions%rowtype; v_reference text; v_response jsonb; v_body jsonb; v_state text; v_plan_id text; v_linked public.pandora_paypal_plan_links%rowtype;
begin
  select * into v_sub from public.pandora_customer_subscriptions where organization_id = p_organization_id;
  select * into v_session from public.pandora_paypal_billing_sessions where organization_id = p_organization_id order by created_at desc limit 1;
  select * into v_change from public.pandora_paypal_plan_change_sessions where organization_id = p_organization_id order by created_at desc limit 1;
  v_reference := coalesce(v_sub.provider_reference, v_session.paypal_subscription_id, v_change.paypal_subscription_id);
  if v_reference is null then return jsonb_build_object('verified', false, 'label', 'Provider state unavailable', 'reason', 'NO_PROVIDER_REFERENCE'); end if;
  v_response := private.pandora_paypal_billing_api_v1('GET', '/v1/billing/subscriptions/' || v_reference, null, p_organization_id::text);
  v_body := coalesce(v_response->'body', '{}'::jsonb);
  if coalesce((v_response->>'status')::int, 0) not between 200 and 299 then return jsonb_build_object('verified', false, 'label', 'Provider verification failed', 'reason', left(coalesce(v_body->>'name', 'PAYPAL_READ_FAILED'), 120)); end if;
  v_state := upper(coalesce(v_body->>'status', ''));
  v_plan_id := v_body->>'plan_id';
  select * into v_linked from public.pandora_paypal_plan_links where paypal_plan_id = v_plan_id and active;
  if v_state in ('ACTIVE', 'APPROVED') and v_linked.plan_id is not null then
    insert into public.pandora_customer_subscriptions (organization_id, plan_id, state, currency, monthly_fee_micros, setup_fee_micros, discount_micros, starts_on, renews_on, source_kind, provider_reference, verified_at, updated_by) select p_organization_id, v_linked.plan_id, 'active', v_linked.currency, p.monthly_fee_micros, 0, 0, current_date, nullif(v_body->'billing_info'->>'next_billing_time', '')::date, 'provider_verified', v_reference, now(), p_actor from public.pandora_service_plans p where p.id = v_linked.plan_id on conflict (organization_id) do update set plan_id = excluded.plan_id, state = 'active', currency = excluded.currency, monthly_fee_micros = excluded.monthly_fee_micros, source_kind = 'provider_verified', provider_reference = excluded.provider_reference, verified_at = now(), renews_on = excluded.renews_on, updated_by = excluded.updated_by, updated_at = now();
  elsif v_state = 'CANCELLED' then
    update public.pandora_customer_subscriptions set state = 'cancelled', source_kind = 'provider_verified', verified_at = now(), ends_on = current_date, updated_by = p_actor, updated_at = now() where organization_id = p_organization_id;
  else
    return jsonb_build_object('verified', false, 'label', 'Awaiting provider confirmation', 'providerState', v_state);
  end if;
  return jsonb_build_object('verified', true, 'label', 'Verified', 'providerState', v_state);
end; $$;
revoke all on function public.pandora_plp_billing_reconcile_v1(uuid, uuid) from public, anon, authenticated;
grant execute on function public.pandora_plp_billing_reconcile_v1(uuid, uuid) to service_role;