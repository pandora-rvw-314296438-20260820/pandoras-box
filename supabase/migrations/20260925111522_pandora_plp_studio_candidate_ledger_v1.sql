
begin;

create table if not exists public.pandora_plp_studio_candidates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  requested_by uuid null references auth.users(id) on delete set null,
  source_intent_id uuid null references public.pandora_project_intents(id) on delete set null,
  idempotency_key text not null,
  base_main_sha text not null check (base_main_sha ~ '^[0-9a-f]{40}$'),
  candidate_sha text not null check (candidate_sha ~ '^[0-9a-f]{40}$'),
  candidate_tree_sha text null check (candidate_tree_sha is null or candidate_tree_sha ~ '^[0-9a-f]{40}$'),
  candidate_version_id uuid null references public.pandora_project_versions(id) on delete set null,
  preview_deployment_row_id uuid null references public.pandora_project_deployments(id) on delete set null,
  preview_provider_deployment_id text null check (preview_provider_deployment_id is null or preview_provider_deployment_id ~ '^dpl_[A-Za-z0-9]+$'),
  preview_url text null,
  preview_token text null check (preview_token is null or preview_token ~ '^[0-9a-f]{64}$'),
  files_changed jsonb not null default '[]'::jsonb check (jsonb_typeof(files_changed)='array'),
  change_summary text null,
  status text not null default 'preview_building'
    check (status in ('preview_building','preview_ready','publishing','live','failed','stale')),
  merged_main_sha text null check (merged_main_sha is null or merged_main_sha ~ '^[0-9a-f]{40}$'),
  production_version_id uuid null references public.pandora_project_versions(id) on delete set null,
  production_deployment_row_id uuid null references public.pandora_project_deployments(id) on delete set null,
  production_provider_deployment_id text null check (production_provider_deployment_id is null or production_provider_deployment_id ~ '^dpl_[A-Za-z0-9]+$'),
  production_url text null,
  failure_code text null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(project_id,idempotency_key)
);

create index if not exists pandora_plp_studio_candidates_project_status_idx
  on public.pandora_plp_studio_candidates(project_id,status,created_at desc);

alter table public.pandora_plp_studio_candidates enable row level security;
revoke all on public.pandora_plp_studio_candidates from public,anon,authenticated;
grant select,insert,update on public.pandora_plp_studio_candidates to service_role;

commit;
;
