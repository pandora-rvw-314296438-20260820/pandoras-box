import { createClient } from "jsr:@supabase/supabase-js@2.57.2";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@5.10.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ISSUER = "https://oidc.vercel.com/mbanatao";
const AUDIENCE = "https://vercel.com/mbanatao";
const SUBJECT = "owner:mbanatao:project:enterprise:environment:production";
const JWKS = createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks`));
const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

async function authorize(req: Request) {
  const header = req.headers.get("authorization") || "";
  if (!header.startsWith("Bearer ")) return false;
  const token = header.slice(7).trim();
  if (!token) return false;
  try {
    const { payload } = await jwtVerify(token, JWKS, {
      issuer: ISSUER,
      audience: AUDIENCE,
      subject: SUBJECT,
      clockTolerance: 30,
    });
    return payload.iss === ISSUER && payload.sub === SUBJECT;
  } catch {
    return false;
  }
}

function uuid(value: unknown) {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
    ? value
    : null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);
  if (!(await authorize(req))) return json({ ok: false, error: "unauthorized" }, 401);

  const raw = await req.text();
  if (new TextEncoder().encode(raw).byteLength > 16 * 1024) {
    return json({ ok: false, error: "body_too_large" }, 413);
  }

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw || "{}");
  } catch {
    return json({ ok: false, error: "invalid_json" }, 400);
  }

  const action = body.action;
  if (action === "claim") {
    const requested = Number(body.limit ?? 5);
    const limit = Number.isInteger(requested) && requested >= 1 && requested <= 20 ? requested : 5;
    const { data, error } = await admin.rpc("pandora_claim_verified_learning_outbox", {
      p_limit: limit,
    });
    if (error) return json({ ok: false, error: "claim_failed" }, 500);
    return json({ ok: true, items: Array.isArray(data) ? data : [] });
  }

  if (action === "ack") {
    const id = uuid(body.outboxId);
    if (!id || typeof body.success !== "boolean") {
      return json({ ok: false, error: "invalid_ack" }, 400);
    }
    const candidateId = body.candidateId == null ? null : uuid(body.candidateId);
    const reviewItemId = body.reviewItemId == null ? null : uuid(body.reviewItemId);
    if ((body.candidateId != null && !candidateId) || (body.reviewItemId != null && !reviewItemId)) {
      return json({ ok: false, error: "invalid_ack" }, 400);
    }
    const { data, error } = await admin.rpc("pandora_ack_verified_learning_outbox", {
      p_outbox_id: id,
      p_success: body.success,
      p_candidate_id: candidateId,
      p_review_item_id: reviewItemId,
      p_retryable: body.retryable === true,
      p_error_code: typeof body.errorCode === "string" ? body.errorCode.slice(0, 120) : null,
    });
    if (error) return json({ ok: false, error: "ack_failed" }, 500);
    return json({ ok: true, result: data });
  }

  return json({ ok: false, error: "unsupported_action" }, 400);
});
