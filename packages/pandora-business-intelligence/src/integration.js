'use strict';

function isObject(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function req(value, name) {
  if (typeof value !== 'string' || value.trim() === '') throw new TypeError(`${name} is required`);
  return value;
}

function businessIntelligenceReadiness({ objective, instrumentationVerification, measurement, outcome, economics }) {
  const objectiveConfigured = isObject(objective) && typeof (objective.successMetric ?? objective.success_metric) === 'string' && (objective.successMetric ?? objective.success_metric).trim() !== '';
  const instrumentationVerified = instrumentationVerification?.status === 'PASS' || instrumentationVerification?.status === 'passed';
  const receivingData = measurement?.value != null || (measurement?.sampleSize ?? measurement?.sample_size ?? 0) > 0;
  const measurementFresh = measurement?.stale !== true;
  const outcomeMeasured = isObject(outcome) && !['not_measurable', 'awaiting_data', 'inconclusive'].includes(outcome.state);
  const economicsKnown = economics?.complete === true || economics?.totalCostMicros != null || economics?.total_cost_micros != null;
  const state = !objectiveConfigured ? 'not_configured'
    : !instrumentationVerified ? 'configured'
      : !receivingData ? 'awaiting_data'
        : !measurementFresh ? 'stale'
          : 'ready';
  return Object.freeze({ objectiveConfigured, instrumentationVerified, receivingData, measurementFresh, outcomeMeasured, economicsKnown, state });
}

function proveWorkerHFlow({ scope, objective, instrumentationVerification, measurement, outcome, economics, budgetSignal, recommendation = null, changeIntent = null }) {
  if (!isObject(scope)) throw new TypeError('scope is required');
  const organizationId = req(scope.organizationId, 'scope.organizationId');
  const projectId = req(scope.projectId, 'scope.projectId');
  for (const record of [objective, measurement, outcome, economics, recommendation]) {
    if (!isObject(record)) continue;
    const org = record.organizationId ?? record.organization_id;
    const project = record.projectId ?? record.project_id;
    if (org != null && org !== organizationId) throw new Error('CROSS_ORG_ACCESS');
    if (project != null && project !== projectId) throw new Error('CROSS_PROJECT_ACCESS');
  }
  const readiness = businessIntelligenceReadiness({ objective, instrumentationVerification, measurement, outcome, economics });
  const recommendationGoverned = recommendation == null || (changeIntent?.requiresWorkerLifecycle === true && changeIntent?.productionMutationAuthorized === false);
  const budgetFailClosed = budgetSignal == null || typeof budgetSignal.exhausted === 'boolean';
  return Object.freeze({
    organizationId,
    projectId,
    readiness,
    objectiveToMeasurementProved: readiness.objectiveConfigured && readiness.instrumentationVerified && readiness.receivingData,
    outcomeAssessmentProved: readiness.outcomeMeasured,
    economicsAssessmentProved: readiness.economicsKnown,
    budgetPolicyContractProved: budgetFailClosed,
    recommendationGovernanceProved: recommendationGoverned,
    productionMutationAuthorized: false,
    pass: readiness.state === 'ready' && recommendationGoverned && budgetFailClosed,
  });
}

function noDataProof({ objectiveConfigured = true, instrumentationVerified = true, providerEventObserved = false }) {
  const state = !objectiveConfigured ? 'not_configured' : !instrumentationVerified ? 'configured' : providerEventObserved ? 'receiving_data' : 'awaiting_data';
  return Object.freeze({
    state,
    value: null,
    label: providerEventObserved ? 'measurement_available' : 'not_measured',
    zeroAssumed: false,
    successAssumed: false,
    providerEventObserved: providerEventObserved === true,
  });
}

module.exports = { businessIntelligenceReadiness, noDataProof, proveWorkerHFlow };
