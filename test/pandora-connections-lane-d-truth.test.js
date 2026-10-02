import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const ownerApi = await readFile(
  "supabase/functions/pandora-owner-api/index.ts",
  "utf8",
);
const screen = await readFile(
  "apps/pandora-mobile/lib/features/connections/connections_screen.dart",
  "utf8",
);
const observationMigration = await readFile(
  "supabase/migrations/20261002103500_pandora_connection_verification_observations_v1.sql",
  "utf8",
);
const verifierMigration = await readFile(
  "supabase/migrations/20261002104500_pandora_connection_verify_vault_no_spend_v1.sql",
  "utf8",
);

test("Lane D Connections uses one fresh tenant-scoped verification truth per provider", () => {
  assert.match(observationMigration, /pandora_connection_verification_observations_v1/);
  assert.match(observationMigration, /primary key \(organization_id, provider_key\)/);
  assert.match(observationMigration, /state in \('verified','partial','not_connected','error'\)/);
  assert.match(ownerApi, /pandora_connection_verification_observations_v1/);
  assert.match(ownerApi, /applyConnectionVerificationObservation/);
  assert.match(ownerApi, /verificationState: observedState/);
  assert.match(ownerApi, /stale_after/);
});

test("Verify all keeps broker health for active broker accounts and no-spend truth elsewhere", () => {
  assert.match(ownerApi, /functions\/v1\/pandora-connections-broker/);
  assert.match(ownerApi, /verifyVaultNoSpendConnection/);
  assert.match(
    ownerApi,
    /normalizedProvider === "meta"[\s\S]{0,180}verifyMetaConnection\(context, connectionId\)/,
  );
  assert.doesNotMatch(
    screen,
    /verificationEvidence|Verification evidence|_buildEvidence/,
  );
  assert.match(ownerApi, /verifyPublicSafeReadConnection/);
  assert.match(ownerApi, /PUBLIC_SAFE_READ_PROVIDERS/);
  assert.match(verifierMigration, /'posthog','openai','gemini','kimi','meta','google_workspace'/);
  assert.match(verifierMigration, /testInference','not_run_no_spend'/);
  assert.doesNotMatch(verifierMigration, /Reply OK/);
});

test("Connections is deterministically Obsidian with no indigo primary or white card surface", () => {
  assert.match(screen, /ColorScheme\.dark/);
  assert.match(screen, /scaffoldBackgroundColor: PandoraV2Colors\.canvas/);
  assert.match(screen, /backgroundColor: PandoraV2Colors\.ink/);
  assert.match(screen, /foregroundColor: Colors\.black/);
  assert.match(screen, /color: PandoraV2Colors\.surface/);
  assert.match(screen, /OutlinedButton\.icon/);
  assert.doesNotMatch(screen, /PandoraColorTokens\.action/);
  assert.doesNotMatch(screen, /Color\(0xFF7C83FF\)/);
});

test("mobile honors exact provider states without inventing connectivity", () => {
  assert.match(screen, /explicitStatus == 'verified'/);
  assert.match(screen, /explicitStatus == 'partial'/);
  assert.match(screen, /explicitStatus == 'not connected'/);
  assert.match(screen, /explicitStatus == 'error'/);
});
