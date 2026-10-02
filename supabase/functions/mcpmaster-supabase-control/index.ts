import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createRemoteJWKSet, decodeJwt, jwtVerify } from "npm:jose@5.10.0";
import { routeForCanonicalReleaseCapture } from "./canonical-release-capture-routes.mjs";
import { assertProductionVercelClaims } from "./identity-policy.mjs";
import { routeForRdpOperations } from "./rdp-routes.mjs";
import { routeForMergedRelease } from "./merged-release-routes.mjs";
import { routeForReasoningRdpOperations } from "./reasoning-rdp-routes.mjs";
import { handleGeminiWorkerRequest } from "./gemini-worker-gateway.mjs";

const CONTROL_ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const OPERATIONS_PROJECT_ID = "ee282126-3f61-4058-8c92-2fedbfcecf1f";
const OPERATIONS_NATIVE_WORKERS = Object.freeze({
  builder: Object.freeze({
    workerKey: "pandora-native-builder-v1",
    principalKey: "vercel:mcpmaster:operations-native-builder-v1",
    lanes: ["backend", "reliability", "web", "growth"],
    capabilities: [
      "source.write",
      "ci.verify",
      "release.handoff",
      "runtime.deploy",
      "worker.reconcile",
      "provider.readback",
      "security.verify",
      "memory.integrate",
      "inference.route",
      "events.verify",
    ],
    capacity: 4,
  }),
  release: Object.freeze({
    workerKey: "pandora-native-release-v1",
    principalKey: "vercel:mcpmaster:operations-native-release-v1",
    lanes: ["release"],
    capabilities: ["release.verify", "provider.readback", "canary.execute"],
    capacity: 1,
  }),
});
const OPERATIONS_NATIVE_GENERIC_VERIFY_TASKS = new Set([
  "OPS-MEMORY-CALLER-ADOPTION-V1",
  "OPS-WHOLE-SHEET-ACCEPTANCE-V3",
]);
const MAX_REQUEST_BYTES = 256_000;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type ControlRpc =
  | "get_supabase_control_accounts"
  | "get_github_control_accounts"
  | "get_runtime_security_config"
  | "pandora_create_execution_plan"
  | "pandora_approve_execution_plan"
  | "pandora_claim_execution_plan"
  | "pandora_finish_execution_plan"
  | "list_execution_plans"
  | "list_execution_audit"
  | "verify_execution_audit_chain"
  | "consume_runtime_rate_limit"
  | "get_canonical_release_status"
  | "capture_canonical_supabase_release_receipt"
  | "capture_canonical_vercel_rehearsal_receipt"
  | "pandora_ops_register_native_worker_v1"
  | "pandora_ops_heartbeat_v1"
  | "pandora_ops_snapshot_v1"
  | "pandora_ops_claim_v1"
  | "pandora_ops_dispatch_v1"
  | "pandora_ops_handoff_v1"
  | "pandora_ops_activation_readback_v1"
  | "pandora_ops_wake_authorize_v1"
  | "pandora_ops_reconcile_required_v1"
  | "pandora_ops_reconcile_external_success_v1"
  | "pandora_ops_reconcile_merged_release_v1"
  | "pandora_ops_merged_release_source_step_v1"
  | "pandora_ops_verify_merged_release_source_v1"
  | "pandora_ops_native_release_verify_v1"
  | "pandora_ops_record_verification_v1"
  | "pandora_ops_verify_v1"
  | "pandora_ops_final_acceptance_readback_v1"
  | "pandora_ops_wake_nonce_consume_v1"
  | "pandora_ops_generic_source_candidate_v1"
  | "pandora_ops_generic_source_execute_v1"
  | "pandora_ops_generic_source_release_step_v1"
  | "pandora_ops_preflight_next_v1"
  | "pandora_ops_register_reasoning_rdp_bridge_v1"
  | "pandora_ops_reasoning_rdp_candidate_v1"
  | "pandora_ops_reasoning_rdp_begin_v1"
  | "pandora_ops_reasoning_rdp_materialize_v1"
  | "pandora_ops_reasoning_rdp_status_v1"
  | "pandora_ops_reasoning_rdp_verify_child_v1"
  | "pandora_ops_reasoning_rdp_parent_handoff_v1"
  | "pandora_ops_reasoning_rdp_verify_parent_v1"
  | "pandora_ops_register_rdp_artemis_verifier_v1"
  | "pandora_ops_reasoning_rdp_queue_memory_v1"
  | "pandora_bedrock_catalog_sync_claim_v1"
  | "pandora_apply_bedrock_catalog_sync_v2"
  | "pandora_bedrock_catalog_sync_fail_v1"
  | "pandora_claim_growth_learning_delivery_v1"
  | "pandora_ack_growth_learning_delivery_v1";

type ControlAction =
  | "catalog"
  | "github_catalog"
  | "runtime_security"
  | "execution_plan_create"
  | "execution_plan_approve"
  | "execution_plan_claim"
  | "execution_plan_finish"
  | "execution_plan_list"
  | "execution_audit_list"
  | "execution_audit_verify"
  | "runtime_rate_limit_consume"
  | "canonical_release_status"
  | "canonical_supabase_receipt_capture"
  | "canonical_vercel_rehearsal_capture"
  | "operations_native_register"
  | "operations_heartbeat"
  | "operations_snapshot"
  | "operations_claim"
  | "operations_dispatch_prepare"
  | "operations_dispatch_ack"
  | "operations_handoff"
  | "operations_activation_readback"
  | "operations_wake_authorize"
  | "operations_reconcile"
  | "operations_external_success_reconcile"
  | "operations_merged_release_reconcile"
  | "operations_merged_release_source_step"
  | "operations_merged_release_verify_source"
  | "operations_native_release_verify"
  | "operations_verification_record"
  | "operations_verification_accept"
  | "operations_final_acceptance_readback"
  | "operations_wake_nonce_consume"
  | "bedrock_catalog_sync_claim"
  | "bedrock_catalog_sync_apply"
  | "bedrock_catalog_sync_fail"
  | "operations_generic_source_candidate"
  | "operations_generic_source_execute"
  | "operations_generic_source_release_step"
  | "operations_preflight_next"
  | "operations_reasoning_rdp_register"
  | "operations_reasoning_rdp_heartbeat"
  | "operations_reasoning_rdp_candidate"
  | "operations_reasoning_rdp_claim"
  | "operations_reasoning_rdp_dispatch_ack"
  | "operations_reasoning_rdp_begin"
  | "operations_reasoning_rdp_materialize"
  | "operations_reasoning_rdp_status"
  | "operations_reasoning_rdp_verify_child"
  | "operations_reasoning_rdp_parent_handoff"
  | "operations_reasoning_rdp_verify_parent"
  | "operations_rdp_artemis_register"
  | "operations_reasoning_rdp_queue_memory"
  | "growth_learning_claim"
  | "growth_learning_ack";

interface ControlRoute {
  action: ControlAction;
  rpc: ControlRpc;
  params: Record<string, unknown>;
  responseKey:
    | "accounts"
    | "security"
    | "plan"
    | "plans"
    | "checkpoint"
    | "events"
    | "verification"
    | "rateLimit"
    | "releaseEvidence"
    | "supabaseReceipt"
    | "vercelRehearsalReceipt"
    | "operations";
}

function response(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function bearerToken(request: Request): string | undefined {
  const authorization = request.headers.get("authorization");
  const match = authorization?.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim();
}

function trustedIssuer(token: string): string {
  const decoded = decodeJwt(token);
  if (typeof decoded.iss !== "string") throw new Error("missing issuer");

  const issuer = new URL(decoded.iss);
  const segments = issuer.pathname.split("/").filter(Boolean);
  if (
    issuer.protocol !== "https:"
    || issuer.hostname !== "oidc.vercel.com"
    || issuer.username
    || issuer.password
    || issuer.search
    || issuer.hash
    || segments.length > 1
  ) {
    throw new Error("untrusted issuer");
  }

  issuer.pathname = segments.length === 1 ? `/${segments[0]}` : "";
  return issuer.toString().replace(/\/$/, "");
}

function audienceValues(audience: unknown): string[] {
  if (typeof audience === "string") return [audience];
  if (Array.isArray(audience) && audience.every((value) => typeof value === "string")) {
    return audience as string[];
  }
  return [];
}

async function verifyVercelToken(token: string): Promise<void> {
  const unverified = decodeJwt(token);
  const issuer = trustedIssuer(token);
  const audiences = audienceValues(unverified.aud);
  if (audiences.length === 0 || !audiences.every((value) => value.startsWith("https://vercel.com/"))) {
    throw new Error("untrusted audience");
  }

  const jwks = createRemoteJWKSet(new URL(`${issuer}/.well-known/jwks`));
  const { payload } = await jwtVerify(token, jwks, {
    issuer,
    audience: audiences,
  });

  assertProductionVercelClaims(payload, audiences);
}

function serviceRoleKey(): string | undefined {
  const modernKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (modernKeys) {
    try {
      const parsed = JSON.parse(modernKeys) as Record<string, unknown>;
      if (typeof parsed.default === "string" && parsed.default.length > 0) return parsed.default;
    } catch {
      // Fall through to the legacy built-in key.
    }
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? undefined;
}

async function fetchRpc(
  supabaseUrl: string,
  key: string,
  rpcName: ControlRpc,
  params: Record<string, unknown>,
): Promise<unknown | undefined> {
  const rpcResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/${rpcName}`, {
    method: "POST",
    headers: {
      apikey: key,
      authorization: `Bearer ${key}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      p_organization_id: CONTROL_ORGANIZATION_ID,
      ...params,
    }),
    redirect: "error",
  });

  if (!rpcResponse.ok) return undefined;
  return rpcResponse.json();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function requiredString(input: Record<string, unknown>, key: string): string | undefined {
  const value = input[key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function requiredUuid(input: Record<string, unknown>, key: string): string | undefined {
  const value = requiredString(input, key);
  return value && UUID_PATTERN.test(value) ? value : undefined;
}

function requiredInteger(
  input: Record<string, unknown>,
  key: string,
  minimum: number,
  maximum: number,
): number | undefined {
  const value = input[key];
  return typeof value === "number"
      && Number.isInteger(value)
      && value >= minimum
      && value <= maximum
    ? value
    : undefined;
}

function routeForInput(input: Record<string, unknown>): ControlRoute | undefined {
  const canonicalCapture = routeForCanonicalReleaseCapture(input);
  if (canonicalCapture) return canonicalCapture as ControlRoute;

  const rdpRoute = routeForRdpOperations(input, OPERATIONS_PROJECT_ID);
  if (rdpRoute) return rdpRoute as ControlRoute;

  const reasoningRdpRoute = routeForReasoningRdpOperations(input, OPERATIONS_PROJECT_ID);
  if (reasoningRdpRoute) return reasoningRdpRoute as ControlRoute;

  const mergedRelease = routeForMergedRelease(input, OPERATIONS_PROJECT_ID);
  if (mergedRelease) return mergedRelease as ControlRoute;

  if (input.action === "catalog") {
    return {
      action: "catalog",
      rpc: "get_supabase_control_accounts",
      params: {},
      responseKey: "accounts",
    };
  }
  if (input.action === "github_catalog") {
    return {
      action: "github_catalog",
      rpc: "get_github_control_accounts",
      params: {},
      responseKey: "accounts",
    };
  }
  if (input.action === "runtime_security") {
    return {
      action: "runtime_security",
      rpc: "get_runtime_security_config",
      params: {},
      responseKey: "security",
    };
  }

  if (input.action === "execution_plan_create") {
    const requestId = requiredUuid(input, "requestId");
    const tool = requiredString(input, "tool");
    const risk = requiredString(input, "risk");
    const payloadHash = requiredString(input, "payloadHash");
    const expiresAt = requiredString(input, "expiresAt");
    if (!requestId || !tool || !risk || !payloadHash || !expiresAt || !isRecord(input.args)) {
      return undefined;
    }
    return {
      action: "execution_plan_create",
      rpc: "pandora_create_execution_plan",
      responseKey: "plan",
      params: {
        p_request_id: requestId,
        p_tool: tool,
        p_risk: risk,
        p_args: input.args,
        p_payload_hash: payloadHash,
        p_expires_at: expiresAt,
      },
    };
  }

  if (input.action === "execution_plan_approve") {
    const planId = requiredUuid(input, "planId");
    const approvedBy = requiredString(input, "approvedBy");
    if (!planId || !approvedBy) return undefined;
    return {
      action: "execution_plan_approve",
      rpc: "pandora_approve_execution_plan",
      responseKey: "plan",
      params: { p_plan_id: planId, p_approved_by: approvedBy },
    };
  }

  if (input.action === "execution_plan_claim") {
    const planId = requiredUuid(input, "planId");
    if (!planId) return undefined;
    return {
      action: "execution_plan_claim",
      rpc: "pandora_claim_execution_plan",
      responseKey: "plan",
      params: { p_plan_id: planId },
    };
  }

  if (input.action === "execution_plan_finish") {
    const planId = requiredUuid(input, "planId");
    const status = requiredString(input, "status");
    if (!planId || !status) return undefined;
    return {
      action: "execution_plan_finish",
      rpc: "pandora_finish_execution_plan",
      responseKey: "plan",
      params: {
        p_plan_id: planId,
        p_status: status,
        p_duration_ms: typeof input.durationMs === "number" ? Math.max(0, Math.floor(input.durationMs)) : 0,
        p_error: typeof input.error === "string" ? input.error : null,
        p_result_summary: isRecord(input.resultSummary) ? input.resultSummary : {},
      },
    };
  }

  if (input.action === "execution_plan_list") {
    return {
      action: "execution_plan_list",
      rpc: "list_execution_plans",
      responseKey: "plans",
      params: {
        p_limit: typeof input.limit === "number" ? Math.min(Math.max(Math.floor(input.limit), 1), 500) : 100,
      },
    };
  }

  if (input.action === "execution_audit_list") {
    return {
      action: "execution_audit_list",
      rpc: "list_execution_audit",
      responseKey: "events",
      params: {
        p_limit: typeof input.limit === "number" ? Math.min(Math.max(Math.floor(input.limit), 1), 500) : 100,
      },
    };
  }

  if (input.action === "execution_audit_verify") {
    return {
      action: "execution_audit_verify",
      rpc: "verify_execution_audit_chain",
      responseKey: "verification",
      params: {},
    };
  }

  if (input.action === "runtime_rate_limit_consume") {
    const keyHash = requiredString(input, "keyHash");
    const limit = requiredInteger(input, "limit", 1, 10_000);
    const windowSeconds = requiredInteger(input, "windowSeconds", 1, 3_600);
    if (!keyHash || !/^[0-9a-f]{64}$/.test(keyHash) || !limit || !windowSeconds) return undefined;
    return {
      action: "runtime_rate_limit_consume",
      rpc: "consume_runtime_rate_limit",
      responseKey: "rateLimit",
      params: {
        p_key_hash: keyHash,
        p_limit: limit,
        p_window_seconds: windowSeconds,
      },
    };
  }

  if (input.action === "operations_native_register") {
    const workerRole = requiredString(input, "workerRole");
    const worker = workerRole === "builder"
      ? OPERATIONS_NATIVE_WORKERS.builder
      : workerRole === "release"
      ? OPERATIONS_NATIVE_WORKERS.release
      : undefined;
    if (!worker) return undefined;
    return {
      action: "operations_native_register",
      rpc: "pandora_ops_register_native_worker_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_worker_key: worker.workerKey,
        p_principal_key: worker.principalKey,
        p_lanes: worker.lanes,
        p_capabilities: worker.capabilities,
        p_capacity: worker.capacity,
        p_receipt_ref: `vercel-oidc:mcpmaster:production:${worker.workerKey}`,
      },
    };
  }

  if (input.action === "operations_heartbeat") {
    const workerRole = requiredString(input, "workerRole");
    const worker = workerRole === "builder"
      ? OPERATIONS_NATIVE_WORKERS.builder
      : workerRole === "release"
      ? OPERATIONS_NATIVE_WORKERS.release
      : undefined;
    if (!worker) return undefined;
    return {
      action: "operations_heartbeat",
      rpc: "pandora_ops_heartbeat_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_worker_key: worker.workerKey,
        p_principal_key: worker.principalKey,
        p_connected: true,
        p_health: "ready",
      },
    };
  }

  if (input.action === "operations_snapshot") {
    return {
      action: "operations_snapshot",
      rpc: "pandora_ops_snapshot_v1",
      responseKey: "operations",
      params: { p_project_id: OPERATIONS_PROJECT_ID },
    };
  }

  if (input.action === "operations_activation_readback") {
    return {
      action: "operations_activation_readback",
      rpc: "pandora_ops_activation_readback_v1",
      responseKey: "operations",
      params: { p_project_id: OPERATIONS_PROJECT_ID },
    };
  }

  if (input.action === "operations_wake_authorize") {
    const tokenSha256 = requiredString(input, "tokenSha256");
    if (!tokenSha256 || !/^[0-9a-f]{64}$/.test(tokenSha256)) return undefined;
    return {
      action: "operations_wake_authorize",
      rpc: "pandora_ops_wake_authorize_v1",
      responseKey: "operations",
      params: { p_token_sha256: tokenSha256 },
    };
  }

  if (input.action === "operations_wake_nonce_consume") {
    const nonce = requiredUuid(input, "nonce");
    const issuedAt = requiredInteger(input, "issuedAt", 1, Number.MAX_SAFE_INTEGER);
    if (!nonce || issuedAt === undefined) return undefined;
    return {
      action: "operations_wake_nonce_consume",
      rpc: "pandora_ops_wake_nonce_consume_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_nonce: nonce,
        p_issued_at: issuedAt,
      },
    };
  }

  if (input.action === "bedrock_catalog_sync_claim") {
    return {
      action: "bedrock_catalog_sync_claim",
      rpc: "pandora_bedrock_catalog_sync_claim_v1",
      responseKey: "operations",
      params: {},
    };
  }

  if (input.action === "bedrock_catalog_sync_apply") {
    const syncId = requiredUuid(input, "syncId");
    const region = requiredString(input, "region");
    const observedAt = requiredString(input, "observedAt");
    const models = Array.isArray(input.models) ? input.models : undefined;
    if (!syncId || region !== "us-east-1" || !observedAt || !Number.isFinite(Date.parse(observedAt))
        || !models || models.length < 1 || models.length > 500) return undefined;
    return {
      action: "bedrock_catalog_sync_apply",
      rpc: "pandora_apply_bedrock_catalog_sync_v2",
      responseKey: "operations",
      params: {
        p_sync_id: syncId,
        p_region: region,
        p_observed_at: observedAt,
        p_models: models,
      },
    };
  }

  if (input.action === "bedrock_catalog_sync_fail") {
    const syncId = requiredUuid(input, "syncId");
    const reason = requiredString(input, "reason");
    if (!syncId || !reason || reason.length > 160) return undefined;
    return {
      action: "bedrock_catalog_sync_fail",
      rpc: "pandora_bedrock_catalog_sync_fail_v1",
      responseKey: "operations",
      params: { p_sync_id: syncId, p_reason: reason },
    };
  }

  if (input.action === "growth_learning_claim") {
    const worker = OPERATIONS_NATIVE_WORKERS.builder;
    return {
      action: "growth_learning_claim",
      rpc: "pandora_claim_growth_learning_delivery_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_worker_key: worker.workerKey,
        p_principal_key: worker.principalKey,
      },
    };
  }

  if (input.action === "growth_learning_ack") {
    const outboxId = requiredUuid(input, "outboxId");
    const claimToken = requiredUuid(input, "claimToken");
    const httpStatus = requiredInteger(input, "httpStatus", 100, 599);
    const content = typeof input.content === "string" ? input.content : undefined;
    const error = input.error === null || input.error === undefined
      ? null
      : typeof input.error === "string" ? input.error : undefined;
    if (!outboxId || !claimToken || httpStatus === undefined || content === undefined
      || new TextEncoder().encode(content).byteLength > 65536 || (error !== null && (error === undefined || error.length > 2000))) {
      return undefined;
    }
    const worker = OPERATIONS_NATIVE_WORKERS.builder;
    return {
      action: "growth_learning_ack",
      rpc: "pandora_ack_growth_learning_delivery_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_worker_key: worker.workerKey,
        p_principal_key: worker.principalKey,
        p_outbox_id: outboxId,
        p_claim_token: claimToken,
        p_http_status: httpStatus,
        p_content: content,
        p_error: error,
      },
    };
  }

  if (input.action === "operations_preflight_next") {
    const worker = OPERATIONS_NATIVE_WORKERS.builder;
    return {
      action: "operations_preflight_next",
      rpc: "pandora_ops_preflight_next_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_worker_key: worker.workerKey,
        p_principal_key: worker.principalKey,
      },
    };
  }

  if (input.action === "operations_generic_source_candidate") {
    const worker = OPERATIONS_NATIVE_WORKERS.builder;
    return {
      action: "operations_generic_source_candidate",
      rpc: "pandora_ops_generic_source_candidate_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_worker_key: worker.workerKey,
        p_principal_key: worker.principalKey,
      },
    };
  }

  if (input.action === "operations_generic_source_execute") {
    const taskId = requiredString(input, "taskId");
    const generation = requiredInteger(input, "generation", 1, Number.MAX_SAFE_INTEGER);
    if (!taskId || !/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$/.test(taskId) || generation === undefined) return undefined;
    const worker = OPERATIONS_NATIVE_WORKERS.builder;
    return {
      action: "operations_generic_source_execute",
      rpc: "pandora_ops_generic_source_execute_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_task_key: taskId,
        p_generation: generation,
        p_worker_key: worker.workerKey,
        p_principal_key: worker.principalKey,
      },
    };
  }

  if (input.action === "operations_generic_source_release_step") {
    const release = OPERATIONS_NATIVE_WORKERS.release;
    return {
      action: "operations_generic_source_release_step",
      rpc: "pandora_ops_generic_source_release_step_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_verifier_key: release.workerKey,
        p_principal_key: release.principalKey,
      },
    };
  }

  if (input.action === "operations_claim") {
    const taskId = requiredString(input, "taskId");
    const taskRevision = requiredInteger(input, "taskRevision", 0, Number.MAX_SAFE_INTEGER);
    const controlRevision = requiredInteger(input, "controlRevision", 0, Number.MAX_SAFE_INTEGER);
    if (!taskId || !/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$/.test(taskId)
      || taskRevision === undefined || controlRevision === undefined) return undefined;
    const worker = OPERATIONS_NATIVE_WORKERS.builder;
    return {
      action: "operations_claim",
      rpc: "pandora_ops_claim_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_task_key: taskId,
        p_worker_key: worker.workerKey,
        p_task_revision: taskRevision,
        p_control_revision: controlRevision,
      },
    };
  }

  if (input.action === "operations_dispatch_prepare") {
    const leaseId = requiredUuid(input, "leaseId");
    const generation = requiredInteger(input, "generation", 1, Number.MAX_SAFE_INTEGER);
    if (!leaseId || generation === undefined) return undefined;
    return {
      action: "operations_dispatch_prepare",
      rpc: "pandora_ops_dispatch_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_lease_id: leaseId,
        p_generation: generation,
        p_ack: null,
      },
    };
  }

  if (input.action === "operations_dispatch_ack") {
    const leaseId = requiredUuid(input, "leaseId");
    const dispatchId = requiredUuid(input, "dispatchId");
    const taskId = requiredString(input, "taskId");
    const generation = requiredInteger(input, "generation", 1, Number.MAX_SAFE_INTEGER);
    const receiptRef = requiredString(input, "receiptRef");
    if (!leaseId || !dispatchId || !taskId || generation === undefined || !receiptRef
      || receiptRef.length > 1000) return undefined;
    const worker = OPERATIONS_NATIVE_WORKERS.builder;
    return {
      action: "operations_dispatch_ack",
      rpc: "pandora_ops_dispatch_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_lease_id: leaseId,
        p_generation: generation,
        p_ack: {
          accepted: true,
          dispatchId,
          workerId: worker.workerKey,
          taskId,
          generation,
          receiptRef,
        },
      },
    };
  }

  if (input.action === "operations_reconcile") {
    const leaseId = requiredUuid(input, "leaseId");
    const generation = requiredInteger(input, "generation", 1, Number.MAX_SAFE_INTEGER);
    const reason = requiredString(input, "reason");
    if (!leaseId || generation === undefined || !reason || !/^[A-Z_]{3,80}$/.test(reason)) return undefined;
    return {
      action: "operations_reconcile",
      rpc: "pandora_ops_reconcile_required_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_lease_id: leaseId,
        p_generation: generation,
        p_reason: reason,
      },
    };
  }

  if (input.action === "operations_external_success_reconcile") {
    const leaseId = requiredUuid(input, "leaseId");
    const generation = requiredInteger(input, "generation", 1, Number.MAX_SAFE_INTEGER);
    const receipt = isRecord(input.receipt) ? input.receipt : undefined;
    const taskId = receipt ? requiredString(receipt, "taskId") : undefined;
    const taskSpecDigest = receipt ? requiredString(receipt, "taskSpecDigest") : undefined;
    const repository = receipt ? requiredString(receipt, "repository") : undefined;
    const pullRequest = receipt ? requiredInteger(receipt, "pullRequest", 1, 2147483647) : undefined;
    const branch = receipt ? requiredString(receipt, "branch") : undefined;
    const observedHeadSha = receipt ? requiredString(receipt, "observedHeadSha") : undefined;
    const receiptRef = receipt ? requiredString(receipt, "ref") : undefined;
    if (!leaseId || generation === undefined || !taskId
      || !/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$/.test(taskId)
      || !taskSpecDigest || !/^[a-f0-9]{64}$/.test(taskSpecDigest)
      || !repository || ![
        "pandora-rvw-314296438-20260820/pandoras-box",
        "pandora-rvw-314296438-20260820/pandoras-box-memory",
      ].includes(repository)
      || pullRequest === undefined || !branch || branch.length > 240
      || !observedHeadSha || !/^[a-f0-9]{40}$/.test(observedHeadSha)
      || !receiptRef || receiptRef.length > 1000) return undefined;
    const release = OPERATIONS_NATIVE_WORKERS.release;
    return {
      action: "operations_external_success_reconcile",
      rpc: "pandora_ops_reconcile_external_success_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_lease_id: leaseId,
        p_generation: generation,
        p_reconciler_worker_key: release.workerKey,
        p_reconciler_principal_key: release.principalKey,
        p_receipt: {
          taskId,
          taskSpecDigest,
          repository,
          pullRequest,
          branch,
          observedHeadSha,
          ref: receiptRef,
        },
      },
    };
  }

  if (input.action === "operations_handoff") {
    const leaseId = requiredUuid(input, "leaseId");
    const generation = requiredInteger(input, "generation", 1, Number.MAX_SAFE_INTEGER);
    if (!leaseId || generation === undefined || !isRecord(input.handoff)) return undefined;
    const worker = OPERATIONS_NATIVE_WORKERS.builder;
    return {
      action: "operations_handoff",
      rpc: "pandora_ops_handoff_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_lease_id: leaseId,
        p_generation: generation,
        p_principal_key: worker.principalKey,
        p_handoff: input.handoff,
        p_actual_cost_micros: 0,
      },
    };
  }

  if (input.action === "operations_final_acceptance_readback") {
    return {
      action: "operations_final_acceptance_readback",
      rpc: "pandora_ops_final_acceptance_readback_v1",
      responseKey: "operations",
      params: { p_project_id: OPERATIONS_PROJECT_ID },
    };
  }

  if (input.action === "operations_verification_record") {
    const taskId = requiredString(input, "taskId");
    const generation = requiredInteger(input, "generation", 1, Number.MAX_SAFE_INTEGER);
    const status = requiredString(input, "status");
    if (!taskId || !OPERATIONS_NATIVE_GENERIC_VERIFY_TASKS.has(taskId)
      || generation === undefined || !["PASS", "FAIL", "BLOCKED"].includes(String(status))
      || !isRecord(input.evidence)) return undefined;
    const release = OPERATIONS_NATIVE_WORKERS.release;
    return {
      action: "operations_verification_record",
      rpc: "pandora_ops_record_verification_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_task_key: taskId,
        p_generation: generation,
        p_verifier_key: release.workerKey,
        p_principal_key: release.principalKey,
        p_status: status,
        p_evidence: input.evidence,
      },
    };
  }

  if (input.action === "operations_verification_accept") {
    const taskId = requiredString(input, "taskId");
    const generation = requiredInteger(input, "generation", 1, Number.MAX_SAFE_INTEGER);
    const verificationRunId = requiredUuid(input, "verificationRunId");
    if (!taskId || !OPERATIONS_NATIVE_GENERIC_VERIFY_TASKS.has(taskId)
      || generation === undefined || !verificationRunId || !isRecord(input.receipt)) return undefined;
    const release = OPERATIONS_NATIVE_WORKERS.release;
    return {
      action: "operations_verification_accept",
      rpc: "pandora_ops_verify_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_task_key: taskId,
        p_generation: generation,
        p_verifier_key: release.workerKey,
        p_principal_key: release.principalKey,
        p_verification_run_id: verificationRunId,
        p_receipt: input.receipt,
      },
    };
  }

  if (input.action === "operations_native_release_verify") {
    const taskId = requiredString(input, "taskId");
    if (taskId !== "OPS-CLOUD-CONNECTORS-RELEASE-V1") return undefined;
    const worker = OPERATIONS_NATIVE_WORKERS.release;
    return {
      action: "operations_native_release_verify",
      rpc: "pandora_ops_native_release_verify_v1",
      responseKey: "operations",
      params: {
        p_project_id: OPERATIONS_PROJECT_ID,
        p_task_key: taskId,
        p_verifier_key: worker.workerKey,
        p_principal_key: worker.principalKey,
      },
    };
  }

  if (input.action === "canonical_release_status") {
    const repository = requiredString(input, "repository");
    const sourceSha = requiredString(input, "sourceSha");
    if (
      repository !== "pandora-rvw-314296438-20260820/pandoras-box"
      || !sourceSha
      || !/^[0-9a-f]{40}$/.test(sourceSha)
    ) return undefined;
    return {
      action: "canonical_release_status",
      rpc: "get_canonical_release_status",
      responseKey: "releaseEvidence",
      params: {
        p_repository: repository,
        p_source_sha: sourceSha,
      },
    };
  }

  return undefined;
}

Deno.serve(async (request: Request) => {
  const geminiWorkerResponse = await handleGeminiWorkerRequest(request);
  if (geminiWorkerResponse) return geminiWorkerResponse;

  if (request.method !== "POST") return response(405, { ok: false, error: "method_not_allowed" });

  const token = bearerToken(request);
  if (!token) return response(401, { ok: false, error: "unauthorized" });

  try {
    await verifyVercelToken(token);
  } catch {
    return response(401, { ok: false, error: "unauthorized" });
  }

  const rawBody = await request.text();
  if (new TextEncoder().encode(rawBody).byteLength > MAX_REQUEST_BYTES) {
    return response(413, { ok: false, error: "request_too_large" });
  }

  let input: Record<string, unknown>;
  try {
    const parsed = JSON.parse(rawBody);
    if (!isRecord(parsed)) throw new Error("not an object");
    input = parsed;
  } catch {
    return response(400, { ok: false, error: "invalid_json" });
  }

  const route = routeForInput(input);
  if (!route) return response(400, { ok: false, error: "unsupported_or_invalid_action" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const key = serviceRoleKey();
  if (!supabaseUrl || !key) return response(503, { ok: false, error: "control_database_not_configured" });

  try {
    const payload = await fetchRpc(supabaseUrl, key, route.rpc, route.params);
    if (payload === undefined) return response(502, { ok: false, error: "control_operation_unavailable" });

    if (route.responseKey === "accounts") {
      if (!Array.isArray(payload)) return response(502, { ok: false, error: "control_operation_unavailable" });
      return response(200, { ok: true, accounts: payload });
    }

    if (
      route.responseKey === "checkpoint"
      || route.responseKey === "releaseEvidence"
    ) {
      if (payload !== null && (!payload || typeof payload !== "object" || Array.isArray(payload))) {
        return response(502, { ok: false, error: "control_operation_unavailable" });
      }
      return response(200, { ok: true, [route.responseKey]: payload });
    }

    if (route.responseKey === "supabaseReceipt" || route.responseKey === "vercelRehearsalReceipt") {
      if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
        return response(502, { ok: false, error: "control_operation_unavailable" });
      }
      return response(200, { ok: true, [route.responseKey]: payload });
    }

    if (route.responseKey === "operations") {
      return response(200, { ok: true, operations: payload });
    }

    if (route.responseKey === "events" || route.responseKey === "plans") {
      if (!Array.isArray(payload)) return response(502, { ok: false, error: "control_operation_unavailable" });
      return response(200, { ok: true, [route.responseKey]: payload });
    }

    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      return response(502, { ok: false, error: "control_operation_unavailable" });
    }

    return response(200, { ok: true, [route.responseKey]: payload });
  } catch {
    return response(502, { ok: false, error: "control_operation_unavailable" });
  }
});
