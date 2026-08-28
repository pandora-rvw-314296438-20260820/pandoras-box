function assertRepairBudget(budget, usage, now = Date.now()) {
  if (!budget || !Number.isInteger(budget.maxAttempts) || budget.maxAttempts < 1) throw new Error('INVALID_REPAIR_BUDGET');
  if (usage.attempts >= budget.maxAttempts) throw new Error('REPAIR_ATTEMPTS_EXHAUSTED');
  if (budget.deadlineAt && now >= new Date(budget.deadlineAt).getTime()) throw new Error('REPAIR_DEADLINE_EXCEEDED');
  if (budget.maxElapsedMs != null && usage.elapsedMs >= budget.maxElapsedMs) throw new Error('REPAIR_ELAPSED_BUDGET_EXCEEDED');
  if (budget.maxBuildMs != null && usage.buildMs >= budget.maxBuildMs) throw new Error('REPAIR_BUILD_BUDGET_EXCEEDED');
  if (budget.maxComputeMillis != null && usage.computeMillis >= budget.maxComputeMillis) throw new Error('REPAIR_COMPUTE_BUDGET_EXCEEDED');
  if (budget.maxCostMicrounits != null && usage.costMicrounits >= budget.maxCostMicrounits) throw new Error('REPAIR_COST_BUDGET_EXCEEDED');
  return true;
}

function createRepairAttempt({ attempt, parentAttempt = null, inputSourceDigest, proposalDigest, authorizedActionId, startedAt = new Date().toISOString() }) {
  if (!Number.isInteger(attempt) || attempt < 1 || !/^[0-9a-f]{64}$/.test(inputSourceDigest ?? '') || !/^[0-9a-f]{64}$/.test(proposalDigest ?? '') || !authorizedActionId) throw new Error('INVALID_REPAIR_ATTEMPT');
  return Object.freeze({ schemaVersion: 1, attempt, parentAttempt, inputSourceDigest, proposalDigest, authorizedActionId, startedAt });
}

function finishRepairAttempt(record, { status, changedFiles = [], artifactDigest = null, failureClass = null, finishedAt = new Date().toISOString() }) {
  if (!['completed','failed','cancelled'].includes(status)) throw new Error('INVALID_REPAIR_STATUS');
  return Object.freeze({ ...record, status, changedFiles: Object.freeze([...changedFiles]), artifactDigest, failureClass, finishedAt });
}

export { assertRepairBudget, createRepairAttempt, finishRepairAttempt };
