import { createHash } from 'node:crypto';

const identifierPattern = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$/;
const sensitiveKeyPattern = /(?:secret|password|authorization|cookie|raw[_-]?body|private[_-]?key|access[_-]?token|refresh[_-]?token|credential[_-]?value)/i;
const sensitiveValuePatterns = [
  /^Bearer\s+/i,
  /^sk-[A-Za-z0-9_-]{8,}$/,
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  /(?:client_secret|access_token|refresh_token)=/i,
];

function canonicalize(value) {
  if (Array.isArray(value)) {
    return value.map(canonicalize);
  }
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, canonicalize(value[key])]),
    );
  }
  return value;
}

function digest(value) {
  return createHash('sha256')
    .update(JSON.stringify(canonicalize(value)))
    .digest('hex');
}

function assertIdentifier(value, name) {
  if (typeof value !== 'string' || !identifierPattern.test(value)) {
    throw new TypeError(`${name} must be a bounded identifier`);
  }
}

function assertNoSensitiveMaterial(value, path = 'details') {
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertNoSensitiveMaterial(item, `${path}[${index}]`));
    return;
  }
  if (value && typeof value === 'object') {
    for (const [key, item] of Object.entries(value)) {
      if (sensitiveKeyPattern.test(key)) {
        throw new TypeError(`${path}.${key} is not allowed in audit evidence`);
      }
      assertNoSensitiveMaterial(item, `${path}.${key}`);
    }
    return;
  }
  if (typeof value === 'string' && sensitiveValuePatterns.some((pattern) => pattern.test(value))) {
    throw new TypeError(`${path} contains credential-like material`);
  }
}

export function appendAuditEvent({
  previousEventHash = null,
  eventType,
  actorType = 'system',
  actorId,
  organizationId,
  subjectType = 'connection',
  subjectId,
  outcome,
  reasonCode,
  occurredAt,
  evidence = {},
}) {
  for (const [name, value] of Object.entries({
    eventType,
    actorType,
    actorId,
    organizationId,
    subjectType,
    subjectId,
    outcome,
    reasonCode,
  })) {
    assertIdentifier(value, name);
  }
  if (previousEventHash !== null && !/^[0-9a-f]{64}$/.test(previousEventHash)) {
    throw new TypeError('previousEventHash must be null or a SHA-256 digest');
  }
  const timestamp = new Date(occurredAt);
  if (!Number.isFinite(timestamp.getTime())) {
    throw new TypeError('occurredAt must be a valid timestamp');
  }
  assertNoSensitiveMaterial(evidence);

  const body = {
    version: 'pandora-connection-audit-v1',
    eventType,
    actor: { type: actorType, id: actorId },
    organizationId,
    subject: { type: subjectType, id: subjectId },
    outcome,
    reasonCode,
    occurredAt: timestamp.toISOString(),
    evidence: canonicalize(evidence),
  };
  const eventHash = digest({ previousEventHash, body });
  return Object.freeze({ ...body, previousEventHash, eventHash });
}

export function verifyAuditChain(events) {
  if (!Array.isArray(events)) {
    return { valid: false, index: -1, reason: 'events_not_array' };
  }
  let previousEventHash = null;
  for (let index = 0; index < events.length; index += 1) {
    const event = events[index];
    if (!event || event.previousEventHash !== previousEventHash) {
      return { valid: false, index, reason: 'previous_hash_mismatch' };
    }
    const { eventHash, previousEventHash: recordedPrevious, ...body } = event;
    if (eventHash !== digest({ previousEventHash: recordedPrevious, body })) {
      return { valid: false, index, reason: 'event_hash_mismatch' };
    }
    previousEventHash = eventHash;
  }
  return { valid: true, eventCount: events.length, headHash: previousEventHash };
}

export const auditInternals = Object.freeze({ canonicalize, digest });
