-- Pandora PayPal billing: explicit sandbox environment, kept apart from live.
-- Live tables (pandora_customer_subscriptions, pandora_paypal_billing_sessions,
-- pandora_paypal_plan_change_sessions, pandora_service_plans PayPal bindings)
-- are not altered. Sandbox state lives only in pandora_paypal_sandbox_* tables
-- whose environment column is constrained to 'sandbox'.

create table if not exists public.pandora_paypal_catalog_bindings (
  environment text not null check (environment = 'sandbox'),
  plan_code text not null check (plan_code in ('launch','professional')),
  paypal_product_id text,
  paypal_plan_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (environment, plan_code),
  unique (environment, paypal_plan_id)
);

create table if not exists public.pandora_paypal_sandbox_billing_sessions (
  id uuid primary key default gen_random_uuid(),
  environment text not null default 'sandbox' check (environment = 'sandbox'),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  requested_by uuid not null references auth.users(id),
  plan_id uuid not null references public.pandora_service_plans(id),
  plan_code text not null,
  idempotency_key text not null,
  paypal_subscription_id text unique,
  paypal_plan_id text not null,
  approval_url text,
  status text not null default 'created' check (status in ('created','approval_pending','active','cancel_requested','cancelled','suspended','expired','failed')),
  return_url text not null,
  cancel_url text not null,
  expires_at timestamptz not null default (now() + interval '30 minutes'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, idempotency_key)
);
create index if not exists pandora_paypal_sandbox_billing_sessions_org_idx
  on public.pandora_paypal_sandbox_billing_sessions (organization_id, created_at desc);

create table if not exists public.pandora_paypal_sandbox_plan_change_sessions (
  id uuid primary key default gen_random_uuid(),
  environment text not null default 'sandbox' check (environment = 'sandbox'),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  requested_by uuid not null references auth.users(id),
  paypal_subscription_id text not null,
  from_plan_id uuid not null,
  to_plan_id uuid not null,
  from_plan_code text not null,
  to_plan_code text not null,
  idempotency_key text not null,
  status text not null default 'created',
  approval_url text,
  provider_reference text,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (organization_id, idempotency_key)
);
create index if not exists pandora_paypal_sandbox_plan_change_sessions_org_idx
  on public.pandora_paypal_sandbox_plan_change_sessions (organization_id, created_at desc);

create table if not exists public.pandora_paypal_sandbox_subscriptions (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  environment text not null default 'sandbox' check (environment = 'sandbox'),
  plan_id uuid not null references public.pandora_service_plans(id),
  state text not null check (state in ('trial','active','past_due','suspended','cancelled')),
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  monthly_fee_micros bigint,
  starts_on date,
  ends_on date,
  renews_on date,
  source_kind text not null default 'provider_verified' check (source_kind = 'provider_verified'),
  provider_reference text not null,
  provider_status text,
  verified_at timestamptz not null,
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
declare t text;
begin
  foreach t in array array[
    'pandora_paypal_catalog_bindings',
    'pandora_paypal_sandbox_billing_sessions',
    'pandora_paypal_sandbox_plan_change_sessions',
    'pandora_paypal_sandbox_subscriptions'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant select, insert, update on table public.%I to service_role', t);
    execute format('drop policy if exists %I on public.%I', 'service_role_manage_' || t, t);
    execute format('create policy %I on public.%I as permissive for all to service_role using (true) with check (true)', 'service_role_manage_' || t, t);
  end loop;
end $$;

-- Same accessor, same service-role-only guard; the allowlist gains the two
-- sandbox credential names. Values never leave the database except to the
-- service-role edge function.
create or replace function public.pandora_paypal_secret(p_name text)
 returns text
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'vault'
as $function$
declare
  v_role text := current_setting('request.jwt.claim.role', true);
  v_secret text;
begin
  if v_role <> 'service_role' then
    raise exception 'ACCESS_DENIED' using errcode='42501';
  end if;
  if p_name not in ('paypal_client_id','paypal_client_secret','paypal_webhook_id','paypal_client_id_sandbox','paypal_client_secret_sandbox') then
    raise exception 'SECRET_NAME_NOT_ALLOWED' using errcode='22023';
  end if;
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = p_name
  limit 1;
  return nullif(btrim(v_secret),'');
end;
$function$;
