'use strict';

function createDomainEvent({ name, schemaVersion = '1.0', aggregate, actor, project, payload, occurredAt, idempotencyKey }) {
  if (typeof name !== 'string' || !/^[a-z][a-z0-9_.-]+$/.test(name)) throw new TypeError('event name is invalid');
  if (!/^\d+\.\d+$/.test(schemaVersion)) throw new TypeError('event schemaVersion must be major.minor');
  const projectId = required(project && project.id, 'project.id');
  const projectVersionId = required(project && project.versionId, 'project.versionId');
  const environment = required(project && project.environment, 'project.environment');
  return Object.freeze({
    name,
    schemaVersion,
    aggregate: aggregate ? Object.freeze({ type: required(aggregate.type, 'aggregate.type'), id: required(aggregate.id, 'aggregate.id') }) : null,
    actor: actor ? Object.freeze({ userId: required(actor.userId, 'actor.userId') }) : null,
    project: Object.freeze({ id: projectId, versionId: projectVersionId, environment }),
    occurredAt: occurredAt || new Date().toISOString(),
    idempotencyKey: idempotencyKey || null,
    payload: Object.freeze(sanitizePayload(payload || {})),
  });
}

function sanitizePayload(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('event payload must be an object');
  const denied = /(?:password|secret|token|card.?number|cvv|service.?role|private.?key)/i;
  const output = {};
  for (const [key, child] of Object.entries(value)) {
    if (denied.test(key)) continue;
    if (child == null || ['string', 'number', 'boolean'].includes(typeof child)) output[key] = child;
  }
  return output;
}
function assertIdempotentEventSink(sink, field = 'event sink') { if (!sink || typeof sink.publish !== 'function') throw new TypeError(`${field}.publish is required`); if (sink.idempotent !== true) throw new Error(`${field} must guarantee idempotent publication`); return sink; }
function required(value, field) { if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`); return value.trim(); }

module.exports = { assertIdempotentEventSink, createDomainEvent, sanitizePayload };
