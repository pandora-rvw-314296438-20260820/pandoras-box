
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_RE = /^[0-9a-f]{64}$/;
const MAX_BUNDLE_BYTES = 25 * 1024 * 1024;
const MAX_SOURCE_BYTES = 12 * 1024 * 1024;
const MAX_FILE_BYTES = 10 * 1024 * 1024;
const MAX_SEARCH_FILE_BYTES = 1024 * 1024;
const MAX_SEARCH_MATCHES = 50;

type JsonRecord = Record<string, unknown>;
type SourceFile = { file: string; bytes: Uint8Array; sha256: string; byteSize: number };

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}
function text(value: unknown) { return typeof value === "string" ? value.trim() : ""; }
function serviceClient() {
  if (!SERVICE_ROLE) throw new Error("SOURCE_FILES_NOT_CONFIGURED");
  return createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false, autoRefreshToken: false } });
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
async function sha256Hex(bytes: Uint8Array) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function safePath(value: unknown) {
  const path = text(value);
  if (!path || path.length > 512 || path.startsWith("/") || path.endsWith("/") || path.includes("\\") || path.includes("\0") || path.includes("?") || path.includes("#")) {
    throw new Error("SOURCE_FILE_PATH_INVALID");
  }
  if (path.split("/").some((part) => !part || part === "." || part === ".." || part.length > 255)) {
    throw new Error("SOURCE_FILE_PATH_INVALID");
  }
  return path;
}
function base64Bytes(value: unknown) {
  const source = text(value);
  if (!source || source.length % 4 !== 0 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(source)) {
    throw new Error("SOURCE_FILE_BASE64_INVALID");
  }
  let binary = "";
  try { binary = atob(source); } catch { throw new Error("SOURCE_FILE_BASE64_INVALID"); }
  if (binary.length > MAX_FILE_BYTES) throw new Error("SOURCE_FILE_TOO_LARGE");
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
function toBase64(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
function isTextFile(path: string) {
  return /\.(?:html?|css|[cm]?js|jsx|ts|tsx|json|md|txt|xml|svg|ya?ml|toml|sql|dart|kt|kts|swift|py|rb|go|rs|java|c|cc|cpp|h|hpp)$/i.test(path);
}
function redactSecrets(source: string) {
  let redacted = false;
  let value = source.replace(/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/g, () => {
    redacted = true;
    return "[REDACTED_PRIVATE_KEY]";
  });
  value = value.replace(/\b(SUPABASE_SERVICE_ROLE_KEY|OPENAI_API_KEY|GITHUB_TOKEN|VERCEL_TOKEN|AWS_SECRET_ACCESS_KEY)\b\s*([:=])\s*(["']?)[A-Za-z0-9+/_=.\-]{12,}\3/g, (_match, name, separator) => {
    redacted = true;
    return `${name}${separator}[REDACTED_SECRET]`;
  });
  value = value.replace(/\b(ghp_|github_pat_|sk-proj-|sk_live_)[A-Za-z0-9_\-]{12,}/g, (_match, prefix) => {
    redacted = true;
    return `${prefix}[REDACTED_SECRET]`;
  });
  return { value, redacted };
}
function u16(value: number) { return [value & 255, (value >>> 8) & 255]; }
function u32(value: number) { return [value & 255, (value >>> 8) & 255, (value >>> 16) & 255, (value >>> 24) & 255]; }
function crc32(bytes: Uint8Array) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function concat(parts: Uint8Array[]) {
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) { out.set(part, offset); offset += part.length; }
  return out;
}
function bytesOf(values: number[]) { return new Uint8Array(values); }
function zipStored(files: SourceFile[]) {
  const encoder = new TextEncoder();
  const local: Uint8Array[] = [];
  const central: Uint8Array[] = [];
  let offset = 0;
  for (const source of files) {
    const name = encoder.encode(source.file);
    const checksum = crc32(source.bytes);
    const localHeader = bytesOf([
      ...u32(0x04034b50), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(0), ...u16(0),
      ...u32(checksum), ...u32(source.bytes.length), ...u32(source.bytes.length), ...u16(name.length), ...u16(0),
    ]);
    local.push(localHeader, name, source.bytes);
    const centralHeader = bytesOf([
      ...u32(0x02014b50), ...u16(20), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(0), ...u16(0),
      ...u32(checksum), ...u32(source.bytes.length), ...u32(source.bytes.length), ...u16(name.length), ...u16(0), ...u16(0),
      ...u16(0), ...u16(0), ...u32(0), ...u32(offset),
    ]);
    central.push(centralHeader, name);
    offset += localHeader.length + name.length + source.bytes.length;
  }
  const centralBytes = concat(central);
  const end = bytesOf([
    ...u32(0x06054b50), ...u16(0), ...u16(0), ...u16(files.length), ...u16(files.length),
    ...u32(centralBytes.length), ...u32(offset), ...u16(0),
  ]);
  return concat([...local, centralBytes, end]);
}
async function recordAudit(admin: ReturnType<typeof serviceClient>, args: JsonRecord, required: boolean) {
  const { error } = await admin.rpc("pandora_record_source_access_audit_service_v1", args);
  if (error && required) throw new Error("SOURCE_ACCESS_AUDIT_FAILED");
  if (error) console.error(JSON.stringify({ code: "SOURCE_ACCESS_AUDIT_FAILED", detail: error.code }));
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-methods": "POST, OPTIONS", "access-control-allow-headers": "authorization, apikey, content-type" } });
  if (req.method !== "POST") return json({ code: "METHOD_NOT_ALLOWED", plainMessage: "That source action is not available.", requestId }, 405, requestId);
  try {
    const authorization = req.headers.get("authorization") || "";
    if (!/^Bearer\s+\S+$/i.test(authorization)) throw new Error("SIGN_IN_REQUIRED");
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) throw new Error("SIGN_IN_REQUIRED");
    let body: JsonRecord;
    try { body = asRecord(await req.json()); } catch { throw new Error("INVALID_JSON"); }
    if (Object.keys(body).some((key) => !new Set(["projectId", "versionId", "operation", "path", "query"]).has(key))) throw new Error("INVALID_JSON");
    const projectId = text(body.projectId).toLowerCase();
    const versionId = text(body.versionId).toLowerCase();
    const operation = text(body.operation).toLowerCase();
    if (!UUID_RE.test(projectId) || !UUID_RE.test(versionId) || !new Set(["tree", "read", "search", "export"]).has(operation)) throw new Error("INVALID_SOURCE_REQUEST");
    const capability = operation === "search" ? "search" : operation === "export" ? "export" : "read";
    const action = `source.${operation}`;
    const admin = serviceClient();
    const { data: project, error: projectError } = await admin.from("projectos_projects").select("id,organization_id").eq("id", projectId).maybeSingle();
    if (projectError || !project) throw new Error("PROJECT_NOT_FOUND");
    const organizationId = text(project.organization_id);
    const { data: entitlement, error: entitlementError } = await userClient.rpc("pandora_get_source_entitlement_v1", { p_project_id: projectId, p_capability: capability });
    if (entitlementError) throw new Error("SOURCE_ENTITLEMENT_CHECK_FAILED");
    const decision = asRecord(entitlement);
    const allowed = decision.allowed === true;
    const entitlementId = text(decision.entitlementId);
    const reason = text(decision.reason) || "NO_SOURCE_ENTITLEMENT";
    if (!allowed) {
      await recordAudit(admin, { p_organization_id: organizationId, p_project_id: projectId, p_user_id: authData.user.id, p_entitlement_id: null, p_capability: capability, p_action: action, p_resource_ref: versionId, p_allowed: false, p_reason: reason, p_request_id: requestId, p_metadata: {} }, false);
      return json({ code: "SOURCE_ENTITLEMENT_REQUIRED", reason, plainMessage: "Source files are available with source access.", requestId }, 403, requestId);
    }
    await recordAudit(admin, { p_organization_id: organizationId, p_project_id: projectId, p_user_id: authData.user.id, p_entitlement_id: UUID_RE.test(entitlementId) ? entitlementId : null, p_capability: capability, p_action: action, p_resource_ref: versionId, p_allowed: true, p_reason: "SOURCE_ENTITLEMENT_ACTIVE", p_request_id: requestId, p_metadata: {} }, true);

    const { data: version, error: versionError } = await admin.from("pandora_project_versions").select("id,organization_id,project_id,root_artifact_version_id,artifact_digest_sha256").eq("id", versionId).eq("organization_id", organizationId).eq("project_id", projectId).maybeSingle();
    if (versionError || !version) throw new Error("EXACT_VERSION_REQUIRED");
    const rootId = text(version.root_artifact_version_id);
    const artifactDigest = text(version.artifact_digest_sha256).toLowerCase();
    if (!UUID_RE.test(rootId) || !SHA256_RE.test(artifactDigest)) throw new Error("ARTIFACT_LINEAGE_INCOMPLETE");
    const { data: artifactVersion, error: artifactVersionError } = await admin.from("pandora_artifact_versions").select("id,artifact_id,content_sha256,byte_size,storage_provider,storage_bucket,storage_path").eq("id", rootId).eq("organization_id", organizationId).eq("project_id", projectId).maybeSingle();
    if (artifactVersionError || !artifactVersion || text(artifactVersion.content_sha256).toLowerCase() !== artifactDigest || text(artifactVersion.storage_provider) !== "supabase_storage") throw new Error("ARTIFACT_NOT_FOUND");
    const { data: artifact, error: artifactError } = await admin.from("pandora_artifacts").select("id,artifact_kind").eq("id", artifactVersion.artifact_id).eq("organization_id", organizationId).eq("project_id", projectId).maybeSingle();
    if (artifactError || !artifact || !new Set(["build_output", "runtime_bundle"]).has(text(artifact.artifact_kind))) throw new Error("ARTIFACT_NOT_FOUND");
    const { data: blob, error: blobError } = await admin.storage.from(text(artifactVersion.storage_bucket)).download(text(artifactVersion.storage_path));
    if (blobError || !blob) throw new Error("ARTIFACT_STORAGE_READ_FAILED");
    const bundleBytes = new Uint8Array(await blob.arrayBuffer());
    const declaredSize = Number(artifactVersion.byte_size);
    if (!Number.isSafeInteger(declaredSize) || declaredSize < 1 || declaredSize > MAX_BUNDLE_BYTES || bundleBytes.length !== declaredSize || await sha256Hex(bundleBytes) !== artifactDigest) throw new Error("ARTIFACT_BUNDLE_INVALID");
    let bundle: JsonRecord;
    try { bundle = asRecord(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bundleBytes))); } catch { throw new Error("ARTIFACT_BUNDLE_INVALID"); }
    if (bundle.kind !== "pandora.runtime-bundle.v1" || bundle.schemaVersion !== 1 || text(bundle.projectVersionId).toLowerCase() !== versionId || !Array.isArray(bundle.files)) throw new Error("ARTIFACT_BUNDLE_INVALID");
    const files: SourceFile[] = [];
    const seen = new Set<string>();
    let prior = "";
    let totalBytes = 0;
    for (const raw of bundle.files) {
      const entry = asRecord(raw);
      const file = safePath(entry.file);
      if (seen.has(file) || (prior && prior.localeCompare(file, "en") >= 0) || entry.encoding !== "base64") throw new Error("ARTIFACT_FILES_NOT_CANONICAL");
      seen.add(file); prior = file;
      const bytes = base64Bytes(entry.data);
      totalBytes += bytes.length;
      if (totalBytes > MAX_SOURCE_BYTES) throw new Error("SOURCE_BUNDLE_TOO_LARGE");
      const digest = text(entry.sha256).toLowerCase();
      if (!SHA256_RE.test(digest) || await sha256Hex(bytes) !== digest || Number(entry.byteSize) !== bytes.length) throw new Error("ARTIFACT_FILE_DIGEST_MISMATCH");
      files.push({ file, bytes, sha256: digest, byteSize: bytes.length });
    }

    if (operation === "tree") {
      return json({ kind: "pandora.source-tree.v1", projectId, versionId, artifactDigest, files: files.map((file) => ({ path: file.file, byteSize: file.byteSize, sha256: file.sha256, text: isTextFile(file.file) })) }, 200, requestId);
    }
    if (operation === "read") {
      const requested = safePath(body.path);
      const source = files.find((file) => file.file === requested);
      if (!source) return json({ code: "SOURCE_FILE_NOT_FOUND", plainMessage: "That file is not in this version.", requestId }, 404, requestId);
      if (isTextFile(source.file)) {
        const decoded = new TextDecoder("utf-8").decode(source.bytes);
        const redaction = redactSecrets(decoded);
        return json({ kind: "pandora.source-file.v1", projectId, versionId, path: source.file, sha256: source.sha256, byteSize: source.byteSize, encoding: "utf-8", content: redaction.value, redacted: redaction.redacted }, 200, requestId);
      }
      return json({ kind: "pandora.source-file.v1", projectId, versionId, path: source.file, sha256: source.sha256, byteSize: source.byteSize, encoding: "base64", content: toBase64(source.bytes), redacted: false }, 200, requestId);
    }
    if (operation === "search") {
      const query = text(body.query);
      if (query.length < 2 || query.length > 100) throw new Error("SOURCE_SEARCH_QUERY_INVALID");
      const needle = query.toLowerCase();
      const matches: JsonRecord[] = [];
      for (const source of files) {
        if (matches.length >= MAX_SEARCH_MATCHES || !isTextFile(source.file) || source.byteSize > MAX_SEARCH_FILE_BYTES) continue;
        const decoded = redactSecrets(new TextDecoder("utf-8").decode(source.bytes)).value;
        const lower = decoded.toLowerCase();
        let offset = 0;
        while (matches.length < MAX_SEARCH_MATCHES) {
          const index = lower.indexOf(needle, offset);
          if (index < 0) break;
          const line = decoded.slice(0, index).split("\n").length;
          const start = Math.max(0, index - 80);
          const end = Math.min(decoded.length, index + query.length + 120);
          matches.push({ path: source.file, line, snippet: decoded.slice(start, end).replace(/\s+/g, " ").trim().slice(0, 240) });
          offset = index + Math.max(1, query.length);
        }
      }
      return json({ kind: "pandora.source-search.v1", projectId, versionId, query, truncated: matches.length >= MAX_SEARCH_MATCHES, matches }, 200, requestId);
    }

    const exportFiles = files.map((source) => {
      if (!isTextFile(source.file)) return source;
      const redaction = redactSecrets(new TextDecoder("utf-8").decode(source.bytes));
      if (!redaction.redacted) return source;
      const bytes = new TextEncoder().encode(redaction.value);
      return { file: source.file, bytes, byteSize: bytes.length, sha256: source.sha256 };
    });
    const zip = zipStored(exportFiles);
    return new Response(zip, {
      status: 200,
      headers: {
        "content-type": "application/octet-stream",\n        "x-pandora-content-type": "application/zip",
        "content-disposition": `attachment; filename="pandora-${projectId}-${versionId}.zip"`,
        "cache-control": "no-store, max-age=0",
        "x-content-type-options": "nosniff",
        "x-request-id": requestId,
        "x-pandora-source-version": versionId,
      },
    });
  } catch (error) {
    const code = error instanceof Error ? error.message : "SOURCE_FILES_UNAVAILABLE";
    if (code === "SIGN_IN_REQUIRED") return json({ code, plainMessage: "Please sign in again.", requestId }, 401, requestId);
    if (code === "PROJECT_NOT_FOUND") return json({ code, plainMessage: "Pandora could not find that project.", requestId }, 404, requestId);
    if (new Set(["INVALID_JSON", "INVALID_SOURCE_REQUEST", "SOURCE_FILE_PATH_INVALID", "SOURCE_SEARCH_QUERY_INVALID"]).has(code)) return json({ code, plainMessage: "Pandora could not understand that source request.", requestId }, 400, requestId);
    if (code === "SOURCE_BUNDLE_TOO_LARGE") return json({ code, plainMessage: "This source bundle is too large to open here.", requestId }, 413, requestId);
    console.error(JSON.stringify({ requestId, code }));
    return json({ code: "SOURCE_FILES_UNAVAILABLE", plainMessage: "Pandora could not open source files right now.", requestId }, 503, requestId);
  }
});
