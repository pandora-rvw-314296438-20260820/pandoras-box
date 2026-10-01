import { appendAuditEvent } from './audit-chain.mjs';

const healthyProviderStates = new Set(['healthy']);
const attentionProviderStates = new Set([
  'degraded',
  'revoked',
  'unauthorized',
  'unavailable',
  'error',
]);
const credentialStates = new Set(['active', 'missing', 'revoked']);
const identifierPattern = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$/;

function timestamp(value, name) {
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime())) {
    throw new TypeError(`${name} must be a valid timestamp`);
  }
  return parsed;
}

function identifier(value, name) {
  if (typeof value !== 'string' || !identifierPattern.test(value)) {
    throw new TypeError(`${name} must be a bounded identifier`);
  }
  return value;
}

function stringSet(value, name) {
  if (!Array.isArray(value) || value.some((item) => typeof item !== 'string' || !item.trim())) {
    throw new TypeError(`${name} must be an array of non-empty strings`);
  }
  return new Set(value.map((item) => item.trim()));
}

function result({ state, reasonCode, canUseNow = false, lastVerifiedAt = null }) {
  return {
    state,
    connected: state === 'Connected' && canUseNow,
    canUseNow: state === 'Connected' && canUseNow,
    needsAttention: state === 'Needs attention',
    reasonCode,
    lastVerifiedAt,
  };
}

export function evaluateConnectionHealth(input, options = {}) {
  if (!input || typeof input !== 'object') {
    throw new TypeError('connection input is required');
  }
  const now = timestamp(options.now ?? new Date(), 'now');
  const maxReadbackAgeMs = options.maxReadbackAgeMs ?? 15 * 60 * 1000;
  const rotateBeforeMs = options.rotateBeforeMs ?? 7 * 24 * 60 * 60 * 1000;
  const futureSkewMs = options.futureSkewMs ?? 60 * 1000;
  if (!Number.isInteger(maxReadbackAgeMs) || maxReadbackAgeMs < 1) {
    throw new TypeError('maxReadbackAgeMs must be a positive integer');
  }
  if (!Number.isInteger(rotateBeforeMs) || rotateBeforeMs < 0) {
    throw new TypeError('rotateBeforeMs must be a non-negative integer');
  }

  const connectionId = identifier(input.connectionId, 'connectionId');
  const organizationId = identifier(input.organizationId, 'organizationId');
  const provider = identifier(input.provider, 'provider');
  const previousState = input.previousState ?? 'Unknown';
  let projection;
  let receiptId = null;

  if (input.lifecycle === 'disconnected') {
    projection = result({ state: 'Disconnected', reasonCode: 'user_disconnected' });
  } else if (input.lifecycle === 'connecting') {
    projection = result({ state: 'Connecting', reasonCode: 'verification_pending' });
  } else {
    const credential = input.credential ?? {};
    if (!credentialStates.has(credential.state)) {
      throw new TypeError('credential.state must be active, missing, or revoked');
    }
    if (credential.state === 'missing') {
      projection = result({ state: 'Needs attention', reasonCode: 'credential_missing' });
    } else if (credential.state === 'revoked') {
      projection = result({ state: 'Needs attention', reasonCode: 'credential_revoked' });
    } else if (credential.expiresAt) {
      const expiresAt = timestamp(credential.expiresAt, 'credential.expiresAt');
      if (expiresAt <= now) {
        projection = result({ state: 'Needs attention', reasonCode: 'credential_expired' });
      } else if (expiresAt.getTime() - now.getTime() <= rotateBeforeMs) {
        projection = result({ state: 'Needs attention', reasonCode: 'credential_expiring' });
      }
    }

    const readback = input.providerReadback;
    if (!projection && (!readback || typeof readback !== 'object')) {
      projection = result({ state: 'Needs attention', reasonCode: 'provider_readback_missing' });
    }
    if (!projection && readback.verified !== true) {
      projection = result({ state: 'Needs attention', reasonCode: 'provider_readback_unverified' });
    }
    if (!projection) {
      receiptId = identifier(readback.receiptId, 'providerReadback.receiptId');
      const observedAt = timestamp(readback.observedAt, 'providerReadback.observedAt');
      const ageMs = now.getTime() - observedAt.getTime();
      if (ageMs < -futureSkewMs) {
        projection = result({ state: 'Needs attention', reasonCode: 'provider_readback_from_future' });
      } else if (ageMs > maxReadbackAgeMs) {
        projection = result({
          state: 'Needs attention',
          reasonCode: 'provider_readback_stale',
          lastVerifiedAt: observedAt.toISOString(),
        });
      } else if (attentionProviderStates.has(readback.status)) {
        projection = result({
          state: 'Needs attention',
          reasonCode: `provider_${readback.status}`,
          lastVerifiedAt: observedAt.toISOString(),
        });
      } else if (!healthyProviderStates.has(readback.status)) {
        projection = result({
          state: 'Needs attention',
          reasonCode: 'provider_status_unknown',
          lastVerifiedAt: observedAt.toISOString(),
        });
      } else {
        const binding = input.accountBinding;
        const identity = readback.identity;
        if (!binding || !identity || binding.accountId !== identity.accountId) {
          projection = result({
            state: 'Needs attention',
            reasonCode: 'account_identity_mismatch',
            lastVerifiedAt: observedAt.toISOString(),
          });
        } else if (
          binding.tenantId && binding.tenantId !== identity.tenantId
        ) {
          projection = result({
            state: 'Needs attention',
            reasonCode: 'tenant_identity_mismatch',
            lastVerifiedAt: observedAt.toISOString(),
          });
        } else {
          const requiredScopes = stringSet(input.requiredScopes ?? [], 'requiredScopes');
          const grantedScopes = stringSet(readback.scopes ?? [], 'providerReadback.scopes');
          const missingScope = [...requiredScopes].find((scope) => !grantedScopes.has(scope));
          if (missingScope) {
            projection = result({
              state: 'Needs attention',
              reasonCode: 'required_scope_denied',
              lastVerifiedAt: observedAt.toISOString(),
            });
          } else {
            const requiredCapabilities = stringSet(
              input.requiredCapabilities ?? [],
              'requiredCapabilities',
            );
            const verifiedCapabilities = stringSet(
              readback.capabilities ?? [],
              'providerReadback.capabilities',
            );
            const missingCapability = [...requiredCapabilities]
              .find((capability) => !verifiedCapabilities.has(capability));
            projection = missingCapability
              ? result({
                state: 'Needs attention',
                reasonCode: 'capability_probe_failed',
                lastVerifiedAt: observedAt.toISOString(),
              })
              : result({
                state: 'Connected',
                reasonCode: 'provider_verified',
                canUseNow: true,
                lastVerifiedAt: observedAt.toISOString(),
              });
          }
        }
      }
    }
  }

  const auditEvent = appendAuditEvent({
    previousEventHash: options.previousEventHash ?? null,
    eventType: 'connection.health.evaluated',
    actorType: 'service',
    actorId: 'connection-health-monitor',
    organizationId,
    subjectId: connectionId,
    outcome: projection.state.toLowerCase().replaceAll(' ', '_'),
    reasonCode: projection.reasonCode,
    occurredAt: now,
    evidence: {
      provider,
      previousState,
      nextState: projection.state,
      providerReceiptId: receiptId,
      lastVerifiedAt: projection.lastVerifiedAt,
    },
  });

  return Object.freeze({
    contractVersion: 'pandora-connection-health-v1',
    connectionId,
    organizationId,
    provider,
    ...projection,
    evaluatedAt: now.toISOString(),
    auditEvent,
  });
}
