import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import {
  createClient,
  type SupabaseClient,
} from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

const BUILD_KINDS = new Set([
  "website",
  "web_app",
  "mobile_app",
  "internal_tool",
  "automation",
  "api_backend",
  "full_system",
  "help_me_decide",
]);

const DEFAULT_ORIGINS = new Set([
  "https://pandoras-box-system.vercel.app",
  "https://mcpmaster.vercel.app",
]);

type JsonRecord = Record<string, unknown>;
type DbClient = SupabaseClient<any, "public", "public", any, any>;
type UserContext = {
  userId: string;
  organizationId: string;
  role: string;
  client: DbClient;
};

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

function textValue(value: unknown, fallback = "") {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function jsonResponse(
  body: unknown,
  status = 200,
  requestId?: string,
  origin?: string | null,
) {
  return new Response(status === 204 ? null : JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store, max-age=0",
      "x-content-type-options": "nosniff",
      "access-control-allow-methods": "GET, POST, OPTIONS",
      "access-control-allow-headers":
        "authorization, apikey, content-type, idempotency-key, x-organization-id",
      "vary": "Origin",
      ...(origin ? { "access-control-allow-origin": origin } : {}),
      ...(requestId ? { "x-request-id": requestId } : {}),
    },
  });
}

function allowedOrigin(req: Request) {
  const origin = req.headers.get("origin");
  if (!origin) return null;
  const configured = (Deno.env.get("PANDORA_ALLOWED_ORIGINS") || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  const allowed = new Set([...DEFAULT_ORIGINS, ...configured]);
  return allowed.has(origin) ? origin : "";
}

async function bodyJson(req: Request): Promise<JsonRecord> {
  const length = Number(req.headers.get("content-length") || "0");
  if (Number.isFinite(length) && length > 64 * 1024) {
    throw new Error("BODY_TOO_LARGE");
  }
  let value: unknown;
  try {
    value = await req.json();
  } catch {
    throw new Error("INVALID_JSON");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("INVALID_JSON");
  }
  return value as JsonRecord;
}

async function authenticate(req: Request): Promise<UserContext> {
  const authorization = req.headers.get("authorization") || "";
  if (!/^Bearer\s+\S+$/i.test(authorization)) {
    throw new Error("SIGN_IN_REQUIRED");
  }

  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await client.auth.getUser();
  if (authError || !authData.user) throw new Error("SIGN_IN_REQUIRED");

  const requestedOrganization = req.headers.get("x-organization-id")?.trim() || null;
  let membership = client.from("memberships")
    .select("organization_id, role, status")
    .eq("user_id", authData.user.id)
    .eq("status", "active")
    .limit(3);
  if (requestedOrganization) {
    membership = membership.eq("organization_id", requestedOrganization);
  }
  const { data: memberships, error } = await membership;
  if (error || !memberships?.length) throw new Error("ORGANIZATION_ACCESS_REQUIRED");
  if (!requestedOrganization && memberships.length > 1) throw new Error("ORGANIZATION_SELECTION_REQUIRED");
  const role = String(memberships[0].role);
  if (!new Set(["owner", "admin"]).has(role)) throw new Error("OWNER_ROLE_REQUIRED");

  return {
    userId: authData.user.id,
    organizationId: String(memberships[0].organization_id),
    role,
    client,
  };
}

async function enforceRateLimit(context: UserContext, method: string) {
  const keyBytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${context.userId}:${method}:pandora-project-runtime`),
  );
  const key = [...new Uint8Array(keyBytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
  const { data, error } = await serviceClient().rpc("consume_runtime_rate_limit", {
    p_organization_id: context.organizationId,
    p_key_hash: key,
    p_limit: method === "GET" ? 120 : 20,
    p_window_seconds: 60,
  });
  if (error) throw new Error("RATE_LIMIT_UNAVAILABLE");
  if (asRecord(data).allowed !== true) throw new Error("RATE_LIMITED");
}

function routePath(pathname: string) {
  const marker = "/pandora-project-runtime";
  const index = pathname.indexOf(marker);
  if (index >= 0) {
    const rest = pathname.slice(index + marker.length);
    return rest || "/";
  }
  return pathname || "/";
}

function slugify(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 42) || "project";
}

function buildKind(value: unknown) {
  const kind = textValue(value).toLowerCase();
  if (!BUILD_KINDS.has(kind)) throw new Error("INVALID_BUILD_KIND");
  return kind;
}

function normalizeDomain(value: unknown) {
  const raw = textValue(value).toLowerCase();
  if (!raw) return null;
  const stripped = raw.replace(/^https?:\/\//, "").split("/")[0].replace(/\.$/, "");
  if (stripped.length > 253 || !/^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(stripped)) {
    throw new Error("INVALID_DOMAIN");
  }
  return stripped;
}

async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function serviceClient() {
  if (!SUPABASE_SERVICE_ROLE_KEY) throw new Error("RUNTIME_BROKER_NOT_CONFIGURED");
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function vercelRequest(path: string, init: RequestInit, accepted: number[] = [200, 201]) {
  if (!SUPABASE_SERVICE_ROLE_KEY) throw new Error("RUNTIME_BROKER_NOT_CONFIGURED");
  const method = textValue(init.method, "GET").toUpperCase();
  const admin = serviceClient();
  const { data: providerConfig, error: providerConfigError } = await admin.from("pandora_runtime_provider_configs")
    .select("config_value").eq("provider", "vercel").eq("config_key", "team_id").eq("active", true).maybeSingle();
  const teamId = textValue(asRecord(providerConfig).config_value);
  if (providerConfigError || !teamId) throw new Error("VERCEL_NOT_CONFIGURED");
  const separator = path.includes("?") ? "&" : "?";
  const scopedPath = `${path}${separator}teamId=${encodeURIComponent(teamId)}`;
  let requestBody: JsonRecord | null = null;
  if (typeof init.body === "string" && init.body) {
    try {
      requestBody = asRecord(JSON.parse(init.body));
    } catch {
      throw new Error("VERCEL_REQUEST_INVALID");
    }
  }
  const { data, error } = await admin.rpc("pandora_worker_f_vercel_request_20260829", {
    p_method: method,
    p_path: scopedPath,
    p_body: requestBody,
  });
  if (error) throw new Error("VERCEL_REQUEST_FAILED");
  const envelope = asRecord(data);
  const status = Number(envelope.status ?? 0);
  const decoded: unknown = envelope.body ?? {};
  if (!accepted.includes(status)) {
    const payload = asRecord(decoded);
    const nested = asRecord(payload.error);
    const providerCode = textValue(nested.code ?? payload.code);
    if (status === 409 || providerCode.includes("conflict")) throw new Error("VERCEL_CONFLICT");
    if (providerCode.includes("domain") || status === 400 && path.includes("/domains")) throw new Error("VERCEL_DOMAIN_REJECTED");
    throw new Error("VERCEL_REQUEST_FAILED");
  }
  return asRecord(decoded);
}

async function ensureVercelProject(context: UserContext, project: JsonRecord) {
  const config = asRecord(project.config);
  const journey = asRecord(config.customerJourney);
  const existingId = textValue(journey.vercelProjectId);
  const existingName = textValue(journey.vercelProjectName);
  if (existingId && existingName) return { id: existingId, name: existingName, config };

  const projectId = textValue(project.id);
  const desiredName = `pandora-${slugify(textValue(project.name))}-${projectId.slice(0, 8)}`;
  let provider: JsonRecord;
  try {
    provider = await vercelRequest("/v11/projects", {
      method: "POST",
      body: JSON.stringify({ name: desiredName, framework: null, skipGitConnectDuringLink: true, enablePreviewFeedback: true, enableProductionFeedback: true }),
    });
  } catch (error) {
    if (!(error instanceof Error) || error.message !== "VERCEL_CONFLICT") throw error;
    provider = await vercelRequest(`/v9/projects/${encodeURIComponent(desiredName)}`, { method: "GET" }, [200]);
  }
  const providerId = textValue(provider.id);
  const providerName = textValue(provider.name, desiredName);
  if (!providerId) throw new Error("VERCEL_PROJECT_INVALID");

  const nextConfig = {
    ...config,
    customerJourney: { ...journey, vercelProjectId: providerId, vercelProjectName: providerName, runtimeStatus: "ready", runtimeUpdatedAt: new Date().toISOString() },
  };
  const { error: updateError } = await serviceClient().from("projectos_projects")
    .update({ config: nextConfig, updated_at: new Date().toISOString() })
    .eq("organization_id", context.organizationId).eq("id", projectId);
  if (updateError) throw new Error("BACKEND_WRITE_FAILED");
  return { id: providerId, name: providerName, config: nextConfig };
}

async function projectByIdentifier(context: UserContext, identifier: string) {
  const value = identifier.trim();
  if (!value) throw new Error("PROJECT_NOT_FOUND");
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
  let query = context.client.from("projectos_projects")
    .select("id, project_key, name, objective, status, config, created_at, updated_at")
    .eq("organization_id", context.organizationId);
  query = isUuid ? query.eq("id", value) : query.eq("project_key", value);
  const { data, error } = await query.maybeSingle();
  if (error) throw new Error("BACKEND_READ_FAILED");
  if (!data) throw new Error("PROJECT_NOT_FOUND");
  return asRecord(data);
}

function projectResponse(project: JsonRecord) {
  const config = asRecord(project.config);
  const journey = asRecord(config.customerJourney);
  return {
    id: textValue(project.id),
    projectKey: textValue(project.project_key),
    name: textValue(project.name, "Untitled project"),
    objective: textValue(project.objective),
    buildKind: textValue(journey.buildKind, "help_me_decide"),
    stage: textValue(journey.stage, "idea"),
    runtimeStatus: textValue(journey.runtimeStatus, "not_configured"),
    vercelProjectId: textValue(journey.vercelProjectId) || null,
    vercelProjectName: textValue(journey.vercelProjectName) || null,
    previewUrl: textValue(journey.previewUrl) || null,
    liveUrl: textValue(journey.liveUrl) || null,
    requestedDomain: textValue(journey.requestedDomain) || null,
    domainStatus: textValue(journey.domainStatus) || null,
    createdAt: project.created_at ?? null,
    updatedAt: project.updated_at ?? null,
  };
}


const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA40_RE = /^[0-9a-f]{40}$/;
const SHA256_RE = /^[0-9a-f]{64}$/;
const MAX_RUNTIME_BUNDLE_BYTES = 25 * 1024 * 1024;
const MAX_RUNTIME_FILE_BYTES = 10 * 1024 * 1024;
const MAX_RUNTIME_FILES = 1000;

type RuntimeFile = { file: string; data: string; encoding: "base64"; sha256: string; byteSize: number };
type ExactRuntimeBundle = {
  version: JsonRecord;
  artifactVersion: JsonRecord;
  artifact: JsonRecord;
  artifactDigest: string;
  sourceDigest: string;
  sourceKind: "git_commit" | "artifact_snapshot";
  sourceRef: string;
  sourceCommit: string | null;
  buildJobId: string;
  projectSpecId: string;
  files: RuntimeFile[];
};

function projectSourceIdentity(versionIdValue: unknown, sourceKindValue: unknown, sourceRefValue: unknown, sourceCommitValue: unknown) {
  const versionId = textValue(versionIdValue).toLowerCase();
  const rawCommit = textValue(sourceCommitValue).toLowerCase() || null;
  const sourceKind = textValue(sourceKindValue, rawCommit ? "git_commit" : "artifact_snapshot").toLowerCase();
  const sourceRef = textValue(sourceRefValue, sourceKind === "git_commit" ? (rawCommit ?? "") : versionId).toLowerCase();
  const valid = UUID_RE.test(versionId) && (sourceKind === "git_commit"
    ? Boolean(rawCommit && SHA40_RE.test(rawCommit) && sourceRef === rawCommit)
    : sourceKind === "artifact_snapshot" && rawCommit === null && sourceRef === versionId);
  if (!valid) throw new Error("SOURCE_IDENTITY_MISMATCH");
  return { sourceKind: sourceKind as "git_commit" | "artifact_snapshot", sourceRef, sourceCommit: rawCommit };
}

async function sha256BytesHex(bytes: Uint8Array) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function bytesToBase64(bytes: Uint8Array) {
  let binary = "";
  const chunk = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunk) {
    binary += String.fromCharCode(...bytes.subarray(offset, Math.min(offset + chunk, bytes.length)));
  }
  return btoa(binary);
}

function canonicalBase64(value: unknown) {
  const text = textValue(value);
  if (!text || text.length % 4 !== 0 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(text)) throw new Error("ARTIFACT_FILE_BASE64_INVALID");
  let binary: string;
  try { binary = atob(text); } catch { throw new Error("ARTIFACT_FILE_BASE64_INVALID"); }
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  if (bytesToBase64(bytes) !== text) throw new Error("ARTIFACT_FILE_BASE64_NON_CANONICAL");
  return bytes;
}

function safeRuntimePath(value: unknown) {
  const path = textValue(value);
  if (!path || path.length > 512 || path.startsWith("/") || path.endsWith("/") || path.includes("\\") || path.includes("\0") || path.includes("?") || path.includes("#")) throw new Error("ARTIFACT_FILE_PATH_INVALID");
  const parts = path.split("/");
  if (parts.some((part) => !part || part === "." || part === ".." || part.length > 255)) throw new Error("ARTIFACT_FILE_PATH_INVALID");
  return path;
}

function safeStorageCoordinate(bucketValue: unknown, pathValue: unknown) {
  const bucket = textValue(bucketValue);
  const path = textValue(pathValue);
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,126}$/.test(bucket)) throw new Error("ARTIFACT_STORAGE_INVALID");
  if (!path || path.length > 1024 || path.startsWith("/") || path.endsWith("/") || path.includes("\\") || path.includes("\0") || path.split("/").some((part) => !part || part === "." || part === "..")) throw new Error("ARTIFACT_STORAGE_INVALID");
  return { bucket, path };
}

async function loadExactRuntimeBundle(context: UserContext, projectId: string, versionId: string, requestedArtifactDigest: string): Promise<ExactRuntimeBundle> {
  if (!UUID_RE.test(versionId) || !SHA256_RE.test(requestedArtifactDigest)) throw new Error("EXACT_VERSION_REQUIRED");
  const admin = serviceClient();
  const { data: versionData, error: versionError } = await admin.from("pandora_project_versions")
    .select("id, organization_id, project_id, project_spec_id, build_job_id, root_artifact_version_id, source_sha256, source_kind, source_ref, source_commit, artifact_digest_sha256, migration_set_digest_sha256, runtime_target_digest_sha256, lifecycle_status, created_at")
    .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("id", versionId).maybeSingle();
  if (versionError) throw new Error("BACKEND_READ_FAILED");
  if (!versionData) throw new Error("EXACT_VERSION_REQUIRED");
  const version = asRecord(versionData);
  const rootArtifactVersionId = textValue(version.root_artifact_version_id);
  const artifactDigest = textValue(version.artifact_digest_sha256).toLowerCase();
  const sourceDigest = textValue(version.source_sha256).toLowerCase();
  const { sourceKind, sourceRef, sourceCommit } = projectSourceIdentity(versionId, version.source_kind, version.source_ref, version.source_commit);
  const buildJobId = textValue(version.build_job_id);
  const projectSpecId = textValue(version.project_spec_id);
  if (!UUID_RE.test(rootArtifactVersionId) || !UUID_RE.test(buildJobId) || !UUID_RE.test(projectSpecId) || !SHA256_RE.test(artifactDigest) || !SHA256_RE.test(sourceDigest)) throw new Error("ARTIFACT_LINEAGE_INCOMPLETE");
  if (artifactDigest !== requestedArtifactDigest) throw new Error("ARTIFACT_DIGEST_MISMATCH");

  const { data: artifactVersionData, error: artifactVersionError } = await admin.from("pandora_artifact_versions")
    .select("id, organization_id, project_id, artifact_id, content_sha256, byte_size, media_type, storage_provider, storage_bucket, storage_path, produced_by_build_step_id, provenance_redacted, created_at")
    .eq("id", rootArtifactVersionId).eq("organization_id", context.organizationId).eq("project_id", projectId).maybeSingle();
  if (artifactVersionError) throw new Error("BACKEND_READ_FAILED");
  if (!artifactVersionData) throw new Error("ARTIFACT_NOT_FOUND");
  const artifactVersion = asRecord(artifactVersionData);
  if (textValue(artifactVersion.content_sha256).toLowerCase() !== artifactDigest) throw new Error("ARTIFACT_DIGEST_MISMATCH");
  if (textValue(artifactVersion.storage_provider).toLowerCase() !== "supabase_storage") throw new Error("ARTIFACT_STORAGE_INVALID");
  const artifactId = textValue(artifactVersion.artifact_id);
  if (!UUID_RE.test(artifactId)) throw new Error("ARTIFACT_LINEAGE_INCOMPLETE");

  const { data: artifactData, error: artifactError } = await admin.from("pandora_artifacts")
    .select("id, organization_id, project_id, logical_key, artifact_kind, created_at")
    .eq("id", artifactId).eq("organization_id", context.organizationId).eq("project_id", projectId).maybeSingle();
  if (artifactError) throw new Error("BACKEND_READ_FAILED");
  if (!artifactData) throw new Error("ARTIFACT_NOT_FOUND");
  const artifact = asRecord(artifactData);
  if (!new Set(["build_output", "runtime_bundle"]).has(textValue(artifact.artifact_kind).toLowerCase())) throw new Error("ARTIFACT_KIND_NOT_DEPLOYABLE");

  const provenance = asRecord(artifactVersion.provenance_redacted);
  const provenanceSource = projectSourceIdentity(versionId, provenance.sourceKind ?? provenance.source_kind, provenance.sourceRef ?? provenance.source_ref, provenance.sourceCommit ?? provenance.source_commit);
  if (textValue(provenance.buildJobId ?? provenance.build_job_id) !== buildJobId || textValue(provenance.projectVersionId ?? provenance.project_version_id) !== versionId || provenanceSource.sourceKind !== sourceKind || provenanceSource.sourceRef !== sourceRef || provenanceSource.sourceCommit !== sourceCommit) throw new Error("ARTIFACT_PROVENANCE_MISMATCH");
  const coordinate = safeStorageCoordinate(artifactVersion.storage_bucket, artifactVersion.storage_path);
  const { data: objectData, error: objectError } = await admin.storage.from(coordinate.bucket).download(coordinate.path);
  if (objectError || !objectData) throw new Error("ARTIFACT_STORAGE_READ_FAILED");
  const bytes = new Uint8Array(await objectData.arrayBuffer());
  const expectedByteSize = Number(artifactVersion.byte_size);
  if (!Number.isSafeInteger(expectedByteSize) || expectedByteSize < 1 || expectedByteSize > MAX_RUNTIME_BUNDLE_BYTES || bytes.byteLength !== expectedByteSize) throw new Error("ARTIFACT_BUNDLE_SIZE_INVALID");
  if ((await sha256BytesHex(bytes)) !== artifactDigest) throw new Error("ARTIFACT_BUNDLE_DIGEST_MISMATCH");

  let bundle: JsonRecord;
  try { bundle = asRecord(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes))); } catch { throw new Error("ARTIFACT_BUNDLE_JSON_INVALID"); }
  if (bundle.kind !== "pandora.runtime-bundle.v1" || bundle.schemaVersion !== 1) throw new Error("ARTIFACT_BUNDLE_SCHEMA_UNSUPPORTED");
  const bundleSource = projectSourceIdentity(versionId, bundle.sourceKind, bundle.sourceRef, bundle.sourceCommit);
  if (textValue(bundle.projectVersionId) !== versionId || textValue(bundle.buildJobId) !== buildJobId || bundleSource.sourceKind !== sourceKind || bundleSource.sourceRef !== sourceRef || bundleSource.sourceCommit !== sourceCommit) throw new Error("ARTIFACT_BUNDLE_LINEAGE_MISMATCH");
  if (!Array.isArray(bundle.files) || bundle.files.length < 1 || bundle.files.length > MAX_RUNTIME_FILES) throw new Error("ARTIFACT_BUNDLE_FILES_INVALID");

  const seen = new Set<string>();
  let prior = "";
  let totalBytes = 0;
  let hasEntrypoint = false;
  const files: RuntimeFile[] = [];
  for (const raw of bundle.files) {
    const entry = asRecord(raw);
    const file = safeRuntimePath(entry.file);
    if (seen.has(file) || prior && prior.localeCompare(file, "en") >= 0) throw new Error("ARTIFACT_FILES_NOT_CANONICAL");
    seen.add(file); prior = file;
    if (file === "index.html") hasEntrypoint = true;
    if (entry.encoding !== "base64") throw new Error("ARTIFACT_FILE_ENCODING_UNSUPPORTED");
    const fileBytes = canonicalBase64(entry.data);
    if (fileBytes.byteLength > MAX_RUNTIME_FILE_BYTES) throw new Error("ARTIFACT_FILE_TOO_LARGE");
    totalBytes += fileBytes.byteLength;
    if (totalBytes > MAX_RUNTIME_BUNDLE_BYTES) throw new Error("ARTIFACT_FILES_TOTAL_TOO_LARGE");
    const fileDigest = textValue(entry.sha256).toLowerCase();
    if (!SHA256_RE.test(fileDigest) || await sha256BytesHex(fileBytes) !== fileDigest) throw new Error("ARTIFACT_FILE_DIGEST_MISMATCH");
    if (!Number.isSafeInteger(Number(entry.byteSize)) || Number(entry.byteSize) !== fileBytes.byteLength) throw new Error("ARTIFACT_FILE_SIZE_MISMATCH");
    files.push({ file, data: textValue(entry.data), encoding: "base64", sha256: fileDigest, byteSize: fileBytes.byteLength });
  }
  if (!hasEntrypoint) throw new Error("ARTIFACT_ENTRYPOINT_MISSING");
  return { version, artifactVersion, artifact, artifactDigest, sourceDigest, sourceKind, sourceRef, sourceCommit, buildJobId, projectSpecId, files };
}

function exactPreviewMeta(bundle: ExactRuntimeBundle, projectId: string, versionId: string, operationId: string, authorizationRef: string) {
  return {
    pandoraOperationId: operationId,
    pandoraProjectId: projectId,
    pandoraProjectVersionId: versionId,
    pandoraArtifactDigest: bundle.artifactDigest,
    pandoraSourceKind: bundle.sourceKind,
    pandoraSourceRef: bundle.sourceRef,
    ...(bundle.sourceCommit ? { pandoraSourceCommit: bundle.sourceCommit } : {}),
    pandoraAuthorizationRef: authorizationRef,
    pandoraEnvironment: "preview",
  };
}

function assertPreviewProviderLineage(deployment: JsonRecord, bundle: ExactRuntimeBundle, projectId: string, versionId: string, operationId: string) {
  const meta = asRecord(deployment.meta);
  const providerCommit = textValue(meta.pandoraSourceCommit).toLowerCase() || null;
  if (textValue(meta.pandoraOperationId) !== operationId || textValue(meta.pandoraProjectId) !== projectId || textValue(meta.pandoraProjectVersionId) !== versionId || textValue(meta.pandoraArtifactDigest).toLowerCase() !== bundle.artifactDigest || textValue(meta.pandoraSourceKind).toLowerCase() !== bundle.sourceKind || textValue(meta.pandoraSourceRef).toLowerCase() !== bundle.sourceRef || providerCommit !== bundle.sourceCommit) throw new Error("PROVIDER_LINEAGE_MISMATCH");
}

async function findVercelDeploymentByOperation(providerProjectId: string, operationId: string) {
  const result = await vercelRequest(`/v6/deployments?projectId=${encodeURIComponent(providerProjectId)}&limit=100`, { method: "GET" }, [200]);
  const deployments = Array.isArray(result.deployments) ? result.deployments : [];
  return asRecord(deployments.find((item) => textValue(asRecord(asRecord(item).meta).pandoraOperationId) === operationId));
}

async function createVercelDeployment(provider: { id: string; name: string }, bundle: ExactRuntimeBundle, versionId: string, operationId: string, authorizationRef: string) {
  const prior = await findVercelDeploymentByOperation(provider.id, operationId);
  if (Object.keys(prior).length) {
    assertPreviewProviderLineage(prior, bundle, textValue(bundle.version.project_id), versionId, operationId);
    return prior;
  }
  const requestBody: JsonRecord = {
    name: provider.name,
    project: provider.id,
    target: "preview",
    files: bundle.files.map(({ file, data, encoding }) => ({ file, data, encoding })),
    meta: exactPreviewMeta(bundle, textValue(bundle.version.project_id), versionId, operationId, authorizationRef),
  };
  let deployment: JsonRecord;
  try {
    deployment = await vercelRequest("/v13/deployments", { method: "POST", body: JSON.stringify(requestBody) }, [200, 201]);
  } catch (error) {
    const reconciled = await findVercelDeploymentByOperation(provider.id, operationId);
    if (!Object.keys(reconciled).length) throw new Error("PREVIEW_RECONCILIATION_REQUIRED");
    assertPreviewProviderLineage(reconciled, bundle, textValue(bundle.version.project_id), versionId, operationId);
    deployment = reconciled;
  }
  const deploymentId = textValue(deployment.id ?? deployment.uid);
  if (!deploymentId) throw new Error("VERCEL_DEPLOYMENT_INVALID");
  let latest = deployment;
  for (let attempt = 0; attempt < 8; attempt++) {
    const state = textValue(latest.readyState ?? latest.status).toUpperCase();
    if (["READY", "ERROR", "CANCELED"].includes(state)) break;
    await new Promise((resolve) => setTimeout(resolve, 750));
    try { latest = await vercelRequest(`/v13/deployments/${encodeURIComponent(deploymentId)}`, { method: "GET" }, [200]); } catch { break; }
  }
  if (Object.keys(asRecord(latest.meta)).length) assertPreviewProviderLineage(latest, bundle, textValue(bundle.version.project_id), versionId, operationId);
  return latest;
}

async function createProject(context: UserContext, body: JsonRecord) {
  const name = textValue(body.name);
  const objective = textValue(body.objective);
  const kind = buildKind(body.buildKind);
  if (name.length < 2 || name.length > 100) throw new Error("INVALID_PROJECT_NAME");
  if (objective.length < 10 || objective.length > 50000) throw new Error("INVALID_OBJECTIVE");

  const projectKey = `${slugify(name)}-${crypto.randomUUID().slice(0, 8)}`;
  const now = new Date().toISOString();
  const config = {
    customerJourney: {
      buildKind: kind,
      stage: "understanding",
      runtimeStatus: "not_configured",
      createdFrom: "simple_mode",
      updatedAt: now,
    },
  };
  const { data, error } = await serviceClient().from("projectos_projects")
    .insert({ organization_id: context.organizationId, project_key: projectKey, name, workspace_path: `projectos/projects/${projectKey}`, status: "active", objective, roadmap_version: "2.0.0", config, created_by: context.userId })
    .select("id, project_key, name, objective, status, config, created_at, updated_at").single();
  if (error || !data) throw new Error("BACKEND_WRITE_FAILED");
  return projectResponse(asRecord(data));
}


type DomainFacts = {
  ownershipVerified: boolean;
  dnsConfigured: boolean;
  tlsReady: boolean;
  routingReady: boolean;
  runtimeHealthy: boolean;
  allReady: boolean;
  httpStatus: number | null;
  verification: unknown[];
};

async function inspectVercelDomainFacts(providerProjectId: string, hostname: string): Promise<DomainFacts> {
  const domain = normalizeDomain(hostname);
  if (!domain) throw new Error("INVALID_DOMAIN");
  const projectDomain = await vercelRequest(`/v9/projects/${encodeURIComponent(providerProjectId)}/domains/${encodeURIComponent(domain)}`, { method: "GET" }, [200]);
  const config = await vercelRequest(`/v6/domains/${encodeURIComponent(domain)}/config`, { method: "GET" }, [200]);
  const ownershipVerified = projectDomain.verified === true;
  const dnsConfigured = config.misconfigured === false;
  let tlsReady = false;
  let routingReady = false;
  let runtimeHealthy = false;
  let httpStatus: number | null = null;
  try {
    let response = await fetch(`https://${domain}/`, { method: "HEAD", redirect: "manual", signal: AbortSignal.timeout(6000), headers: { "user-agent": "Pandora-Worker-F-Domain-Probe/1.0" } });
    if (response.status === 405) response = await fetch(`https://${domain}/`, { method: "GET", redirect: "manual", signal: AbortSignal.timeout(6000), headers: { "user-agent": "Pandora-Worker-F-Domain-Probe/1.0", range: "bytes=0-0" } });
    httpStatus = response.status;
    tlsReady = true;
    routingReady = Boolean(response.headers.get("x-vercel-id"));
    runtimeHealthy = response.status >= 200 && response.status < 400;
    try { await response.body?.cancel(); } catch { /* bounded probe body */ }
  } catch {
    tlsReady = false;
    routingReady = false;
    runtimeHealthy = false;
  }
  const rawVerification = Array.isArray(projectDomain.verification) ? projectDomain.verification : [];
  const verification = rawVerification.slice(0, 20).map((item) => {
    const row = asRecord(item);
    return { type: textValue(row.type), domain: textValue(row.domain), reason: textValue(row.reason) };
  });
  return { ownershipVerified, dnsConfigured, tlsReady, routingReady, runtimeHealthy, allReady: ownershipVerified && dnsConfigured && tlsReady && routingReady && runtimeHealthy, httpStatus, verification };
}

async function saveDomainFacts(context: UserContext, projectId: string, providerProjectId: string, hostname: string, environment: string, facts: DomainFacts, primaryDomain: boolean) {
  const admin = serviceClient();
  const domain = normalizeDomain(hostname);
  if (!domain) throw new Error("INVALID_DOMAIN");
  const status = facts.allReady ? "ready" : !facts.ownershipVerified ? "verification_required" : !facts.dnsConfigured ? "dns_pending" : !facts.tlsReady ? "tls_pending" : !facts.routingReady ? "routing_pending" : "unhealthy";
  const now = new Date().toISOString();
  if (primaryDomain) {
    const { error: clearError } = await admin.from("pandora_project_domains").update({ primary_domain: false }).eq("organization_id", context.organizationId).eq("project_id", projectId).eq("primary_domain", true).neq("domain", domain);
    if (clearError) throw new Error("BACKEND_WRITE_FAILED");
  }
  const payload = {
    provider: "vercel", environment, provider_project_id: providerProjectId, status, verified: facts.allReady, primary_domain: primaryDomain,
    verification: facts.verification, ownership_verified: facts.ownershipVerified, dns_configured: facts.dnsConfigured, tls_ready: facts.tlsReady,
    routing_ready: facts.routingReady, runtime_healthy: facts.runtimeHealthy, provider_payload: { httpStatus: facts.httpStatus }, last_checked_at: now, failed_at: null,
  };
  const { data: existing, error: existingError } = await admin.from("pandora_project_domains").select("id").eq("organization_id", context.organizationId).eq("project_id", projectId).eq("domain", domain).maybeSingle();
  if (existingError) throw new Error("BACKEND_READ_FAILED");
  if (existing) {
    const { data, error } = await admin.from("pandora_project_domains").update(payload).eq("id", existing.id).select("id, domain, status, verified, primary_domain, ownership_verified, dns_configured, tls_ready, routing_ready, runtime_healthy, last_checked_at").single();
    if (error || !data) throw new Error("BACKEND_WRITE_FAILED");
    return data;
  }
  const { data, error } = await admin.from("pandora_project_domains").insert({ organization_id: context.organizationId, project_id: projectId, domain, ...payload }).select("id, domain, status, verified, primary_domain, ownership_verified, dns_configured, tls_ready, routing_ready, runtime_healthy, last_checked_at").single();
  if (error || !data) throw new Error("BACKEND_WRITE_FAILED");
  return data;
}

async function attachProjectDomain(context: UserContext, identifier: string, body: JsonRecord) {
  const project = await projectByIdentifier(context, identifier);
  const projectId = textValue(project.id);
  const hostname = normalizeDomain(body.hostname);
  const targetEnvironment = textValue(body.targetEnvironment || body.environment).toLowerCase();
  const deploymentId = textValue(body.deploymentId);
  const idempotencyRef = textValue(body.idempotencyKey);
  const authorizationRef = textValue(body.authorizationRef);
  if (!hostname || !new Set(["preview", "production"]).has(targetEnvironment) || !UUID_RE.test(deploymentId) || idempotencyRef.length < 8 || idempotencyRef.length > 200 || authorizationRef.length < 8 || authorizationRef.length > 300) throw new Error("INVALID_DOMAIN_REQUEST");
  const admin = serviceClient();
  const { data: deploymentData, error: deploymentError } = await admin.from("pandora_project_deployments")
    .select("id, version_id, provider_project_id, provider_deployment_id, artifact_digest, source_commit_sha, verification_state, environment")
    .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("id", deploymentId).eq("environment", targetEnvironment).maybeSingle();
  if (deploymentError) throw new Error("BACKEND_READ_FAILED");
  if (!deploymentData) throw new Error("DOMAIN_DEPLOYMENT_REQUIRED");
  const deployment = asRecord(deploymentData);
  const providerProjectId = textValue(deployment.provider_project_id);
  const providerDeploymentId = textValue(deployment.provider_deployment_id);
  if (!/^prj_[A-Za-z0-9]+$/.test(providerProjectId) || !/^dpl_[A-Za-z0-9]+$/.test(providerDeploymentId)) throw new Error("PROVIDER_LINEAGE_MISMATCH");
  const operationKey = await sha256Hex(["attach_domain", context.organizationId, projectId, deploymentId, hostname, targetEnvironment, authorizationRef, idempotencyRef].join("|"));
  const operation = { idempotency_key: operationKey, action: "attach_domain", organization_id: context.organizationId, project_id: projectId, project_version_id: deployment.version_id, environment: targetEnvironment, provider: "vercel", authorization_ref: authorizationRef, verification_ref: textValue(deployment.verification_state) === "live_verified" ? `deployment:${deploymentId}` : null, provider_project_id: providerProjectId, provider_resource_id: providerDeploymentId, status: "claimed" };
  const { data: claimed, error: claimError } = await admin.from("pandora_runtime_operations").insert(operation).select("id").single();
  if (claimError) {
    if (claimError.code !== "23505") throw new Error("DOMAIN_CLAIM_FAILED");
    const { data: existing, error } = await admin.from("pandora_runtime_operations").select("id, status").eq("provider", "vercel").eq("idempotency_key", operationKey).maybeSingle();
    if (error || !existing) throw new Error("DOMAIN_CLAIM_FAILED");
    if (existing.status === "succeeded") {
      const facts = await inspectVercelDomainFacts(providerProjectId, hostname);
      return { domain: await saveDomainFacts(context, projectId, providerProjectId, hostname, targetEnvironment, facts, targetEnvironment === "production"), facts, reconciled: true };
    }
    if (existing.status === "uncertain") throw new Error("DOMAIN_RECONCILIATION_REQUIRED");
    throw new Error("DOMAIN_IN_PROGRESS");
  }
  const operationId = textValue(claimed.id);
  await admin.from("pandora_runtime_operations").update({ status: "running", started_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", operationId);
  try {
    try {
      await vercelRequest(`/v10/projects/${encodeURIComponent(providerProjectId)}/domains`, { method: "POST", body: JSON.stringify({ name: hostname }) }, [200, 201]);
    } catch {
      try { await vercelRequest(`/v9/projects/${encodeURIComponent(providerProjectId)}/domains/${encodeURIComponent(hostname)}`, { method: "GET" }, [200]); }
      catch {
        await admin.from("pandora_runtime_operations").update({ status: "uncertain", ambiguous: true, normalized_error: { code: "domain_reconciliation_required" }, updated_at: new Date().toISOString() }).eq("id", operationId);
        throw new Error("DOMAIN_RECONCILIATION_REQUIRED");
      }
    }
    const facts = await inspectVercelDomainFacts(providerProjectId, hostname);
    const domainRow = await saveDomainFacts(context, projectId, providerProjectId, hostname, targetEnvironment, facts, targetEnvironment === "production");
    const now = new Date().toISOString();
    await admin.from("pandora_runtime_operations").update({ status: "succeeded", ambiguous: false, result_facts: { hostname, deploymentId, providerDeploymentId, ...facts }, finished_at: now, last_reconciled_at: now, updated_at: now }).eq("id", operationId);
    const config = asRecord(project.config); const journey = asRecord(config.customerJourney);
    const nextConfig = { ...config, customerJourney: { ...journey, requestedDomain: hostname, domainStatus: domainRow.status, runtimeUpdatedAt: now } };
    await admin.from("projectos_projects").update({ config: nextConfig, updated_at: now }).eq("organization_id", context.organizationId).eq("id", projectId);
    return { domain: domainRow, facts };
  } catch (error) {
    if (error instanceof Error && error.message === "DOMAIN_RECONCILIATION_REQUIRED") throw error;
    await admin.from("pandora_runtime_operations").update({ status: "failed", normalized_error: { code: error instanceof Error ? error.message : "domain_failed" }, finished_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", operationId);
    throw error;
  }
}

async function inspectProjectDomain(context: UserContext, identifier: string, hostnameValue: string) {
  const project = await projectByIdentifier(context, identifier);
  const projectId = textValue(project.id);
  const hostname = normalizeDomain(hostnameValue);
  if (!hostname) throw new Error("INVALID_DOMAIN");
  const admin = serviceClient();
  const { data: domainData, error } = await admin.from("pandora_project_domains").select("environment, provider_project_id, primary_domain").eq("organization_id", context.organizationId).eq("project_id", projectId).eq("domain", hostname).maybeSingle();
  if (error) throw new Error("BACKEND_READ_FAILED");
  if (!domainData) throw new Error("DOMAIN_NOT_FOUND");
  const providerProjectId = textValue(domainData.provider_project_id);
  const facts = await inspectVercelDomainFacts(providerProjectId, hostname);
  const domain = await saveDomainFacts(context, projectId, providerProjectId, hostname, textValue(domainData.environment, "production"), facts, domainData.primary_domain === true);
  return { domain, facts };
}

async function rollbackProject(context: UserContext, identifier: string, body: JsonRecord) {
  const project = await projectByIdentifier(context, identifier);
  const projectId = textValue(project.id);
  const targetVersionId = textValue(body.targetVersionId);
  const expectedProductionVersionId = textValue(body.expectedProductionVersionId);
  const idempotencyRef = textValue(body.idempotencyKey);
  const authorizationRef = textValue(body.authorizationRef);
  if (!UUID_RE.test(targetVersionId) || !UUID_RE.test(expectedProductionVersionId) || targetVersionId === expectedProductionVersionId || idempotencyRef.length < 8 || authorizationRef.length < 8) throw new Error("INVALID_ROLLBACK_REQUEST");
  const admin = serviceClient();
  const { data: environmentData, error: environmentError } = await admin.from("pandora_runtime_environments").select("id, current_version_id, current_deployment_id, provider_project_id").eq("organization_id", context.organizationId).eq("project_id", projectId).eq("environment", "production").maybeSingle();
  if (environmentError) throw new Error("BACKEND_READ_FAILED");
  if (!environmentData || textValue(environmentData.current_version_id) !== expectedProductionVersionId) throw new Error("PRODUCTION_PRECONDITION_MISMATCH");
  const providerProjectId = textValue(environmentData.provider_project_id);
  const { data: targetVersionData, error: targetVersionError } = await admin.from("pandora_project_versions").select("id, rollback_eligible, source_sha256, source_kind, source_ref, source_commit, artifact_digest_sha256, project_spec_id, build_job_id").eq("organization_id", context.organizationId).eq("project_id", projectId).eq("id", targetVersionId).maybeSingle();
  if (targetVersionError) throw new Error("BACKEND_READ_FAILED");
  if (!targetVersionData || targetVersionData.rollback_eligible !== true) throw new Error("ROLLBACK_TARGET_NOT_ELIGIBLE");
  const targetVersion = asRecord(targetVersionData);
  const { data: targetDeploymentData, error: targetDeploymentError } = await admin.from("pandora_project_deployments")
    .select("id, provider_project_id, provider_deployment_id, url, immutable_url, artifact_digest, source_commit_sha, source_sha256, verification_state, metadata, created_at")
    .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("version_id", targetVersionId).eq("environment", "production").eq("verification_state", "live_verified").order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (targetDeploymentError) throw new Error("BACKEND_READ_FAILED");
  if (!targetDeploymentData) throw new Error("ROLLBACK_TARGET_NOT_VERIFIED");
  const targetDeployment = asRecord(targetDeploymentData);
  const providerDeploymentId = textValue(targetDeployment.provider_deployment_id);
  const targetSource = projectSourceIdentity(targetVersionId, targetVersion.source_kind, targetVersion.source_ref, targetVersion.source_commit);
  const targetMetadata = asRecord(targetDeployment.metadata);
  const deploymentCommit = textValue(targetDeployment.source_commit_sha) || null;
  const metadataKind = textValue(targetMetadata.sourceKind).toLowerCase();
  const metadataRef = textValue(targetMetadata.sourceRef).toLowerCase();
  const deploymentSourceExact = targetSource.sourceKind === "git_commit"
    ? deploymentCommit === targetSource.sourceCommit && (!metadataKind || metadataKind === targetSource.sourceKind) && (!metadataRef || metadataRef === targetSource.sourceRef)
    : deploymentCommit === null && metadataKind === targetSource.sourceKind && metadataRef === targetSource.sourceRef;
  if (textValue(targetDeployment.provider_project_id) !== providerProjectId || !/^dpl_[A-Za-z0-9]+$/.test(providerDeploymentId) || textValue(targetDeployment.artifact_digest) !== textValue(targetVersion.artifact_digest_sha256) || !deploymentSourceExact) throw new Error("PROVIDER_LINEAGE_MISMATCH");
  const operationKey = await sha256Hex(["rollback", context.organizationId, projectId, expectedProductionVersionId, targetVersionId, providerDeploymentId, authorizationRef, idempotencyRef].join("|"));
  const { data: claimed, error: claimError } = await admin.from("pandora_runtime_operations").insert({ idempotency_key: operationKey, action: "rollback", organization_id: context.organizationId, project_id: projectId, project_version_id: targetVersionId, environment: "production", provider: "vercel", authorization_ref: authorizationRef, verification_ref: `previous-live:${targetDeployment.id}`, provider_project_id: providerProjectId, provider_resource_id: providerDeploymentId, status: "claimed" }).select("id").single();
  if (claimError) {
    if (claimError.code !== "23505") throw new Error("ROLLBACK_CLAIM_FAILED");
    const { data: existing, error } = await admin.from("pandora_runtime_operations").select("id,status").eq("provider", "vercel").eq("idempotency_key", operationKey).maybeSingle();
    if (error || !existing) throw new Error("ROLLBACK_CLAIM_FAILED");
    if (existing.status === "succeeded") return runtimeSummary(context, projectId);
    if (existing.status === "uncertain") throw new Error("ROLLBACK_RECONCILIATION_REQUIRED");
    throw new Error("ROLLBACK_IN_PROGRESS");
  }
  const operationId = textValue(claimed.id);
  await admin.from("pandora_runtime_operations").update({ status: "running", started_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", operationId);
  try {
    try { await vercelRequest(`/v1/projects/${encodeURIComponent(providerProjectId)}/rollback/${encodeURIComponent(providerDeploymentId)}`, { method: "POST" }, [200, 201, 202, 204]); }
    catch { /* read back the production target before deciding ambiguity */ }
    const providerProject = await vercelRequest(`/v9/projects/${encodeURIComponent(providerProjectId)}`, { method: "GET" }, [200]);
    const productionTarget = asRecord(asRecord(providerProject.targets).production);
    if (textValue(productionTarget.id) !== providerDeploymentId) {
      await admin.from("pandora_runtime_operations").update({ status: "uncertain", ambiguous: true, normalized_error: { code: "rollback_reconciliation_required" }, updated_at: new Date().toISOString() }).eq("id", operationId);
      throw new Error("ROLLBACK_RECONCILIATION_REQUIRED");
    }
    const now = new Date().toISOString();
    const { data: rollbackRow, error: rollbackRowError } = await admin.from("pandora_project_deployments").insert({
      organization_id: context.organizationId, project_id: projectId, version_id: targetVersionId, provider: "vercel", environment: "production", provider_project_id: providerProjectId,
      provider_deployment_id: providerDeploymentId, url: targetDeployment.url, status: "ready_for_verification", source_sha256: targetDeployment.source_sha256,
      artifact_digest: targetDeployment.artifact_digest, source_commit_sha: targetDeployment.source_commit_sha, authorization_ref: authorizationRef, verification_ref: null,
      idempotency_key: operationKey, provider_state: "READY", immutable_url: targetDeployment.immutable_url ?? targetDeployment.url, promoted_from_id: environmentData.current_deployment_id,
      verification_state: "ready_for_verification", ready_at: now, last_provider_check_at: now, metadata: { rollback: true, rolledBackFromVersionId: expectedProductionVersionId, priorVerifiedDeploymentId: targetDeployment.id, sourceKind: targetSource.sourceKind, sourceRef: targetSource.sourceRef },
    }).select("id,version_id,provider_deployment_id,url,verification_state").single();
    if (rollbackRowError || !rollbackRow) throw new Error("BACKEND_WRITE_FAILED");
    const { data: updatedEnvironment, error: updateEnvironmentError } = await admin.from("pandora_runtime_environments")
      .update({ current_version_id: targetVersionId, current_deployment_id: rollbackRow.id, status: "ready", verification_state: "ready_for_verification", last_reconciled_at: now, updated_at: now })
      .eq("id", environmentData.id).eq("current_version_id", expectedProductionVersionId).select("id").maybeSingle();
    if (updateEnvironmentError || !updatedEnvironment) throw new Error("PRODUCTION_PRECONDITION_MISMATCH");
    await admin.from("pandora_project_versions").update({ lifecycle_status: "rolled_back", rolled_back_at: now, rollback_eligible: true }).eq("organization_id", context.organizationId).eq("project_id", projectId).eq("id", targetVersionId);
    const config = asRecord(project.config); const journey = asRecord(config.customerJourney); const nextConfig = { ...config, customerJourney: { ...journey, stage: "publishing", runtimeStatus: "verifying", productionCandidateUrl: rollbackRow.url, publishedVersionId: targetVersionId, productionVerificationState: "ready_for_verification", runtimeUpdatedAt: now } };
    await admin.from("projectos_projects").update({ config: nextConfig, updated_at: now }).eq("organization_id", context.organizationId).eq("id", projectId);
    await admin.from("pandora_runtime_operations").update({ status: "succeeded", ambiguous: false, result_facts: { targetVersionId, providerDeploymentId, sourceKind: targetSource.sourceKind, sourceRef: targetSource.sourceRef, verificationState: "ready_for_verification" }, finished_at: now, last_reconciled_at: now, updated_at: now }).eq("id", operationId);
    return { project: projectResponse({ ...project, config: nextConfig }), production: rollbackRow, verificationState: "ready_for_verification" };
  } catch (error) {
    if (error instanceof Error && error.message === "ROLLBACK_RECONCILIATION_REQUIRED") throw error;
    await admin.from("pandora_runtime_operations").update({ status: "failed", normalized_error: { code: error instanceof Error ? error.message : "rollback_failed" }, finished_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", operationId);
    throw error;
  }
}

async function reconcileProjectRuntime(context: UserContext, identifier: string) {
  const project = await projectByIdentifier(context, identifier);
  const projectId = textValue(project.id);
  const admin = serviceClient();
  const { data: deploymentsData, error: deploymentsError } = await admin.from("pandora_project_deployments")
    .select("id, environment, provider_deployment_id, provider_state, status, verification_state")
    .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("provider", "vercel").order("created_at", { ascending: false }).limit(50);
  if (deploymentsError) throw new Error("BACKEND_READ_FAILED");
  let deploymentUpdates = 0;
  for (const raw of deploymentsData ?? []) {
    const row = asRecord(raw); const deploymentId = textValue(row.provider_deployment_id);
    if (!/^dpl_[A-Za-z0-9]+$/.test(deploymentId)) continue;
    if (textValue(row.verification_state) === "live_verified" && textValue(row.status) === "ready") continue;
    try {
      const provider = await vercelRequest(`/v13/deployments/${encodeURIComponent(deploymentId)}`, { method: "GET" }, [200]);
      const state = textValue(provider.readyState ?? provider.status).toUpperCase();
      const failed = new Set(["ERROR", "CANCELED"]).has(state); const ready = state === "READY";
      const nextVerification = textValue(row.verification_state) === "live_verified" ? "live_verified" : ready ? "ready_for_verification" : failed ? "failed" : "not_verified";
      const nextStatus = textValue(row.verification_state) === "live_verified" && ready ? "ready" : ready ? "ready_for_verification" : failed ? "failed" : state.toLowerCase();
      const now = new Date().toISOString();
      const { error } = await admin.from("pandora_project_deployments").update({ provider_state: state, status: nextStatus, verification_state: nextVerification, last_provider_check_at: now, ready_at: ready ? now : null, failed_at: failed ? now : null, updated_at: now }).eq("id", row.id);
      if (!error) deploymentUpdates++;
    } catch { /* keep durable last-known state; next reconciliation will retry */ }
  }

  const { data: operationsData } = await admin.from("pandora_runtime_operations").select("id, action, idempotency_key, provider_project_id, provider_resource_id, status")
    .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("provider", "vercel").in("status", ["running", "uncertain"]).order("updated_at", { ascending: true }).limit(20);
  let operationUpdates = 0;
  for (const raw of operationsData ?? []) {
    const op = asRecord(raw); const providerProjectId = textValue(op.provider_project_id); let providerResourceId = textValue(op.provider_resource_id);
    try {
      if (textValue(op.action) === "create_preview" && !providerResourceId && /^prj_[A-Za-z0-9]+$/.test(providerProjectId)) {
        const found = await findVercelDeploymentByOperation(providerProjectId, textValue(op.idempotency_key)); providerResourceId = textValue(found.id ?? found.uid);
      }
      if (!/^dpl_[A-Za-z0-9]+$/.test(providerResourceId)) continue;
      const provider = await vercelRequest(`/v13/deployments/${encodeURIComponent(providerResourceId)}`, { method: "GET" }, [200]);
      const state = textValue(provider.readyState ?? provider.status).toUpperCase();
      if (["READY", "ERROR", "CANCELED"].includes(state)) {
        const success = state === "READY";
        const now = new Date().toISOString();
        await admin.from("pandora_runtime_operations").update({ status: success ? "succeeded" : "failed", ambiguous: false, provider_resource_id: providerResourceId, normalized_error: success ? {} : { code: `provider_${state.toLowerCase()}` }, last_reconciled_at: now, finished_at: now, updated_at: now }).eq("id", op.id);
        operationUpdates++;
      }
    } catch { /* bounded reconciliation: preserve uncertain state */ }
  }

  const { data: domainsData } = await admin.from("pandora_project_domains").select("domain, environment, provider_project_id, primary_domain").eq("organization_id", context.organizationId).eq("project_id", projectId).eq("provider", "vercel").limit(20);
  let domainUpdates = 0;
  for (const raw of domainsData ?? []) {
    const row = asRecord(raw); const providerProjectId = textValue(row.provider_project_id); const hostname = textValue(row.domain);
    if (!providerProjectId || !hostname) continue;
    try { const facts = await inspectVercelDomainFacts(providerProjectId, hostname); await saveDomainFacts(context, projectId, providerProjectId, hostname, textValue(row.environment, "production"), facts, row.primary_domain === true); domainUpdates++; } catch { /* retry later */ }
  }
  const now = new Date().toISOString();
  const { data: processedEvents } = await admin.from("pandora_runtime_provider_events").update({ status: "processed", processed_at: now }).eq("organization_id", context.organizationId).eq("project_id", projectId).eq("status", "received").select("id");
  return { projectId, deploymentUpdates, operationUpdates, domainUpdates, providerEventsProcessed: processedEvents?.length ?? 0, reconciledAt: now };
}

async function runtimeSummary(context: UserContext, identifier: string) {
  const project = await projectByIdentifier(context, identifier);
  const projectId = textValue(project.id);
  const admin = serviceClient();
  const [preview, production, domain, candidate] = await Promise.all([
    admin.from("pandora_project_deployments").select("id, version_id, environment, provider_deployment_id, url, status, source_sha256, artifact_digest, source_commit_sha, created_at").eq("organization_id", context.organizationId).eq("project_id", projectId).eq("environment", "preview").order("created_at", { ascending: false }).limit(1).maybeSingle(),
    admin.from("pandora_project_deployments").select("id, version_id, environment, provider_deployment_id, url, status, source_sha256, artifact_digest, source_commit_sha, created_at").eq("organization_id", context.organizationId).eq("project_id", projectId).eq("environment", "production").order("created_at", { ascending: false }).limit(1).maybeSingle(),
    admin.from("pandora_project_domains").select("id, domain, status, verified, primary_domain, verification, updated_at").eq("organization_id", context.organizationId).eq("project_id", projectId).eq("primary_domain", true).limit(1).maybeSingle(),
    admin.from("pandora_project_versions").select("id, artifact_digest_sha256, lifecycle_status, created_at").eq("organization_id", context.organizationId).eq("project_id", projectId).not("root_artifact_version_id", "is", null).not("artifact_digest_sha256", "is", null).in("lifecycle_status", ["built", "verification_pending", "verified", "preview_ready"]).order("created_at", { ascending: false }).limit(1).maybeSingle(),
  ]);
  if (preview.error || production.error || domain.error || candidate.error) throw new Error("BACKEND_READ_FAILED");

  let verificationState = "not_checked_yet";
  let publishEligible = false;
  let verificationCheckedAt: string | null = null;
  let verificationVersionId: string | null = null;
  if (preview.data) {
    const previewRow = asRecord(preview.data);
    const versionId = textValue(previewRow.version_id);
    verificationVersionId = versionId || null;
    if (versionId) {
      const { data: versionData, error: versionError } = await admin.from("pandora_project_versions")
        .select("id, project_spec_id, build_job_id, source_sha256, source_kind, source_ref, source_commit, artifact_digest_sha256, migration_set_digest_sha256, runtime_target_digest_sha256, verification_run_id, lifecycle_status, created_at")
        .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("id", versionId).maybeSingle();
      if (versionError) throw new Error("BACKEND_READ_FAILED");
      const version = asRecord(versionData);
      const boundVerificationId = textValue(version.verification_run_id);
      let verificationQuery = admin.from("pandora_verification_runs")
        .select("id, project_spec_id, project_version_id, build_job_id, source_kind, source_ref, source_commit, source_digest, artifact_digest, migration_set_digest, runtime_target_digest, preview_deployment_id, target_environment, status, completed_at, created_at")
        .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("project_version_id", versionId);
      verificationQuery = boundVerificationId
        ? verificationQuery.eq("id", boundVerificationId)
        : verificationQuery.order("created_at", { ascending: false }).limit(1);
      const { data: verificationData, error: verificationError } = await verificationQuery.maybeSingle();
      if (verificationError) throw new Error("BACKEND_READ_FAILED");
      if (verificationData) {
        const verification = asRecord(verificationData);
        const status = textValue(verification.status).toUpperCase();
        verificationCheckedAt = textValue(verification.completed_at) || textValue(verification.created_at) || null;
        if (new Set(["PENDING", "RUNNING", "QUEUED"]).has(status)) {
          verificationState = "checking";
        } else if (status === "PASS") {
          const completedAt = Date.parse(textValue(verification.completed_at));
          const versionCreatedAt = Date.parse(textValue(version.created_at));
          const previewCreatedAt = Date.parse(textValue(previewRow.created_at));
          let sourceIdentityExact = false;
          try {
            const versionSource = projectSourceIdentity(versionId, version.source_kind, version.source_ref, version.source_commit);
            const verificationSource = projectSourceIdentity(versionId, verification.source_kind, verification.source_ref, verification.source_commit);
            sourceIdentityExact = versionSource.sourceKind === verificationSource.sourceKind && versionSource.sourceRef === verificationSource.sourceRef && versionSource.sourceCommit === verificationSource.sourceCommit;
          } catch { sourceIdentityExact = false; }
          const exact = Boolean(
            textValue(version.project_spec_id) &&
            textValue(version.build_job_id) &&
            sourceIdentityExact &&
            textValue(version.artifact_digest_sha256) &&
            textValue(previewRow.provider_deployment_id) &&
            textValue(verification.project_spec_id) === textValue(version.project_spec_id) &&
            textValue(verification.project_version_id) === versionId &&
            textValue(verification.build_job_id) === textValue(version.build_job_id) &&
            textValue(verification.source_digest) === textValue(version.source_sha256) &&
            textValue(verification.artifact_digest) === textValue(version.artifact_digest_sha256) &&
            textValue(verification.migration_set_digest) === textValue(version.migration_set_digest_sha256) &&
            textValue(verification.runtime_target_digest) === textValue(version.runtime_target_digest_sha256) &&
            textValue(verification.preview_deployment_id) === textValue(previewRow.provider_deployment_id) &&
            textValue(verification.target_environment) === "preview" &&
            Number.isFinite(completedAt) && Number.isFinite(versionCreatedAt) && Number.isFinite(previewCreatedAt) &&
            completedAt >= Math.max(versionCreatedAt, previewCreatedAt)
          );
          verificationState = exact ? "verified" : "needs_attention";
          publishEligible = exact;
        } else {
          verificationState = "needs_attention";
        }
      } else if (textValue(version.lifecycle_status) === "verification_pending") {
        verificationState = "checking";
      }
    }
  }

  return {
    project: projectResponse(project),
    preview: preview.data || null,
    production: production.data || null,
    domain: domain.data || null,
    candidate: candidate.data ? { versionId: candidate.data.id, artifactDigest: candidate.data.artifact_digest_sha256, status: candidate.data.lifecycle_status } : null,
    verification: {
      state: verificationState,
      publishEligible,
      versionId: verificationVersionId,
      checkedAt: verificationCheckedAt,
    },
  };
}


async function createPreview(context: UserContext, identifier: string, body: JsonRecord) {
  let project = await projectByIdentifier(context, identifier);
  const projectId = textValue(project.id);
  const versionId = textValue(body.versionId);
  const requestedArtifactDigest = textValue(body.artifactDigest).toLowerCase();
  const idempotencyRef = textValue(body.idempotencyKey);
  const authorizationRef = `owner:${context.userId}`;
  if (!UUID_RE.test(versionId) || !SHA256_RE.test(requestedArtifactDigest) || idempotencyRef.length < 8 || idempotencyRef.length > 200) throw new Error("EXACT_VERSION_REQUIRED");

  const bundle = await loadExactRuntimeBundle(context, projectId, versionId, requestedArtifactDigest);
  const operationKey = await sha256Hex(["create_preview", context.organizationId, projectId, versionId, bundle.artifactDigest, bundle.sourceKind, bundle.sourceRef, bundle.sourceCommit ?? "no-commit", authorizationRef, idempotencyRef].join("|"));
  const admin = serviceClient();
  let operationId = "";
  const operationRecord = {
    idempotency_key: operationKey,
    action: "create_preview",
    organization_id: context.organizationId,
    project_id: projectId,
    project_version_id: versionId,
    environment: "preview",
    provider: "vercel",
    authorization_ref: authorizationRef,
    provider_project_id: null,
    status: "claimed",
  };
  const { data: claimed, error: claimError } = await admin.from("pandora_runtime_operations").insert(operationRecord).select("id").single();
  if (claimError) {
    if (claimError.code !== "23505") throw new Error("PREVIEW_CLAIM_FAILED");
    const { data: existing, error: existingError } = await admin.from("pandora_runtime_operations")
      .select("id, status, provider_resource_id, result_facts").eq("provider", "vercel").eq("idempotency_key", operationKey).maybeSingle();
    if (existingError || !existing) throw new Error("PREVIEW_CLAIM_FAILED");
    const status = textValue(existing.status);
    if (status === "succeeded") {
      const { data: prior, error: priorError } = await admin.from("pandora_project_deployments")
        .select("id, version_id, environment, provider_deployment_id, url, status, source_sha256, artifact_digest, source_commit_sha, verification_state, created_at")
        .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("version_id", versionId).eq("environment", "preview").eq("idempotency_key", operationKey).maybeSingle();
      if (priorError || !prior) throw new Error("PREVIEW_RECONCILIATION_REQUIRED");
      return { project: projectResponse(project), version: bundle.version, deployment: prior, previewUrl: prior.url ?? null, reconciled: true };
    }
    if (new Set(["claimed", "running"]).has(status)) throw new Error("PREVIEW_IN_PROGRESS");
    if (!new Set(["failed", "uncertain"]).has(status)) throw new Error("PREVIEW_RECONCILIATION_REQUIRED");
    const { data: reclaimed, error: reclaimError } = await admin.from("pandora_runtime_operations")
      .update({ status: "claimed", ambiguous: false, normalized_error: {}, result_facts: {}, claimed_at: new Date().toISOString(), started_at: null, finished_at: null, updated_at: new Date().toISOString() })
      .eq("id", existing.id).eq("status", status).select("id").maybeSingle();
    if (reclaimError || !reclaimed) throw new Error("PREVIEW_CLAIM_FAILED");
    operationId = textValue(reclaimed.id);
  } else operationId = textValue(claimed.id);

  const provider = await ensureVercelProject(context, project);
  project = { ...project, config: provider.config };
  await admin.from("pandora_runtime_operations").update({ status: "running", provider_project_id: provider.id, started_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", operationId);

  let deployment: JsonRecord;
  try {
    deployment = await createVercelDeployment(provider, bundle, versionId, operationKey, authorizationRef);
  } catch (error) {
    const code = error instanceof Error ? error.message : "PROJECT_RUNTIME_ERROR";
    if (code === "PREVIEW_RECONCILIATION_REQUIRED") {
      await admin.from("pandora_runtime_operations").update({ status: "uncertain", ambiguous: true, normalized_error: { code: "reconciliation_required" }, updated_at: new Date().toISOString() }).eq("id", operationId);
    } else {
      await admin.from("pandora_runtime_operations").update({ status: "failed", ambiguous: false, normalized_error: { code }, finished_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", operationId);
    }
    throw error;
  }

  const providerDeploymentId = textValue(deployment.id ?? deployment.uid);
  if (!providerDeploymentId) throw new Error("VERCEL_DEPLOYMENT_INVALID");
  const rawUrl = textValue(deployment.url);
  const previewUrl = rawUrl ? `https://${rawUrl.replace(/^https?:\/\//, "")}` : null;
  const providerState = textValue(deployment.readyState ?? deployment.status, "QUEUED").toUpperCase();
  const terminalFailure = new Set(["ERROR", "CANCELED"]).has(providerState);
  const ready = providerState === "READY";
  const status = ready ? "ready_for_verification" : terminalFailure ? "failed" : providerState.toLowerCase();
  const verificationState = ready ? "ready_for_verification" : terminalFailure ? "failed" : "not_verified";
  const now = new Date().toISOString();
  const { data: deploymentRow, error: deploymentError } = await admin.from("pandora_project_deployments")
    .insert({
      organization_id: context.organizationId, project_id: projectId, version_id: versionId, provider: "vercel", environment: "preview",
      provider_project_id: provider.id, provider_deployment_id: providerDeploymentId, url: previewUrl, status, source_sha256: bundle.sourceDigest,
      artifact_digest: bundle.artifactDigest, source_commit_sha: bundle.sourceCommit, authorization_ref: authorizationRef, idempotency_key: operationKey,
      provider_state: providerState, immutable_url: previewUrl, last_provider_check_at: now, ready_at: ready ? now : null, failed_at: terminalFailure ? now : null,
      verification_state: verificationState,
      metadata: { providerName: provider.name, pandoraOperationId: operationKey, rootArtifactVersionId: textValue(bundle.version.root_artifact_version_id), projectSpecId: bundle.projectSpecId, buildJobId: bundle.buildJobId },
    })
    .select("id, version_id, environment, provider_deployment_id, url, status, source_sha256, artifact_digest, source_commit_sha, verification_state, created_at").single();
  if (deploymentError || !deploymentRow) throw new Error("BACKEND_WRITE_FAILED");

  const environmentStatus = terminalFailure ? "failed" : ready ? "ready" : "provisioning";
  const { error: environmentError } = await admin.from("pandora_runtime_environments").upsert({
    organization_id: context.organizationId, project_id: projectId, environment: "preview", provider: "vercel", provider_project_id: provider.id,
    status: environmentStatus, current_version_id: versionId, current_deployment_id: deploymentRow.id, verification_state: verificationState, last_reconciled_at: now, updated_at: now,
  }, { onConflict: "project_id,environment" });
  if (environmentError) throw new Error("BACKEND_WRITE_FAILED");

  const nextLifecycle = terminalFailure ? "rejected" : "verification_pending";
  const { error: versionUpdateError } = await admin.from("pandora_project_versions").update({ lifecycle_status: nextLifecycle }).eq("organization_id", context.organizationId).eq("project_id", projectId).eq("id", versionId);
  if (versionUpdateError) throw new Error("BACKEND_WRITE_FAILED");

  const config = asRecord(project.config);
  const journey = asRecord(config.customerJourney);
  const nextConfig = { ...config, customerJourney: { ...journey, stage: ready ? "preview_ready" : terminalFailure ? "needs_attention" : "building", runtimeStatus: ready ? "verifying" : terminalFailure ? "failed" : "working", previewUrl, previewVersionId: versionId, previewDeploymentId: providerDeploymentId, previewVerificationState: verificationState, runtimeUpdatedAt: now } };
  const { error: projectError } = await admin.from("projectos_projects").update({ config: nextConfig, updated_at: now }).eq("organization_id", context.organizationId).eq("id", projectId);
  if (projectError) throw new Error("BACKEND_WRITE_FAILED");
  await admin.from("pandora_runtime_operations").update({ status: terminalFailure ? "failed" : "succeeded", ambiguous: false, provider_resource_id: providerDeploymentId, result_facts: { projectVersionId: versionId, providerDeploymentId, artifactDigest: bundle.artifactDigest, sourceCommit: bundle.sourceCommit, verificationState }, finished_at: now, last_reconciled_at: now, updated_at: now }).eq("id", operationId);
  return { project: projectResponse({ ...project, config: nextConfig }), version: bundle.version, deployment: deploymentRow, previewUrl, verificationState };
}

async function publishProject(context: UserContext, identifier: string, body: JsonRecord) {
  let project = await projectByIdentifier(context, identifier);
  const projectId = textValue(project.id);
  const requestedVersion = textValue(body.versionId);
  if (!requestedVersion) throw new Error("VERSION_REQUIRED");
  if (!Object.prototype.hasOwnProperty.call(body, "expectedProductionVersionId")) throw new Error("PRODUCTION_PRECONDITION_REQUIRED");
  const expectedProductionVersionId = body.expectedProductionVersionId == null ? null : textValue(body.expectedProductionVersionId);
  if (body.expectedProductionVersionId != null && !expectedProductionVersionId) throw new Error("INVALID_PRODUCTION_PRECONDITION");
  if (!SUPABASE_SERVICE_ROLE_KEY) throw new Error("RUNTIME_BROKER_NOT_CONFIGURED");
  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

  const { data: versionData, error: versionError } = await admin.from("pandora_project_versions")
    .select("id, source_sha256, project_spec_id, build_job_id, source_kind, source_ref, source_commit, artifact_digest_sha256, migration_set_digest_sha256, runtime_target_digest_sha256, verification_run_id, lifecycle_status, created_at")
    .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("id", requestedVersion).maybeSingle();
  if (versionError) throw new Error("BACKEND_READ_FAILED");
  if (!versionData) throw new Error("PREVIEW_REQUIRED");
  const version = asRecord(versionData);
  const sourceDigest = textValue(version.source_sha256).toLowerCase();
  const projectSpecId = textValue(version.project_spec_id);
  const buildJobId = textValue(version.build_job_id);
  const { sourceKind, sourceRef, sourceCommit } = projectSourceIdentity(requestedVersion, version.source_kind, version.source_ref, version.source_commit);
  const artifactDigest = textValue(version.artifact_digest_sha256).toLowerCase();
  if (!SHA256_RE.test(sourceDigest) || !UUID_RE.test(projectSpecId) || !UUID_RE.test(buildJobId) || !SHA256_RE.test(artifactDigest)) throw new Error("VERIFICATION_REQUIRED");

  const { data: previewData, error: previewError } = await admin.from("pandora_project_deployments")
    .select("id, version_id, provider_project_id, provider_deployment_id, url, status, source_sha256, artifact_digest, source_commit_sha, created_at")
    .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("environment", "preview").eq("version_id", requestedVersion)
    .order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (previewError) throw new Error("BACKEND_READ_FAILED");
  if (!previewData) throw new Error("PREVIEW_REQUIRED");
  const preview = asRecord(previewData);
  const previewDeploymentId = textValue(preview.provider_deployment_id);
  const previewStatus = textValue(preview.status).toLowerCase();
  if (!previewDeploymentId || !new Set(["ready", "ready_for_verification"]).has(previewStatus)) throw new Error("PREVIEW_NOT_READY");
  if (textValue(preview.source_sha256) !== sourceDigest) throw new Error("VERSION_SOURCE_MISMATCH");
  if (textValue(preview.artifact_digest) && textValue(preview.artifact_digest) !== artifactDigest) throw new Error("VERIFICATION_IDENTITY_MISMATCH");
  if ((textValue(preview.source_commit_sha) || null) !== sourceCommit) throw new Error("VERIFICATION_IDENTITY_MISMATCH");

  let verificationQuery = admin.from("pandora_verification_runs")
    .select("id, project_spec_id, project_version_id, build_job_id, source_kind, source_ref, source_commit, source_digest, artifact_digest, migration_set_digest, runtime_target_digest, preview_deployment_id, target_environment, status, completed_at, created_at")
    .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("project_version_id", requestedVersion);
  const boundVerificationId = textValue(version.verification_run_id);
  verificationQuery = boundVerificationId
    ? verificationQuery.eq("id", boundVerificationId)
    : verificationQuery.order("completed_at", { ascending: false, nullsFirst: false }).limit(1);
  const { data: verificationData, error: verificationError } = await verificationQuery.maybeSingle();
  if (verificationError) throw new Error("BACKEND_READ_FAILED");
  if (!verificationData) throw new Error("VERIFICATION_REQUIRED");
  const verification = asRecord(verificationData);
  if (textValue(verification.status).toUpperCase() !== "PASS") throw new Error("VERIFICATION_REQUIRED");
  if (textValue(verification.target_environment) !== "preview") throw new Error("VERIFICATION_IDENTITY_MISMATCH");
  if (textValue(verification.project_spec_id) !== projectSpecId || textValue(verification.project_version_id) !== requestedVersion ||
      textValue(verification.build_job_id) !== buildJobId || textValue(verification.source_kind) !== sourceKind || textValue(verification.source_ref) !== sourceRef ||
      (textValue(verification.source_commit) || null) !== sourceCommit || textValue(verification.source_digest) !== sourceDigest || textValue(verification.artifact_digest) !== artifactDigest ||
      textValue(verification.migration_set_digest) !== textValue(version.migration_set_digest_sha256) ||
      textValue(verification.runtime_target_digest) !== textValue(version.runtime_target_digest_sha256) ||
      textValue(verification.preview_deployment_id) !== previewDeploymentId) throw new Error("VERIFICATION_IDENTITY_MISMATCH");
  const completedAt = Date.parse(textValue(verification.completed_at));
  const versionCreatedAt = Date.parse(textValue(version.created_at));
  const previewCreatedAt = Date.parse(textValue(preview.created_at));
  if (!Number.isFinite(completedAt) || !Number.isFinite(versionCreatedAt) || !Number.isFinite(previewCreatedAt) || completedAt < Math.max(versionCreatedAt, previewCreatedAt)) throw new Error("VERIFICATION_STALE");

  const { data: currentEnvironment, error: environmentError } = await admin.from("pandora_runtime_environments")
    .select("id, current_version_id, current_deployment_id").eq("organization_id", context.organizationId).eq("project_id", projectId).eq("environment", "production").maybeSingle();
  if (environmentError) throw new Error("BACKEND_READ_FAILED");
  const { data: latestProduction, error: productionReadError } = await admin.from("pandora_project_deployments")
    .select("id, version_id, provider_deployment_id, url, status, created_at").eq("organization_id", context.organizationId).eq("project_id", projectId)
    .eq("environment", "production").order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (productionReadError) throw new Error("BACKEND_READ_FAILED");
  const currentVersionId = currentEnvironment?.current_version_id == null ? (latestProduction?.version_id == null ? null : textValue(latestProduction.version_id)) : textValue(currentEnvironment.current_version_id);
  if (currentVersionId !== expectedProductionVersionId) throw new Error("PRODUCTION_PRECONDITION_MISMATCH");

  const provider = await ensureVercelProject(context, project);
  project = { ...project, config: provider.config };
  const providerProjectId = textValue(preview.provider_project_id) || provider.id;
  if (providerProjectId !== provider.id) throw new Error("PROVIDER_LINEAGE_MISMATCH");
  const domain = normalizeDomain(body.domain);
  const operationKey = await sha256Hex(["publish_version", context.organizationId, projectId, requestedVersion, textValue(verification.id), expectedProductionVersionId ?? "empty", domain ?? "no-domain"].join("|"));
  const operationRecord = { idempotency_key: operationKey, action: "publish_version", organization_id: context.organizationId, project_id: projectId, project_version_id: requestedVersion, environment: "production", provider: "vercel", authorization_ref: `owner:${context.userId}`, verification_ref: textValue(verification.id), provider_project_id: provider.id, status: "claimed" };
  let operationId = "";
  const { data: claimed, error: claimError } = await admin.from("pandora_runtime_operations").insert(operationRecord).select("id").single();
  if (claimError) {
    if (claimError.code !== "23505") throw new Error("PUBLISH_CLAIM_FAILED");
    const { data: existingOperation, error: existingError } = await admin.from("pandora_runtime_operations")
      .select("id, status, result_facts").eq("provider", "vercel").eq("idempotency_key", operationKey).maybeSingle();
    if (existingError || !existingOperation) throw new Error("PUBLISH_CLAIM_FAILED");
    const existingStatus = textValue(existingOperation.status);
    if (existingStatus === "succeeded") {
      const snapshot = await runtimeSummary(context, projectId);
      if (textValue(asRecord(snapshot.production).version_id) !== requestedVersion) throw new Error("PUBLISH_RECONCILIATION_REQUIRED");
      return { project: snapshot.project, production: snapshot.production, domain: snapshot.domain, liveUrl: asRecord(snapshot.project).liveUrl ?? null, domainVerified: asRecord(snapshot.domain).verified === true };
    }
    if (existingStatus === "uncertain") throw new Error("PUBLISH_RECONCILIATION_REQUIRED");
    if (new Set(["claimed", "running"]).has(existingStatus)) throw new Error("PUBLISH_IN_PROGRESS");
    const { data: reclaimed, error: reclaimError } = await admin.from("pandora_runtime_operations")
      .update({ status: "claimed", ambiguous: false, normalized_error: {}, result_facts: {}, claimed_at: new Date().toISOString(), started_at: null, finished_at: null, updated_at: new Date().toISOString() })
      .eq("id", existingOperation.id).eq("status", "failed").select("id").maybeSingle();
    if (reclaimError || !reclaimed) throw new Error("PUBLISH_CLAIM_FAILED");
    operationId = textValue(reclaimed.id);
  } else operationId = textValue(claimed.id);
  await admin.from("pandora_runtime_operations").update({ status: "running", started_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", operationId);

  let providerMutationStarted = false;
  try {
    const beforePromotion = await vercelRequest(`/v13/deployments/${encodeURIComponent(previewDeploymentId)}`, { method: "GET" }, [200]);
    if (textValue(beforePromotion.id ?? beforePromotion.uid) !== previewDeploymentId) throw new Error("PROVIDER_LINEAGE_MISMATCH");
    if (textValue(beforePromotion.readyState ?? beforePromotion.status).toUpperCase() !== "READY") throw new Error("PREVIEW_NOT_READY");
    if (textValue(beforePromotion.target).toLowerCase() === "production") throw new Error("PRODUCTION_PRECONDITION_MISMATCH");
    providerMutationStarted = true;
    try {
      await vercelRequest(`/v10/projects/${encodeURIComponent(provider.id)}/promote/${encodeURIComponent(previewDeploymentId)}`, {
        method: "POST", body: JSON.stringify({ meta: { pandoraProjectVersionId: requestedVersion, pandoraVerificationRunId: textValue(verification.id) } }),
      }, [200, 201]);
    } catch (promotionError) {
      const reconciled = await vercelRequest(`/v13/deployments/${encodeURIComponent(previewDeploymentId)}`, { method: "GET" }, [200]);
      if (textValue(reconciled.target).toLowerCase() !== "production") throw promotionError;
    }
    const deployment = await vercelRequest(`/v13/deployments/${encodeURIComponent(previewDeploymentId)}`, { method: "GET" }, [200]);
    if (textValue(deployment.id ?? deployment.uid) !== previewDeploymentId || textValue(deployment.target).toLowerCase() !== "production" || textValue(deployment.readyState ?? deployment.status).toUpperCase() !== "READY") throw new Error("PRODUCTION_PROMOTION_NOT_CONFIRMED");
    const providerState = textValue(deployment.readyState ?? deployment.status, "pending");
    const rawUrl = textValue(deployment.url) || textValue(preview.url);
    const deploymentUrl = rawUrl ? `https://${rawUrl.replace(/^https?:\/\//, "")}` : null;
    const status = providerState.toLowerCase();

    const { data: productionRow, error: productionError } = await admin.from("pandora_project_deployments").insert({
      organization_id: context.organizationId, project_id: projectId, version_id: requestedVersion, provider: "vercel", environment: "production",
      provider_project_id: provider.id, provider_deployment_id: previewDeploymentId, url: deploymentUrl, status, source_sha256: sourceDigest,
      promoted_from_id: preview.id, artifact_digest: artifactDigest, source_commit_sha: sourceCommit, verification_ref: textValue(verification.id), verification_state: "ready_for_verification",
      provider_state: providerState, immutable_url: deploymentUrl, metadata: { providerName: provider.name, promotionOnly: true, previewVerificationRunId: textValue(verification.id), productionVerificationRunId: null, sourceKind, sourceRef },
    }).select("id, version_id, environment, provider_deployment_id, url, status, source_sha256, verification_state, created_at").single();
    if (productionError || !productionRow) throw new Error("BACKEND_WRITE_FAILED");

    if (currentEnvironment) {
      let environmentUpdate = admin.from("pandora_runtime_environments")
        .update({ current_version_id: requestedVersion, current_deployment_id: productionRow.id, status: "ready", verification_state: "ready_for_verification", last_reconciled_at: new Date().toISOString(), updated_at: new Date().toISOString() })
        .eq("id", currentEnvironment.id);
      environmentUpdate = expectedProductionVersionId == null ? environmentUpdate.is("current_version_id", null) : environmentUpdate.eq("current_version_id", expectedProductionVersionId);
      const { data: updatedEnvironment, error: environmentUpdateError } = await environmentUpdate.select("id").maybeSingle();
      if (environmentUpdateError || !updatedEnvironment) throw new Error("PRODUCTION_PRECONDITION_MISMATCH");
    } else {
      const { error: environmentInsertError } = await admin.from("pandora_runtime_environments").insert({ organization_id: context.organizationId, project_id: projectId, environment: "production", provider: "vercel", provider_project_id: provider.id, status: "ready", current_version_id: requestedVersion, current_deployment_id: productionRow.id, verification_state: "ready_for_verification", last_reconciled_at: new Date().toISOString() });
      if (environmentInsertError) throw new Error("PRODUCTION_PRECONDITION_MISMATCH");
    }

    if (currentVersionId) await admin.from("pandora_project_versions").update({ rollback_eligible: true }).eq("organization_id", context.organizationId).eq("project_id", projectId).eq("id", currentVersionId);
    const { error: versionPromoteError } = await admin.from("pandora_project_versions")
      .update({ lifecycle_status: "production_candidate", promoted_at: new Date().toISOString(), rollback_eligible: true, verification_run_id: textValue(verification.id) })
      .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("id", requestedVersion);
    if (versionPromoteError) throw new Error("BACKEND_WRITE_FAILED");

    let domainRow: JsonRecord | null = null;
    let domainStatus: string | null = null;
    let domainVerified = false;
    if (domain) {
      const { data: existingDomain, error: existingDomainError } = await admin.from("pandora_project_domains").select("id, domain, status, verified, primary_domain, verification, updated_at").eq("organization_id", context.organizationId).eq("project_id", projectId).eq("domain", domain).maybeSingle();
      if (existingDomainError) throw new Error("BACKEND_READ_FAILED");
      const providerDomain = existingDomain ? asRecord(existingDomain) : await vercelRequest(`/v10/projects/${encodeURIComponent(provider.id)}/domains`, { method: "POST", body: JSON.stringify({ name: domain }) }, [200, 201]);
      domainVerified = providerDomain.verified === true;
      domainStatus = domainVerified ? "verified" : "verification_required";
      const { error: clearPrimaryError } = await admin.from("pandora_project_domains").update({ primary_domain: false, updated_at: new Date().toISOString() }).eq("organization_id", context.organizationId).eq("project_id", projectId).eq("primary_domain", true).neq("domain", domain);
      if (clearPrimaryError) throw new Error("BACKEND_WRITE_FAILED");
      const { data: savedDomain, error: domainError } = await admin.from("pandora_project_domains")
        .upsert({ organization_id: context.organizationId, project_id: projectId, provider: "vercel", environment: "production", provider_project_id: provider.id, domain, status: domainStatus, verified: domainVerified, primary_domain: true, verification: Array.isArray(providerDomain.verification) ? providerDomain.verification : [], ownership_verified: domainVerified, updated_at: new Date().toISOString() }, { onConflict: "project_id,domain" })
        .select("id, domain, status, verified, primary_domain, verification, updated_at").single();
      if (domainError || !savedDomain) throw new Error("BACKEND_WRITE_FAILED");
      domainRow = asRecord(savedDomain);
    }

    const config = asRecord(project.config);
    const journey = asRecord(config.customerJourney);
    const productionCandidateUrl = domain && domainVerified ? `https://${domain}` : deploymentUrl;
    const previousLiveUrl = textValue(journey.liveUrl) || null;
    const nextConfig = { ...config, customerJourney: { ...journey, stage: "publishing", runtimeStatus: "verifying", liveUrl: previousLiveUrl, productionCandidateUrl, productionDeploymentId: previewDeploymentId, publishedVersionId: requestedVersion, requestedDomain: domain, domainStatus, productionVerificationState: "ready_for_verification", runtimeUpdatedAt: new Date().toISOString() } };
    const { error: projectError } = await admin.from("projectos_projects").update({ config: nextConfig, updated_at: new Date().toISOString() }).eq("organization_id", context.organizationId).eq("id", projectId);
    if (projectError) throw new Error("BACKEND_WRITE_FAILED");
    await admin.from("pandora_runtime_operations").update({ status: "succeeded", ambiguous: false, provider_resource_id: previewDeploymentId, result_facts: { projectVersionId: requestedVersion, providerDeploymentId: previewDeploymentId, previewVerificationRunId: textValue(verification.id), promotedFromDeploymentId: previewDeploymentId, sourceKind, sourceRef, verificationState: "ready_for_verification" }, finished_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", operationId);
    return { project: projectResponse({ ...project, config: nextConfig }), production: productionRow, domain: domainRow, liveUrl: previousLiveUrl, productionCandidateUrl, domainVerified, verificationState: "ready_for_verification" };
  } catch (error) {
    const code = error instanceof Error ? error.message : "PROJECT_RUNTIME_ERROR";
    if (providerMutationStarted) {
      await admin.from("pandora_runtime_operations").update({ status: "uncertain", ambiguous: true, normalized_error: { code: "reconciliation_required" }, updated_at: new Date().toISOString() }).eq("id", operationId);
      throw new Error("PUBLISH_RECONCILIATION_REQUIRED");
    } else {
      await admin.from("pandora_runtime_operations").update({ status: "failed", ambiguous: false, normalized_error: { code }, finished_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", operationId);
    }
    throw error;
  }
}

async function finalizeProductionVerification(context: UserContext, identifier: string, body: JsonRecord) {
  const project = await projectByIdentifier(context, identifier);
  const projectId = textValue(project.id);
  const requestedVersion = textValue(body.versionId);
  const verificationRunId = textValue(body.verificationRunId);
  if (!requestedVersion) throw new Error("VERSION_REQUIRED");
  if (!verificationRunId) throw new Error("VERIFICATION_REQUIRED");
  const admin = serviceClient();

  const { data: environmentData, error: environmentError } = await admin.from("pandora_runtime_environments")
    .select("id, current_version_id, current_deployment_id, verification_state")
    .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("environment", "production").maybeSingle();
  if (environmentError) throw new Error("BACKEND_READ_FAILED");
  const environment = asRecord(environmentData);
  if (textValue(environment.current_version_id) !== requestedVersion || textValue(environment.verification_state) !== "ready_for_verification") throw new Error("PRODUCTION_PRECONDITION_MISMATCH");
  const productionRowId = textValue(environment.current_deployment_id);
  if (!productionRowId) throw new Error("PRODUCTION_PRECONDITION_MISMATCH");

  const { data: deploymentData, error: deploymentError } = await admin.from("pandora_project_deployments")
    .select("id, version_id, provider_deployment_id, url, verification_state, created_at, metadata")
    .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("environment", "production").eq("id", productionRowId).eq("version_id", requestedVersion).maybeSingle();
  if (deploymentError) throw new Error("BACKEND_READ_FAILED");
  if (!deploymentData) throw new Error("PRODUCTION_PRECONDITION_MISMATCH");
  const deployment = asRecord(deploymentData);
  if (textValue(deployment.verification_state) !== "ready_for_verification") throw new Error("PRODUCTION_PRECONDITION_MISMATCH");
  const providerDeploymentId = textValue(deployment.provider_deployment_id);
  if (!providerDeploymentId) throw new Error("PROVIDER_LINEAGE_MISMATCH");

  const { data: versionData, error: versionError } = await admin.from("pandora_project_versions")
    .select("id, project_spec_id, build_job_id, source_kind, source_ref, source_commit, source_sha256, artifact_digest_sha256, migration_set_digest_sha256, runtime_target_digest_sha256, created_at")
    .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("id", requestedVersion).maybeSingle();
  if (versionError) throw new Error("BACKEND_READ_FAILED");
  if (!versionData) throw new Error("VERIFICATION_REQUIRED");
  const version = asRecord(versionData);

  const { data: verificationData, error: verificationError } = await admin.from("pandora_verification_runs")
    .select("id, project_spec_id, project_version_id, build_job_id, source_kind, source_ref, source_commit, source_digest, artifact_digest, migration_set_digest, runtime_target_digest, preview_deployment_id, target_environment, required_check_profile, status, completed_at")
    .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("project_version_id", requestedVersion).eq("id", verificationRunId).maybeSingle();
  if (verificationError) throw new Error("BACKEND_READ_FAILED");
  if (!verificationData) throw new Error("VERIFICATION_REQUIRED");
  const verification = asRecord(verificationData);
  if (textValue(verification.status).toUpperCase() !== "PASS" || textValue(verification.target_environment) !== "production" || textValue(verification.required_check_profile) !== "production_release") throw new Error("VERIFICATION_REQUIRED");
  const versionSource = projectSourceIdentity(requestedVersion, version.source_kind, version.source_ref, version.source_commit);
  const verificationSource = projectSourceIdentity(requestedVersion, verification.source_kind, verification.source_ref, verification.source_commit);
  if (textValue(verification.project_spec_id) !== textValue(version.project_spec_id) || textValue(verification.project_version_id) !== requestedVersion ||
      textValue(verification.build_job_id) !== textValue(version.build_job_id) || verificationSource.sourceKind !== versionSource.sourceKind || verificationSource.sourceRef !== versionSource.sourceRef || verificationSource.sourceCommit !== versionSource.sourceCommit ||
      textValue(verification.source_digest) !== textValue(version.source_sha256) || textValue(verification.artifact_digest) !== textValue(version.artifact_digest_sha256) ||
      textValue(verification.migration_set_digest) !== textValue(version.migration_set_digest_sha256) || textValue(verification.runtime_target_digest) !== textValue(version.runtime_target_digest_sha256) ||
      textValue(verification.preview_deployment_id) !== providerDeploymentId) throw new Error("VERIFICATION_IDENTITY_MISMATCH");
  const completedAt = Date.parse(textValue(verification.completed_at));
  const deploymentCreatedAt = Date.parse(textValue(deployment.created_at));
  if (!Number.isFinite(completedAt) || !Number.isFinite(deploymentCreatedAt) || completedAt < deploymentCreatedAt) throw new Error("VERIFICATION_STALE");

  const metadata = asRecord(deployment.metadata);
  const now = new Date().toISOString();
  const { data: deploymentUpdated, error: deploymentUpdateError } = await admin.from("pandora_project_deployments")
    .update({ verification_state: "live_verified", verification_ref: verificationRunId, metadata: { ...metadata, productionVerificationRunId: verificationRunId, sourceKind: versionSource.sourceKind, sourceRef: versionSource.sourceRef }, last_provider_check_at: now, updated_at: now })
    .eq("id", productionRowId).eq("verification_state", "ready_for_verification").select("id").maybeSingle();
  if (deploymentUpdateError || !deploymentUpdated) throw new Error("PRODUCTION_PRECONDITION_MISMATCH");
  const { data: environmentUpdated, error: environmentUpdateError } = await admin.from("pandora_runtime_environments")
    .update({ verification_state: "live_verified", status: "ready", last_reconciled_at: now, updated_at: now })
    .eq("id", environment.id).eq("current_version_id", requestedVersion).eq("current_deployment_id", productionRowId).eq("verification_state", "ready_for_verification").select("id").maybeSingle();
  if (environmentUpdateError || !environmentUpdated) throw new Error("PRODUCTION_PRECONDITION_MISMATCH");
  const { data: versionUpdated, error: versionUpdateError } = await admin.from("pandora_project_versions")
    .update({ lifecycle_status: "live", rollback_eligible: true, verification_run_id: verificationRunId })
    .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("id", requestedVersion).eq("lifecycle_status", "production_candidate").select("id").maybeSingle();
  if (versionUpdateError || !versionUpdated) throw new Error("PRODUCTION_PRECONDITION_MISMATCH");

  const { data: domainData, error: domainError } = await admin.from("pandora_project_domains")
    .select("domain, ownership_verified, dns_configured, tls_ready, routing_ready, runtime_healthy")
    .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("environment", "production").eq("primary_domain", true).limit(1).maybeSingle();
  if (domainError) throw new Error("BACKEND_READ_FAILED");
  const domain = asRecord(domainData);
  const domainReady = domain.ownership_verified === true && domain.dns_configured === true && domain.tls_ready === true && domain.routing_ready === true && domain.runtime_healthy === true;
  const deploymentUrl = textValue(deployment.url) || null;
  const liveUrl = domainReady && textValue(domain.domain) ? `https://${textValue(domain.domain)}` : deploymentUrl;
  const config = asRecord(project.config);
  const journey = asRecord(config.customerJourney);
  const nextConfig = { ...config, customerJourney: { ...journey, stage: "live", runtimeStatus: "ready", liveUrl, productionCandidateUrl: null, productionVerificationState: "live_verified", productionVerificationRunId: verificationRunId, runtimeUpdatedAt: now } };
  const { error: projectError } = await admin.from("projectos_projects").update({ config: nextConfig, updated_at: now }).eq("organization_id", context.organizationId).eq("id", projectId);
  if (projectError) throw new Error("BACKEND_WRITE_FAILED");
  return { project: projectResponse({ ...project, config: nextConfig }), production: { ...deploymentData, verification_state: "live_verified" }, liveUrl, verificationRunId };
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const origin = allowedOrigin(req);
  if (origin === "") return jsonResponse({ code: "ORIGIN_NOT_ALLOWED", plainMessage: "That app is not allowed to use this service.", requestId }, 403, requestId);
  if (req.method === "OPTIONS") return jsonResponse(null, 204, requestId, origin);
  if (!["GET", "POST"].includes(req.method)) return jsonResponse({ code: "METHOD_NOT_ALLOWED", plainMessage: "That action is not available.", requestId }, 405, requestId, origin);

  try {
    const context = await authenticate(req);
    await enforceRateLimit(context, req.method);
    const route = routePath(new URL(req.url).pathname);
    if (req.method === "POST" && route === "/projects") return jsonResponse({ project: await createProject(context, await bodyJson(req)) }, 201, requestId, origin);
    const runtimeMatch = route.match(/^\/projects\/([^/]+)\/runtime$/);
    if (req.method === "GET" && runtimeMatch) return jsonResponse(await runtimeSummary(context, decodeURIComponent(runtimeMatch[1])), 200, requestId, origin);
    const previewMatch = route.match(/^\/projects\/([^/]+)\/previews$/);
    if (req.method === "POST" && previewMatch) return jsonResponse(await createPreview(context, decodeURIComponent(previewMatch[1]), await bodyJson(req)), 201, requestId, origin);
    const publishMatch = route.match(/^\/projects\/([^/]+)\/publish$/);
    if (req.method === "POST" && publishMatch) return jsonResponse(await publishProject(context, decodeURIComponent(publishMatch[1]), await bodyJson(req)), 201, requestId, origin);
    const productionVerificationMatch = route.match(/^\/projects\/([^/]+)\/production-verification$/);
    if (req.method === "POST" && productionVerificationMatch) return jsonResponse(await finalizeProductionVerification(context, decodeURIComponent(productionVerificationMatch[1]), await bodyJson(req)), 200, requestId, origin);
    return jsonResponse({ code: "PROJECT_RUNTIME_ROUTE_NOT_FOUND", plainMessage: "That project action is not available yet.", requestId }, 404, requestId, origin);
  } catch (error) {
    const code = error instanceof Error ? error.message : "PROJECT_RUNTIME_ERROR";
    const invalid = new Set(["INVALID_JSON", "BODY_TOO_LARGE", "INVALID_PROJECT_NAME", "INVALID_OBJECTIVE", "INVALID_BUILD_KIND", "INVALID_DOMAIN", "VERSION_REQUIRED", "INVALID_PRODUCTION_PRECONDITION", "EXACT_VERSION_REQUIRED", "ARTIFACT_FILE_BASE64_INVALID", "ARTIFACT_FILE_BASE64_NON_CANONICAL", "ARTIFACT_FILE_PATH_INVALID", "ARTIFACT_BUNDLE_JSON_INVALID", "ARTIFACT_BUNDLE_SCHEMA_UNSUPPORTED", "ARTIFACT_BUNDLE_FILES_INVALID", "INVALID_DOMAIN_REQUEST", "INVALID_ROLLBACK_REQUEST"]);
    const conflicts = new Set(["PREVIEW_REQUIRED", "PREVIEW_NOT_READY", "VERSION_SOURCE_INVALID", "VERSION_SOURCE_MISMATCH", "PRODUCTION_PRECONDITION_REQUIRED", "PRODUCTION_PRECONDITION_MISMATCH", "VERIFICATION_REQUIRED", "VERIFICATION_IDENTITY_MISMATCH", "VERIFICATION_STALE", "PROVIDER_LINEAGE_MISMATCH", "PRODUCTION_PROMOTION_NOT_CONFIRMED", "VERCEL_CONFLICT", "VERCEL_DOMAIN_REJECTED", "ARTIFACT_LINEAGE_INCOMPLETE", "ARTIFACT_NOT_FOUND", "ARTIFACT_DIGEST_MISMATCH", "ARTIFACT_STORAGE_INVALID", "ARTIFACT_STORAGE_READ_FAILED", "ARTIFACT_KIND_NOT_DEPLOYABLE", "ARTIFACT_PROVENANCE_MISMATCH", "ARTIFACT_BUNDLE_SIZE_INVALID", "ARTIFACT_BUNDLE_DIGEST_MISMATCH", "ARTIFACT_BUNDLE_LINEAGE_MISMATCH", "ARTIFACT_FILES_NOT_CANONICAL", "ARTIFACT_FILE_ENCODING_UNSUPPORTED", "ARTIFACT_FILE_TOO_LARGE", "ARTIFACT_FILES_TOTAL_TOO_LARGE", "ARTIFACT_FILE_DIGEST_MISMATCH", "ARTIFACT_FILE_SIZE_MISMATCH", "ARTIFACT_ENTRYPOINT_MISSING", "DOMAIN_DEPLOYMENT_REQUIRED", "DOMAIN_NOT_FOUND", "ROLLBACK_TARGET_NOT_ELIGIBLE", "ROLLBACK_TARGET_NOT_VERIFIED"]);
    if (code === "SIGN_IN_REQUIRED") return jsonResponse({ code, plainMessage: "Please sign in again.", requestId }, 401, requestId, origin);
    if (["ORGANIZATION_ACCESS_REQUIRED", "OWNER_ROLE_REQUIRED"].includes(code)) return jsonResponse({ code, plainMessage: "You do not have permission for this project.", requestId }, 403, requestId, origin);
    if (code === "ORGANIZATION_SELECTION_REQUIRED") return jsonResponse({ code, plainMessage: "Choose which organization you want to use.", requestId }, 409, requestId, origin);
    if (code === "RATE_LIMITED") return jsonResponse({ code, plainMessage: "Please wait a moment before trying again.", requestId }, 429, requestId, origin);
    if (invalid.has(code)) return jsonResponse({ code, plainMessage: "Check that project information and try again.", requestId }, 400, requestId, origin);
    if (code === "PROJECT_NOT_FOUND") return jsonResponse({ code, plainMessage: "Pandora could not find that project.", requestId }, 404, requestId, origin);
    if (code === "DOMAIN_IN_PROGRESS") return jsonResponse({ code, plainMessage: "Pandora is already attaching that domain.", requestId }, 409, requestId, origin);
    if (code === "DOMAIN_RECONCILIATION_REQUIRED") return jsonResponse({ code, plainMessage: "Pandora is confirming the domain with Vercel. Do not attach it again yet.", requestId }, 409, requestId, origin);
    if (code === "ROLLBACK_IN_PROGRESS") return jsonResponse({ code, plainMessage: "Pandora is already rolling back this project.", requestId }, 409, requestId, origin);
    if (code === "ROLLBACK_RECONCILIATION_REQUIRED") return jsonResponse({ code, plainMessage: "Pandora is confirming the production rollback. Do not roll back again yet.", requestId }, 409, requestId, origin);
    if (code === "PREVIEW_IN_PROGRESS") return jsonResponse({ code, plainMessage: "Pandora is already creating this exact preview.", requestId }, 409, requestId, origin);
    if (code === "PREVIEW_RECONCILIATION_REQUIRED") return jsonResponse({ code, plainMessage: "Pandora is confirming whether that preview was created. Do not create it again yet.", requestId }, 409, requestId, origin);
    if (code === "PUBLISH_IN_PROGRESS") return jsonResponse({ code, plainMessage: "Pandora is already publishing this version.", requestId }, 409, requestId, origin);
    if (code === "PUBLISH_RECONCILIATION_REQUIRED") return jsonResponse({ code, plainMessage: "Pandora is confirming whether that publish completed. Do not publish again yet.", requestId }, 409, requestId, origin);
    if (conflicts.has(code)) return jsonResponse({ code, plainMessage: "That project cannot be published in its current state.", requestId }, 409, requestId, origin);
    if (["RUNTIME_BROKER_NOT_CONFIGURED", "VERCEL_NOT_CONFIGURED", "PUBLISH_CLAIM_FAILED", "PREVIEW_CLAIM_FAILED", "DOMAIN_CLAIM_FAILED", "ROLLBACK_CLAIM_FAILED"].includes(code)) return jsonResponse({ code, plainMessage: "Project publishing is temporarily unavailable.", requestId }, 503, requestId, origin);
    console.error(JSON.stringify({ requestId, code }));
    return jsonResponse({ code: "PROJECT_RUNTIME_UNAVAILABLE", plainMessage: "Pandora cannot reach the project runtime right now.", requestId }, 503, requestId, origin);
  }
});
