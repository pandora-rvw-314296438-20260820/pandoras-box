'use strict';
const { createMeasurement } = require('./contracts.js');

function assessOutcome({ objective, metric, measurement, previousMeasurement = null, now = new Date() }) {
  if (!objective.primaryMetricKey || !metric) return result('not_measurable','not_measured','Objective has no configured measurable metric');
  const observed = createMeasurement(measurement);
  if (observed.quality !== 'valid' && observed.quality !== 'partial') return result('inconclusive','needs_attention',`Measurement quality is ${observed.quality}`);
  if (observed.value == null || observed.sampleSize === 0) return result('awaiting_data','collecting_data','No measurement data yet');
  if (observed.sampleSize < metric.minimumSampleSize) return result('inconclusive','collecting_data',`Sample ${observed.sampleSize} is below required ${metric.minimumSampleSize}`);
  if (!observed.windowStart || !observed.windowEnd) return result('inconclusive','collecting_data','Observation window is incomplete');
  const durationSeconds = (Date.parse(observed.windowEnd) - Date.parse(observed.windowStart)) / 1000;
  if (durationSeconds < metric.minimumObservationSeconds) return result('inconclusive','collecting_data','Observation window is too short');
  if (observed.lastObservedAt && metric.freshnessSeconds > 0 && (now.getTime() - Date.parse(observed.lastObservedAt)) / 1000 > metric.freshnessSeconds) {
    return result('inconclusive','needs_attention','Measurement is stale');
  }
  const baseline = objective.baseline.value;
  const target = objective.target.value;
  if (target == null) {
    if (baseline == null) return result('inconclusive','collecting_data','Baseline and target are not defined');
    if (observed.value < baseline) return result('below_baseline','declining','Observed value is below baseline');
    if (observed.value > baseline) return result('inconclusive','improving','Observed value improved, but no target is defined');
    return result('inconclusive','on_track','Observed value matches baseline, but no target is defined');
  }
  if (previousMeasurement?.value != null && observed.value < previousMeasurement.value && observed.value < (baseline ?? target)) return result('regressed','declining','Metric regressed relative to prior observation');
  if (observed.value > target) return result('target_exceeded','target_reached','Target exceeded');
  if (observed.value === target) return result('target_met','target_reached','Target met');
  const directionUp = baseline == null || target >= baseline;
  if (baseline != null) {
    if (directionUp && observed.value < baseline) return result('below_baseline','declining','Metric is below baseline');
    if (!directionUp && observed.value > baseline) return result('below_baseline','declining','Metric is worse than baseline');
    const span = Math.abs(target - baseline);
    if (span > 0) {
      const progress = directionUp ? (observed.value - baseline) / span : (baseline - observed.value) / span;
      if (progress >= 0.8) return result('near_target','on_track','Metric is within 20% of the target range');
      if (progress > 0) return result('inconclusive','improving','Metric improved but target has not been reached');
    }
  }
  return result('inconclusive','needs_attention','Target not reached and evidence is insufficient for a stronger conclusion');
}
function result(state, health, explanation) { return Object.freeze({ state, health, explanation }); }

function compareVersions({ a, b, minimumSampleSize = 20, minimumRelativeDifference = 0.02 }) {
  if (!a || !b || a.value == null || b.value == null) return { state:'inconclusive', reason:'missing version measurement' };
  if (a.sampleSize < minimumSampleSize || b.sampleSize < minimumSampleSize) return { state:'inconclusive', reason:'insufficient sample size' };
  if (a.value === 0 && b.value === 0) return { state:'inconclusive', relativeDifference:0, causal:false };
  const denominator = Math.max(Math.abs(a.value), Number.EPSILON);
  const relativeDifference = (b.value - a.value) / denominator;
  if (Math.abs(relativeDifference) < minimumRelativeDifference) return { state:'inconclusive', relativeDifference, reason:'difference below materiality threshold', causal:false };
  return { state: relativeDifference > 0 ? 'improved' : 'regressed', relativeDifference, causal:false, reason:'temporal association only; causality not established' };
}
module.exports = { assessOutcome, compareVersions };
