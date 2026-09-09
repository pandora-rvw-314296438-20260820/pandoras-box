const CANONICAL_REPOSITORY = "pandora-rvw-314296438-20260820/pandoras-box";
const WORKER_TOOL = "projectos.worker.verify";
const WORKER_RISK = "write";
const ALLOWED_JOB_CLASSES = new Set([
  "node_regression",
  "supabase_migration_replay",
]);
const PLAN_STATUSES = new Set([
  "pending_approval",
  "approved",
  "executing",
  "completed",
  "failed",
  "expired",
  "denied",
]);
const DISPATCH_PENDING_STATUSES = new Set([
  "queued",
  "claimed",
  "envelope_ready",
]);
const DISPATCH_REVIEW_PENDING_STATUSES = new Set([
  "result_reported",
  "finalizing",
]);

function isRecord(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isUuid(value) {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function cleanError(error) {
  const raw = error instanceof Error ? error.message : String(error || "unavailable");
  return raw
    .replace(/\bBearer\s+\S+/gi, "[REDACTED_SECRET]")
    .replace(/\b(?:gh[pousr]_|github_pat_|sk-|sb_secret_)[A-Za-z0-9_-]{12,}\b/gi, "[REDACTED_SECRET]")
    .slice(0, 240);
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function normalizeWorkerCommand(command) {
  if (!isRecord(command)) throw new Error("INVALID_WORKER_COMMAND");
  const exactSha = typeof command.exactSha === "string"
    ? command.exactSha.trim().toLowerCase()
    : "";
  const jobClass = typeof command.jobClass === "string"
    ? command.jobClass.trim()
    : "";
  const repository = typeof command.repository === "string"
    ? command.repository.trim()
    : CANONICAL_REPOSITORY;
  const maxRuntimeSeconds = command.maxRuntimeSeconds === undefined
    ? 1800
    : Number(command.maxRuntimeSeconds);

  if (repository !== CANONICAL_REPOSITORY) {
    throw new Error("NONCANONICAL_REPOSITORY");
  }
  if (!/^[0-9a-f]{40}$/.test(exactSha)) throw new Error("INVALID_EXACT_SHA");
  if (!ALLOWED_JOB_CLASSES.has(jobClass)) throw new Error("INVALID_JOB_CLASS");
  if (
    !Number.isInteger(maxRuntimeSeconds) || maxRuntimeSeconds < 30 ||
    maxRuntimeSeconds > 1800
  ) {
    throw new Error("INVALID_MAX_RUNTIME");
  }

  return Object.freeze({
    exactSha,
    jobClass,
    maxRuntimeSeconds,
    productionMutationAllowed: false,
    repository: CANONICAL_REPOSITORY,
    schemaVersion: 1,
  });
}

function canonicalWorkerPlanPayload(args) {
  return `{"tool":"${WORKER_TOOL}","args":{"exactSha":"${args.exactSha}","jobClass":"${args.jobClass}","maxRuntimeSeconds":${args.maxRuntimeSeconds},"productionMutationAllowed":false,"repository":"${args.repository}","schemaVersion":1}}`;
}

async function workerPlanPayloadHash(command) {
  const args = normalizeWorkerCommand(command);
  return sha256Hex(canonicalWorkerPlanPayload(args));
}

function sameArgs(actual, expected) {
  if (!isRecord(actual)) return false;
  const keys = Object.keys(actual).sort();
  const expectedKeys = Object.keys(expected).sort();
  return keys.length === expectedKeys.length &&
    keys.every((key, index) => key === expectedKeys[index]) &&
    keys.every((key) => actual[key] === expected[key]);
}

function documented(intakeId, plan) {
  return {
    reply: "Pandora prepared an exact-source verification plan. Owner approval is required before Worker-01 can receive it.",
    needsApproval: true,
    actionId: intakeId,
    approvalId: plan.planId,
    status: {
      whatChanged: "A governed verification plan was recorded.",
      whereWeAre: "Awaiting owner approval.",
      whatIsDone: "Repository, source SHA, job class, runtime limit, and payload hash are fixed.",
      whatIsHappeningNow: "Nothing is executing.",
      whatIsStoppingUs: "The plan has not been approved.",
      whatIWillDoNext: "Approve this exact plan to queue it once.",
    },
    proof: { stage: "documented", verified: true, ambiguous: false },
    advanced: { intakeId, planId: plan.planId, planStatus: plan.status },
  };
}

function blocked(intakeId, code, details = {}) {
  return {
    reply: "Pandora stopped before execution because the governed worker path could not be proven safe.",
    needsApproval: false,
    actionId: intakeId,
    approvalId: null,
    status: {
      whatChanged: "No worker action was started.",
      whereWeAre: "Blocked safely.",
      whatIsDone: "The owner request remains recorded.",
      whatIsHappeningNow: "No retry or provider action is running.",
      whatIsStoppingUs: code,
      whatIWillDoNext: "Reconcile the recorded plan and dispatch evidence before continuing.",
    },
    proof: {
      stage: "documented",
      verified: false,
      ambiguous: code === "AMBIGUOUS_DISPATCH",
    },
    advanced: { intakeId, blockerCode: code, ...details },
  };
}

function dispatchPending(intakeId, plan, dispatch) {
  return {
    reply: "The exact-source verification is queued or running on the governed worker path.",
    needsApproval: false,
    actionId: intakeId,
    approvalId: null,
    status: {
      whatChanged: "The approved plan is bound to one durable dispatch.",
      whereWeAre: "Verification is still in progress.",
      whatIsDone: "Approval, plan claim, and one-time queue binding are recorded.",
      whatIsHappeningNow: `Worker dispatch is ${dispatch.status}.`,
      whatIsStoppingUs: null,
      whatIWillDoNext: "Wait for signed completion evidence; do not create another dispatch.",
    },
    proof: { stage: "implemented", verified: false, ambiguous: false },
    advanced: {
      intakeId,
      planId: plan.planId,
      dispatchId: dispatch.dispatchId,
      dispatchStatus: dispatch.status,
    },
  };
}

function reviewPending(intakeId, plan, dispatch) {
  return {
    reply: "Worker-01 reported a signed exact-source result. It is attested and review-pending, not yet independently verified or tested.",
    needsApproval: false,
    actionId: intakeId,
    approvalId: null,
    status: {
      whatChanged: "A worker result attestation was recorded for the exact plan and dispatch.",
      whereWeAre: "Awaiting independent reviewer finalization.",
      whatIsDone: "The worker signature, exact source binding, and evidence hash are recorded.",
      whatIsHappeningNow: dispatch.status === "finalizing"
        ? "A separate reviewer finalization transaction is in progress."
        : "The result is queued for a separate reviewer.",
      whatIsStoppingUs: "Independent reviewer evidence has not finalized the plan.",
      whatIWillDoNext: "Route the attestation to a different reviewer and preserve the current dispatch without retrying it.",
    },
    proof: {
      stage: "implemented",
      verified: false,
      ambiguous: false,
      attested: true,
    },
    advanced: {
      intakeId,
      planId: plan.planId,
      dispatchId: dispatch.dispatchId,
      dispatchStatus: dispatch.status,
      workerEvidenceSha256: dispatch.evidenceSha256 || null,
      reviewPending: true,
    },
  };
}

function verifiedResult(intakeId, plan, dispatch, expectedArgs) {
  const result = isRecord(dispatch.resultSummary) ? dispatch.resultSummary : {};
  const evidenceSha256 = typeof dispatch.evidenceSha256 === "string"
    ? dispatch.evidenceSha256
    : "";
  const exactBinding = result.repository === expectedArgs.repository &&
    result.exactSha === expectedArgs.exactSha &&
    result.jobClass === expectedArgs.jobClass &&
    result.exitCode === 0 &&
    result.isolation === "hyperv_container" &&
    result.networkPolicy === "none" &&
    /^[0-9a-f]{64}$/.test(evidenceSha256) &&
    isUuid(dispatch.verificationEvidenceId) &&
    dispatch.verifiedOutcome === "completed" &&
    Number.isFinite(Date.parse(dispatch.verifiedAt));
  if (!exactBinding) {
    return blocked(intakeId, "COMPLETION_EVIDENCE_MISMATCH", {
      planId: plan.planId,
      dispatchId: dispatch.dispatchId,
    });
  }
  return {
    reply: `Worker-01 verified ${expectedArgs.exactSha} with ${expectedArgs.jobClass}; the signed evidence is bound to this exact plan and dispatch.`,
    needsApproval: false,
    actionId: intakeId,
    approvalId: null,
    status: {
      whatChanged: "Exact-source verification completed.",
      whereWeAre: "Tested with bound evidence.",
      whatIsDone: "The isolated, network-disabled worker job exited successfully.",
      whatIsHappeningNow: "No worker action is running.",
      whatIsStoppingUs: null,
      whatIWillDoNext: "Use this evidence only for the same source SHA.",
    },
    proof: {
      stage: "tested",
      verified: true,
      ambiguous: false,
      proofHash: evidenceSha256,
    },
    advanced: {
      intakeId,
      planId: plan.planId,
      dispatchId: dispatch.dispatchId,
      verificationEvidenceId: dispatch.verificationEvidenceId,
      repository: expectedArgs.repository,
      exactSha: expectedArgs.exactSha,
      jobClass: expectedArgs.jobClass,
    },
  };
}

async function reconcileOwnerWorkerCommand(options) {
  const context = isRecord(options?.context) ? options.context : {};
  const intake = isRecord(options?.intake) ? options.intake : {};
  const adapter = options?.adapter;
  if (
    !isUuid(context.organizationId) || !isUuid(context.userId) ||
    context.isAnonymous === true || !["owner", "admin"].includes(context.role)
  ) {
    throw new Error("OWNER_OR_ADMIN_REQUIRED");
  }
  if (!isUuid(intake.id)) throw new Error("INVALID_INTAKE_ID");

  const args = normalizeWorkerCommand(options.command);
  const payloadHash = await sha256Hex(canonicalWorkerPlanPayload(args));
  if (
    !adapter || typeof adapter.listPlans !== "function" ||
    typeof adapter.createPlan !== "function" ||
    typeof adapter.getDispatch !== "function" ||
    typeof adapter.ensurePlanContext !== "function"
  ) {
    return blocked(intake.id, "WORKER_CONTROL_ADAPTER_UNAVAILABLE");
  }

  let plans;
  try {
    plans = await adapter.listPlans({
      organizationId: context.organizationId,
      limit: 100,
    });
  } catch (error) {
    return blocked(intake.id, "PLAN_READ_UNAVAILABLE", {
      error: cleanError(error),
    });
  }
  if (!Array.isArray(plans)) return blocked(intake.id, "INVALID_PLAN_READBACK");
  const intakePlans = plans.filter((plan) => plan?.intakeId === intake.id);
  if (intakePlans.length > 1) {
    return blocked(intake.id, "MULTIPLE_PLANS_FOR_INTAKE", {
      planIds: intakePlans.map((plan) => plan?.planId).filter(Boolean),
    });
  }

  let plan = intakePlans[0] || null;
  if (!plan) {
    try {
      plan = await adapter.createPlan({
        organizationId: context.organizationId,
        requestId: intake.id,
        intakeId: intake.id,
        tool: WORKER_TOOL,
        risk: WORKER_RISK,
        args,
        payloadHash,
        expiresAt: new Date(
          (options.now instanceof Date ? options.now : new Date()).getTime() +
            30 * 60 * 1000,
        ).toISOString(),
      });
    } catch (error) {
      return blocked(intake.id, "PLAN_CREATE_UNAVAILABLE", {
        error: cleanError(error),
      });
    }
  }

  if (
    !isRecord(plan) || !isUuid(plan.planId) || !PLAN_STATUSES.has(plan.status) ||
    plan.intakeId !== intake.id || plan.tool !== WORKER_TOOL ||
    plan.risk !== WORKER_RISK || plan.payloadHash !== payloadHash ||
    !sameArgs(plan.args, args)
  ) {
    return blocked(intake.id, "PLAN_IDENTITY_MISMATCH", {
      planId: isRecord(plan) ? plan.planId : null,
    });
  }

  if (plan.memoryContextRecorded !== true) {
    let contextRecorded = false;
    try {
      contextRecorded = await adapter.ensurePlanContext({
        organizationId: context.organizationId,
        requestId: intake.id,
        intakeId: intake.id,
        planId: plan.planId,
        tool: WORKER_TOOL,
        args,
      });
    } catch (error) {
      return blocked(intake.id, "MEMORY_CONTEXT_ATTACH_UNAVAILABLE", {
        planId: plan.planId,
        error: cleanError(error),
      });
    }
    if (contextRecorded !== true) {
      return blocked(intake.id, "MEMORY_CONTEXT_NOT_ATTACHED", {
        planId: plan.planId,
      });
    }
  }

  if (plan.status === "pending_approval") return documented(intake.id, plan);
  if (plan.status === "approved") {
    return blocked(intake.id, "APPROVED_PLAN_NOT_ATOMICALLY_DISPATCHED", {
      planId: plan.planId,
    });
  }
  if (["failed", "expired", "denied"].includes(plan.status)) {
    return blocked(intake.id, `PLAN_${plan.status.toUpperCase()}`, {
      planId: plan.planId,
    });
  }

  let dispatch;
  try {
    dispatch = await adapter.getDispatch({
      organizationId: context.organizationId,
      planId: plan.planId,
    });
  } catch (error) {
    return blocked(intake.id, "DISPATCH_READ_UNAVAILABLE", {
      planId: plan.planId,
      error: cleanError(error),
    });
  }
  if (!isRecord(dispatch) || dispatch.planId !== plan.planId) {
    return blocked(intake.id, "PLAN_DISPATCH_BINDING_MISSING", {
      planId: plan.planId,
    });
  }
  if (dispatch.status === "ambiguous") {
    return blocked(intake.id, "AMBIGUOUS_DISPATCH", {
      planId: plan.planId,
      dispatchId: dispatch.dispatchId,
    });
  }
  if (dispatch.status === "failed") {
    return blocked(intake.id, "DISPATCH_FAILED", {
      planId: plan.planId,
      dispatchId: dispatch.dispatchId,
    });
  }
  if (DISPATCH_PENDING_STATUSES.has(dispatch.status)) {
    if (plan.status !== "executing") {
      return blocked(intake.id, "PLAN_DISPATCH_STATE_MISMATCH", {
        planId: plan.planId,
        dispatchId: dispatch.dispatchId,
      });
    }
    return dispatchPending(intake.id, plan, dispatch);
  }
  if (DISPATCH_REVIEW_PENDING_STATUSES.has(dispatch.status)) {
    if (plan.status !== "executing") {
      return blocked(intake.id, "PLAN_DISPATCH_STATE_MISMATCH", {
        planId: plan.planId,
        dispatchId: dispatch.dispatchId,
      });
    }
    return reviewPending(intake.id, plan, dispatch);
  }
  if (dispatch.status === "completed" && plan.status === "completed") {
    return verifiedResult(intake.id, plan, dispatch, args);
  }
  return blocked(intake.id, "UNKNOWN_PLAN_DISPATCH_STATE", {
    planId: plan.planId,
    dispatchId: dispatch.dispatchId,
  });
}

export {
  ALLOWED_JOB_CLASSES,
  CANONICAL_REPOSITORY,
  WORKER_RISK,
  WORKER_TOOL,
  canonicalWorkerPlanPayload,
  normalizeWorkerCommand,
  reconcileOwnerWorkerCommand,
  workerPlanPayloadHash,
};
