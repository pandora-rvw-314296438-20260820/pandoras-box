-- Worker F: forward-only idempotency repair for runtime CHECK constraints.
-- Historical migration 20260829104000 remains immutable. This migration safely
-- drops/recreates the exact constraints so fresh replay and already-provisioned
-- production schemas converge without rewriting applied history.

alter table public.pandora_project_deployments
  drop constraint if exists pandora_project_deployments_provider_nonempty_check,
  drop constraint if exists pandora_project_deployments_environment_v2_check,
  drop constraint if exists pandora_project_deployments_artifact_digest_check,
  drop constraint if exists pandora_project_deployments_source_commit_check,
  drop constraint if exists pandora_project_deployments_config_digest_check,
  drop constraint if exists pandora_project_deployments_verification_state_check;

alter table public.pandora_project_deployments
  add constraint pandora_project_deployments_provider_nonempty_check
    check (provider ~ '^[a-z][a-z0-9_-]{1,31}$') not valid,
  add constraint pandora_project_deployments_environment_v2_check
    check (environment in ('development','preview','production')) not valid,
  add constraint pandora_project_deployments_artifact_digest_check
    check (artifact_digest is null or artifact_digest ~ '^[0-9a-f]{64}$') not valid,
  add constraint pandora_project_deployments_source_commit_check
    check (source_commit_sha is null or source_commit_sha ~ '^([0-9a-f]{40}|[0-9a-f]{64})$') not valid,
  add constraint pandora_project_deployments_config_digest_check
    check (config_digest is null or config_digest ~ '^[0-9a-f]{64}$') not valid,
  add constraint pandora_project_deployments_verification_state_check
    check (verification_state in ('not_verified','ready_for_verification','live_verified','failed','stale')) not valid;

alter table public.pandora_project_domains
  drop constraint if exists pandora_project_domains_provider_nonempty_check,
  drop constraint if exists pandora_project_domains_environment_check;

alter table public.pandora_project_domains
  add constraint pandora_project_domains_provider_nonempty_check
    check (provider ~ '^[a-z][a-z0-9_-]{1,31}$') not valid,
  add constraint pandora_project_domains_environment_check
    check (environment in ('preview','production')) not valid;
