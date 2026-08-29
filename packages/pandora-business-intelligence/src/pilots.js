'use strict';

const { grossMargin, roiAssessment } = require('./economics.js');

function object(value, name) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${name} must be an object`);
  return value;
}
function text(value, name) {
  if (typeof value !== 'string' || value.trim() === '') throw new TypeError(`${name} is required`);
  return value;
}
function integer(value, name, nullable = false) {
  if (value == null && nullable) return null;
  if (!Number.isSafeInteger(value) || value < 0) throw new TypeError(`${name} must be a non-negative safe integer`);
  return value;
}
function finite(value, name, nullable = false) {
  if (value == null && nullable) return null;
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new TypeError(`${name} must be finite`);
  return value;
}

function createPilotDefinition(input) {
  const value = object(input, 'pilot');
  return Object.freeze({
    pilotId: text(value.pilotId, 'pilotId'),
    organizationId: text(value.organizationId, 'organizationId'),
    projectId: text(value.projectId, 'projectId'),
    customerClass: text(value.customerClass ?? 'unknown', 'customerClass'),
    paid: value.paid === true,
    priceMicros: integer(value.priceMicros ?? 0, 'priceMicros'),
    startedAt: value.startedAt ?? null,
    targetOutcome: value.targetOutcome ?? null,
    minimumObservationDays: integer(value.minimumObservationDays ?? 14, 'minimumObservationDays'),
  });
}

function evaluatePilot({ definition: rawDefinition, observedRevenueMicros = null, internalCostMicros = null, creditsMicros = 0, outcome = null, retention = null, observationDays = 0, assumptions = [] }) {
  const definition = createPilotDefinition(rawDefinition);
  const revenue = integer(observedRevenueMicros, 'observedRevenueMicros', true);
  const cost = integer(internalCostMicros, 'internalCostMicros', true);
  const credits = integer(creditsMicros, 'creditsMicros');
  const days = integer(observationDays, 'observationDays');
  const margin = grossMargin({ customerChargeMicros: revenue, creditsMicros: credits, internalCostMicros: cost });
  const retentionState = retention?.applicable === false
    ? 'not_applicable'
    : retention?.measured === true
      ? 'measured'
      : 'not_measured';
  const outcomeState = outcome?.state ?? 'not_measured';
  const sufficientWindow = days >= definition.minimumObservationDays;
  return Object.freeze({
    pilotId: definition.pilotId,
    organizationId: definition.organizationId,
    projectId: definition.projectId,
    customerClass: definition.customerClass,
    paid: definition.paid,
    observedRevenueMicros: revenue,
    internalCostMicros: cost,
    creditsMicros: credits,
    margin,
    outcomeState,
    retentionState,
    observationDays: days,
    sufficientWindow,
    validated: definition.paid && sufficientWindow && outcomeState === 'target_met' && margin.complete && margin.marginMicros > 0,
    assumptions: Object.freeze(Array.isArray(assumptions) ? assumptions.map(String) : []),
  });
}

function cohortEconomics(pilots, { organizationId, customerClass = null } = {}) {
  if (!Array.isArray(pilots)) throw new TypeError('pilots must be an array');
  const rows = pilots.map((pilot) => object(pilot, 'pilot result'));
  for (const row of rows) {
    if (row.organizationId !== organizationId) throw new Error('CROSS_ORG_ACCESS');
  }
  const filtered = customerClass == null ? rows : rows.filter((row) => row.customerClass === customerClass || row.definition?.customerClass === customerClass);
  const knownRevenue = filtered.every((row) => row.observedRevenueMicros != null);
  const knownCost = filtered.every((row) => row.internalCostMicros != null);
  const revenueMicros = knownRevenue ? filtered.reduce((sum, row) => sum + row.observedRevenueMicros, 0) : null;
  const costMicros = knownCost ? filtered.reduce((sum, row) => sum + row.internalCostMicros, 0) : null;
  const paidPilots = filtered.filter((row) => row.paid === true).length;
  const validatedPilots = filtered.filter((row) => row.validated === true).length;
  return Object.freeze({
    organizationId,
    customerClass,
    pilotCount: filtered.length,
    paidPilots,
    validatedPilots,
    paidConversionRate: filtered.length === 0 ? null : paidPilots / filtered.length,
    validationRate: filtered.length === 0 ? null : validatedPilots / filtered.length,
    revenueMicros,
    costMicros,
    grossMargin: grossMargin({ customerChargeMicros: revenueMicros, internalCostMicros: costMicros }),
  });
}

function manualHoursValue({ hoursSaved = null, hourlyValueMicros = null, evidence = [], confidence = 'estimated' }) {
  const hours = finite(hoursSaved, 'hoursSaved', true);
  const hourly = integer(hourlyValueMicros, 'hourlyValueMicros', true);
  if (!Array.isArray(evidence)) throw new TypeError('evidence must be an array');
  return Object.freeze({
    hoursSaved: hours,
    hourlyValueMicros: hourly,
    valueMicros: hours == null || hourly == null ? null : Math.round(hours * hourly),
    confidence: hours == null || hourly == null ? 'unknown' : confidence,
    evidence: Object.freeze(evidence.map(String)),
    causal: false,
  });
}

function pilotRoi({ pilotResult, benefitMicros = null, assumptions = [] }) {
  const pilot = object(pilotResult, 'pilotResult');
  return roiAssessment({
    benefitMicros,
    costMicros: pilot.internalCostMicros,
    benefitConfidence: benefitMicros == null ? 'unknown' : 'estimated',
    costConfidence: pilot.internalCostMicros == null ? 'unknown' : 'actual',
    assumptions,
  });
}

module.exports = {
  cohortEconomics,
  createPilotDefinition,
  evaluatePilot,
  manualHoursValue,
  pilotRoi,
};
