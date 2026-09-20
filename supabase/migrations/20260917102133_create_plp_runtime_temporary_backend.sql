-- Source reconstruction of durable PLP runtime objects first applied by
-- provider migration 20260917102133. Only the subset required by current
-- canonical source is retained here; temporary deployment helpers are omitted.

create schema if not exists plp_runtime;
revoke all on schema plp_runtime from public, anon, authenticated;
grant usage on schema plp_runtime to service_role;

create table if not exists plp_runtime.plp_guests (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text not null,
  normalized_email text,
  phone text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists plp_guests_normalized_email_uidx
  on plp_runtime.plp_guests(normalized_email)
  where normalized_email is not null;

create table if not exists plp_runtime.plp_accommodations (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  nightly_rate_php numeric(12,2) not null default 0 check (nightly_rate_php >= 0),
  capacity integer not null default 1 check (capacity > 0),
  bedrooms integer not null default 0 check (bedrooms >= 0),
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists plp_runtime.plp_bookings (
  id uuid primary key default gen_random_uuid(),
  booking_reference text not null unique,
  guest_id uuid references plp_runtime.plp_guests(id) on delete restrict,
  accommodation_id uuid references plp_runtime.plp_accommodations(id) on delete restrict,
  accommodation_name text not null,
  check_in date not null,
  check_out date not null check (check_out > check_in),
  guest_count integer not null default 1 check (guest_count > 0),
  nights integer not null default 1 check (nights > 0),
  rate_per_night_php numeric(12,2) not null default 0 check (rate_per_night_php >= 0),
  total_amount_php numeric(12,2) not null default 0 check (total_amount_php >= 0),
  deposit_amount_php numeric(12,2) not null default 0 check (deposit_amount_php >= 0),
  balance_amount_php numeric(12,2) not null default 0 check (balance_amount_php >= 0),
  status text not null default 'PENDING_PAYMENT',
  payment_status text not null default 'PENDING',
  special_requests text,
  source text not null default 'website',
  expires_at timestamptz,
  confirmed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists plp_bookings_dates_idx
  on plp_runtime.plp_bookings(check_in,check_out);
create index if not exists plp_bookings_status_idx
  on plp_runtime.plp_bookings(status);

create table if not exists plp_runtime.plp_payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references plp_runtime.plp_bookings(id) on delete cascade,
  provider text not null,
  provider_session_id text,
  provider_reference_id text,
  provider_payment_id text,
  checkout_url text,
  amount_php numeric(12,2) not null default 0,
  currency text not null default 'PHP',
  status text not null default 'PENDING',
  verification_status text not null default 'PENDING',
  verification_error text,
  last_webhook_id text,
  raw_response jsonb not null default '{}'::jsonb,
  expires_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists plp_runtime.plp_ota_conflicts (
  id uuid primary key default gen_random_uuid(),
  channel_key text not null,
  conflict_type text not null,
  internal_booking_reference text,
  ota_reservation_reference text,
  accommodation_name text,
  start_date date,
  end_date date,
  severity text not null default 'medium',
  status text not null default 'open',
  details jsonb,
  resolution_note text,
  resolution_status text,
  resolution_type text,
  resolved_by text,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists plp_runtime.plp_staff_tasks (
  id uuid primary key default gen_random_uuid(),
  booking_reference text not null,
  kind text not null default 'task' check (kind in ('task','note')),
  category text not null default 'admin'
    check (category in ('concierge','housekeeping','payment','arrival','availability','admin')),
  priority text not null default 'normal' check (priority in ('high','medium','normal')),
  status text not null default 'open' check (status in ('open','in_progress','done','cancelled')),
  title text not null,
  note text,
  source text not null default 'resort-command-admin',
  actor text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

alter table plp_runtime.plp_guests enable row level security;
alter table plp_runtime.plp_accommodations enable row level security;
alter table plp_runtime.plp_bookings enable row level security;
alter table plp_runtime.plp_payments enable row level security;
alter table plp_runtime.plp_ota_conflicts enable row level security;
alter table plp_runtime.plp_staff_tasks enable row level security;

revoke all on table plp_runtime.plp_guests from public, anon, authenticated;
revoke all on table plp_runtime.plp_accommodations from public, anon, authenticated;
revoke all on table plp_runtime.plp_bookings from public, anon, authenticated;
revoke all on table plp_runtime.plp_payments from public, anon, authenticated;
revoke all on table plp_runtime.plp_ota_conflicts from public, anon, authenticated;
revoke all on table plp_runtime.plp_staff_tasks from public, anon, authenticated;

grant all on table plp_runtime.plp_guests to service_role;
grant all on table plp_runtime.plp_accommodations to service_role;
grant all on table plp_runtime.plp_bookings to service_role;
grant all on table plp_runtime.plp_payments to service_role;
grant all on table plp_runtime.plp_ota_conflicts to service_role;
grant all on table plp_runtime.plp_staff_tasks to service_role;
