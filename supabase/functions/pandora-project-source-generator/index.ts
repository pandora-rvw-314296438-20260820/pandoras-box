
import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const MODEL = Deno.env.get("PANDORA_SOURCE_GENERATION_MODEL") || "gemini-3.5-flash-lite";
const MAX_BODY_BYTES = 4096;
const MAX_FILES = 120;
const MAX_FILE_BYTES = 512 * 1024;
const MAX_SOURCE_BYTES = 4 * 1024 * 1024;
const MAX_BASE_CONTEXT_BYTES = 120 * 1024;
const MIN_STATIC_INDEX_BYTES = 1024;
const BUCKET = "pandora-build-artifacts";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SAFE_PATH = /^(?!\.)(?!.*(?:^|\/)\.\.?(?:\/|$))[A-Za-z0-9_@+.-]+(?:\/[A-Za-z0-9_@+.-]+)*$/;
const SECRET = /(?:AIza[0-9A-Za-z_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|(?:api[_-]?key|secret|password|authorization)\s*[:=]\s*["'][^"']{12,}["'])/i;
type JsonRecord = Record<string, unknown>;

function rec(value: unknown): JsonRecord { return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {}; }
function text(value: unknown) { return typeof value === "string" ? value.trim() : ""; }
function exactKeys(value: JsonRecord, expected: string[]) { const actual = Object.keys(value).sort(); const wanted = [...expected].sort(); return actual.length === wanted.length && actual.every((key, i) => key === wanted[i]); }
function response(body: unknown, status = 200) { return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store, max-age=0", "x-content-type-options": "nosniff" } }); }
function adminClient() { if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error("SERVICE_UNAVAILABLE"); return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } }); }
function userClient(authorization: string) { if (!SUPABASE_URL || !SUPABASE_ANON_KEY) throw new Error("SERVICE_UNAVAILABLE"); return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false }, global: { headers: { Authorization: authorization } } }); }
async function sha256Bytes(bytes: Uint8Array) { const digest = await crypto.subtle.digest("SHA-256", bytes); return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join(""); }
async function sha256Text(value: string) { return sha256Bytes(new TextEncoder().encode(value)); }
function base64(bytes: Uint8Array) { let binary = ""; for (const b of bytes) binary += String.fromCharCode(b); return btoa(binary); }
function decodeBase64(value: string) { const binary = atob(value); const bytes = new Uint8Array(binary.length); for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i); return bytes; }

async function readBody(req: Request) {
  const declared = Number(req.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) throw new Error("INVALID_REQUEST");
  const raw = await req.text();
  if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) throw new Error("INVALID_REQUEST");
  let parsed: unknown; try { parsed = JSON.parse(raw); } catch { throw new Error("INVALID_REQUEST"); }
  const body = rec(parsed);
  if (!exactKeys(body, ["projectId", "idempotencyKey"]) || !UUID.test(text(body.projectId)) || text(body.idempotencyKey).length < 8 || text(body.idempotencyKey).length > 200) throw new Error("INVALID_REQUEST");
  return { projectId: text(body.projectId), idempotencyKey: text(body.idempotencyKey) };
}

function chooseAdapter(spec: JsonRecord) {
  const type = text(spec.project_type);
  const experience = rec(spec.experience_scope);
  const platforms = Array.isArray(experience.platforms) ? experience.platforms.map(text) : [];
  if (type === "website") return "static-web";
  if (type === "mobile_application" || platforms.includes("android") || platforms.includes("ios")) return "flutter-web";
  if (["web_application", "system", "api", "automation", "other"].includes(type)) return "node-vite-web";
  throw new Error("BUILD_TYPE_NOT_SUPPORTED");
}


function sourcePrompt(spec: JsonRecord, project: JsonRecord, adapter: string, priorSource: JsonRecord | null) {
  const contract = adapter === "static-web"
    ? "Create a self-contained production-quality website. index.html is mandatory; keep JavaScript and CSS inline unless additional local files materially improve quality."
    : adapter === "flutter-web"
      ? "Create a complete Flutter project that builds with Flutter stable for web. pubspec.yaml and lib/main.dart are mandatory. Do not require secret environment values to render the preview."
      : "Create a complete Vite web application. package.json, index.html and src/main.* are mandatory. Use only npm packages declared in package.json. Do not require secret environment values to render the preview.";
  return {
    systemInstruction: { parts: [{ text: [
      "You generate the real source files for Pandora from an already-governed ProjectSpec.",
      "Return newline-delimited JSON only. Every physical output line must be one complete JSON object and nothing else.",
      "Begin with exactly {\"type\":\"stream_start\",\"schemaVersion\":1}.",
      "For every source file emit {\"type\":\"file_start\",\"path\":\"relative/path\"}, then one or more {\"type\":\"file_chunk\",\"path\":\"relative/path\",\"content\":\"actual source chunk\"}, then {\"type\":\"file_end\",\"path\":\"relative/path\"}.",
      "Each file_chunk content should be at most 4096 UTF-8 characters. Escape newlines and quotes as valid JSON. Never emit fake code, summaries, reasoning, markdown fences, commentary, or terminal theatre.",
      "Finish with exactly {\"type\":\"done\",\"schemaVersion\":1}.",
      "Do not return credentials, API keys, tokens, .env files, generated binaries, lockfiles, node_modules, build output, or remote secrets.",
      "Use relative POSIX file paths only. Implement the requested experience and acceptance criteria. Never invent measured business results.",
      priorSource
        ? "An exact previously verified source snapshot is supplied. Treat it as the product baseline. Change only what the active ProjectSpec requires while preserving identity, content depth, responsive behavior, accessibility, and working interactions."
        : "Build a complete first working version; never return a loading shell, placeholder, or skeletal page.",
      contract,
    ].join(" ") }] },
    contents: [{ role: "user", parts: [{ text: JSON.stringify({ project: { name: text(project.name), objective: text(project.objective) }, projectSpec: { id: spec.id, projectType: spec.project_type, businessSummary: spec.business_summary, product: spec.product_scope, data: spec.data_scope, integrations: spec.integration_scope, experience: spec.experience_scope, deployment: spec.deployment_scope, acceptance: spec.acceptance_scope }, existingVerifiedSource: priorSource, buildAdapter: adapter }) }] }],
    generationConfig: { responseMimeType: "text/plain", temperature: 0.2, maxOutputTokens: 32768 },
  };
}

type StreamAssembler = {
  streamId: string;
  organizationId: string;
  projectId: string;
  currentPath: string | null;
  files: Map<string, string[]>;
  fileBytes: Map<string, number>;
  totalBytes: number;
  pending: JsonRecord[];
  done: boolean;
  rollingSecretWindow: string;
};

type StreamProviderMeta = {
  modelVersion: string;
  usage: JsonRecord;
};

function providerChunkText(envelope: JsonRecord) {
  const candidates = Array.isArray(envelope.candidates) ? envelope.candidates as unknown[] : [];
  const parts = Array.isArray(rec(rec(candidates[0]).content).parts) ? rec(rec(candidates[0]).content).parts as unknown[] : [];
  return parts.map((part) => text(rec(part).text)).filter(Boolean).join("");
}

async function flushStreamEvents(admin: ReturnType<typeof adminClient>, state: StreamAssembler, force = false) {
  if (!state.pending.length || (!force && state.pending.length < 6)) return;
  const rows = state.pending.splice(0, state.pending.length);
  const inserted = await admin.from("pandora_build_stream_events").insert(rows);
  if (inserted.error) throw new Error("SOURCE_STREAM_WRITE_FAILED");
}

function queueStreamEvent(state: StreamAssembler, eventType: string, filePath: string | null = null, contentChunk: string | null = null, safePayload: JsonRecord = {}) {
  state.pending.push({
    stream_id: state.streamId,
    organization_id: state.organizationId,
    project_id: state.projectId,
    event_type: eventType,
    file_path: filePath,
    content_chunk: contentChunk,
    safe_payload: safePayload,
  });
}

async function acceptModelLine(admin: ReturnType<typeof adminClient>, state: StreamAssembler, rawLine: string) {
  const line = rawLine.trim();
  if (!line) return;
  let parsed: unknown;
  try { parsed = JSON.parse(line); } catch { throw new Error("INVALID_GENERATED_SOURCE_STREAM"); }
  const event = rec(parsed);
  const kind = text(event.type);
  if (kind === "stream_start") {
    if (!exactKeys(event, ["type", "schemaVersion"]) || event.schemaVersion !== 1 || state.files.size || state.currentPath || state.done) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    return;
  }
  if (kind === "file_start") {
    if (!exactKeys(event, ["type", "path"]) || state.currentPath || state.done) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    const path = text(event.path);
    if (!SAFE_PATH.test(path) || path.length > 512 || path.startsWith(".env") || path.includes("/.env") || path.includes("node_modules/") || path.startsWith("build/") || path.startsWith("dist/") || path.startsWith(".next/") || state.files.has(path) || state.files.size >= MAX_FILES) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    state.currentPath = path;
    state.files.set(path, []);
    state.fileBytes.set(path, 0);
    queueStreamEvent(state, "file_started", path, null, {});
    await flushStreamEvents(admin, state, true);
    return;
  }
  if (kind === "file_chunk") {
    if (!exactKeys(event, ["type", "path", "content"]) || state.done) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    const path = text(event.path);
    const content = typeof event.content === "string" ? event.content : "";
    if (!content || path !== state.currentPath || !state.files.has(path)) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    const bytes = new TextEncoder().encode(content);
    if (bytes.byteLength > 16384) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    const nextFileBytes = (state.fileBytes.get(path) || 0) + bytes.byteLength;
    const nextTotal = state.totalBytes + bytes.byteLength;
    if (nextFileBytes > MAX_FILE_BYTES || nextTotal > MAX_SOURCE_BYTES) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    const secretWindow = state.rollingSecretWindow + content;
    if (SECRET.test(secretWindow)) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    state.rollingSecretWindow = secretWindow.slice(-1024);
    state.fileBytes.set(path, nextFileBytes);
    state.totalBytes = nextTotal;
    state.files.get(path)!.push(content);
    queueStreamEvent(state, "code_chunk", path, content, { byteSize: bytes.byteLength });
    await flushStreamEvents(admin, state);
    return;
  }
  if (kind === "file_end") {
    if (!exactKeys(event, ["type", "path"]) || state.done) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    const path = text(event.path);
    if (path !== state.currentPath || !state.files.has(path) || (state.fileBytes.get(path) || 0) < 1) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    state.currentPath = null;
    state.rollingSecretWindow = "";
    queueStreamEvent(state, "file_completed", path, null, { byteSize: state.fileBytes.get(path) || 0 });
    await flushStreamEvents(admin, state, true);
    return;
  }
  if (kind === "done") {
    if (!exactKeys(event, ["type", "schemaVersion"]) || event.schemaVersion !== 1 || state.currentPath || !state.files.size || state.done) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    state.done = true;
    queueStreamEvent(state, "generation_completed", null, null, { fileCount: state.files.size, byteSize: state.totalBytes });
    await flushStreamEvents(admin, state, true);
    return;
  }
  throw new Error("INVALID_GENERATED_SOURCE_STREAM");
}

async function streamGeminiSource(admin: ReturnType<typeof adminClient>, providerRequest: JsonRecord, state: StreamAssembler) {
  const credential = await admin.rpc("pandora_gemini_stream_credential_service_20260901");
  if (credential.error || typeof credential.data !== "string" || !credential.data.trim()) throw new Error("PROVIDER_UNAVAILABLE");
  let providerResponse: Response;
  try {
    providerResponse = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(MODEL)}:streamGenerateContent?alt=sse&key=${encodeURIComponent(credential.data.trim())}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(providerRequest),
      signal: AbortSignal.timeout(90000),
    });
  } catch {
    throw new Error("PROVIDER_UNAVAILABLE");
  }
  if (providerResponse.status === 429 || providerResponse.status >= 500) throw new Error("PROVIDER_UNAVAILABLE");
  if (!providerResponse.ok || !providerResponse.body) throw new Error("PROVIDER_REJECTED");

  const reader = providerResponse.body.getReader();
  const decoder = new TextDecoder();
  let sseBuffer = "";
  let modelBuffer = "";
  let rawOutput = "";
  let modelVersion = MODEL;
  let usage: JsonRecord = {};

  const consumeModelText = async (piece: string) => {
    if (!piece) return;
    rawOutput += piece;
    if (new TextEncoder().encode(rawOutput).byteLength > MAX_SOURCE_BYTES * 3) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    modelBuffer += piece;
    for (;;) {
      const newline = modelBuffer.indexOf("\n");
      if (newline < 0) break;
      const line = modelBuffer.slice(0, newline);
      modelBuffer = modelBuffer.slice(newline + 1);
      await acceptModelLine(admin, state, line);
    }
  };

  const consumeSseLine = async (lineValue: string) => {
    const line = lineValue.endsWith("\r") ? lineValue.slice(0, -1) : lineValue;
    if (!line.startsWith("data:")) return;
    const payload = line.slice(5).trim();
    if (!payload || payload === "[DONE]") return;
    let parsed: unknown;
    try { parsed = JSON.parse(payload); } catch { throw new Error("PROVIDER_REJECTED"); }
    const envelope = rec(parsed);
    if (text(envelope.modelVersion)) modelVersion = text(envelope.modelVersion);
    if (Object.keys(rec(envelope.usageMetadata)).length) usage = rec(envelope.usageMetadata);
    await consumeModelText(providerChunkText(envelope));
  };

  for (;;) {
    const chunk = await reader.read();
    if (chunk.done) break;
    sseBuffer += decoder.decode(chunk.value, { stream: true });
    for (;;) {
      const newline = sseBuffer.indexOf("\n");
      if (newline < 0) break;
      const line = sseBuffer.slice(0, newline);
      sseBuffer = sseBuffer.slice(newline + 1);
      await consumeSseLine(line);
    }
  }
  sseBuffer += decoder.decode();
  if (sseBuffer.trim()) await consumeSseLine(sseBuffer.trim());
  if (modelBuffer.trim()) await acceptModelLine(admin, state, modelBuffer);
  await flushStreamEvents(admin, state, true);
  if (!state.done) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
  return { rawOutput, meta: { modelVersion, usage } satisfies StreamProviderMeta };
}

async function canonicalBundle(raw: unknown, projectSpecId: string, adapter: string) {
  const root = rec(raw);
  if (!exactKeys(root, ["schemaVersion", "files"]) || root.schemaVersion !== 1 || !Array.isArray(root.files) || root.files.length < 1 || root.files.length > MAX_FILES) throw new Error("INVALID_GENERATED_SOURCE");
  const seen = new Set<string>(); let total = 0; let staticIndexContent = ""; const files = [] as JsonRecord[];
  for (const value of root.files) {
    const row = rec(value); if (!exactKeys(row, ["path", "content"])) throw new Error("INVALID_GENERATED_SOURCE");
    const path = text(row.path); const content = typeof row.content === "string" ? row.content : "";
    if (adapter === "static-web" && path === "index.html") staticIndexContent = content;
    if (!SAFE_PATH.test(path) || path.length > 512 || path.startsWith(".env") || path.includes("/.env") || path.includes("node_modules/") || path.startsWith("build/") || path.startsWith("dist/") || path.startsWith(".next/") || seen.has(path)) throw new Error("INVALID_GENERATED_SOURCE");
    const bytes = new TextEncoder().encode(content); if (!bytes.length || bytes.length > MAX_FILE_BYTES || SECRET.test(content)) throw new Error("INVALID_GENERATED_SOURCE");
    total += bytes.length; if (total > MAX_SOURCE_BYTES) throw new Error("INVALID_GENERATED_SOURCE"); seen.add(path);
    files.push({ file: path, data: base64(bytes), encoding: "base64", sha256: await sha256Bytes(bytes), byteSize: bytes.length });
  }
  files.sort((a, b) => String(a.file).localeCompare(String(b.file), "en"));
  if (adapter === "static-web") {
    if (!seen.has("index.html")) throw new Error("INVALID_GENERATED_SOURCE");
    const indexBytes = new TextEncoder().encode(staticIndexContent);
    const normalizedIndex = staticIndexContent.replace(/\s+/g, " ").trim();
    if (
      indexBytes.byteLength < MIN_STATIC_INDEX_BYTES ||
      !/<meta[^>]+name=["']viewport["'][^>]*>/i.test(staticIndexContent) ||
      /<body[^>]*>\s*(?:loading(?:\.\.\.)?|coming soon|placeholder)\s*<\/body>/i.test(normalizedIndex)
    ) throw new Error("INVALID_GENERATED_SOURCE");
  }
  if (adapter === "node-vite-web" && (!seen.has("package.json") || !seen.has("index.html") || ![...seen].some((p) => p.startsWith("src/main.")))) throw new Error("INVALID_GENERATED_SOURCE");
  if (adapter === "flutter-web" && (!seen.has("pubspec.yaml") || !seen.has("lib/main.dart"))) throw new Error("INVALID_GENERATED_SOURCE");
  const bundle = { kind: "pandora.source-bundle.v1", schemaVersion: 1, projectSpecId, buildAdapter: adapter, files };
  const bytes = new TextEncoder().encode(JSON.stringify(bundle));
  if (bytes.byteLength > MAX_SOURCE_BYTES * 2) throw new Error("INVALID_GENERATED_SOURCE");
  return { bundle, bytes, sha256: await sha256Bytes(bytes) };
}

async function loadLatestVerifiedSource(
  admin: ReturnType<typeof adminClient>,
  organizationId: string,
  projectId: string,
) {
  const version = await admin.from("pandora_project_versions")
    .select("id,root_artifact_version_id")
    .eq("organization_id", organizationId)
    .eq("project_id", projectId)
    .in("lifecycle_status", ["verified", "preview_ready", "live"])
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (version.error) throw new Error("BASE_SOURCE_READ_FAILED");
  if (!version.data?.root_artifact_version_id) return null;

  const artifact = await admin.from("pandora_artifact_versions")
    .select("id,storage_bucket,storage_path,content_sha256")
    .eq("id", version.data.root_artifact_version_id)
    .eq("organization_id", organizationId)
    .eq("project_id", projectId)
    .maybeSingle();
  if (artifact.error) throw new Error("BASE_SOURCE_READ_FAILED");
  if (!artifact.data?.storage_bucket || !artifact.data?.storage_path) return null;

  const downloaded = await admin.storage
    .from(String(artifact.data.storage_bucket))
    .download(String(artifact.data.storage_path));
  if (downloaded.error || !downloaded.data) {
    throw new Error("BASE_SOURCE_READ_FAILED");
  }
  const raw = await downloaded.data.text();
  if (SECRET.test(raw)) throw new Error("BASE_SOURCE_UNSAFE");
  let parsed: unknown;
  try { parsed = JSON.parse(raw); } catch { throw new Error("BASE_SOURCE_INVALID"); }
  const bundle = rec(parsed);
  const rows = Array.isArray(bundle.files) ? bundle.files : [];
  const prioritized = [...rows].sort((left, right) => {
    const a = text(rec(left).file);
    const b = text(rec(right).file);
    const rank = (path: string) =>
      path === "index.html" ? 0 :
      path === "package.json" || path === "pubspec.yaml" ? 1 :
      path.startsWith("src/main.") || path === "lib/main.dart" ? 2 : 3;
    return rank(a) - rank(b) || a.localeCompare(b, "en");
  });
  let used = 0;
  const files: JsonRecord[] = [];
  for (const value of prioritized) {
    const row = rec(value);
    const path = text(row.file);
    const encoded = text(row.data);
    if (!path || !encoded || text(row.encoding) !== "base64") continue;
    let content = "";
    try {
      content = new TextDecoder("utf-8", { fatal: true })
        .decode(decodeBase64(encoded));
    } catch {
      continue;
    }
    if (SECRET.test(content)) throw new Error("BASE_SOURCE_UNSAFE");
    const bytes = new TextEncoder().encode(content).byteLength;
    if (used + bytes > MAX_BASE_CONTEXT_BYTES) continue;
    used += bytes;
    files.push({ path, content });
  }
  return files.length ? {
    versionId: version.data.id,
    artifactVersionId: version.data.root_artifact_version_id,
    sourceDigest: artifact.data.content_sha256,
    files,
  } : null;
}


async function runGenerationInBackground(input: {
  authorization: string;
  project: JsonRecord;
  spec: JsonRecord;
  requestedBy: string;
  idempotencyKey: string;
  streamId: string;
}) {
  const admin = adminClient();
  const organizationId = text(input.project.organization_id);
  const projectId = text(input.project.id);
  const state: StreamAssembler = {
    streamId: input.streamId,
    organizationId,
    projectId,
    currentPath: null,
    files: new Map<string, string[]>(),
    fileBytes: new Map<string, number>(),
    totalBytes: 0,
    pending: [],
    done: false,
    rollingSecretWindow: "",
  };
  try {
    await admin.from("pandora_build_stream_sessions").update({ status: "streaming", updated_at: new Date().toISOString() }).eq("id", input.streamId);
    queueStreamEvent(state, "stream_started", null, null, { model: MODEL });
    await flushStreamEvents(admin, state, true);

    const adapter = chooseAdapter(input.spec);
    const priorSource = await loadLatestVerifiedSource(admin, organizationId, projectId);
    const providerRequest = sourcePrompt(input.spec, input.project, adapter, priorSource);
    const requestSha = await sha256Text(JSON.stringify(providerRequest));
    const streamed = await streamGeminiSource(admin, providerRequest, state);
    const files = [...state.files.entries()].map(([path, chunks]) => ({ path, content: chunks.join("") }));
    const canonical = await canonicalBundle({ schemaVersion: 1, files }, text(input.spec.id), adapter);
    const responseSha = await sha256Text(streamed.rawOutput);
    const requestId = crypto.randomUUID();
    const usage = streamed.meta.usage;
    const { data: modelRun, error: modelRunError } = await admin.from("pandora_model_runs").insert({
      organization_id: organizationId,
      project_id: projectId,
      project_spec_id: input.spec.id,
      request_id: requestId,
      task: "generate_project_source",
      output_mode: "streamed_source",
      status: "succeeded",
      provider: "gemini",
      model: MODEL,
      model_revision: streamed.meta.modelVersion || MODEL,
      request_sha256: requestSha,
      context_sha256: input.spec.content_sha256,
      response_sha256: responseSha,
      input_tokens: Number(usage.promptTokenCount || 0),
      output_tokens: Number(usage.candidatesTokenCount || 0),
      total_tokens: Number(usage.totalTokenCount || 0),
      started_at: new Date().toISOString(),
      completed_at: new Date().toISOString(),
    }).select("id").single();
    if (modelRunError || !modelRun) throw new Error("MODEL_RUN_WRITE_FAILED");

    await admin.from("pandora_build_stream_sessions").update({ status: "assembling", updated_at: new Date().toISOString() }).eq("id", input.streamId);
    const storagePath = `${organizationId}/${projectId}/${input.spec.id}/${canonical.sha256}.json`;
    const uploaded = await admin.storage.from(BUCKET).upload(storagePath, canonical.bytes, { contentType: "application/json", upsert: false });
    if (uploaded.error && !/already exists|duplicate/i.test(uploaded.error.message || "")) throw new Error("SOURCE_STORAGE_FAILED");

    const { data: intake, error: intakeError } = await admin.rpc("pandora_commit_generated_build_intake_service_20260830", {
      p_organization_id: organizationId,
      p_project_id: projectId,
      p_project_spec_id: input.spec.id,
      p_requested_by: input.requestedBy,
      p_idempotency_key: input.idempotencyKey,
      p_source_sha256: canonical.sha256,
      p_source_byte_size: canonical.bytes.byteLength,
      p_storage_path: storagePath,
      p_model_run_id: modelRun.id,
      p_build_adapter: adapter,
    });
    if (intakeError) throw new Error("BUILD_INTAKE_FAILED");
    const result = rec(intake);
    const buildJobId = text(result.buildJobId);
    const projectVersionId = text(result.projectVersionId);
    if (!UUID.test(buildJobId)) throw new Error("BUILD_INTAKE_FAILED");
    await admin.from("pandora_build_stream_sessions").update({
      status: "building",
      build_job_id: buildJobId,
      project_version_id: UUID.test(projectVersionId) ? projectVersionId : null,
      updated_at: new Date().toISOString(),
    }).eq("id", input.streamId);
    await admin.from("pandora_build_stream_events").insert({
      stream_id: input.streamId,
      organization_id: organizationId,
      project_id: projectId,
      build_job_id: buildJobId,
      event_type: "build_job_created",
      safe_payload: { buildJobId, projectVersionId: UUID.test(projectVersionId) ? projectVersionId : null },
    });

    const currentSteps = await admin.from("pandora_build_job_steps").select("step_key,step_kind,status,public_error_summary").eq("build_job_id", buildJobId).order("sequence");
    if (!currentSteps.error && currentSteps.data?.length) {
      await admin.from("pandora_build_stream_events").insert(currentSteps.data.map((step) => ({
        stream_id: input.streamId,
        organization_id: organizationId,
        project_id: projectId,
        build_job_id: buildJobId,
        event_type: "build_step",
        safe_payload: { stepKey: step.step_key, stepKind: step.step_kind, status: step.status, error: step.public_error_summary },
      })));
    }
  } catch (error) {
    const code = error instanceof Error ? error.message : "BUILD_REQUEST_FAILED";
    try {
      await admin.from("pandora_build_stream_sessions").update({ status: "failed", public_error_code: code, updated_at: new Date().toISOString() }).eq("id", input.streamId);
    } catch { /* best-effort terminal state */ }
    try {
      await admin.from("pandora_build_stream_events").insert({
        stream_id: input.streamId,
        organization_id: organizationId,
        project_id: projectId,
        event_type: "stream_error",
        safe_payload: { code },
      });
    } catch { /* best-effort event */ }
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return response({ ok: false, state: "rejected" }, 405);
  const authorization = req.headers.get("authorization") || "";
  if (!/^Bearer\s+\S+$/i.test(authorization)) return response({ ok: false, state: "rejected" }, 401);
  try {
    const { projectId, idempotencyKey } = await readBody(req);
    const user = userClient(authorization);
    const { data: auth, error: authError } = await user.auth.getUser();
    if (authError || !auth.user) throw new Error("SIGN_IN_REQUIRED");
    const { data: project, error: projectError } = await user.from("projectos_projects").select("id,organization_id,name,objective").eq("id", projectId).maybeSingle();
    if (projectError || !project) throw new Error("PROJECT_NOT_AVAILABLE");
    const admin = adminClient();

    const existingSession = await admin.from("pandora_build_stream_sessions").select("id,status,build_job_id,project_version_id,public_error_code").eq("organization_id", project.organization_id).eq("project_id", projectId).eq("idempotency_key", idempotencyKey).maybeSingle();
    if (existingSession.error) throw new Error("BUILD_REQUEST_FAILED");
    if (existingSession.data) {
      const session = existingSession.data;
      return response({
        ok: session.status !== "failed",
        state: session.status === "completed" ? "ready" : session.status === "failed" ? "blocked" : "working",
        streamId: session.id,
        buildJobId: session.build_job_id,
        projectVersionId: session.project_version_id,
      }, session.status === "failed" ? 409 : session.status === "completed" ? 200 : 202);
    }

    let { data: spec, error: specError } = await admin.from("pandora_project_specs").select("id,organization_id,project_id,source_intent_id,project_type,business_summary,product_scope,data_scope,integration_scope,experience_scope,deployment_scope,acceptance_scope,content_sha256").eq("organization_id", project.organization_id).eq("project_id", projectId).eq("status", "active").order("version", { ascending: false }).limit(1).maybeSingle();
    if (specError) throw new Error("PROJECT_SPEC_NOT_READY");
    if (!spec) {
      const { data: latestIntent, error: latestIntentError } = await admin.from("pandora_project_intents").select("id").eq("organization_id", project.organization_id).eq("project_id", projectId).order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (latestIntentError || !latestIntent) throw new Error("PROJECT_SPEC_NOT_READY");
      let compilerResponse: Response;
      try {
        compilerResponse = await fetch(`${SUPABASE_URL}/functions/v1/pandora-project-spec-compiler`, {
          method: "POST",
          headers: { authorization, apikey: SUPABASE_ANON_KEY, "content-type": "application/json" },
          body: JSON.stringify({ intentId: latestIntent.id }),
          signal: AbortSignal.timeout(20000),
        });
      } catch {
        throw new Error("PROVIDER_UNAVAILABLE");
      }
      if (compilerResponse.status >= 500) throw new Error("PROVIDER_UNAVAILABLE");
      if (compilerResponse.status === 202 || compilerResponse.status === 422) {
        return response({ ok: true, state: "working", stage: "understanding", streamId: null }, 202);
      }
      if (compilerResponse.status === 409) {
        const { data: compilation } = await admin.from("pandora_project_spec_compilations").select("status,attempt_count,retry_after_at").eq("source_intent_id", latestIntent.id).maybeSingle();
        if (!compilation || Number(compilation.attempt_count || 0) < 20) {
          return response({ ok: true, state: "working", stage: "understanding", streamId: null }, 202);
        }
        throw new Error("PROJECT_SPEC_NOT_READY");
      }
      if (compilerResponse.status !== 200) throw new Error("PROJECT_SPEC_NOT_READY");
      const retry = await admin.from("pandora_project_specs").select("id,organization_id,project_id,source_intent_id,project_type,business_summary,product_scope,data_scope,integration_scope,experience_scope,deployment_scope,acceptance_scope,content_sha256").eq("organization_id", project.organization_id).eq("project_id", projectId).eq("status", "active").order("version", { ascending: false }).limit(1).maybeSingle();
      if (retry.error || !retry.data) return response({ ok: true, state: "working", stage: "understanding", streamId: null }, 202);
      spec = retry.data;
    }

    const runtime = (globalThis as unknown as { EdgeRuntime?: { waitUntil(promise: Promise<unknown>): void } }).EdgeRuntime;
    if (!runtime?.waitUntil) throw new Error("BACKGROUND_STREAMING_UNAVAILABLE");
    await admin.from("pandora_build_stream_events").delete().lt("expires_at", new Date().toISOString());

    const created = await admin.from("pandora_build_stream_sessions").insert({
      organization_id: project.organization_id,
      project_id: projectId,
      requested_by: auth.user.id,
      idempotency_key: idempotencyKey,
      status: "queued",
    }).select("id").single();
    if (created.error || !created.data) throw new Error("BUILD_REQUEST_FAILED");
    const streamId = text(created.data.id);
    runtime.waitUntil(runGenerationInBackground({
      authorization,
      project: rec(project),
      spec: rec(spec),
      requestedBy: auth.user.id,
      idempotencyKey,
      streamId,
    }));
    return response({ ok: true, state: "working", stage: "generating_source", streamId }, 202);
  } catch (error) {
    const code = error instanceof Error ? error.message : "BUILD_REQUEST_FAILED";
    const status = code === "SIGN_IN_REQUIRED" ? 401 : code === "INVALID_REQUEST" ? 400 : code === "PROJECT_NOT_AVAILABLE" ? 404 : code === "PROJECT_SPEC_NOT_READY" ? 409 : code === "PROVIDER_REJECTED" || code === "INVALID_GENERATED_SOURCE_STREAM" || code === "BUILD_TYPE_NOT_SUPPORTED" ? 422 : 503;
    return response({ ok: false, state: status === 503 ? "waiting" : "blocked", error: { code } }, status);
  }
});
