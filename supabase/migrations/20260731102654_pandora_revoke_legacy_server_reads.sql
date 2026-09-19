-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

revoke select on table public.credential_refs from authenticated;
revoke select on table public.webhook_events from authenticated;
revoke select on table public.meta_webhook_health from authenticated;

grant select on table
  public.pandora_projects,
  public.pandora_project_resources,
  public.pandora_phases,
  public.pandora_tasks,
  public.pandora_task_dependencies,
  public.pandora_intake_requests,
  public.pandora_external_events,
  public.pandora_evidence,
  public.pandora_reconciliation_runs,
  public.pandora_integration_health,
  public.pandora_decisions,
  public.pandora_task_outcomes,
  public.pandora_lessons,
  public.pandora_agent_observations,
  public.pandora_workspace_documents,
  public.pandora_projections,
  public.pandora_learning_runs,
  public.pandora_policies
to authenticated;
