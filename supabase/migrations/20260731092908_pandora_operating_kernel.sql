-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

create table public.projectos_projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_key text not null check (project_key ~ '^[a-z0-9][a-z0-9._-]{0,79}$'),
  name text not null check (char_length(name) between 1 and 160),
  repository text check (repository is null or repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  workspace_path text not null check (workspace_path ~ '^projectos/projects/[a-z0-9][a-z0-9._-]{0,79}$'),
  status text not null default 'active' check (status in ('active','blocked','paused','complete','archived')),
  objective text not null default '',
  roadmap_version text not null default '1.0.0',
  current_phase_key text,
  current_task_key text,
  progress_percent numeric(5,2) not null default 0 check (progress_percent between 0 and 100),
  config jsonb not null default '{}'::jsonb check (jsonb_typeof(config) = 'object'),
  created_by uuid references auth.users(id),
  last_reconciled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, project_key),
  unique (organization_id, repository)
);

create table public.projectos_project_resources (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  provider text not null check (provider ~ '^[a-z][a-z0-9_-]{1,63}$'),
  resource_type text not null check (resource_type ~ '^[a-z][a-z0-9_-]{1,63}$'),
  external_id text not null,
  external_name text,
  environment text,
  canonical_url text,
  binding_state text not null default 'verified' check (binding_state in ('verified','degraded','missing','not_required','quarantined')),
  configuration jsonb not null default '{}'::jsonb check (jsonb_typeof(configuration) = 'object'),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, provider, resource_type, external_id)
);

create table public.projectos_phases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  phase_key text not null check (phase_key ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$'),
  name text not null check (char_length(name) between 1 and 200),
  sequence integer not null check (sequence >= 0),
  status text not null default 'planned' check (status in ('planned','active','blocked','complete','skipped')),
  exit_criteria jsonb not null default '[]'::jsonb check (jsonb_typeof(exit_criteria) = 'array'),
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, phase_key),
  unique (project_id, sequence)
);

create table public.projectos_tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  phase_id uuid references public.projectos_phases(id) on delete set null,
  task_key text not null check (task_key ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$'),
  title text not null check (char_length(title) between 1 and 240),
  description text not null default '',
  sequence integer not null default 0 check (sequence >= 0),
  priority integer not null default 50 check (priority between 0 and 100),
  status text not null default 'not_started' check (status in ('not_started','ready','in_progress','waiting_review','waiting_approval','blocked','complete','cancelled')),
  continuation_role text not null default 'primary' check (continuation_role in ('primary','parallel','optional')),
  blocks_phase_exit boolean not null default true,
  risk_class text not null default 'R1' check (risk_class in ('R0','R1','R2','R3','R4')),
  builder_agent text,
  builder_vendor text,
  reviewer_agent text,
  reviewer_vendor text,
  completion_criteria jsonb not null default '[]'::jsonb check (jsonb_typeof(completion_criteria) = 'array'),
  current_branch text,
  current_pr_number integer check (current_pr_number is null or current_pr_number > 0),
  current_head_sha text check (current_head_sha is null or current_head_sha ~ '^[0-9a-f]{40}$'),
  result_summary jsonb not null default '{}'::jsonb check (jsonb_typeof(result_summary) = 'object'),
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, task_key),
  unique (project_id, sequence)
);

create table public.projectos_task_dependencies (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  task_id uuid not null references public.projectos_tasks(id) on delete cascade,
  depends_on_task_id uuid not null references public.projectos_tasks(id) on delete cascade,
  dependency_type text not null default 'hard' check (dependency_type in ('hard','soft','evidence')),
  created_at timestamptz not null default now(),
  primary key (task_id, depends_on_task_id),
  check (task_id <> depends_on_task_id)
);

create table public.projectos_intake_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid references public.projectos_projects(id) on delete set null,
  requester_id uuid references auth.users(id),
  source text not null default 'operator' check (source in ('operator','chatgpt','github','slack','email','api','system')),
  request_type text not null default 'work' check (request_type in ('work','research','incident','maintenance','release','idea','decision')),
  request_text text not null check (char_length(request_text) between 1 and 20000),
  project_hint text,
  repository_hint text check (repository_hint is null or repository_hint ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  idempotency_key text not null,
  status text not null default 'accepted' check (status in ('accepted','analyzing','planned','executing','completed','blocked','rejected')),
  analysis jsonb not null default '{}'::jsonb check (jsonb_typeof(analysis) = 'object'),
  workflow_run_id uuid references public.workflow_runs(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, idempotency_key)
);

create table public.projectos_external_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid references public.projectos_projects(id) on delete set null,
  provider text not null check (provider ~ '^[a-z][a-z0-9_-]{1,63}$'),
  delivery_id text not null,
  event_type text not null,
  repository text check (repository is null or repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  external_created_at timestamptz,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  payload_redacted jsonb not null default '{}'::jsonb check (jsonb_typeof(payload_redacted) = 'object'),
  process_status text not null default 'received' check (process_status in ('received','processed','ignored','failed')),
  process_error text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (organization_id, provider, delivery_id)
);

create table public.projectos_evidence (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  task_id uuid references public.projectos_tasks(id) on delete cascade,
  evidence_type text not null check (evidence_type ~ '^[a-z][a-z0-9_.-]{1,127}$'),
  provider text not null check (provider ~ '^[a-z][a-z0-9_-]{1,63}$'),
  external_id text,
  source_url text,
  repository text check (repository is null or repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  head_sha text check (head_sha is null or head_sha ~ '^[0-9a-f]{40}$'),
  status text not null default 'observed' check (status in ('observed','passing','failing','complete','blocked','superseded','invalidated')),
  verdict text,
  payload_redacted jsonb not null default '{}'::jsonb check (jsonb_typeof(payload_redacted) = 'object'),
  observed_at timestamptz not null default now(),
  invalidated_at timestamptz,
  invalidation_reason text,
  created_at timestamptz not null default now()
);
create unique index projectos_evidence_external_unique
  on public.projectos_evidence (organization_id, provider, evidence_type, external_id)
  where external_id is not null;
create index projectos_evidence_task_idx on public.projectos_evidence (task_id, observed_at desc);

create table public.projectos_reconciliation_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid references public.projectos_projects(id) on delete cascade,
  provider text not null,
  status text not null default 'running' check (status in ('running','succeeded','partial','failed')),
  cursor_before jsonb not null default '{}'::jsonb,
  cursor_after jsonb not null default '{}'::jsonb,
  stats jsonb not null default '{}'::jsonb,
  error_code text,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create table public.projectos_integration_health (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  provider text not null,
  status text not null default 'unknown' check (status in ('healthy','degraded','down','unknown','not_configured')),
  last_event_at timestamptz,
  last_success_at timestamptz,
  stale_after timestamptz,
  details jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (project_id, provider)
);

create table public.projectos_decisions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  task_id uuid references public.projectos_tasks(id) on delete set null,
  decision_type text not null,
  statement text not null check (char_length(statement) between 1 and 10000),
  rationale text not null default '',
  confidence numeric(4,3) not null default 1 check (confidence between 0 and 1),
  source text not null default 'operator',
  supersedes_id uuid references public.projectos_decisions(id) on delete set null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.projectos_task_outcomes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  task_id uuid not null references public.projectos_tasks(id) on delete cascade,
  planned jsonb not null default '{}'::jsonb,
  actual jsonb not null default '{}'::jsonb,
  success boolean not null,
  quality_score numeric(5,2) check (quality_score is null or quality_score between 0 and 100),
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  repair_attempts integer not null default 0 check (repair_attempts >= 0),
  deployment_result text,
  impact_metrics jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  unique (task_id)
);

create table public.projectos_lessons (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  scope text not null check (scope in ('project','portfolio','operational')),
  project_id uuid references public.projectos_projects(id) on delete cascade,
  source_task_id uuid references public.projectos_tasks(id) on delete set null,
  category text not null,
  lesson text not null check (char_length(lesson) between 1 and 10000),
  pattern jsonb not null default '{}'::jsonb,
  evidence_count integer not null default 1 check (evidence_count >= 1),
  confidence numeric(4,3) not null default 0.5 check (confidence between 0 and 1),
  status text not null default 'candidate' check (status in ('candidate','promoted','rejected','superseded')),
  applies_to jsonb not null default '{}'::jsonb,
  promoted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((scope = 'project' and project_id is not null) or scope <> 'project')
);

create table public.projectos_agent_observations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid references public.projectos_projects(id) on delete set null,
  task_id uuid references public.projectos_tasks(id) on delete set null,
  agent_key text not null,
  vendor text not null,
  role text not null check (role in ('planner','builder','reviewer','operator','analyst')),
  success boolean not null,
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  repair_attempts integer not null default 0 check (repair_attempts >= 0),
  quality_score numeric(5,2) check (quality_score is null or quality_score between 0 and 100),
  cost_cents integer not null default 0 check (cost_cents >= 0),
  capabilities jsonb not null default '[]'::jsonb,
  notes jsonb not null default '{}'::jsonb,
  observed_at timestamptz not null default now()
);
create index projectos_agent_observations_agent_idx on public.projectos_agent_observations (organization_id, agent_key, observed_at desc);

create table public.projectos_workspace_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  document_key text not null check (document_key in ('identity','objectives','architecture','roadmap','tasks','decisions','risks','integrations','deployments','analytics','evidence','audit','lessons','current_state','next_action')),
  version integer not null default 1 check (version > 0),
  content jsonb not null default '{}'::jsonb,
  source_hash text check (source_hash is null or source_hash ~ '^[0-9a-f]{64}$'),
  generated_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, document_key)
);

create table public.projectos_projections (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  version bigint not null default 1 check (version > 0),
  projection jsonb not null default '{}'::jsonb,
  source_event_id bigint references public.projectos_external_events(id) on delete set null,
  computed_at timestamptz not null default now(),
  stale_after timestamptz,
  primary key (project_id)
);

create table public.projectos_learning_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid references public.projectos_projects(id) on delete cascade,
  status text not null default 'running' check (status in ('running','succeeded','failed','no_change')),
  inputs jsonb not null default '{}'::jsonb,
  outputs jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  error_code text
);

create table public.projectos_policies (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  mandatory_control_layer boolean not null default true,
  require_project_workspace boolean not null default true,
  require_evidence_for_completion boolean not null default true,
  require_exact_sha_review boolean not null default true,
  require_independent_vendor_review boolean not null default true,
  require_owner_release_approval boolean not null default true,
  allow_untracked_work boolean not null default false,
  learning_enabled boolean not null default true,
  promotion_min_evidence integer not null default 3 check (promotion_min_evidence >= 1),
  policy jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create trigger projectos_projects_updated before update on public.projectos_projects for each row execute function private.set_updated_at();
create trigger projectos_project_resources_updated before update on public.projectos_project_resources for each row execute function private.set_updated_at();
create trigger projectos_phases_updated before update on public.projectos_phases for each row execute function private.set_updated_at();
create trigger projectos_tasks_updated before update on public.projectos_tasks for each row execute function private.set_updated_at();
create trigger projectos_intake_updated before update on public.projectos_intake_requests for each row execute function private.set_updated_at();
create trigger projectos_lessons_updated before update on public.projectos_lessons for each row execute function private.set_updated_at();
create trigger projectos_workspace_documents_updated before update on public.projectos_workspace_documents for each row execute function private.set_updated_at();

alter table public.projectos_projects enable row level security;
alter table public.projectos_project_resources enable row level security;
alter table public.projectos_phases enable row level security;
alter table public.projectos_tasks enable row level security;
alter table public.projectos_task_dependencies enable row level security;
alter table public.projectos_intake_requests enable row level security;
alter table public.projectos_external_events enable row level security;
alter table public.projectos_evidence enable row level security;
alter table public.projectos_reconciliation_runs enable row level security;
alter table public.projectos_integration_health enable row level security;
alter table public.projectos_decisions enable row level security;
alter table public.projectos_task_outcomes enable row level security;
alter table public.projectos_lessons enable row level security;
alter table public.projectos_agent_observations enable row level security;
alter table public.projectos_workspace_documents enable row level security;
alter table public.projectos_projections enable row level security;
alter table public.projectos_learning_runs enable row level security;
alter table public.projectos_policies enable row level security;

do $$
declare t text;
begin
  foreach t in array array[
    'projectos_projects','projectos_project_resources','projectos_phases','projectos_tasks',
    'projectos_task_dependencies','projectos_intake_requests','projectos_external_events',
    'projectos_evidence','projectos_reconciliation_runs','projectos_integration_health',
    'projectos_decisions','projectos_task_outcomes','projectos_lessons',
    'projectos_agent_observations','projectos_workspace_documents','projectos_projections',
    'projectos_learning_runs','projectos_policies'
  ] loop
    execute format('create policy %I on public.%I for select to authenticated using (private.is_org_member(organization_id))', t || '_member_read', t);
  end loop;
end $$;

create policy projectos_projects_operator_write on public.projectos_projects for all to authenticated
  using (private.has_org_role(organization_id, array['owner','admin','operator']::member_role[]))
  with check (private.has_org_role(organization_id, array['owner','admin','operator']::member_role[]));
create policy projectos_resources_operator_write on public.projectos_project_resources for all to authenticated
  using (private.has_org_role(organization_id, array['owner','admin','operator']::member_role[]))
  with check (private.has_org_role(organization_id, array['owner','admin','operator']::member_role[]));
create policy projectos_phases_operator_write on public.projectos_phases for all to authenticated
  using (private.has_org_role(organization_id, array['owner','admin','operator']::member_role[]))
  with check (private.has_org_role(organization_id, array['owner','admin','operator']::member_role[]));
create policy projectos_tasks_operator_write on public.projectos_tasks for all to authenticated
  using (private.has_org_role(organization_id, array['owner','admin','operator']::member_role[]))
  with check (private.has_org_role(organization_id, array['owner','admin','operator']::member_role[]));
create policy projectos_dependencies_operator_write on public.projectos_task_dependencies for all to authenticated
  using (private.has_org_role(organization_id, array['owner','admin','operator']::member_role[]))
  with check (private.has_org_role(organization_id, array['owner','admin','operator']::member_role[]));
create policy projectos_intake_member_insert on public.projectos_intake_requests for insert to authenticated
  with check (private.is_org_member(organization_id) and (requester_id is null or requester_id = auth.uid()));
create policy projectos_intake_operator_update on public.projectos_intake_requests for update to authenticated
  using (private.has_org_role(organization_id, array['owner','admin','operator']::member_role[]))
  with check (private.has_org_role(organization_id, array['owner','admin','operator']::member_role[]));
create policy projectos_policies_owner_write on public.projectos_policies for all to authenticated
  using (private.has_org_role(organization_id, array['owner','admin']::member_role[]))
  with check (private.has_org_role(organization_id, array['owner','admin']::member_role[]));

grant select on all tables in schema public to authenticated;
grant insert, update, delete on public.projectos_projects, public.projectos_project_resources, public.projectos_phases, public.projectos_tasks, public.projectos_task_dependencies to authenticated;
grant insert, update on public.projectos_intake_requests to authenticated;
grant insert, update, delete on public.projectos_policies to authenticated;
grant usage, select on sequence public.projectos_external_events_id_seq to authenticated;
