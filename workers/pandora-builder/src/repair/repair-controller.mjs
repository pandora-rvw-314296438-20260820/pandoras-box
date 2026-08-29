const RETRYABLE_FAILURES = new Set(['dependency', 'syntax', 'type', 'compile', 'test', 'configuration', 'filesystem']);

function validateChangedFiles(files, limits) {
  if (!Array.isArray(files)) throw new Error('REPAIR_CHANGED_FILES_REQUIRED');
  if (files.length > limits.maxChangedFiles) throw new Error('REPAIR_CHANGED_FILE_LIMIT_EXCEEDED');
  let bytes = 0;
  const normalized = files.map((file) => {
    if (!file || typeof file !== 'object' || typeof file.path !== 'string' || file.path.startsWith('/') || file.path.includes('..')) throw new Error('REPAIR_CHANGED_FILE_INVALID');
    if (!['create', 'modify', 'delete', 'move'].includes(file.operation)) throw new Error('REPAIR_CHANGED_FILE_INVALID');
    const sizeBytes = Number(file.sizeBytes ?? 0);
    if (!Number.isInteger(sizeBytes) || sizeBytes < 0) throw new Error('REPAIR_CHANGED_FILE_INVALID');
    bytes += sizeBytes;
    return Object.freeze({ path: file.path, operation: file.operation, beforeSha256: file.beforeSha256 ?? null, afterSha256: file.afterSha256 ?? null, sizeBytes });
  });
  if (bytes > limits.maxChangedBytes) throw new Error('REPAIR_CHANGED_BYTES_LIMIT_EXCEEDED');
  return Object.freeze({ files: Object.freeze(normalized), bytes });
}

function createRepairController({ buildJobId, sourceDigest, budget = {}, clock = () => new Date() }) {
  const limits = Object.freeze({
    maxAttempts: budget.maxAttempts ?? 3,
    maxWallClockMs: budget.maxWallClockMs ?? 20 * 60_000,
    maxChangedFiles: budget.maxChangedFiles ?? 100,
    maxChangedBytes: budget.maxChangedBytes ?? 4 * 1024 * 1024,
    maxCostCents: budget.maxCostCents ?? 100,
    deadlineAt: budget.deadlineAt ?? null,
  });
  if (!Number.isInteger(limits.maxAttempts) || limits.maxAttempts < 1 || limits.maxAttempts > 10) throw new Error('INVALID_REPAIR_BUDGET');
  const startedAt = clock();
  let attempts = 0;
  let spentCents = 0;
  let cancelled = false;

  return Object.freeze({
    authorize({ failureClass, changedFiles, estimatedCostCents = 0, authorizationId }) {
      if (cancelled) throw new Error('REPAIR_CANCELLED');
      if (!RETRYABLE_FAILURES.has(failureClass)) throw new Error('REPAIR_FAILURE_NOT_ELIGIBLE');
      if (typeof authorizationId !== 'string' || authorizationId.length < 3) throw new Error('REPAIR_AUTHORIZATION_REQUIRED');
      const now = clock();
      if (now.getTime() - startedAt.getTime() > limits.maxWallClockMs) throw new Error('REPAIR_WALL_CLOCK_BUDGET_EXCEEDED');
      if (limits.deadlineAt && now.getTime() >= Date.parse(limits.deadlineAt)) throw new Error('REPAIR_DEADLINE_EXCEEDED');
      if (attempts >= limits.maxAttempts) throw new Error('REPAIR_ATTEMPT_BUDGET_EXCEEDED');
      if (!Number.isInteger(estimatedCostCents) || estimatedCostCents < 0 || spentCents + estimatedCostCents > limits.maxCostCents) throw new Error('REPAIR_COST_BUDGET_EXCEEDED');
      const manifest = validateChangedFiles(changedFiles, limits);
      attempts += 1;
      spentCents += estimatedCostCents;
      return Object.freeze({
        buildJobId,
        sourceDigest,
        repairAttempt: attempts,
        authorizationId,
        workspaceKey: `${buildJobId}:repair:${attempts}`,
        changedFiles: manifest.files,
        changedBytes: manifest.bytes,
        estimatedCostCents,
        cumulativeCostCents: spentCents,
      });
    },
    cancel() { cancelled = true; },
    snapshot() { return Object.freeze({ buildJobId, sourceDigest, attempts, spentCents, cancelled, limits }); },
  });
}

export { createRepairController, validateChangedFiles };
