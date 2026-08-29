'use strict';

const {
  PANDORA_LIFECYCLE_EVENTS,
  PANDORA_PRODUCT_KEY,
  PANDORA_EVENT_SCHEMA_VERSION,
  PANDORA_DATABASE_SCHEMA_VERSION,
  PANDORA_PRIVACY_MODE,
  PANDORA_PRIVACY_TIER,
  isPandoraPseudonymousKey,
} = require('./pandora-lifecycle.js');

const POSTHOG_INGEST_HOSTS = Object.freeze([
  'https://us.i.posthog.com',
  'https://eu.i.posthog.com',
]);
const HOST_SET = new Set(POSTHOG_INGEST_HOSTS);
const EVENT_SET = new Set(PANDORA_LIFECYCLE_EVENTS);
const MAX_ENVELOPE_BYTES = 16 * 1024;

function nonEmpty(value, field, max = 512) {
  if (typeof value !== 'string' || value.trim().length === 0) throw new TypeError(`${field} must be a non-empty string`);
  if (value !== value.trim() || value.length > max) throw new RangeError(`${field} is invalid`);
  return value;
}

function normalizeHost(value = 'https://us.i.posthog.com') {
  const host = nonEmpty(value, 'PostHog host', 128).replace(/\/$/, '');
  if (!HOST_SET.has(host)) throw new RangeError('PostHog ingestion host is not allowlisted');
  return host;
}

function assertProjectToken(value) {
  const token = nonEmpty(value, 'PostHog project token', 512);
  if (!/^phc_[A-Za-z0-9_-]{20,}$/.test(token)) throw new RangeError('PostHog project token format is invalid');
  return token;
}

function assertPlainObject(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.getPrototypeOf(value) !== Object.prototype) {
    throw new TypeError(`${field} must be a plain object`);
  }
  return value;
}

function assertEnvelope(envelope, { allowProduction = false } = {}) {
  const input = assertPlainObject(envelope, 'lifecycle envelope');
  if (!EVENT_SET.has(input.event)) throw new RangeError('unsupported Pandora lifecycle event');
  if (!isPandoraPseudonymousKey('actor', input.distinct_id)) throw new Error('Pandora lifecycle distinct_id must be pseudonymous');
  const properties = assertPlainObject(input.properties, 'lifecycle properties');
  if (properties.product_key !== PANDORA_PRODUCT_KEY) throw new Error('Pandora product key mismatch');
  if (properties.schema_version !== PANDORA_EVENT_SCHEMA_VERSION) throw new Error('Pandora event schema mismatch');
  if (properties.event_schema_version !== PANDORA_DATABASE_SCHEMA_VERSION) throw new Error('Pandora database event schema mismatch');
  if (properties.privacy_mode !== PANDORA_PRIVACY_MODE || properties.privacy_tier !== PANDORA_PRIVACY_TIER) throw new Error('Pandora privacy contract mismatch');
  if (!isPandoraPseudonymousKey('organization', properties.organization_key)) throw new Error('organization key must be pseudonymous');
  if (!isPandoraPseudonymousKey('project', properties.project_key)) throw new Error('project key must be pseudonymous');
  if (properties.environment === 'production' && allowProduction !== true) throw new Error('production PostHog capture is not approved');
  if (typeof input.timestamp !== 'string' || new Date(input.timestamp).toISOString() !== input.timestamp) throw new RangeError('lifecycle timestamp must be canonical ISO-8601 UTC');
  const bytes = Buffer.byteLength(JSON.stringify(input), 'utf8');
  if (bytes > MAX_ENVELOPE_BYTES) throw new RangeError('Pandora lifecycle envelope exceeds capture limit');
  return input;
}

function safeHttpError(status) {
  const error = new Error('PostHog capture was rejected');
  error.code = `posthog_http_${Number.isInteger(status) ? status : 'error'}`;
  return error;
}

function createPostHogCaptureTransport({
  projectToken,
  host = 'https://us.i.posthog.com',
  fetchImpl = globalThis.fetch,
  timeoutMs = 5000,
  allowProduction = false,
} = {}) {
  const token = assertProjectToken(projectToken);
  const ingestHost = normalizeHost(host);
  if (typeof fetchImpl !== 'function') throw new TypeError('fetch implementation is required');
  if (!Number.isInteger(timeoutMs) || timeoutMs < 250 || timeoutMs > 15000) throw new RangeError('PostHog timeout must be between 250ms and 15000ms');
  if (typeof allowProduction !== 'boolean') throw new TypeError('allowProduction must be boolean');

  return Object.freeze({
    host: ingestHost,
    async capture(envelope) {
      const safeEnvelope = assertEnvelope(envelope, { allowProduction });
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      try {
        const response = await fetchImpl(`${ingestHost}/i/v0/e/`, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            api_key: token,
            event: safeEnvelope.event,
            properties: {
              distinct_id: safeEnvelope.distinct_id,
              ...safeEnvelope.properties,
              timestamp: safeEnvelope.timestamp,
            },
          }),
          signal: controller.signal,
        });
        if (!response || response.ok !== true) throw safeHttpError(Number(response?.status || 0));
        return Object.freeze({ accepted: true, status: Number(response.status || 200) });
      } catch (error) {
        if (error?.name === 'AbortError') {
          const timeoutError = new Error('PostHog capture timed out');
          timeoutError.code = 'posthog_timeout';
          throw timeoutError;
        }
        if (typeof error?.code === 'string' && /^posthog_[a-z0-9_]+$/.test(error.code)) throw error;
        const networkError = new Error('PostHog capture failed');
        networkError.code = 'posthog_network_error';
        throw networkError;
      } finally {
        clearTimeout(timer);
      }
    },
  });
}

module.exports = {
  POSTHOG_INGEST_HOSTS,
  MAX_ENVELOPE_BYTES,
  normalizeHost,
  assertEnvelope,
  createPostHogCaptureTransport,
};
