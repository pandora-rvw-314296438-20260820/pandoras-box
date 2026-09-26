-- Source reconstruction of provider migration 20260918051723.
-- The live provider contains these durable local-AI queue tables, but the
-- migration file was absent from Git. Fresh-source replay needs the schema
-- dependency before phone-local acceptance migrations run.
--
-- Historical one-time anonymous build callback policies are intentionally not
-- reconstructed. These legacy queue tables are retained as server-side history
-- and compatibility surfaces only.

create table if not exists public.pandora_local_ai_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  requested_by uuid not null,
  model text not null check (char_length(model) between 1 and 160),
  request_body jsonb not null,
  status text not null default 'queued'
    check (status in ('queued','processing','completed','failed','cancelled')),
  claim_token uuid,
  worker_id text,
  result_body jsonb,
  error_code text,
  claimed_at timestamptz,
  completed_at timestamptz,
  expires_at timestamptz not null default (now() + interval '10 minutes'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists pandora_local_ai_jobs_queue_idx
  on public.pandora_local_ai_jobs(status, created_at)
  where status in ('queued','processing');

create table if not exists public.pandora_local_ai_workers (
  worker_id text primary key,
  model text not null,
  status text not null
    check (status in ('ready','busy','degraded','offline')),
  last_seen_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists public.pandora_local_ai_build_receipts (
  build_id text primary key,
  status text not null,
  step text,
  source_sha text,
  apk_sha256 text,
  apk_size_bytes bigint,
  tunnel_url text,
  detail text,
  updated_at timestamptz not null default now(),
  callback_nonce text
);

alter table public.pandora_local_ai_jobs enable row level security;
alter table public.pandora_local_ai_workers enable row level security;
alter table public.pandora_local_ai_build_receipts enable row level security;

revoke all on table public.pandora_local_ai_jobs
  from public, anon, authenticated;
revoke all on table public.pandora_local_ai_workers
  from public, anon, authenticated;
revoke all on table public.pandora_local_ai_build_receipts
  from public, anon, authenticated;

grant all on table public.pandora_local_ai_jobs to service_role;
grant all on table public.pandora_local_ai_workers to service_role;
grant all on table public.pandora_local_ai_build_receipts to service_role;

comment on table public.pandora_local_ai_build_receipts is
  'Reconstructed durable source-history dependency for phone-local exact-source acceptance. Client callback access is retired.';
