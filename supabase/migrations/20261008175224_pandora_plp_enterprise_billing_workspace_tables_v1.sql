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
create index if not exists pandora_paypal_billing_sessions_org_idx on public.pandora_paypal_billing_sessions (organization_id, created_at desc);
create index if not exists pandora_paypal_plan_change_sessions_org_idx on public.pandora_paypal_plan_change_sessions (organization_id, created_at desc);
create index if not exists pandora_paypal_billing_webhook_events_org_idx on public.pandora_paypal_billing_webhook_events (organization_id, received_at desc);
alter table public.pandora_paypal_plan_links enable row level security;
alter table public.pandora_paypal_billing_sessions enable row level security;
alter table public.pandora_paypal_plan_change_sessions enable row level security;
alter table public.pandora_paypal_billing_webhook_events enable row level security;
revoke all on public.pandora_paypal_plan_links from public, anon, authenticated;
revoke all on public.pandora_paypal_billing_sessions from public, anon, authenticated;
revoke all on public.pandora_paypal_plan_change_sessions from public, anon, authenticated;
revoke all on public.pandora_paypal_billing_webhook_events from public, anon, authenticated;