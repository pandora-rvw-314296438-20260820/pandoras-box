create or replace function public.pandora_plp_billing_checkout_v1(p_organization_id uuid, p_actor uuid, p_plan_code text, p_idempotency_key text, p_return_url text, p_cancel_url text) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, private as $$
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
end; $$;
revoke all on function public.pandora_plp_billing_checkout_v1(uuid,uuid,text,text,text,text) from public, anon, authenticated;
grant execute on function public.pandora_plp_billing_checkout_v1(uuid,uuid,text,text,text,text) to service_role;
create or replace function public.pandora_plp_billing_change_plan_v1(p_organization_id uuid, p_actor uuid, p_plan_code text, p_idempotency_key text) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, private as $$
declare v_sub public.pandora_customer_subscriptions%rowtype; v_plan public.pandora_service_plans%rowtype; v_link public.pandora_paypal_plan_links%rowtype;
begin
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then raise exception 'INVALID_IDEMPOTENCY_KEY' using errcode='22023'; end if;
  select * into v_sub from public.pandora_customer_subscriptions where organization_id=p_organization_id;
  if not found or v_sub.state not in ('trial','active','past_due') then raise exception 'SUBSCRIPTION_NOT_ACTIVE' using errcode='P0002'; end if;
  if v_sub.provider_reference is null or v_sub.source_kind <> 'provider_verified' then raise exception 'RECONCILIATION_REQUIRED' using errcode='P0001'; end if;
  select * into v_plan from public.pandora_service_plans where code=p_plan_code and state='active';
  if not found then raise exception 'PLAN_NOT_FOUND' using errcode='P0002'; end if;
  if v_plan.id = v_sub.plan_id then raise exception 'PLAN_UNCHANGED' using errcode='22023'; end if;
  select * into v_link from public.pandora_paypal_plan_links where plan_id=v_plan.id and active;
  if not found then raise exception 'PLAN_PROVIDER_LINK_REQUIRED' using errcode='P0002'; end if;
  return jsonb_build_object('status','requested','verified', false);
end; $$;
revoke all on function public.pandora_plp_billing_change_plan_v1(uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function public.pandora_plp_billing_change_plan_v1(uuid,uuid,text,text) to service_role;
create or replace function public.pandora_plp_billing_reconcile_v1(p_organization_id uuid, p_actor uuid) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, private as $$
declare v_sub public.pandora_customer_subscriptions%rowtype; v_reference text;
begin
  select * into v_sub from public.pandora_customer_subscriptions where organization_id=p_organization_id;
  v_reference := v_sub.provider_reference;
  if v_reference is null then return jsonb_build_object('verified', false, 'label', 'Provider state unavailable', 'reason', 'NO_PROVIDER_REFERENCE'); end if;
  return jsonb_build_object('verified', false, 'label', 'Provider verification failed', 'reason', 'NOT_IMPLEMENTED_IN_THIS_CALL');
end; $$;
revoke all on function public.pandora_plp_billing_reconcile_v1(uuid,uuid) from public, anon, authenticated;
grant execute on function public.pandora_plp_billing_reconcile_v1(uuid,uuid) to service_role;
create or replace function public.pandora_plp_billing_cancel_v1(p_organization_id uuid, p_actor uuid, p_reason text) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, private as $$
declare v_sub public.pandora_customer_subscriptions%rowtype;
begin
  select * into v_sub from public.pandora_customer_subscriptions where organization_id=p_organization_id;
  if not found or v_sub.provider_reference is null then raise exception 'SUBSCRIPTION_NOT_ACTIVE' using errcode='P0002'; end if;
  return public.pandora_plp_billing_reconcile_v1(p_organization_id, p_actor) || jsonb_build_object('cancelRequested', true);
end; $$;
revoke all on function public.pandora_plp_billing_cancel_v1(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.pandora_plp_billing_cancel_v1(uuid,uuid,text) to service_role;