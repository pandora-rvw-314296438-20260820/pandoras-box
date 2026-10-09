import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const MAX_BODY_BYTES = 131072;

const REQUIRED_HEADERS = [
  "paypal-auth-algo",
  "paypal-cert-url",
  "paypal-transmission-id",
  "paypal-transmission-sig",
  "paypal-transmission-time",
] as const;

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
  if (req.method !== "POST") {
    return json({ accepted: false, code: "METHOD_NOT_ALLOWED" }, 405);
  }

  const declared = Number(req.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    return json({ accepted: false, code: "BODY_TOO_LARGE" }, 413);
  }

  const headers: Record<string, string> = {};
  for (const name of REQUIRED_HEADERS) {
    const val = req.headers.get(name);
    if (!val || !val.trim()) {
      return json({ accepted: false, code: "SIGNATURE_HEADERS_REQUIRED" }, 400);
    }
    headers[name] = val.trim();
  }

  let rawBody = "";
  try {
    rawBody = await req.text();
  } catch {
    return json({ accepted: false, code: "BODY_INVALID" }, 400);
  }

  if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) {
    return json({ accepted: false, code: "BODY_TOO_LARGE" }, 413);
  }

  try {
    const admin = adminClient();
    const { data, error } = await admin.rpc("pandora_plp_paypal_webhook_ingest_v1", {
      p_headers: headers,
      p_raw_body: rawBody,
    });

    if (error) {
      console.error(JSON.stringify({ code: "WEBHOOK_INGEST_UNAVAILABLE" }));
      return json({ accepted: false, code: "WEBHOOK_INGEST_UNAVAILABLE" }, 503);
    }

    const result = data && typeof data === "object" && !Array.isArray(data) ? (data as JsonRecord) : {};
    const code = typeof result.code === "string" ? result.code : "";

    if (result.accepted === true) {
      return json({ accepted: true, duplicate: result.duplicate === true }, 200);
    }

    if (code === "SIGNATURE_INVALID") {
      return json({ accepted: false, code: "SIGNATURE_INVALID" }, 401);
    }

    if (code.startsWith("BODY_")) {
      return json({ accepted: false, code }, 400);
    }

    if (code === "PROCESSING_FAILED" || code === "VERIFY_UNAVAILABLE") {
      console.error(JSON.stringify({ code }));
      return json({ accepted: false, code }, 500);
    }

    console.error(JSON.stringify({ code: code || "INTERNAL_ERROR" }));
    return json({ accepted: false, code: code || "INTERNAL_ERROR" }, 500);
  } catch {
    console.error(JSON.stringify({ code: "WEBHOOK_RUNTIME_UNAVAILABLE" }));
    return json({ accepted: false, code: "WEBHOOK_RUNTIME_UNAVAILABLE" }, 503);
  }
});
