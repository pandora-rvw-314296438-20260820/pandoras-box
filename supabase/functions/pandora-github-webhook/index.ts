import "jsr:@supabase/functions-js@2.57.2/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const MAX_BODY_BYTES = 1_048_576;
const DELIVERY_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HEX_256 = /^[0-9a-f]{64}$/i;
const SHA40 = /^[0-9a-f]{40}$/i;
const TARGET_REPOSITORY = "pandora-rvw-314296438-20260820/pandoras-box";
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

const record = (value: unknown): Record<string, unknown> =>
  value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};

const text = (value: unknown) => typeof value === "string" ? value.trim() : "";

const hex = (bytes: ArrayBuffer) =>
  [...new Uint8Array(bytes)].map((value) => value.toString(16).padStart(2, "0")).join("");

const constantTimeEqual = (left: string, right: string) => {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let i = 0; i < left.length; i += 1) {
    difference |= left.charCodeAt(i) ^ right.charCodeAt(i);
  }
  return difference === 0;
};

Deno.serve(async (request: Request) => {
  if (request.method === "GET") {
    return json({
      ok: true,
      service: "pandora-github-webhook",
      status: "ready",
      ciRescueSchema: 2,
    });
  }
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (!Number.isFinite(contentLength) || contentLength > MAX_BODY_BYTES) {
    return json({ error: "payload_too_large" }, 413);
  }

  const deliveryId = request.headers.get("x-github-delivery") ?? "";
  const eventName = request.headers.get("x-github-event") ?? "";
  const signatureHeader = request.headers.get("x-hub-signature-256") ?? "";

  if (!DELIVERY_ID.test(deliveryId) || !eventName || !signatureHeader.startsWith("sha256=")) {
    return json({ error: "invalid_github_headers" }, 400);
  }

  const signature = signatureHeader.slice(7).toLowerCase();
  if (!HEX_256.test(signature)) return json({ error: "invalid_signature" }, 401);

  const raw = new Uint8Array(await request.arrayBuffer());
  if (raw.byteLength > MAX_BODY_BYTES) return json({ error: "payload_too_large" }, 413);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "service_unavailable" }, 503);

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: webhookSecret, error: secretError } =
    await supabase.rpc("pandora_get_github_webhook_secret");
  if (secretError || typeof webhookSecret !== "string" || webhookSecret.length < 32) {
    return json({ error: "service_unavailable" }, 503);
  }

  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(webhookSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const expected = hex(await crypto.subtle.sign("HMAC", key, raw));
  if (!constantTimeEqual(expected, signature)) return json({ error: "invalid_signature" }, 401);

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(new TextDecoder().decode(raw)) as Record<string, unknown>;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const repository = record(payload.repository);
  const sender = record(payload.sender);
  const installation = record(payload.installation);
  const repositoryFullName = text(repository.full_name);
  const payloadSha256 = hex(await crypto.subtle.digest("SHA-256", raw));

  const { data: inserted, error: recordError } = await supabase.rpc(
    "pandora_record_github_webhook_delivery",
    {
      p_delivery_id: deliveryId,
      p_event_name: eventName,
      p_action_name: typeof payload.action === "string" ? payload.action : null,
      p_repository_full_name: repositoryFullName || null,
      p_sender_login: typeof sender.login === "string" ? sender.login : null,
      p_installation_id:
        typeof installation.id === "number" && Number.isSafeInteger(installation.id)
          ? installation.id
          : null,
      p_payload_sha256: payloadSha256,
    },
  );
  if (recordError) return json({ error: "delivery_record_failed" }, 500);

  if (inserted !== true) {
    return json({ ok: true, accepted: false, duplicate: true, delivery_id: deliveryId, event: eventName });
  }

  let rescue: unknown = null;
  if (
    repositoryFullName === TARGET_REPOSITORY &&
    eventName === "workflow_run" &&
    payload.action === "completed"
  ) {
    const run = record(payload.workflow_run);
    const conclusion = text(run.conclusion).toLowerCase();
    const branch = text(run.head_branch);
    const headSha = text(run.head_sha).toLowerCase();
    const workflowName = text(run.name).slice(0, 200);
    const runId = typeof run.id === "number" && Number.isSafeInteger(run.id) ? run.id : null;
    const runAttempt =
      typeof run.run_attempt === "number" && Number.isSafeInteger(run.run_attempt)
        ? run.run_attempt
        : null;
    const pulls = Array.isArray(run.pull_requests) ? run.pull_requests : [];
    const firstPr = pulls.length ? record(pulls[0]) : {};
    const prNumber =
      typeof firstPr.number === "number" && Number.isSafeInteger(firstPr.number)
        ? firstPr.number
        : null;

    if (
      ["failure", "timed_out", "action_required"].includes(conclusion) &&
      branch &&
      branch !== "main" &&
      SHA40.test(headSha) &&
      runId !== null
    ) {
      const { data, error } = await supabase.rpc("pandora_ci_rescue_enqueue_v2", {
        p_delivery_id: deliveryId,
        p_repository: TARGET_REPOSITORY,
        p_branch: branch,
        p_head_sha: headSha,
        p_workflow_run_id: runId,
        p_workflow_name: workflowName,
        p_pr_number: prNumber,
        p_evidence: {
          conclusion,
          runAttempt,
          workflowUrl: text(run.html_url).slice(0, 1000),
          receivedAt: new Date().toISOString(),
        },
      });
      if (error) return json({ error: "ci_rescue_enqueue_failed" }, 500);
      rescue = data;
    }
  }

  return json({
    ok: true,
    accepted: true,
    duplicate: false,
    delivery_id: deliveryId,
    event: eventName,
    rescue,
  });
});
