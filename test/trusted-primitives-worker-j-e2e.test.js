'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  composePrimitives,
  createDefaultPrimitiveRegistry,
  digest,
  planPrimitiveUpgrades,
  planPrimitiveMaterialization,
  buildWorkerDMaterializationRequest,
  planExecutionBoundaries,
  validateEventCompatibility,
  projectVersionPrimitiveLineage,
  primitiveUpgradeLineage,
} = require('../packages/primitives/src');
const {
  AUTHORITATIVE_ISSUER,
  buildPrimitiveVerificationDecision,
  createPrimitiveVerificationAuthority,
  scanPrimitiveAdversarialFixtures,
} = require('../packages/pandora-verification/src/primitive-trust');
const { createPrimitiveEconomicsFacts } = require('../packages/pandora-business-intelligence/src/primitive-economics');
const {
  assertExactLineage,
  normalizeDeploymentRequest,
} = require('../packages/pandora-project-runtime/src');

const ORG = '11111111-1111-4111-8111-111111111111';
const PROJECT = '22222222-2222-4222-8222-222222222222';
const VERSION_1 = '33333333-3333-4333-8333-333333333333';
const VERSION_2 = '44444444-4444-4444-8444-444444444444';
const SOURCE_COMMIT = 'a'.repeat(40);
const RUNTIME_CAPABILITIES = Object.freeze([
  'identity-provider',
  'database',
  'notification-provider',
  'analytics-sink',
  'transactions',
  'payment-provider',
  'object-storage',
  'search-provider',
  'configuration-store',
]);

function configurationFor(name) {
  if (name === 'pandora-booking') return { timezone: 'Asia/Manila', capacityMode: 'resource' };
  if (name === 'pandora-files') return { maxBytes: 5_000_000, allowedContentTypes: ['image/png'], privateByDefault: true };
  return {};
}

function selections(definitions, overrides = {}) {
  return definitions.map((definition) => ({
    name: definition.name,
    version: overrides[definition.name] || definition.version,
    configuration: configurationFor(definition.name),
    customization: definition.name === 'pandora-settings' ? { brandingPreset: 'customer-owned' } : {},
  }));
}

function workerEPass(definition) {
  return Object.freeze({
    verification_run_id: `worker-e-${definition.name}-1`,
    status: 'PASS',
    identity_digest: digest({ primitive: definition.name, version: definition.version }),
    completed_at: '2026-08-29T02:56:00Z',
    request: Object.freeze({ source_digest: definition.sourceDigest }),
    required_checks: Object.freeze(['primitive.contract', 'primitive.security']),
    results: Object.freeze([
      Object.freeze({ check_id: 'primitive.contract', status: 'PASS', authoritative_issuer: AUTHORITATIVE_ISSUER, evidence_refs: Object.freeze([`evidence:${definition.name}:contract`]) }),
      Object.freeze({ check_id: 'primitive.security', status: 'PASS', authoritative_issuer: AUTHORITATIVE_ISSUER, evidence_refs: Object.freeze([`evidence:${definition.name}:security`]) }),
    ]),
  });
}

test('Worker J composes all 18 exact primitive families and carries them through release lineage', () => {
  const sealedWorkerERuns = new Map();
  const verificationAuthority = createPrimitiveVerificationAuthority({
    readVerificationRun: (evidenceId) => sealedWorkerERuns.get(evidenceId) || null,
  });
  const registry = createDefaultPrimitiveRegistry({ verificationAuthority });
  const baseDefinitions = registry.list();
  assert.equal(baseDefinitions.length, 18);
  assert.ok(baseDefinitions.every((definition) => /^sha256:[0-9a-f]{64}$/.test(definition.sourceDigest || '')));

  const composed = composePrimitives(registry, {
    projectId: PROJECT,
    projectVersionId: VERSION_1,
    projectType: 'web_application',
    runtimeCapabilities: RUNTIME_CAPABILITIES,
    primitives: selections(baseDefinitions),
  });
  assert.equal(composed.ok, true, composed.errors.join('\n'));
  assert.equal(composed.manifest.primitives.length, 18);
  assert.match(composed.manifest.manifestDigest, /^sha256:[0-9a-f]{64}$/);
  assert.equal(validateEventCompatibility(baseDefinitions).ok, true);

  const mutable = composePrimitives(registry, {
    projectId: PROJECT,
    projectVersionId: VERSION_1,
    projectType: 'web_application',
    runtimeCapabilities: RUNTIME_CAPABILITIES,
    primitives: [{ name: 'pandora-auth', version: 'latest', configuration: {} }],
  });
  assert.equal(mutable.ok, false);
  assert.match(mutable.errors.join('\n'), /may not use latest/);

  const authV1 = registry.getExact('pandora-auth', '1.0.0');
  const { definitionDigest: _oldDigest, ...authDefinition } = authV1;
  registry.register({
    ...authDefinition,
    version: '1.1.0',
    trustState: 'EXPERIMENTAL',
    sourceDigest: digest({ primitive: 'pandora-auth', version: '1.1.0', source: 'immutable-fixture' }),
  });

  const authV11Candidate = registry.getExact('pandora-auth', '1.1.0');
  const authV11Run = workerEPass(authV11Candidate);
  sealedWorkerERuns.set(authV11Run.verification_run_id, authV11Run);
  const authV11TrustDecision = buildPrimitiveVerificationDecision({ definition: authV11Candidate, run: authV11Run });
  const authV11Trusted = registry.applyVerificationDecision('pandora-auth', '1.1.0', authV11TrustDecision);
  assert.equal(authV11Trusted.trustState, 'TRUSTED');

  const migrationDigest = digest({ migration: 'pandora-auth-1.0.0-to-1.1.0' });
  const upgrade = planPrimitiveUpgrades(registry, {
    currentManifest: composed.manifest,
    targets: [{ name: 'pandora-auth', version: '1.1.0' }],
    migrations: [{
      name: 'pandora-auth',
      id: 'auth_1_0_0_to_1_1_0',
      fromVersion: '1.0.0',
      toVersion: '1.1.0',
      digest: migrationDigest,
      reversible: true,
      rollback: 'auth_1_1_0_to_1_0_0',
    }],
    now: '2026-08-29T02:56:00Z',
  });
  assert.equal(upgrade.ok, true, upgrade.errors.join('\n'));
  assert.equal(upgrade.plan.decision, 'AUTO');

  const upgraded = composePrimitives(registry, {
    projectId: PROJECT,
    projectVersionId: VERSION_2,
    projectType: 'web_application',
    runtimeCapabilities: RUNTIME_CAPABILITIES,
    primitives: selections(baseDefinitions, { 'pandora-auth': '1.1.0' }),
  });
  assert.equal(upgraded.ok, true, upgraded.errors.join('\n'));
  assert.equal(upgraded.manifest.primitives.length, 18);

  const sourceFiles = upgraded.manifest.primitives.map((primitive) => ({
    path: `generated/${primitive.name}.js`,
    primitive: primitive.name,
    contentDigest: digest({ name: primitive.name, version: primitive.version }),
    ownership: 'primitive-core',
  }));
  const customerDigest = digest({ customer: 'branding-extension-v1' });
  const materialization = planPrimitiveMaterialization({
    manifest: upgraded.manifest,
    sourceFiles,
    currentFiles: [{
      path: 'src/customer/branding.js',
      primitive: 'pandora-settings',
      contentDigest: customerDigest,
      ownership: 'customer-owned',
    }],
    migrationPlan: upgrade.plan,
  });
  assert.equal(materialization.decision, 'READY');
  const preserved = materialization.actions.find((action) => action.path === 'src/customer/branding.js');
  assert.equal(preserved.type, 'PRESERVE');
  assert.equal(preserved.contentDigest, customerDigest);
  assert.throws(
    () => buildWorkerDMaterializationRequest({
      manifest: upgraded.manifest,
      materializationPlan: { ...materialization, decision: 'MANUAL_REVIEW' },
      runtimeBindings: {},
    }),
    /READY approval state/,
  );

  const execution = planExecutionBoundaries([
    { id: 'persist-runtime', provider: 'postgres', transactional: true },
   { id: 'authorize-payment', provider: 'payments', transactional: false, compensation: 'void-payment' },
    { id: 'publish-runtime', provider: 'vercel', transactional: false, compensation: 'rollback-deployment' },
  ]);
  assert.equal(execution.ok, true, execution.errors.join('\n'));
  assert.equal(execution.requiresSaga, true);

  const workerD = buildWorkerDMaterializationRequest({
    manifest: upgraded.manifest,
    materializationPlan: materialization,
    runtimeBindings: {
      database: { resourceRef: 'runtime-db-preview' },
      storage: { resourceRef: 'runtime-storage-preview' },
      payments: { resourceRef: 'runtime-payments-preview' },
    },
  });
  assert.equal(workerD.projectVersionId, VERSION_2);
  assert.match(workerD.requestDigest, /^sha256:[0-9a-f]{64}$/);

  const authV11 = registry.getExact('pandora-auth', '1.1.0');
  const workerEDecision = buildPrimitiveVerificationDecision({ definition: authV11, run: authV11Run });
  assert.equal(workerEDecision.authority, 'worker-e');
  assert.equal(workerEDecision.status, 'PASS');

  const adversarial = scanPrimitiveAdversarialFixtures([
    { path: 'bad.sql', content: 'ALTER TABLE tenant_data DISABLE ROW LEVEL SECURITY; GRANT UPDATE ON tenant_data TO authenticated;' },
  ], { upgrade: { decision: 'AUTO', irreversible: true, majorChange: true, migrationDigest: 'main-branch' } });
  assert.equal(adversarial.ok, false);
  assert.ok(adversarial.findings.some((finding) => finding.code === 'RLS_DISABLED'));
  assert.ok(adversarial.findings.some((finding) => finding.code === 'UNSAFE_AUTO_UPGRADE'));
  assert.ok(adversarial.findings.some((finding) => finding.code === 'MUTABLE_MIGRATION_IDENTITY'));

  const lineage = projectVersionPrimitiveLineage({
    composition: upgraded.manifest,
    verificationEvidenceByPrimitive: { 'pandora-auth': workerEDecision.evidenceId },
  });
  assert.equal(lineage.primitiveCount, 18);
  assert.equal(lineage.primitives.find((row) => row.primitiveName === 'pandora-auth').verificationEvidenceId, workerEDecision.evidenceId);

  const upgradeLineage = primitiveUpgradeLineage({
    plan: upgrade.plan,
    outcomes: {
      'pandora-auth': {
        outcome: 'VERIFIED',
        migrationSetDigest: migrationDigest,
        rollbackPlanDigest: digest({ rollback: 'pandora-auth-1.1.0-to-1.0.0' }),
        forwardFixDigest: digest({ forwardFix: 'pandora-auth-1.1.1' }),
        verificationEvidenceId: workerEDecision.evidenceId,
      },
    },
  });
  assert.equal(upgradeLineage.length, 1);
  assert.match(upgradeLineage[0].rollbackPlanDigest, /^sha256:/);
  assert.match(upgradeLineage[0].forwardFixDigest, /^sha256:/);

  const artifactDigest = upgraded.manifest.manifestDigest.slice('sha256:'.length);
  const preview = normalizeDeploymentRequest({
    organizationId: ORG,
    projectId: PROJECT,
    projectVersionId: VERSION_2,
    artifactDigest,
    sourceCommit: SOURCE_COMMIT,
    environment: 'preview',
    authorizationRef: 'policy:preview-authorized',
    verificationRef: workerEDecision.evidenceId,
    provider: 'vercel',
    runtimeType: 'web_app',
  });
  assert.equal(assertExactLineage(preview, { projectVersionId: VERSION_2, artifactDigest, sourceCommit: SOURCE_COMMIT }), true);

  const production = normalizeDeploymentRequest({
    organizationId: ORG,
    projectId: PROJECT,
    projectVersionId: VERSION_2,
    artifactDigest,
    sourceCommit: SOURCE_COMMIT,
    environment: 'production',
    authorizationRef: 'policy:publish-authorized',
    verificationRef: workerEDecision.evidenceId,
    provider: 'vercel',
    runtimeType: 'web_app',
    expectedProductionVersionId: VERSION_1,
  });
  assert.equal(assertExactLineage(production, { projectVersionId: VERSION_2, artifactDigest, sourceCommit: SOURCE_COMMIT }), true);

  const economics = createPrimitiveEconomicsFacts({
    project: { id: PROJECT, versionId: VERSION_2, environment: 'preview' },
    composition: upgraded.manifest,
    actual: {
      reusedPrimitives: upgraded.manifest.primitives.map((primitive) => primitive.name),
      repairCount: 1,
      repairDurationMs: 250,
      buildTimeMs: 500,
      modelTokens: 200,
      costMicros: 1_000,
    },
    baseline: { buildTimeMs: 1_500, modelTokens: 700, costMicros: 4_000 },
    verification: { status: 'PASS' },
    upgrade: { decision: upgrade.plan.decision, burdenMs: 150, primitiveCount: 1 },
  });
  assert.equal(economics.primitiveCount, 18);
  assert.equal(economics.reusedCount, 18);
  assert.ok(economics.facts.some((fact) => fact.kind === 'primitive.savings'));
  assert.match(economics.summaryDigest, /^sha256:[0-9a-f]{64}$/);
});
