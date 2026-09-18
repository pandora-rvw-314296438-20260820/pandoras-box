create table if not exists public.pandora_local_ai_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  requested_by uuid not null,
  model text not null check (char_length(model) between 1 and 160),
  request_body jsonb not null,
  status text not null default 'queued' check (status in ('queued','processing','completed','failed','cancelled')),
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

alter table public.pandora_local_ai_jobs enable row level security;
revoke all on public.pandora_local_ai_jobs from anon, authenticated;

create table if not exists public.pandora_local_ai_workers (
  worker_id text primary key,
  model text not null,
  status text not null check (status in ('ready','busy','degraded','offline')),
  last_seen_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

alter table public.pandora_local_ai_workers enable row level security;
revoke all on public.pandora_local_ai_workers from anon, authenticated;

insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active)
values
 ('local','enabled','true',true),
 ('local','routing_eligible','true',true),
 ('local','fallback_enabled','true',true),
 ('local','default_model','Qwen/Qwen2.5-7B-Instruct-GGUF:Q4_K_M',true),
 ('local','allowed_models','["Qwen/Qwen2.5-7B-Instruct-GGUF:Q4_K_M"]',true),
 ('local','task_eligibility','["chat","clarify"]',true),
 ('local','preferred_tasks','[]',true),
 ('local','policy_version','provider-auto-failover-v4',true),
 ('local','stream_mode','buffered_v1',true)
on conflict (provider,config_key) do update
set config_value=excluded.config_value, active=true, updated_at=now();

comment on table public.pandora_local_ai_jobs is
  'Ephemeral service-only queue for Pandora local AI execution on authorized worker nodes.';
comment on table public.pandora_local_ai_workers is
  'Safe heartbeat/readiness projection for authorized local AI worker nodes.';

-- The worker-key verifier is provisioned at runtime and is intentionally not committed.
