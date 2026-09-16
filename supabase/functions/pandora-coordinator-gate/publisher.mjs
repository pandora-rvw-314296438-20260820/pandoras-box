import {
  INTEGRATION_APP_ID,
  RULE_CONTEXT,
  bindEnvelope,
  desiredCheckState,
  parseCheckExternalId,
} from "./contract.mjs";

function asRecord(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function trustedChecks(rows, headSha) {
  return (Array.isArray(rows) ? rows : []).filter((row) => {
    const check = asRecord(row);
    const app = asRecord(check.app);
    return check.name === RULE_CONTEXT && check.head_sha === headSha && app.id === INTEGRATION_APP_ID;
  });
}

function assertLiveIdentity(envelope, pull, mainSha) {
  const pr = asRecord(pull);
  const head = asRecord(pr.head);
  const base = asRecord(pr.base);
  if (
    pr.number !== envelope.pullRequestNumber || pr.state !== "open" || pr.merged === true ||
    head.sha !== envelope.headSha || base.ref !== "main" || base.sha !== envelope.baseSha ||
    mainSha !== envelope.baseSha
  ) throw new Error("LIVE_IDENTITY_MISMATCH");
}
function matchesDesired(check, desired) {
  const row = asRecord(check);
  return row.name === desired.name && row.head_sha === desired.head_sha &&
    row.external_id === desired.external_id && row.status === desired.status &&
    row.conclusion === desired.conclusion && asRecord(row.app).id === INTEGRATION_APP_ID;
}

function inProgressState(desired, evaluatedAt) {
  return {
    name: desired.name,
    head_sha: desired.head_sha,
    external_id: desired.external_id,
    status: "in_progress",
    started_at: evaluatedAt,
    output: {
      title: "Pandora coordinator evaluation",
      summary: "Trusted coordinator decision is being provider-bound and verified.",
    },
  };
}

async function readExact(provider, checkRunId) {
  const check = await provider.getCheck(checkRunId);
  if (asRecord(check).id !== checkRunId || asRecord(asRecord(check).app).id !== INTEGRATION_APP_ID) {
    throw new Error("CHECK_READBACK_IDENTITY_MISMATCH");
  }
  return check;
}
async function readByExternalId(provider, headSha, externalId) {
  const rows = trustedChecks(await provider.listChecks(headSha), headSha);
  const matches = rows.filter((row) => asRecord(row).external_id === externalId);
  if (matches.length > 1) throw new Error("DUPLICATE_TRUSTED_CHECKS");
  return matches[0] || null;
}

async function writeAndRead({ provider, kind, checkRunId, payload, headSha }) {
  try {
    const response = kind === "create"
      ? await provider.createCheck(payload)
      : await provider.updateCheck(checkRunId, payload);
    const id = Number(asRecord(response).id || checkRunId || 0);
    if (!Number.isSafeInteger(id) || id < 1) throw new Error("CHECK_WRITE_INVALID_RESPONSE");
    return await readExact(provider, id);
  } catch (error) {
    if (!(error instanceof Error) || error.message !== "GITHUB_WRITE_AMBIGUOUS") throw error;
    const reconciled = await readByExternalId(provider, headSha, payload.external_id);
    if (!reconciled) throw error;
    return reconciled;
  }
}
async function assertChain(provider, existing, envelope) {
  if (!existing) {
    if (envelope.decisionGeneration === 1) {
      if (envelope.priorGeneration !== null || envelope.priorCheckRunId !== null) {
        throw new Error("DECISION_CHAIN_MISMATCH");
      }
      return null;
    }
    if (envelope.priorGeneration !== envelope.decisionGeneration - 1) {
      throw new Error("DECISION_CHAIN_MISMATCH");
    }
    if (envelope.priorCheckRunId === null) {
      return null;
    }
    const prior = asRecord(await provider.getCheck(envelope.priorCheckRunId));
    const priorMeta = parseCheckExternalId(prior.external_id);
    if (!priorMeta || prior.id !== envelope.priorCheckRunId ||
        asRecord(prior.app).id !== INTEGRATION_APP_ID || prior.name !== RULE_CONTEXT ||
        priorMeta.generation !== envelope.priorGeneration) {
      throw new Error("DECISION_CHAIN_MISMATCH");
    }
    return null;
  }
  const row = asRecord(existing);
  const meta = parseCheckExternalId(row.external_id);
  if (!meta) throw new Error("TRUSTED_CHECK_METADATA_INVALID");
  if (!Number.isSafeInteger(row.id) || row.id < 1) throw new Error("TRUSTED_CHECK_ID_INVALID");
  if (meta.generation > envelope.decisionGeneration) throw new Error("STALE_DECISION_GENERATION");
  if (meta.generation < envelope.decisionGeneration && (
    envelope.priorGeneration !== meta.generation || envelope.priorCheckRunId !== row.id
  )) throw new Error("DECISION_CHAIN_MISMATCH");
  return meta;
}

function finalStateMatches(check, desired) {
  return matchesDesired(check, desired);
}
async function publishDecision(provider, envelope, now = new Date()) {
  const binding = await bindEnvelope(envelope, now);
  const desired = desiredCheckState(binding);
  const [pull, mainSha, checks] = await Promise.all([
    provider.getPull(envelope.pullRequestNumber),
    provider.getMainSha(),
    provider.listChecks(envelope.headSha),
  ]);
  assertLiveIdentity(envelope, pull, mainSha);
  const trusted = trustedChecks(checks, envelope.headSha);
  if (trusted.length > 1) throw new Error("DUPLICATE_TRUSTED_CHECKS");
  const existing = trusted[0] || null;
  const priorMeta = await assertChain(provider, existing, envelope);

  if (existing && priorMeta.generation === envelope.decisionGeneration) {
    if (
      priorMeta.envelopeHash !== binding.envelopeHash ||
      priorMeta.idempotencyKey !== binding.idempotencyKey
    ) throw new Error("SAME_GENERATION_CONFLICT");
    if (finalStateMatches(existing, desired)) {
      return { state: "idempotent", check: existing, binding };
    }
    if (asRecord(existing).status === "completed") throw new Error("SAME_GENERATION_STATE_CONFLICT");
  }
  let current = existing;
  if (envelope.decision === "PASS") {
    const progress = inProgressState(desired, envelope.evaluatedAt);
    current = await writeAndRead({
      provider,
      kind: existing ? "update" : "create",
      checkRunId: existing ? existing.id : null,
      payload: progress,
      headSha: envelope.headSha,
    });
    if (
      asRecord(current).external_id !== desired.external_id ||
      asRecord(current).status !== "in_progress" ||
      asRecord(asRecord(current).app).id !== INTEGRATION_APP_ID
    ) throw new Error("CHECK_PROGRESS_READBACK_MISMATCH");
  }

  current = await writeAndRead({
    provider,
    kind: current ? "update" : "create",
    checkRunId: current ? current.id : null,
    payload: desired,
    headSha: envelope.headSha,
  });
  if (!finalStateMatches(current, desired)) throw new Error("CHECK_FINAL_READBACK_MISMATCH");
  return { state: existing ? "updated" : "created", check: current, binding };
}
async function expireCheck(provider, checkRunId, headSha, now = new Date()) {
  const check = await readExact(provider, checkRunId);
  const row = asRecord(check);
  if (row.name !== RULE_CONTEXT || row.head_sha !== headSha) throw new Error("CHECK_EXPIRY_IDENTITY_MISMATCH");
  const meta = parseCheckExternalId(row.external_id);
  if (!meta) throw new Error("TRUSTED_CHECK_METADATA_INVALID");
  if (Date.parse(meta.expiresAt) > now.getTime()) return { state: "fresh", check };
  if (row.status === "completed" && row.conclusion !== "success") return { state: "already_invalid", check };
  const payload = {
    name: RULE_CONTEXT,
    external_id: row.external_id,
    status: "completed",
    conclusion: "action_required",
    completed_at: now.toISOString(),
    output: {
      title: "Pandora coordinator HOLD",
      summary: `Decision expired at ${meta.expiresAt}. A fresh generation is required.`,
    },
  };
  const updated = await writeAndRead({ provider, kind: "update", checkRunId, payload, headSha });
  if (asRecord(updated).conclusion !== "action_required") throw new Error("CHECK_EXPIRY_READBACK_MISMATCH");
  return { state: "expired", check: updated };
}

async function revokeCheckForSnapshot(provider, checkRunId, headSha, promotionId, now = new Date()) {
  const check = await readExact(provider, checkRunId);
  const row = asRecord(check);
  if (row.name !== RULE_CONTEXT || row.head_sha !== headSha) throw new Error("CHECK_REVOCATION_IDENTITY_MISMATCH");
  if (!parseCheckExternalId(row.external_id)) throw new Error("TRUSTED_CHECK_METADATA_INVALID");
  if (row.status === "completed" && row.conclusion !== "success") return { state: "already_invalid", check };
  const payload = {
    name: RULE_CONTEXT, external_id: row.external_id, status: "completed", conclusion: "action_required",
    completed_at: now.toISOString(),
    output: {
      title: "Pandora coordinator HOLD",
      summary: `Authoritative Sheet snapshot promotion ${promotionId} revoked this decision before the new snapshot became effective.`,
    },
  };
  const updated = await writeAndRead({ provider, kind: "update", checkRunId, payload, headSha });
  const result = asRecord(updated);
  if (result.status !== "completed" || result.conclusion !== "action_required" ||
      asRecord(result.app).id !== INTEGRATION_APP_ID || result.head_sha !== headSha) {
    throw new Error("CHECK_REVOCATION_READBACK_MISMATCH");
  }
  return { state: "revoked", check: updated };
}

export { assertLiveIdentity, expireCheck, publishDecision, revokeCheckForSnapshot, trustedChecks };
