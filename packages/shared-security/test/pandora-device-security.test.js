const assert = require('node:assert/strict');
const test = require('node:test');

const security = require('../dist/index.js');

test('M7-001 permanently denies protected-app security bypasses', () => {
  for (const operation of [
    'credential_extract', 'credential_scrape', 'otp_read', 'otp_bypass',
    'authenticator_secret_export', 'biometric_bypass', 'device_integrity_bypass',
    'protected_screen_scrape', 'silent_financial_transfer'
  ]) {
    const result = security.evaluateProtectedAppAction({
      appClass: 'financial', operation,
      authorityBasis: 'explicit_current_user_instruction',
      userPresenceVerified: true
    });
    assert.equal(result.decision, 'deny', operation);
    assert.equal(result.reasonCode, 'protected_app_security_bypass_forbidden');
  }
});

test('M7-001 safe handoffs are allowed but unknown operations fail closed', () => {
  assert.equal(security.evaluateProtectedAppAction({
    appClass: 'financial', operation: 'launch'
  }).decision, 'allow_handoff');
  const unknown = security.evaluateProtectedAppAction({
    appClass: 'financial', operation: 'do_something_new'
  });
  assert.equal(unknown.decision, 'deny');
  assert.equal(unknown.reasonCode, 'unsupported_protected_operation');
});

test('M7-004 standing authority must match scope and verified bounds', () => {
  const base = {
    appClass: 'financial', operation: 'financial_transfer',
    authorityBasis: 'active_explicit_standing_policy',
    userPresenceVerified: true
  };
  assert.equal(security.evaluateProtectedAppAction({
    ...base, standingPolicyMatches: true, standingPolicyBoundsVerified: false
  }).decision, 'needs_approval');
  assert.equal(security.evaluateProtectedAppAction({
    ...base, standingPolicyMatches: true, standingPolicyBoundsVerified: true
  }).decision, 'allow');
});

test('M7-004 sensitive protected actions require user presence', () => {
  const result = security.evaluateProtectedAppAction({
    appClass: 'financial', operation: 'purchase',
    authorityBasis: 'explicit_current_user_instruction', userPresenceVerified: false
  });
  assert.equal(result.decision, 'needs_user_presence');
});
test('M7-001 supported protected APIs require provider controls and post-verification', () => {
  const base = {
    appClass: 'financial', operation: 'supported_api_action',
    authorityBasis: 'explicit_current_user_instruction'
  };
  assert.equal(security.evaluateProtectedAppAction({
    ...base, providerControlsVerified: false, postVerificationPlanned: true
  }).reasonCode, 'protected_app_provider_controls_not_verified');
  assert.equal(security.evaluateProtectedAppAction({
    ...base, providerControlsVerified: true, postVerificationPlanned: false
  }).reasonCode, 'protected_app_post_verification_required');
  assert.equal(security.evaluateProtectedAppAction({
    ...base, providerControlsVerified: true, postVerificationPlanned: true
  }).decision, 'allow');
});

test('M7-002 integrity baseline distinguishes violation, unknown, and verified state', () => {
  const verified = {
    stockFirmware: true, bootloaderLocked: true, rooted: false, customRom: false,
    verifiedBootTrusted: true, googleSystemServicesPreserved: true,
    biometricsPreserved: true, simTelephonyPreserved: true,
    imsDependenciesPreserved: true, physicalEvidenceVerified: true
  };
  assert.equal(security.evaluateDeviceIntegrityBaseline(verified).status, 'meets_policy_baseline');
  assert.equal(security.evaluateDeviceIntegrityBaseline({ ...verified, rooted: true }).status, 'blocked');
  const unknown = { ...verified };
  delete unknown.verifiedBootTrusted;
  unknown.physicalEvidenceVerified = false;
  const unknownResult = security.evaluateDeviceIntegrityBaseline(unknown);
  assert.equal(unknownResult.status, 'needs_physical_verification');
  assert.ok(unknownResult.unknown.includes('verifiedBootTrusted'));
});

test('M7-004 financial risk tiers remain explicit', () => {
  assert.equal(security.classifyFinancialAction('launch'), 'F1');
  assert.equal(security.classifyFinancialAction('add_or_change_payee'), 'F2');
  assert.equal(security.classifyFinancialAction('financial_transfer'), 'F3');
  assert.equal(security.classifyFinancialAction('otp_bypass'), 'F4');
});

test('M7-005 destructive provisioning requires every recovery and rollback gate', () => {
  const complete = {
    authenticatorRecoveryVerified: true,
    passwordManagerRecoveryVerified: true,
    protectedAppRecoveryVerified: true,
    backupExportVerified: true,
    simEsimRecoveryVerified: true,
    knownGoodRollbackAvailable: true,
    userExplicitlyAuthorizedDestructiveAction: true
  };
  assert.equal(security.canStartDestructiveProvisioning(complete).allowed, true);
  assert.equal(security.canStartDestructiveProvisioning({ ...complete, backupExportVerified: false }).allowed, false);
});
test('M7-007 audit records are attributable without leaking secrets or personal payloads', () => {
  const record = security.buildConsequentialActionAuditRecord({
    actionId: 'act-1', jobId: 'job-1', actor: 'owner',
    authorityBasis: 'explicit_current_user_instruction',
    authorityPolicyId: 'policy-1', authorityPolicyFingerprint: 'raw-policy-fingerprint',
    capability: 'protected_app', operation: 'financial_transfer',
    actionClass: 'financial', protectedAppClass: 'financial',
    inputScope: { apiKey: 'secret-key', otp: '123456', email: 'owner@example.com', amount: 100 },
    idempotencyKey: 'idem-secret-value', outcome: 'completed',
    verificationState: 'provider_readback_verified',
    providerReadback: { token: 'provider-secret', status: 'confirmed' },
    evidenceIds: ['evidence-1'], recordedAt: '2026-09-14T09:30:00.000Z'
  });
  const serialized = JSON.stringify(record);
  assert.equal(record.schemaVersion, 'pandora-consequential-device-action-audit-v1');
  assert.equal(record.redactedInputScope.apiKey, '[REDACTED_SECRET]');
  assert.equal(record.redactedInputScope.otp, '[REDACTED_SECRET]');
  assert.equal(record.redactedInputScope.email, '[REDACTED_PERSONAL]');
  assert.notEqual(record.idempotencyKeyHash, 'idem-secret-value');
  assert.ok(!serialized.includes('secret-key'));
  assert.ok(!serialized.includes('123456'));
  assert.ok(!serialized.includes('provider-secret'));
  assert.ok(!serialized.includes('owner@example.com'));
});

test('package root declarations expose every M7 security API', () => {
  const { readFileSync } = require('node:fs');
  const { join } = require('node:path');
  const declarations = readFileSync(join(__dirname, '../dist/index.d.ts'), 'utf8');
  const exported = declarations.match(/export \{([^}]+)\};/)?.[1]
    .split(',').map((name) => name.trim()) ?? [];
  for (const symbol of [
    'PROTECTED_APP_CLASSES', 'FINANCIAL_RISK_TIERS', 'classifyFinancialAction',
    'evaluateProtectedAppAction', 'evaluateDeviceIntegrityBaseline',
    'canStartDestructiveProvisioning', 'buildConsequentialActionAuditRecord'
  ]) {
    assert.ok(exported.includes(symbol), symbol);
  }
});
