'use strict';

const STICKINESS_MODES = Object.freeze(['unassigned', 'sticky', 'recovering']);

/** @param {unknown} value @param {string} field */
function optionalText(value, field) {
  if (value == null) return null;
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} must be a non-empty string or null`);
  return value.trim();
}
/** @param {unknown} value @param {string} field @param {number} fallback */
function nonNegativeInteger(value, field, fallback) {
  if (value == null) return fallback;
  if (!Number.isInteger(value) || Number(value) < 0) throw new TypeError(`${field} must be a non-negative integer`);
  return Number(value);
}

/** @param {Record<string, unknown>} input */
function createSessionRoutingState(input = {}) {
  const provider = optionalText(input.provider, 'session.provider');
  const model = optionalText(input.model, 'session.model');
  if ((provider == null) !== (model == null)) throw new TypeError('session provider and model must be assigned together');
  const requestedMode = input.stickinessMode == null ? (provider ? 'sticky' : 'unassigned') : String(input.stickinessMode);
  if (!STICKINESS_MODES.includes(requestedMode)) throw new TypeError('session.stickinessMode is invalid');
  if (requestedMode === 'unassigned' && provider) throw new TypeError('unassigned session cannot have provider/model');
  if (requestedMode !== 'unassigned' && !provider) throw new TypeError('assigned session requires provider/model');
  const reasoningPolicy = input.reasoningPolicy == null ? null : input.reasoningPolicy;
  if (reasoningPolicy != null && (typeof reasoningPolicy !== 'string' || !reasoningPolicy.trim())) throw new TypeError('session.reasoningPolicy must be a non-empty string or null');
  return Object.freeze({
    provider,
    model,
    modelVersion: optionalText(input.modelVersion, 'session.modelVersion'),
    routingPolicyVersion: optionalText(input.routingPolicyVersion, 'session.routingPolicyVersion'),
    reasoningPolicy: reasoningPolicy == null ? null : String(reasoningPolicy).trim(),
    stickinessMode: requestedMode,
    recoveryEpoch: nonNegativeInteger(input.recoveryEpoch, 'session.recoveryEpoch', 0),
    lastCompatibleTurnId: optionalText(input.lastCompatibleTurnId, 'session.lastCompatibleTurnId'),
  });
}

/** @param {Readonly<Record<string, unknown>>} model @param {Readonly<Record<string, unknown>>|null|undefined} session */
function sessionCompatibility(model, session) {
  if (!session || session.stickinessMode === 'unassigned') return Object.freeze({ compatible: true, recoveryRequired: false, reason: null });
  const same = session.provider === model.provider && session.model === model.modelId;
  if (same) return Object.freeze({ compatible: true, recoveryRequired: false, reason: null });
  return Object.freeze({ compatible: false, recoveryRequired: true, reason: 'session_sticky_mismatch' });
}

/** @param {Readonly<Record<string, unknown>>} previous @param {Readonly<Record<string, unknown>>} model @param {string|null} policyVersion @param {string|null} reasoningPolicy */
function createRecoveryRoutingState(previous, model, policyVersion = null, reasoningPolicy = null) {
  return createSessionRoutingState({
    provider: String(model.provider),
    model: String(model.modelId),
    modelVersion: typeof model.modelVersion === 'string' ? model.modelVersion : null,
    routingPolicyVersion: policyVersion,
    reasoningPolicy,
    stickinessMode: 'recovering',
    recoveryEpoch: Number(previous.recoveryEpoch ?? 0) + 1,
    lastCompatibleTurnId: typeof previous.lastCompatibleTurnId === 'string' ? previous.lastCompatibleTurnId : null,
  });
}

module.exports = { STICKINESS_MODES, createRecoveryRoutingState, createSessionRoutingState, sessionCompatibility };
