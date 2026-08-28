'use strict';
function measurementReadiness(input) {
  if (!input.objective?.primaryMetricKey) return { state:'not_configured', reasons:['primary metric not configured'] };
  if (!input.metricDefinition) return { state:'broken', reasons:['metric definition missing'] };
  if (!input.instrumentationVerified) return { state:'configured', reasons:['instrumentation not independently verified'] };
  if (!input.querySucceeded) return { state:'broken', reasons:['metric query failed'] };
  if (!input.receivingData) return { state:'configured', reasons:['no events received yet'] };
  if (input.attributionComplete !== true) return { state:'receiving_data', reasons:['project/version attribution incomplete'] };
  if (input.stale === true) return { state:'stale', reasons:['latest observation exceeds freshness threshold'] };
  return { state:'ready', reasons:[] };
}
module.exports = { measurementReadiness };
