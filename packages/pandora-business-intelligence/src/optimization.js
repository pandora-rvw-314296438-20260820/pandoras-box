'use strict';

function isObject(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function req(value, name) {
  if (typeof value !== 'string' || value.trim() === '') throw new TypeError(`${name} is required`);
  return value;
}
function finite(value, name, nullable = false) {
  if (value == null && nullable) return null;
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new TypeError(`${name} must be finite`);
  return value;
}

function governedChangeIntent({ recommendation, measurementEvidence = null }) {
  if (!isObject(recommendation)) throw new TypeError('recommendation is required');
  if (recommendation.status !== 'accepted') throw new Error('recommendation must be accepted');
  const organizationId = req(recommendation.organizationId ?? recommendation.organization_id, 'organizationId');
  const projectId = req(recommendation.projectId ?? recommendation.project_id, 'projectId');
  const recommendationId = req(recommendation.recommendationId ?? recommendation.recommendation_id, 'recommendationId');
  const objectiveId = req(recommendation.objectiveId ?? recommendation.objective_id, 'objectiveId');
  const suggestedChange = req(recommendation.suggestedChange ?? recommendation.suggested_change, 'suggestedChange');
  const affectedMetric = req(recommendation.affectedMetric ?? recommendation.affected_metric, 'affectedMetric');
  return Object.freeze({
    organizationId,
    projectId,
    intentKind: 'change',
    source: 'pandora',
    summary: suggestedChange,
    directExecutionAuthorized: false,
    productionMutationAuthorized: false,
    requiresWorkerLifecycle: true,
    provenance: Object.freeze({
      recommendationId,
      objectiveId,
      affectedMetric,
      measurementWindow: measurementEvidence?.window ?? null,
      measurementState: measurementEvidence?.state ?? measurementEvidence?.measurementState ?? null,
      exactProjectVersionId: measurementEvidence?.projectVersionId ?? measurementEvidence?.project_version_id ?? null,
    }),
  });
}

function versionOutcomeTimeline(records, { organizationId, projectId, metricKey }) {
  if (!Array.isArray(records)) throw new TypeError('records must be an array');
  const rows = records.map((record, index) => {
    if (!isObject(record)) throw new TypeError(`records[${index}] must be an object`);
    if ((record.organizationId ?? record.organization_id) !== organizationId) throw new Error('CROSS_ORG_ACCESS');
    if ((record.projectId ?? record.project_id) !== projectId) throw new Error('CROSS_PROJECT_ACCESS');
    const versionId = req(record.projectVersionId ?? record.project_version_id, `records[${index}].projectVersionId`);
    const value = finite(record.value, `records[${index}].value`, true);
    return Object.freeze({
      versionId,
      deployedAt: record.deployedAt ?? record.deployed_at ?? null,
      measuredAt: record.measuredAt ?? record.measured_at ?? null,
      value,
      sampleSize: record.sampleSize ?? record.sample_size ?? null,
      measurementState: record.measurementState ?? record.measurement_state ?? 'unknown',
    });
  });
  return Object.freeze({
    organizationId,
    projectId,
    metricKey: req(metricKey, 'metricKey'),
    rows: Object.freeze(rows),
    interpretation: 'temporal_association_only',
    causal: false,
  });
}

function compareVersionOutcomes({ before, after, minimumSampleSize = 20, materialityThreshold = 0.1 }) {
  if (!isObject(before) || !isObject(after)) throw new TypeError('before and after measurements are required');
  const beforeValue = finite(before.value, 'before.value', true);
  const afterValue = finite(after.value, 'after.value', true);
  const beforeSample = Number.isSafeInteger(before.sampleSize) ? before.sampleSize : 0;
  const afterSample = Number.isSafeInteger(after.sampleSize) ? after.sampleSize : 0;
  const enoughSample = beforeSample >= minimumSampleSize && afterSample >= minimumSampleSize;
  if (beforeValue == null || afterValue == null || !enoughSample) return Object.freeze({ state: 'inconclusive', absoluteChange: null, relativeChange: null, material: false, causal: false });
  const absoluteChange = afterValue - beforeValue;
  const relativeChange = beforeValue === 0 ? null : absoluteChange / Math.abs(beforeValue);
  const material = relativeChange == null ? Math.abs(absoluteChange) >= materialityThreshold : Math.abs(relativeChange) >= materialityThreshold;
  return Object.freeze({ state: material ? (absoluteChange > 0 ? 'improved' : 'regressed') : 'no_material_change', absoluteChange, relativeChange, material, causal: false });
}

function recommendationPriority({ impact = null, confidence = 'low', costMicros = null, risk = 'medium', customerPriority = 1, strategicFit = 1 }) {
  const impactValue = finite(impact, 'impact', true);
  const cost = costMicros == null ? null : finite(costMicros, 'costMicros');
  const confidenceWeight = { low: 0.35, medium: 0.65, high: 0.9 }[confidence];
  const riskWeight = { low: 1, medium: 0.75, high: 0.4 }[risk];
  if (confidenceWeight == null) throw new TypeError('invalid confidence');
  if (riskWeight == null) throw new TypeError('invalid risk');
  if (impactValue == null || cost == null || cost <= 0) return Object.freeze({ score: null, band: 'needs_estimate', inputs: Object.freeze({ impact: impactValue, confidence, costMicros: cost, risk, customerPriority, strategicFit }) });
  const score = (impactValue * confidenceWeight * riskWeight * customerPriority * strategicFit) / cost;
  return Object.freeze({ score, band: score >= 0.000005 ? 'high' : score >= 0.000001 ? 'medium' : 'low', inputs: Object.freeze({ impact: impactValue, confidence, costMicros: cost, risk, customerPriority, strategicFit }) });
}

function optimizationLoopState({ recommendation, changeIntent = null, verification = null, postChangeMeasurement = null }) {
  if (!isObject(recommendation)) throw new TypeError('recommendation is required');
  let state = recommendation.status ?? 'proposed';
  if (changeIntent) state = 'queued';
  if (verification?.status === 'PASS' || verification?.status === 'passed') state = 'implemented';
  if (postChangeMeasurement) state = 'measuring';
  if (postChangeMeasurement?.outcome === 'target_met' && (verification?.status === 'PASS' || verification?.status === 'passed')) state = 'validated';
  return Object.freeze({ state, productionMutationAuthorized: false, authority: 'proposal_and_measurement_only' });
}

module.exports = {
  compareVersionOutcomes,
  governedChangeIntent,
  optimizationLoopState,
  recommendationPriority,
  versionOutcomeTimeline,
};
