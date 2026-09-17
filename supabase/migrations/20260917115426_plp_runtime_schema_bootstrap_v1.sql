-- Bootstrap PLP runtime schema/tables required by
-- 20260917115427_enterprise_plp_runtime_projection_v1.sql.
-- Exact-source replay previously failed with 42P01 on plp_runtime.plp_accommodations.

create schema if not exists plp_runtime;

create table if not exists plp_runtime.plp_accommodations (
  id uuid primary key default gen_random_uuid(),
  name text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists plp_runtime.plp_bookings (
  id uuid primary key default gen_random_uuid(),
  accommodation_id uuid references plp_runtime.plp_accommodations(id) on delete set null,
  check_in date,
  check_out date,
  status text not null default 'PENDING',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists plp_runtime.plp_payments (
  id uuid primary key default gen_random_uuid(),
  amount_php numeric(14,2) not null default 0,
  status text not null default 'PENDING',
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists plp_runtime.plp_staff_tasks (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'open',
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists plp_runtime.plp_ota_conflicts (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'open',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on schema plp_runtime is
  'PLP operating runtime storage bootstrapped for enterprise overview projection replay.';
