'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  getBudgetStatus, getExperimentResult, getPortfolioBusinessSummary, getProjectBusinessSummary,
  getProjectEconomics, getProjectFunnel, getProjectMetric, getProjectRecommendations, professionalDetails,
} = require('../src/business-api.js');
const { compareVersionOutcomes, governedChangeIntent, optimizationLoopState, recommendationPriority, versionOutcomeTimeline } = require('../src/optimization.js');

const SCOPE = { organizationId: 'org-1', projectId: 'project-1' };

test('project business summary is owner-safe and scoped', () => {
  const result = getProjectBusinessSummary({ scope: SCOPE, objective: { organizationId: 'org-1', projectId: 'project-1', objective: 'Increase bookings', baseline: '10', target: '20' }, metric: { organizationId: 'org-1', projectId: 'project-1', key: 'booking_completed' }, measurement: { organizationId: 'org-1', projectId: 'project-1', value: 14, sampleSize: 50, state: 'ready' }, outcome: { organizationId: 'org-1', projectId: 'project-1', state: 'near_target', health: 'working' } });
  assert.equal(result.goal, 'Increase bookings'); assert.equal(result.measurement.value, 14); assert.equal(result.outcome.causal, false);
});
test('project business summary rejects cross-org data', () => {
  assert.throws(() => getProjectBusinessSummary({ scope: SCOPE, measurement: { organizationId: 'other', projectId: 'project-1', value: 1 } }), /CROSS_ORG_ACCESS/);
});
test('project metric projection hides provider internals', () => {
  const result = getProjectMetric({ scope: SCOPE, metric: { organizationId: 'org-1', projectId: 'project-1', key: 'signup' }, measurement: { organizationId: 'org-1', projectId: 'project-1', value: 2, providerQuery: 'secret-query', raw: { x: 1 } } });
  assert.equal(result.measurement.value, 2); assert.equal(Object.hasOwn(result.measurement, 'providerQuery'), false);
});
test('project funnel projection sanitizes raw provider fields', () => {
  const result = getProjectFunnel({ scope: SCOPE, funnel: { organizationId: 'org-1', projectId: 'project-1', steps: [{ event: 'a', count: 10 }], raw: { provider: true }, hogql: 'select' } });
  assert.equal(result.funnel.steps[0].count, 10); assert.equal(Object.hasOwn(result.funnel, 'raw'), false); assert.equal(Object.hasOwn(result.funnel, 'hogql'), false);
});
test('project recommendations enforce project isolation', () => {
  assert.throws(() => getProjectRecommendations({ scope: SCOPE, recommendations: [{ organizationId: 'org-1', projectId: 'other', recommendationId: 'r1' }] }), /CROSS_PROJECT_ACCESS/);
});
test('economics and budget projections expose owner-safe values only', () => {
  const economics = getProjectEconomics({ scope: SCOPE, economics: { organizationId: 'org-1', projectId: 'project-1', totalCostMicros: 100, knownCostMicros: 100, confidence: 'actual', complete: true, metadataRedacted: { pricing_source: 'x' } }, budget: { organizationId: 'org-1', projectId: 'project-1', exhausted: false, remaining_units: 900, requires_approval_for_extra_spend: false } });
  assert.equal(economics.economics.totalCostMicros, 100); assert.equal(Object.hasOwn(economics.economics, 'metadataRedacted'), false); assert.equal(economics.budget.remainingUnits, 900);
});
test('budget status maps Worker C policy fields for UI without authority', () => {
  const result = getBudgetStatus({ scope: SCOPE, budget: { organizationId: 'org-1', projectId: 'project-1', exhausted: true, remaining_units: 0, requires_approval_for_extra_spend: false } });
  assert.equal(result.budget.exhausted, true); assert.equal(result.budget.remainingUnits, 0);
});
test('experiment result exposes causal status explicitly', () => {
  const result = getExperimentResult({ scope: SCOPE, experiment: { organizationId: 'org-1', projectId: 'project-1', experimentId: 'e1', state: 'winner', primaryMetric: 'conversion', causal: false, causalClaim: 'not_established' } });
  assert.equal(result.experiment.state, 'winner'); assert.equal(result.experiment.causal, false);
});
test('portfolio summary rejects cross-org projects', () => {
  assert.throws(() => getPortfolioBusinessSummary({ scope: { organizationId: 'org-1' }, projects: [{ organizationId: 'other', projectId: 'p1' }] }), /CROSS_ORG_ACCESS/);
});
test('professional details sanitize credentials and raw query internals', () => {
  const result = professionalDetails({ scope: SCOPE, details: { organizationId: 'org-1', projectId: 'project-1', eventName: 'booking_completed', providerQuery: 'internal', secretToken: 'should-not-project' } });
  assert.equal(result.technical.eventName, 'booking_completed'); assert.equal(Object.hasOwn(result.technical, 'providerQuery'), false); assert.equal(Object.hasOwn(result.technical, 'secretToken'), false);
});
test('accepted recommendation becomes governed change intent, never direct production mutation', () => {
  const intent = governedChangeIntent({ recommendation: { organizationId: 'org-1', projectId: 'project-1', recommendationId: 'r1', objectiveId: 'o1', affectedMetric: 'conversion', suggestedChange: 'Simplify checkout', status: 'accepted' }, measurementEvidence: { window: { start: '2026-08-01', end: '2026-08-28' }, projectVersionId: 'v19', state: 'ready' } });
  assert.equal(intent.intentKind, 'change'); assert.equal(intent.requiresWorkerLifecycle, true); assert.equal(intent.productionMutationAuthorized, false);
});
test('version comparison and recommendation priority stay evidence-bounded', () => {
  const timeline = versionOutcomeTimeline([{ organizationId: 'org-1', projectId: 'project-1', projectVersionId: 'v18', value: 0.2, sampleSize: 100 }, { organizationId: 'org-1', projectId: 'project-1', projectVersionId: 'v19', value: 0.25, sampleSize: 120 }], { organizationId: 'org-1', projectId: 'project-1', metricKey: 'conversion' });
  const comparison = compareVersionOutcomes({ before: { value: 0.2, sampleSize: 100 }, after: { value: 0.25, sampleSize: 120 } });
  const priority = recommendationPriority({ impact: 0.05, confidence: 'high', costMicros: 1000, risk: 'low' });
  const loop = optimizationLoopState({ recommendation: { status: 'accepted' }, changeIntent: { id: 'i1' }, verification: { status: 'PASS' }, postChangeMeasurement: { outcome: 'target_met' } });
  assert.equal(timeline.causal, false); assert.equal(comparison.state, 'improved'); assert.equal(comparison.causal, false); assert.notEqual(priority.score, null); assert.equal(loop.state, 'validated'); assert.equal(loop.productionMutationAuthorized, false);
});
