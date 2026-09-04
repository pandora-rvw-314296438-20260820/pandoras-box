const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { pathToFileURL } = require('node:url');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const migrationPath = join(
  root,
  'supabase/migrations/20260823170000_add_immutable_physical_android_receipts.sql',
);
const edgePath = join(
  root,
  'supabase/functions/pandora-physical-android-attestation/index.ts',
);
const contractPath = join(
  root,
  'supabase/functions/pandora-physical-android-attestation/contract.mjs',
);

function request(overrides = {}) {
  const sourceSha = 'a'.repeat(40);
  return {
    schemaVersion: 1,
    action: 'capture',
    organizationId: '11111111-1111-4111-8111-111111111111',
    requestId: '22222222-2222-4222-8222-222222222222',
    observerId: 'physical-android-01',
    observerKeyFingerprint: '1'.repeat(64),
    repository: 'pandora-rvw-314296438-20260820/pandoras-box',
    sourceSha,
    sourceTreeSha: 'b'.repeat(40),
    productionDeploymentId: 'dpl_exact123',
    productionOrigin: 'https://mcpmaster.vercel.app',
    ciArtifactExternalId: '123456789',
    ciArtifactUrl:
      'https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/artifacts/123456789',
    ciArtifactName: `pandora-mobile-android-validation-${sourceSha}`,
    ciArtifactSha256: '2'.repeat(64),
    apkSha256: '3'.repeat(64),
    deviceIdHash: '4'.repeat(64),
    packageName: 'com.banataosystems.pandora_mobile',
    network: 'wifi',
    providerObservationIndex: 1,
    completedSteps: [
      'owner_authenticate',
      'submit_owner_command',
      'observe_durable_dispatch',
      'observe_worker_01_claim',
      'observe_exact_provider_result',
      'observe_proof_in_owner_read',
    ],
    ownerPlanId: '33333333-3333-4333-8333-333333333333',
    ownerDispatchId: '44444444-4444-4444-8444-444444444444',
    workerEvidenceSha256: '5'.repeat(64),
    verificationEvidenceId: '55555555-5555-4555-8555-555555555555',
    reviewerRuntimeProofId: '66666666-6666-4666-8666-666666666666',
    nonce: 'physical-observer-nonce-0001',
    timestamp: '2026-08-23T12:00:00.000Z',
    signatureB64: `${'A'.repeat(86)}==`,
    ...overrides,
  };
}

test('physical receipt contract fixes every exact journey and network field', async () => {
  const contract = await import(pathToFileURL(contractPath));
  const wifi = request();
  assert.equal(
    contract.validatePhysicalAndroidReceiptRequest(
      wifi,
      new Date('2026-08-23T12:00:10.000Z'),
    ),
    wifi,
  );
  assert.match(
    contract.physicalAndroidReceiptSignatureBasis(wifi),
    /physical-android-01\|1{64}\|22222222-2222-4222-8222-222222222222/,
  );
  assert.throws(
    () => contract.validatePhysicalAndroidReceiptRequest(
      request({ network: 'mobile_data', providerObservationIndex: 1 }),
      new Date('2026-08-23T12:00:10.000Z'),
    ),
    /INVALID_PHYSICAL_ANDROID_RECEIPT/,
  );
  assert.throws(
    () => contract.validatePhysicalAndroidReceiptRequest(
      request({ completedSteps: wifi.completedSteps.slice(0, -1) }),
      new Date('2026-08-23T12:00:10.000Z'),
    ),
    /INVALID_PHYSICAL_ANDROID_RECEIPT/,
  );
});

test('candidate runtime cannot mint or use physical authority', () => {
  const edge = readFileSync(edgePath, 'utf8');
  const migration = readFileSync(migrationPath, 'utf8');
  const config = readFileSync(join(root, 'supabase/config.toml'), 'utf8');

  assert.doesNotMatch(edge, /SUPABASE_SERVICE_ROLE_KEY|PANDORA_PHYSICAL_ANDROID_INGEST_JWT/);
  assert.doesNotMatch(edge, /EXTERNAL_PHYSICAL_AUTHORITY_MISMATCH/);
  assert.doesNotMatch(migration, /issue_physical_android_gateway_capability/);
  assert.match(edge, /EXTERNAL_AUTHORITY_ISSUER/);
  assert.match(edge, /request\.headers\.get\("authorization"\)/);
  assert.match(edge, /global: \{ headers: \{ authorization \} \}/);
  assert.match(edge, /throw new Error\("OBSERVER_AUTH_FAILED"\)/);
  assert.match(edge, /consume_physical_android_authority_rate_limit/);
  assert.match(migration, /physical_android_authority_jtis/);
  assert.match(migration, /request_sha256.*authority_request_sha/s);
  assert.match(migration, /authority_expires_at > authority_issued_at/);
  assert.match(migration, /consumed_at >= authority_issued_at - interval '30 seconds'/);
  assert.match(migration, /primary key \(issuer, jti\)/);
  assert.match(migration, /from public, anon, authenticated, service_role, projectos_physical_android_ingest/);
  assert.match(migration, /\) to projectos_physical_android_ingest;/);
  const captureGrant = migration.match(
    /grant execute on function public\.capture_canonical_physical_android_receipt\([\s\S]*?\) to ([^;]+);/,
  );
  assert.ok(captureGrant);
  assert.equal(captureGrant[1].trim(), 'projectos_physical_android_ingest');
  assert.match(
    config,
    /\[functions\.pandora-physical-android-attestation\]\s+verify_jwt = true/,
  );
  assert.match(config, /caller-supplied, externally issued one-shot authority JWT/i);
  assert.doesNotMatch(config, /mints? (?:a )?one-use capability/i);
});

test('release review and status authority require immutable ordered receipts', () => {
  const migration = readFileSync(migrationPath, 'utf8');
  assert.match(migration, /bind_release_review_to_physical_android_receipts/);
  assert.match(migration, /provider_observed_at < mobile\.provider_observed_at/);
  assert.match(migration, /candidate\.captured_at < mobile\.captured_at/);
  assert.match(migration, /physical_wifi_receipt_id/);
  assert.match(migration, /physical_mobile_data_receipt_id/);
  assert.match(migration, /IMMUTABLE_PHYSICAL_ANDROID_RECEIPT/);
  assert.match(migration, /owner_plan_id/);
  assert.match(migration, /worker_evidence_sha256/);
  assert.match(migration, /reviewer_runtime_proof_id/);
});

test('physical Android rollback disables authority and preserves immutable evidence', () => {
  const rollback = readFileSync(join(
    root,
    'docs/supabase/recovery/jcyqixttuebxqqfkjonq/rollback/20260823170000_remove_immutable_physical_android_receipts.sql',
  ), 'utf8');
  assert.match(rollback, /FAIL-CLOSED CAPABILITY-DISABLE ROLLBACK/);
  assert.match(rollback, /revoke all on function public\.capture_canonical_physical_android_receipt/);
  assert.match(rollback, /revoke all on function public\.get_canonical_release_status_without_physical_android_authority/);
  assert.match(rollback, /get_canonical_release_status_without_final_attestations/);
  assert.match(rollback, /revoke projectos_physical_android_ingest from authenticator/);
  assert.match(rollback, /set status = 'draining'/);
  assert.match(rollback, /begin;[\s\S]*commit;/);
  assert.doesNotMatch(
    rollback,
    /\b(?:drop|delete\s+from|truncate|grant\s+execute|rename\s+to)\b/i,
  );
});
