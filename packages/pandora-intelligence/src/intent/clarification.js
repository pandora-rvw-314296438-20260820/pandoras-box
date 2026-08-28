'use strict';

const INFRASTRUCTURE_FIELDS = Object.freeze([
  'framework', 'frontend_framework', 'backend_framework', 'database', 'hosting',
  'deployment_provider', 'css_framework', 'state_management', 'package_manager',
]);

/** @param {unknown} value */
function isRecord(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }

/**
 * @param {unknown} uncertainties
 * @param {{maxQuestions?:number}} options
 */
function decideClarifications(uncertainties, options = {}) {
  const items = Array.isArray(uncertainties) ? uncertainties : [];
  const maxQuestions = Number.isInteger(options.maxQuestions) && Number(options.maxQuestions) > 0 ? Number(options.maxQuestions) : 3;
  /** @type {Readonly<Record<string, unknown>>[]} */
  const resolved = [];
  /** @type {Readonly<Record<string, unknown>>[]} */
  const blocking = [];

  for (const item of items) {
    if (!isRecord(item)) continue;
    const field = typeof item.field === 'string' ? item.field.trim() : '';
    if (!field) continue;
    const normalized = field.toLowerCase().replace(/[^a-z0-9]+/g, '_');
    const infrastructureChoice = INFRASTRUCTURE_FIELDS.includes(normalized);
    const safeInference = item.safeInference === true || infrastructureChoice;
    const hasDefault = item.defaultValue !== undefined && item.defaultValue !== null;
    const optional = item.optional === true;
    const trulyBlocking = item.blocking === true && !safeInference && !hasDefault && !optional;
    const record = Object.freeze({
      field,
      reason: typeof item.reason === 'string' ? item.reason : '',
      impact: typeof item.impact === 'string' ? item.impact : '',
      resolution: trulyBlocking ? 'ask_user' : safeInference ? 'infer' : hasDefault ? 'default' : optional ? 'optional' : 'non_blocking',
      defaultValue: hasDefault ? item.defaultValue : null,
      question: typeof item.question === 'string' ? item.question.trim() : '',
    });
    if (trulyBlocking) blocking.push(record); else resolved.push(record);
  }

  const questions = blocking.slice(0, maxQuestions).map((item) => ({
    field: item.field,
    question: item.question || `Please clarify ${item.field}.`,
    reason: item.reason,
    impact: item.impact,
  }));

  return Object.freeze({
    required: questions.length > 0,
    questions: Object.freeze(questions.map(Object.freeze)),
    blocking: Object.freeze(blocking),
    resolved: Object.freeze(resolved),
  });
}

module.exports = { INFRASTRUCTURE_FIELDS, decideClarifications };
