"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { pathToFileURL } = require("node:url");

const root = join(__dirname, "..");
const migration = readFileSync(join(
  root,
  "supabase/migrations/20260823153552_canonical_release_status_readback.sql",
), "utf8");
const control = readFileSync(join(
  root,
  "supabase/functions/mcpmaster-supabase-control/index.ts",
), "utf8");
const captureRoutesPath = join(
  root,
  "supabase/functions/mcpmaster-supabase-control/canonical-release-capture-routes.mjs",
);
const captureRoutes = readFileSync(captureRoutesPath, "utf8");
const rollback = readFileSync(join(
  root,
  "docs/supabase/recovery/jcyqixttuebxqqfkjonq/rollback/20260823153552_remove_canonical_release_status_readback.sql",
), "utf8");
const mobileWorkflow = readFileSync(join(
  root,
  ".github/workflows/pandora-mobile-integration.yml",
), "utf8");

test("canonical release readback is service-role-only and source-bound", () => {
  assert.match(migration, /get_canonical_release_status/);
  assert.match(migration, /private\.assert_control_service_role\(\)/);
  assert.match(migration, /p_repository <> 'banataosystems\/Pandoras-box'/);
  assert.match(migration, /p_source_sha !~ '\^\[0-9a-f\]\{40\}\$'/);
  assert.match(migration, /revoke all[\s\S]*from public, anon, authenticated/i);
  assert.match(migration, /grant execute[\s\S]*to service_role/i);
});

test("rollback capture live-reads one fixed alias around fixed route probes", () => {
  assert.match(migration, /private\.canonical_vercel_rehearsal_receipts/);
  assert.match(migration, /capture_canonical_vercel_rehearsal_receipt/);
  assert.match(migration, /canonical_vercel_production/);
  assert.match(migration, /phase in \('rollback_transition', 'rollback_restoration'\)/);
  assert.match(migration, /candidate_deployment_id <> rollback_deployment_id/);
  assert.match(migration, /candidate_source_sha <> rollback_source_sha/);
  assert.match(migration, /alias_pre_observed_at < route_probe_observed_at[\s\S]*route_probe_observed_at < alias_post_observed_at/s);
  assert.match(migration, /https:\/\/api\.vercel\.com\/v13\/deployments\//);
  assert.match(migration, /https:\/\/api\.vercel\.com\/v13\/deployments\/mcpmaster\.vercel\.app/);
  assert.match(migration, /https:\/\/mcpmaster\.vercel\.app\/health/);
  assert.match(migration, /https:\/\/mcpmaster\.vercel\.app\/mcp/);
  assert.match(migration, /https:\/\/mcpmaster\.vercel\.app\/\.well-known\/oauth-protected-resource\/mcp/);
  assert.doesNotMatch(migration, /p_route_probe_(?:source_url|external_id)/);
  assert.match(migration, /http\.curlopt_connecttimeout_ms/);
  assert.match(migration, /http\.curlopt_timeout_ms/);
  assert.match(migration, /octet_length\(coalesce\(alias_response\.content/);
  assert.match(migration, /alias_payload is null/);
  assert.match(migration, /alias_post_payload is null/);
  assert.match(migration, /health_payload is null[\s\S]*metadata_payload is null/s);
  assert.match(migration, /alias_post_response[\s\S]*live Vercel alias changed during route probes/s);
  assert.match(migration, /production_payload ->> 'readyState' = 'READY'/);
  assert.match(migration, /production_payload ->> 'target' = 'production'/);
  assert.match(migration, /rollback_payload ->> 'readyState' = 'READY'/);
  assert.match(migration, /githubCommitOrg/);
  assert.match(migration, /githubCommitRepo/);
  assert.doesNotMatch(migration, /payload_redacted\s*->\s*'rollbackVerified'/);
  assert.match(migration, /'rollbackVerified', true/);
});

test("Supabase receipt binds source artifact to captured live versions without claiming applied bytes", () => {
  assert.match(migration, /private\.canonical_supabase_release_receipts/);
  assert.match(migration, /capture_canonical_supabase_release_receipt/);
  assert.match(migration, /from supabase_migrations\.schema_migrations/);
  assert.match(migration, /captured_version_chain_sha256 = expected_version_chain_sha256/);
  assert.match(migration, /source_chain_sha256 text not null/);
  assert.match(migration, /source_artifact_sha256 text not null/);
  assert.match(migration, /sourceArtifactDatabaseReceipt/);
  assert.match(migration, /'databaseCaptured', true/);
  assert.match(migration, /'exactAppliedBytesProven', false/);
  assert.match(migration, /'providerReadback', false/);
  assert.doesNotMatch(migration, /sourceArtifactReceipt[\s\S]*'readback', true/s);
  assert.match(migration, /canonical release receipts are immutable/);
  assert.match(migration, /revoke all on table private\.canonical_supabase_release_receipts[\s\S]*service_role/s);
  assert.match(migration, /grant execute on function public\.capture_canonical_supabase_release_receipt[\s\S]*to service_role/s);
  assert.match(rollback, /FAIL-CLOSED CAPABILITY-DISABLE ROLLBACK/);
  assert.match(rollback, /revoke all on function public\.capture_canonical_supabase_release_receipt/);
  assert.match(rollback, /revoke all on function public\.capture_canonical_vercel_rehearsal_receipt/);
  assert.match(rollback, /revoke all on function public\.get_canonical_release_status/);
  assert.match(rollback, /get_canonical_release_status_without_physical_android_authority/);
  assert.match(rollback, /get_canonical_release_status_without_final_attestations/);
  assert.match(rollback, /begin;[\s\S]*commit;/);
  assert.doesNotMatch(rollback, /\b(?:drop|delete\s+from|truncate|grant\s+execute)\b/i);
});

test("physical network receipts remain source, build, and device bound", () => {
  assert.match(migration, /canonical_physical_android_wifi/);
  assert.match(migration, /canonical_physical_android_mobile_data/);
  assert.match(migration, /deviceIdHash/);
  assert.match(migration, /observe_proof_in_owner_read/);
  assert.match(migration, /com\.banataosystems\.pandora_mobile/);
  assert.match(migration, /evidence\.payload_redacted ->> 'artifactSha256'[\s\S]*= wifi\.payload_redacted ->> 'artifactSha256'/s);
  assert.match(migration, /ciArtifactDatabaseReceipt/);
  assert.match(migration, /pandora-mobile-android-validation-' \|\| p_source_sha/);
  assert.match(migration, /\{ciArtifact,digestSha256\}/);
  assert.match(migration, /\{ciArtifact,apkSha256\}/);
  assert.match(migration, /https:\/\/mcpmaster\.vercel\.app/);
  assert.match(migration, /evidence\.observed_at > rollback_restoration\.alias_post_observed_at/);
  assert.match(migration, /evidence\.payload_redacted -> 'ciArtifact'[\s\S]*= wifi\.payload_redacted -> 'ciArtifact'/s);
});

test("mobile CI publishes an exact-source GitHub artifact locator", () => {
  assert.match(
    mobileWorkflow,
    /ANDROID_ARTIFACT_NAME: pandora-mobile-android-validation-\$\{\{ github\.sha \}\}/,
  );
  assert.match(mobileWorkflow, /id: upload_android_validation/);
  assert.match(mobileWorkflow, /name: \$\{\{ env\.ANDROID_ARTIFACT_NAME \}\}/);
  assert.match(mobileWorkflow, /steps\.upload_android_validation\.outputs\.artifact-id/);
  assert.match(mobileWorkflow, /steps\.upload_android_validation\.outputs\.artifact-digest/);
  assert.match(mobileWorkflow, /artifact_api_url="https:\/\/api\.github\.com\/repos\/\$\{GITHUB_REPOSITORY\}\/actions\/artifacts\/\$\{ARTIFACT_ID\}"/);
});

test("OIDC control route accepts only the canonical repository and exact source SHA", () => {
  assert.match(control, /input\.action === "canonical_release_status"/);
  assert.match(control, /repository !== "banataosystems\/Pandoras-box"/);
  assert.match(control, /\^\[0-9a-f\]\{40\}\$/);
  assert.match(control, /rpc: "get_canonical_release_status"/);
  assert.match(control, /responseKey: "releaseEvidence"/);
});

test("authenticated control exposes closed-schema immutable receipt capture actions", () => {
  assert.match(captureRoutes, /input\.action === "canonical_supabase_receipt_capture"/);
  assert.match(captureRoutes, /exactKeys\(input,[\s\S]*"sourceArtifactExternalId"[\s\S]*"expectedVersionChainSha256"/s);
  assert.match(captureRoutes, /rpc: "capture_canonical_supabase_release_receipt"/);
  assert.match(captureRoutes, /responseKey: "supabaseReceipt"/);
  assert.match(captureRoutes, /\^\[1-9\]\[0-9\]\{0,19\}\$/);
  assert.match(captureRoutes, /https:\/\/api\.github\.com\/repos\/banataosystems\/Pandoras-box\/actions\/artifacts\//);

  assert.match(captureRoutes, /input\.action === "canonical_vercel_rehearsal_capture"/);
  assert.match(captureRoutes, /exactKeys\(input,[\s\S]*"candidateDeploymentId"[\s\S]*"rollbackSourceSha"/s);
  assert.match(captureRoutes, /\["rollback_transition", "rollback_restoration"\]\.includes\(phase \|\| ""\)/);
  assert.match(captureRoutes, /\^dpl_\[A-Za-z0-9\]\{1,128\}\$/);
  assert.match(captureRoutes, /candidateSourceSha === rollbackSourceSha/);
  assert.match(captureRoutes, /candidateDeploymentId === rollbackDeploymentId/);
  assert.match(captureRoutes, /rpc: "capture_canonical_vercel_rehearsal_receipt"/);
  assert.match(captureRoutes, /responseKey: "vercelRehearsalReceipt"/);
  assert.doesNotMatch(captureRoutes, /routeProbeSourceUrl|routeProbeExternalId/);
  assert.match(
    control,
    /responseKey === "supabaseReceipt" \|\| route\.responseKey === "vercelRehearsalReceipt"[\s\S]*if \(!payload \|\| typeof payload !== "object" \|\| Array\.isArray\(payload\)\)[\s\S]*response\(502/s,
  );
});

test("capture router rejects extra keys and mismatched canonical identities", async () => {
  const { routeForCanonicalReleaseCapture } = await import(pathToFileURL(captureRoutesPath).href);
  const sourceSha = "a".repeat(40);
  const rollbackSha = "b".repeat(40);
  const artifactId = "123456";
  const supabaseInput = {
    action: "canonical_supabase_receipt_capture",
    repository: "pandora-rvw-314296438-20260820/pandoras-box",
    sourceSha,
    sourceTreeSha: "c".repeat(40),
    sourceChainSha256: "d".repeat(64),
    sourceArtifactSha256: "e".repeat(64),
    sourceArtifactExternalId: artifactId,
    sourceArtifactUrl: `https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/artifacts/${artifactId}`,
    expectedVersionChainSha256: "f".repeat(64),
  };
  assert.equal(routeForCanonicalReleaseCapture(supabaseInput)?.responseKey, "supabaseReceipt");
  assert.equal(routeForCanonicalReleaseCapture({ ...supabaseInput, extra: true }), undefined);
  assert.equal(routeForCanonicalReleaseCapture({
    ...supabaseInput,
    sourceArtifactUrl: `${supabaseInput.sourceArtifactUrl}0`,
  }), undefined);
  assert.equal(routeForCanonicalReleaseCapture({ ...supabaseInput, sourceSha: sourceSha.toUpperCase() }), undefined);

  const vercelInput = {
    action: "canonical_vercel_rehearsal_capture",
    repository: "pandora-rvw-314296438-20260820/pandoras-box",
    candidateSourceSha: sourceSha,
    phase: "rollback_transition",
    candidateDeploymentId: "dpl_candidate",
    rollbackDeploymentId: "dpl_rollback",
    rollbackSourceSha: rollbackSha,
  };
  assert.equal(routeForCanonicalReleaseCapture(vercelInput)?.responseKey, "vercelRehearsalReceipt");
  assert.equal(routeForCanonicalReleaseCapture({ ...vercelInput, phase: "rollbackVerified" }), undefined);
  assert.equal(routeForCanonicalReleaseCapture({ ...vercelInput, rollbackSourceSha: sourceSha }), undefined);
  assert.equal(routeForCanonicalReleaseCapture({
    ...vercelInput,
    rollbackDeploymentId: vercelInput.candidateDeploymentId,
  }), undefined);
  assert.equal(routeForCanonicalReleaseCapture({
    ...vercelInput,
    rollbackDeploymentId: `dpl_${"a".repeat(129)}`,
  }), undefined);
});
