const EXACT_WORKER_A_RPCS = Object.freeze({
  claim: 'pandora_claim_build_job',
  heartbeat: 'pandora_heartbeat_build_job',
  requeueExpired: 'pandora_requeue_expired_build_jobs',
});

const CONTROL_PLANE_OPERATIONS = Object.freeze({
  readControl: 'build_job.read_control',
  checkpoint: 'build_job.checkpoint',
  finish: 'build_job.finish',
});

class BuildJobControlPort {
  constructor(transport) {
    if (!transport || typeof transport.call !== 'function') throw new Error('CONTROL_PLANE_TRANSPORT_REQUIRED');
    this.transport = transport;
  }
  claim({ jobId, workerIdentity, leaseTokenSha256, leaseSeconds = 300 }) {
    return this.transport.call(EXACT_WORKER_A_RPCS.claim, { jobId, workerIdentity, leaseTokenSha256, leaseSeconds });
  }
  heartbeat({ jobId, workerIdentity, leaseTokenSha256, leaseSeconds = 300 }) {
    return this.transport.call(EXACT_WORKER_A_RPCS.heartbeat, { jobId, workerIdentity, leaseTokenSha256, leaseSeconds });
  }
  requeueExpired({ limit = 100 }) {
    return this.transport.call(EXACT_WORKER_A_RPCS.requeueExpired, { limit });
  }
  readControl({ jobId }) {
    return this.transport.call(CONTROL_PLANE_OPERATIONS.readControl, { jobId });
  }
  checkpoint({ jobId, stepKey, inputSha256, resultSha256, safePayload = {} }) {
    return this.transport.call(CONTROL_PLANE_OPERATIONS.checkpoint, { jobId, stepKey, inputSha256, resultSha256, safePayload });
  }
  finish({ jobId, workerIdentity, leaseTokenSha256, outcome, errorCode = null, publicErrorSummary = null, resourceUsage = {} }) {
    return this.transport.call(CONTROL_PLANE_OPERATIONS.finish, { jobId, workerIdentity, leaseTokenSha256, outcome, errorCode, publicErrorSummary, resourceUsage });
  }
}

async function waitForInterval(intervalMs, signal) {
  if (signal?.aborted) return;
  await new Promise((resolve) => {
    const timer = setTimeout(resolve, intervalMs);
    signal?.addEventListener('abort', () => { clearTimeout(timer); resolve(); }, { once: true });
  });
}

async function durableControlLoop({ port, identity, heartbeatIntervalMs = 30_000, cancelPollMs = 2_000, signal, onLostLease = () => {}, onCancellation = () => {} }) {
  let nextHeartbeat = Date.now();
  while (!signal?.aborted) {
    const now = Date.now();
    if (now >= nextHeartbeat) {
      const ok = await port.heartbeat(identity);
      if (!ok) { onLostLease(); throw new Error('BUILD_JOB_LEASE_LOST'); }
      nextHeartbeat = now + heartbeatIntervalMs;
    }
    const state = await port.readControl({ jobId: identity.jobId });
    if (state?.cancelRequestedAt) { onCancellation(state); return Object.freeze({ cancelled: true, state }); }
    await waitForInterval(Math.min(cancelPollMs, Math.max(1, nextHeartbeat - Date.now())), signal);
  }
  return Object.freeze({ cancelled: false, state: null });
}

export { BuildJobControlPort, CONTROL_PLANE_OPERATIONS, EXACT_WORKER_A_RPCS, durableControlLoop };
