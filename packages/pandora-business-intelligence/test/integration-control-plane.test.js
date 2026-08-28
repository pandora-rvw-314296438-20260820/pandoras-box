'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { budgetAlert, dataQualityAlert, measurementAlert, outcomeAlert } = require('../src/alerts.js');
const { measurementDefinitionFromObjective, numericText, objectiveFromControlPlaneRow } = require('../src/control-plane.js');
const { businessIntelligenceReadiness, noDataProof, proveWorkerHFlow } = require('../src/integration.js');

test('control-plane objective adapter preserves raw truth and parses only safe numeric values', () => {
  const objective = objectiveFromControlPlaneRow({ id: 'o1', organization_id: 'org-1', project_id: 'p1', project_spec_id: 's1', ordinal: 1, objective: 'Increase conversion', desired_outcome: 'More completed checkouts', success_metric: 'Checkout Conversion Rate', baseline: '10%', target: '0.2', provenance: { source: 'customer' } });
  assert.equal(objective.baseline.value, 0.1); assert.equal(objective.target.value, 0.2); assert.equal(numericText('about ten'), null);
  const metric = measurementDefinitionFromObjective(objective, { checkout_conversion_rate: { key: 'checkout_conversion_rate' } });
  assert.equal(metric.configured, true);
});
test('alerts distinguish budget, measurement, data-quality and outcome conditions', () => {
  assert.equal(budgetAlert({ exhausted: true }).code, 'budget_exhausted');
  assert.equal(measurementAlert({ measurementState: 'ready', stale: true }).code, 'measurement_stale');
  assert.equal(dataQualityAlert({ issues: [{ type: 'wrong_attribution' }] }).severity, 'critical');
  assert.equal(outcomeAlert({ state: 'target_met', material: true }).code, 'target_reached');
});
test('no-data proof never converts missing PostHog events into zero or success', () => {
  const proof = noDataProof({ objectiveConfigured: true, instrumentationVerified: true, providerEventObserved: false });
  assert.equal(proof.state, 'awaiting_data'); assert.equal(proof.value, null); assert.equal(proof.zeroAssumed, false); assert.equal(proof.successAssumed, false);
});
test('Worker H E2E proof requires objective, independent instrumentation, data, budget contract and governed recommendation path', () => {
  const objective = { organizationId: 'org-1', projectId: 'p1', successMetric: 'conversion' };
  const measurement = { organizationId: 'org-1', projectId: 'p1', value: 0.2, sampleSize: 100, stale: false };
  const outcome = { organizationId: 'org-1', projectId: 'p1', state: 'near_target' };
  const economics = { organizationId: 'org-1', projectId: 'p1', complete: true, totalCostMicros: 1000 };
  const readiness = businessIntelligenceReadiness({ objective, instrumentationVerification: { status: 'PASS' }, measurement, outcome, economics });
  const proof = proveWorkerHFlow({ scope: { organizationId: 'org-1', projectId: 'p1' }, objective, instrumentationVerification: { status: 'PASS' }, measurement, outcome, economics, budgetSignal: { exhausted: false, remaining_units: 100 }, recommendation: { organizationId: 'org-1', projectId: 'p1' }, changeIntent: { requiresWorkerLifecycle: true, productionMutationAuthorized: false } });
  assert.equal(readiness.state, 'ready'); assert.equal(proof.pass, true); assert.equal(proof.productionMutationAuthorized, false);
});
