import { assertRepairBudget, createRepairAttempt, finishRepairAttempt } from './repair-attempt-manager.mjs';

async function runRepairLoop({ initialResult, budget, usage, sourceDigest, proposeAuthorizedRepair, prepareAttempt, applyRepair, rebuild, onAttempt = () => {} }) {
  let result = initialResult;
  let currentSourceDigest = sourceDigest;
  let parentAttempt = null;
  const attempts = [];
  while (result?.status !== 'completed') {
    assertRepairBudget(budget, usage);
    const nextAttempt = usage.attempts + 1;
    const approved = await proposeAuthorizedRepair({ failure: result, attempt: nextAttempt, sourceDigest: currentSourceDigest });
    if (!approved?.authorizationId || !/^[0-9a-f]{64}$/.test(approved.proposalDigest ?? '')) throw new Error('AUTHORIZED_REPAIR_REQUIRED');
    const record = createRepairAttempt({ attempt: nextAttempt, parentAttempt, inputSourceDigest: currentSourceDigest, proposalDigest: approved.proposalDigest, authorizedActionId: approved.authorizationId });
    const workspace = await prepareAttempt({ attempt: nextAttempt, parentAttempt, sourceDigest: currentSourceDigest });
    onAttempt(Object.freeze({ phase: 'started', record, workspace }));
    let repair;
    try {
      repair = await applyRepair({ workspace, proposal: approved.proposal, authorization: approved });
      result = await rebuild({ workspace, attempt: nextAttempt });
    } catch (error) {
      result = { status: 'failed', failureClass: error?.failureClass ?? 'unknown' };
    }
    const finished = finishRepairAttempt(record, { status: result.status === 'completed' ? 'completed' : 'failed', changedFiles: repair?.changedFiles ?? [], artifactDigest: result?.manifest?.manifestSha256 ?? result?.artifactDigest ?? null, failureClass: result?.failureClass ?? null });
    attempts.push(finished);
    onAttempt(Object.freeze({ phase: 'finished', record: finished, workspace }));
    usage.attempts += 1;
    usage.buildMs += Number(result?.resourceUsage?.buildMs ?? 0);
    usage.computeMillis += Number(result?.resourceUsage?.computeMillis ?? 0);
    usage.costMicrounits += Number(result?.resourceUsage?.costMicrounits ?? 0);
    currentSourceDigest = repair?.outputSourceDigest ?? currentSourceDigest;
    parentAttempt = nextAttempt;
  }
  return Object.freeze({ result, attempts: Object.freeze(attempts), usage: Object.freeze({ ...usage }) });
}

export { runRepairLoop };
