'use strict';

const MODEL_TASKS = Object.freeze([
  'understand_intent', 'compile_project_spec', 'classify_task', 'plan_build',
  'design_experience', 'plan_architecture', 'generate_code', 'repair_code',
  'inspect_error', 'inspect_visual', 'write_copy', 'summarize_context',
  'extract_structure', 'derive_acceptance_tests',
]);
const OUTPUT_MODES = Object.freeze(['text', 'json', 'structured', 'tool_proposals']);
const LATENCY_CLASSES = Object.freeze(['interactive', 'standard', 'batch']);
const COST_CLASSES = Object.freeze(['low', 'medium', 'high']);
const RELIABILITY_CLASSES = Object.freeze(['experimental', 'standard', 'high']);
const MODEL_ERROR_CODES = Object.freeze(['provider_unavailable','timeout','rate_limited','authentication_failed','invalid_request','context_too_large','structured_output_invalid','unsupported_capability','budget_exhausted','provider_error']);

/** @param {unknown} value @param {readonly string[]} allowed @param {string} field */
function requireEnum(value, allowed, field) {
  if (typeof value !== 'string' || !allowed.includes(value)) throw new TypeError(`${field} must be one of: ${allowed.join(', ')}`);
  return value;
}
/** @param {unknown} value @param {string} field */
function requireString(value, field) {
  if (typeof value !== 'string' || value.trim() === '') throw new TypeError(`${field} must be a non-empty string`);
  return value;
}
/** @param {unknown} value @param {string} field */
function requireObject(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return /** @type {Record<string, unknown>} */ (value);
}
/** @param {Record<string, unknown>} input */
function createModelRequest(input) {
  const task = requireEnum(input.task, MODEL_TASKS, 'task');
  const outputMode = requireEnum(input.outputMode ?? 'structured', OUTPUT_MODES, 'outputMode');
  const context = requireObject(input.context ?? {}, 'context');
  const budget = requireObject(input.budget ?? {}, 'budget');
  const requiredCapabilities = Array.isArray(input.requiredCapabilities) ? input.requiredCapabilities.map((item,index)=>requireString(item,`requiredCapabilities[${index}]`)) : [];
  const maxAttempts = positiveIntegerOrDefault(budget.maxAttempts, 1, 'budget.maxAttempts');
  return Object.freeze({
    requestId: requireString(input.requestId, 'requestId'), task, outputMode, context,
    input: input.input ?? null, schema: input.schema ?? null,
    requiredCapabilities: Object.freeze(requiredCapabilities),
    budget: Object.freeze({
      maxInputTokens: positiveIntegerOrNull(budget.maxInputTokens,'budget.maxInputTokens'),
      maxOutputTokens: positiveIntegerOrNull(budget.maxOutputTokens,'budget.maxOutputTokens'),
      maxAttempts,
      remainingAttempts: nonNegativeIntegerOrDefault(budget.remainingAttempts,maxAttempts,'budget.remainingAttempts'),
      maxCostUsd: nonNegativeNumberOrNull(budget.maxCostUsd,'budget.maxCostUsd'),
      deadlineMs: positiveIntegerOrNull(budget.deadlineMs,'budget.deadlineMs'),
    }),
    metadata: Object.freeze(requireObject(input.metadata ?? {}, 'metadata')),
  });
}
/** @param {unknown} value @param {string} field */
function positiveIntegerOrNull(value, field) { if (value==null) return null; if (!Number.isInteger(value)||Number(value)<=0) throw new TypeError(`${field} must be a positive integer`); return Number(value); }
/** @param {unknown} value @param {number} fallback @param {string} field */
function positiveIntegerOrDefault(value,fallback,field) { if (value==null) return fallback; const parsed=positiveIntegerOrNull(value,field); return parsed===null?fallback:parsed; }
/** @param {unknown} value @param {number} fallback @param {string} field */
function nonNegativeIntegerOrDefault(value,fallback,field) { if (value==null) return fallback; if (!Number.isInteger(value)||Number(value)<0) throw new TypeError(`${field} must be a non-negative integer`); return Number(value); }
/** @param {unknown} value @param {string} field */
function nonNegativeNumberOrNull(value,field) { if (value==null) return null; if (typeof value!=='number'||!Number.isFinite(value)||value<0) throw new TypeError(`${field} must be a non-negative number`); return value; }
/** @param {Record<string, unknown>} input */
function createModelError(input) { return Object.freeze({code:requireEnum(input.code,MODEL_ERROR_CODES,'code'),message:requireString(input.message,'message'),provider:typeof input.provider==='string'?input.provider:null,model:typeof input.model==='string'?input.model:null,retryable:input.retryable===true,retryAfterMs:positiveIntegerOrNull(input.retryAfterMs,'retryAfterMs'),details:Object.freeze(requireObject(input.details??{},'details'))}); }
/** @param {Record<string, unknown>} input */
function createModelUsage(input={}) { return Object.freeze({inputTokens:nonNegativeIntegerOrDefault(input.inputTokens,0,'inputTokens'),outputTokens:nonNegativeIntegerOrDefault(input.outputTokens,0,'outputTokens'),totalTokens:nonNegativeIntegerOrDefault(input.totalTokens,0,'totalTokens'),estimatedCostUsd:nonNegativeNumberOrNull(input.estimatedCostUsd,'estimatedCostUsd')}); }
module.exports={COST_CLASSES,LATENCY_CLASSES,MODEL_ERROR_CODES,MODEL_TASKS,OUTPUT_MODES,RELIABILITY_CLASSES,createModelError,createModelRequest,createModelUsage};
