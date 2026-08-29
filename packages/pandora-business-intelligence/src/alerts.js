'use strict';

function budgetAlert(signal) {
  if (!signal || typeof signal !== 'object') throw new TypeError('budget signal is required');
  if (signal.exhausted === true) return Object.freeze({ severity: 'critical', code: 'budget_exhausted', notify: true, action: 'stop_or_require_approval' });
  if (signal.requires_approval_for_extra_spend === true) return Object.freeze({ severity: 'warning', code: 'budget_near_limit', notify: true, action: 'require_approval_for_extra_spend' });
  return Object.freeze({ severity: 'none', code: 'budget_ok', notify: false, action: null });
}

function measurementAlert({ measurementState, stale = false, quality = 'valid' }) {
  if (quality === 'invalid' || quality === 'schema_mismatch') return Object.freeze({ severity: 'critical', code: 'measurement_broken', notify: true });
  if (stale === true) return Object.freeze({ severity: 'warning', code: 'measurement_stale', notify: true });
  if (['not_configured', 'configured', 'awaiting_data'].includes(measurementState)) return Object.freeze({ severity: 'info', code: 'measurement_not_ready', notify: false });
  return Object.freeze({ severity: 'none', code: 'measurement_ready', notify: false });
}

function dataQualityAlert(report) {
  if (!report || typeof report !== 'object') throw new TypeError('data quality report is required');
  const issues = Array.isArray(report.issues) ? report.issues : [];
  const severe = issues.filter((issue) => ['wrong_attribution', 'schema_change', 'impossible_value', 'malformed_event'].includes(issue.type));
  const duplicates = issues.filter((issue) => issue.type === 'duplicate_event');
  if (severe.length > 0) return Object.freeze({ severity: 'critical', code: 'analytics_data_invalid', notify: true, issueCount: issues.length });
  if (duplicates.length > 0) return Object.freeze({ severity: 'warning', code: 'analytics_duplicates_suspected', notify: true, issueCount: issues.length });
  return Object.freeze({ severity: 'none', code: 'analytics_data_valid', notify: false, issueCount: 0 });
}

function outcomeAlert({ state, material = false }) {
  if (state === 'regressed' && material) return Object.freeze({ severity: 'warning', code: 'material_outcome_regression', notify: true });
  if (state === 'target_met' || state === 'target_exceeded') return Object.freeze({ severity: 'info', code: 'target_reached', notify: true });
  return Object.freeze({ severity: 'none', code: 'no_material_outcome_alert', notify: false });
}

module.exports = { budgetAlert, dataQualityAlert, measurementAlert, outcomeAlert };
