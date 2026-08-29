const TERMINAL = new Set(['succeeded', 'failed', 'cancelled']);

function classifyBuildJobRecovery(job, now = new Date()) {
  if (!job || typeof job !== 'object') throw new Error('BUILD_JOB_REQUIRED');
  if (TERMINAL.has(job.status)) return { action: 'none', reason: 'TERMINAL' };
  if (job.cancel_requested_at) return { action: 'cancel', reason: 'CANCEL_REQUESTED' };
  if (!job.lease_expires_at) return job.status === 'queued' ? { action: 'claim', reason: 'QUEUED' } : { action: 'inspect', reason: 'UNLEASED_NONTERMINAL' };
  const expires = Date.parse(job.lease_expires_at);
  if (!Number.isFinite(expires)) return { action: 'quarantine', reason: 'INVALID_LEASE' };
  if (expires > now.getTime()) return { action: 'none', reason: 'LEASE_ACTIVE' };
  if (job.status === 'claimed') return { action: 'requeue', reason: 'EXPIRED_BEFORE_EXECUTION' };
  if (job.status === 'running') return { action: 'quarantine', reason: 'LEASE_EXPIRED_OUTCOME_UNKNOWN' };
  return { action: 'inspect', reason: 'EXPIRED_NONRUNNING' };
}

function orphanSandboxCleanupPlan({ sandboxes, liveBuildJobIds }) {
  const live = new Set(liveBuildJobIds ?? []);
  return Object.freeze((sandboxes ?? []).filter((sandbox) => sandbox?.buildJobId && !live.has(sandbox.buildJobId)).map((sandbox) => Object.freeze({ sandboxId: sandbox.id, buildJobId: sandbox.buildJobId, action: 'destroy' })));
}

export { classifyBuildJobRecovery, orphanSandboxCleanupPlan };
