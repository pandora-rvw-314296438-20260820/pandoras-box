'use strict';
const { createHash } = require('node:crypto');

const EVENT_RE = /^[a-z][a-z0-9_.-]{2,127}$/;
const TYPE_RE = /^[a-z][a-z0-9_.-]{0,63}$/;
const ID_RE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const SENSITIVE_KEY = /(?:password|passphrase|secret|token|authorization|cookie|private.?key|service.?role|api.?key|card|cvv|cvc)/i;

class PandoraAuditService {
  constructor({ sink, clock = () => new Date() }) {
    if (!sink || typeof sink.append !== 'function') throw new TypeError('audit sink.append is required');
    this.sink = sink;
    this.clock = clock;
  }

  async recordMutation(input) {
    const record = normalizeAuditRecord({ ...input, occurredAt: input.occurredAt || this.clock().toISOString() });
    const result = await this.sink.append(record);
    return Object.freeze({ ...record, receiptId: result && typeof result.receiptId === 'string' ? result.receiptId : null });
  }
}

function normalizeAuditRecord(input) {
  const tenantId = requireId(input.tenantId, 'tenantId');
  const actorUserId = requireId(input.actorUserId, 'actorUserId');
  const eventName = requirePattern(input.eventName, 'eventName', EVENT_RE);
  const resourceType = requirePattern(input.resourceType, 'resourceType', TYPE_RE);
  const resourceId = requireId(input.resourceId, 'resourceId');
  const mutationId = requireId(input.mutationId, 'mutationId');
  const occurredAt = normalizeTimestamp(input.occurredAt);
  const metadata = sanitizeMetadata(input.metadata || {});
  const changeDigest = input.change == null ? null : sha256Json(input.change);
  return Object.freeze({ schemaVersion:'1.0', tenantId, actorUserId, eventName, resourceType, resourceId, mutationId, occurredAt, metadata:Object.freeze(metadata), changeDigest });
}

function sanitizeMetadata(value, depth = 0) {
  if (depth > 4) throw new TypeError('audit metadata nesting exceeds limit');
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('audit metadata must be an object');
  const entries = Object.entries(value);
  if (entries.length > 32) throw new TypeError('audit metadata contains too many fields');
  const out = {};
  for (const [key, child] of entries) {
    if (SENSITIVE_KEY.test(key)) continue;
    if (!/^[A-Za-z][A-Za-z0-9_.-]{0,63}$/.test(key)) throw new TypeError('audit metadata key is invalid');
    if (child == null || typeof child === 'boolean' || typeof child === 'number') out[key] = child;
    else if (typeof child === 'string') out[key] = child.slice(0, 512);
    else if (Array.isArray(child)) out[key] = child.slice(0, 16).map(item => primitiveValue(item));
    else out[key] = sanitizeMetadata(child, depth + 1);
  }
  return out;
}

function primitiveValue(value) {
  if (value == null || typeof value === 'boolean' || typeof value === 'number') return value;
  if (typeof value === 'string') return value.slice(0, 256);
  throw new TypeError('audit metadata arrays may contain only primitive values');
}
function sha256Json(value) { return `sha256:${createHash('sha256').update(stable(value)).digest('hex')}`; }
function stable(value) {
  if (Array.isArray(value)) return `[${value.map(stable).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.keys(value).sort().map(k => `${JSON.stringify(k)}:${stable(value[k])}`).join(',')}}`;
  return JSON.stringify(value);
}
function normalizeTimestamp(value) { const d = new Date(value); if (!Number.isFinite(d.getTime())) throw new TypeError('occurredAt is invalid'); return d.toISOString(); }
function requirePattern(value, field, pattern) { if (typeof value !== 'string' || !pattern.test(value)) throw new TypeError(`${field} is invalid`); return value; }
function requireId(value, field) { return requirePattern(value, field, ID_RE); }

module.exports = { PandoraAuditService, normalizeAuditRecord, sanitizeMetadata, sha256Json };
