'use strict';

const INTERNAL_KEYS = new Set([
  'providerQuery', 'provider_query', 'raw', 'rawResult', 'raw_result', 'sql', 'hogql',
  'metadataRedacted', 'metadata_redacted', 'pricingSource', 'pricing_source', 'idempotencyKey',
  'idempotency_key', 'toolCallId', 'tool_call_id', 'modelRunId', 'model_run_id', 'secret', 'token',
]);

function isObject(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function requireScope(scope, { project = true } = {}) {
  if (!isObject(scope)) throw new TypeError('scope is required');
  if (typeof scope.organizationId !== 'string' || !scope.organizationId) throw new TypeError('scope.organizationId is required');
  if (project && (typeof scope.projectId !== 'string' || !scope.projectId)) throw new TypeError('scope.projectId is required');
  return scope;
}
function read(record, camel, snake) { return record?.[camel] ?? record?.[snake] ?? null; }
function assertScoped(record, scope, { project = true } = {}) {
  if (!isObject(record)) return true;
  const org = read(record, 'organizationId', 'organization_id');
  const projectId = read(record, 'projectId', 'project_id');
  if (org != null && org !== scope.organizationId) throw new Error('CROSS_ORG_ACCESS');
  if (project && projectId != null && projectId !== scope.projectId) throw new Error('CROSS_PROJECT_ACCESS');
  return true;
}
function sanitize(value) {
  if (Array.isArray(value)) return Object.freeze(value.map(sanitize));
  if (!isObject(value)) return value;
  const result = {};
  for (const [key, child] of Object.entries(value)) {
    if (INTERNAL_KEYS.has(key) || /secret|password|authorization|credential/i.test(key)) continue;
    result[key] = sanitize(child);
  }
  return Object.freeze(result);
}
function ownerMeasurement(value) {
  if (!value) return null;
  return Object.freeze({
    value: value.value ?? null,
    sampleSize: value.sampleSize ?? value.sample_size ?? null,
    state: value.state ?? value.measurementState ?? value.measurement_state ?? null,
    lastObservedAt: value.lastObservedAt ?? value.last_observed_at ?? null,
    stale: value.stale ?? null,
    quality: value.quality ?? null,
  });
}
function ownerEconomics(value) {
  if (!value) return null;
  return Object.freeze({
    currency: value.currency ?? 'USD',
    totalCostMicros: value.totalCostMicros ?? value.total_cost_micros ?? null,
    knownCostMicros: value.knownCostMicros ?? value.known_cost_micros ?? null,
    confidence: value.confidence ?? 'unknown',
    complete: value.complete === true,
    chargedMicros: value.chargedMicros ?? value.charged_micros ?? null,
    creditsMicros: value.creditsMicros ?? value.credits_micros ?? null,
    marginMicros: value.marginMicros ?? value.margin_micros ?? value.margin?.marginMicros ?? null,
    marginRate: value.marginRate ?? value.margin_rate ?? value.margin?.marginRate ?? null,
  });
}
function ownerBudget(value) {
  if (!value) return null;
  return Object.freeze({
    exhausted: value.exhausted === true,
    remainingUnits: value.remaining_units ?? value.remainingUnits ?? null,
    approvalRequiredForExtraSpend: value.requires_approval_for_extra_spend === true || value.approvalRequiredForExtraSpend === true,
    currency: value.currency ?? 'USD',
  });
}
function ownerRecommendation(value) {
  if (!value) return null;
  return Object.freeze({
    recommendationId: value.recommendationId ?? value.recommendation_id ?? null,
    observedFact: value.observedFact ?? value.observed_fact ?? null,
    suggestedChange: value.suggestedChange ?? value.suggested_change ?? null,
    expectedImpact: value.expectedImpactHypothesis ?? value.expected_impact_hypothesis ?? null,
    confidence: value.confidence ?? null,
    status: value.status ?? null,
  });
}

function getProjectBusinessSummary({ scope: rawScope, objective = null, metric = null, measurement = null, outcome = null, economics = null, budget = null, recommendation = null }) {
  const scope = requireScope(rawScope);
  for (const record of [objective, metric, measurement, outcome, economics, budget, recommendation]) assertScoped(record, scope);
  return Object.freeze({
    organizationId: scope.organizationId,
    projectId: scope.projectId,
    goal: objective?.objective ?? objective?.goal ?? null,
    desiredOutcome: objective?.desiredOutcome ?? objective?.desired_outcome ?? null,
    metric: metric?.key ?? objective?.successMetric ?? objective?.success_metric ?? null,
    baseline: objective?.baseline?.value ?? objective?.baseline ?? null,
    target: objective?.target?.value ?? objective?.target ?? null,
    measurement: ownerMeasurement(measurement),
    outcome: outcome ? Object.freeze({ state: outcome.state ?? 'not_measurable', health: outcome.health ?? 'not_measured', causal: outcome.causal === true }) : Object.freeze({ state: 'not_measurable', health: 'not_measured', causal: false }),
    economics: ownerEconomics(economics),
    budget: ownerBudget(budget),
    topRecommendation: ownerRecommendation(recommendation),
  });
}

function getProjectMetric({ scope: rawScope, metric, measurement }) {
  const scope = requireScope(rawScope);
  assertScoped(metric, scope); assertScoped(measurement, scope);
  return Object.freeze({ organizationId: scope.organizationId, projectId: scope.projectId, metric: metric?.key ?? null, measurement: ownerMeasurement(measurement) });
}
function getProjectFunnel({ scope: rawScope, funnel }) {
  const scope = requireScope(rawScope); assertScoped(funnel, scope);
  return Object.freeze({ organizationId: scope.organizationId, projectId: scope.projectId, funnel: sanitize(funnel ?? null) });
}
function getProjectRecommendations({ scope: rawScope, recommendations = [] }) {
  const scope = requireScope(rawScope);
  if (!Array.isArray(recommendations)) throw new TypeError('recommendations must be an array');
  recommendations.forEach((record) => assertScoped(record, scope));
  return Object.freeze({ organizationId: scope.organizationId, projectId: scope.projectId, recommendations: Object.freeze(recommendations.map(ownerRecommendation)) });
}
function getProjectEconomics({ scope: rawScope, economics, budget = null }) {
  const scope = requireScope(rawScope); assertScoped(economics, scope); assertScoped(budget, scope);
  return Object.freeze({ organizationId: scope.organizationId, projectId: scope.projectId, economics: ownerEconomics(economics), budget: ownerBudget(budget) });
}
function getBudgetStatus({ scope: rawScope, budget }) {
  const scope = requireScope(rawScope); assertScoped(budget, scope);
  return Object.freeze({ organizationId: scope.organizationId, projectId: scope.projectId, budget: ownerBudget(budget) });
}
function getExperimentResult({ scope: rawScope, experiment }) {
  const scope = requireScope(rawScope); assertScoped(experiment, scope);
  return Object.freeze({
    organizationId: scope.organizationId,
    projectId: scope.projectId,
    experiment: experiment ? Object.freeze({
      experimentId: experiment.experimentId ?? experiment.experiment_id ?? null,
      state: experiment.state ?? 'inconclusive',
      primaryMetric: experiment.primaryMetric ?? experiment.primary_metric ?? null,
      absoluteEffect: experiment.absoluteEffect ?? experiment.absolute_effect ?? null,
      relativeEffect: experiment.relativeEffect ?? experiment.relative_effect ?? null,
      confidence: experiment.confidence ?? null,
      sampleSufficient: experiment.sampleSufficient === true,
      causal: experiment.causal === true,
      causalClaim: experiment.causalClaim ?? experiment.causal_claim ?? 'not_established',
    }) : null,
  });
}

function getPortfolioBusinessSummary({ scope: rawScope, projects = [] }) {
  const scope = requireScope(rawScope, { project: false });
  if (!Array.isArray(projects)) throw new TypeError('projects must be an array');
  const rows = projects.map((project, index) => {
    if (!isObject(project)) throw new TypeError(`projects[${index}] must be an object`);
    assertScoped(project, scope, { project: false });
    const projectId = read(project, 'projectId', 'project_id');
    if (typeof projectId !== 'string' || !projectId) throw new TypeError(`projects[${index}].projectId is required`);
    return Object.freeze({
      projectId,
      goal: project.goal ?? project.objective?.objective ?? null,
      outcome: project.outcome?.state ?? project.outcome ?? 'not_measurable',
      health: project.outcome?.health ?? project.health ?? 'not_measured',
      economics: ownerEconomics(project.economics),
      budget: ownerBudget(project.budget),
      recommendation: ownerRecommendation(project.recommendation),
    });
  });
  const measured = rows.filter((row) => !['not_measurable', 'awaiting_data', 'inconclusive'].includes(row.outcome));
  return Object.freeze({
    organizationId: scope.organizationId,
    projectCount: rows.length,
    measuredProjectCount: measured.length,
    projects: Object.freeze(rows),
  });
}

function professionalDetails({ scope: rawScope, details = {} }) {
  const scope = requireScope(rawScope);
  assertScoped(details, scope);
  return Object.freeze({ organizationId: scope.organizationId, projectId: scope.projectId, technical: sanitize(details) });
}

module.exports = {
  getBudgetStatus,
  getExperimentResult,
  getPortfolioBusinessSummary,
  getProjectBusinessSummary,
  getProjectEconomics,
  getProjectFunnel,
  getProjectMetric,
  getProjectRecommendations,
  professionalDetails,
  sanitize,
};
