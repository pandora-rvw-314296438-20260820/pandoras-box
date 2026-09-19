-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

drop policy if exists projectos_integration_secrets_deny_clients on private.integration_secrets; create policy projectos_integration_secrets_deny_clients on private.integration_secrets for all to anon,authenticated using(false) with check(false);
