-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

-- Targeted, low-risk performance improvements for the Pandora/Pandoras-Box
-- Nano database. These indexes cover the operational relationships most likely
-- to grow, without changing application behavior or broad authorization rules.

create index if not exists pandora_external_events_project_received_idx
  on public.pandora_external_events (project_id, received_at desc)
  where project_id is not null;

create index if not exists pandora_evidence_project_observed_idx
  on public.pandora_evidence (project_id, observed_at desc);

create index if not exists pandora_reconciliation_runs_project_started_idx
  on public.pandora_reconciliation_runs (project_id, started_at desc)
  where project_id is not null;

create index if not exists pandora_task_dependencies_depends_on_idx
  on public.pandora_task_dependencies (depends_on_task_id);

create index if not exists pandora_tasks_phase_idx
  on public.pandora_tasks (phase_id)
  where phase_id is not null;

create index if not exists execution_audit_events_plan_idx
  on private.execution_audit_events (plan_id)
  where plan_id is not null;

create index if not exists execution_plans_intake_idx
  on private.execution_plans (intake_id)
  where intake_id is not null;

-- Preserve the existing INSERT authorization semantics while evaluating the
-- authenticated user once per statement instead of once per candidate row.
alter policy pandora_intake_member_insert
  on public.pandora_intake_requests
  with check (
    private.is_org_member(organization_id)
    and (
      requester_id is null
      or requester_id = (select auth.uid())
    )
  );

analyze public.pandora_external_events;
analyze public.pandora_evidence;
analyze public.pandora_reconciliation_runs;
analyze public.pandora_task_dependencies;
analyze public.pandora_tasks;
analyze private.execution_audit_events;
analyze private.execution_plans;
analyze public.pandora_intake_requests;
