'use strict';

function isObject(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function text(value, name, nullable = false) {
  if (value == null && nullable) return null;
  if (typeof value !== 'string' || value.trim() === '') throw new TypeError(`${name} is required`);
  return value;
}
function parsePlainDecimal(value) {
  if (typeof value !== 'string' || value.length === 0 || value.length > 128) return null;
  let index = 0;
  if (value[0] === '-') {
    index = 1;
    if (index === value.length) return null;
  }
  let digits = 0;
  let decimalPoints = 0;
  for (; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code >= 48 && code <= 57) {
      digits += 1;
      continue;
    }
    if (value[index] === '.' && decimalPoints === 0) {
      decimalPoints += 1;
      continue;
    }
    return null;
  }
  if (digits === 0) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}
function numericText(value) {
  if (value == null || typeof value !== 'string') return null;
  const trimmed = value.trim();
  const percentage = trimmed.endsWith('%');
  const token = percentage ? trimmed.slice(0, -1) : trimmed;
  const parsed = parsePlainDecimal(token);
  if (parsed == null) return null;
  return { value: percentage ? parsed / 100 : parsed, unit: percentage ? 'ratio' : 'number' };
}

function objectiveFromControlPlaneRow(row) {
  if (!isObject(row)) throw new TypeError('business objective row is required');
  const baselineText = row.baseline ?? null;
  const targetText = row.target ?? null;
  const baselineParsed = numericText(baselineText);
  const targetParsed = numericText(targetText);
  return Object.freeze({
    objectiveId: text(row.id, 'id'),
    organizationId: text(row.organization_id ?? row.organizationId, 'organizationId'),
    projectId: text(row.project_id ?? row.projectId, 'projectId'),
    projectSpecId: text(row.project_spec_id ?? row.projectSpecId, 'projectSpecId'),
    ordinal: row.ordinal ?? null,
    objective: text(row.objective, 'objective'),
    desiredOutcome: text(row.desired_outcome ?? row.desiredOutcome, 'desiredOutcome', true),
    successMetric: text(row.success_metric ?? row.successMetric, 'successMetric', true),
    baseline: Object.freeze({ raw: baselineText, value: baselineParsed?.value ?? null, unit: baselineParsed?.unit ?? null, parsed: baselineParsed != null }),
    target: Object.freeze({ raw: targetText, value: targetParsed?.value ?? null, unit: targetParsed?.unit ?? null, parsed: targetParsed != null }),
    provenance: Object.freeze(isObject(row.provenance) ? { ...row.provenance } : {}),
  });
}

function measurementDefinitionFromObjective(objective, metricRegistry) {
  if (!isObject(objective)) throw new TypeError('objective is required');
  if (!objective.successMetric) return Object.freeze({ configured: false, reason: 'success_metric_missing', metric: null });
  const normalizedKey = String(objective.successMetric).trim().toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
  const registryMetric = metricRegistry?.get ? metricRegistry.get(normalizedKey) : metricRegistry?.[normalizedKey] ?? null;
  return Object.freeze({ configured: registryMetric != null, reason: registryMetric ? null : 'metric_not_registered', metricKey: normalizedKey, metric: registryMetric ?? null });
}

module.exports = { measurementDefinitionFromObjective, numericText, objectiveFromControlPlaneRow };
