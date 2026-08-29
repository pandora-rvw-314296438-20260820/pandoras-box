'use strict';

function normalizeIdentity(input) {
  if (!input || typeof input !== 'object') throw new TypeError('authenticated identity is required');
  const userId = requireText(input.userId, 'identity.userId');
  const provider = requireText(input.provider, 'identity.provider');
  const environment = requireText(input.environment, 'identity.environment');
  return Object.freeze({
    userId,
    provider,
    environment,
    email: optionalText(input.email),
    emailVerified: input.emailVerified === true,
    sessionId: optionalText(input.sessionId),
    claims: Object.freeze(sanitizeClaims(input.claims)),
  });
}

function sanitizeClaims(value) {
  if (value == null) return {};
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('identity.claims must be an object');
  const denied = /(?:secret|token|password|service.?role|private.?key)/i;
  const output = {};
  for (const [key, child] of Object.entries(value)) {
    if (denied.test(key)) continue;
    if (child == null || ['string', 'number', 'boolean'].includes(typeof child)) output[key] = child;
  }
  return output;
}

function requireText(value, field) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`);
  return value.trim();
}
function optionalText(value) { return typeof value === 'string' && value.trim() ? value.trim() : null; }

module.exports = { normalizeIdentity, sanitizeClaims };
