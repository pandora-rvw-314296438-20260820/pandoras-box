import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { resolveVercelWorkloadToken } from "../src/runtime/vercel-workload-identity.js";

export const config = { api: { bodyParser: false }, maxDuration: 180 };

const CONTROL_URL =
  "https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/mcpmaster-supabase-control";
const INFERENCE_URL =
  "https://mcpmaster.vercel.app/api/operations-inference?operation=infer";
const TASK_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type Json = Record<string, any>;

function send(response: any, status: number, body: Json) {
  response.status(status);
  response.setHeader("content-type", "application/json; charset=utf-8");
  response.setHeader("cache-control", "no-store");
  response.setHeader("x-content-type-options", "nosniff");
  return response.end(JSON.stringify(body));
}

async function readJson(response: Response, maxBytes = 64_000) {
  const text = await response.text();
  if (Buffer.byteLength(text) > maxBytes) throw new Error("RESPONSE_TOO_LARGE");
  return text ? JSON.parse(text) : {};
}

async function control(oidc: string, input: Json, timeoutMs = 15_000) {
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
  const payload = await readJson(response);
  if (!response.ok || payload?.ok !== true) {
    throw Object.assign(new Error("OPS_BRIDGE_CONTROL_UNAVAILABLE"), {
      status: response.status,
      code: payload?.error || "OPS_BRIDGE_CONTROL_UNAVAILABLE",
    });
  }
  return payload.operations;
}

function signedWake(request: any) {
  const secret = String(process.env.PANDORA_OPS_WAKE_HMAC_SECRET || "");
  const timestamp = String(request.headers["x-pandora-wake-timestamp"] || "");
  const nonce = String(request.headers["x-pandora-wake-nonce"] || "");
  const signature = String(request.headers["x-pandora-wake-signature"] || "").toLowerCase();
  if (secret.length < 32 || secret.length > 512) return null;
  if (!/^\d{10}$/.test(timestamp) || !UUID_PATTERN.test(nonce) || !/^[0-9a-f]{64}$/.test(signature)) return null;
  const issuedAt = Number(timestamp);
  if (!Number.isSafeInteger(issuedAt) || Math.abs(Math.floor(Date.now() / 1000) - issuedAt) > 90) return null;
  const message = `${timestamp}\n${nonce}\nPOST\n/api/operations-reasoning-rdp-bridge\n{}`;
  const expected = createHmac("sha256", secret).update(message).digest("hex");
  if (expected.length !== signature.length ||
      !timingSafeEqual(Buffer.from(expected), Buffer.from(signature))) return null;
  return { nonce, issuedAt };
}

function inferenceToken() {
  const token = String(process.env.PANDORA_REASONING_RDP_INFERENCE_TOKEN || "");
  return /^opw_[A-Za-z0-9._~-]{32,256}$/.test(token) ? token : "";
}

function ackRef(dispatchId: string, taskId: string, generation: number) {
  return "reasoning-rdp-ack:" + createHash("sha256")
    .update(`${dispatchId}:${taskId}:${generation}:reasoning-rdp-bridge-v1`)
    .digest("hex");
}

async function infer(token: string, payload: Json) {
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
  const body = await readJson(response, 128_000);
  if (!response.ok) {
    throw Object.assign(new Error(String(body?.error || "INFERENCE_REQUEST_FAILED")), {
      status: response.status,
    });
  }
  return body;
}

async function advanceExisting(oidc: string, status: Json) {
  const taskId = String(status?.parentTaskId || "");
  const generation = Number(status?.parentGeneration);
  if (!TASK_PATTERN.test(taskId) || !Number.isSafeInteger(generation) || generation < 1) {
    return { state: "idle" };
  }

  if (status.state === "child_handed_off") {
    return control(oidc, {
      action: "operations_reasoning_rdp_verify_child",
      taskId,
      generation,
    });
  }

  if (status.state === "child_complete") {
    return control(oidc, {
      action: "operations_reasoning_rdp_parent_handoff",
      taskId,
      generation,
    });
  }

  if (status.state === "parent_handed_off") {
    return control(oidc, {
      action: "operations_reasoning_rdp_verify_parent",
      taskId,
      generation,
    });
  }

  if (status.state === "reasoning") {
    const leaseId = String(status?.parentLeaseId || "");
    if (UUID_PATTERN.test(leaseId)) {
      await control(oidc, {
        action: "operations_reconcile",
        leaseId,
        generation,
        reason: "REASONING_OUTPUT_UNRECOVERABLE",
      });
    }
    return { state: "reconciliation_required", taskId, reason: "reasoning_output_not_durable" };
  }

  return status;
}

export default async function operationsReasoningRdpBridge(request: any, response: any) {
  if (request.method !== "POST" || request.headers.origin) {
    return send(response, 403, { ok: false, code: "OPS_REASONING_RDP_WAKE_DENIED" });
  }
  const url = new URL(String(request.url || "/api/operations-reasoning-rdp-bridge"), "https://mcpmaster.vercel.app");
  if (url.search || url.hash) return send(response, 403, { ok: false, code: "OPS_REASONING_RDP_WAKE_DENIED" });

  const declared = Number(request.headers["content-length"] || "0");
  if (Number.isFinite(declared) && declared > 16) {
    return send(response, 413, { ok: false, code: "OPS_REASONING_RDP_WAKE_DENIED" });
  }

  const wake = signedWake(request);
  if (!wake) return send(response, 401, { ok: false, code: "OPS_REASONING_RDP_WAKE_DENIED" });
  const token = inferenceToken();
  if (!token) return send(response, 503, { ok: false, code: "OPS_REASONING_RDP_INFERENCE_TOKEN_UNAVAILABLE" });

  const oidc = await resolveVercelWorkloadToken();
  if (!oidc) return send(response, 503, { ok: false, code: "OPS_REASONING_RDP_IDENTITY_UNAVAILABLE" });

  try {
    const consumed = await control(oidc, {
      action: "operations_wake_nonce_consume",
      nonce: wake.nonce,
      issuedAt: wake.issuedAt,
    });
    if (consumed !== true) {
      return send(response, 409, { ok: false, code: "OPS_REASONING_RDP_WAKE_REPLAY_DENIED" });
    }

    await control(oidc, { action: "operations_reasoning_rdp_register" });
    await control(oidc, { action: "operations_reasoning_rdp_heartbeat" });
    await control(oidc, { action: "operations_native_register", workerRole: "release" });
    await control(oidc, { action: "operations_heartbeat", workerRole: "release" });

    let status = await control(oidc, { action: "operations_reasoning_rdp_status" });
    if (status?.state && status.state !== "idle") {
      const advanced = await advanceExisting(oidc, status);
      if (advanced?.complete === true || advanced?.state === "parent_handed_off") {
        status = await control(oidc, { action: "operations_reasoning_rdp_status" });
        if (status?.state === "parent_handed_off") {
          const verified = await advanceExisting(oidc, status);
          return send(response, 200, { ok: true, state: "complete", taskId: status.parentTaskId, verification: verified });
        }
      }
      return send(response, 200, { ok: true, state: advanced?.state || status.state, taskId: status.parentTaskId || null, result: advanced });
    }

    const candidate = await control(oidc, { action: "operations_reasoning_rdp_candidate" });
    if (candidate?.state !== "ready") {
      return send(response, 200, {
        ok: true,
        state: candidate?.state || "idle",
        taskId: candidate?.taskId || null,
        reason: candidate?.reason || null,
        requiredTaskBudgetMicros: candidate?.requiredTaskBudgetMicros ?? null,
        workspaceAvailableMicros: candidate?.workspaceAvailableMicros ?? null,
      });
    }

    const taskId = String(candidate.taskId || "");
    const taskRevision = Number(candidate.taskRevision);
    const controlRevision = Number(candidate.controlRevision);
    if (!TASK_PATTERN.test(taskId) || !Number.isSafeInteger(taskRevision) || !Number.isSafeInteger(controlRevision)) {
      throw new Error("OPS_REASONING_RDP_CANDIDATE_INVALID");
    }

    const claim = await control(oidc, {
      action: "operations_reasoning_rdp_claim",
      taskId,
      taskRevision,
      controlRevision,
    });
    if (claim?.claimed !== true) {
      return send(response, 200, { ok: true, state: "not_claimed", taskId, reason: claim?.reason || "claim_rejected" });
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
      if (!UUID_PATTERN.test(dispatchId)) throw new Error("OPS_REASONING_RDP_DISPATCH_INVALID");
      if (intent?.acknowledged !== true) {
        await control(oidc, {
          action: "operations_reasoning_rdp_dispatch_ack",
          leaseId,
          dispatchId,
          taskId,
          generation,
          receiptRef: ackRef(dispatchId, taskId, generation),
        });
      }

      const begun = await control(oidc, {
        action: "operations_reasoning_rdp_begin",
        taskId,
        leaseId,
        generation,
      });
      if (begun?.state !== "reasoning" || !UUID_PATTERN.test(String(begun?.requestId || "")) ||
          !/^[a-f0-9]{40}$/.test(String(begun?.sourceSha || "")) ||
          typeof begun?.prompt !== "string") {
        throw new Error("OPS_REASONING_RDP_BEGIN_INVALID");
      }

      const inference = await infer(token, {
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

      if (inference?.state !== "verification_pending" || typeof inference?.output !== "string" ||
          !/^[a-f0-9]{64}$/.test(String(inference?.outputDigest || ""))) {
        throw new Error("OPS_REASONING_RDP_MODEL_OUTPUT_UNAVAILABLE");
      }

      const materialized = await control(oidc, {
        action: "operations_reasoning_rdp_materialize",
        taskId,
        generation,
        output: inference.output,
      }, 20_000);

      return send(response, 200, {
        ok: true,
        state: materialized?.state || "child_queued",
        taskId,
        childTaskId: materialized?.childTaskId || null,
        profile: materialized?.profile || null,
        reasoningRequestId: begun.requestId,
        reasoningOutputDigest: inference.outputDigest,
        arbitraryCommandAuthority: false,
      });
    } catch (error: any) {
      try {
        await control(oidc, {
          action: "operations_reconcile",
          leaseId,
          generation,
          reason: "REASONING_RDP_EXECUTION_UNCONFIRMED",
        });
      } catch {
        // The retained parent lease remains the reconciliation authority.
      }
      return send(response, 503, {
        ok: false,
        state: "reconciliation_required",
        taskId,
        dispatchId: dispatchId || null,
        code: String(error?.message || "REASONING_RDP_EXECUTION_UNCONFIRMED"),
      });
    }
  } catch (error: any) {
    const status = Number(error?.status || 503);
    return send(response, status === 401 || status === 403 ? status : 503, {
      ok: false,
      code: String(error?.code || error?.message || "OPS_REASONING_RDP_BRIDGE_UNAVAILABLE"),
    });
  }
}
