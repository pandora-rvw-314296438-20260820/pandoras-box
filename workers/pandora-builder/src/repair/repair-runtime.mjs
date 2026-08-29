async function executeRepairAttempt({ controller, failureClass, authorizationId, changedFiles, estimatedCostCents = 0, createWorkspace, applyChanges, rebuild, destroyWorkspace = async () => {}, signal = null }) {
  if (!controller || typeof controller.authorize !== 'function') throw new Error('REPAIR_CONTROLLER_REQUIRED');
  if (typeof createWorkspace !== 'function' || typeof applyChanges !== 'function' || typeof rebuild !== 'function') throw new Error('REPAIR_RUNTIME_DEPENDENCY_REQUIRED');
  if (signal?.aborted) throw signal.reason ?? new Error('REPAIR_CANCELLED');

  const plan = controller.authorize({ failureClass, authorizationId, changedFiles, estimatedCostCents });
  let workspace = null;
  try {
    workspace = await createWorkspace({ workspaceKey: plan.workspaceKey, repairAttempt: plan.repairAttempt, sourceDigest: plan.sourceDigest, signal });
    if (!workspace?.root) throw new Error('REPAIR_WORKSPACE_REQUIRED');
    const applied = await applyChanges({ workspace, changedFiles: plan.changedFiles, authorizationId, signal });
    if (signal?.aborted) throw signal.reason ?? new Error('REPAIR_CANCELLED');
    const result = await rebuild({ workspace, repairAttempt: plan.repairAttempt, signal });
    return Object.freeze({
      status: result?.status ?? 'failed',
      failureClass: result?.failureClass ?? null,
      repairAttempt: plan.repairAttempt,
      workspaceKey: plan.workspaceKey,
      sourceDigest: plan.sourceDigest,
      changedFiles: plan.changedFiles,
      applied: applied ?? null,
      result,
    });
  } finally {
    if (workspace) await destroyWorkspace({ workspace, workspaceKey: plan.workspaceKey }).catch(() => {});
  }
}

export { executeRepairAttempt };
