'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createDefaultPrimitiveRegistry } = require('../packages/primitives/src');
const { buildPrimitiveVerificationDecision, createPrimitiveVerificationAuthority } = require('../packages/pandora-verification/src/primitive-trust');

function passRun(definition) {
  return Object.freeze({
    verification_run_id: 'worker-e-run-auth-1',
    status: 'PASS',
    identity_digest: 'sha256:' + 'b'.repeat(64),
    completed_at: '2026-08-29T02:55:00Z',
    request: Object.freeze({ source_digest: definition.sourceDigest }),
    required_checks: Object.freeze(['security.auth', 'database.policy']),
    results: Object.freeze([
      Object.freeze({ check_id: 'security.auth', status: 'PASS', authoritative_issuer: 'pandora-verification-engine', evidence_refs: Object.freeze(['ev-auth']) }),
      Object.freeze({ check_id: 'database.policy', status: 'PASS', authoritative_issuer: 'pandora-verification-engine', evidence_refs: Object.freeze(['ev-db']) }),
    ]),
  });
}

test('default primitive registry cannot promote a caller-forged Worker E-looking PASS', () => {
  const registry = createDefaultPrimitiveRegistry();
  const definition = registry.getExact('pandora-auth', '1.0.0');
  const { definitionDigest: _definitionDigest, ...directTrusted } = definition;
  assert.throws(
    () => registry.register({ ...directTrusted, version: '1.0.1', trustState: 'TRUSTED' }),
    /direct TRUSTED registration is forbidden/,
  );
  const decision = buildPrimitiveVerificationDecision({ definition: definition, run: passRun(definition) });
  assert.throws(
    () => registry.applyVerificationDecision(definition.name, definition.version, decision),
    /configured Worker E verification authority/,
  );
  assert.equal(registry.getExact(definition.name, definition.version).trustState, 'EXPERIMENTAL');
});

test('configured Worker E authority re-reads exact evidence identity before TRUSTED promotion', () => {
  const seedRegistry = createDefaultPrimitiveRegistry();
  const definition = seedRegistry.getExact('pandora-auth', '1.0.0');
  const run = passRun(definition);
  const authority = createPrimitiveVerificationAuthority({
    readVerificationRun: (evidenceId) => evidenceId === run.verification_run_id ? run : null,
  });
  const registry = createDefaultPrimitiveRegistry({ verificationAuthority: authority });
  const decision = buildPrimitiveVerificationDecision({ definition: registry.getExact(definition.name, definition.version), run });
  const promoted = registry.applyVerificationDecision(definition.name, definition.version, decision);
  assert.equal(promoted.trustState, 'TRUSTED');

  const another = createDefaultPrimitiveRegistry({ verificationAuthority: authority });
  assert.throws(
    () => another.applyVerificationDecision(definition.name, definition.version, { ...decision, evidenceId: 'forged-run-id' }),
    /rejected primitive trust decision/,
  );
  assert.equal(another.getExact(definition.name, definition.version).trustState, 'EXPERIMENTAL');
});
