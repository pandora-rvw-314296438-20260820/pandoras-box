const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const source = fs.readFileSync("supabase/functions/pandora-project-runtime/index.ts", "utf8");
const publishStart = source.indexOf("async function publishProject");
const finalizeStart = source.indexOf("async function finalizeProductionVerification");
const serveStart = source.indexOf("Deno.serve", finalizeStart);
const publish = source.slice(publishStart, finalizeStart);
const finalize = source.slice(finalizeStart, serveStart);

test("Vercel scope is resolved from runtime provider config, never a source fallback", () => {
  assert.doesNotMatch(source, /team_IcdJUnzLi5wUN1GD8ALHyjF7/);
  assert.doesNotMatch(source, /PANDORA_VERCEL_TEAM_ID/);
  assert.match(source, /pandora_runtime_provider_configs/);
  assert.match(source, /pandora_worker_f_vercel_request_20260829/);
  assert.doesNotMatch(source, /PANDORA_VERCEL_TOKEN/);
});

test("promotion creates a production candidate instead of self-declaring Live", () => {
  assert.match(publish, /verification_state: "ready_for_verification"/);
  assert.match(publish, /lifecycle_status: "production_candidate"/);
  assert.match(publish, /current_deployment_id: productionRow\.id/);
  assert.match(publish, /runtimeStatus: "verifying"/);
  assert.match(publish, /productionVerificationState: "ready_for_verification"/);
  assert.doesNotMatch(publish, /verification_state: "live_verified"/);
  assert.doesNotMatch(publish, /stage: "live"/);
});

test("only a fresh exact Worker E production_release PASS finalizes Live", () => {
  assert.match(finalize, /target_environment\) !== "production"/);
  assert.match(finalize, /required_check_profile\) !== "production_release"/);
  assert.match(finalize, /verification\.status\)\.toUpperCase\(\) !== "PASS"/);
  assert.match(finalize, /verification\.preview_deployment_id\) !== providerDeploymentId/);
  assert.match(finalize, /completedAt < deploymentCreatedAt/);
  for (const identity of ["project_spec_id", "project_version_id", "build_job_id", "source_commit", "source_digest", "artifact_digest", "migration_set_digest", "runtime_target_digest"]) {
    assert.match(finalize, new RegExp(identity));
  }
  assert.match(finalize, /verification_state: "live_verified"/);
  assert.match(finalize, /lifecycle_status: "live"/);
  assert.match(finalize, /stage: "live"/);
});

test("custom domain is selected for Live only when ownership DNS TLS routing and runtime health are all true", () => {
  for (const fact of ["ownership_verified", "dns_configured", "tls_ready", "routing_ready", "runtime_healthy"]) assert.match(finalize, new RegExp(fact));
  assert.match(finalize, /domainReady/);
});

test("runtime exposes an explicit production verification finalizer route", () => {
  assert.match(source, /production-verification/);
  assert.match(source, /finalizeProductionVerification/);
});


test("production finalization compare-and-set fails closed on races and is organization scoped", () => {
  assert.match(publish, /organization_id[^\n]+context\.organizationId[^\n]+project_id[^\n]+projectId[^\n]+environment[^\n]+production/);
  assert.match(finalize, /deploymentUpdateError \|\| !deploymentUpdated/);
  assert.match(finalize, /environmentUpdateError \|\| !environmentUpdated/);
  assert.match(finalize, /versionUpdateError \|\| !versionUpdated/);
  assert.match(finalize, /select\("id"\)\.maybeSingle\(\)/);
});
