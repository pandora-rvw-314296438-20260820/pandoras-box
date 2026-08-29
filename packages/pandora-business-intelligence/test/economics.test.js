'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  assertScope, budgetPolicySignal, grossMargin, modelEconomics, normalizeCostEntry,
  priceModelUsage, primitiveSavings, qualityPerDollar, roiAssessment,
  summarizeCostEntries, summarizeRepairSpend, totalCostToVerifiedResult,
} = require('../src/economics.js');

const SCOPE = { organizationId: 'org-1', projectId: 'project-1', projectVersionId: 'v1' };
function cost(overrides = {}) {
  return {
    organization_id: 'org-1', project_id: 'project-1', project_version_id: 'v1',
    cost_category: 'model', estimated_cost_micros: 0, billed_cost_micros: 100,
    charged_cost_micros: 0, credit_micros: 0, currency: 'USD', quantity: 1, unit: 'request',
    metadata_redacted: {}, ...overrides,
  };
}

test('normalizes actual billed cost', () => {
  const row = normalizeCostEntry(cost({ billed_cost_micros: 123 }));
  assert.equal(row.internalCostMicros, 123); assert.equal(row.confidence, 'actual');
});
test('normalizes estimated cost when billing is absent', () => {
  const row = normalizeCostEntry(cost({ billed_cost_micros: 0, estimated_cost_micros: 77 }));
  assert.equal(row.internalCostMicros, 77); assert.equal(row.confidence, 'estimated');
});
test('keeps unknown cost unknown instead of zero', () => {
  const row = normalizeCostEntry(cost({ billed_cost_micros: 0, estimated_cost_micros: 0 }));
  assert.equal(row.internalCostMicros, null); assert.equal(row.confidence, 'unknown');
});
test('rejects unsupported cost categories', () => {
  assert.throws(() => normalizeCostEntry(cost({ cost_category: 'made_up' })), /unsupported cost category/);
});
test('rejects cross-organization cost scope', () => {
  assert.throws(() => assertScope(normalizeCostEntry(cost()), { ...SCOPE, organizationId: 'other' }), /CROSS_ORG_ACCESS/);
});
test('rejects cross-project cost scope', () => {
  assert.throws(() => assertScope(normalizeCostEntry(cost()), { ...SCOPE, projectId: 'other' }), /CROSS_PROJECT_ACCESS/);
});
test('exact version costing rejects unattributed records', () => {
  assert.throws(() => summarizeCostEntries([cost({ project_version_id: null })], SCOPE), /UNATTRIBUTED_VERSION_COST/);
});
test('summarizes known internal cost, charges, and credits', () => {
  const result = summarizeCostEntries([
    cost({ billed_cost_micros: 100, charged_cost_micros: 300, credit_micros: 50 }),
    cost({ cost_category: 'verification', billed_cost_micros: 40 }),
  ], SCOPE);
  assert.equal(result.totalInternalCostMicros, 140); assert.equal(result.netCustomerChargeMicros, 250); assert.equal(result.confidence, 'actual');
});
test('summary does not fabricate total when any internal cost is unknown', () => {
  const result = summarizeCostEntries([cost(), cost({ cost_category: 'verification', billed_cost_micros: 0 })], SCOPE);
  assert.equal(result.totalInternalCostMicros, null); assert.equal(result.unknownCount, 1);
});
test('rejects mixed currencies in one scoped cost summary', () => {
  assert.throws(() => summarizeCostEntries([cost(), cost({ currency: 'PHP' })], SCOPE), /MIXED_CURRENCY_COSTS/);
});
test('computes total cost to verified result only when required categories are complete', () => {
  const result = totalCostToVerifiedResult([
    cost({ cost_category: 'model', billed_cost_micros: 100 }),
    cost({ cost_category: 'build_compute', billed_cost_micros: 200 }),
    cost({ cost_category: 'verification', billed_cost_micros: 50 }),
  ], SCOPE);
  assert.equal(result.complete, true); assert.equal(result.totalCostMicros, 350);
});
test('verified-result cost reports missing categories', () => {
  const result = totalCostToVerifiedResult([cost({ cost_category: 'model' })], SCOPE);
  assert.equal(result.complete, false); assert.deepEqual([...result.missingCategories].sort(), ['build_compute', 'verification']); assert.equal(result.totalCostMicros, null);
});
test('verified-result cost remains unknown when a required entry has unknown price', () => {
  const result = totalCostToVerifiedResult([
    cost({ cost_category: 'model', billed_cost_micros: 100 }),
    cost({ cost_category: 'build_compute', billed_cost_micros: 0, estimated_cost_micros: 0 }),
    cost({ cost_category: 'verification', billed_cost_micros: 50 }),
  ], SCOPE);
  assert.equal(result.complete, false); assert.equal(result.unknownRequiredEntries, 1);
});
test('repair spending includes retries and repair attempts', () => {
  const result = summarizeRepairSpend([
    cost({ billed_cost_micros: 10, metadata_redacted: { retry: true } }),
    cost({ billed_cost_micros: 20, metadata_redacted: { repair_attempt: true } }),
    cost({ billed_cost_micros: 99 }),
  ], SCOPE, { capMicros: 40 });
  assert.equal(result.attemptCount, 2); assert.equal(result.totalSpendMicros, 30); assert.equal(result.remainingMicros, 10);
});
test('budget signal matches Worker C exhausted contract', () => {
  const result = budgetPolicySignal({ organization_id: 'org-1', project_id: 'project-1', budget_kind: 'build', scope_key: 'b1', hard_limit_micros: 100, warning_limit_micros: 80, spent_micros: 100, reserved_micros: 0, status: 'exhausted', currency: 'USD' });
  assert.equal(result.exhausted, true); assert.equal(result.remaining_units, 0);
});
test('budget signal requests approval before warning or overage spend', () => {
  const result = budgetPolicySignal({ organization_id: 'org-1', project_id: 'project-1', budget_kind: 'build', scope_key: 'b1', hard_limit_micros: 100, warning_limit_micros: 80, spent_micros: 70, reserved_micros: 0, status: 'active', currency: 'USD' }, { requestedAdditionalMicros: 15 });
  assert.equal(result.exhausted, false); assert.equal(result.requires_approval_for_extra_spend, true); assert.equal(result.remaining_units, 30);
});
test('gross margin is computed only with complete revenue and cost inputs', () => {
  const complete = grossMargin({ customerChargeMicros: 1000, creditsMicros: 100, internalCostMicros: 400 });
  assert.equal(complete.marginMicros, 500); assert.equal(complete.complete, true);
  const incomplete = grossMargin({ customerChargeMicros: 1000, internalCostMicros: null });
  assert.equal(incomplete.marginMicros, null); assert.equal(incomplete.complete, false);
});
test('model usage pricing is versioned and accounts for cached input', () => {
  const result = priceModelUsage({ inputTokens: 1_000_000, cachedInputTokens: 500_000, outputTokens: 1_000_000, rates: { inputMicrosPerMillionTokens: 200, cachedInputMicrosPerMillionTokens: 50, outputMicrosPerMillionTokens: 600 }, pricingVersion: '2026-08-29', pricingSource: 'provider-rate-card' });
  assert.equal(result.estimatedCostMicros, 725); assert.equal(result.pricingVersion, '2026-08-29'); assert.equal(result.confidence, 'estimated');
});
test('quality-per-dollar excludes unknown-cost candidates from selection', () => {
  const result = qualityPerDollar([
    { id: 'a', qualityScore: 0.9, costMicros: 100, verified: true },
    { id: 'b', qualityScore: 1, costMicros: 200, verified: true },
    { id: 'c', qualityScore: 1, costMicros: null, verified: true },
  ]);
  assert.equal(result.recommendedId, 'a'); assert.equal(result.unknownCost.length, 1);
});
test('model economics reports cost per verified result without hiding unknown spend', () => {
  const rows = modelEconomics([
    { model: 'm1', verified: true, costMicros: 100, qualityScore: 0.9 },
    { model: 'm1', verified: false, costMicros: 50, qualityScore: 0.5 },
    { model: 'm2', verified: true, costMicros: null, qualityScore: 1 },
  ]);
  assert.equal(rows[0].costPerVerifiedResultMicros, 150); assert.equal(rows[1].totalCostMicros, null);
});
test('ROI and primitive savings remain explicitly non-causal with confidence labels', () => {
  const roi = roiAssessment({ benefitMicros: 2000, costMicros: 1000, benefitConfidence: 'estimated', costConfidence: 'actual', assumptions: ['benefit estimate'] });
  const savings = primitiveSavings({ baselineCostMicros: 1000, composedCostMicros: 700, baselineConfidence: 'estimated', composedConfidence: 'actual', evidence: ['same acceptance criteria'] });
  assert.equal(roi.roi, 1); assert.equal(roi.causal, false); assert.equal(roi.label, 'estimate');
  assert.equal(savings.savingsMicros, 300); assert.equal(savings.causal, false);
});
