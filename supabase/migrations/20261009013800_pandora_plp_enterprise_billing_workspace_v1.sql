-- PLP Enterprise Revenue billing workspace.
-- Provider credentials stay in Vault. This migration stores subscription evidence
-- and plan-change sessions only. It never returns PayPal client secrets.

create table if not exists public.pandora_paypal_plan_links (
  plan_id uuid primary key references public.pandora_service_plans(id),
  paypal_plan_id text not null check (paypal_plan_id ~ '^P-[A-Z0-9]+$'),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.pandora_paypal_billing_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.pandora_enterprise_accounts(organization_id),
  plan_id uuid not null references public.pandora_service_plans(id),
  idempotency_key text not null check (length(idempotency_key) between 8 and 120),
  status text not null check (status in ('requested','approval_pending','provider_verified','completed','failed')),
  provider_reference text check (length(provider_reference) <= 240),
  approval_url text check (approval_url is null or approval_url ~ '^https://'),
  error_message text check (length(error_message) <= 500),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (organization_id, idempotency_key)
);

create table if not exists public.pandora_paypal_plan_change_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.pandora_enterprise_accounts(organization_id),
  from_plan_id uuid references public.pandora_service_plans(id),
  to_plan_id uuid not null references public.pandora_service_plans(id),
  idempotency_key text not null check (length(idempotency_key) between 8 and 120),
  provider_subscription text check (length(provider_subscription) <= 240),
  status text not null check (status in ('requested','approval_pending','provider_verified','completed','failed')),
  provider_reference text check (length(provider_reference) <= 240),
  approval_url text check (approval_url is null or approval_url ~ '^https://'),
  error_message text check (length(error_message) <= 500),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (organization_id, idempotency_key)
);

create table if not exists public.pandora_paypal_billing_webhook_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.pandora_enterprise_accounts(organization_id),
  event_type text not null check (length(event_type) between 1 and 120),
  provider_reference text not null check (length(provider_reference) between 1 and 240),
  resource_reference text check (length(resource_reference) <= 240),
  verified_at timestamptz not null,
  received_at timestamptz not null default now(),
  summary text not null check (length(summary) between 1 and 500),
  unique (provider_reference)
);

create index if not exists pandora_paypal_billing_sessions_org_idx
  on public.pandora_paypal_billing_sessions (organization_id, created_at desc);
create index if not exists pandora_paypal_plan_change_sessions_org_idx
  on public.pandora_paypal_plan_change_sessions (organization_id, created_at desc);
create index if not exists pandora_paypal_billing_webhook_events_org_idx
  on public.pandora_paypal_billing_webhook_events (organization_id, received_at desc);

alter table public.pandora_paypal_plan_links enable row level security;
alter table public.pandora_paypal_billing_sessions enable row level security;
alter table public.pandora_paypal_plan_change_sessions enable row level security;
alter table public.pandora_paypal_billing_webhook_events enable row level security;
revoke all on public.pandora_paypal_plan_links from public, anon, authenticated;
revoke all on public.pandora_paypal_billing_sessions from public, anon, authenticated;
revoke all on public.pandora_paypal_plan_change_sessions from public, anon, authenticated;
revoke all on public.pandora_paypal_billing_webhook_events from public, anon, authenticated;

create or replace function private.pandora_paypal_billing_api_v1(
  p_method text,
  p_path text,
  p_body jsonb default null,
  p_request_id text default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, extensions, private
as $$
declare
  v_token text;
  v_response extensions.http_response;
  v_method extensions.http_method;
  v_body jsonb;
  v_headers extensions.http_header[];
begin
  if upper(coalesce(p_method, '')) not in ('GET', 'POST') then
    raise exception 'PAYPAL_METHOD_NOT_ALLOWED' using errcode = '22023';
  end if;
  if p_path is null or p_path like '%..%' or p_path ~ E'[\\r\\n]' then
    raise exception 'PAYPAL_PATH_INVALID' using errcode = '22023';
  end if;
  if not (
    (upper(p_method) = 'POST' and p_path = '/v1/billing/subscriptions') or
    (upper(p_method) = 'GET' and p_path ~ '^/v1/billing/subscriptions/I-[A-Z0-9]+$') or
    (upper(p_method) = 'POST' and p_path ~ '^/v1/billing/subscriptions/I-[A-Z0-9]+/(revise|cancel)$')
  ) then
    raise exception 'PAYPAL_PATH_NOT_ALLOWED' using errcode = '22023';
  end if;
  v_token := private.pandora_paypal_access_20260830();
  v_headers := array[
    extensions.http_header('authorization', 'Bearer ' || v_token),
    extensions.http_header('content-type', 'application/json'),
    extensions.http_header('accept', 'application/json'),
    extensions.http_header('prefer', 'return=representation'),
    extensions.http_header('user-agent', 'Pandora-PLP-Billing/1.0')
  ]::extensions.http_header[];
  if nullif(p_request_id, '') is not null then
    v_headers := array_append(v_headers, extensions.http_header('paypal-request-id', left(p_request_id, 78)));
  end if;
  v_method := upper(p_method)::extensions.http_method;
  select * into v_response from extensions.http((
    v_method,
    (private.pandora_paypal_base_20260830() || p_path)::varchar,
    v_headers,
    case when p_body is null then null else 'application/json' end::varchar,
    case when p_body is null then null else p_body::text end::varchar
  )::extensions.http_request);
  begin
    v_body := nullif(v_response.content, '')::jsonb;
  exception when others then
    v_body := jsonb_build_object('name', 'UNREADABLE_RESPONSE');
  end;
  return jsonb_build_object('status', v_response.status, 'body', coalesce(v_body, '{}'::jsonb));
end;
$$;

revoke all on function private.pandora_paypal_billing_api_v1(text, text, jsonb, text) from public, anon, authenticated;
grant execute on function private.pandora_paypal_billing_api_v1(text, text, jsonb, text) to service_role;

create or replace function private.pandora_plp_billing_money(p_micros bigint)
returns numeric
language sql
immutable
as $$
  select round(coalesce(p_micros, 0) / 1000000.0, 2);
$$;

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
    exists (
      select 1 from vault.decrypted_secrets
      where name = 'paypal_client_id' and nullif(btrim(decrypted_secret), '') is not null
    )
    and exists (
      select 1 from vault.decrypted_secrets
      where name = 'paypal_client_secret' and nullif(btrim(decrypted_secret), '') is not null
    )
  ) into v_configured;

  select jsonb_build_object(
    'plan_id', s.plan_id,
    'plan_code', p.code,
    'plan_name', p.name,
    'state', s.state,
    'currency', s.currency,
    'monthly_fee', private.pandora_plp_billing_money(s.monthly_fee_micros),
    'monthly_fee_micros', s.monthly_fee_micros,
    'setup_fee', private.pandora_plp_billing_money(s.setup_fee_micros),
    'setup_fee_micros', s.setup_fee_micros,
    'discount', private.pandora_plp_billing_money(s.discount_micros),
    'discount_micros', s.discount_micros,
    'net_monthly_fee', private.pandora_plp_billing_money(coalesce(s.monthly_fee_micros, 0) - s.discount_micros),
    'starts_on', s.starts_on,
    'ends_on', s.ends_on,
    'renews_on', s.renews_on,
    'source_kind', s.source_kind,
    'provider_reference', s.provider_reference,
    'verified_at', s.verified_at,
    'updated_at', s.updated_at,
    'verification_label', case
      when s.source_kind = 'provider_verified' and s.verified_at is not null then 'Verified'
      when s.provider_reference is not null then 'Reconciliation required'
      else 'Awaiting provider confirmation'
    end
  )
  into v_subscription
  from public.pandora_customer_subscriptions s
  join public.pandora_service_plans p on p.id = s.plan_id
  where s.organization_id = p_organization_id;

  select coalesce(jsonb_agg(row_to_json(x)::jsonb order by x.monthly_fee_micros nulls last, x.code), '[]'::jsonb)
  into v_plans
  from (
    select
      p.id as plan_id,
      p.code,
      p.name,
      p.currency,
      private.pandora_plp_billing_money(p.monthly_fee_micros) as monthly_fee,
      p.monthly_fee_micros,
      l.paypal_plan_id is not null and l.active as provider_linked
    from public.pandora_service_plans p
    left join public.pandora_paypal_plan_links l on l.plan_id = p.id and l.active
    where p.state = 'active'
  ) x;

  select jsonb_build_object(
    'id', c.id,
    'from_plan_id', c.from_plan_id,
    'from_plan_code', fp.code,
    'from_plan_name', fp.name,
    'to_plan_id', c.to_plan_id,
    'to_plan_code', tp.code,
    'to_plan_name', tp.name,
    'provider_subscription', c.provider_subscription,
    'status', c.status,
    'approval_url', c.approval_url,
    'provider_reference', c.provider_reference,
    'error_message', c.error_message,
    'created_at', c.created_at,
    'updated_at', c.updated_at,
    'completed_at', c.completed_at,
    'price_delta', private.pandora_plp_billing_money(coalesce(tp.monthly_fee_micros, 0) - coalesce(fp.monthly_fee_micros, 0)),
    'currency', tp.currency,
    'trust', case
      when c.status in ('provider_verified', 'completed') then 'provider'
      when c.status = 'approval_pending' then 'pending_action'
      when c.status = 'failed' then 'failed'
      else 'local_request'
    end
  )
  into v_change
  from public.pandora_paypal_plan_change_sessions c
  join public.pandora_service_plans tp on tp.id = c.to_plan_id
  left join public.pandora_service_plans fp on fp.id = c.from_plan_id
  where c.organization_id = p_organization_id
  order by c.created_at desc
  limit 1;

  select jsonb_build_object(
    'id', b.id,
    'plan_id', b.plan_id,
    'plan_code', p.code,
    'plan_name', p.name,
    'status', b.status,
    'provider_reference', b.provider_reference,
    'approval_url', b.approval_url,
    'error_message', b.error_message,
    'created_at', b.created_at,
    'updated_at', b.updated_at,
    'completed_at', b.completed_at,
    'trust', case
      when b.status in ('provider_verified', 'completed') then 'provider'
      when b.status = 'approval_pending' then 'pending_action'
      when b.status = 'failed' then 'failed'
      else 'local_request'
    end
  )
  into v_checkout
  from public.pandora_paypal_billing_sessions b
  join public.pandora_service_plans p on p.id = b.plan_id
  where b.organization_id = p_organization_id
  order by b.created_at desc
  limit 1;

  select coalesce(jsonb_agg(item order by item->>'occurred_at' desc), '[]'::jsonb)
  into v_activity
  from (
    select jsonb_build_object(
      'kind', 'payment',
      'trust', case when pay.source_kind = 'provider_verified' then 'provider' else 'local_request' end,
      'title', case pay.payment_kind when 'refund' then 'Refund recorded' else 'Payment recorded' end,
      'detail', pay.reference,
      'occurred_at', pay.occurred_on,
      'verified_at', pay.verified_at,
      'amount', private.pandora_plp_billing_money(pay.amount_micros),
      'currency', pay.currency
    ) as item
    from public.pandora_customer_payments pay
    where pay.organization_id = p_organization_id
    union all
    select jsonb_build_object(
      'kind', 'webhook',
      'trust', 'provider',
      'title', w.event_type,
      'detail', w.summary,
      'occurred_at', w.received_at,
      'verified_at', w.verified_at,
      'provider_reference', w.provider_reference
    )
    from public.pandora_paypal_billing_webhook_events w
    where w.organization_id = p_organization_id
    union all
    select jsonb_build_object(
      'kind', 'plan_change',
      'trust', case when c.status in ('provider_verified', 'completed') then 'provider' else 'local_request' end,
      'title', 'Plan change ' || c.status,
      'detail', coalesce(fp.name, 'Current') || ' → ' || tp.name,
      'occurred_at', c.updated_at,
      'verified_at', case when c.status in ('provider_verified', 'completed') then c.completed_at else null end,
      'status', c.status
    )
    from public.pandora_paypal_plan_change_sessions c
    join public.pandora_service_plans tp on tp.id = c.to_plan_id
    left join public.pandora_service_plans fp on fp.id = c.from_plan_id
    where c.organization_id = p_organization_id
    union all
    select jsonb_build_object(
      'kind', 'checkout',
      'trust', case when b.status in ('provider_verified', 'completed') then 'provider' else 'local_request' end,
      'title', 'Checkout ' || b.status,
      'detail', p.name,
      'occurred_at', b.updated_at,
      'verified_at', case when b.status in ('provider_verified', 'completed') then b.completed_at else null end,
      'status', b.status
    )
    from public.pandora_paypal_billing_sessions b
    join public.pandora_service_plans p on p.id = b.plan_id
    where b.organization_id = p_organization_id
  ) events
  limit 12;

  return jsonb_build_object(
    'provider', jsonb_build_object(
      'name', 'paypal',
      'configured', coalesce(v_configured, false),
      'label', case when coalesce(v_configured, false) then 'PayPal' else 'Provider state unavailable' end
    ),
    'subscription', v_subscription,
    'plans', v_plans,
    'pendingPlanChange', v_change,
    'checkout', v_checkout,
    'activity', coalesce(v_activity, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.pandora_plp_billing_status_v1(uuid) from public, anon, authenticated;
grant execute on function public.pandora_plp_billing_status_v1(uuid) to service_role;

create or replace function public.pandora_plp_billing_checkout_v1(
  p_organization_id uuid,
  p_actor uuid,
  p_plan_code text,
  p_idempotency_key text,
  p_return_url text,
  p_cancel_url text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_plan public.pandora_service_plans%rowtype;
  v_link public.pandora_paypal_plan_links%rowtype;
  v_existing public.pandora_paypal_billing_sessions%rowtype;
  v_session public.pandora_paypal_billing_sessions%rowtype;
  v_response jsonb;
  v_body jsonb;
  v_approval text;
  v_reference text;
begin
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then
    raise exception 'INVALID_IDEMPOTENCY_KEY' using errcode = '22023';
  end if;
  if p_return_url is null or p_return_url !~ '^https://' or p_cancel_url is null or p_cancel_url !~ '^https://' then
    raise exception 'INVALID_RETURN_URL' using errcode = '22023';
  end if;
  select * into v_existing
  from public.pandora_paypal_billing_sessions
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('replayed', true, 'status', v_existing.status, 'approvalUrl', v_existing.approval_url, 'providerReference', v_existing.provider_reference);
  end if;
  if exists (
    select 1 from public.pandora_customer_subscriptions
    where organization_id = p_organization_id and state in ('trial', 'active', 'past_due')
  ) then
    raise exception 'SUBSCRIPTION_ALREADY_ACTIVE' using errcode = '23505';
  end if;
  select * into v_plan from public.pandora_service_plans where code = p_plan_code and state = 'active';
  if not found then
    raise exception 'PLAN_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into v_link from public.pandora_paypal_plan_links where plan_id = v_plan.id and active;
  if not found then
    raise exception 'PLAN_PROVIDER_LINK_REQUIRED' using errcode = 'P0002';
  end if;

  insert into public.pandora_paypal_billing_sessions (
    organization_id, plan_id, idempotency_key, status, created_by
  ) values (
    p_organization_id, v_plan.id, p_idempotency_key, 'requested', p_actor
  ) returning * into v_session;

  v_response := private.pandora_paypal_billing_api_v1(
    'POST',
    '/v1/billing/subscriptions',
    jsonb_build_object(
      'plan_id', v_link.paypal_plan_id,
      'custom_id', v_session.id::text,
      'application_context', jsonb_build_object(
        'brand_name', 'PLP Enterprise',
        'user_action', 'SUBSCRIBE_NOW',
        'return_url', p_return_url,
        'cancel_url', p_cancel_url
      )
    ),
    v_session.id::text
  );
  v_body := coalesce(v_response->'body', '{}'::jsonb);
  if coalesce((v_response->>'status')::int, 0) not between 200 and 299 then
    update public.pandora_paypal_billing_sessions
    set status = 'failed',
        error_message = left(coalesce(v_body->>'message', v_body->>'name', 'PayPal checkout failed'), 500),
        updated_at = now()
    where id = v_session.id;
    raise exception 'PAYPAL_CHECKOUT_FAILED' using errcode = 'P0001';
  end if;
  v_reference := nullif(v_body->>'id', '');
  select link->>'href' into v_approval
  from jsonb_array_elements(coalesce(v_body->'links', '[]'::jsonb)) link
  where link->>'rel' = 'approve'
  limit 1;
  update public.pandora_paypal_billing_sessions
  set status = case when v_approval is null then 'requested' else 'approval_pending' end,
      provider_reference = v_reference,
      approval_url = v_approval,
      updated_at = now()
  where id = v_session.id
  returning * into v_session;
  return jsonb_build_object(
    'status', v_session.status,
    'approvalUrl', v_session.approval_url,
    'providerReference', v_session.provider_reference,
    'verified', false
  );
end;
$$;

revoke all on function public.pandora_plp_billing_checkout_v1(uuid, uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function public.pandora_plp_billing_checkout_v1(uuid, uuid, text, text, text, text) to service_role;

create or replace function public.pandora_plp_billing_change_plan_v1(
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
  v_sub public.pandora_customer_subscriptions%rowtype;
  v_plan public.pandora_service_plans%rowtype;
  v_link public.pandora_paypal_plan_links%rowtype;
  v_existing public.pandora_paypal_plan_change_sessions%rowtype;
  v_session public.pandora_paypal_plan_change_sessions%rowtype;
  v_response jsonb;
  v_body jsonb;
  v_approval text;
begin
  if p_idempotency_key is null or length(p_idempotency_key) < 8 then
    raise exception 'INVALID_IDEMPOTENCY_KEY' using errcode = '22023';
  end if;
  select * into v_existing
  from public.pandora_paypal_plan_change_sessions
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('replayed', true, 'status', v_existing.status, 'approvalUrl', v_existing.approval_url, 'providerReference', v_existing.provider_reference);
  end if;
  select * into v_sub from public.pandora_customer_subscriptions where organization_id = p_organization_id;
  if not found or v_sub.state not in ('trial', 'active', 'past_due') then
    raise exception 'SUBSCRIPTION_NOT_ACTIVE' using errcode = 'P0002';
  end if;
  if v_sub.provider_reference is null or v_sub.source_kind <> 'provider_verified' then
    raise exception 'RECONCILIATION_REQUIRED' using errcode = 'P0001';
  end if;
  select * into v_plan from public.pandora_service_plans where code = p_plan_code and state = 'active';
  if not found then
    raise exception 'PLAN_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_plan.id = v_sub.plan_id then
    raise exception 'PLAN_UNCHANGED' using errcode = '22023';
  end if;
  select * into v_link from public.pandora_paypal_plan_links where plan_id = v_plan.id and active;
  if not found then
    raise exception 'PLAN_PROVIDER_LINK_REQUIRED' using errcode = 'P0002';
  end if;
  insert into public.pandora_paypal_plan_change_sessions (
    organization_id, from_plan_id, to_plan_id, idempotency_key, provider_subscription, status, created_by
  ) values (
    p_organization_id, v_sub.plan_id, v_plan.id, p_idempotency_key, v_sub.provider_reference, 'requested', p_actor
  ) returning * into v_session;
  v_response := private.pandora_paypal_billing_api_v1(
    'POST',
    '/v1/billing/subscriptions/' || v_sub.provider_reference || '/revise',
    jsonb_build_object('plan_id', v_link.paypal_plan_id),
    v_session.id::text
  );
  v_body := coalesce(v_response->'body', '{}'::jsonb);
  if coalesce((v_response->>'status')::int, 0) not between 200 and 299 then
    update public.pandora_paypal_plan_change_sessions
    set status = 'failed',
        error_message = left(coalesce(v_body->>'message', v_body->>'name', 'PayPal plan change failed'), 500),
        updated_at = now()
    where id = v_session.id;
    raise exception 'PAYPAL_PLAN_CHANGE_FAILED' using errcode = 'P0001';
  end if;
  select link->>'href' into v_approval
  from jsonb_array_elements(coalesce(v_body->'links', '[]'::jsonb)) link
  where link->>'rel' = 'approve'
  limit 1;
  update public.pandora_paypal_plan_change_sessions
  set status = case when v_approval is null then 'requested' else 'approval_pending' end,
      provider_reference = nullif(v_body->>'id', ''),
      approval_url = v_approval,
      updated_at = now()
  where id = v_session.id
  returning * into v_session;
  return jsonb_build_object(
    'status', v_session.status,
    'approvalUrl', v_session.approval_url,
    'providerReference', v_session.provider_reference,
    'verified', false
  );
end;
$$;

revoke all on function public.pandora_plp_billing_change_plan_v1(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.pandora_plp_billing_change_plan_v1(uuid, uuid, text, text) to service_role;

create or replace function public.pandora_plp_billing_reconcile_v1(
  p_organization_id uuid,
  p_actor uuid
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
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
  select * into v_sub from public.pandora_customer_subscriptions where organization_id = p_organization_id;
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
  v_reference := coalesce(v_sub.provider_reference, v_session.provider_reference, v_change.provider_subscription);
  if v_reference is null then
    return jsonb_build_object('verified', false, 'label', 'Provider state unavailable', 'reason', 'NO_PROVIDER_REFERENCE');
  end if;
  v_response := private.pandora_paypal_billing_api_v1('GET', '/v1/billing/subscriptions/' || v_reference, null, p_organization_id::text);
  v_body := coalesce(v_response->'body', '{}'::jsonb);
  if coalesce((v_response->>'status')::int, 0) not between 200 and 299 then
    return jsonb_build_object(
      'verified', false,
      'label', 'Provider verification failed',
      'reason', left(coalesce(v_body->>'name', 'PAYPAL_READ_FAILED'), 120)
    );
  end if;
  v_state := upper(coalesce(v_body->>'status', ''));
  v_plan_id := v_body->>'plan_id';
  select * into v_linked from public.pandora_paypal_plan_links where paypal_plan_id = v_plan_id and active;
  if v_state in ('ACTIVE', 'APPROVED') and v_linked.plan_id is not null then
    insert into public.pandora_customer_subscriptions (
      organization_id, plan_id, state, currency, monthly_fee_micros, setup_fee_micros, discount_micros,
      starts_on, renews_on, source_kind, provider_reference, verified_at, updated_by
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
    set status = 'provider_verified', completed_at = now(), updated_at = now()
    where organization_id = p_organization_id and provider_reference = v_reference and status <> 'failed';
    update public.pandora_paypal_plan_change_sessions
    set status = 'completed', completed_at = now(), updated_at = now()
    where organization_id = p_organization_id and provider_subscription = v_reference and to_plan_id = v_linked.plan_id and status in ('requested', 'approval_pending');
  elsif v_state = 'CANCELLED' then
    update public.pandora_customer_subscriptions
    set state = 'cancelled', source_kind = 'provider_verified', verified_at = now(), ends_on = current_date, updated_by = p_actor, updated_at = now()
    where organization_id = p_organization_id;
  else
    return jsonb_build_object('verified', false, 'label', 'Awaiting provider confirmation', 'providerState', v_state);
  end if;
  return jsonb_build_object('verified', true, 'label', 'Verified', 'providerState', v_state);
end;
$$;

revoke all on function public.pandora_plp_billing_reconcile_v1(uuid, uuid) from public, anon, authenticated;
grant execute on function public.pandora_plp_billing_reconcile_v1(uuid, uuid) to service_role;

create or replace function public.pandora_plp_billing_cancel_v1(
  p_organization_id uuid,
  p_actor uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_sub public.pandora_customer_subscriptions%rowtype;
  v_response jsonb;
  v_body jsonb;
begin
  select * into v_sub from public.pandora_customer_subscriptions where organization_id = p_organization_id;
  if not found or v_sub.provider_reference is null then
    raise exception 'SUBSCRIPTION_NOT_ACTIVE' using errcode = 'P0002';
  end if;
  v_response := private.pandora_paypal_billing_api_v1(
    'POST',
    '/v1/billing/subscriptions/' || v_sub.provider_reference || '/cancel',
    jsonb_build_object('reason', left(coalesce(nullif(btrim(p_reason), ''), 'Cancelled by PLP owner'), 128)),
    p_organization_id::text
  );
  v_body := coalesce(v_response->'body', '{}'::jsonb);
  if coalesce((v_response->>'status')::int, 0) not between 200 and 299 and coalesce((v_response->>'status')::int, 0) <> 204 then
    raise exception 'PAYPAL_CANCEL_FAILED' using errcode = 'P0001';
  end if;
  return public.pandora_plp_billing_reconcile_v1(p_organization_id, p_actor) || jsonb_build_object('cancelRequested', true);
end;
$$;

revoke all on function public.pandora_plp_billing_cancel_v1(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.pandora_plp_billing_cancel_v1(uuid, uuid, text) to service_role;
