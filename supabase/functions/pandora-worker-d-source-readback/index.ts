import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const BUCKET = "pandora-build-artifacts";
const MAX_SOURCE_BYTES = 25 * 1024 * 1024;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256 = /^[0-9a-f]{64}$/;
const SECRET = /(?:AIza[0-9A-Za-z_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|(?:api[_-]?key|secret|password|authorization)\s*[:=]\s*["'][^"']{12,}["'])/i;

type JsonRecord = Record<string, unknown>;

function rec(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}
function text(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}
function exactKeys(value: JsonRecord, expected: string[]) {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return actual.length === wanted.length && actual.every((key, index) => key === wanted[index]);
}
function response(body: unknown, status = 200) {
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
async function sha256Bytes(bytes: Uint8Array) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return response({ ok: false, state: "rejected" }, 405);
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) return response({ ok: false, state: "unavailable" }, 503);

  const admin = adminClient();
  const internalKey = req.headers.get("x-pandora-worker-d-key")?.trim() || "";
  const validated = await admin.rpc("pandora_validate_worker_d_readback_key_20260905", { p_token: internalKey });
  if (validated.error || validated.data !== true) return response({ ok: false, state: "rejected" }, 401);

  try {
    const raw = await req.text();
    if (new TextEncoder().encode(raw).byteLength > 1024) throw new Error("INVALID_REQUEST");
    let parsed: unknown;
    try { parsed = JSON.parse(raw); } catch { throw new Error("INVALID_REQUEST"); }
    const body = rec(parsed);
    const buildJobId = text(body.buildJobId);
    if (!exactKeys(body, ["buildJobId"]) || !UUID.test(buildJobId)) throw new Error("INVALID_REQUEST");

    const job = await admin.from("pandora_build_jobs")
      .select("id,organization_id,project_id,project_spec_id,target_project_version_id,status,worker_identity,lease_owner,lease_token_sha256,lease_expires_at")
      .eq("id", buildJobId).maybeSingle();
    if (job.error || !job.data) throw new Error("BUILD_JOB_NOT_FOUND");
    const j = job.data;
    if (!["claimed", "running"].includes(String(j.status)) ||
        j.worker_identity !== "pandora-worker-d-static-web" ||
        j.lease_owner !== "pandora-worker-d-static-web" ||
        !SHA256.test(text(j.lease_token_sha256)) ||
        !j.lease_expires_at || Date.parse(String(j.lease_expires_at)) <= Date.now() ||
        !UUID.test(text(j.target_project_version_id))) {
      throw new Error("BUILD_LEASE_INVALID");
    }

    const version = await admin.from("pandora_project_versions")
      .select("id,organization_id,project_id,project_spec_id,build_job_id,lifecycle_status,source_kind,source_ref,source_commit,root_artifact_version_id,source_sha256,source_payload")
      .eq("id", j.target_project_version_id)
      .eq("organization_id", j.organization_id)
      .eq("project_id", j.project_id)
      .eq("project_spec_id", j.project_spec_id)
      .eq("build_job_id", j.id)
      .maybeSingle();
    if (version.error || !version.data) throw new Error("BUILD_VERSION_INVALID");
    const v = version.data;
    const payload = rec(v.source_payload);
    if (v.lifecycle_status !== "draft" || v.source_kind !== "artifact_snapshot" ||
        v.source_ref !== v.id || v.source_commit !== null ||
        text(payload.buildAdapter) !== "static-web" || !UUID.test(text(v.root_artifact_version_id)) ||
        !SHA256.test(text(v.source_sha256))) {
      throw new Error("BUILD_VERSION_INVALID");
    }

    const artifactVersion = await admin.from("pandora_artifact_versions")
      .select("id,artifact_id,organization_id,project_id,content_sha256,byte_size,storage_provider,storage_bucket,storage_path")
      .eq("id", v.root_artifact_version_id)
      .eq("organization_id", j.organization_id)
      .eq("project_id", j.project_id)
      .maybeSingle();
    if (artifactVersion.error || !artifactVersion.data) throw new Error("SOURCE_ARTIFACT_INVALID");
    const av = artifactVersion.data;
    if (av.content_sha256 !== v.source_sha256 || av.storage_provider !== "supabase_storage" ||
        av.storage_bucket !== BUCKET || !text(av.storage_path) ||
        Number(av.byte_size) <= 0 || Number(av.byte_size) > MAX_SOURCE_BYTES ||
        !SHA256.test(text(av.content_sha256)) || !UUID.test(text(av.artifact_id))) {
      throw new Error("SOURCE_ARTIFACT_INVALID");
    }

    const artifact = await admin.from("pandora_artifacts")
      .select("id,organization_id,project_id,artifact_kind")
      .eq("id", av.artifact_id)
      .eq("organization_id", j.organization_id)
      .eq("project_id", j.project_id)
      .maybeSingle();
    if (artifact.error || !artifact.data || artifact.data.artifact_kind !== "source_snapshot") {
      throw new Error("SOURCE_ARTIFACT_INVALID");
    }

    const downloaded = await admin.storage.from(BUCKET).download(String(av.storage_path));
    if (downloaded.error || !downloaded.data) throw new Error("SOURCE_READBACK_FAILED");
    const bytes = new Uint8Array(await downloaded.data.arrayBuffer());
    if (bytes.byteLength !== Number(av.byte_size) || await sha256Bytes(bytes) !== av.content_sha256) {
      throw new Error("SOURCE_READBACK_MISMATCH");
    }
    let sourceText = "";
    try { sourceText = new TextDecoder("utf-8", { fatal: true }).decode(bytes); } catch { throw new Error("SOURCE_READBACK_INVALID"); }
    if (!sourceText || SECRET.test(sourceText)) throw new Error("SOURCE_READBACK_UNSAFE");

    return response({ ok: true, state: "source_ready", buildJobId: j.id, projectVersionId: v.id,
      artifactVersionId: av.id, sha256: av.content_sha256, byteSize: Number(av.byte_size), sourceText });
  } catch (error) {
    const code = error instanceof Error ? error.message : "SOURCE_READBACK_FAILED";
    const status = code === "INVALID_REQUEST" ? 400 : code === "BUILD_JOB_NOT_FOUND" ? 404 :
      code === "BUILD_LEASE_INVALID" ? 409 : 503;
    return response({ ok: false, state: "failed", error: { code: code.slice(0, 120) } }, status);
  }
});
