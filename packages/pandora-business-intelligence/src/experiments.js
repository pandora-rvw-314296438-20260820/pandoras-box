'use strict';

const EXPERIMENT_STATES = Object.freeze([
  'draft', 'running', 'paused', 'stopped', 'winner', 'loser',
  'no_significant_difference', 'inconclusive', 'guardrail_failed',
]);
const METRIC_DIRECTIONS = Object.freeze(['increase', 'decrease']);

function isObject(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function req(value, name) {
  if (typeof value !== 'string' || value.trim() === '') throw new TypeError(`${name} is required`);
  return value;
}
function finite(value, name) {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new TypeError(`${name} must be finite`);
  return value;
}
function nonNegativeInteger(value, name) {
  if (!Number.isSafeInteger(value) || value < 0) throw new TypeError(`${name} must be a non-negative safe integer`);
  return value;
}

function createExperimentDefinition(input) {
  if (!isObject(input)) throw new TypeError('experiment definition is required');
  const minimumSampleSize = nonNegativeInteger(input.minimumSampleSize ?? 100, 'minimumSampleSize');
  if (minimumSampleSize < 2) throw new TypeError('minimumSampleSize must be at least 2');
  const metricDirection = input.metricDirection ?? 'increase';
  if (!METRIC_DIRECTIONS.includes(metricDirection)) throw new TypeError('invalid metricDirection');
  const minimumEffect = finite(input.minimumEffect ?? 0, 'minimumEffect');
  if (minimumEffect < 0) throw new TypeError('minimumEffect cannot be negative');
  if (!Array.isArray(input.guardrails ?? [])) throw new TypeError('guardrails must be an array');
  return Object.freeze({
    experimentId: req(input.experimentId, 'experimentId'),
    organizationId: req(input.organizationId, 'organizationId'),
    projectId: req(input.projectId, 'projectId'),
    objectiveId: req(input.objectiveId, 'objectiveId'),
    hypothesis: req(input.hypothesis, 'hypothesis'),
    control: req(input.control, 'control'),
    variant: req(input.variant, 'variant'),
    primaryMetric: req(input.primaryMetric, 'primaryMetric'),
    metricDirection,
    minimumEffect,
    minimumSampleSize,
    guardrails: Object.freeze((input.guardrails ?? []).map((value) => req(value, 'guardrail'))),
    randomized: input.randomized === true,
    exposureVerified: input.exposureVerified === true,
    status: input.status ?? 'draft',
    analysisPlanVersion: input.analysisPlanVersion ?? '1.0.0',
    providerBinding: input.providerBinding ? Object.freeze({ ...input.providerBinding }) : null,
  });
}

function validateExperimentScope(definition, scope) {
  if (!scope || definition.organizationId !== scope.organizationId) throw new Error('CROSS_ORG_ACCESS');
  if (definition.projectId !== scope.projectId) throw new Error('CROSS_PROJECT_ACCESS');
  return true;
}

function posthogExperimentBinding({ experimentId, featureFlagKey, projectId, environment = 'production' }) {
  return Object.freeze({
    provider: 'posthog',
    experimentId: req(experimentId, 'experimentId'),
    featureFlagKey: req(featureFlagKey, 'featureFlagKey'),
    projectId: req(projectId, 'projectId'),
    environment: req(environment, 'environment'),
    credentialIncluded: false,
  });
}

function normalizeArm(input, name) {
  if (!isObject(input)) throw new TypeError(`${name} is required`);
  return Object.freeze({
    sampleSize: nonNegativeInteger(input.sampleSize ?? 0, `${name}.sampleSize`),
    value: input.value == null ? null : finite(input.value, `${name}.value`),
  });
}

function evaluateExperiment({ definition: rawDefinition, control, variant, confidence = null, guardrails = [], state = 'stopped' }) {
  const definition = createExperimentDefinition(rawDefinition);
  const c = normalizeArm(control, 'control');
  const v = normalizeArm(variant, 'variant');
  const conf = confidence == null ? null : finite(confidence, 'confidence');
  if (conf != null && (conf < 0 || conf > 1)) throw new TypeError('confidence must be between 0 and 1');
  if (!Array.isArray(guardrails)) throw new TypeError('guardrails must be an array');
  const failedGuardrails = guardrails.filter((item) => item?.failed === true).map((item) => String(item.name ?? 'unnamed_guardrail'));
  const enoughSample = c.sampleSize >= definition.minimumSampleSize && v.sampleSize >= definition.minimumSampleSize;
  const hasValues = c.value != null && v.value != null;
  const absoluteEffect = hasValues ? v.value - c.value : null;
  const relativeEffect = hasValues && c.value !== 0 ? absoluteEffect / Math.abs(c.value) : null;
  const directionSatisfied = hasValues && (
    definition.metricDirection === 'increase' ? absoluteEffect >= definition.minimumEffect : -absoluteEffect >= definition.minimumEffect
  );
  const oppositeDirection = hasValues && (
    definition.metricDirection === 'increase' ? absoluteEffect <= -definition.minimumEffect : absoluteEffect >= definition.minimumEffect
  );
  const significant = conf != null && conf >= 0.95;

  let resultState = 'inconclusive';
  if (failedGuardrails.length > 0) resultState = 'guardrail_failed';
  else if (!enoughSample || !hasValues || !significant) resultState = state === 'running' ? 'running' : 'inconclusive';
  else if (directionSatisfied) resultState = 'winner';
  else if (oppositeDirection) resultState = 'loser';
  else resultState = 'no_significant_difference';

  const causal = resultState === 'winner' && definition.randomized && definition.exposureVerified && significant && failedGuardrails.length === 0;
  return Object.freeze({
    experimentId: definition.experimentId,
    organizationId: definition.organizationId,
    projectId: definition.projectId,
    state: resultState,
    primaryMetric: definition.primaryMetric,
    control: c,
    variant: v,
    absoluteEffect,
    relativeEffect,
    confidence: conf,
    minimumSampleSize: definition.minimumSampleSize,
    sampleSufficient: enoughSample,
    failedGuardrails: Object.freeze(failedGuardrails),
    randomized: definition.randomized,
    exposureVerified: definition.exposureVerified,
    causal,
    causalClaim: causal ? 'randomized_exposure_verified' : 'not_established',
  });
}

function pricingExperimentResult({ offers, minimumSampleSize = 30, confidenceThreshold = 0.95 }) {
  if (!Array.isArray(offers) || offers.length < 2) throw new TypeError('at least two pricing offers are required');
  const minimum = nonNegativeInteger(minimumSampleSize, 'minimumSampleSize');
  const threshold = finite(confidenceThreshold, 'confidenceThreshold');
  const rows = offers.map((offer, index) => {
    if (!isObject(offer)) throw new TypeError(`offer[${index}] must be an object`);
    const visitors = nonNegativeInteger(offer.visitors, `offer[${index}].visitors`);
    const conversions = nonNegativeInteger(offer.conversions, `offer[${index}].conversions`);
    if (conversions > visitors) throw new TypeError('conversions cannot exceed visitors');
    const priceMicros = nonNegativeInteger(offer.priceMicros, `offer[${index}].priceMicros`);
    return Object.freeze({
      offerId: req(offer.offerId, `offer[${index}].offerId`),
      visitors,
      conversions,
      priceMicros,
      conversionRate: visitors === 0 ? null : conversions / visitors,
      observedRevenueMicros: conversions * priceMicros,
      confidence: offer.confidence == null ? null : finite(offer.confidence, `offer[${index}].confidence`),
    });
  });
  const eligible = rows.filter((row) => row.visitors >= minimum && row.confidence != null && row.confidence >= threshold);
  const ranked = [...eligible].sort((a, b) => b.observedRevenueMicros - a.observedRevenueMicros);
  return Object.freeze({
    offers: Object.freeze(rows),
    minimumSampleSize: minimum,
    confidenceThreshold: threshold,
    winnerOfferId: ranked.length > 0 ? ranked[0].offerId : null,
    state: ranked.length > 0 ? 'observed_leader' : 'inconclusive',
    causal: false,
  });
}

module.exports = {
  EXPERIMENT_STATES,
  METRIC_DIRECTIONS,
  createExperimentDefinition,
  evaluateExperiment,
  posthogExperimentBinding,
  pricingExperimentResult,
  validateExperimentScope,
};
