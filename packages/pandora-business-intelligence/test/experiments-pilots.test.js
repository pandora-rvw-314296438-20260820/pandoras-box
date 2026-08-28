'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createExperimentDefinition, evaluateExperiment, posthogExperimentBinding, pricingExperimentResult, validateExperimentScope } = require('../src/experiments.js');
const { cohortEconomics, createPilotDefinition, evaluatePilot, manualHoursValue, pilotRoi } = require('../src/pilots.js');

function experiment(overrides = {}) {
  return { experimentId: 'exp-1', organizationId: 'org-1', projectId: 'project-1', objectiveId: 'obj-1', hypothesis: 'Variant improves conversion', control: 'control', variant: 'variant', primaryMetric: 'conversion', minimumSampleSize: 20, randomized: true, exposureVerified: true, ...overrides };
}

test('creates bounded experiment definition', () => {
  const result = createExperimentDefinition(experiment());
  assert.equal(result.minimumSampleSize, 20); assert.equal(result.randomized, true);
});
test('experiment scope rejects cross-project reads', () => {
  assert.throws(() => validateExperimentScope(createExperimentDefinition(experiment()), { organizationId: 'org-1', projectId: 'other' }), /CROSS_PROJECT_ACCESS/);
});
test('PostHog binding never carries a credential', () => {
  const binding = posthogExperimentBinding({ experimentId: 'exp-1', featureFlagKey: 'flag-a', projectId: 'project-1' });
  assert.equal(binding.provider, 'posthog'); assert.equal(binding.credentialIncluded, false);
});
test('insufficient experiment sample is inconclusive', () => {
  const result = evaluateExperiment({ definition: experiment(), control: { sampleSize: 10, value: 0.2 }, variant: { sampleSize: 10, value: 0.3 }, confidence: 0.99 });
  assert.equal(result.state, 'inconclusive'); assert.equal(result.causal, false);
});
test('significant randomized verified experiment can establish bounded causal claim', () => {
  const result = evaluateExperiment({ definition: experiment({ minimumEffect: 0.02 }), control: { sampleSize: 100, value: 0.2 }, variant: { sampleSize: 100, value: 0.25 }, confidence: 0.97 });
  assert.equal(result.state, 'winner'); assert.equal(result.causal, true); assert.equal(result.causalClaim, 'randomized_exposure_verified');
});
test('non-randomized winner cannot claim causality', () => {
  const result = evaluateExperiment({ definition: experiment({ randomized: false }), control: { sampleSize: 100, value: 0.2 }, variant: { sampleSize: 100, value: 0.3 }, confidence: 0.99 });
  assert.equal(result.state, 'winner'); assert.equal(result.causal, false);
});
test('guardrail failure overrides primary metric winner', () => {
  const result = evaluateExperiment({ definition: experiment(), control: { sampleSize: 100, value: 0.2 }, variant: { sampleSize: 100, value: 0.3 }, confidence: 0.99, guardrails: [{ name: 'error_rate', failed: true }] });
  assert.equal(result.state, 'guardrail_failed'); assert.deepEqual(result.failedGuardrails, ['error_rate']);
});
test('pricing experiment does not pick a winner without sample and confidence', () => {
  const result = pricingExperimentResult({ offers: [{ offerId: 'a', visitors: 10, conversions: 2, priceMicros: 100, confidence: 0.99 }, { offerId: 'b', visitors: 10, conversions: 3, priceMicros: 80, confidence: 0.99 }] });
  assert.equal(result.winnerOfferId, null); assert.equal(result.state, 'inconclusive');
});
test('pilot validation requires paid, sufficient window, target and positive complete margin', () => {
  const definition = createPilotDefinition({ pilotId: 'p1', organizationId: 'org-1', projectId: 'project-1', customerClass: 'restaurant', paid: true, priceMicros: 1000, minimumObservationDays: 14 });
  const result = evaluatePilot({ definition, observedRevenueMicros: 1000, internalCostMicros: 400, outcome: { state: 'target_met' }, retention: { applicable: false }, observationDays: 30 });
  assert.equal(result.validated, true); assert.equal(result.retentionState, 'not_applicable');
});
test('pilot with unknown internal cost cannot be validated economically', () => {
  const definition = createPilotDefinition({ pilotId: 'p1', organizationId: 'org-1', projectId: 'project-1', paid: true, priceMicros: 1000 });
  const result = evaluatePilot({ definition, observedRevenueMicros: 1000, internalCostMicros: null, outcome: { state: 'target_met' }, observationDays: 30 });
  assert.equal(result.margin.complete, false); assert.equal(result.validated, false);
});
test('cohort economics rejects cross-organization pilot aggregation', () => {
  assert.throws(() => cohortEconomics([{ organizationId: 'other', projectId: 'p', paid: true, validated: false, observedRevenueMicros: 1, internalCostMicros: 1 }], { organizationId: 'org-1' }), /CROSS_ORG_ACCESS/);
});
test('manual-hours value and pilot ROI preserve assumptions and non-causal posture', () => {
  const value = manualHoursValue({ hoursSaved: 10, hourlyValueMicros: 100, evidence: ['time study'] });
  const roi = pilotRoi({ pilotResult: { internalCostMicros: 500 }, benefitMicros: value.valueMicros, assumptions: ['hourly value estimate'] });
  assert.equal(value.valueMicros, 1000); assert.equal(value.causal, false); assert.equal(roi.roi, 1); assert.equal(roi.causal, false);
});


test('cohort economics filters by customer class', () => {
  const a = evaluatePilot({ definition:{pilotId:'pa',organizationId:'org-a',projectId:'p1',customerClass:'restaurant',paid:true}, observedRevenueMicros:200, internalCostMicros:100, outcome:{state:'target_met'}, observationDays:30 });
  const b = evaluatePilot({ definition:{pilotId:'pb',organizationId:'org-a',projectId:'p2',customerClass:'law',paid:true}, observedRevenueMicros:300, internalCostMicros:100, outcome:{state:'target_met'}, observationDays:30 });
  const result = cohortEconomics([a,b], {organizationId:'org-a',customerClass:'restaurant'});
  assert.equal(result.pilotCount, 1);
  assert.equal(result.revenueMicros, 200);
});
