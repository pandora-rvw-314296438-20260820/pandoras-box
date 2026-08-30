import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_RE = /^[0-9a-f]{64}$/;
const MAX_BUNDLE_BYTES = 25 * 1024 * 1024;
const MAX_MOBILE_BYTES = 12 * 1024 * 1024;
const MAX_FILE_BYTES = 10 * 1024 * 1024;

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function text(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function serviceClient() {
  if (!SERVICE_ROLE) throw new Error("PREVIEW_CONTENT_NOT_CONFIGURED");
  return createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false, autoRefreshToken: false } });
}

async function sha256Hex(bytes: Uint8Array) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function canonicalBase64(value: unknown) {
  const source = text(value);
  if (!source || source.length % 4 !== 0 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(source)) throw new Error("ARTIFACT_FILE_BASE64_INVALID");
  let binary = "";
  try { binary = atob(source); } catch { throw new Error("ARTIFACT_FILE_BASE64_INVALID"); }
  if (binary.length > MAX_FILE_BYTES) throw new Error("ARTIFACT_FILE_TOO_LARGE");
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function safePath(value: unknown) {
  const path = text(value);
  if (!path || path.length > 512 || path.startsWith("/") || path.endsWith("/") || path.includes("\\") || path.includes("\0") || path.includes("?") || path.includes("#")) throw new Error("ARTIFACT_FILE_PATH_INVALID");
  const parts = path.split("/");
  if (parts.some((part) => !part || part === "." || part === ".." || part.length > 255)) throw new Error("ARTIFACT_FILE_PATH_INVALID");
  return path;
}

function mimeType(path: string) {
  const ext = path.toLowerCase().split(".").pop() || "";
  return ({
    html: "text/html", css: "text/css", js: "text/javascript", mjs: "text/javascript", json: "application/json",
    txt: "text/plain", xml: "application/xml", svg: "image/svg+xml", png: "image/png", jpg: "image/jpeg",
    jpeg: "image/jpeg", webp: "image/webp", gif: "image/gif", ico: "image/x-icon", woff: "font/woff",
    woff2: "font/woff2", ttf: "font/ttf", wasm: "application/wasm", pdf: "application/pdf",
  } as Record<string, string>)[ext] || "application/octet-stream";
}

function json(body: unknown, status = 200, requestId?: string) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store, max-age=0",
      "x-content-type-options": "nosniff",
      ...(requestId ? { "x-request-id": requestId } : {}),
    },
  });
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-methods": "POST, OPTIONS", "access-control-allow-headers": "authorization, apikey, content-type" } });
  if (req.method !== "POST") return json({ code: "METHOD_NOT_ALLOWED", plainMessage: "That preview action is not available.", requestId }, 405, requestId);
  try {
    const authorization = req.headers.get("authorization") || "";
    if (!/^Bearer\s+\S+$/i.test(authorization)) throw new Error("SIGN_IN_REQUIRED");
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) throw new Error("SIGN_IN_REQUIRED");

    let body: Record<string, unknown>;
    try { body = asRecord(await req.json()); } catch { throw new Error("INVALID_JSON"); }
    const projectId = text(body.projectId).toLowerCase();
    const versionId = text(body.versionId).toLowerCase();
    if (!UUID_RE.test(projectId) || !UUID_RE.test(versionId)) throw new Error("EXACT_VERSION_REQUIRED");

    const admin = serviceClient();
    const { data: project, error: projectError } = await admin.from("projectos_projects").select("id, organization_id").eq("id", projectId).maybeSingle();
    if (projectError || !project) throw new Error("PROJECT_NOT_FOUND");
    const organizationId = text(project.organization_id);
    const { data: membership, error: membershipError } = await admin.from("memberships")
      .select("organization_id, role, status")
      .eq("organization_id", organizationId)
      .eq("user_id", authData.user.id)
      .eq("status", "active")
      .in("role", ["owner", "admin"])
      .maybeSingle();
    if (membershipError || !membership) throw new Error("ORGANIZATION_ACCESS_REQUIRED");

    const { data: version, error: versionError } = await admin.from("pandora_project_versions")
      .select("id, organization_id, project_id, root_artifact_version_id, artifact_digest_sha256")
      .eq("id", versionId).eq("organization_id", organizationId).eq("project_id", projectId).maybeSingle();
    if (versionError || !version) throw new Error("EXACT_VERSION_REQUIRED");
    const rootArtifactVersionId = text(version.root_artifact_version_id);
    const artifactDigest = text(version.artifact_digest_sha256).toLowerCase();
    if (!UUID_RE.test(rootArtifactVersionId) || !SHA256_RE.test(artifactDigest)) throw new Error("ARTIFACT_LINEAGE_INCOMPLETE");

    const { data: artifactVersion, error: avError } = await admin.from("pandora_artifact_versions")
      .select("id, organization_id, project_id, artifact_id, content_sha256, byte_size, storage_provider, storage_bucket, storage_path")
      .eq("id", rootArtifactVersionId).eq("organization_id", organizationId).eq("project_id", projectId).maybeSingle();
    if (avError || !artifactVersion) throw new Error("ARTIFACT_NOT_FOUND");
    if (text(artifactVersion.content_sha256).toLowerCase() !== artifactDigest || text(artifactVersion.storage_provider) !== "supabase_storage") throw new Error("ARTIFACT_DIGEST_MISMATCH");

    const { data: artifact, error: artifactError } = await admin.from("pandora_artifacts")
      .select("id, organization_id, project_id, artifact_kind")
      .eq("id", artifactVersion.artifact_id).eq("organization_id", organizationId).eq("project_id", projectId).maybeSingle();
    if (artifactError || !artifact || !new Set(["build_output", "runtime_bundle"]).has(text(artifact.artifact_kind))) throw new Error("ARTIFACT_NOT_FOUND");

    const { data: blob, error: storageError } = await admin.storage.from(text(artifactVersion.storage_bucket)).download(text(artifactVersion.storage_path));
    if (storageError || !blob) throw new Error("ARTIFACT_STORAGE_READ_FAILED");
    const bundleBytes = new Uint8Array(await blob.arrayBuffer());
    const declaredSize = Number(artifactVersion.byte_size);
    if (!Number.isSafeInteger(declaredSize) || declaredSize < 1 || declaredSize > MAX_BUNDLE_BYTES || bundleBytes.byteLength !== declaredSize) throw new Error("ARTIFACT_BUNDLE_SIZE_INVALID");
    if (await sha256Hex(bundleBytes) !== artifactDigest) throw new Error("ARTIFACT_BUNDLE_DIGEST_MISMATCH");

    let bundle: Record<string, unknown>;
    try { bundle = asRecord(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bundleBytes))); } catch { throw new Error("ARTIFACT_BUNDLE_JSON_INVALID"); }
    if (bundle.kind !== "pandora.runtime-bundle.v1" || bundle.schemaVersion !== 1 || text(bundle.projectVersionId) !== versionId || !Array.isArray(bundle.files)) throw new Error("ARTIFACT_BUNDLE_SCHEMA_UNSUPPORTED");

    let totalBytes = 0;
    let hasIndex = false;
    const files: Array<Record<string, unknown>> = [];
    const seen = new Set<string>();
    let prior = "";
    for (const raw of bundle.files) {
      const entry = asRecord(raw);
      const file = safePath(entry.file);
      if (seen.has(file) || prior && prior.localeCompare(file, "en") >= 0) throw new Error("ARTIFACT_FILES_NOT_CANONICAL");
      seen.add(file); prior = file;
      if (file === "index.html") hasIndex = true;
      if (entry.encoding !== "base64") throw new Error("ARTIFACT_FILE_ENCODING_UNSUPPORTED");
      const fileBytes = canonicalBase64(entry.data);
      totalBytes += fileBytes.byteLength;
      if (totalBytes > MAX_MOBILE_BYTES) throw new Error("PREVIEW_BUNDLE_TOO_LARGE");
      const fileDigest = text(entry.sha256).toLowerCase();
      if (!SHA256_RE.test(fileDigest) || await sha256Hex(fileBytes) !== fileDigest || Number(entry.byteSize) !== fileBytes.byteLength) throw new Error("ARTIFACT_FILE_DIGEST_MISMATCH");
      files.push({ file, mimeType: mimeType(file), dataBase64: text(entry.data), byteSize: fileBytes.byteLength, sha256: fileDigest });
    }
    if (!hasIndex) throw new Error("ARTIFACT_ENTRYPOINT_MISSING");

    return json({ kind: "pandora.mobile-preview-bundle.v1", projectId, versionId, artifactDigest, totalBytes, files }, 200, requestId);
  } catch (error) {
    const code = error instanceof Error ? error.message : "PREVIEW_CONTENT_UNAVAILABLE";
    if (code === "SIGN_IN_REQUIRED") return json({ code, plainMessage: "Please sign in again.", requestId }, 401, requestId);
    if (code === "ORGANIZATION_ACCESS_REQUIRED") return json({ code, plainMessage: "You do not have permission for this project.", requestId }, 403, requestId);
    if (new Set(["INVALID_JSON", "EXACT_VERSION_REQUIRED"]).has(code)) return json({ code, plainMessage: "Pandora could not identify that exact preview.", requestId }, 400, requestId);
    if (code === "PROJECT_NOT_FOUND") return json({ code, plainMessage: "Pandora could not find that project.", requestId }, 404, requestId);
    if (code === "PREVIEW_BUNDLE_TOO_LARGE") return json({ code, plainMessage: "This preview is too large for the mobile renderer.", requestId }, 413, requestId);
    console.error(JSON.stringify({ requestId, code }));
    return json({ code: "PREVIEW_CONTENT_UNAVAILABLE", plainMessage: "Pandora could not load the exact preview content right now.", requestId }, 503, requestId);
  }
});