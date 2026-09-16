import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const machinePath = new URL('../docs/architecture/pandora-standing-authority-policy-v1.json', import.meta.url);
const documentPath = new URL('../docs/architecture/PANDORA_STANDING_AUTHORITY_POLICY_V1.md', import.meta.url);

const [machineRaw, document] = await Promise.all([
  readFile(machinePath, 'utf8'),
  readFile(documentPath, 'utf8'),
]);
const policy = JSON.parse(machineRaw);

const byId = new Map(policy.approvalMatrix.map((row) => [row.id, row]));

test('freezes autonomous-by-default without making all writes approval-gated', () => {
  assert.equal(policy.schemaVersion, 'pandora-standing-authority-policy-v1');
  assert.equal(policy.status, 'frozen');
  assert.equal(policy.principles.autonomousInsideAuthority, true);
  assert.equal(policy.principles.approvalOnlyWhenConsequentialAndNotAlreadyAuthorized, true);
  assert.equal(policy.principles.writeDoesNotAutomaticallyMeanConsequential, true);
  assert.match(document, /A write is \*\*not automatically consequential\*\*/);
});

test('only explicit current instruction or explicit standing policy can grant authority', () => {
  assert.deepEqual(policy.authoritySources.grantingOrder, [
    'explicit_current_user_instruction',
    'active_explicit_standing_policy',
  ]);
  for (const source of ['model_proposal', 'memory_pattern', 'prediction', 'recommendation', 'prior_success']) {
    assert.ok(policy.authoritySources.nonGranting.includes(source));
  }
  assert.equal(policy.principles.predictionNeverGrantsAuthority, true);
  assert.match(document, /they never create or expand permission/i);
});

test('routine work proceeds without unnecessary Needs You interruptions', () => {
  for (const id of ['routine_read', 'model_call', 'test_or_dry_run', 'local_reversible_change_current_request']) {
    assert.equal(byId.get(id)?.expectedDecision, 'auto_execute', id);
  }
  for (const reason of [
    'routine_read_or_search',
    'model_call_or_model_selection',
    'test_build_or_dry_run',
    'waiting_for_ci_or_cloud_work',
    'bounded_retry_inside_authority',
  ]) {
    assert.ok(policy.needsYou.notReasons.includes(reason), reason);
  }
});

test('explicit current instruction does not require a second approval prompt', () => {
  assert.equal(byId.get('bounded_provider_write_current_request')?.expectedDecision, 'auto_execute');
  assert.equal(byId.get('production_publish_explicit_request')?.expectedDecision, 'auto_execute');
  assert.match(document, /If the user's current instruction clearly authorizes the exact action, that is already authorization/i);
});

test('standing policy authorizes only when every applicable scope binding matches', () => {
  assert.equal(policy.standingPolicyContract.allApplicableBindingsMustMatch, true);
  assert.equal(policy.standingPolicyContract.ambiguousScopeFailsClosedToNeedsApproval, true);
  assert.equal(byId.get('bounded_provider_write_standing_policy')?.expectedDecision, 'standing_authorized');
  assert.equal(byId.get('external_message_standing_policy_scope_match')?.expectedDecision, 'standing_authorized');
  assert.equal(byId.get('external_message_standing_policy_scope_mismatch')?.expectedDecision, 'needs_approval');
});

test('production and financial effects stop only when authority is missing', () => {
  assert.equal(byId.get('production_publish_no_authority')?.expectedDecision, 'needs_approval');
  assert.equal(byId.get('financial_transfer_without_authority')?.expectedDecision, 'needs_approval');
  assert.equal(byId.get('financial_transfer_specific_standing_policy')?.expectedDecision, 'standing_authorized');
  assert.equal(policy.protectedAndFinancial.financialAndSecurityCriticalActionsRequireExplicitCurrentOrStandingAuthority, true);
});

test('prediction, stale policy and prior success never become permission', () => {
  assert.equal(byId.get('prediction_is_not_permission')?.expectedDecision, 'needs_approval');
  assert.equal(byId.get('expired_policy_is_not_permission')?.expectedDecision, 'needs_approval');
  assert.equal(policy.learningBoundary.learnedInferenceCannotCreateOrExpandStandingPolicy, true);
  assert.equal(policy.learningBoundary.proposedAutomationRequiresExplicitAuthorizationBeforeBecomingPolicy, true);
});

test('credential, OTP and protected-app security bypass are denied even when requested', () => {
  assert.equal(byId.get('credential_or_otp_bypass')?.expectedDecision, 'deny');
  assert.equal(byId.get('protected_app_security_bypass')?.expectedDecision, 'deny');
  assert.equal(policy.protectedAndFinancial.credentialOrOtpBypassAlwaysDenied, true);
  assert.equal(policy.protectedAndFinancial.protectedAppSecurityBypassAlwaysDenied, true);
});

test('fallback stays within the original authority boundary', () => {
  assert.equal(policy.principles.fallbackNeverExpandsAuthority, true);
  assert.equal(policy.fallbackAndRetry.modelProviderFallbackMayBeAutomaticInsideSameAuthorityScope, true);
  assert.equal(policy.fallbackAndRetry.directProviderFallbackUsesSameAuthorityPolicy, true);
  assert.equal(policy.fallbackAndRetry.fallbackMayNotIncreaseCostPrivacyOrSideEffectScopeBeyondAuthority, true);
});

test('consequential retries are idempotent and ambiguous writes require readback', () => {
  assert.equal(policy.standingPolicyContract.consequentialSideEffectsRequireIdempotency, true);
  assert.equal(policy.fallbackAndRetry.consequentialRetryReusesIdempotencyIdentity, true);
  assert.equal(policy.fallbackAndRetry.ambiguousEffectRequiresProviderReadbackBeforeRetry, true);
  assert.match(document, /read back provider state before retrying/i);
});

test('authorization remains separate from verified completion', () => {
  assert.equal(policy.principles.authorizationDoesNotImplySuccess, true);
  assert.equal(policy.principles.verifiedOutcomeStillRequired, true);
  assert.equal(policy.standingPolicyContract.postActionVerificationRequired, true);
  assert.match(document, /Authorization does not imply success/i);
});

test('Needs You remains a user-boundary signal rather than a generic pause', () => {
  assert.equal(policy.principles.needsYouOnlyForRealUserBoundary, true);
  assert.equal(policy.needsYou.notEquivalentToVoluntaryPause, true);
  assert.ok(policy.needsYou.allowedReasons.includes('authorization_required'));
  assert.ok(policy.needsYou.allowedReasons.includes('account_connection_or_reauthentication_required'));
  assert.match(document, /Needs You is not the same as a voluntary Pause\/Resume control/i);
});

test('downstream M3/M7 own enforcement rather than M0-003 stealing implementation scope', () => {
  for (const key of ['M3-005', 'M7-001', 'M7-003', 'M7-004']) {
    assert.equal(typeof policy.handoffs[key], 'string');
    assert.ok(policy.handoffs[key].length > 0);
  }
  assert.match(document, /This is a policy contract, not the downstream enforcement implementation/i);
  assert.match(document, /No production policy-engine, protected-app, APK, provider, or deployment mutation is claimed/i);
});
