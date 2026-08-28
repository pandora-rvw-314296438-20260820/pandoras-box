import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const MAX_BODY_BYTES = 524288;
const SIGNATURE = /^[0-9a-f]{40}$/i;

type JsonRecord = Record<string, unknown>;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store, max-age=0",
      "x-content-type-options": "nosniff",
    },
  });
}

function adminClient() {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error("SERVICE_UNAVAILABLE");
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ accepted: false, code: "METHOD_NOT_ALLOWED" }, 405);
  const declared = Number(req.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) return json({ accepted: false, code: "BODY_TOO_LARGE" }, 413);
  const signature = req.headers.get("x-vercel-signature") || "";
  if (!SIGNATURE.test(signature)) return json({ accepted: false, code: "SIGNATURE_REQUIRED" }, 403);

  let rawBody = "";
  try {
    rawBody = await req.text();
  } catch {
    return json({ accepted: false, code: "BODY_INVALID" }, 400);
  }
  if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) return json({ accepted: false, code: "BODY_TOO_LARGE" }, 413);

  try {
    const admin = adminClient();
    const { data, error } = await admin.rpc("pandora_worker_f_ingest_vercel_webhook_20260829", {
      p_raw_body: rawBody,
      p_signature: signature,
    });
    if (error) {
      console.error(JSON.stringify({ code: "WEBHOOK_INGEST_UNAVAILABLE" }));
      return json({ accepted: false, code: "WEBHOOK_INGEST_UNAVAILABLE" }, 503);
    }
    const result = data && typeof data === "object" && !Array.isArray(data) ? data as JsonRecord : {};
    if (result.accepted !== true) return json({ accepted: false, code: "SIGNATURE_INVALID" }, 403);
    return json({ accepted: true, eventId: result.eventId ?? null, duplicate: result.duplicate === true, status: result.status ?? "received" }, 200);
  } catch {
    console.error(JSON.stringify({ code: "WEBHOOK_RUNTIME_UNAVAILABLE" }));
    return json({ accepted: false, code: "WEBHOOK_RUNTIME_UNAVAILABLE" }, 503);
  }
});
