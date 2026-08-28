'use strict';

class AnalyticsProvider {
  async captureEvent() { throw new Error('captureEvent not implemented'); }
  async queryMetric() { throw new Error('queryMetric not implemented'); }
  async queryFunnel() { throw new Error('queryFunnel not implemented'); }
  async queryRetention() { throw new Error('queryRetention not implemented'); }
  async queryCohort() { throw new Error('queryCohort not implemented'); }
  async queryTimeseries() { throw new Error('queryTimeseries not implemented'); }
  async queryExperiment() { throw new Error('queryExperiment not implemented'); }
}

function assertProviderScope(requestScope, resultScope) {
  for (const key of ['organizationId','projectId','environment']) {
    if (requestScope[key] !== resultScope[key]) throw new Error(`analytics scope mismatch: ${key}`);
  }
  if (requestScope.projectVersionId && resultScope.projectVersionId !== requestScope.projectVersionId) {
    throw new Error('analytics scope mismatch: projectVersionId');
  }
  return true;
}

module.exports = { AnalyticsProvider, assertProviderScope };
