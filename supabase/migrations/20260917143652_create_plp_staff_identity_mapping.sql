create table if not exists plp_runtime.plp_staff_identities (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique,
  email_hint text,
  display_name text not null,
  role text not null check (role in ('owner','manager','reservations','finance')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table plp_runtime.plp_staff_identities enable row level security;
revoke all on plp_runtime.plp_staff_identities from public, anon, authenticated;
grant select,insert,update,delete on plp_runtime.plp_staff_identities to service_role;
comment on table plp_runtime.plp_staff_identities is 'PLP staff authorization mapping. Human authentication is handled by Supabase Auth; this table contains only role mapping and display metadata.';
