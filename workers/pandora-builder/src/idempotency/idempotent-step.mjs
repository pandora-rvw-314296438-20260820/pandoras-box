const FINAL = new Set(['succeeded', 'failed', 'cancelled', 'skipped']);

async function runIdempotentStep({ store, identity, inputSha256, mutation = false, execute }) {
  if (!store || typeof store.read !== 'function' || typeof store.begin !== 'function' || typeof store.complete !== 'function') throw new Error('IDEMPOTENCY_STORE_REQUIRED');
  if (!identity?.jobId || !identity?.stepKey || !/^[0-9a-f]{64}$/.test(inputSha256 ?? '') || typeof execute !== 'function') throw new Error('INVALID_IDEMPOTENT_STEP');
  const prior = await store.read(identity);
  if (prior) {
    if (prior.inputSha256 !== inputSha256) throw new Error('IDEMPOTENCY_INPUT_CONFLICT');
    if (prior.status === 'succeeded') return Object.freeze({ status: 'succeeded', replay: true, result: prior.result, resultSha256: prior.resultSha256 ?? null });
    if (!FINAL.has(prior.status) && mutation) throw new Error('AMBIGUOUS_PRIOR_MUTATION_OUTCOME');
    if (prior.status === 'cancelled') return Object.freeze({ status: 'cancelled', replay: true, result: prior.result ?? null });
  }
  const begun = await store.begin({ ...identity, inputSha256, mutation });
  if (begun?.status === 'succeeded') return Object.freeze({ status: 'succeeded', replay: true, result: begun.result, resultSha256: begun.resultSha256 ?? null });
  let result;
  try {
    result = await execute();
  } catch (error) {
    await store.fail?.({ ...identity, inputSha256, failureClass: error?.failureClass ?? 'unknown' });
    throw error;
  }
  const completed = await store.complete({ ...identity, inputSha256, result });
  return Object.freeze({ status: 'succeeded', replay: false, result, resultSha256: completed?.resultSha256 ?? null });
}

export { runIdempotentStep };
