import test from 'node:test';
import assert from 'node:assert/strict';
import { conservativeImpactPlan, isIncrementalSourceEligible, selectVerificationDefinitions, validateImpactPlan } from '../src/impact/change-impact.mjs';

const visual = Object.freeze({ authoritative: true, assessmentId: 'impact-1', impactTier: 0, impactClass: 'visual', buildScope: 'visual_incremental', verificationScope: 'visual_plus_global', changedScopes: { brand: true } });
const component = Object.freeze({ authoritative: true, assessmentId: 'impact-2', impactTier: 1, impactClass: 'component', buildScope: 'component_incremental', verificationScope: 'component_plus_global', changedScopes: { component: true } });

test('malformed or untrusted impact plans fail closed to the highest-risk full candidate', () => {
  for (const value of [null, {}, { ...visual, authoritative: false }, { ...visual, impactTier: 4 }, { ...visual, buildScope: 'full_candidate' }, { ...visual, verificationScope: 'database_plus_global' }]) {
    const plan = validateImpactPlan(value);
    assert.equal(plan.authoritative, false);
    assert.equal(plan.impactTier, 4);
    assert.equal(plan.buildScope, 'full_candidate');
    assert.equal(plan.verificationScope, 'database_plus_global');
  }
  assert.deepEqual(conservativeImpactPlan().changedScopes, { conservativeFallback: true });
});

test('authoritative low-impact plans can reuse an exact verified baseline', () => {
  assert.equal(isIncrementalSourceEligible(visual, { files: [{ path: 'index.html', content: 'x' }] }), true);
  assert.equal(isIncrementalSourceEligible(component, { files: [{ path: 'src/a.ts', content: 'x' }] }), true);
  assert.equal(isIncrementalSourceEligible({ ...component, impactTier: 2, impactClass: 'app_logic', buildScope: 'full_candidate', verificationScope: 'app_plus_global' }, { files: [{ path: 'src/a.ts', content: 'x' }] }), false);
  assert.equal(isIncrementalSourceEligible(visual, null), false);
});

test('verification scoping never removes mandatory checks', () => {
  const checks = [
    { category: 'unit', optional: false },
    { category: 'lint', optional: false },
    { category: 'unit', optional: true },
    { category: 'typecheck', optional: true },
    { category: 'integration', optional: true },
  ];
  assert.deepEqual(selectVerificationDefinitions(checks, visual).map((item) => `${item.category}:${item.optional}`), ['unit:false', 'lint:false', 'typecheck:true']);
  assert.deepEqual(selectVerificationDefinitions(checks, component).map((item) => `${item.category}:${item.optional}`), ['unit:false', 'lint:false', 'unit:true', 'typecheck:true']);
  assert.equal(selectVerificationDefinitions(checks, null).length, checks.length);
});
