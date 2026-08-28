'use strict';

const { createModelRequest } = require('../contracts/model.js');
const { validateProjectSpecCandidate } = require('../contracts/project-spec.js');
const { assertNoCredentialMaterial } = require('../security/secret-boundary.js');
const { getPromptTemplate } = require('../prompts/templates.js');
const { decideClarifications } = require('./clarification.js');

const INTENT_COMPILER_VERSION = '1.0.0';

/** @param {unknown} value */
function isRecord(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }
/** @param {unknown} value @param {string} field */
function requireText(value, field) { if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`); return value.trim(); }

/**
 * @param {Record<string, unknown>} input
 */
function createIntentCompilerRequest(input) {
  const rawIntent = requireText(input.rawIntent, 'rawIntent');
  if (rawIntent.length > 50000) throw new RangeError('rawIntent exceeds 50000 characters');
  const template = getPromptTemplate('intent_compilation');
  const context = {
    existingProjectSpec: input.existingProjectSpec ?? null,
    projectState: input.projectState ?? {},
    businessContext: input.businessContext ?? {},
    userDecisions: input.userDecisions ?? [],
    constraints: input.constraints ?? [],
    previousClarifications: input.previousClarifications ?? [],
    conversationContext: input.conversationContext ?? [],
  };
  assertNoCredentialMaterial(context);
  return createModelRequest({
    requestId: requireText(input.requestId, 'requestId'),
    task: 'compile_project_spec',
    outputMode: 'structured',
    requiredCapabilities: ['structuredOutput'],
    input: { rawIntent },
    context,
    schema: { id: 'pandora.intent_compilation.v1', output: ['projectSpec','uncertainties'] },
    budget: isRecord(input.budget) ? input.budget : {},
    metadata: {
      promptTemplateId: template.id,
      promptTemplateVersion: template.version,
      compilerVersion: INTENT_COMPILER_VERSION,
    },
  });
}

/** @param {unknown} output */
function validateIntentCompilationOutput(output) {
  if (!isRecord(output)) return { ok: false, errors: ['intent compilation output must be an object'], value: null };
  const root = /** @type {Record<string, unknown>} */ (output);
  const projectSpec = root.projectSpec ?? root.spec ?? null;
  const specValidation = validateProjectSpecCandidate(projectSpec);
  /** @type {string[]} */
  const errors = specValidation.ok ? [] : [...specValidation.errors];
  if (root.uncertainties !== undefined && !Array.isArray(root.uncertainties)) errors.push('uncertainties must be an array');
  if (errors.length) return { ok: false, errors, value: null };
  return { ok: true, errors: [], value: Object.freeze({ projectSpec: specValidation.value, uncertainties: Object.freeze(Array.isArray(root.uncertainties) ? root.uncertainties : []) }) };
}

/**
 * @param {{router:{execute:(request:Record<string,unknown>,options?:Record<string,unknown>)=>Promise<unknown>},request:Record<string,unknown>,routeOptions?:Record<string,unknown>,maxClarificationQuestions?:number}} input
 */
async function compileIntent(input) {
  assertNoCredentialMaterial(input.request);
  const result = await input.router.execute(input.request, input.routeOptions ?? {});
  if (!isRecord(result)) return Object.freeze({ ok: false, kind: 'invalid_model_result', errors: Object.freeze(['model router returned a non-object result']) });
  const normalized = /** @type {Record<string, unknown>} */ (result);
  const validated = validateIntentCompilationOutput(normalized.output);
  if (!validated.ok || !validated.value) {
    return Object.freeze({ ok: false, kind: 'invalid_structured_output', errors: Object.freeze(validated.errors), routing: routeMetadata(normalized) });
  }
  const value = /** @type {{projectSpec:unknown, uncertainties:unknown[]}} */ (validated.value);
  const clarification = decideClarifications(value.uncertainties, { maxQuestions: input.maxClarificationQuestions });
  return Object.freeze({
    ok: true,
    projectSpec: value.projectSpec,
    clarification,
    compilerVersion: INTENT_COMPILER_VERSION,
    routing: routeMetadata(normalized),
  });
}

/** @param {Record<string, unknown>} result */
function routeMetadata(result) {
  return Object.freeze({
    provider: typeof result.routedProvider === 'string' ? result.routedProvider : typeof result.provider === 'string' ? result.provider : null,
    model: typeof result.routedModel === 'string' ? result.routedModel : typeof result.model === 'string' ? result.model : null,
    fallbackUsed: result.fallbackUsed === true,
    attempts: Number.isInteger(result.attempts) ? result.attempts : 1,
    usage: result.usage ?? null,
  });
}

module.exports = { INTENT_COMPILER_VERSION, compileIntent, createIntentCompilerRequest, validateIntentCompilationOutput };
