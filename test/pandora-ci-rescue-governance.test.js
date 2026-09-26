import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const migration = fs.readFileSync(
  "supabase/migrations/20260919224500_ci_rescue_projectos_exit_and_fencing_v2.sql",
  "utf8",
);
const webhook = fs.readFileSync(
  "supabase/functions/pandora-github-webhook/index.ts",
  "utf8",
);
const runner = fs.readFileSync(
  "supabase/functions/pandora-ci-rescue-runner/index.ts",
  "utf8",
);

test("CI rescue webhook no longer routes through retired ProjectOS", () => {
  assert.equal(webhook.includes("projectos_"), false);
  assert.match(webhook, /pandora_ci_rescue_enqueue_v2/);
  assert.match(webhook, /pandora_record_github_webhook_delivery/);
  assert.match(webhook, /x-hub-signature-256/);
});

test("CI rescue migration removes the legacy trigger and adds durable fencing", () => {
  assert.match(migration, /drop trigger if exists pandora_ci_rescue_external_event_v1/);
  assert.match(migration, /claim_generation bigint not null default 0/);
  assert.match(migration, /idempotency_key text/);
  assert.match(migration, /transient_retry_consumed boolean not null default false/);
  assert.match(migration, /pandora_ci_rescue_audit_events/);
  assert.match(migration, /ci rescue terminal state is immutable/);
  assert.match(migration, /ci rescue stale claim/);
  assert.match(migration, /revoke insert, update, delete, truncate on table private\.pandora_ci_rescue_jobs from service_role/);
});

test("CI rescue eligible workflows are explicit and audit workflow is excluded", () => {
  for (const name of [
    "Canonical release evidence",
    "Engineering toolchain",
    "Windows Worker Contract",
    "Pandora mobile exact-source gate",
    "Dependency Review",
    "Pandora Integration",
  ]) {
    assert.ok(migration.includes("('" + name + "', true)"), name);
  }
  assert.match(migration, /Kimi Evaluation and Verification/);
  assert.match(migration, /delete from private\.pandora_ci_rescue_workflow_allowlist/);
});

test("legacy queue is quarantined rather than executed", () => {
  assert.match(migration, /LEGACY_PROJECTOS_QUEUE_QUARANTINED/);
  assert.match(migration, /legacy_queue_quarantine/);
  assert.match(migration, /status='superseded'/);
});

test("runner checks agent configuration before claiming and never weakens fencing", () => {
  const configIndex = runner.indexOf("pandora_ci_rescue_agent_config_v2");
  const claimIndex = runner.indexOf("pandora_ci_rescue_claim_v2");
  assert.ok(configIndex >= 0);
  assert.ok(claimIndex > configIndex);
  assert.match(runner, /p_claim_generation: claimGeneration/);
  assert.match(runner, /p_lease_token: leaseToken/);
  assert.match(runner, /transition_rejected/);
  assert.equal(runner.includes("pandora_ci_rescue_claim_v1"), false);
  assert.equal(runner.includes("pandora_ci_rescue_update_v1"), false);
});

test("agent completion requires independent GitHub provider readback", () => {
  assert.match(migration, /pandora_ci_rescue_verify_provider_v2/);
  assert.match(migration, /v_run_conclusion = 'success'/);
  assert.match(migration, /v_branch_sha = v_sha/);
  const verifyIndex = runner.indexOf("pandora_ci_rescue_verify_provider_v2");
  const transitionIndex = runner.indexOf("pandora_ci_rescue_transition_v2");
  assert.ok(verifyIndex >= 0);
  assert.ok(transitionIndex > verifyIndex);
  assert.match(runner, /PROVIDER_READBACK_NOT_GREEN/);
  assert.match(runner, /providerReadback/);
});
