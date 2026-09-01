'use strict';

const VALIDATOR_REGISTRY_VERSION = 'pandora-kimi-validator-registry-v1';
/** @typedef {{executor: string, deterministic: boolean}} ValidatorDescriptor */
/** @type {Readonly<Record<string, ValidatorDescriptor>>} */
const VALIDATOR_REGISTRY = Object.freeze({
  unit_tests: Object.freeze({ executor: 'sandbox', deterministic: true }),
  forbidden_change_scan: Object.freeze({ executor: 'sandbox', deterministic: true }),
  typecheck: Object.freeze({ executor: 'sandbox', deterministic: true }),
  api_surface_check: Object.freeze({ executor: 'sandbox', deterministic: true }),
  contract_tests: Object.freeze({ executor: 'sandbox', deterministic: true }),
  citation_reference_check: Object.freeze({ executor: 'evidence', deterministic: true }),
  constraint_coverage_check: Object.freeze({ executor: 'evidence', deterministic: true }),
  hallucinated_path_check: Object.freeze({ executor: 'evidence', deterministic: true }),
  decision_continuity_check: Object.freeze({ executor: 'evidence', deterministic: true }),
  json_parse: Object.freeze({ executor: 'builtin', deterministic: true }),
  json_schema: Object.freeze({ executor: 'builtin', deterministic: true }),
  tool_allowlist: Object.freeze({ executor: 'builtin', deterministic: true }),
  no_invented_fields: Object.freeze({ executor: 'evidence', deterministic: true }),
  visual_fixture_claim_check: Object.freeze({ executor: 'visual_fixture', deterministic: true }),
  security_fixture_check: Object.freeze({ executor: 'sandbox', deterministic: true }),
  migration_preflight: Object.freeze({ executor: 'sandbox', deterministic: true }),
});

/** @param {unknown} value @returns {value is Record<string, any>} */
function isRecord(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }
/** @param {unknown} value @returns {Record<string, any> | null} */
function outputObject(value) {
  if (isRecord(value)) return value;
  if (typeof value === 'string') {
    try { const parsed = JSON.parse(value); return isRecord(parsed) ? parsed : null; }
    catch { return null; }
  }
  return null;
}
/** @param {unknown} value @param {Record<string, any>} schema */
function validateRequiredSchema(value, schema) {
  const object = outputObject(value);
  if (!object) return { status: 'FAIL', reason: 'not_object' };
  const required = Array.isArray(schema?.required) ? schema.required.map(String) : [];
  for (const key of required) if (!Object.hasOwn(object, key)) return { status: 'FAIL', reason: `missing_required:${key}` };
  if (schema?.additionalProperties === false) {
    const allowedKeys = isRecord(schema.properties) ? Object.keys(schema.properties) : required;
    const allowed = new Set(allowedKeys);
    for (const key of Object.keys(object)) if (!allowed.has(key)) return { status: 'FAIL', reason: `unexpected_field:${key}` };
  }
  return { status: 'PASS', reason: null };
}

/**
 * @param {Record<string, any>} benchmarkCase
 * @param {unknown} output
 * @param {{externalValidators?: Record<string, (input: Record<string, any>) => Promise<Record<string, any>> | Record<string, any>>}} [options]
 */
async function runDeterministicValidators(benchmarkCase, output, options = {}) {
  const validators = Array.isArray(benchmarkCase?.deterministicValidators) ? benchmarkCase.deterministicValidators : [];
  const external = isRecord(options.externalValidators) ? options.externalValidators : {};
  const results = [];
  for (const validator of validators) {
    const descriptor = VALIDATOR_REGISTRY[validator];
    if (!descriptor) {
      results.push(Object.freeze({ validator, status: 'BLOCKED', reason: 'unknown_validator' }));
      continue;
    }
    if (validator === 'json_parse') {
      let status = 'PASS';
      try { if (typeof output === 'string') JSON.parse(output); else if (!isRecord(output)) throw new Error('not_json_object'); }
      catch { status = 'FAIL'; }
      results.push(Object.freeze({ validator, status, reason: status === 'PASS' ? null : 'invalid_json' }));
      continue;
    }
    if (validator === 'json_schema') {
      const result = validateRequiredSchema(output, benchmarkCase.structuredOutputSchema ?? {});
      results.push(Object.freeze({ validator, ...result }));
      continue;
    }
    if (validator === 'tool_allowlist') {
      const object = outputObject(output);
      const tool = object && typeof object.tool === 'string' ? object.tool : null;
      const allowed = Array.isArray(benchmarkCase.allowedTools) ? benchmarkCase.allowedTools : [];
      const passed = tool != null && allowed.includes(tool);
      results.push(Object.freeze({ validator, status: passed ? 'PASS' : 'FAIL', reason: passed ? null : 'tool_not_allowed' }));
      continue;
    }
    const executor = external[validator];
    if (typeof executor !== 'function') {
      results.push(Object.freeze({ validator, status: 'BLOCKED', reason: `executor_unavailable:${descriptor.executor}` }));
      continue;
    }
    const result = await executor(Object.freeze({ benchmarkCase, output, validator, descriptor }));
    const status = String(result?.status ?? 'BLOCKED').toUpperCase();
    if (!['PASS','FAIL','BLOCKED','INCONCLUSIVE'].includes(status)) throw new Error(`invalid validator status for ${validator}`);
    results.push(Object.freeze({ validator, status, reason: result?.reason ? String(result.reason) : null, evidenceRef: result?.evidenceRef ? String(result.evidenceRef) : null }));
  }
  return Object.freeze(results);
}

module.exports = Object.freeze({ VALIDATOR_REGISTRY_VERSION, VALIDATOR_REGISTRY, runDeterministicValidators });
