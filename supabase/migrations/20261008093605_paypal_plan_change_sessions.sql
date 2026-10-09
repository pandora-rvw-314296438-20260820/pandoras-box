create table if not exists public.pandora_paypal_plan_change_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  requested_by uuid not null,
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

create index if not exists pandora_paypal_plan_change_sessions_org_idx
  on public.pandora_paypal_plan_change_sessions (organization_id, created_at desc);

create index if not exists pandora_paypal_plan_change_sessions_subscription_idx
  on public.pandora_paypal_plan_change_sessions (paypal_subscription_id, created_at desc);

alter table public.pandora_paypal_plan_change_sessions enable row level security;

revoke all on table public.pandora_paypal_plan_change_sessions from public, anon, authenticated;
grant select, insert, update on table public.pandora_paypal_plan_change_sessions to service_role;