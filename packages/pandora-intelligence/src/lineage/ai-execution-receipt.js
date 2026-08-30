
'use strict';

const crypto = require('node:crypto');
const { assertNoCredentialMaterial } = require('../security/secret-boundary.js');

/** @param {unknown} value @returns {string} */
function stableJson(value) {
  if (value === undefined) return 'null';
  if (value === null || typeof value !== 'object') {
    const encoded = JSON.stringify(value);
    return encoded === undefined ? 'null' : encoded;
  }
  if (Array.isArray(value)) return `[${value.map((item) => stableJson(item)).join(',')}]`;
  const record = /** @type {Record<string, unknown>} */ (value);
  return `{${Object.keys(record).sort().map((key) => `${JSON.stringify(key)}:${stableJson(record[key])}`).join(',')}}`;
}

/** @param {unknown} value */
function digestValue(value) {
  return `sha256:${crypto.createHash('sha256').update(stableJson(value)).digest('hex')}`;
}

/** @param {unknown} value @param {string} field */
function requiredText(value, field) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`);
  return value.trim();
}

/** @param {unknown} value @param {string} field */
function optionalText(value, field) {
  if (value == null) return null;
  return requiredText(value, field);
}

/** @param {unknown} value @param {string} field */
function nonNegativeNumber(value, field) {
  if (value == null) return 0;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) throw new TypeError(`${field} must be a non-negative number`);
  return value;
}

/** @param {unknown} value @param {string} field */
function nonNegativeInteger(value, field) {
  const number = nonNegativeNumber(value, field);
  if (!Number.isInteger(number)) throw new TypeError(`${field} must be a non-negative integer`);
  return number;
}

/** @param {unknown} value @param {string} field */
function exactRefs(value, field) {
  if (value == null) return [];
  if (!Array.isArray(value)) throw new TypeError(`${field} must be an array`);
  return value.map((item, index) => {
    if (!item || typeof item !== 'object' || Array.isArray(item)) throw new TypeError(`${field}[${index}] must be an object`);
    const ref = /** @type {Record<string, unknown>} */ (item);
    const id = requiredText(ref.id, `${field}[${index}].id`);
    const version = requiredText(ref.version, `${field}[${index}].version`);
    return Object.freeze({ id, version, digest: optionalText(ref.digest, `${field}[${index}].digest`) });
  });
}

/** @param {unknown} value */
function modelRoute(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('model is required');
  const input = /** @type {Record<string, unknown>} */ (value);
  return Object.freeze({
    provider: requiredText(input.provider, 'model.provider'),
    modelId: requiredText(input.modelId, 'model.modelId'),
    routeReason: optionalText(input.routeReason, 'model.routeReason'),
    fallbackUsed: input.fallbackUsed === true,
    attempts: input.attempts == null ? 1 : nonNegativeInteger(input.attempts, 'model.attempts'),
  });
}

/** @param {unknown} value */
function usage(value) {
  if (value == null) return Object.freeze({ inputTokens: 0, outputTokens: 0, totalTokens: 0, estimatedCostUsd: 0, latencyMs: 0 });
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('usage must be an object');
  const input = /** @type {Record<string, unknown>} */ (value);
  return Object.freeze({
    inputTokens: nonNegativeInteger(input.inputTokens, 'usage.inputTokens'),
    outputTokens: nonNegativeInteger(input.outputTokens, 'usage.outputTokens'),
    totalTokens: nonNegativeInteger(input.totalTokens, 'usage.totalTokens'),
    estimatedCostUsd: nonNegativeNumber(input.estimatedCostUsd, 'usage.estimatedCostUsd'),
    latencyMs: nonNegativeInteger(input.latencyMs, 'usage.latencyMs'),
  });
}

/**
 * Builds a durable, secret-free receipt. Raw prompts and raw model output are intentionally omitted;
 * only exact digests and bounded lineage references are retained.
 * @param {Record<string, unknown>} input
 */
function createAiExecutionReceipt(input) {
  assertNoCredentialMaterial(input);
  const inputDigest = typeof input.inputDigest === 'string' && input.inputDigest.trim()
    ? input.inputDigest.trim()
    : digestValue(input.input ?? null);
  const outputDigest = typeof input.outputDigest === 'string' && input.outputDigest.trim()
    ? input.outputDigest.trim()
    : digestValue(input.output ?? null);

  const base = Object.freeze({
    executionId: requiredText(input.executionId, 'executionId'),
    projectId: requiredText(input.projectId, 'projectId'),
    projectVersionId: optionalText(input.projectVersionId, 'projectVersionId'),
    task: requiredText(input.task, 'task'),
    requestId: optionalText(input.requestId, 'requestId'),
    skills: Object.freeze(exactRefs(input.skills, 'skills')),
    knowledge: Object.freeze(exactRefs(input.knowledge, 'knowledge')),
    primitives: Object.freeze(exactRefs(input.primitives, 'primitives')),
    model: modelRoute(input.model),
    contextDigest: optionalText(input.contextDigest, 'contextDigest'),
    inputDigest,
    outputDigest,
    usage: usage(input.usage),
    verificationRequired: input.verificationRequired !== false,
    verificationEvidenceId: optionalText(input.verificationEvidenceId, 'verificationEvidenceId'),
    createdAt: input.createdAt == null ? new Date().toISOString() : new Date(requiredText(input.createdAt, 'createdAt')).toISOString(),
  });
  assertNoCredentialMaterial(base);
  return Object.freeze({ ...base, receiptDigest: digestValue(base) });
}

module.exports = {
  createAiExecutionReceipt,
  digestValue,
  stableJson,
};
