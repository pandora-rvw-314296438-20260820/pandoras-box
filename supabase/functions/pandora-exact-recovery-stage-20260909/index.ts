import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

const SOURCE_SHA = "c6fb492c23aa0766effc931889bef2ac1a431cb4";
const WORKFLOW_RUN_ID = "34318992007";
const SOURCE_URL =
  "https://raw.githubusercontent.com/pandora-rvw-314296438-20260820/pandoras-box/5efa848941be1c5f575f906254277a5f1b440036/recovery/exact-bundles/c6fb492c23aa0766effc931889bef2ac1a431cb4/34318992007/pandoras-box.bundle.b64";
const EXPECTED_SHA256 = "c9b8272b3c12d1baecec75eaa55d6e2bbdbdc3a1e9cf5210555a3a4690257337";
const EXPECTED_BYTES = 7_876_284;
const MAX_ENCODED_BYTES = 11_000_000;
const BUCKET = "pandora-recovery";
const OBJECT_PATH =
  "operational/pandoras-box-c6fb492c23aa0766effc931889bef2ac1a431cb4-34318992007.bundle";

const headers = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
};

const respond = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers });

const sha256 = async (bytes: Uint8Array): Promise<string> => {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
};

const decodeBundle = (encoded: string): Uint8Array => {
  const normalized = encoded.replace(/\s+/g, "");
  if (
    !normalized ||
    normalized.length % 4 !== 0 ||
    !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(normalized)
  ) {
    throw new Error("RECOVERY_BUNDLE_BASE64_INVALID");
  }
  let binary = "";
  try {
    binary = atob(normalized);
  } catch {
    throw new Error("RECOVERY_BUNDLE_BASE64_INVALID");
  }
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
};

const verifyBundle = async (bytes: Uint8Array) => {
  if (bytes.byteLength !== EXPECTED_BYTES) {
    throw new Error("RECOVERY_BUNDLE_SIZE_MISMATCH");
  }
  const digest = await sha256(bytes);
  if (digest !== EXPECTED_SHA256) {
    throw new Error("RECOVERY_BUNDLE_DIGEST_MISMATCH");
  }
  return digest;
};

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return respond({ ok: false, state: "rejected" }, 405);
  }
  if (!SUPABASE_URL || !SERVICE_ROLE) {
    return respond({ ok: false, state: "unavailable" }, 503);
  }

  const internalKey = request.headers.get("x-pandora-internal-key")?.trim() || "";
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const validation = await admin.rpc("pandora_validate_source_worker_key_20260831", {
    p_token: internalKey,
  });
  if (validation.error || validation.data !== true) {
    return respond({ ok: false, state: "rejected" }, 401);
  }

  try {
    const source = await fetch(SOURCE_URL, {
      method: "GET",
      headers: {
        accept: "text/plain",
        "cache-control": "no-store",
        "user-agent": "Pandora-Exact-Recovery-Stage/1.0",
      },
      redirect: "error",
    });
    if (!source.ok) {
      return respond({ ok: false, state: "source_unavailable", sourceStatus: source.status }, 502);
    }
    const declaredLength = Number(source.headers.get("content-length") || "0");
    if (Number.isFinite(declaredLength) && declaredLength > MAX_ENCODED_BYTES) {
      return respond({ ok: false, state: "source_oversized" }, 413);
    }
    const encoded = await source.text();
    if (new TextEncoder().encode(encoded).byteLength > MAX_ENCODED_BYTES) {
      return respond({ ok: false, state: "source_oversized" }, 413);
    }

    const bytes = decodeBundle(encoded);
    await verifyBundle(bytes);

    const filename = OBJECT_PATH.split("/").pop() || "";
    const directory = OBJECT_PATH.slice(0, -(filename.length + 1));
    const listed = await admin.storage.from(BUCKET).list(directory, {
      limit: 100,
      search: filename,
    });
    if (listed.error) {
      return respond({ ok: false, state: "storage_list_failed" }, 502);
    }
    const exists = (listed.data || []).some((item) => item.name === filename);

    if (!exists) {
      const uploaded = await admin.storage.from(BUCKET).upload(OBJECT_PATH, bytes, {
        contentType: "application/octet-stream",
        cacheControl: "0",
        upsert: false,
      });
      if (uploaded.error) {
        return respond({ ok: false, state: "storage_upload_failed" }, 502);
      }
    }

    const readback = await admin.storage.from(BUCKET).download(OBJECT_PATH);
    if (readback.error || !readback.data) {
      return respond({ ok: false, state: "storage_readback_failed" }, 502);
    }
    const storedBytes = new Uint8Array(await readback.data.arrayBuffer());
    const readbackDigest = await verifyBundle(storedBytes);

    return respond({
      ok: true,
      state: exists ? "existing_verified" : "uploaded_verified",
      storageProvider: "supabase_storage",
      storageBucket: BUCKET,
      storagePath: OBJECT_PATH,
      sourceSha: SOURCE_SHA,
      workflowRunId: WORKFLOW_RUN_ID,
      byteSize: storedBytes.byteLength,
      sha256: readbackDigest,
      sourcePinned: true,
      readbackVerified: true,
    });
  } catch (error) {
    const code = error instanceof Error ? error.message : "RECOVERY_STAGE_FAILED";
    if (code.startsWith("RECOVERY_BUNDLE_")) {
      return respond({ ok: false, state: "verification_failed", code }, 409);
    }
    return respond({ ok: false, state: "failed", code: "RECOVERY_STAGE_FAILED" }, 500);
  }
});
