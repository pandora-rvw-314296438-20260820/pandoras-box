'use strict';

const { runContinuousExecution } = require('./continuous-executor.js');
const {
  deriveActivityProjection,
  normalizeActivityEvent,
  validateActivityProjection,
} = require('../../../pandora-activity-theatre');

const REALTIME_ACTIVITY_CONTRACT_VERSION = 'pandora-realtime-activity-stream-v1';

async function runRealtimeContinuousExecution(input, adapters, options) {
  if (!options || typeof options !== 'object') throw new TypeError('realtime options are required');
  const sink = options.sink;
  if (!sink || typeof sink.append !== 'function') throw new TypeError('realtime sink.append is required');
  const jobId = opaque(input?.jobId, 'jobId');
  const admittedBy = opaque(options.admittedBy, 'admittedBy');
  const admissionRef = ref(options.admissionRef, 'admissionRef');
  const writerEpoch = positive(options.writerEpoch ?? 1, 'writerEpoch');
  const clock = typeof options.clock === 'function' ? options.clock : () => new Date().toISOString();
  let nextSequence = positive(options.startSequence ?? 1, 'startSequence');
  let lastEventId = null;
  const emit = async ({ state, message, sourceType = 'runtime', sourceId = admittedBy,
    sourceEventId, evidence = [], capability = options.capability ?? null,
    executionId = options.executionId ?? null, blocker = null, outcome = null,
    eventId = null, occurredAt = null }) => {
    const sequence = nextSequence;
    const at = occurredAt ?? clock();
    const canonical = normalizeActivityEvent({
      schemaVersion: 1,
      eventId: eventId ?? `${jobId}:activity:${sequence}`,
      jobId,
      sequence,
      writerEpoch,
      admittedBy,
      admissionMode: 'online',
      state,
      message,
      occurredAt: at,
      admittedAt: at,
      provenance: { sourceType, sourceId, sourceEventId: canonicalSourceEventId(sourceEventId, `${jobId}:source:${sequence}`), observedAt: at },
      evidence,
      domain: options.domain ?? null,
      capability,
      executionId,
      parentEventId: lastEventId,
      blocker,
      outcome,
    });
    const projection = deriveActivityProjection(canonical);
    await sink.append(Object.freeze({
      contractVersion: REALTIME_ACTIVITY_CONTRACT_VERSION,
      event: canonical,
      projection,
    }));
    nextSequence += 1;
    lastEventId = canonical.eventId;
    return Object.freeze({ event: canonical, projection });
  };

  await emit({
    state: 'understanding',
    message: options.admissionMessage ?? 'Pandora admitted this request for execution.',
    sourceEventId: admissionRef,
    evidence: [{ type: 'runtime_event', relation: 'source', ref: admissionRef }],
  });

  const wrapped = { ...adapters };
  wrapped.reason = async (view) => {
    const decision = await adapters.reason(view);
    const decisionRef = ref(decision?.decisionRef, 'reason.decisionRef');
    await emit({
      state: 'planning',
      message: 'Pandora produced the next runtime decision.',
      sourceEventId: decisionRef,
      evidence: [{ type: 'runtime_event', relation: 'source', ref: decisionRef }],
      capability: decision?.action?.capability ?? options.capability ?? null,
    });
    return decision;
  };
  if (typeof adapters.actRead === 'function') {
    wrapped.actRead = async (action, view) => {
      const receipt = await adapters.actRead(action, view);
      const receiptRef = ref(receipt?.receiptRef, 'read receipt.receiptRef');
      await emit({
        state: 'acting',
        message: 'Pandora received a tool execution receipt.',
        sourceType: 'tool',
        sourceId: action.capability,
        sourceEventId: receiptRef,
        evidence: [{ type: 'tool_receipt', relation: 'source', ref: receiptRef }],
        capability: action.capability,
        executionId: action.actionId,
      });
      return receipt;
    };
  }

  if (typeof adapters.observeRead === 'function') {
    wrapped.observeRead = async (context) => {
      const observation = await adapters.observeRead(context);
      const observationRef = ref(observation?.observationRef, 'read observation.observationRef');
      await emit({
        state: 'checking',
        message: 'Pandora observed authoritative readback for the latest action.',
        sourceEventId: observationRef,
        evidence: [{ type: 'runtime_event', relation: 'readback', ref: observationRef }],
        capability: context.action.capability,
        executionId: context.action.actionId,
      });
      return observation;
    };
  }
  if (typeof adapters.executeGoverned === 'function') {
    wrapped.executeGoverned = async (action, view) => {
      const outcome = await adapters.executeGoverned(action, view);
      const sourceRef = ref(outcome?.receiptRef ?? outcome?.readbackRef, 'governed outcome source');
      const evidence = [{ type: 'provider_receipt', relation: 'source', ref: sourceRef }];
      if (outcome?.readbackRef) {
        evidence.push({ type: 'runtime_event', relation: 'readback', ref: ref(outcome.readbackRef, 'governed outcome.readbackRef') });
      }
      await emit({
        state: outcome?.state === 'needs_approval' ? 'needs_you' : 'acting',
        message: outcome?.summary || 'Pandora received a governed execution receipt.',
        sourceType: 'provider',
        sourceId: action.capability,
        sourceEventId: sourceRef,
        evidence,
        capability: action.capability,
        executionId: action.actionId,
        blocker: outcome?.state === 'needs_approval' ? {
          reasonCode: 'authorization_required',
          reason: outcome?.summary || 'Authorization is required.',
          requiredAction: 'Review and approve the requested consequential action.',
          approvalRequired: true,
          policyRef: outcome?.policyRef ?? null,
        } : null,
      });
      return outcome;
    };
  }

  wrapped.verify = async (view) => {
    const verification = await adapters.verify(view);
    const verifyRef = ref(verification?.verificationReceiptRef ?? `runtime:${jobId}:verification:${view.iteration}`, 'verification source');
    await emit({
      state: 'verifying',
      message: verification?.summary || 'Pandora completed an independent verification pass.',
      sourceEventId: verifyRef,
      evidence: [{ type: verification?.verificationReceiptRef ? 'verification_receipt' : 'runtime_event', relation: 'source', ref: verifyRef }],
    });
    return verification;
  };
  if (typeof adapters.projectResult === 'function') {
    wrapped.projectResult = async (payload) => {
      const projection = await adapters.projectResult(Object.freeze({
        ...payload,
        activityCursor: Object.freeze({ nextSequence, writerEpoch, lastEventId }),
      }));
      if (!projection || typeof projection !== 'object' || Array.isArray(projection)) {
        throw new TypeError('activity result projection must be an object');
      }
      if (projection.sequence !== nextSequence) {
        throw new Error('activity result projection must use the next canonical sequence');
      }
      const source = projection.source || {};
      const canonical = normalizeActivityEvent({
        schemaVersion: 1,
        eventId: projection.eventId,
        jobId,
        sequence: projection.sequence,
        writerEpoch,
        admittedBy,
        admissionMode: 'online',
        state: 'result',
        message: projection.message,
        occurredAt: projection.occurredAt,
        admittedAt: projection.admittedAt,
        provenance: {
          sourceType: source.sourceType,
          sourceId: source.sourceId,
          sourceEventId: source.sourceEventId,
          observedAt: source.observedAt,
        },
        evidence: projection.evidenceRefs,
        domain: projection.domain,
        capability: projection.capability,
        executionId: projection.executionId,
        parentEventId: lastEventId,
        outcome: projection.outcome,
      });
      validateActivityProjection(projection, canonical);
      await sink.append(Object.freeze({
        contractVersion: REALTIME_ACTIVITY_CONTRACT_VERSION,
        event: canonical,
        projection,
      }));
      nextSequence += 1;
      lastEventId = canonical.eventId;
      return projection;
    };
  }

  const result = await runContinuousExecution(input, wrapped);
  if (typeof sink.complete === 'function') {
    await sink.complete(Object.freeze({
      contractVersion: REALTIME_ACTIVITY_CONTRACT_VERSION,
      jobId,
      status: result.status,
      verified: result.verified,
      lastSequence: nextSequence - 1,
      lastEventId,
    }));
  }
  return result;
}

function opaque(value, field) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$/.test(value.trim())) {
    throw new TypeError(`${field} must be an opaque identifier`);
  }
  return value.trim();
}
function ref(value, field) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`);
  const result = value.trim();
  if (result.length > 500) throw new Error(`${field} is too long`);
  return result;
}

function positive(value, field) {
  if (!Number.isSafeInteger(value) || value < 1) throw new TypeError(`${field} must be a positive safe integer`);
  return value;
}

function canonicalSourceEventId(value, fallback) {
  if (typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$/.test(value.trim())) {
    return value.trim();
  }
  return fallback;
}

module.exports = {
  REALTIME_ACTIVITY_CONTRACT_VERSION,
  runRealtimeContinuousExecution,
};
