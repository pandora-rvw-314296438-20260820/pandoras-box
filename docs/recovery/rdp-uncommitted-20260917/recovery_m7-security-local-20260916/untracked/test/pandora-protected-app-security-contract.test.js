import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const machinePath = new URL('../docs/security/pandora-protected-app-security-v1.json', import.meta.url);
const documentPath = new URL('../docs/security/PANDORA_PROTECTED_APP_SECURITY_V1.md', import.meta.url);
const [machineRaw, document] = await Promise.all([
  readFile(machinePath, 'utf8'),
  readFile(documentPath, 'utf8')
]);
const contract = JSON.parse(machineRaw);

test('M7 contract freezes the trusted production-device baseline', () => {
  assert.equal(contract.schemaVersion, 'pandora-protected-app-security-v1');
  assert.equal(contract.productionBaseline.stockFirmware, true);
  assert.equal(contract.productionBaseline.lockedBootloader, true);
  assert.equal(contract.productionBaseline.rootAllowed, false);
  assert.equal(contract.productionBaseline.customRomAllowed, false);
  assert.equal(contract.productionBaseline.verifiedBootTrusted, true);
  assert.equal(contract.productionBaseline.preserveSimTelephony, true);
  assert.equal(contract.productionBaseline.preserveImsDependencies, true);
  assert.equal(contract.productionBaseline.physicalVerificationRequired, true);
});
test('protected classes, handoffs and permanent denials are explicit', () => {
  for (const name of ['financial', 'authenticator', 'password_manager']) {
    assert.ok(contract.protectedClasses.includes(name), name);
  }
  for (const operation of ['launch', 'open_supported_deep_link']) {
    assert.ok(contract.allowedHandoffs.includes(operation), operation);
  }
  for (const operation of [
    'otp_read', 'otp_bypass', 'biometric_bypass',
    'device_integrity_bypass', 'silent_financial_transfer'
  ]) {
    assert.ok(contract.forbidden.includes(operation), operation);
  }
  assert.match(document, /Unknown protected-app operations fail closed/i);
});

test('standing authority requires both scope and bounds verification', () => {
  assert.deepEqual(contract.standingAuthorityRequires, ['scope_match', 'bounds_verified']);
  assert.match(document, /scope \*\*and bounds are both verified\*\*/i);
});

test('financial tiers preserve handoff, money movement and forbidden bypass', () => {
  assert.equal(contract.financialRiskTiers.F1, 'protected_app_handoff');
  assert.equal(contract.financialRiskTiers.F3, 'money_movement_or_purchase');
  assert.equal(contract.financialRiskTiers.F4, 'security_bypass_forbidden');
  assert.match(document, /Authority never overrides F4/i);
});
test('destructive provisioning requires complete recovery and rollback proof', () => {
  for (const gate of [
    'authenticator_recovery_verified', 'password_manager_recovery_verified',
    'protected_app_recovery_verified', 'backup_export_verified',
    'sim_esim_recovery_verified', 'known_good_rollback_available',
    'explicit_destructive_authority'
  ]) {
    assert.ok(contract.destructiveProvisioningRequires.includes(gate), gate);
  }
  assert.match(document, /current lane performs no reset/i);
});

test('audit contract requires attribution, redaction and verification evidence', () => {
  for (const field of [
    'actor', 'authority_basis', 'job_action_identity', 'redacted_input_scope',
    'idempotency_key_hash', 'outcome', 'verification_state', 'provider_readback',
    'evidence_ids', 'timestamps'
  ]) assert.ok(contract.auditRequiredFields.includes(field), field);
  assert.match(document, /Raw idempotency keys are never stored/i);
});

test('physical acceptance cannot be substituted with CI or emulator evidence', () => {
  assert.match(contract.acceptanceBoundary, /final exact-source physical APK run/i);
  assert.match(document, /Do not mark the following PASS from unit tests, CI, emulator/i);
  assert.match(document, /Any protected-app or core-telephony regression blocks release/i);
});
test('M7-006 remains downstream of M4-001 instead of colliding with Android workers', () => {
  assert.match(document, /M7-006 least-privilege runtime permission brokerage remains downstream of M4-001/i);
  assert.match(document, /does not modify Android permission-broker or communications files/i);
});
