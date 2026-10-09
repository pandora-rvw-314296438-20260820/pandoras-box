create or replace function public.pandora_plp_billing_sandbox_reconcile_v1(p_organization_id uuid, p_actor uuid) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, private as $$
declare v_session public.pandora_paypal_sandbox_billing_sessions%rowtype; v_response jsonb; v_state text;
begin
  select * into v_session from public.pandora_paypal_sandbox_billing_sessions where organization_id = p_organization_id and environment = 'sandbox' and paypal_subscription_id is not null order by created_at desc limit 1;
  if not found then return jsonb_build_object('verified', false, 'label', 'Provider state unavailable', 'reason', 'NO_PROVIDER_REFERENCE'); end if;
  v_response := private.pandora_paypal_sandbox_call_v1('GET', '/v1/billing/subscriptions/' || v_session.paypal_subscription_id, null);
  if coalesce((v_response->>'status')::int, 0) not between 200 and 299 then return jsonb_build_object('verified', false, 'label', 'Provider verification failed', 'reason', left(coalesce(v_response->'body'->>'name', 'PAYPAL_READ_FAILED'), 80)); end if;
  v_state := upper(coalesce(v_response->'body'->>'status', ''));
  if v_state = 'ACTIVE' then
    insert into public.pandora_paypal_sandbox_subscriptions (organization_id, environment, plan_id, state, currency, monthly_fee_micros, starts_on, source_kind, provider_reference, provider_status, verified_at, updated_by)
    select p_organization_id, 'sandbox', v_session.plan_id, 'active', p.currency, p.monthly_fee_micros, current_date, 'provider_verified', v_session.paypal_subscription_id, v_state, now(), p_actor from public.pandora_service_plans p where p.id = v_session.plan_id
    on conflict (organization_id) do update set state = 'active', source_kind = 'provider_verified', provider_status = excluded.provider_status, provider_reference = excluded.provider_reference, verified_at = now(), updated_at = now();
    update public.pandora_paypal_sandbox_billing_sessions set status = 'active', updated_at = now() where id = v_session.id;
    return jsonb_build_object('verified', true, 'label', 'Verified', 'providerState', v_state);
  end if;
  return jsonb_build_object('verified', false, 'label', 'Awaiting provider confirmation', 'providerState', v_state, 'providerReference', v_session.paypal_subscription_id);
end; $$;
revoke all on function public.pandora_plp_billing_sandbox_reconcile_v1(uuid, uuid) from public, anon, authenticated;
grant execute on function public.pandora_plp_billing_sandbox_reconcile_v1(uuid, uuid) to service_role;
create or replace function public.pandora_plp_billing_sandbox_cancel_v1(p_organization_id uuid, p_actor uuid, p_reason text) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, private as $$
declare v_session public.pandora_paypal_sandbox_billing_sessions%rowtype; v_response jsonb; v_state text;
begin
  select * into v_session from public.pandora_paypal_sandbox_billing_sessions where organization_id = p_organization_id and environment = 'sandbox' and paypal_subscription_id is not null order by created_at desc limit 1;
  if not found then return jsonb_build_object('cancelled', false, 'reason', 'NO_PROVIDER_REFERENCE'); end if;
  v_response := private.pandora_paypal_sandbox_call_v1('POST', '/v1/billing/subscriptions/' || v_session.paypal_subscription_id || '/cancel', jsonb_build_object('reason', left(coalesce(p_reason, 'PLP sandbox lifecycle validation'), 128)));
  if coalesce((v_response->>'status')::int, 0) not between 200 and 299 then return jsonb_build_object('cancelled', false, 'providerStatus', v_response->>'status', 'reason', left(coalesce(v_response->'body'->>'name', 'PAYPAL_CANCEL_FAILED'), 80)); end if;
  v_response := private.pandora_paypal_sandbox_call_v1('GET', '/v1/billing/subscriptions/' || v_session.paypal_subscription_id, null);
  v_state := upper(coalesce(v_response->'body'->>'status', ''));
  update public.pandora_paypal_sandbox_billing_sessions set status = 'cancelled', updated_at = now() where id = v_session.id;
  return jsonb_build_object('cancelled', v_state in ('CANCELLED', 'EXPIRED'), 'providerState', v_state, 'verified', false);
end; $$;
revoke all on function public.pandora_plp_billing_sandbox_cancel_v1(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.pandora_plp_billing_sandbox_cancel_v1(uuid, uuid, text) to service_role;