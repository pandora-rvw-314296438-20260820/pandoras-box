// Reuses a retired one-shot Edge Function slot because this Supabase project
// is at its function-count cap. The deployed code is the PLP learning outbox.
const OUTBOX_URL =
  "https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-pr181-supersede-close-20260831";
const MEMORY_GATEWAY_URL =
  "https://ivmvufhcsezyhczzondn.supabase.co/functions/v1/pandora-machine-gateway";

export const config = { maxDuration: 55 };

function json(response: any, status: number, body: unknown) {
  response.setHeader("Cache-Control", "private, no-store, max-age=0");
  return response.status(status).json(body);
}

async function postJson(url: string, headers: Record<string, string>, body: unknown) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json", ...headers },
      body: JSON.stringify(body),
      redirect: "error",
      cache: "no-store",
      signal: controller.signal,
    });
    const text = await response.text();
    let parsed: any = null;
    try { parsed = text ? JSON.parse(text) : null; } catch { parsed = null; }
    return { status: response.status, ok: response.ok, body: parsed };
  } finally {
    clearTimeout(timer);
  }
}

function memoryArgs(item: any) {
  return {
    namespace: item.namespace,
    projectId: item.memory_project_id,
    execution: item.execution,
    learningKind: item.learning_kind,
    learningSummary: item.learning_summary,
    promotionBasis: item.promotion_basis,
    confidence: Number(item.confidence),
    incidentVerificationRef: item.incident_verification_ref ?? null,
    additionalEvidenceRefs: Array.isArray(item.additional_evidence_refs) ? item.additional_evidence_refs : [],
  };
}

export default async function handler(request: any, response: any) {
  if (request.method !== "GET" && request.method !== "POST") {
    return json(response, 405, { ok: false, error: "method_not_allowed" });
  }
  const cronSecret = process.env.CRON_SECRET;
  const authorization = String(request.headers?.authorization || "");
  if (!cronSecret || authorization !== `Bearer ${cronSecret}`) {
    return json(response, 401, { ok: false, error: "unauthorized" });
  }
  const oidcToken = process.env.VERCEL_OIDC_TOKEN?.trim();
  if (!oidcToken) {
    return json(response, 503, { ok: false, error: "workload_identity_unavailable" });
  }

  const claim = await postJson(OUTBOX_URL, { authorization: `Bearer ${oidcToken}` }, { action: "claim", limit: 5 });
  if (!claim.ok || claim.body?.ok !== true || !Array.isArray(claim.body.items)) {
    return json(response, 502, { ok: false, error: "outbox_claim_failed" });
  }

  let accepted = 0;
  let retrying = 0;
  let failed = 0;
  for (const item of claim.body.items) {
    let success = false;
    let retryable = false;
    let candidateId: string | null = null;
    let reviewItemId: string | null = null;
    let errorCode = "memory_delivery_failed";
    try {
      const delivered = await postJson(MEMORY_GATEWAY_URL, { "x-pandora-workload-oidc": oidcToken }, {
        jsonrpc: "2.0",
        id: item.id,
        method: "tools/call",
        params: { name: "memory_verified_learning_propose", arguments: memoryArgs(item) },
      });
      if (delivered.ok && delivered.body?.result?.content?.[0]?.text) {
        let envelope: any = null;
        try { envelope = JSON.parse(delivered.body.result.content[0].text); } catch { envelope = null; }
        const learning = envelope?.learning;
        if (envelope?.ok === true && learning?.candidateId && learning?.reviewItemId) {
          success = true;
          candidateId = learning.candidateId;
          reviewItemId = learning.reviewItemId;
          errorCode = "";
        } else {
          errorCode = "memory_response_contract_error";
        }
      } else {
        const rpcCode = Number(delivered.body?.error?.code);
        errorCode = typeof delivered.body?.error?.message === "string"
          ? delivered.body.error.message.slice(0, 120)
          : `memory_http_${delivered.status}`;
        retryable = delivered.status === 408 || delivered.status === 429 || delivered.status >= 500 || rpcCode === -32603;
      }
    } catch (error) {
      retryable = true;
      errorCode = error instanceof Error && error.name === "AbortError" ? "memory_timeout" : "memory_transport_error";
    }

    const ack = await postJson(OUTBOX_URL, { authorization: `Bearer ${oidcToken}` }, {
      action: "ack",
      outboxId: item.id,
      success,
      candidateId,
      reviewItemId,
      retryable,
      errorCode,
    });
    if (!ack.ok || ack.body?.ok !== true) { failed += 1; continue; }
    if (success) accepted += 1;
    else if (retryable) retrying += 1;
    else failed += 1;
  }

  return json(response, 200, { ok: true, claimed: claim.body.items.length, accepted, retrying, failed });
}
