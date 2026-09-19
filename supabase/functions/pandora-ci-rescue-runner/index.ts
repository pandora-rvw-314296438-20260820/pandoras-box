import "jsr:@supabase/functions-js@2.57.2/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const CLAIMANT = "supabase:pandora-ci-rescue-runner";
const encoder = new TextEncoder();

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });

const asRecord = (value: unknown): Record<string, unknown> =>
  value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};

const integer = (value: unknown) =>
  typeof value === "number" && Number.isSafeInteger(value) ? value : null;

const text = (value: unknown) => typeof value === "string" ? value.trim() : "";

async function hmac(secret: string, payload: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(payload)));
  return [...sig].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "service_unavailable" }, 503);

  const internalKey = request.headers.get("x-pandora-internal-key") ?? "";
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: authorized, error: authError } = await supabase.rpc(
    "pandora_ci_rescue_internal_auth_v1",
    { p_presented: internalKey },
  );
  if (authError || authorized !== true) return json({ error: "unauthorized" }, 401);

  let limit = 2;
  try {
    const body = asRecord(await request.json());
    const requested = integer(body.limit);
    if (requested !== null) limit = Math.max(1, Math.min(4, requested));
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const { data: configRaw, error: configError } = await supabase.rpc(
    "pandora_ci_rescue_agent_config_v2",
  );
  const config = asRecord(configRaw);
  const agentUrl = text(config.url);
  const agentSecret = text(config.secret);
  if (
    configError ||
    config.configured !== true ||
    !agentUrl.startsWith("https://") ||
    agentSecret.length < 32
  ) {
    return json({ ok: false, claimed: 0, error: "agent_unconfigured" }, 503);
  }

  const { data: jobsRaw, error: claimError } = await supabase.rpc(
    "pandora_ci_rescue_claim_v2",
    { p_claimed_by: CLAIMANT, p_limit: limit },
  );
  if (claimError) return json({ error: "claim_failed" }, 500);

  const jobs = Array.isArray(jobsRaw) ? jobsRaw : [];
  const results: unknown[] = [];

  for (const rawJob of jobs) {
    const job = asRecord(rawJob);
    const id = text(job.id);
    const leaseToken = text(job.leaseToken);
    const claimGeneration = integer(job.claimGeneration);
    if (!id || !leaseToken || claimGeneration === null) {
      results.push({ id: id || null, ok: false, error: "invalid_claim" });
      continue;
    }

    const payload = {
      event: "ci_failed",
      repository: text(job.repository),
      branch: text(job.branch),
      sha: text(job.currentFailingSha),
      pr: integer(job.prNumber),
      workflow_run_id: integer(job.workflowRunId),
      workflow: text(job.workflowName),
      job: "pending",
      run_attempt: integer(asRecord(job.evidence).runAttempt),
      rescue_id: id,
      claim_generation: claimGeneration,
      source_attempt_count: integer(job.sourceAttemptCount) ?? 0,
      transient_retry_count: integer(job.transientRetryCount) ?? 0,
    };
    const bodyText = JSON.stringify(payload);
    const signature = await hmac(agentSecret, bodyText);

    let agentStatus = 0;
    let agentBody: Record<string, unknown> = {};
    try {
      const response = await fetch(agentUrl, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-pandora-signature": "sha256=" + signature,
          "x-pandora-rescue-id": id,
        },
        body: bodyText,
        redirect: "error",
        signal: AbortSignal.timeout(110_000),
      });
      agentStatus = response.status;
      const responseText = await response.text();
      if (responseText.length > 1_048_576) throw new Error("response_too_large");
      try {
        agentBody = asRecord(responseText ? JSON.parse(responseText) : {});
      } catch {
        agentBody = {};
      }
    } catch {
      agentStatus = 0;
      agentBody = {};
    }

    const finalStatus = text(agentBody.status);
    const allowed = new Set([
      "retrying",
      "analyzing",
      "repairing",
      "verifying",
      "completed",
      "superseded",
      "blocked",
      "failed",
    ]);

    const patch = asRecord(agentBody.patch);
    let transitionStatus = finalStatus;
    let transitionPatch: Record<string, unknown> = patch;

    if (agentStatus < 200 || agentStatus >= 300) {
      transitionStatus = "blocked";
      transitionPatch = {
        lastErrorCode: agentStatus ? "AGENT_HTTP_" + String(agentStatus) : "AGENT_DISPATCH_FAILED",
        evidence: { agentHttpStatus: agentStatus || null },
      };
    } else if (!allowed.has(finalStatus)) {
      transitionStatus = "blocked";
      transitionPatch = {
        lastErrorCode: "AGENT_RESPONSE_INVALID",
        evidence: { agentHttpStatus: agentStatus },
      };
    }

    const { data: transitioned, error: transitionError } = await supabase.rpc(
      "pandora_ci_rescue_transition_v2",
      {
        p_id: id,
        p_claimed_by: CLAIMANT,
        p_claim_generation: claimGeneration,
        p_lease_token: leaseToken,
        p_status: transitionStatus,
        p_patch: transitionPatch,
      },
    );

    if (transitionError) {
      results.push({ id, ok: false, error: "transition_rejected" });
      continue;
    }

    results.push({ id, ok: true, result: transitioned });
  }

  return json({ ok: true, claimed: jobs.length, results });
});
