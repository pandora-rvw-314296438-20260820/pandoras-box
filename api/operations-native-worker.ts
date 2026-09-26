import { createHash, createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { resolveVercelWorkloadToken } from "../src/runtime/vercel-workload-identity.js";

export const config = { api: { bodyParser: false }, maxDuration: 60 };

const CONTROL_URL =
  "https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/mcpmaster-supabase-control";
const REPOSITORY = "pandora-rvw-314296438-20260820/pandoras-box";
const MEMORY_URL = "https://ivmvufhcsezyhczzondn.supabase.co/functions/v1/pandora-memory-bridge";
const MEMORY_PROJECT_ID = "7c686cbd-d968-49d5-86cc-918f5e777bd2";
const BUILDER_ID = "pandora-native-builder-v1";
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

async function control(oidc: string, input: Json) {
  const response = await fetch(CONTROL_URL, {
    method: "POST",
    headers: {
      authorization: `Bearer ${oidc}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(input),
    redirect: "error",
    signal: AbortSignal.timeout(12_000),
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
        memory,
      });
    }

    const task = Array.isArray(snapshot?.tasks)
      ? snapshot.tasks.find(
          (entry: any) =>
            entry?.status === "queued" && entry?.spec?.id === CANARY_TASK,
        )
      : undefined;

    if (!task) {
      return send(response, 200, {
        ok: true,
        state: "idle",
        registered: true,
        reason: "no_supported_queued_task",
        memory,
      });
    }

    if (
      activation?.connectorDeliveryTable !== true ||
      activation?.connectorDeliveryRpc !== true ||
      activation?.connectorReconcileRpc !== true ||
      activation?.nativeWorkerRpc !== true
    ) {
      return send(response, 503, {
        ok: false,
        code: "OPS_CONNECTOR_READBACK_INCOMPLETE",
      });
    }

    // Read provider evidence before claiming so an external read failure cannot strand a lease.
    const evidence = await connectorCanaryEvidence();

    const claim = await control(oidc, {
      action: "operations_claim",
      taskId: CANARY_TASK,
      taskRevision: task.revision,
      controlRevision: snapshot.controls.revision,
    });
    if (claim?.claimed !== true) {
      return send(response, 200, {
        ok: true,
        state: "not_claimed",
        reason: claim?.reason || "claim_rejected",
      });
    }

    let dispatchId = "";
    try {
      const intent = await control(oidc, {
        action: "operations_dispatch_prepare",
        leaseId: claim.leaseId,
        generation: claim.generation,
      });
      dispatchId = String(intent?.dispatchId || "");
      if (!/^[0-9a-f-]{36}$/.test(dispatchId)) {
        throw new Error("DISPATCH_INTENT_INVALID");
      }
      if (intent?.canSend !== true && intent?.acknowledged !== true) {
        return send(response, 200, {
          ok: true,
          state: "dispatch_in_flight",
          dispatchId,
        });
      }

      const ackRef = receiptRef(dispatchId, CANARY_TASK, claim.generation);
      if (intent?.acknowledged !== true) {
        await control(oidc, {
          action: "operations_dispatch_ack",
          leaseId: claim.leaseId,
          dispatchId,
          taskId: CANARY_TASK,
          generation: claim.generation,
          receiptRef: ackRef,
        });
      }

      const handoff = {
        taskId: CANARY_TASK,
        workerId: BUILDER_ID,
        generation: claim.generation,
        headSha: evidence.mergeSha,
        pullRequest: CANARY_PR,
        tests: [
          ...evidence.tests,
          "Live Supabase connector delivery table/RPC readback PASS",
          "Vercel production workload identity worker registration PASS",
        ],
        evidenceRefs: [
          evidence.prUrl,
          "supabase:migration:20260926012832",
          "supabase:rpc:pandora_ops_activation_readback_v1",
        ],
        receiptRef: `ops-native-handoff:${createHash("sha256")
          .update(`${dispatchId}:${evidence.mergeSha}:741`)
          .digest("hex")}`,
        implementationComplete: true,
      };

      const handedOff = await control(oidc, {
        action: "operations_handoff",
        leaseId: claim.leaseId,
        generation: claim.generation,
        handoff,
      });

      try {
        await control(oidc, { action: "operations_heartbeat", workerRole: "release" });
        const verified = await control(oidc, {
          action: "operations_native_release_verify",
          taskId: CANARY_TASK,
        });
        return send(response, 200, {
          ok: true,
          state: verified?.complete === true ? "complete" : "verification_pending",
          taskId: CANARY_TASK,
          dispatchId,
          mergeSha: evidence.mergeSha,
          handedOff,
          verified,
          memory,
        });
      } catch {
        return send(response, 503, {
          ok: false,
          state: "verification_pending",
          taskId: CANARY_TASK,
          dispatchId,
          code: "OPS_NATIVE_RELEASE_VERIFICATION_UNCONFIRMED",
        });
      }
    } catch (error: any) {
      try {
        await control(oidc, {
          action: "operations_reconcile",
          leaseId: claim.leaseId,
          generation: claim.generation,
          reason: "NATIVE_WORKER_EXECUTION_UNCONFIRMED",
        });
      } catch {
        // Preserve the original error; lease state remains authoritative.
      }
      return send(response, 503, {
        ok: false,
        state: "reconciliation_required",
        taskId: CANARY_TASK,
        dispatchId: dispatchId || null,
        code: String(error?.message || "NATIVE_WORKER_EXECUTION_UNCONFIRMED"),
      });
    }
  } catch (error: any) {
    const status = Number(error?.status || 503);
    return send(response, status === 401 || status === 403 ? status : 503, {
      ok: false,
      code: String(error?.code || error?.message || "OPS_NATIVE_WORKER_UNAVAILABLE"),
    });
  }
}
