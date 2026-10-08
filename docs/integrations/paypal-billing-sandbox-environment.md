# PayPal billing: explicit sandbox environment

Status: applied to the production Supabase project on 2026-10-08 as migration
`paypal_sandbox_environment` (version `20261008141840`). It is recorded here and
not in `supabase/migrations/` because the base PayPal billing tables (and the
earlier applied migrations `20261008093605` / `20261008094307`) have no
repository migration yet, so a replayable migration would not apply cleanly.
That parity gap predates this change.

## Model

- **Live is the default.** `pandora-owner-api` uses `https://api-m.paypal.com`,
  the Vault secrets `paypal_client_id` / `paypal_client_secret`, and the live
  tables `pandora_paypal_billing_sessions`, `pandora_paypal_plan_change_sessions`,
  `pandora_customer_subscriptions`. Nothing in the live path changed.
- **Sandbox is opt-in per request and allowlisted server side.** A request
  selects sandbox only with the header `x-pandora-billing-environment: sandbox`.
  The server accepts it only when the caller is an owner/admin of the
  organization *and* that organization is listed in the active provider config
  `pandora_runtime_provider_configs (provider='paypal', config_key='sandbox_organization_ids', active=true)`.
  Any other organization gets `BILLING_SANDBOX_NOT_ALLOWED`; an unknown value
  gets `BILLING_ENVIRONMENT_INVALID`. A client cannot flip another tenant.
- **Sandbox state is physically separate.** It lives only in the
  `pandora_paypal_sandbox_*` tables, each constrained to
  `environment = 'sandbox'`, and is returned with `environment: "sandbox"`, so it
  can never be read as live provider state.
- **Sandbox catalog bootstrap is idempotent.** One sandbox product
  (`PANDORABOXSERVICESBX1`) holds both plans so PayPal plan revision works.
  Bootstrap reuses an existing product (GET, 409 on create = reuse) and matches
  existing plans by name, price and currency before creating anything. Bindings
  are kept in `pandora_paypal_catalog_bindings`.
- **Secrets.** Credentials are read only by the service-role edge function via
  `public.pandora_paypal_secret(name)` (SECURITY DEFINER, service-role only,
  explicit name allowlist). No PayPal credential or token is returned to clients.

## Removing sandbox access for an organization

```sql
update public.pandora_runtime_provider_configs
   set active = false  -- or remove the org id from the comma separated config_value
 where provider = 'paypal' and config_key = 'sandbox_organization_ids';
```

## Applied SQL

```sql
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
```

## Subscription lifecycle (cancel / reconcile)

The owner API decides every lifecycle outcome from PayPal readbacks; the app
only renders the result. Identical in live and sandbox.

| PayPal `GET /v1/billing/subscriptions/{id}` | Reconcile | Cancel |
| --- | --- | --- |
| `APPROVAL_PENDING` (buyer has not approved) | `verified: false`, reason `AWAITING_BUYER_APPROVAL`, nothing written | `status: "blocked"`, reason `AWAITING_BUYER_APPROVAL`; **no `POST /cancel` is sent** (PayPal would answer 404 `INVALID_RESOURCE_ID`) |
| `APPROVED` (not activated yet) | `verified: false`, reason `AWAITING_PROVIDER_ACTIVATION` | `blocked`, `AWAITING_PROVIDER_ACTIVATION` |
| `ACTIVE`, not yet recorded `provider_verified` | records `active` / `provider_verified` | `blocked`, `RECONCILIATION_REQUIRED` (reconcile first) |
| `ACTIVE`, recorded `provider_verified` | refreshes | `POST /cancel` (`paypal-request-id: pandora-cancel-{id}`), then a second `GET`: |
| ↳ readback `CANCELLED` | | recorded `cancelled` (`status: "cancelled"`) |
| ↳ readback not `CANCELLED` | | `status: "cancel_unconfirmed"`; checkout session `cancel_requested`; plan unchanged, never shown as cancelled |
| ↳ PayPal rejects the cancel and readback not `CANCELLED` | | `PAYPAL_CANCEL_FAILED` (502); nothing recorded |

The live webhook follows the same rule: lifecycle state comes from the `GET`
readback, never from the event name.
