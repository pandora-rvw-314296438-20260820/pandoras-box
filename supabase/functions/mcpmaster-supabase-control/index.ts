import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createRemoteJWKSet, decodeJwt, jwtVerify } from "npm:jose@5.10.0";
import { routeForCanonicalReleaseCapture } from "./canonical-release-capture-routes.mjs";
import { assertProductionVercelClaims } from "./identity-policy.mjs";

const CONTROL_ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const MAX_REQUEST_BYTES = 256_000;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type ControlRpc =
  | "get_supabase_control_accounts"
  | "get_github_control_accounts"
  | "get_runtime_security_config"
  | "create_execution_plan"
  | "approve_execution_plan"
  | "claim_execution_plan"
  | "finish_execution_plan"
  | "list_execution_plans"
  | "list_execution_audit"
  | "verify_execution_audit_chain"
  | "save_projectos_checkpoint"
  | "get_projectos_checkpoint"
  | "list_projectos_events"
  | "verify_projectos_event_chain"
  | "consume_runtime_rate_limit"
  | "get_canonical_release_status"
  | "capture_canonical_supabase_release_receipt"
  | "capture_canonical_vercel_rehearsal_receipt";

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
  | "projectos_checkpoint_save"
  | "projectos_checkpoint_get"
  | "projectos_event_list"
  | "projectos_event_verify"
  | "runtime_rate_limit_consume"
  | "canonical_release_status"
  | "canonical_supabase_receipt_capture"
  | "canonical_vercel_rehearsal_capture";

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
    | "vercelRehearsalReceipt";
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
    const intakeId = requiredUuid(input, "intakeId");
    const tool = requiredString(input, "tool");
    const risk = requiredString(input, "risk");
    const payloadHash = requiredString(input, "payloadHash");
    const expiresAt = requiredString(input, "expiresAt");
    if (!requestId || !intakeId || !tool || !risk || !payloadHash || !expiresAt || !isRecord(input.args)) {
      return undefined;
    }
    return {
      action: "execution_plan_create",
      rpc: "create_execution_plan",
      responseKey: "plan",
      params: {
        p_request_id: requestId,
        p_intake_id: intakeId,
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
      rpc: "approve_execution_plan",
      responseKey: "plan",
      params: { p_plan_id: planId, p_approved_by: approvedBy },
    };
  }

  if (input.action === "execution_plan_claim") {
    const planId = requiredUuid(input, "planId");
    if (!planId) return undefined;
    return {
      action: "execution_plan_claim",
      rpc: "claim_execution_plan",
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
      rpc: "finish_execution_plan",
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

  if (input.action === "projectos_checkpoint_save") {
    const projectKey = requiredString(input, "projectKey");
    const expectedVersion = requiredInteger(input, "expectedVersion", 0, Number.MAX_SAFE_INTEGER);
    const status = requiredString(input, "status");
    const sourceRepository = requiredString(input, "sourceRepository");
    const sourceCommitSha = requiredString(input, "sourceCommitSha");
    const planVersion = requiredString(input, "planVersion");
    const observedAt = requiredString(input, "observedAt");
    const phaseKey = typeof input.phaseKey === "string" && input.phaseKey.length <= 160 ? input.phaseKey : null;
    const primaryTaskKey = typeof input.primaryTaskKey === "string" && input.primaryTaskKey.length <= 160
      ? input.primaryTaskKey
      : null;
    const eventType = typeof input.eventType === "string" ? input.eventType : "projectos.checkpoint.saved";
    const runId = typeof input.runId === "string" ? input.runId : null;
    const stepId = typeof input.stepId === "string" ? input.stepId : null;
    if (
      !projectKey
      || expectedVersion === undefined
      || !status
      || !sourceRepository
      || !sourceCommitSha
      || !planVersion
      || !observedAt
      || !isRecord(input.state)
      || !/^[a-zA-Z0-9][a-zA-Z0-9._/-]{0,159}$/.test(projectKey)
      || !["active", "blocked", "paused", "complete", "archived"].includes(status)
      || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(sourceRepository)
      || !/^[0-9a-f]{40}$/.test(sourceCommitSha)
      || !/^projectos\.[a-z0-9_.-]{1,127}$/.test(eventType)
    ) return undefined;
    return {
      action: "projectos_checkpoint_save",
      rpc: "save_projectos_checkpoint",
      responseKey: "checkpoint",
      params: {
        p_project_key: projectKey,
        p_expected_version: expectedVersion,
        p_status: status,
        p_phase_key: phaseKey,
        p_primary_task_key: primaryTaskKey,
        p_source_repository: sourceRepository,
        p_source_commit_sha: sourceCommitSha,
        p_plan_version: planVersion,
        p_state_redacted: input.state,
        p_observed_at: observedAt,
        p_event_type: eventType,
        p_run_id: runId,
        p_step_id: stepId,
      },
    };
  }

  if (input.action === "projectos_checkpoint_get") {
    const projectKey = requiredString(input, "projectKey");
    if (!projectKey || !/^[a-zA-Z0-9][a-zA-Z0-9._/-]{0,159}$/.test(projectKey)) return undefined;
    return {
      action: "projectos_checkpoint_get",
      rpc: "get_projectos_checkpoint",
      responseKey: "checkpoint",
      params: { p_project_key: projectKey },
    };
  }

  if (input.action === "projectos_event_list") {
    const projectKey = requiredString(input, "projectKey");
    if (!projectKey || !/^[a-zA-Z0-9][a-zA-Z0-9._/-]{0,159}$/.test(projectKey)) return undefined;
    return {
      action: "projectos_event_list",
      rpc: "list_projectos_events",
      responseKey: "events",
      params: {
        p_project_key: projectKey,
        p_limit: typeof input.limit === "number" ? Math.min(Math.max(Math.floor(input.limit), 1), 500) : 100,
      },
    };
  }

  if (input.action === "projectos_event_verify") {
    const projectKey = requiredString(input, "projectKey");
    if (!projectKey || !/^[a-zA-Z0-9][a-zA-Z0-9._/-]{0,159}$/.test(projectKey)) return undefined;
    return {
      action: "projectos_event_verify",
      rpc: "verify_projectos_event_chain",
      responseKey: "verification",
      params: { p_project_key: projectKey },
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

  if (input.action === "canonical_release_status") {
    const repository = requiredString(input, "repository");
    const sourceSha = requiredString(input, "sourceSha");
    if (
      repository !== "banataosystems/Pandoras-box"
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
