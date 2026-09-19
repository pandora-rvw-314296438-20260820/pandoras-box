-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

revoke select on table public.credential_refs from authenticated;
revoke select on table public.webhook_events from authenticated;
revoke select on table public.meta_webhook_health from authenticated;

grant select on table
  public.projectos_projects,
  public.projectos_project_resources,
  public.projectos_phases,
  public.projectos_tasks,
  public.projectos_task_dependencies,
  public.projectos_intake_requests,
  public.projectos_external_events,
  public.projectos_evidence,
  public.projectos_reconciliation_runs,
  public.projectos_integration_health,
  public.projectos_decisions,
  public.projectos_task_outcomes,
  public.projectos_lessons,
  public.projectos_agent_observations,
  public.projectos_workspace_documents,
  public.projectos_projections,
  public.projectos_learning_runs,
  public.projectos_policies
to authenticated;
