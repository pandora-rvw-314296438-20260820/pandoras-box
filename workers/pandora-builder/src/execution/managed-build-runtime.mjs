import { withCredentialLeases } from '../credentials/credential-lease-manager.mjs';

async function executeManagedBuild({ request, leaseToken, controlPlane, admissionController, admissionSnapshot, journal, credentialManager, execute, eventSink = () => {}, heartbeatIntervalMs = null }) {
  if (!request?.buildJobId || !request?.idempotencyKey) throw new Error('MANAGED_BUILD_REQUEST_REQUIRED');
  if (!controlPlane || !admissionController || !journal || !credentialManager || typeof execute !== 'function') throw new Error('MANAGED_BUILD_DEPENDENCY_REQUIRED');

  const admission = admissionController.decide({ job: { organizationId: request.organizationId, projectId: request.projectId }, snapshot: admissionSnapshot });
  if (!admission.admitted) return Object.freeze({ status: 'deferred', reason: admission.reason });

  await controlPlane.claim(request.buildJobId, leaseToken);
  const stepKey = `build:${request.buildJobId}:${request.attempt}`;
  const prepared = await journal.prepare({ stepKey, idempotencyKey: request.idempotencyKey, input: request });
  if (prepared.action === 'replay') return Object.freeze({ status: 'replayed', result: prepared.result, resultSha256: prepared.resultSha256 });
  if (prepared.action === 'ambiguous') throw new Error('BUILD_OUTCOME_AMBIGUOUS');
  if (prepared.action === 'in_progress') return Object.freeze({ status: 'deferred', reason: 'BUILD_ALREADY_IN_PROGRESS' });
  if (prepared.action === 'blocked') return Object.freeze({ status: 'blocked', reason: prepared.reason });

  const leaseExpiresAt = new Date(Date.now() + controlPlane.leaseSeconds * 1000).toISOString();
  await journal.begin({ stepKey, idempotencyKey: request.idempotencyKey, inputSha256: prepared.inputSha256, attemptCount: request.attempt, maxAttempts: 100, leaseExpiresAt });

  const checkpoint = async (event) => {
    eventSink(event);
    await controlPlane.checkpoint(event);
  };

  const abortController = new AbortController();
  const intervalMs = heartbeatIntervalMs ?? Math.max(10_000, Math.min(60_000, Math.floor(controlPlane.leaseSeconds * 1000 / 3)));
  let heartbeatFailure = null;
  let tickRunning = false;
  const timer = setInterval(async () => {
    if (tickRunning || abortController.signal.aborted) return;
    tickRunning = true;
    try {
      await controlPlane.heartbeat(request.buildJobId, leaseToken);
      if (await controlPlane.cancellationRequested(request.buildJobId)) abortController.abort(new Error('BUILD_CANCEL_REQUESTED'));
    } catch (error) {
      heartbeatFailure = error;
      abortController.abort(error);
    } finally {
      tickRunning = false;
    }
  }, intervalMs);

  try {
    if (await controlPlane.cancellationRequested(request.buildJobId)) {
      await journal.fail({ stepKey, idempotencyKey: request.idempotencyKey, inputSha256: prepared.inputSha256, failureClass: 'cancelled', retryable: false, attemptCount: request.attempt, maxAttempts: 100 });
      return Object.freeze({ status: 'cancelled', failureClass: 'cancelled' });
    }
    await controlPlane.heartbeat(request.buildJobId, leaseToken);
    return await withCredentialLeases(credentialManager, request.credentialLeaseRefs, async (leaseSet) => {
      const result = await execute({ request, environment: leaseSet.environment, credentialValues: leaseSet.redactionValues, eventSink: checkpoint, signal: abortController.signal });
      if (heartbeatFailure) throw heartbeatFailure;
      const normalizedResult = abortController.signal.aborted
        ? { status: 'cancelled', failureClass: 'cancelled', retryable: false }
        : result;
      if (normalizedResult?.status === 'completed') {
        await journal.complete({ stepKey, idempotencyKey: request.idempotencyKey, inputSha256: prepared.inputSha256, result: normalizedResult });
      } else {
        await journal.fail({ stepKey, idempotencyKey: request.idempotencyKey, inputSha256: prepared.inputSha256, failureClass: normalizedResult?.failureClass ?? 'unknown', retryable: Boolean(normalizedResult?.retryable), attemptCount: request.attempt, maxAttempts: 100 });
      }
      if (!abortController.signal.aborted) await controlPlane.heartbeat(request.buildJobId, leaseToken);
      return normalizedResult;
    });
  } catch (error) {
    if (error?.message !== 'BUILD_OUTCOME_AMBIGUOUS') {
      await journal.fail({ stepKey, idempotencyKey: request.idempotencyKey, inputSha256: prepared.inputSha256, failureClass: abortController.signal.aborted || error?.name === 'AbortError' ? 'cancelled' : 'unknown', retryable: false, attemptCount: request.attempt, maxAttempts: 100 }).catch(() => {});
    }
    throw error;
  } finally {
    clearInterval(timer);
  }
}

export { executeManagedBuild };
