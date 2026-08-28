'use strict';
const { EVENT_KINDS, objectOrEmpty, requireEnum, requireString, scope } = require('./contracts.js');

const CUSTOMER_APP_EVENTS = Object.freeze([
  'page_viewed','booking_started','booking_completed','order_started','order_completed',
  'checkout_started','checkout_completed','lead_submitted','signup_completed','login_completed',
  'search_performed','automation_completed','workflow_completed','admin_action_completed',
  'availability_checked','room_viewed','session_started','customer_returned','revenue_recorded','support_ticket_created'
]);
const PANDORA_PRODUCT_EVENTS = Object.freeze([
  'project_created','intent_submitted','project_understanding_confirmed','build_started','build_completed',
  'preview_opened','change_requested','publish_started','publish_completed','domain_connected',
  'recommendation_viewed','recommendation_accepted','rollback_started','budget_exceeded'
]);
const INTERNAL_ONLY_EVENTS = new Set(['build_completed','publish_completed','budget_exceeded','rollback_started']);
const FORBIDDEN_PROPERTY_PATTERNS = Object.freeze([/secret/i,/password/i,/credential/i,/token$/i,/raw_prompt/i,/source_code/i,/stack_trace/i,/document/i,/payment_details/i,/phone/i,/email/i,/full_name/i]);
const ALLOWED_COMMON_PROPERTIES = new Set(['schema_version','organization_id','project_id','project_version_id','environment','occurred_at','source','metric_value','amount','currency','duration_seconds','manual_hours_saved','branch','location','device_class','traffic_source','cohort_key','experiment_id','variant']);
const MAX_EVENT_BYTES = 16 * 1024;
const MAX_PROPERTIES = 32;

function validateEventEnvelope(input, options = {}) {
  const value = objectOrEmpty(input, 'event');
  const kind = requireEnum(value.kind, EVENT_KINDS, 'kind');
  const event = requireString(value.event, 'event', 160);
  const allowed = kind === 'pandora_internal_event' ? PANDORA_PRODUCT_EVENTS : CUSTOMER_APP_EVENTS;
  if (!allowed.includes(event)) throw new TypeError(`event ${event} is not allowed for ${kind}`);
  if (kind === 'customer_app_business_event' && INTERNAL_ONLY_EVENTS.has(event)) throw new TypeError('customer app cannot emit Pandora internal authority events');
  if (kind === 'pandora_internal_event' && options.trustedInternal !== true) throw new TypeError('Pandora internal events require a trusted server boundary');
  const eventScope = scope(value.scope);
  const schemaVersion = requireString(value.schemaVersion ?? '1.0.0', 'schemaVersion', 32);
  if (!/^\d+\.\d+\.\d+$/.test(schemaVersion)) throw new TypeError(lschemaVersion must be semantic version format`);
  const properties = sanitizeProperties(value.properties ?? {});
  const normalized = { kind, event, scope: eventScope, schemaVersion, properties };
  const bytes = Buffer.byteLength(JSON.stringify(normalized), 'utf8');
  if (bytes > MAX_EVENT_BYTES) throw new TypeError(`event exceeds ${MAX_EVENT_BYTES} bytes`);
  return Object.freeze(normalized);
}

function sanitizeProperties(input) {
  const source = objectOrEmpty(input, 'properties');
  const entries = Object.entries(source);
  if (entries.length > MAX_PROPERTIES) throw new TypeError(`properties exceed ${MAX_PROPERTIES} keys`);
  const clean = {};
  for (const [key, value] of entries) {
    if (!ALLOWED_COMMON_PROPERTIES.has(key)) throw new TypeError(`property not allowlisted: ${key}`);
    if (FORBIDDEN_PROPERTY_PATTERNS.some((pattern) => pattern.test(key))) throw new TypeError(`sensitive property forbidden: ${key}`);
    if (!['string','number','boolean'].includes(typeof value) && value !== null) throw new TypeError(`property ${key} must be scalar`);
    if (typeof value === 'string' && value.length > 1000) throw new TypeError(`property ${key} is too large`);
    clean[key] = value;
  }
  return Object.freeze(clean);
}

function instrumentationRequirement(metric) {
  return Object.freeze({
    metricKey: metric.key,
    requiredEvent: metric.event,
    denominatorEvent: metric.denominatorEvent,
    requiredProperty: metric.property,
    requireProjectVersionAttribution: metric.versionAttribution !== 'none',
    schemaVersion: '1.0.0',
  });
}

module.exports = { ALLOWED_COMMON_PROPERTIES, CUSTOMER_APP_EVENTS, INTERNAL_ONLY_EVENTS, MAX_EVENT_BYTES, PANDORA_PRODUCT_EVENTS, instrumentationRequirement, sanitizeProperties, validateEventEnvelope };
