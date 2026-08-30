'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  createDefaultPrimitiveRegistry,
  inferPrimitiveRequirements,
  resolvePrimitiveRequirements,
  resolveProjectSpecPrimitives,
} = require('../packages/primitives/src');
const {
  AUTHORITATIVE_ISSUER,
  buildPrimitiveVerificationDecision,
  createPrimitiveVerificationAuthority,
} = require('../packages/pandora-verification/src/primitive-trust');

function workerEPass(definition, evidenceId) {
  return Object.freeze({
    verification_run_id: evidenceId,
    status: 'PASS',
    identity_digest: `identity:${definition.name}:${definition.version}`,
    completed_at: '2026-08-31T04:40:00+08:00',
    request: Object.freeze({ source_digest: definition.sourceDigest }),
    required_checks: Object.freeze(['primitive.contract', 'primitive.security']),
    results: Object.freeze([
      Object.freeze({ check_id: 'primitive.contract', status: 'PASS', authoritative_issuer: AUTHORITATIVE_ISSUER, evidence_refs: Object.freeze([`${evidenceId}:contract`]) }),
      Object.freeze({ check_id: 'primitive.security', status: 'PASS', authoritative_issuer: AUTHORITATIVE_ISSUER, evidence_refs: Object.freeze([`${evidenceId}:security`]) }),
    ]),
  });
}

function trust(registry, sealedRuns, name) {
  const definition = registry.getExact(name, '1.0.0');
  const run = workerEPass(definition, `worker-e-${name}-selection-proof`);
  sealedRuns.set(run.verification_run_id, run);
  registry.applyVerificationDecision(name, '1.0.0', buildPrimitiveVerificationDecision({ definition, run }));
}

test('Worker I infers exact primitive requirements from ProjectSpec owner requirements', () => {
  const requirements = inferPrimitiveRequirements({
    product: {
      projectType: 'web_application',
      roles: ['owner', 'staff'],
      features: ['Admin operations console', 'Restaurant booking and availability', 'Checkout and order management'],
    },
    integrations: {
      payment: ['card payment'],
      messaging: ['email notifications'],
      analytics: ['business event tracking'],
    },
  });
  for (const expected of ['pandora-auth','pandora-rbac','pandora-admin','pandora-booking','pandora-commerce','pandora-billing','pandora-notifications','pandora-analytics']) {
    assert.ok(requirements.includes(expected), `${expected} should be required`);
  }
});

test('Worker I resolves immutable experimental identities for non-production planning and expands required dependencies', () => {
  const registry = createDefaultPrimitiveRegistry();
  const result = resolveProjectSpecPrimitives(registry, {
    projectSpec: {
      product: { projectType: 'web_application', roles: ['owner'], features: ['Admin operations console'] },
      integrations: {},
    },
    requireTrusted: false,
  });
  assert.equal(result.ok, true, result.errors.join('\n'));
  assert.equal(result.state, 'READY');
  assert.ok(result.selections.some((item) => item.name === 'pandora-auth'));
  assert.ok(result.selections.some((item) => item.name === 'pandora-rbac'));
  assert.ok(result.selections.some((item) => item.name === 'pandora-admin'));
  assert.ok(result.selections.some((item) => item.name === 'pandora-audit'));
  assert.ok(result.selections.every((item) => item.version === '1.0.0'));
  assert.ok(result.selections.every((item) => /^sha256:[0-9a-f]{64}$/.test(item.sourceDigest)));
  assert.ok(result.selections.every((item) => /^sha256:[0-9a-f]{64}$/.test(item.definitionDigest)));
  assert.match(result.selectionDigest, /^sha256:[0-9a-f]{64}$/);
});

test('Worker I trusted-only selection fails closed until exact Worker E primitive evidence exists', () => {
  const registry = createDefaultPrimitiveRegistry();
  const blocked = resolvePrimitiveRequirements(registry, {
    requiredPrimitives: ['pandora-auth', 'pandora-rbac'],
    projectType: 'web_application',
    requireTrusted: true,
  });
  assert.equal(blocked.ok, false);
  assert.equal(blocked.state, 'BLOCKED');
  assert.equal(blocked.selections.length, 0);
  assert.match(blocked.errors.join('\n'), /no TRUSTED primitive/);
});

test('Worker I accepts trusted exact versions only after authoritative Worker E evidence is re-read', () => {
  const sealedRuns = new Map();
  const authority = createPrimitiveVerificationAuthority({ readVerificationRun: (id) => sealedRuns.get(id) || null });
  const registry = createDefaultPrimitiveRegistry({ verificationAuthority: authority });
  trust(registry, sealedRuns, 'pandora-auth');
  trust(registry, sealedRuns, 'pandora-rbac');

  const result = resolveProjectSpecPrimitives(registry, {
    projectSpec: { product: { projectType: 'web_application', roles: ['owner', 'staff'] }, integrations: {} },
    requireTrusted: true,
  });
  assert.equal(result.ok, true, result.errors.join('\n'));
  assert.deepEqual(result.selections.map((item) => item.name), ['pandora-auth', 'pandora-rbac']);
  assert.ok(result.selections.every((item) => item.trustState === 'TRUSTED'));
  assert.ok(result.selections.every((item) => item.verificationEvidenceId && item.verificationEvidenceId.startsWith('worker-e-')));
});

test('Worker I rejects mutable or malformed primitive requirement identities', () => {
  const registry = createDefaultPrimitiveRegistry();
  assert.throws(() => resolvePrimitiveRequirements(registry, { requiredPrimitives: ['latest'] }), /invalid primitive name/);
  assert.throws(() => resolvePrimitiveRequirements(registry, { requiredPrimitives: ['pandora-auth@latest'] }), /invalid primitive name/);
});
