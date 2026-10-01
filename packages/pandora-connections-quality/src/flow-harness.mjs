import { appendAuditEvent } from './audit-chain.mjs';
import { evaluateConnectionHealth } from './health-monitor.mjs';

const surfaces = new Set(['web', 'mobile']);
const statuses = new Set(['Disconnected', 'Authorizing', 'Verifying', 'Connected', 'Needs attention']);

function lastHash(state) {
  return state.auditChain.at(-1)?.eventHash ?? null;
}

function append(state, eventType, outcome, reasonCode, evidence, occurredAt) {
  const event = appendAuditEvent({
    previousEventHash: lastHash(state),
    eventType,
    actorType: 'user',
    actorId: 'connection-owner',
    organizationId: state.organizationId,
    subjectId: state.connectionId,
    outcome,
    reasonCode,
    occurredAt,
    evidence: { provider: state.provider, surface: state.surface, ...evidence },
  });
  return [...state.auditChain, event];
}

function next(state, changes, eventType, outcome, reasonCode, evidence, occurredAt) {
  const value = {
    ...state,
    ...changes,
    auditChain: append(state, eventType, outcome, reasonCode, evidence, occurredAt),
  };
  value.connected = value.status === 'Connected' && value.canUseNow === true;
  return Object.freeze(value);
}

export function createConnectionFlow({
  surface,
  connectionId,
  organizationId,
  provider,
  status = 'Disconnected',
}) {
  if (!surfaces.has(surface)) throw new TypeError('surface must be web or mobile');
  if (!statuses.has(status)) throw new TypeError('invalid initial status');
  return Object.freeze({
    contractVersion: 'pandora-connection-flow-v1',
    surface,
    connectionId,
    organizationId,
    provider,
    status,
    connected: status === 'Connected',
    canUseNow: status === 'Connected',
    resumeStatus: status,
    activeAccountId: null,
    pendingAccountId: null,
    auditChain: [],
  });
}

export function transitionConnectionFlow(state, event, options = {}) {
  const occurredAt = new Date(options.now ?? new Date()).toISOString();
  if (!state || !event || typeof event.type !== 'string') {
    throw new TypeError('state and event.type are required');
  }

  if (event.type === 'CONNECT') {
    if (!['Disconnected', 'Needs attention'].includes(state.status)) {
      throw new Error('connect is only valid while disconnected or needing attention');
    }
    return next(
      state,
      { status: 'Authorizing', connected: false, canUseNow: false, resumeStatus: state.status },
      'connection.authorization.started',
      'authorizing',
      state.status === 'Needs attention' ? 'reconnect_requested' : 'connect_requested',
      {},
      occurredAt,
    );
  }

  if (event.type === 'PROVIDER_RETURN') {
    if (state.status !== 'Authorizing') throw new Error('provider return requires Authorizing state');
    if (['back', 'cancelled'].includes(event.outcome)) {
      return next(
        state,
        { status: state.resumeStatus, connected: false, canUseNow: false },
        'connection.authorization.returned',
        event.outcome,
        event.outcome === 'back' ? 'authorization_back' : 'authorization_cancelled',
        {},
        occurredAt,
      );
    }
    if (event.outcome === 'denied') {
      return next(
        state,
        { status: 'Needs attention', connected: false, canUseNow: false },
        'connection.authorization.returned',
        'needs_attention',
        'scope_denied',
        {},
        occurredAt,
      );
    }
    if (event.outcome !== 'approved') throw new TypeError('invalid provider return outcome');
    const validChannel = state.surface === 'web'
      ? event.returnChannel === 'https_callback'
      : ['app_link', 'universal_link'].includes(event.returnChannel);
    if (!validChannel) {
      return next(
        state,
        { status: 'Needs attention', connected: false, canUseNow: false },
        'connection.authorization.returned',
        'needs_attention',
        'invalid_return_channel',
        {},
        occurredAt,
      );
    }
    return next(
      state,
      { status: 'Verifying', connected: false, canUseNow: false },
      'connection.authorization.returned',
      'verifying',
      'provider_approval_received',
      { returnChannel: event.returnChannel },
      occurredAt,
    );
  }

  if (event.type === 'PROVIDER_READBACK') {
    if (state.status !== 'Verifying') throw new Error('readback requires Verifying state');
    const projection = evaluateConnectionHealth(
      {
        ...event.input,
        connectionId: state.connectionId,
        organizationId: state.organizationId,
        provider: state.provider,
        previousState: state.resumeStatus,
        accountBinding: {
          ...event.input.accountBinding,
          accountId: state.pendingAccountId ?? event.input.accountBinding?.accountId,
        },
      },
      { ...options, previousEventHash: lastHash(state) },
    );
    return Object.freeze({
      ...state,
      status: projection.state,
      connected: projection.connected,
      canUseNow: projection.canUseNow,
      activeAccountId: projection.connected
        ? state.pendingAccountId ?? event.input.accountBinding.accountId
        : state.activeAccountId,
      pendingAccountId: null,
      auditChain: [...state.auditChain, projection.auditEvent],
    });
  }

  if (event.type === 'SWITCH_ACCOUNT') {
    if (state.status !== 'Connected' || !state.connected) {
      throw new Error('account switch requires a verified Connected state');
    }
    if (typeof event.accountId !== 'string' || !event.accountId.trim()) {
      throw new TypeError('accountId is required');
    }
    return next(
      state,
      {
        status: 'Verifying',
        connected: false,
        canUseNow: false,
        resumeStatus: 'Connected',
        pendingAccountId: event.accountId,
      },
      'connection.account.switch_requested',
      'verifying',
      'account_switch_requires_readback',
      { targetAccountId: event.accountId },
      occurredAt,
    );
  }

  if (event.type === 'DISCONNECT') {
    if (!['Connected', 'Needs attention'].includes(state.status)) {
      throw new Error('disconnect requires an existing connection');
    }
    return next(
      state,
      {
        status: 'Disconnected',
        connected: false,
        canUseNow: false,
        resumeStatus: 'Disconnected',
        activeAccountId: null,
        pendingAccountId: null,
      },
      'connection.disconnected',
      'disconnected',
      'owner_disconnect_confirmed',
      {},
      occurredAt,
    );
  }

  throw new TypeError(`unsupported event type: ${event.type}`);
}
