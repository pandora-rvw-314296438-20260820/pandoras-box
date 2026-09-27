import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { resolveVercelWorkloadToken } from "../src/runtime/vercel-workload-identity.js";

export const config = { api: { bodyParser: false }, maxDuration: 60 };

const CONTROL_URL = "https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/mcpmaster-supabase-control";
const WORKER_KEY = "pandora-rdp-windows-01";
const MAX_BODY_BYTES = 64_000;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^[0-9a-f]{64}$/;
const TASK_PATTERN = /^OPS-RDP-[A-Za-z0-9_.:-]{1,110}$/;

type Json = Record<string, any>;

function send(response: any, status: number, body: Json) {
  response.status(status);
  response.setHeader("content-type", "application/json; charset=utf-8");
  response.setHeader("cache-control", "no-store");
  response.setHeader("x-content-type-options", "nosniff");
  return response.end(JSON.stringify(body));
}

async function rawBody(request: any): Promise<string> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > MAX_BODY_BYTES) throw new Error("REQUEST_TOO_LARGE");
    chunks.push(buffer);
  }
  return Buffer.concat(chunks).toString("utf8");
}

async function control(oidc: string, input: Json) {
  const result = await fetch(CONTROL_URL, {
    method: "POST",
    headers: { authorization: `Bearer ${oidc}`, "content-type": "application/json" },
    body: JSON.stringify(input),
    redirect: "error",
    signal: AbortSignal.timeout(12_000),
  });
  const payload = await result.json().catch(() => ({}));
  if (!result.ok || payload?.ok !== true) {
    throw Object.assign(new Error("OPERATIONS_CONTROL_UNAVAILABLE"), {
      status: result.status, code: payload?.error || "OPERATIONS_CONTROL_UNAVAILABLE",
    });
  }
  return payload.operations;
}

function bearerToken(request: any) {
  const value = String(request.headers.authorization || "");
  const match = value.match(/^Bearer\s+([A-Za-z0-9._~-]{32,256})$/);
  return match?.[1] || "";
}

function header(request: any, name: string) {
  return String(request.headers[name] || "").trim();
}

function safeEqualHex(a: string, b: string) {
  if (!SHA256_PATTERN.test(a) || !SHA256_PATTERN.test(b)) return false;
  return timingSafeEqual(Buffer.from(a, "hex"), Buffer.from(b, "hex"));
}

function verifySignedEnvelope(request: any, token: string, body: string) {
  const issuedAt = Number(header(request, "x-pandora-issued-at"));
  const nonce = header(request, "x-pandora-nonce");
  const signature = header(request, "x-pandora-signature").toLowerCase();
  if (!Number.isInteger(issuedAt) || Math.abs(Math.floor(Date.now() / 1000) - issuedAt) > 120) {
    throw new Error("RDP_REQUEST_STALE");
  }
  if (!UUID_PATTERN.test(nonce) || !SHA256_PATTERN.test(signature)) {
    throw new Error("RDP_REQUEST_SIGNATURE_INVALID");
  }
  const bodySha = createHash("sha256").update(body).digest("hex");
  const expected = createHmac("sha256", token)
    .update(`${issuedAt}\n${nonce}\n${bodySha}`)
    .digest("hex");
  if (!safeEqualHex(expected, signature)) throw new Error("RDP_REQUEST_SIGNATURE_INVALID");
  return { issuedAt, nonce };
}

function eligible(task: any) {
  const capabilities = Array.isArray(task?.spec?.requiredCapabilities)
    ? task.spec.requiredCapabilities.map(String) : [];
  return task?.status === "queued"
    && TASK_PATTERN.test(String(task?.spec?.id || ""))
    && task?.spec?.risk === "read"
    && ["reliability", "mobile"].includes(String(task?.spec?.lane || ""))
    && capabilities.includes("rdp.execute");
}

function profileForTask(task: any) {
  const taskId = String(task?.spec?.id || "");
  const caps = Array.isArray(task?.spec?.requiredCapabilities)
    ? task.spec.requiredCapabilities.map(String) : [];
  if (taskId === "OPS-RDP-WORKER-CANARY-V1") return "canary_v1";
  if (caps.includes("rdp.android.verify")) return "android_verify";
  if (caps.includes("rdp.flutter.verify")) return "flutter_verify";
  if (caps.includes("rdp.github_runner.verify")) return "github_runner_verify";
  return "toolchain_verify";
}

function validEvidence(evidence: any) {
  return evidence && typeof evidence === "object"
    && evidence.exitCode === 0
    && typeof evidence.profile === "string"
    && SHA256_PATTERN.test(String(evidence.stdoutSha256 || ""))
    && SHA256_PATTERN.test(String(evidence.proofSha256 || ""))
    && Array.isArray(evidence.tests)
    && evidence.tests.length >= 1 && evidence.tests.length <= 16
    && evidence.tests.every((value: unknown) => typeof value === "string" && value.length >= 1 && value.length <= 240);
}

export default async function operationsRdpWorker(request: any, response: any) {
  if (request.method !== "POST" || request.headers.origin) {
    return send(response, 403, { ok: false, code: "RDP_WORKER_REQUEST_DENIED" });
  }

  let body = "";
  try { body = await rawBody(request); }
  catch { return send(response, 413, { ok: false, code: "RDP_WORKER_REQUEST_TOO_LARGE" }); }

  const token = bearerToken(request);
  if (!token) return send(response, 401, { ok: false, code: "RDP_WORKER_UNAUTHORIZED" });

  let signed: { issuedAt: number; nonce: string };
  try { signed = verifySignedEnvelope(request, token, body); }
  catch (error: any) {
    return send(response, 401, { ok: false, code: String(error?.message || "RDP_WORKER_UNAUTHORIZED") });
  }

  let input: Json;
  try { input = JSON.parse(body || "{}"); }
  catch { return send(response, 400, { ok: false, code: "RDP_WORKER_INVALID_JSON" }); }

  const oidc = await resolveVercelWorkloadToken();
  if (!oidc) return send(response, 503, { ok: false, code: "RDP_WORKER_IDENTITY_UNAVAILABLE" });

  try {
    const tokenSha256 = createHash("sha256").update(token).digest("hex");
    const authorized = await control(oidc, {
      action: "operations_rdp_authorize", workerKey: WORKER_KEY, tokenSha256,
    });
    if (authorized !== true) return send(response, 401, { ok: false, code: "RDP_WORKER_UNAUTHORIZED" });

    const consumed = await control(oidc, {
      action: "operations_wake_nonce_consume", nonce: signed.nonce, issuedAt: signed.issuedAt,
    });
    if (consumed !== true) return send(response, 409, { ok: false, code: "RDP_WORKER_REPLAY_REJECTED" });

    await control(oidc, { action: "operations_rdp_register" });
    await control(oidc, { action: "operations_rdp_heartbeat" });

    const action = String(input.action || "");
    if (action === "poll") {
      const snapshot = await control(oidc, { action: "operations_snapshot" });
      if (snapshot?.controls?.paused === true) return send(response, 200, { ok: true, state: "paused" });
      const candidates = Array.isArray(snapshot?.tasks)
        ? snapshot.tasks.filter(eligible).sort((a: any, b: any) =>
          Number(a?.spec?.priority ?? 3) - Number(b?.spec?.priority ?? 3)
          || Number(a?.queuedAt ?? 0) - Number(b?.queuedAt ?? 0))
        : [];
      for (const task of candidates.slice(0, 8)) {
        const claim = await control(oidc, {
          action: "operations_rdp_claim", taskId: task.spec.id,
          taskRevision: task.revision, controlRevision: snapshot.controls.revision,
        });
        if (claim?.claimed !== true) continue;
        const dispatch = await control(oidc, {
          action: "operations_dispatch_prepare", leaseId: claim.leaseId, generation: claim.generation,
        });
        if (!dispatch?.dispatchId) throw new Error("RDP_DISPATCH_PREPARE_FAILED");
        return send(response, 200, { ok: true, state: "offered", offer: {
          taskId: task.spec.id, title: task.spec.title, leaseId: claim.leaseId,
          generation: claim.generation, dispatchId: dispatch.dispatchId, expiresAt: claim.expiresAt,
          profile: profileForTask(task),
        } });
      }
      return send(response, 200, { ok: true, state: "idle" });
    }

    const taskId = String(input.taskId || "");
    const leaseId = String(input.leaseId || "");
    const dispatchId = String(input.dispatchId || "");
    const generation = Number(input.generation);
    if (!TASK_PATTERN.test(taskId) || !UUID_PATTERN.test(leaseId) || !UUID_PATTERN.test(dispatchId)
      || !Number.isInteger(generation) || generation < 1) {
      return send(response, 400, { ok: false, code: "RDP_WORKER_ENVELOPE_INVALID" });
    }

    if (action === "accept") {
      const receiptRef = `rdp-ack:${createHash("sha256")
        .update(`${dispatchId}:${taskId}:${generation}:${WORKER_KEY}`).digest("hex")}`;
      const accepted = await control(oidc, {
        action: "operations_rdp_dispatch_ack", leaseId, dispatchId, taskId, generation, receiptRef,
      });
      const snapshot = await control(oidc, { action: "operations_snapshot" });
      const task = Array.isArray(snapshot?.tasks)
        ? snapshot.tasks.find((entry: any) => entry?.spec?.id === taskId) : undefined;
      if (!task) throw new Error("RDP_TASK_READBACK_FAILED");
      return send(response, 200, { ok: true, state: "accepted", profile: profileForTask(task), accepted });
    }

    if (action === "complete") {
      if (!validEvidence(input.evidence)) return send(response, 400, { ok: false, code: "RDP_WORKER_EVIDENCE_INVALID" });
      const snapshot = await control(oidc, { action: "operations_snapshot" });
      const task = Array.isArray(snapshot?.tasks)
        ? snapshot.tasks.find((entry: any) => entry?.spec?.id === taskId)
        : undefined;
      const sourceSha = String(task?.spec?.source?.baseSha || "");
      if (!/^[0-9a-f]{40}$/.test(sourceSha)) {
        return send(response, 409, { ok: false, code: "RDP_WORKER_SOURCE_BINDING_INVALID" });
      }
      const evidence = input.evidence;
      const proofBasis = `${dispatchId}:${taskId}:${generation}:${evidence.profile}:${evidence.exitCode}:${evidence.stdoutSha256}`;
      const expectedProof = createHash("sha256").update(proofBasis).digest("hex");
      if (!safeEqualHex(expectedProof, evidence.proofSha256)) {
        return send(response, 400, { ok: false, code: "RDP_WORKER_PROOF_INVALID" });
      }
      const handoff = {
        taskId, workerId: WORKER_KEY, generation, headSha: sourceSha, tests: evidence.tests,
        evidenceRefs: [
          `rdp:${WORKER_KEY}:${evidence.profile}`,
          `sha256:${evidence.stdoutSha256}`,
          `dispatch:${dispatchId}`,
          `source:${sourceSha}`,
        ],
        receiptRef: `rdp-worker:${evidence.proofSha256}`, implementationComplete: true,
        machineProof: { profile: evidence.profile, exitCode: evidence.exitCode,
          stdoutSha256: evidence.stdoutSha256, proofSha256: evidence.proofSha256 },
      };
      const handedOff = await control(oidc, { action: "operations_rdp_handoff", leaseId, generation, handoff });
      return send(response, 200, { ok: true, state: "handed_off", handedOff });
    }

    if (action === "fail") {
      const reconciled = await control(oidc, {
        action: "operations_reconcile", leaseId, generation, reason: "RDP_EXECUTION_FAILED",
      });
      return send(response, 200, { ok: true, state: "reconciliation_required", reconciled });
    }

    return send(response, 400, { ok: false, code: "RDP_WORKER_ACTION_INVALID" });
  } catch (error: any) {
    const status = Number(error?.status || 503);
    return send(response, status === 401 || status === 403 ? status : 503, {
      ok: false, code: String(error?.code || error?.message || "RDP_WORKER_UNAVAILABLE"),
    });
  }
}
