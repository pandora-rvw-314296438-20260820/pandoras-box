'use strict';

const { assertNoCredentialMaterial } = require('../security/secret-boundary.js');

const FALLBACK_CODES = Object.freeze(new Set([
  'provider_unavailable',
  'timeout',
  'rate_limited',
  'quota_exhausted',
  'unsupported_capability',
  'structured_output_invalid',
  'invalid_output',
  'low_confidence',
  'provider_error',
]));
const RESULT_REJECTION_CODES = Object.freeze(new Set(['low_confidence', 'invalid_output']));

/** @param {unknown} value */
function isRecord(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }
/** @param {unknown} value @param {string} field */
function requiredText(value, field) { if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`); return value.trim(); }

/** @param {string} requestId @param {string} provider @param {string} model */
function modelAttemptKey(requestId, provider, model) {
  return `${requiredText(requestId, 'requestId')}::${requiredText(provider, 'provider')}::${requiredText(model, 'model')}`;
}

/**
 * Bind resume history to one exact model request so a retry cannot accidentally consume another request's attempt ledger.
 * Legacy records without requestId/attemptKey are accepted only as belonging to the current request and are normalized immediately.
 * @param {string} requestId
 * @param {readonly Record<string,unknown>[]|undefined} history
 * @returns {ReadonlyArray<Readonly<Record<string,unknown>>>}
 */
function normalizeAttemptHistory(requestId, history) {
  const exactRequestId = requiredText(requestId, 'requestId');
  if (history == null) return Object.freeze([]);
  if (!Array.isArray(history)) throw new TypeError('attemptHistory must be an array');
  assertNoCredentialMaterial(history);
  return Object.freeze(history.map((item, index) => {
    if (!isRecord(item)) throw new TypeError(`attemptHistory[${index}] must be an object`);
    const provider = requiredText(item.provider, `attemptHistory[${index}].provider`);
    const model = requiredText(item.model, `attemptHistory[${index}].model`);
    const itemRequestId = item.requestId == null ? exactRequestId : requiredText(item.requestId, `attemptHistory[${index}].requestId`);
    if (itemRequestId !== exactRequestId) throw new TypeError('attemptHistory requestId does not match the current model request');
    const attemptKey = modelAttemptKey(exactRequestId, provider, model);
    if (item.attemptKey != null && String(item.attemptKey) !== attemptKey) throw new TypeError('attemptHistory attemptKey does not match its request/provider/model identity');
    return Object.freeze({ ...item, requestId: exactRequestId, provider, model, attemptKey });
  }));
}

/** @param {unknown} error */
function fallbackEligible(error) {
  if (!isRecord(error)) return false;
  const failure = /** @type {Readonly<Record<string,unknown>>} */ (error);
  const code = typeof failure.code === 'string' ? failure.code : '';
  if (!FALLBACK_CODES.has(code) || failure.crossProviderEligible === false) return false;
  if (code === 'unsupported_capability') return true;
  return failure.retryable === true;
}

/**
 * Only a trusted caller-supplied evaluator can reject an otherwise successful model result for low confidence/invalid output.
 * Model self-reported confidence is never routing authority by itself.
 * @param {((result:Readonly<Record<string,unknown>>,context:Readonly<Record<string,unknown>>)=>unknown|Promise<unknown>)|undefined} evaluator
 * @param {Readonly<Record<string,unknown>>} result
 * @param {Readonly<Record<string,unknown>>} context
 * @returns {Promise<Readonly<{accepted:boolean,code:string|null,reason:string|null}>>}
 */
async function evaluateProviderResult(evaluator, result, context) {
  if (evaluator == null) return Object.freeze({ accepted: true, code: null, reason: null });
  if (typeof evaluator !== 'function') throw new TypeError('resultEvaluator must be a function');
  const raw = await evaluator(result, context);
  assertNoCredentialMaterial(raw);
  if (!isRecord(raw) || typeof raw.accepted !== 'boolean') throw new TypeError('resultEvaluator must return { accepted: boolean, code?, reason? }');
  if (raw.accepted) return Object.freeze({ accepted: true, code: null, reason: null });
  const code = raw.code == null ? 'low_confidence' : String(raw.code);
  if (!RESULT_REJECTION_CODES.has(code)) throw new TypeError('resultEvaluator rejection code must be low_confidence or invalid_output');
  const reason = typeof raw.reason === 'string' && raw.reason.trim() ? raw.reason.trim().slice(0, 160) : code;
  return Object.freeze({ accepted: false, code, reason });
}

/** @param {Readonly<{accepted:boolean,code:string|null,reason:string|null}>} evaluation */
function resultRejectionError(evaluation) {
  if (evaluation.accepted || !evaluation.code) throw new TypeError('accepted result cannot become a fallback rejection');
  const message = evaluation.code === 'invalid_output' ? 'model result failed trusted validation' : 'model result did not meet trusted confidence threshold';
  return Object.assign(new Error(message), {
    code: evaluation.code,
    retryable: true,
    crossProviderEligible: true,
    safeDetails: Object.freeze({ kind: evaluation.code, reason: evaluation.reason }),
  });
}

module.exports = {
  FALLBACK_CODES,
  RESULT_REJECTION_CODES,
  evaluateProviderResult,
  fallbackEligible,
  modelAttemptKey,
  normalizeAttemptHistory,
  resultRejectionError,
};
