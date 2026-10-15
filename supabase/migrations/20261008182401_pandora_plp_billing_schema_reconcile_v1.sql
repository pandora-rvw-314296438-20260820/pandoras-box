-- Reconcile PLP billing functions to the live control-plane schema.
-- Live tables already exist. This migration does not recreate them and does not
-- call the live PayPal API. Sandbox lifecycle uses Vault sandbox secrets only.

create or replace function private.pandora_paypal_sandbox_access_v1()
returns text
language plpgsql
security definer
set search_path = pg_catalog, extensions, vault
as $$
declare
  v_client text;
  v_secret text;
  v_response extensions.http_response;
  v_body jsonb;
begin
  select decrypted_secret into v_client from vault.decrypted_secrets where name = 'paypal_client_id_sandbox' limit 1;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'paypal_client_secret_sandbox' limit 1;
  if nullif(btrim(v_client), '') is null or nullif(btrim(v_secret), '') is null then
    raise exception 'PAYPAL_SANDBOX_NOT_CONFIGURED' using errcode = '55000';
  end if;
  select * into v_response from extensions.http((
    'POST'::extensions.http_method,
    'https://api-m.sandbox.paypal.com/v1/oauth2/token',
    array[
      extensions.http_header('authorization', 'Basic ' || encode(convert_to(v_client || ':' || v_secret, 'UTF8'), 'base64')),
      extensions.http_header('content-type', 'application/x-www-form-urlencoded'),
      extensions.http_header('accept', 'application/json')
    ]::extensions.http_header[],
    'application/x-www-form-urlencoded',
    'grant_type=client_credentials'
  )::extensions.http_request);
  begin
    v_body := nullif(v_response.content, '')::jsonb;
  exception when others then
    v_body := '{}'::jsonb;
  end;
  if v_response.status <> 200 or nullif(v_body->>'access_token', '') is null then
    raise exception 'PAYPAL_SANDBOX_AUTH_FAILED' using errcode = '55000';
  end if;
  return v_body->>'access_token';
end;
$$;

revoke all on function private.pandora_paypal_sandbox_access_v1() from public, anon, authenticated;
grant execute on function private.pandora_paypal_sandbox_access_v1() to service_role;

create or replace function private.pandora_paypal_sandbox_api_v1(
  p_method text,
  p_path text,
  p_body jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, extensions, private
as $$
declare
  v_token text;
  v_response extensions.http_response;
  v_body jsonb;
begin
  if upper(coalesce(p_method, '')) not in ('GET', 'POST') then
    raise exception 'PAYPAL_METHOD_NOT_ALLOWED' using errcode = '22023';
  end if;
  if p_path is null or p_path like '%..%' or p_path ~ E'[\r\n]' then
    raise exception 'PAYPAL_PATH_INVALID' using errcode = '22023';
  end if;
  if not (
    (upper(p_method) = 'POST' and p_path in ('/v1/catalogs/products', '/v1/billing/plans', '/v1/billing/subscriptions')) or
    (upper(p_method) = 'GET' and p_path ~ '^/v1/billing/subscriptions/I-[A-Z0-9]+$') or
    (upper(p_method) = 'POST' and p_path ~ '^/v1/billing/subscriptions/I-[A-Z0-9]+/(revise|cancel)$')
  ) then
    raise exception 'PAYPAL_PATH_NOT_ALLOWED' using errcode = '22023';
  end if;
  v_token := private.pandora_paypal_sandbox_access_v1();
  select * into v_response from extensions.http((
    upper(p_method)::extensions.http_method,
    ('https://api-m.sandbox.paypal.com' || p_path)::varchar,
    array[
      extensions.http_header('authorization', 'Bearer ' || v_token),
      extensions.http_header('content-type', 'application/json'),
      extensions.http_header('accept', 'application/json'),
      extensions.http_header('prefer', 'return=representation')
    ]::extensions.http_header[],
    case when p_body is null then null else 'application/json' end::varchar,
    case when p_body is null then null else p_body::text end::varchar
  )::extensions.http_request);
  begin
    v_body := nullif(v_response.content, '')::jsonb;
  exception when others then
    v_body := jsonb_build_object('name', 'UNREADABLE_RESPONSE');
  end;
  return jsonb_build_object('status', v_response.status, 'body', coalesce(v_body, '{}'::jsonb) - 'access_token' - 'client_id' - 'client_secret');
end;
$$;

revoke all on function private.pandora_paypal_sandbox_api_v1(text, text, jsonb) from public, anon, authenticated;
grant execute on function private.pandora_paypal_sandbox_api_v1(text, text, jsonb) to service_role;

create or replace function public.pandora_plp_billing_sandbox_checkout_v1(
  p_organization_id uuid,
  p_actor uuid,
  p_plan_code text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_plan public.pandora_service_plans%rowtype;
  v_product jsonb;
  v_paypal_plan jsonb;
  v_sub jsonb;
  v_product_id text;
  v_plan_id text;
  v_approval text;
  v_reference text;
  v_session_id uuid;
begin
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then
    raise exception 'INVALID_IDEMPOTENCY_KEY' using errcode = '22023';
  end if;
  select * into v_plan from public.pandora_service_plans where code = p_plan_code and state = 'active';
  if not found then
    raise exception 'PLAN_NOT_FOUND' using errcode = 'P0002';
  end if;
  v_product := private.pandora_paypal_sandbox_api_v1('POST', '/v1/catalogs/products', jsonb_build_object('name', 'PLP sandbox ' || v_plan.code, 'type', 'SERVICE'));
  if coalesce((v_product->>'status')::int, 0) not between 200 and 299 then
    raise exception 'PAYPAL_SANDBOX_PRODUCT_FAILED' using errcode = 'P0001';
  end if;
  v_product_id := v_product->'body'->>'id';
  v_paypal_plan := private.pandora_paypal_sandbox_api_v1('POST', '/v1/billing/plans', jsonb_build_object(
    'product_id', v_product_id,
    'name', v_plan.name,
    'status', 'ACTIVE',
    'billing_cycles', jsonb_build_array(jsonb_build_object(
      'frequency', jsonb_build_object('interval_unit', 'MONTH', 'interval_count', 1),
      'tenure_type', 'REGULAR',
      'sequence', 1,
      'total_cycles', 0,
      'pricing_scheme', jsonb_build_object('fixed_price', jsonb_build_object('value', private.pandora_plp_billing_money(v_plan.monthly_fee_micros), 'currency_code', v_plan.currency))
    )),
    'payment_preferences', jsonb_build_object('auto_bill_outstanding', true, 'payment_failure_threshold', 1)
  ));
  if coalesce((v_paypal_plan->>'status')::int, 0) not between 200 and 299 then
    raise exception 'PAYPAL_SANDBOX_PLAN_FAILED' using errcode = 'P0001';
  end if;
  v_plan_id := v_paypal_plan->'body'->>'id';
  insert into public.pandora_paypal_catalog_bindings (environment, plan_code, paypal_product_id, paypal_plan_id)
  values ('sandbox', v_plan.code, v_product_id, v_plan_id)
  on conflict (environment, plan_code) do update set paypal_product_id = excluded.paypal_product_id, paypal_plan_id = excluded.paypal_plan_id, updated_at = now();
  v_sub := private.pandora_paypal_sandbox_api_v1('POST', '/v1/billing/subscriptions', jsonb_build_object(
    'plan_id', v_plan_id,
    'application_context', jsonb_build_object(
      'brand_name', 'PLP Enterprise sandbox',
      'user_action', 'SUBSCRIBE_NOW',
      'return_url', 'https://mcpmaster.vercel.app/#/enterprise/paypal-return',
      'cancel_url', 'https://mcpmaster.vercel.app/#/enterprise/paypal-cancel'
    )
  ));
  if coalesce((v_sub->>'status')::int, 0) not between 200 and 299 then
    raise exception 'PAYPAL_SANDBOX_CHECKOUT_FAILED' using errcode = 'P0001';
  end if;
  v_reference := v_sub->'body'->>'id';
  select link->>'href' into v_approval
  from jsonb_array_elements(coalesce(v_sub->'body'->'links', '[]'::jsonb)) link
  where link->>'rel' = 'approve'
  limit 1;
  insert into public.pandora_paypal_sandbox_billing_sessions (
    environment, organization_id, requested_by, plan_id, plan_code, idempotency_key,
    paypal_subscription_id, paypal_plan_id, approval_url, status, return_url, cancel_url, expires_at
  ) values (
    'sandbox', p_organization_id, p_actor, v_plan.id, v_plan.code, p_idempotency_key,
    v_reference, v_plan_id, v_approval, 'approval_pending',
    'https://mcpmaster.vercel.app/#/enterprise/paypal-return',
    'https://mcpmaster.vercel.app/#/enterprise/paypal-cancel',
    now() + interval '3 hours'
  ) returning id into v_session_id;
  return jsonb_build_object(
    'environment', 'sandbox',
    'status', 'approval_pending',
    'verified', false,
    'sessionId', v_session_id,
    'providerReference', v_reference,
    'approvalUrlPresent', v_approval is not null
  );
end;
$$;

revoke all on function public.pandora_plp_billing_sandbox_checkout_v1(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.pandora_plp_billing_sandbox_checkout_v1(uuid, uuid, text, text) to service_role;

create or replace function public.pandora_plp_billing_sandbox_reconcile_v1(
  p_organization_id uuid,
  p_actor uuid
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_session public.pandora_paypal_sandbox_billing_sessions%rowtype;
  v_response jsonb;
  v_state text;
begin
  select * into v_session
  from public.pandora_paypal_sandbox_billing_sessions
  where organization_id = p_organization_id and environment = 'sandbox'
  order by created_at desc
  limit 1;
  if not found or v_session.paypal_subscription_id is null then
    return jsonb_build_object('verified', false, 'label', 'Provider state unavailable', 'reason', 'NO_PROVIDER_REFERENCE');
  end if;
  v_response := private.pandora_paypal_sandbox_api_v1('GET', '/v1/billing/subscriptions/' || v_session.paypal_subscription_id, null);
  if coalesce((v_response->>'status')::int, 0) not between 200 and 299 then
    return jsonb_build_object('verified', false, 'label', 'Provider verification failed', 'reason', left(coalesce(v_response->'body'->>'name', 'PAYPAL_READ_FAILED'), 120));
  end if;
  v_state := upper(coalesce(v_response->'body'->>'status', ''));
  if v_state = 'ACTIVE' then
    insert into public.pandora_paypal_sandbox_subscriptions (
      organization_id, environment, plan_id, state, currency, monthly_fee_micros, starts_on, source_kind, provider_reference, provider_status, verified_at, updated_by
    )
    select p_organization_id, 'sandbox', v_session.plan_id, 'active', p.currency, p.monthly_fee_micros, current_date, 'provider_verified', v_session.paypal_subscription_id, v_state, now(), p_actor
    from public.pandora_service_plans p
    where p.id = v_session.plan_id
    on conflict (organization_id) do update set
      state = 'active', source_kind = 'provider_verified', provider_status = excluded.provider_status, verified_at = now(), updated_at = now();
    update public.pandora_paypal_sandbox_billing_sessions set status = 'provider_verified', updated_at = now() where id = v_session.id;
    return jsonb_build_object('verified', true, 'label', 'Verified', 'providerState', v_state);
  end if;
  return jsonb_build_object('verified', false, 'label', 'Awaiting provider confirmation', 'providerState', v_state);
end;
$$;

revoke all on function public.pandora_plp_billing_sandbox_checkout_v1(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.pandora_plp_billing_sandbox_reconcile_v1(uuid, uuid) to service_role;