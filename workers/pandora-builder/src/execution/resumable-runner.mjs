import { durableControlLoop } from '../control-plane/build-job-port.mjs';

function abortReason(signal) {
  return signal?.reason instanceof Error ? signal.reason : new Error('BUILD_EXECUTION_ABORTED');
}

async function runResumableBuild({ control, identity, admission, projectId, pressure, execute, cancel, cleanup, signal, heartbeatIntervalMs = 30_000, cancelPollMs = 2_000 }) {
  const gate = admission.admit({ jobId: identity.jobId, projectId }, pressure);
  if (!gate.admitted) return Object.freeze({ status: 'deferred', reason: gate.reason });
  const monitorAbort = new AbortController();
  const executionAbort = new AbortController();
  const relayAbort = () => executionAbort.abort(abortReason(signal));
  signal?.addEventListener('abort', relayAbort, { once: true });
  let monitorTask = null;
  let leaseLost = false;
  let durableCancellation = null;
  try {
    const claimed = await control.claim(identity);
    if (!claimed) return Object.freeze({ status: 'not_claimed' });
    const initial = await control.readControl({ jobId: identity.jobId });
    if (initial?.cancelRequestedAt) {
      await cancel?.();
      await cleanup?.();
      await control.finish({ ...identity, outcome: 'cancelled' });
      return Object.freeze({ status: 'cancelled' });
    }

    monitorTask = durableControlLoop({
      port: control, identity, heartbeatIntervalMs, cancelPollMs, signal: monitorAbort.signal,
      onLostLease: () => { leaseLost = true; executionAbort.abort(new Error('BUILD_JOB_LEASE_LOST')); },
      onCancellation: (state) => { durableCancellation = state; executionAbort.abort(new Error('BUILD_JOB_CANCEL_REQUESTED')); },
    });

    const executionTask = Promise.resolve().then(() => execute({ checkpoint: initial?.checkpoint ?? null, signal: executionAbort.signal }));
    const monitorFailure = monitorTask.then((result) => {
      if (result.cancelled) throw new Error('BUILD_JOB_CANCEL_REQUESTED');
      return new Promise(() => {});
    });

    let result;
    try {
      result = await Promise.race([executionTask, monitorFailure]);
    } catch (error) {
      if (leaseLost) { await cancel?.(); await cleanup?.(); throw error; }
      if (durableCancellation || error?.message === 'BUILD_JOB_CANCEL_REQUESTED') {
        await cancel?.(); await cleanup?.();
        await control.finish({ ...identity, outcome: 'cancelled' });
        return Object.freeze({ status: 'cancelled' });
      }
      throw error;
    } finally {
      monitorAbort.abort();
      await monitorTask?.catch((error) => { if (!leaseLost && error?.message !== 'BUILD_JOB_CANCEL_REQUESTED') throw error; });
    }

    const latest = await control.readControl({ jobId: identity.jobId });
    if (latest?.cancelRequestedAt) {
      await cancel?.(); await cleanup?.();
      await control.finish({ ...identity, outcome: 'cancelled' });
      return Object.freeze({ status: 'cancelled', result });
    }
    await control.finish({ ...identity, outcome: result.status === 'completed' ? 'succeeded' : 'failed', errorCode: result.failureClass ?? null, publicErrorSummary: result.publicErrorSummary ?? null, resourceUsage: result.resourceUsage ?? {} });
    return result;
  } finally {
    monitorAbort.abort();
    signal?.removeEventListener('abort', relayAbort);
    admission.release(identity.jobId);
  }
}

export { runResumableBuild };
