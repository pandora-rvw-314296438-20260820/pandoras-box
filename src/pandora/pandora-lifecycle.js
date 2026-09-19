'use strict';

const { createHmac } = require('node:crypto');

const PANDORA_PRODUCT_KEY = 'pandoras_box';
const PANDORA_EVENT_SCHEMA_VERSION = '1.0.0';
const PANDORA_DATABASE_SCHEMA_VERSION = 1;
const PANDORA_PRIVACY_MODE = 'strict_metadata_only';
const PANDORA_PRIVACY_TIER = 'pseudonymous_product';

const PANDORA_LIFECYCLE_EVENTS = Object.freeze([
  'pandora_intent_received',
  'pandora_plan_accepted',
  'pandora_execution_started',
  'pandora_build_succeeded',
  'pandora_tests_passed',
  'pandora_deployment_created',
  'pandora_production_verified',
  'pandora_outcome_accepted',
  'pandora_execution_failed',
  'pandora_rollback_completed',
]);

const PANDORA_PROOF_STAGES = Object.freeze([
  'documented',
  'implemented',
  'tested',
  'deployed',
  'production_verified',
]);

const PANDORA_RESULTS = Object.freeze([
  'accepted',
  'blocked',
  'failure',
  'partial',
  'rejected',
  'rolled_back',
  'success',
]);

const PANDORA_INPUT_ENVIRONMENTS = Object.freeze([
  'local',
  'test',
  'development',
  'preview',
  'staging',
  'production',
  'unknown',
]);

const EVENT_SET = new Set(PANDORA_LIFECYCLE_EVENTS);
const PROOF_STAGE_SET = new Set(PANDORA_PROOF_STAGES);
const RESULT_SET = new Set(PANDORA_RESULTS);
const INPUT_ENVIRONMENT_SET = new Set(PANDORA_INPUT_ENVIRONMENTS);

const PREFIXES = Object.freeze({
  actor: 'actor',
  organization: 'org',
  project: 'project',
});

const FORBIDDEN_KEY = /(?:^|_)(?:api[_-]?key|authorization|body|code|credential|customer[_-]?message|document|email|input|jwt|kyc|message|output|password|payload|phone|private[_-]?key|prompt|response|secret|source[_-]?code|token|tool[_-]?(?:arg|argument|arguments|input|output|result)|transcript)(?:$|_)/i;
const EMAIL_LIKE = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i;
const PRIVATE_KEY_LIKE = /-----BEGIN [A-Z ]*PRIVATE KEY-----/;
const BEARER_LIKE = /\bBearer\s+[A-Za-z0-9._~+/-]{16,}=*\b/i;
const COMMON_SECRET_LIKE = /\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|sb_secret_[A-Za-z0-9_-]{16,})\b/;
const JWT_LIKE = /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/;

const STRING_RULES = Object.freeze({
  source_sha: { pattern: /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/i, max: 64 },
  release_sha: { pattern: /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/i, max: 64 },
  release_id: { pattern: /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/, max: 128 },
  deployment_id: { pattern: /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/, max: 128 },
  rollback_of_deployment_id: { pattern: /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/, max: 128 },
  failure_class: { pattern: /^[a-z][a-z0-9_.-]{0,63}$/, max: 64 },
  tool_class: { pattern: /^[a-z][a-z0-9_.-]{0,63}$/, max: 64 },
  model_provider: { pattern: /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/, max: 64 },
  model_name: { pattern: /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/, max: 128 },
  outcome_type: { pattern: /^[a-z][a-z0-9_.-]{0,63}$/, max: 64 },
});

const NUMBER_RULES = Object.freeze({
  duration_ms: { min: 0, max: 604_800_000, integer: true },
  latency_ms: { min: 0, max: 86_400_000, integer: true },
  retry_count: { min: 0, max: 1_000, integer: true },
  input_tokens: { min: 0, max: 100_000_000, integer: true },
  output_tokens: { min: 0, max: 100_000_000, integer: true },
  total_cost_usd: { min: 0, max: 10_000, integer: false },
  evaluation_score: { min: 0, max: 1, integer: false },
  evidence_count: { min: 0, max: 100_000, integer: true },
});

const ALLOWED_EXTRA_KEYS = new Set([
  ...Object.keys(STRING_RULES),
  ...Object.keys(NUMBER_RULES),
  'result',
]);

function assertPlainObject(name, value) {
  if (value === undefined) return {};
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError(`${name} must be a plain object`);
  }
  if (Object.getPrototypeOf(value) !== Object.prototype) {
    throw new TypeError(`${name} must use the default object prototype`);
  }
  return value;
}

function normalizeHmacKey(key) {
  if (typeof key === 'string') {
    if (key.length < 32) throw new RangeError('pseudonymization key must be at least 32 characters');
    return Buffer.from(key, 'utf8');
  }
  if (Buffer.isBuffer(key) || key instanceof Uint8Array) {
    const value = Buffer.from(key);
    if (value.length < 32) throw new RangeError('pseudonymization key must be at least 32 bytes');
    return value;
  }
  throw new TypeError('pseudonymization key must be a string, Buffer, or Uint8Array');
}

function assertRawIdentifier(name, value) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new TypeError(`${name} must be a non-empty string`);
  }
  if (value.length > 512) throw new RangeError(`${name} exceeds 512 characters`);
  return value.trim();
}

function derivePandoraPseudonymousKey(kind, rawValue, pseudonymizationKey) {
  if (!Object.prototype.hasOwnProperty.call(PREFIXES, kind)) {
    throw new RangeError(`unsupported pseudonymous key kind: ${kind}`);
  }
  const normalizedValue = assertRawIdentifier('rawValue', rawValue);
  const key = normalizeHmacKey(pseudonymizationKey);
  const digest = createHmac('sha256', key)
    .update(`${kind}\u0000${normalizedValue}`, 'utf8')
    .digest('base64url')
    .slice(0, 32);
  return `${PREFIXES[kind]}_${digest}`;
}

function isPandoraPseudonymousKey(kind, value) {
  const prefix = PREFIXES[kind];
  if (!prefix || typeof value !== 'string') return false;
  return new RegExp(`^${prefix}_[A-Za-z0-9_-]{32}$`).test(value);
}

function resemblesSensitiveData(value) {
  return EMAIL_LIKE.test(value)
    || PRIVATE_KEY_LIKE.test(value)
    || BEARER_LIKE.test(value)
    || COMMON_SECRET_LIKE.test(value)
    || JWT_LIKE.test(value);
}

function assertSafeString(key, value, rule) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new TypeError(`${key} must be a non-empty string`);
  }
  if (value.length > rule.max || !rule.pattern.test(value)) {
    throw new RangeError(`${key} does not satisfy the metadata contract`);
  }
  if (resemblesSensitiveData(value)) throw new Error(`${key} resembles sensitive data`);
  return value;
}

function assertSafeNumber(key, value, rule) {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new TypeError(`${key} must be a finite number`);
  }
  if (value < rule.min || value > rule.max) {
    throw new RangeError(`${key} is outside the allowed range`);
  }
  if (rule.integer && !Number.isInteger(value)) throw new TypeError(`${key} must be an integer`);
  return value;
}

function validateAdditionalProperties(properties) {
  const input = assertPlainObject('properties', properties);
  const output = {};
  for (const [key, value] of Object.entries(input)) {
    if (!ALLOWED_EXTRA_KEYS.has(key)) {
      if (FORBIDDEN_KEY.test(key)) throw new Error(`forbidden telemetry key: ${key}`);
      throw new Error(`unknown telemetry key: ${key}`);
    }
    if (value === undefined) continue;
    if (key === 'result') {
      if (!RESULT_SET.has(value)) throw new RangeError(`unsupported result: ${value}`);
      output[key] = value;
      continue;
    }
    if (Object.prototype.hasOwnProperty.call(STRING_RULES, key)) {
      output[key] = assertSafeString(key, value, STRING_RULES[key]);
      continue;
    }
    if (Object.prototype.hasOwnProperty.call(NUMBER_RULES, key)) {
      output[key] = assertSafeNumber(key, value, NUMBER_RULES[key]);
      continue;
    }
    throw new Error(`unhandled telemetry key: ${key}`);
  }
  return output;
}

function normalizePandoraEnvironment(value) {
  if (typeof value !== 'string' || !INPUT_ENVIRONMENT_SET.has(value)) {
    throw new RangeError(`unsupported environment: ${value}`);
  }
  // The current control-plane database accepts development but not local/test.
  if (value === 'local' || value === 'test') return 'development';
  return value;
}

function assertTimestamp(value) {
  const timestamp = value ?? new Date().toISOString();
  if (typeof timestamp !== 'string') throw new TypeError('timestamp must be an ISO-8601 string');
  const parsed = Date.parse(timestamp);
  if (!Number.isFinite(parsed) || new Date(parsed).toISOString() !== timestamp) {
    throw new RangeError('timestamp must be a canonical ISO-8601 UTC string');
  }
  return timestamp;
}

function assertExecutionId(value) {
  if (typeof value !== 'string' || !/^exec_[A-Za-z0-9_-]{8,96}$/.test(value)) {
    throw new RangeError('executionId must be a non-sensitive exec_ identifier');
  }
  return value;
}

function buildPandoraLifecycleEvent({
  event,
  actorId,
  organizationId,
  projectId,
  executionId,
  environment,
  proofStage,
  properties,
  timestamp,
}, pseudonymizationKey) {
  if (!EVENT_SET.has(event)) throw new RangeError(`unsupported lifecycle event: ${event}`);
  if (!PROOF_STAGE_SET.has(proofStage)) throw new RangeError(`unsupported proof stage: ${proofStage}`);

  const actorKey = derivePandoraPseudonymousKey('actor', actorId, pseudonymizationKey);
  const organizationKey = derivePandoraPseudonymousKey('organization', organizationId, pseudonymizationKey);
  const projectKey = derivePandoraPseudonymousKey('project', projectId, pseudonymizationKey);
  assertExecutionId(executionId);
  const safeExtras = validateAdditionalProperties(properties);

  return Object.freeze({
    event,
    distinct_id: actorKey,
    timestamp: assertTimestamp(timestamp),
    properties: Object.freeze({
      product_key: PANDORA_PRODUCT_KEY,
      schema_version: PANDORA_EVENT_SCHEMA_VERSION,
      event_schema_version: PANDORA_DATABASE_SCHEMA_VERSION,
      privacy_mode: PANDORA_PRIVACY_MODE,
      privacy_tier: PANDORA_PRIVACY_TIER,
      environment: normalizePandoraEnvironment(environment),
      proof_stage: proofStage,
      organization_key: organizationKey,
      project_key: projectKey,
      execution_id: executionId,
      ...safeExtras,
    }),
  });
}

function redactCaptureError(error) {
  if (!error || typeof error !== 'object') return 'unknown_capture_error';
  if (typeof error.code === 'string' && /^[A-Za-z0-9_.-]{1,64}$/.test(error.code)) return error.code;
  return 'capture_error';
}

function createPandoraLifecycleTelemetry({
  enabled = false,
  environment = 'unknown',
  capture,
  flush,
  pseudonymizationKey,
  productionApproved = false,
  logger = console,
} = {}) {
  if (typeof enabled !== 'boolean') throw new TypeError('enabled must be a boolean');
  const normalizedEnvironment = normalizePandoraEnvironment(environment);
  if (enabled && typeof capture !== 'function') throw new TypeError('capture must be provided when telemetry is enabled');
  if (flush !== undefined && typeof flush !== 'function') throw new TypeError('flush must be a function when provided');
  if (enabled) normalizeHmacKey(pseudonymizationKey);
  if (enabled && normalizedEnvironment === 'production' && productionApproved !== true) {
    throw new Error('production telemetry requires a separate explicit approval');
  }

  return Object.freeze({
    enabled,
    async captureLifecycle(input) {
      if (!enabled) return Object.freeze({ sent: false, status: 'disabled' });
      const envelope = buildPandoraLifecycleEvent({ ...input, environment }, pseudonymizationKey);
      try {
        await capture(envelope);
        return Object.freeze({ sent: true, status: 'captured', event: envelope.event, timestamp: envelope.timestamp });
      } catch (error) {
        const errorCode = redactCaptureError(error);
        if (logger && typeof logger.warn === 'function') {
          logger.warn('pandora_telemetry_capture_failed', { error_code: errorCode });
        }
        return Object.freeze({ sent: false, status: 'capture_failed', errorCode });
      }
    },
    async shutdown() {
      if (!enabled || !flush) return Object.freeze({ flushed: false, status: 'not_required' });
      try {
        await flush();
        return Object.freeze({ flushed: true, status: 'flushed' });
      } catch (error) {
        const errorCode = redactCaptureError(error);
        if (logger && typeof logger.warn === 'function') {
          logger.warn('pandora_telemetry_flush_failed', { error_code: errorCode });
        }
        return Object.freeze({ flushed: false, status: 'flush_failed', errorCode });
      }
    },
  });
}

function pandoraLifecycleTelemetryEnabled(env = process.env) {
  return env.PANDORA_POSTHOG_TELEMETRY_ENABLED === 'true';
}

function pandoraProductionTelemetryApproved(env = process.env) {
  return env.PANDORA_POSTHOG_PRODUCTION_APPROVED === 'true';
}

module.exports = {
  PANDORA_PRODUCT_KEY,
  PANDORA_EVENT_SCHEMA_VERSION,
  PANDORA_DATABASE_SCHEMA_VERSION,
  PANDORA_PRIVACY_MODE,
  PANDORA_PRIVACY_TIER,
  PANDORA_LIFECYCLE_EVENTS,
  PANDORA_PROOF_STAGES,
  PANDORA_RESULTS,
  PANDORA_INPUT_ENVIRONMENTS,
  derivePandoraPseudonymousKey,
  isPandoraPseudonymousKey,
  normalizePandoraEnvironment,
  buildPandoraLifecycleEvent,
  createPandoraLifecycleTelemetry,
  pandoraLifecycleTelemetryEnabled,
  pandoraProductionTelemetryApproved,
};
