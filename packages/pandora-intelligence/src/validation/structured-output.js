'use strict';

const TOOL_PROPOSAL_VERSION = 1;
const CANONICAL_TOOL_PROPOSALS = Object.freeze([
  'read_file',
  'write_file',
  'list_files',
  'query_schema',
  'request_migration',
  'request_build',
  'request_tests',
  'inspect_build_error',
  'create_preview',
  'inspect_preview',
  'request_publish',
]);
const LEGACY_TOOL_ALIASES = Object.freeze({
  run_build: 'request_build',
  run_tests: 'request_tests',
  publish_project: 'request_publish',
});
const ALLOWED_TOOL_PROPOSALS = Object.freeze([
  ...CANONICAL_TOOL_PROPOSALS,
  ...Object.keys(LEGACY_TOOL_ALIASES),
]);
const ALLOWED_PROPOSAL_FIELDS = Object.freeze([
  'tool',
  'version',
  'arguments',
  'reason',
  'requirement_refs',
]);
const BLOCKED_PATH_SEGMENTS = Object.freeze(['.git', '.env', 'node_modules', 'secrets', '.ssh']);
const DEFAULT_MAX_ARGUMENT_BYTES = 128 * 1024;

/** @param {unknown} value */
function isRecord(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

/** @param {string} path */
function isSafeRelativePath(path) {
  if (!path || path.length > 512 || path.startsWith('/') || path.includes('\\') || path.includes('\0')) return false;
  const segments = path.split('/');
  return !segments.some((segment) => segment === '..' || BLOCKED_PATH_SEGMENTS.includes(segment.toLowerCase()));
}

/** @param {string} tool */
function canonicalToolName(tool) {
  return LEGACY_TOOL_ALIASES[tool] ?? tool;
}

/** @param {unknown} proposal @param {{maxArgumentBytes?: number}} options */
function validateToolProposal(proposal, options = {}) {
  /** @type {string[]} */
  const errors = [];
  if (!isRecord(proposal)) return { ok: false, errors: ['tool proposal must be an object'], value: null };

  const record = /** @type {Record<string, unknown>} */ (proposal);
  for (const key of Object.keys(record)) {
    if (!ALLOWED_PROPOSAL_FIELDS.includes(key)) errors.push(`unknown tool proposal field: ${key}`);
  }

  const rawTool = typeof record.tool === 'string' ? record.tool : '';
  if (!ALLOWED_TOOL_PROPOSALS.includes(rawTool)) errors.push('unsupported tool proposal');
  const tool = canonicalToolName(rawTool);

  const version = record.version === undefined ? TOOL_PROPOSAL_VERSION : record.version;
  if (!Number.isInteger(version) || version !== TOOL_PROPOSAL_VERSION) {
    errors.push(`unsupported tool proposal version: ${String(version)}`);
  }

  if (!isRecord(record.arguments)) errors.push('arguments must be an object');
  if (typeof record.reason !== 'string' || record.reason.trim() === '') errors.push('reason is required');

  if (record.requirement_refs !== undefined) {
    if (
      !Array.isArray(record.requirement_refs) ||
      record.requirement_refs.length > 50 ||
      record.requirement_refs.some((value) => typeof value !== 'string' || value.length < 1 || value.length > 128)
    ) {
      errors.push('requirement_refs must be an array of bounded strings');
    }
  }

  if (isRecord(record.arguments)) {
    const args = /** @type {Record<string, unknown>} */ (record.arguments);
    for (const key of ['path', 'source_path', 'target_path']) {
      if (args[key] !== undefined && (typeof args[key] !== 'string' || !isSafeRelativePath(String(args[key])))) {
        errors.push(`${key} is unsafe`);
      }
    }
    const bytes = utf8ByteLength(JSON.stringify(args));
    if (bytes > (options.maxArgumentBytes ?? DEFAULT_MAX_ARGUMENT_BYTES)) errors.push('tool arguments exceed size limit');
  }

  if (errors.length) return { ok: false, errors, value: null };

  const normalized = {
    tool,
    version: TOOL_PROPOSAL_VERSION,
    arguments: record.arguments,
    reason: record.reason,
  };
  if (record.requirement_refs !== undefined) normalized.requirement_refs = [...record.requirement_refs];

  return { ok: true, errors: [], value: normalized };
}

/** @param {unknown} value @param {(value: unknown) => {ok: boolean, errors: string[], value: unknown}} validator */
function validateStructuredResult(value, validator) {
  try {
    const result = validator(value);
    return result.ok ? result : { ok: false, errors: result.errors, value: null };
  } catch (error) {
    return {
      ok: false,
      errors: [error instanceof Error ? error.message : 'structured output validation failed'],
      value: null,
    };
  }
}

/** @param {string} value */
function utf8ByteLength(value) {
  let bytes = 0;
  for (const char of value) {
    const code = char.codePointAt(0) ?? 0;
    bytes += code <= 0x7f ? 1 : code <= 0x7ff ? 2 : code <= 0xffff ? 3 : 4;
  }
  return bytes;
}

module.exports = {
  ALLOWED_TOOL_PROPOSALS,
  CANONICAL_TOOL_PROPOSALS,
  DEFAULT_MAX_ARGUMENT_BYTES,
  LEGACY_TOOL_ALIASES,
  TOOL_PROPOSAL_VERSION,
  canonicalToolName,
  isSafeRelativePath,
  validateStructuredResult,
  validateToolProposal,
};
