-- Pandora Base44 read-only identity bridge.
-- Links a verified Base44 app user to an existing Pandora user/org identity.
-- Service-role only; Base44 remains presentation-only.

create table if not exists public.pandora_base44_identity_links (
  base44_app_id text not null,
  base44_user_id text not null,
  pandora_user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  enabled boolean not null default true,
  note text null check (note is null or char_length(note) <= 240),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (base44_app_id, base44_user_id)
);

alter table public.pandora_base44_identity_links enable row level security;

revoke all on table public.pandora_base44_identity_links from public, anon, authenticated;
grant select, insert, update, delete on table public.pandora_base44_identity_links to service_role;

insert into public.pandora_base44_identity_links(
  base44_app_id,
  base44_user_id,
  pandora_user_id,
  organization_id,
  enabled,
  note
) values (
  '6a94ecfadf75736cd4ebf7e1',
  '6a94ecfadf75736cd4ebf7e2',
  'f17558e4-e1b2-4b8d-a215-b96775b1a470'::uuid,
  '076a9306-5c4e-4d9d-98d3-e3a6fea968fb'::uuid,
  true,
  'Verified active Base44 Pandora app admin mapped to isolated Pandora acceptance owner.'
)
on conflict (base44_app_id, base44_user_id) do update
set
  pandora_user_id = excluded.pandora_user_id,
  organization_id = excluded.organization_id,
  enabled = excluded.enabled,
  note = excluded.note,
  updated_at = now();

comment on table public.pandora_base44_identity_links is
  'Service-only identity links used by the read-only Pandora Base44 bridge after Base44 bearer-token validation.';
