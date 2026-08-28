'use strict';

const MEASUREMENT_STATES = Object.freeze(['not_configured','configured','receiving_data','stale','broken','ready']);
const OUTCOME_STATES = Object.freeze(['not_measurable','awaiting_data','below_baseline','near_target','target_met','target_exceeded','regressed','inconclusive']);
const BUSINESS_HEALTH_STATES = Object.freeze(['not_measured','collecting_data','on_track','needs_attention','target_reached','improving','declining']);
const EVENT_KINDS = Object.freeze(['customer_app_business_event','pandora_internal_event']);
const ENVIRONMENTS = Object.freeze(['preview','production','test','development']);
const AGGREGATIONS = Object.freeze(['count','unique_count','sum','average','rate','duration','latest']);
const UNITS = Object.freeze(['count','percent','currency','seconds','minutes','hours','days','score','boolean','custom']);
const PROVENANCE_TYPES = Object.freeze(['analytics','customer_supplied','observation_period','import','provider','derived']);

function requireString(value, field, max = 5000) {
  if (typeof value !== 'string' || value.trim() === '') throw new TypeError(`${field} is required`);
  const text = value.trim();
  if (text.length > max) throw new TypeError(`${field} exceeds ${max} characters`);
  return text;
}
function optionalString(value, field, max = 5000) {
  if (value == null || value === '') return null;
  return requireString(value, field, max);
}
function requireEnum(value, allowed, field) {
  if (!allowed.includes(value)) throw new TypeError(`${field} must be one of: ${allowed.join(', ')}`);
  return value;
}
function optionalFiniteNumber(value, field) {
  if (value == null) return null;
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new TypeError(`${field} must be a finite number`);
  return value;
}
function nonNegativeInteger(value, field, fallback = 0) {
  if (value == null) return fallback;
  if (!Number.isInteger(value) || value < 0) throw new TypeError(`${field} must be a non-negative integer`);
  return value;
}
function objectOrEmpty(value, field) {
  if (value == null) return {};
  if (typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}
function isoOrNull(value, field) {
  if (value == null) return null;
  if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) throw new TypeError(`${field} must be an ISO date-time`);
  return new Date(value).toISOString();
}
function scope(input, options = {}) {
  const value = objectOrEmpty(input, 'scope');
  return Object.freeze({
    organizationId: requireString(value.organizationId, 'organizationId', 160),
    projectId: requireString(value.projectId, 'projectId', 160),
    projectVersionId: options.requireVersion === false ? optionalString(value.projectVersionId, 'projectVersionId', 160) : requireString(value.projectVersionId, 'projectVersionId', 160),
    environment: requireEnum(value.environment ?? 'production', ENVIRONMENTS, 'environment'),
  });
}

function createBusinessObjective(input) {
  const value = objectOrEmpty(input, 'businessObjective');
  const metricKey = optionalString(value.primaryMetricKey, 'primaryMetricKey', 160);
  const window = objectOrEmpty(value.measurementWindow, 'measurementWindow');
  const baseline = objectOrEmpty(value.baseline, 'baseline');
  const target = objectOrEmpty(value.target, 'target');
  return Object.freeze({
    objectiveId: requireString(value.objectiveId, 'objectiveId', 160),
    projectSpecId: requireString(value.projectSpecId, 'projectSpecId', 160),
    objective: requireString(value.objective, 'objective'),
    desiredOutcome: optionalString(value.desiredOutcome, 'desiredOutcome'),
    primaryMetricKey: metricKey,
    baseline: Object.freeze({
      value: optionalFiniteNumber(baseline.value, 'baseline.value'),
      text: optionalString(baseline.text, 'baseline.text', 1000),
      provenance: baseline.value == null && baseline.text == null ? null : requireEnum(baseline.provenance ?? 'customer_supplied', PROVENANCE_TYPES, 'baseline.provenance'),
      observedAt: isoOrNull(baseline.observedAt, 'baseline.observedAt'),
    }),
    target: Object.freeze({
      value: optionalFiniteNumber(target.value, 'target.value'),
      text: optionalString(target.text, 'target.text', 1000),
      dueAt: isoOrNull(target.dueAt, 'target.dueAt'),
    }),
    measurementWindow: Object.freeze({
      amount: window.amount == null ? null : nonNegativeInteger(window.amount, 'measurementWindow.amount'),
      unit: window.unit == null ? null : requireEnum(window.unit, ['hour','day','week','month','custom'], 'measurementWindow.unit'),
    }),
    guardrailMetricKeys: Object.freeze(Array.isArray(value.guardrailMetricKeys) ? value.guardrailMetricKeys.map((item, i) => requireString(item, `guardrailMetricKeys[${i}]`, 160)) : []),
  });
}

function createMetricDefinition(input) {
  const value = objectOrEmpty(input, 'metricDefinition');
  return Object.freeze({
    key: requireString(value.key, 'key', 160),
    event: requireString(value.event, 'event', 160),
    aggregation: requireEnum(value.aggregation, AGGREGATIONS, 'aggregation'),
    unit: requireEnum(value.unit, UNITS, 'unit'),
    property: optionalString(value.property, 'property', 160),
    denominatorEvent: optionalString(value.denominatorEvent, 'denominatorEvent', 160),
    freshnessSeconds: nonNegativeInteger(value.freshnessSeconds, 'freshnessSeconds', 3600),
    minimumSampleSize: nonNegativeInteger(value.minimumSampleSize, 'minimumSampleSize', 1),
    minimumObservationSeconds: nonNegativeInteger(value.minimumObservationSeconds, 'minimumObservationSeconds', 0),
    versionAttribution: requireEnum(value.versionAttribution ?? 'event_scope', ['event_scope','deployment_window','none'], 'versionAttribution'),
    description: optionalString(value.description, 'description', 1000),
  });
}

function createMeasurement(input) {
  const value = objectOrEmpty(input, 'measurement');
  return Object.freeze({
    metricKey: requireString(value.metricKey, 'metricKey', 160),
    value: optionalFiniteNumber(value.value, 'value'),
    sampleSize: nonNegativeInteger(value.sampleSize, 'sampleSize'),
    windowStart: isoOrNull(value.windowStart, 'windowStart'),
    windowEnd: isoOrNull(value.windowEnd, 'windowEnd'),
    lastObservedAt: isoOrNull(value.lastObservedAt, 'lastObservedAt'),
    complete: value.complete === true,
    source: requireEnum(value.source ?? 'analytics', PROVENANCE_TYPES, 'source'),
    quality: requireEnum(value.quality ?? 'valid', ['valid','partial','duplicate_suspected','attribution_missing','schema_mismatch','invalid'], 'quality'),
  });
}

module.exports = {
  AGGREGATIONS, BUSINESS_HEALTH_STATES, ENVIRONMENTS, EVENT_KINDS, MEASUREMENT_STATES,
  OUTCOME_STATES, PROVENANCE_TYPES, UNITS, createBusinessObjective, createMeasurement,
  createMetricDefinition, isoOrNull, nonNegativeInteger, objectOrEmpty, optionalFiniteNumber,
  optionalString, requireEnum, requireString, scope,
};
