const REPAIR_DISPOSITIONS = Object.freeze({
  AUTO_REPAIRABLE: 'AUTO_REPAIRABLE',
  RETRY_INFRASTRUCTURE: 'RETRY_INFRASTRUCTURE',
  NEEDS_USER_INPUT: 'NEEDS_USER_INPUT',
  POLICY_BLOCKED: 'POLICY_BLOCKED',
  NON_REPAIRABLE: 'NON_REPAIRABLE',
  BUDGET_EXCEEDED: 'BUDGET_EXCEEDED',
  DEADLINE_EXCEEDED: 'DEADLINE_EXCEEDED',
  SECURITY_BLOCKED: 'SECURITY_BLOCKED',
});

function diagnosticText(diagnostics = []) {
  return diagnostics.map((item) => `${item?.errorCode ?? ''} ${item?.message ?? ''}`).join('\n').slice(0, 20_000);
}

function classifyRepairDisposition({ failureClass, diagnostics = [] } = {}) {
  const text = diagnosticText(diagnostics);

  if (['credential', 'authorization'].includes(failureClass)) return REPAIR_DISPOSITIONS.NEEDS_USER_INPUT;
  if (['network', 'timeout', 'sandbox'].includes(failureClass)) return REPAIR_DISPOSITIONS.RETRY_INFRASTRUCTURE;
  if (failureClass === 'resource_limit') return REPAIR_DISPOSITIONS.NON_REPAIRABLE;
  if (failureClass === 'configuration') {
    if (/missing (?:environment|credential|api|provider)|authorization|domain ownership|billing/i.test(text)) {
      return REPAIR_DISPOSITIONS.NEEDS_USER_INPUT;
    }
    return REPAIR_DISPOSITIONS.NON_REPAIRABLE;
  }
  if (failureClass === 'filesystem') {
    if (/path escape|permission denied|read-only|eacces|eperm/i.test(text)) return REPAIR_DISPOSITIONS.SECURITY_BLOCKED;
    return REPAIR_DISPOSITIONS.NON_REPAIRABLE;
  }
  if (failureClass === 'dependency') {
    if (/unauthorized|authentication|credential|private registry|payment|billing/i.test(text)) {
      return REPAIR_DISPOSITIONS.NEEDS_USER_INPUT;
    }
    if (/network|econn|enotfound|registry unavailable|temporary failure/i.test(text)) {
      return REPAIR_DISPOSITIONS.RETRY_INFRASTRUCTURE;
    }
    return REPAIR_DISPOSITIONS.NON_REPAIRABLE;
  }
  if (['syntax', 'type', 'compile'].includes(failureClass)) return REPAIR_DISPOSITIONS.AUTO_REPAIRABLE;
  if (failureClass === 'test') {
    return diagnostics.some((item) => item?.filePath)
      ? REPAIR_DISPOSITIONS.AUTO_REPAIRABLE
      : REPAIR_DISPOSITIONS.NON_REPAIRABLE;
  }
  return REPAIR_DISPOSITIONS.NON_REPAIRABLE;
}

export { REPAIR_DISPOSITIONS, classifyRepairDisposition };
