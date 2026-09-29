import { createHash, createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { resolveVercelWorkloadToken } from "../src/runtime/vercel-workload-identity.js";
import releasePolicy from "../src/runtime/operations-source-release-policy.cjs";
const { canContinueSourceBuilding } = releasePolicy;

export const config = { api: { bodyParser: false }, maxDuration: 300 };

const CONTROL_URL =
  "https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/mcpmaster-supabase-control";
const INFERENCE_URL =
  "https://mcpmaster.vercel.app/api/operations-inference?operation=infer";
const REASONING_TASK_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$/;
const REASONING_UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REPOSITORY = "pandora-rvw-314296438-20260820/pandoras-box";
const MEMORY_URL = "https://ivmvufhcsezyhczzondn.supabase.co/functions/v1/pandora-memory-bridge";
const MEMORY_PROJECT_ID = "7c686cbd-d968-49d5-86cc-918f5e777bd2";
const BUILDER_ID = "pandora-native-builder-v1";
const GENERIC_SOURCE_FANOUT = 4;
const RELEASE_ID = "pandora-native-release-v1";
const CANARY_TASK = "OPS-CLOUD-CONNECTORS-RELEASE-V1";
const MEMORY_ADOPTION_TASK = "OPS-MEMORY-CALLER-ADOPTION-V1";
const WHOLE_SHEET_TASK = "OPS-WHOLE-SHEET-ACCEPTANCE-V3";
const CANARY_PR = 741;
const MEMORY_PROOF_URL =
  "https://mcpmaster-mk0h1rinp-mbanatao.vercel.app/operations-memory-canary.json";
const MEMORY_APPROVAL_REF =
  "https://github.com/pandora-rvw-314296438-20260820/pandoras-box/issues/714#issuecomment-5844397041";
const MEMORY_ROLLBACK_REF =
  "vercel:deployment:dpl_GmGhiKuCBkQir6u1WQMFtLEwtjpo:source:ba9b12c1b2d1be70bf104e856c352c57e20ccef9";

type Json = Record<string, any>;

function send(response: any, status: number, body: Json) {
  response.status(status);
  response.setHeader("content-type", "application/json; charset=utf-8");
  response.setHeader("cache-control", "no-store");
  response.setHeader("x-content-type-options", "nosniff");
  return response.end(JSON.stringify(body));
}

async function readBoundedJson(response: Response, maxBytes = 256_000) {
  const declared = Number(response.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > maxBytes) throw new Error("RESPONSE_TOO_LARGE");
  const text = await response.text();
  if (Buffer.byteLength(text) > maxBytes) throw new Error("RESPONSE_TOO_LARGE");
  return text ? JSON.parse(text) : {};
}

async function control(oidc: string, input: Json, timeoutMs = 12_000) {
  const response = await fetch(CONTROL_URL, {
    method: "POST",
    headers: {
      authorization: `Bearer ${oidc}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(input),
    redirect: "error",
    signal: AbortSignal.timeout(timeoutMs),
  });
  const payload = await readBoundedJson(response);
  if (!response.ok || payload?.ok !== true) {
    throw Object.assign(new Error("OPERATIONS_CONTROL_UNAVAILABLE"), {
      status: response.status,
      code: payload?.error || "OPERATIONS_CONTROL_UNAVAILABLE",
    });
  }
  return payload.operations;
}

async function githubJson(path: string) {
  const response = await fetch(`https://api.github.com${path}`, {
    headers: {
      accept: "application/vnd.github+json",
      "x-github-api-version": "2026-03-10",
      "user-agent": "Pandora-Operations-Native-Worker/1.0",
    },
    redirect: "error",
    signal: AbortSignal.timeout(12_000),
  });
  const payload = await readBoundedJson(response);
  if (!response.ok) throw new Error("GITHUB_READBACK_UNAVAILABLE");
  return payload;
}

async function memoryContextCanary(oidc: string) {
  const response = await fetch(MEMORY_URL, {
    method: "POST",
    headers: {
      "x-pandora-vercel-oidc": oidc,
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify({
      action: "operations",
      operation: "context",
      requestId: randomUUID(),
      projectId: MEMORY_PROJECT_ID,
      namespace: "real_life",
      payload: {
        intent: "coding_building",
        actionMode: "read_only",
        consequential: false,
        terms: ["operations"],
        requiredCapabilities: [],
        maxBytes: 4096,
      },
    }),
    redirect: "error",
    signal: AbortSignal.timeout(12_000),
  });
  const payload = await readBoundedJson(response, 64_000);
  if (
    !response.ok || payload?.ok !== true ||
    payload?.projectId !== MEMORY_PROJECT_ID ||
    payload?.namespace !== "real_life" ||
    payload?.memoryProjectRef !== "ivmvufhcsezyhczzondn" ||
    payload?.data?.kind !== "task_context" ||
    payload?.data?.authorizationGranted !== false
  ) throw new Error("OPS_MEMORY_CONTEXT_CANARY_FAILED");
  return {
    verified: true,
    kind: "task_context",
    authorizationGranted: false,
    projectId: MEMORY_PROJECT_ID,
    namespace: "real_life",
  };
}


async function drainGrowthLearning(oidc: string) {
  const claimed = await control(oidc, { action: "growth_learning_claim" });
  if (claimed?.state !== "claimed") return { state: "idle" };
  const outboxId = String(claimed.outboxId || "");
  const claimToken = String(claimed.claimToken || "");
  if (!REASONING_UUID_PATTERN.test(outboxId) || !REASONING_UUID_PATTERN.test(claimToken)
      || !claimed.payload || typeof claimed.payload !== "object" || Array.isArray(claimed.payload)) {
    throw new Error("GROWTH_LEARNING_CLAIM_INVALID");
  }

  let status = 503;
  let content = "{}";
  let error: string | null = null;
  try {
    const memoryResponse = await fetch(MEMORY_URL, {
      method: "POST",
      headers: {
        "x-pandora-vercel-oidc": oidc,
        "content-type": "application/json",
        accept: "application/json",
      },
      body: JSON.stringify({ action: "growth_learning", payload: claimed.payload }),
      redirect: "error",
      signal: AbortSignal.timeout(20_000),
    });
    status = memoryResponse.status;
    const body = await readBoundedJson(memoryResponse, 64_000);
    const receipt = body?.data && typeof body.data === "object" && !Array.isArray(body.data)
      ? body.data
      : body;
    content = JSON.stringify(receipt || {});
    if (!memoryResponse.ok || body?.ok !== true) {
      error = String(body?.error || "GROWTH_LEARNING_MEMORY_REJECTED").slice(0, 1000);
    }
  } catch (cause: any) {
    status = 503;
    error = String(cause?.message || "GROWTH_LEARNING_MEMORY_UNAVAILABLE").slice(0, 1000);
  }

  const acknowledged = await control(oidc, {
    action: "growth_learning_ack",
    outboxId,
    claimToken,
    httpStatus: status,
    content,
    error,
  });
  return {
    state: acknowledged?.state || "unknown",
    delivered: acknowledged?.delivered === true,
    outboxId,
    attempt: acknowledged?.attempt ?? claimed?.attempt ?? null,
  };
}

async function publicJson(url: string) {
  const response = await fetch(url, {
    headers: { accept: "application/json" },
    redirect: "error",
    signal: AbortSignal.timeout(12_000),
  });
  const payload = await readBoundedJson(response, 64_000);
  if (!response.ok) throw new Error("PROVIDER_READBACK_UNAVAILABLE");
  return payload;
}

function taskEvidenceBase(task: any, ref: string) {
  if (
    !task || !/^[0-9a-f]{40}$/.test(String(task.headSha || "")) ||
    !/^[0-9a-f]{64}$/.test(String(task.specDigest || "")) ||
    !Number.isSafeInteger(Number(task.generation)) || Number(task.generation) < 1 ||
    !Array.isArray(task?.spec?.acceptance) || task.spec.acceptance.length < 1
  ) throw new Error("OPS_NATIVE_TASK_EVIDENCE_INVALID");
  return {
    taskId: task.spec.id,
    generation: String(task.generation),
    headSha: task.headSha,
    taskSpecDigest: task.specDigest,
    criteria: task.spec.acceptance,
    ref,
  };
}

async function recordAndAccept(
  oidc: string,
  task: any,
  evidence: Json,
  productionRefs: Json = {},
) {
  await control(oidc, { action: "operations_heartbeat", workerRole: "release" });
  const recorded = await control(oidc, {
    action: "operations_verification_record",
    taskId: task.spec.id,
    generation: task.generation,
    status: "PASS",
    evidence,
  });
  const verificationRunId = String(recorded?.verificationRunId || "");
  if (!/^[0-9a-f-]{36}$/i.test(verificationRunId)) {
    throw new Error("OPS_NATIVE_VERIFICATION_RECORD_INVALID");
  }
  const receipt = { ...evidence, verificationRunId, ...productionRefs };
  const verified = await control(oidc, {
    action: "operations_verification_accept",
    taskId: task.spec.id,
    generation: task.generation,
    verificationRunId,
    receipt,
  });
  return { recorded, verified };
}

async function verifyMemoryAdoption(oidc: string, task: any, currentMemory: Json) {
  const proof = await publicJson(MEMORY_PROOF_URL);
  if (
    proof?.schemaVersion !== "pandora-operations-memory-production-canary-v1" ||
    proof?.identity !== "vercel-workload-oidc" ||
    proof?.sourceCommit !== task?.headSha ||
    proof?.context?.state !== "available" ||
    proof?.context?.authorizationGranted !== false ||
    proof?.performance?.authorizationGranted !== false ||
    proof?.performance?.providerApprovalGranted !== false ||
    proof?.outcome?.state !== "pending_review" ||
    proof?.outcome?.deliveryVerified !== true ||
    proof?.outcome?.canonicalMemoryWritten !== false ||
    proof?.outcome?.currentReviewStatus !== "pending_review" ||
    proof?.outcome?.readbackMatchesSubmission !== true ||
    proof?.outcome?.modelRevisionKnown !== false ||
    proof?.outcome?.usageKnown !== false ||
    proof?.outcome?.estimatedCostKnown !== false ||
    proof?.outcome?.billedCostKnown !== false ||
    currentMemory?.verified !== true ||
    currentMemory?.authorizationGranted !== false
  ) throw new Error("OPS_MEMORY_ADOPTION_PROVIDER_READBACK_FAILED");

  const evidence = {
    ...taskEvidenceBase(task, `ops-native-release:memory:${task.headSha}`),
    providerReadback: {
      immutableDeployment: MEMORY_PROOF_URL,
      currentWorkloadOidcContextVerified: true,
      sourceRunId: proof.outcome.sourceRunId,
      contextState: proof.context.state,
      contextAuthorizationGranted: false,
      performanceState: proof.performance.state,
      performanceRecordCount: proof.performance.recordCount,
      providerApprovalGranted: false,
      outcomeState: proof.outcome.state,
      deliveryVerified: true,
      canonicalMemoryWritten: false,
      reviewStatus: proof.outcome.currentReviewStatus,
      receiptRef: proof.outcome.receiptRef,
      modelRevisionKnown: false,
      usageKnown: false,
      estimatedCostKnown: false,
      billedCostKnown: false,
    },
  };
  return recordAndAccept(oidc, task, evidence, {
    approvalRef: MEMORY_APPROVAL_REF,
    rollbackRef: MEMORY_ROLLBACK_REF,
  });
}

async function verifyWholeSheetAcceptance(oidc: string, task: any) {
  const readback = await control(oidc, { action: "operations_final_acceptance_readback" });
  const tasks = readback?.tasks && typeof readback.tasks === "object" ? readback.tasks : {};
  const required = [
    "OPS-SESSION-SHEETS-BRIDGE-V2",
    "OPS-WAKE-RECOVERY-V3",
    "OPS-INTELLIGENCE-ROUTER-SERVICE-V1",
    MEMORY_ADOPTION_TASK,
    "OPS-THEATRE-LIVE-EVENTS-V1",
    "OPS-SERIALIZATION-CANARY-A-V1",
    "OPS-SERIALIZATION-CANARY-B-V1",
  ];
  if (required.some((id) => tasks?.[id]?.status !== "complete")) {
    throw new Error("OPS_WHOLE_SHEET_DEPENDENCY_READBACK_FAILED");
  }

  const target = tasks?.[WHOLE_SHEET_TASK];
  const sheets = tasks?.["OPS-SESSION-SHEETS-BRIDGE-V2"]?.verification?.providerReadback;
  const wake = tasks?.["OPS-WAKE-RECOVERY-V3"]?.verification?.providerReadback;
  const router = tasks?.["OPS-INTELLIGENCE-ROUTER-SERVICE-V1"]?.verification?.providerReadback;
  const memory = tasks?.[MEMORY_ADOPTION_TASK]?.verification?.providerReadback;
  const theatre = tasks?.["OPS-THEATRE-LIVE-EVENTS-V1"]?.verification?.providerReadback;
  const serialization = tasks?.["OPS-SERIALIZATION-CANARY-B-V1"]?.verification?.providerReadback;

  if (
    target?.status !== task.status ||
    target?.headSha !== task.headSha ||
    target?.generation !== task.generation ||
    !String(target?.builderWorkerKey || "").startsWith("chatgpt-pro-session") ||
    target?.builderWorkerKey === RELEASE_ID ||
    !String(target?.builderPrincipalKey || "").startsWith("chatgpt:interactive:") ||
    sheets?.validationPreserved !== true ||
    sheets?.ownerColumnsPreserved !== "A:N" ||
    sheets?.machineColumnsChanged !== "O:U" ||
    wake?.recoveredProviderReadbackVerified !== true ||
    router?.routerEdgeFunction !== "ACTIVE:v1" ||
    memory?.deliveryVerified !== true ||
    memory?.canonicalMemoryWritten !== false ||
    memory?.reviewStatus !== "pending_review" ||
    theatre?.syntheticProgress !== false ||
    theatre?.eventAuthority !== "immutable_operations_events" ||
    serialization?.initialClaim !== "resource_conflict"
  ) throw new Error("OPS_WHOLE_SHEET_PROVIDER_READBACK_FAILED");

  const pullRequest = Number(target?.handoff?.pullRequest);
  if (!Number.isSafeInteger(pullRequest) || pullRequest < 1) {
    throw new Error("OPS_WHOLE_SHEET_PR_REQUIRED");
  }
  const pr = await githubJson(`/repos/${REPOSITORY}/pulls/${pullRequest}`);
  if (
    pr?.number !== pullRequest ||
    typeof pr?.merged_at !== "string" ||
    !/^[0-9a-f]{40}$/.test(String(pr?.head?.sha || ""))
  ) throw new Error("OPS_WHOLE_SHEET_MERGE_READBACK_FAILED");

  let verifiedMergeSha = String(pr?.merge_commit_sha || "");
  if (!verifiedMergeSha) {
    const mergeCommit = await githubJson(`/repos/${REPOSITORY}/commits/${task.headSha}`);
    const parents = Array.isArray(mergeCommit?.parents) ? mergeCommit.parents : [];
    if (
      mergeCommit?.sha !== task.headSha ||
      !parents.some((parent: any) => parent?.sha === pr.head.sha)
    ) throw new Error("OPS_WHOLE_SHEET_MERGE_READBACK_FAILED");
    verifiedMergeSha = task.headSha;
  }
  if (verifiedMergeSha !== task.headSha) {
    throw new Error("OPS_WHOLE_SHEET_MERGE_READBACK_FAILED");
  }

  const checks = await githubJson(
    `/repos/${REPOSITORY}/commits/${pr.head.sha}/check-runs?per_page=100`,
  );
  const runs = Array.isArray(checks?.check_runs) ? checks.check_runs : [];
  const pending = runs.filter((run: any) => run?.status !== "completed");
  const failed = runs.filter(
    (run: any) => run?.status === "completed" &&
      !["success", "neutral", "skipped"].includes(String(run?.conclusion || "")),
  );
  if (
    pending.length > 0 || failed.length > 0 ||
    !runs.some((run: any) =>
      run?.name === "Pandora coordinator / integration" && run?.conclusion === "success"
    )
  ) throw new Error("OPS_WHOLE_SHEET_CHECK_READBACK_FAILED");

  const deploymentCommit = String(process.env.VERCEL_GIT_COMMIT_SHA || "");
  if (deploymentCommit !== task.headSha) {
    throw new Error("OPS_WHOLE_SHEET_VERCEL_SOURCE_MISMATCH");
  }

  const taskEvents = Array.isArray(readback?.events)
    ? readback.events.filter((event: any) => event?.taskId === WHOLE_SHEET_TASK)
    : [];
  for (const type of ["task_claimed", "worker_started", "implementation_handed_off"]) {
    if (!taskEvents.some((event: any) => event?.eventType === type)) {
      throw new Error("OPS_WHOLE_SHEET_EVENT_READBACK_FAILED");
    }
  }

  const evidence = {
    ...taskEvidenceBase(task, `ops-native-release:whole-sheet:${task.headSha}`),
    providerReadback: {
      pullRequest,
      pullRequestHead: pr.head.sha,
      mergeSha: verifiedMergeSha,
      coordinator: "success",
      vercelSourceCommit: deploymentCommit,
      vercelDeploymentRef: process.env.VERCEL_URL ? `vercel:${process.env.VERCEL_URL}` : null,
      sessionWorker: target.builderWorkerKey,
      sessionPrincipal: target.builderPrincipalKey,
      sheets: {
        spreadsheetId: sheets.spreadsheetId,
        validationPreserved: true,
        ownerColumnsPreserved: "A:N",
        machineColumnsChanged: "O:U",
      },
      memory: {
        state: memory.outcomeState,
        reviewStatus: memory.reviewStatus,
        deliveryVerified: true,
        canonicalMemoryWritten: false,
        receiptRef: memory.receiptRef,
      },
      serialization: {
        initialClaim: serialization.initialClaim,
        resource: serialization.resource,
      },
      theatre: {
        eventAuthority: theatre.eventAuthority,
        syntheticProgress: false,
      },
      router: {
        edgeFunction: router.routerEdgeFunction,
        providerProbe: router.providerProbe,
      },
      wake: {
        recoveredProviderReadbackVerified: true,
      },
      immutableTaskEventCount: taskEvents.length,
    },
  };
  return recordAndAccept(oidc, task, evidence);
}

async function verifySupportedHandedOffTask(
  oidc: string,
  snapshot: Json,
  currentMemory: Json,
) {
  const tasks = Array.isArray(snapshot?.tasks) ? snapshot.tasks : [];
  const memoryTask = tasks.find(
    (entry: any) =>
      entry?.spec?.id === MEMORY_ADOPTION_TASK &&
      ["handed_off", "verifying"].includes(String(entry?.status || "")),
  );
  if (memoryTask) {
    const result = await verifyMemoryAdoption(oidc, memoryTask, currentMemory);
    return { taskId: MEMORY_ADOPTION_TASK, ...result };
  }
  const wholeSheetTask = tasks.find(
    (entry: any) =>
      entry?.spec?.id === WHOLE_SHEET_TASK &&
      ["handed_off", "verifying"].includes(String(entry?.status || "")),
  );
  if (wholeSheetTask) {
    const result = await verifyWholeSheetAcceptance(oidc, wholeSheetTask);
    return { taskId: WHOLE_SHEET_TASK, ...result };
  }
  return null;
}

async function verifyMergedFacebookSource(oidc: string, snapshot: Json) {
  const task = (Array.isArray(snapshot?.tasks) ? snapshot.tasks : []).find(
    (entry: any) => entry?.spec?.id === "FB-025" &&
      ["handed_off", "verifying"].includes(String(entry?.status || "")),
  );
  if (!task) return null;

  await control(oidc, { action: "operations_heartbeat", workerRole: "release" });
  // The database selects the task and immutable receipt; no caller verdict or proof.
  const result = await control(
    oidc, { action: "operations_merged_release_source_step" }, 60_000,
  );
  if (result?.taskId !== "FB-025" ||
      !["idle", "held", "complete"].includes(String(result?.state || ""))) {
    throw new Error("OPS_MERGED_SOURCE_STEP_INVALID");
  }
  if (result.state === "complete" &&
      (result?.verification?.complete !== true ||
       result?.headSha !== "3e38b571ae963cc663e622fc1a75d5578b6fb7a2" ||
       result?.generation !== 5 ||
       !REASONING_UUID_PATTERN.test(String(result?.reconciliationReceiptId || "")))) {
    throw new Error("OPS_MERGED_SOURCE_COMPLETION_UNCONFIRMED");
  }
  return result;
}

async function connectorCanaryEvidence() {
  const pr = await githubJson(`/repos/${REPOSITORY}/pulls/${CANARY_PR}`);
  if (
    pr?.number !== CANARY_PR ||
    pr?.base?.ref !== "main" ||
    typeof pr?.merged_at !== "string" ||
    !/^[0-9a-f]{40}$/.test(String(pr?.merge_commit_sha || "")) ||
    !/^[0-9a-f]{40}$/.test(String(pr?.head?.sha || ""))
  ) throw new Error("PR741_MERGE_READBACK_FAILED");

  const checks = await githubJson(
    `/repos/${REPOSITORY}/commits/${pr.head.sha}/check-runs?per_page=100`,
  );
  const runs = Array.isArray(checks?.check_runs) ? checks.check_runs : [];
  const failed = runs.filter(
    (run: any) =>
      run?.status === "completed" &&
      !["success", "neutral", "skipped"].includes(String(run?.conclusion || "")),
  );
  const successful = runs
    .filter((run: any) => run?.status === "completed" && run?.conclusion === "success")
    .map((run: any) => String(run?.name || "").trim())
    .filter(Boolean);
  if (failed.length > 0 || successful.length < 1) {
    throw new Error("PR741_CHECK_READBACK_FAILED");
  }

  return {
    mergeSha: pr.merge_commit_sha as string,
    headSha: pr.head.sha as string,
    tests: successful.slice(0, 24).map((name: string) => `GitHub check PASS: ${name}`),
    prUrl: pr.html_url as string,
  };
}

function cronAuthorized(request: any) {
  const secret = String(process.env.CRON_SECRET || "");
  const authorization = String(request.headers.authorization || "");
  if (secret.length < 32 || secret.length > 512) return false;
  const expected = `Bearer ${secret}`;
  if (authorization.length !== expected.length) return false;
  return timingSafeEqual(Buffer.from(authorization), Buffer.from(expected));
}

function signedWake(request: any) {
  const secret = String(process.env.PANDORA_OPS_WAKE_HMAC_SECRET || "");
  const timestamp = String(request.headers["x-pandora-wake-timestamp"] || "");
  const nonce = String(request.headers["x-pandora-wake-nonce"] || "");
  const signature = String(request.headers["x-pandora-wake-signature"] || "").toLowerCase();
  if (secret.length < 32 || secret.length > 512) return null;
  if (!/^\d{10}$/.test(timestamp) || !/^[0-9a-f-]{36}$/i.test(nonce) || !/^[0-9a-f]{64}$/.test(signature)) return null;
  const issuedAt = Number(timestamp);
  if (!Number.isSafeInteger(issuedAt) || Math.abs(Math.floor(Date.now() / 1000) - issuedAt) > 90) return null;
  const message = `${timestamp}\n${nonce}\nPOST\n/api/operations-native-worker\n{}`;
  const expected = createHmac("sha256", secret).update(message).digest("hex");
  if (expected.length !== signature.length || !timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return null;
  return { nonce, issuedAt };
}

function receiptRef(dispatchId: string, taskId: string, generation: number) {
  const digest = createHash("sha256")
    .update(`${dispatchId}:${taskId}:${generation}:mcpmaster:production`)
    .digest("hex");
  return `ops-native-ack:${digest}`;
}

function reasoningInferenceToken() {
  const token = String(process.env.PANDORA_REASONING_RDP_INFERENCE_TOKEN || "");
  return /^opw_[A-Za-z0-9._~-]{32,256}$/.test(token) ? token : "";
}

function reasoningAckRef(dispatchId: string, taskId: string, generation: number) {
  return "reasoning-rdp-ack:" + createHash("sha256")
    .update(`${dispatchId}:${taskId}:${generation}:reasoning-rdp-native-v1`)
    .digest("hex");
}

async function inferReasoning(token: string, payload: Json) {
  const response = await fetch(INFERENCE_URL, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
    redirect: "error",
    signal: AbortSignal.timeout(55_000),
  });
  const body = await readBoundedJson(response, 128_000);
  if (!response.ok) {
    throw Object.assign(new Error(String(body?.error || "INFERENCE_REQUEST_FAILED")), {
      status: response.status,
    });
  }
  return body;
}

async function advanceReasoningRdp(oidc: string, status: Json) {
  const taskId = String(status?.parentTaskId || "");
  const generation = Number(status?.parentGeneration);
  if (!REASONING_TASK_PATTERN.test(taskId) || !Number.isSafeInteger(generation) || generation < 1) {
    return { state: "idle" };
  }

  if (status.state === "child_handed_off") {
    await control(oidc, { action: "operations_rdp_artemis_register" });
    const verification = await control(oidc, {
      action: "operations_reasoning_rdp_verify_child",
      taskId,
      generation,
    });
    return { state: "child_complete", taskId, verification };
  }

  if (status.state === "child_complete") {
    return control(oidc, {
      action: "operations_reasoning_rdp_parent_handoff",
      taskId,
      generation,
    });
  }

  if (status.state === "parent_handed_off") {
    await control(oidc, { action: "operations_rdp_artemis_register" });
    const verification = await control(oidc, {
      action: "operations_reasoning_rdp_verify_parent",
      taskId,
      generation,
    });
    const learning = await control(oidc, {
      action: "operations_reasoning_rdp_queue_memory",
      taskId,
      generation,
    });
    return { state: "complete", taskId, verification, learning };
  }

  if (status.state === "complete") {
    const learning = await control(oidc, {
      action: "operations_reasoning_rdp_queue_memory",
      taskId,
      generation,
    });
    return { state: "complete", taskId, learning };
  }

  if (status.state === "reasoning") {
    const leaseId = String(status?.parentLeaseId || "");
    if (REASONING_UUID_PATTERN.test(leaseId)) {
      await control(oidc, {
        action: "operations" + "_reconcile",
        leaseId,
        generation,
        reason: "REASONING_OUTPUT_UNRECOVERABLE",
      });
    }
    return { state: "reconciliation_required", taskId, reason: "reasoning_output_not_durable" };
  }

  return status;
}

async function runReasoningRdpStep(oidc: string) {
  await control(oidc, { action: "operations_reasoning_rdp_register" });
  await control(oidc, { action: "operations_reasoning_rdp_heartbeat" });

  let status = await control(oidc, { action: "operations_reasoning_rdp_status" });
  if (status?.state && status.state !== "idle") {
    const advanced = await advanceReasoningRdp(oidc, status);
    if (advanced?.state === "child_complete" || advanced?.state === "parent_handed_off") {
      status = await control(oidc, { action: "operations_reasoning_rdp_status" });
      return advanceReasoningRdp(oidc, status);
    }
    return advanced;
  }

  const candidate = await control(oidc, { action: "operations_reasoning_rdp_candidate" });
  if (candidate?.state !== "ready") return candidate || { state: "idle" };

  const token = reasoningInferenceToken();
  if (!token) {
    return {
      state: "held",
      taskId: candidate?.taskId ?? null,
      reason: "inference_token_unavailable",
    };
  }

  const taskId = String(candidate.taskId || "");
  const taskRevision = Number(candidate.taskRevision);
  const controlRevision = Number(candidate.controlRevision);
  if (!REASONING_TASK_PATTERN.test(taskId) ||
      !Number.isSafeInteger(taskRevision) ||
      !Number.isSafeInteger(controlRevision)) {
    throw new Error("OPS_REASONING_RDP_CANDIDATE_INVALID");
  }

  const claim = await control(oidc, {
    action: "operations_reasoning_rdp_claim",
    taskId,
    taskRevision,
    controlRevision,
  });
  if (claim?.claimed !== true) {
    return { state: "not_claimed", taskId, reason: claim?.reason || "claim_rejected" };
  }

  const leaseId = String(claim.leaseId || "");
  const generation = Number(claim.generation);
  let dispatchId = "";
  try {
    const intent = await control(oidc, {
      action: "operations_dispatch_prepare",
      leaseId,
      generation,
    });
    dispatchId = String(intent?.dispatchId || "");
    if (!REASONING_UUID_PATTERN.test(dispatchId)) throw new Error("OPS_REASONING_RDP_DISPATCH_INVALID");
    if (intent?.acknowledged !== true) {
      if (intent?.canSend !== true) {
        return { state: "dispatch_in_flight", taskId, dispatchId };
      }
      await control(oidc, {
        action: "operations_reasoning_rdp_dispatch_ack",
        leaseId,
        dispatchId,
        taskId,
        generation,
        receiptRef: reasoningAckRef(dispatchId, taskId, generation),
      });
    }

    const begun = await control(oidc, {
      action: "operations_reasoning_rdp_begin",
      taskId,
      leaseId,
      generation,
    });
    if (begun?.state !== "reasoning" ||
        !REASONING_UUID_PATTERN.test(String(begun?.requestId || "")) ||
        !/^[a-f0-9]{40}$/.test(String(begun?.sourceSha || "")) ||
        typeof begun?.prompt !== "string") {
      throw new Error("OPS_REASONING_RDP_BEGIN_INVALID");
    }

    const inference = await inferReasoning(token, {
      requestId: begun.requestId,
      taskId,
      leaseId,
      generation,
      sourceSha: begun.sourceSha,
      taskClass: "structured_extraction",
      parts: [{ type: "text", text: begun.prompt }],
      maxOutputTokens: Number(begun.maxOutputTokens || 128),
      maxCostMicros: Number(begun.maxCostMicros || 0),
      deadlineMs: Number(begun.deadlineMs || 45000),
    });

    if (inference?.state !== "verification_pending" ||
        typeof inference?.output !== "string" ||
        !/^[a-f0-9]{64}$/.test(String(inference?.outputDigest || ""))) {
      throw new Error("OPS_REASONING_RDP_MODEL_OUTPUT_UNAVAILABLE");
    }

    const materialized = await control(oidc, {
      action: "operations_reasoning_rdp_materialize",
      taskId,
      generation,
      output: inference.output,
    }, 20_000);

    return {
      state: materialized?.state || "child_queued",
      taskId,
      childTaskId: materialized?.childTaskId || null,
      profile: materialized?.profile || null,
      reasoningRequestId: begun.requestId,
      reasoningOutputDigest: inference.outputDigest,
      arbitraryCommandAuthority: false,
    };
  } catch (error: any) {
    try {
      await control(oidc, {
        action: "operations" + "_reconcile",
        leaseId,
        generation,
        reason: "REASONING_RDP_EXECUTION_UNCONFIRMED",
      });
    } catch {
      // The retained lease remains authoritative for reconciliation.
    }
    return {
      state: "reconciliation_required",
      taskId,
      dispatchId: dispatchId || null,
      code: String(error?.message || "REASONING_RDP_EXECUTION_UNCONFIRMED"),
    };
  }
}

type GenericSourceClaim = {
  taskId: string;
  claim: Json;
};

function parseGenericSourceCandidate(candidate: any) {
  const taskId = String(candidate?.taskId || "");
  const taskRevision = Number(candidate?.taskRevision);
  const controlRevision = Number(candidate?.controlRevision);
  if (
    !/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$/.test(taskId) ||
    !Number.isSafeInteger(taskRevision) ||
    !Number.isSafeInteger(controlRevision)
  ) {
    throw new Error("OPS_GENERIC_SOURCE_CANDIDATE_INVALID");
  }
  return { taskId, taskRevision, controlRevision };
}

async function claimGenericSourceBatch(oidc: string) {
  const claims: GenericSourceClaim[] = [];
  let lastCandidate: any = {
    state: "idle",
    reason: "no_dependency_ready_authorized_source_task",
  };
  let attempts = 0;
  while (claims.length < GENERIC_SOURCE_FANOUT && attempts < GENERIC_SOURCE_FANOUT * 2) {
    attempts += 1;
    const candidate = await control(oidc, { action: "operations_generic_source_candidate" });
    lastCandidate = candidate || lastCandidate;
    if (candidate?.state !== "ready") break;

    const parsed = parseGenericSourceCandidate(candidate);
    const claim = await control(oidc, {
      action: "operations_claim",
      taskId: parsed.taskId,
      taskRevision: parsed.taskRevision,
      controlRevision: parsed.controlRevision,
    });
    if (claim?.claimed === true) {
      claims.push({ taskId: parsed.taskId, claim });
    }
  }
  return { claims, lastCandidate };
}

async function executeClaimedGenericSourceTask(oidc: string, item: GenericSourceClaim) {
  const { taskId, claim } = item;
  let dispatchId = "";
  try {
    const intent = await control(oidc, {
      action: "operations_dispatch_prepare",
      leaseId: claim.leaseId,
      generation: claim.generation,
    });
    dispatchId = String(intent?.dispatchId || "");
    if (!/^[0-9a-f-]{36}$/i.test(dispatchId)) throw new Error("DISPATCH_INTENT_INVALID");
    if (intent?.canSend !== true && intent?.acknowledged !== true) {
      return { ok: true, state: "dispatch_in_flight", taskId, dispatchId };
    }
    if (intent?.acknowledged !== true) {
      await control(oidc, {
        action: "operations_dispatch_ack",
        leaseId: claim.leaseId,
        dispatchId,
        taskId,
        generation: claim.generation,
        receiptRef: receiptRef(dispatchId, taskId, claim.generation),
      });
    }

    const execution = await control(
      oidc,
      {
        action: "operations_generic_source_execute",
        taskId,
        generation: claim.generation,
      },
      120_000,
    );
    const headSha = String(execution?.headSha || "");
    const pullRequest = Number(execution?.pullRequest);
    const pullRequestUrl = String(execution?.pullRequestUrl || "");
    if (
      execution?.state !== "completed" ||
      !/^[0-9a-f]{40}$/.test(headSha) ||
      !Number.isSafeInteger(pullRequest) ||
      pullRequest < 1 ||
      !pullRequestUrl.startsWith("https://github.com/")
    ) {
      throw new Error("OPS_GENERIC_SOURCE_EXECUTION_INVALID");
    }

    const handoff = {
      taskId,
      workerId: BUILDER_ID,
      generation: claim.generation,
      headSha,
      pullRequest,
      tests: [
        "Lease-bound Operations source execution PASS",
        "Vault-backed GitHub branch and pull-request readback PASS",
        "Immutable task base ancestry check PASS",
      ],
      evidenceRefs: [
        pullRequestUrl,
        String(
          execution.receiptRef ||
            ("ops-source:" + taskId + ":" + claim.generation + ":" + headSha),
        ),
      ],
      receiptRef:
        "ops-native-handoff:" +
        createHash("sha256")
          .update(taskId + ":" + claim.generation + ":" + headSha + ":" + pullRequest)
          .digest("hex"),
      implementationComplete: true,
    };
    const handedOff = await control(oidc, {
      action: "operations_handoff",
      leaseId: claim.leaseId,
      generation: claim.generation,
      handoff,
    });
    return {
      ok: true,
      state: "handed_off",
      taskId,
      dispatchId,
      pullRequest,
      headSha,
      handedOff,
    };
  } catch (error: any) {
    try {
      await control(oidc, {
        action: "operations_reconcile",
        leaseId: claim.leaseId,
        generation: claim.generation,
        reason: "GENERIC_SOURCE_EXECUTION_UNCONFIRMED",
      });
    } catch {
      // Preserve the original failure; the retained lease remains authoritative.
    }
    return {
      ok: false,
      state: "reconciliation_required",
      taskId,
      dispatchId: dispatchId || null,
      code: String(error?.message || "GENERIC_SOURCE_EXECUTION_UNCONFIRMED"),
    };
  }
}

export default async function operationsNativeWorker(request: any, response: any) {
  const isCronWake = request.method === "GET";
  const isPostWake = request.method === "POST";
  if ((!isCronWake && !isPostWake) || request.headers.origin) {
    return send(response, 403, { ok: false, code: "OPS_NATIVE_WAKE_DENIED" });
  }

  const url = new URL(String(request.url || "/api/operations-native-worker"), "https://mcpmaster.vercel.app");
  if (url.search || url.hash) return send(response, 403, { ok: false, code: "OPS_NATIVE_WAKE_DENIED" });

  let tokenSha256 = "";
  let signed: { nonce: string; issuedAt: number } | null = null;
  let manualWake = false;
  if (isCronWake) {
    const declared = Number(request.headers["content-length"] || "0");
    if (!Number.isSafeInteger(declared) || declared !== 0 || !cronAuthorized(request)) {
      return send(response, 401, { ok: false, code: "OPS_NATIVE_WAKE_DENIED" });
    }
  } else {
    signed = signedWake(request);
    if (!signed) {
      const authorization = String(request.headers.authorization || "");
      const match = authorization.match(/^Bearer\s+([A-Za-z0-9._~-]{32,512})$/);
      if (!match) return send(response, 401, { ok: false, code: "OPS_NATIVE_WAKE_DENIED" });
      manualWake = true;
      tokenSha256 = createHash("sha256").update(match[1]).digest("hex");
    }
  }

  const oidc = await resolveVercelWorkloadToken();
  if (!oidc) return send(response, 503, { ok: false, code: "OPS_NATIVE_IDENTITY_UNAVAILABLE" });

  try {
    if (manualWake) {
      const authorized = await control(oidc, {
        action: "operations_wake_authorize",
        tokenSha256,
      });
      if (authorized !== true) {
        return send(response, 401, { ok: false, code: "OPS_NATIVE_WAKE_DENIED" });
      }
    } else if (signed) {
      const consumed = await control(oidc, {
        action: "operations_wake_nonce_consume",
        nonce: signed.nonce,
        issuedAt: signed.issuedAt,
      });
      if (consumed !== true) {
        return send(response, 401, { ok: false, code: "OPS_NATIVE_WAKE_REPLAY_DENIED" });
      }
    }

    const memory = await memoryContextCanary(oidc);

    await control(oidc, { action: "operations_native_register", workerRole: "builder" });
    await control(oidc, { action: "operations_native_register", workerRole: "release" });
    await control(oidc, { action: "operations_heartbeat", workerRole: "builder" });
    await control(oidc, { action: "operations_heartbeat", workerRole: "release" });

    const growthLearning = await drainGrowthLearning(oidc);

    const [snapshot, activation] = await Promise.all([
      control(oidc, { action: "operations_snapshot" }),
      control(oidc, { action: "operations_activation_readback" }),
    ]);

    if (snapshot?.controls?.paused === true) {
      return send(response, 200, {
        ok: true,
        state: "paused",
        registered: true,
        queuedTasks: activation?.queuedTasks ?? null,
        growthLearning,
        growthLearning,
      memory,
      });
    }

    const verification = await verifySupportedHandedOffTask(oidc, snapshot, memory);
    if (verification) {
      return send(response, 200, {
        ok: true,
        state: verification?.verified?.complete === true ? "complete" : "verification_pending",
        taskId: verification.taskId,
        verification,
        growthLearning,
        growthLearning,
      memory,
      });
    }

    const mergedFacebookSource = await verifyMergedFacebookSource(oidc, snapshot);
    if (mergedFacebookSource?.state === "complete") {
      return send(response, 200, {
        ok: true,
        state: "complete",
        taskId: "FB-025",
        release: mergedFacebookSource,
        growthLearning,
        growthLearning,
      memory,
      });
    }

    const reasoningRdp = await runReasoningRdpStep(oidc);
    const passiveReasoningStates = new Set([
      "idle",
      "budget_required",
      "model_route_unavailable",
      "held",
      "ineligible",
    ]);
    if (!passiveReasoningStates.has(String(reasoningRdp?.state || "idle"))) {
      return send(response, reasoningRdp?.state === "reconciliation_required" ? 503 : 200, {
        ok: reasoningRdp?.state !== "reconciliation_required",
        state: reasoningRdp?.state || "idle",
        taskId: reasoningRdp?.taskId ?? null,
        reasoningRdp,
        growthLearning,
        growthLearning,
      memory,
      });
    }

    const sourceRelease = await control(
      oidc,
      { action: "operations_generic_source_release_step" },
      60_000,
    );
    if (!canContinueSourceBuilding(sourceRelease?.state)) {
      return send(response, 200, {
        ok: true,
        state: sourceRelease.state,
        taskId: sourceRelease.taskId ?? null,
        release: sourceRelease,
        growthLearning,
        growthLearning,
      memory,
      });
    }

    if (activation?.nativeWorkerRpc !== true) {
      return send(response, 503, { ok: false, code: "OPS_NATIVE_RUNTIME_READBACK_INCOMPLETE" });
    }

    const batch = await claimGenericSourceBatch(oidc);
    if (batch.claims.length === 0) {
      const candidate = batch.lastCandidate;
      const preflight = await control(oidc, { action: "operations_preflight_next" });
      if (preflight?.state === "preflighted") {
        return send(response, 200, {
          ok: true,
          state: "preflighted",
          taskId: preflight.taskId ?? null,
          executionClass: preflight.executionClass ?? null,
          preflight,
          growthLearning,
        growthLearning,
      memory,
        });
      }
      return send(response, 200, {
        ok: true,
        state: "idle",
        registered: true,
        reason: candidate?.reason || "no_dependency_ready_authorized_source_task",
        humanBlocked: candidate?.humanBlocked ?? 0,
        mergedFacebookSource,
        preflighted: preflight?.preflighted ?? null,
        sourceFanout: { limit: GENERIC_SOURCE_FANOUT, claimed: 0, results: [] },
        growthLearning,
        growthLearning,
      memory,
      });
    }

    const results = await Promise.all(
      batch.claims.map((item) => executeClaimedGenericSourceTask(oidc, item)),
    );
    const reconciliationRequired = results.some(
      (result) => result.state === "reconciliation_required",
    );
    const state =
      reconciliationRequired
        ? "reconciliation_required"
        : results.length === 1
          ? results[0].state
          : results.every((result) => result.state === "handed_off")
            ? "source_fanout_handed_off"
            : "source_fanout_progress";

    return send(response, reconciliationRequired ? 503 : 200, {
      ok: !reconciliationRequired,
      state,
      taskId: results.length === 1 ? results[0].taskId : null,
      taskIds: results.map((result) => result.taskId),
      sourceFanout: {
        limit: GENERIC_SOURCE_FANOUT,
        claimed: batch.claims.length,
        results,
      },
      growthLearning,
      memory,
    });

  } catch (error: any) {
    const status = Number(error?.status || 503);
    return send(response, status === 401 || status === 403 ? status : 503, {
      ok: false,
      code: String(error?.code || error?.message || "OPS_NATIVE_WORKER_UNAVAILABLE"),
    });
  }
}
