
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

const SOURCE_SECRET_LOOKBEHIND_CHARS = 4096;
const SOURCE_SECRET_RULES = [
  String.raw`Authorization\s*[:=]\s*["'\x60]?(?:Bearer|Basic)\s+[A-Za-z0-9._~+\/=-]{8,}`,
  String.raw`\bBearer\s+[A-Za-z0-9._~+\/-]{12,}=*`,
  String.raw`\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|secret|password|private[_-]?key)\s*[:=]\s*["'\x60][^"'\x60\r\n]{12,}`,
  String.raw`(?:^|[\s;{])(?:GITHUB_TOKEN|GITHUB_PAT|GITHUB_SUPABASE|VERCEL_TOKEN|SUPABASE_SERVICE_ROLE|SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE_KEY|GEMINI_API_KEY|MOONSHOT_API_KEY|KIMI_API_KEY|DATABASE_URL)\s*=\s*["'\x60]?(?!process\.env\b|Deno\.env\b|import\.meta\.env\b|\$\{)[^\s,;}"'\x60]{12,}`,
  String.raw`sk-[A-Za-z0-9_-]{20,}`,
  String.raw`github_pat_[A-Za-z0-9_]{20,}`,
  String.raw`gh[pousr]_[A-Za-z0-9_]{20,}`,
  String.raw`glpat-[A-Za-z0-9_-]{20,}`,
  String.raw`(?:sbp|vcp|vercel)_[A-Za-z0-9_-]{20,}`,
  String.raw`sb_secret_[A-Za-z0-9_-]{20,}`,
  String.raw`AIza[A-Za-z0-9_-]{20,}`,
  String.raw`eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}`,
  String.raw`-----BEGIN [A-Z ]*PRIVATE KEY-----`,
  String.raw`https?:\/\/[^\/\s:@]+:[^@\s\/]+@`,
] as const;
const SOURCE_SECRET_PATTERNS = SOURCE_SECRET_RULES.map((source) => new RegExp(source, "i"));
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


function sourcePrompt(spec: JsonRecord, project: JsonRecord, adapter: string, priorSource: JsonRecord | null, impactPlan: JsonRecord) {
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
      priorSource && impactPlan.authoritative === true && Number(impactPlan.impactTier) <= 1
        ? "This is an authoritative low-impact incremental change. Emit complete replacement contents only for files that actually change. Do not emit untouched files and do not delete files. Pandora will merge these exact changed files onto the exact verified baseline before building."
        : "Emit the complete project source bundle required by the active ProjectSpec.",
      contract,
    ].join(" ") }] },
    contents: [{ role: "user", parts: [{ text: JSON.stringify({ project: { name: text(project.name), objective: text(project.objective) }, projectSpec: { id: spec.id, projectType: spec.project_type, businessSummary: spec.business_summary, product: spec.product_scope, data: spec.data_scope, integrations: spec.integration_scope, experience: spec.experience_scope, deployment: spec.deployment_scope, acceptance: spec.acceptance_scope }, existingVerifiedSource: priorSource ? { versionId: priorSource.versionId, artifactVersionId: priorSource.artifactVersionId, sourceDigest: priorSource.sourceDigest, files: priorSource.files } : null, changeImpact: impactPlan, buildAdapter: adapter }) }] }],
    generationConfig: { responseMimeType: "text/plain", temperature: 0.2, maxOutputTokens: 32768 },
  };
}

type StreamAssembler = {
  streamId: string;
  buildJobId: string;
  organizationId: string;
  projectId: string;
  currentPath: string | null;
  files: Map<string, string[]>;
  fileBytes: Map<string, number>;
  totalBytes: number;
  pending: JsonRecord[];
  done: boolean;
  liveDisplayBuffer: string;\n  knownSecrets: string[];
};

type StreamProviderMeta = {
  modelVersion: string;
  usage: JsonRecord;
};

function providerChunkText(envelope: JsonRecord) {
  const candidates = Array.isArray(envelope.candidates) ? envelope.candidates as unknown[] : [];
  const parts = Array.isArray(rec(rec(candidates[0]).content).parts) ? rec(rec(candidates[0]).content).parts as unknown[] : [];
  // Preserve provider bytes exactly. Trimming an SSE text part can remove the
  // newline between two NDJSON events and corrupt the real source stream.
  return parts.map((part) => {
    const value = rec(part).text;
    return typeof value === "string" ? value : "";
  }).join("");
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
    build_job_id: state.buildJobId,
    project_id: state.projectId,
    event_type: eventType,
    file_path: filePath,
    content_chunk: contentChunk,
    safe_payload: safePayload,
  });
}


function sourceContainsSecret(value: string, knownSecrets: string[] = []) {
  const candidate = String(value ?? "");
  for (const secret of knownSecrets) {
    const normalized = typeof secret === "string" ? secret.trim() : "";
    if (normalized.length >= 8 && candidate.includes(normalized)) return true;
  }
  return SOURCE_SECRET_PATTERNS.some((pattern) => pattern.test(candidate));
}

async function emitLiveSource(admin: ReturnType<typeof adminClient>, state: StreamAssembler, path: string, content: string) {
  if (!content) return;
  for (let offset = 0; offset < content.length;) {
    let end = Math.min(content.length, offset + 512);
    if (end < content.length && /[\uD800-\uDBFF]/.test(content[end - 1])) end -= 1;
    if (end <= offset) end = Math.min(content.length, offset + 2);
    const liveChunk = content.slice(offset, end);
    const liveBytes = new TextEncoder().encode(liveChunk).byteLength;
    queueStreamEvent(state, "code_chunk", path, liveChunk, { byteSize: liveBytes });
    await flushStreamEvents(admin, state, true);
    offset = end;
  }
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
    if (!exactKeys(event, ["type", "path"]) || state.currentPath || state.liveDisplayBuffer || state.done) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
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
    // Withhold a bounded tail before customer delivery. The next provider chunk is
    // scanned together with this tail, so a credential split across transport/model
    // chunk boundaries is rejected before any credential bytes can reach code_chunk.
    const candidateLiveSource = state.liveDisplayBuffer + content;
    if (sourceContainsSecret(candidateLiveSource, state.knownSecrets)) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    state.fileBytes.set(path, nextFileBytes);
    state.totalBytes = nextTotal;
    state.files.get(path)!.push(content);
    let publishLength = Math.max(0, candidateLiveSource.length - SOURCE_SECRET_LOOKBEHIND_CHARS);
    if (publishLength > 0 && /[\uD800-\uDBFF]/.test(candidateLiveSource[publishLength - 1])) publishLength -= 1;
    const safeLiveSource = candidateLiveSource.slice(0, publishLength);
    state.liveDisplayBuffer = candidateLiveSource.slice(publishLength);
    await emitLiveSource(admin, state, path, safeLiveSource);
    return;
  }
  if (kind === "file_end") {
    if (!exactKeys(event, ["type", "path"]) || state.done) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    const path = text(event.path);
    if (path !== state.currentPath || !state.files.has(path) || (state.fileBytes.get(path) || 0) < 1) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    if (sourceContainsSecret(state.liveDisplayBuffer, state.knownSecrets)) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
    await emitLiveSource(admin, state, path, state.liveDisplayBuffer);
    state.liveDisplayBuffer = "";
    state.currentPath = null;
    queueStreamEvent(state, "file_completed", path, null, { byteSize: state.fileBytes.get(path) || 0 });
    await flushStreamEvents(admin, state, true);
    return;
  }
  if (kind === "done") {
    if (!exactKeys(event, ["type", "schemaVersion"]) || event.schemaVersion !== 1 || state.currentPath || state.liveDisplayBuffer || !state.files.size || state.done) throw new Error("INVALID_GENERATED_SOURCE_STREAM");
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
  const providerCredential = credential.data.trim();
  if (!state.knownSecrets.includes(providerCredential)) state.knownSecrets.push(providerCredential);
  let providerResponse: Response;
  try {
    providerResponse = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(MODEL)}:streamGenerateContent?alt=sse`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-goog-api-key": providerCredential },
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
    const bytes = new TextEncoder().encode(content); if (!bytes.length || bytes.length > MAX_FILE_BYTES || sourceContainsSecret(content, [SUPABASE_SERVICE_ROLE_KEY])) throw new Error("INVALID_GENERATED_SOURCE");
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
  if (sourceContainsSecret(raw, [SUPABASE_SERVICE_ROLE_KEY])) throw new Error("BASE_SOURCE_UNSAFE");
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
  let fullUsed = 0;
  const files: JsonRecord[] = [];
  const allFiles: JsonRecord[] = [];
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
    if (sourceContainsSecret(content, [SUPABASE_SERVICE_ROLE_KEY])) throw new Error("BASE_SOURCE_UNSAFE");
    const bytes = new TextEncoder().encode(content).byteLength;
    fullUsed += bytes;
    if (fullUsed > MAX_SOURCE_BYTES) throw new Error("BASE_SOURCE_INVALID");
    allFiles.push({ path, content });
    if (used + bytes > MAX_BASE_CONTEXT_BYTES) continue;
    used += bytes;
    files.push({ path, content });
  }
  return files.length ? {
    versionId: version.data.id,
    artifactVersionId: version.data.root_artifact_version_id,
    sourceDigest: artifact.data.content_sha256,
    files,
    allFiles,
  } : null;
}


async function runGenerationInBackground(input: {
  authorization: string;
  project: JsonRecord;
  spec: JsonRecord;
  requestedBy: string;
  idempotencyKey: string;
  streamId: string;
  buildJobId: string;
  sourceQueueId: string;
}) {
  const admin = adminClient();
  const organizationId = text(input.project.organization_id);
  const projectId = text(input.project.id);
  const state: StreamAssembler = {
    streamId: input.streamId,
    buildJobId: input.buildJobId,
    organizationId,
    projectId,
    currentPath: null,
    files: new Map<string, string[]>(),
    fileBytes: new Map<string, number>(),
    totalBytes: 0,
    pending: [],
    done: false,
    liveDisplayBuffer: "",\n    knownSecrets: [SUPABASE_SERVICE_ROLE_KEY].filter((value) => value.trim().length >= 8),
  };
  try {
    const claimed = await admin.from("pandora_source_generation_queue")
      .select("id,status,build_job_id,project_spec_id,dispatch_count")
      .eq("id", input.sourceQueueId)
      .maybeSingle();
    if (claimed.error || !claimed.data || claimed.data.status !== "dispatching" ||
        text(claimed.data.build_job_id) !== input.buildJobId ||
        text(claimed.data.project_spec_id) !== text(input.spec.id)) {
      throw new Error("SOURCE_FASTPATH_LEASE_LOST");
    }

    await admin.from("pandora_build_stream_sessions")
      .update({ status: "streaming", updated_at: new Date().toISOString() })
      .eq("id", input.streamId)
      .eq("build_job_id", input.buildJobId);
    queueStreamEvent(state, "stream_started", null, null, { model: MODEL });
    await flushStreamEvents(admin, state, true);

    const adapter = chooseAdapter(input.spec);
    const priorSource = await loadLatestVerifiedSource(admin, organizationId, projectId);
    const impactRead = await admin.rpc("pandora_project_change_impact_service_v1", { p_project_spec_id: input.spec.id });
    const impact = !impactRead.error && impactRead.data && typeof impactRead.data === "object"
      ? rec(impactRead.data)
      : { authoritative: false, impactTier: 4, impactClass: "database", buildScope: "full_candidate", verificationScope: "database_plus_global", changedScopes: { conservativeFallback: true } };
    const incremental = impact.authoritative === true && Number(impact.impactTier) <= 1 &&
      text(impact.buildScope) !== "full_candidate" && priorSource && Array.isArray(priorSource.allFiles) && priorSource.allFiles.length > 0;
    queueStreamEvent(state, "impact_classified", null, null, {
      authoritative: impact.authoritative === true,
      impactTier: Number(impact.impactTier),
      impactClass: text(impact.impactClass),
      buildScope: incremental ? text(impact.buildScope) : "full_candidate",
      verificationScope: text(impact.verificationScope),
    });
    await flushStreamEvents(admin, state, true);
    const providerRequest = sourcePrompt(input.spec, input.project, adapter, priorSource, impact);
    const requestSha = await sha256Text(JSON.stringify(providerRequest));
    const streamed = await streamGeminiSource(admin, providerRequest, state);
    const generatedFiles = [...state.files.entries()].map(([path, chunks]) => ({ path, content: chunks.join("") }));
    const files = incremental
      ? (() => {
          const merged = new Map<string, string>();
          for (const value of priorSource.allFiles as JsonRecord[]) {
            const row = rec(value);
            const path = text(row.path);
            const content = typeof row.content === "string" ? row.content : "";
            if (!SAFE_PATH.test(path) || !content || sourceContainsSecret(content, [SUPABASE_SERVICE_ROLE_KEY])) throw new Error("BASE_SOURCE_INVALID");
            merged.set(path, content);
          }
          for (const file of generatedFiles) merged.set(file.path, file.content);
          return [...merged.entries()].map(([path, content]) => ({ path, content }));
        })()
      : generatedFiles;
    const canonical = await canonicalBundle({ schemaVersion: 1, files }, text(input.spec.id), adapter);
    const responseSha = await sha256Text(streamed.rawOutput);
    const requestId = crypto.randomUUID();
    const usage = streamed.meta.usage;
    const { data: modelRun, error: modelRunError } = await admin.from("pandora_model_runs").insert({
      organization_id: organizationId,
      project_id: projectId,
      project_spec_id: input.spec.id,
      build_job_id: input.buildJobId,
      request_id: requestId,
      task: "generate_project_source",
      output_mode: "structured",
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

    const leaseCheck = await admin.from("pandora_source_generation_queue")
      .select("status,build_job_id")
      .eq("id", input.sourceQueueId)
      .maybeSingle();
    if (leaseCheck.error || !leaseCheck.data || leaseCheck.data.status !== "dispatching" ||
        text(leaseCheck.data.build_job_id) !== input.buildJobId) {
      throw new Error("SOURCE_FASTPATH_LEASE_LOST");
    }

    await admin.from("pandora_build_stream_sessions")
      .update({ status: "assembling", updated_at: new Date().toISOString() })
      .eq("id", input.streamId)
      .eq("build_job_id", input.buildJobId);
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
    if (buildJobId !== input.buildJobId || !UUID.test(projectVersionId)) throw new Error("BUILD_INTAKE_FAILED");

    const completed = await admin.from("pandora_source_generation_queue").update({
      status: "succeeded",
      build_job_id: buildJobId,
      project_version_id: projectVersionId,
      last_error_code: null,
      completed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", input.sourceQueueId)
      .eq("build_job_id", input.buildJobId)
      .eq("status", "dispatching")
      .select("id")
      .maybeSingle();
    if (completed.error || !completed.data) throw new Error("SOURCE_FASTPATH_LEASE_LOST");

    await admin.from("pandora_build_stream_sessions").update({
      status: "building",
      build_job_id: buildJobId,
      project_version_id: projectVersionId,
      updated_at: new Date().toISOString(),
    }).eq("id", input.streamId).eq("build_job_id", input.buildJobId);
    await admin.from("pandora_build_stream_events").insert({
      stream_id: input.streamId,
      organization_id: organizationId,
      project_id: projectId,
      build_job_id: buildJobId,
      event_type: "job_state",
      safe_payload: { stage: "source_ready", buildJobId, projectVersionId },
    });
  } catch (error) {
    const code = error instanceof Error ? error.message : "BUILD_REQUEST_FAILED";
    if (code === "SOURCE_FASTPATH_LEASE_LOST") return;

    const queue = await admin.from("pandora_source_generation_queue")
      .select("status,dispatch_count")
      .eq("id", input.sourceQueueId)
      .eq("build_job_id", input.buildJobId)
      .maybeSingle();
    const dispatchCount = Number(queue.data?.dispatch_count || 0);
    const terminal = ["BUILD_TYPE_NOT_SUPPORTED", "PROJECT_SPEC_NOT_READY", "PROJECT_NOT_AVAILABLE"].includes(code) || dispatchCount >= 5;

    if (!queue.error && queue.data?.status === "dispatching") {
      await admin.from("pandora_source_generation_queue").update({
        status: terminal ? "failed" : "queued",
        last_error_code: code.slice(0, 120),
        dispatched_at: null,
        completed_at: terminal ? new Date().toISOString() : null,
        updated_at: new Date().toISOString(),
      }).eq("id", input.sourceQueueId).eq("build_job_id", input.buildJobId).eq("status", "dispatching");
    }

    if (terminal) {
      await admin.from("pandora_build_jobs").update({
        status: "failed", current_stage: "failed", completed_at: new Date().toISOString(),
        error_code: code.slice(0, 120), public_error_summary: "Pandora couldn't finish this build. Your current version is unchanged.",
        updated_at: new Date().toISOString(),
      }).eq("id", input.buildJobId).eq("status", "queued").is("target_project_version_id", null);
      await admin.from("pandora_build_stream_sessions").update({
        status: "failed", public_error_code: code, updated_at: new Date().toISOString(),
      }).eq("id", input.streamId).eq("build_job_id", input.buildJobId);
      try {
        await admin.from("pandora_build_stream_events").insert({
          stream_id: input.streamId, organization_id: organizationId, project_id: projectId,
          build_job_id: input.buildJobId, event_type: "stream_error", safe_payload: { code },
        });
      } catch { /* best-effort event */ }
    } else {
      await admin.from("pandora_build_stream_sessions").update({
        status: "queued", public_error_code: null, updated_at: new Date().toISOString(),
      }).eq("id", input.streamId).eq("build_job_id", input.buildJobId);
      try {
        await admin.from("pandora_build_stream_events").insert({
          stream_id: input.streamId, organization_id: organizationId, project_id: projectId,
          build_job_id: input.buildJobId, event_type: "job_state",
          safe_payload: { stage: "source_generation", state: "retrying", code },
        });
      } catch { /* best-effort event */ }
    }
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
    const { data: project, error: projectError } = await user.from("projectos_projects")
      .select("id,organization_id,name,objective").eq("id", projectId).maybeSingle();
    if (projectError || !project) throw new Error("PROJECT_NOT_AVAILABLE");
    const admin = adminClient();

    const existingSession = await admin.from("pandora_build_stream_sessions")
      .select("id,status,build_job_id,project_version_id,public_error_code")
      .eq("organization_id", project.organization_id).eq("project_id", projectId)
      .eq("idempotency_key", idempotencyKey).maybeSingle();
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

    let { data: spec, error: specError } = await admin.from("pandora_project_specs")
      .select("id,organization_id,project_id,source_intent_id,project_type,business_summary,product_scope,data_scope,integration_scope,experience_scope,deployment_scope,acceptance_scope,content_sha256")
      .eq("organization_id", project.organization_id).eq("project_id", projectId).eq("status", "active")
      .order("version", { ascending: false }).limit(1).maybeSingle();
    if (specError) throw new Error("PROJECT_SPEC_NOT_READY");
    if (!spec) {
      const { data: latestIntent, error: latestIntentError } = await admin.from("pandora_project_intents")
        .select("id").eq("organization_id", project.organization_id).eq("project_id", projectId)
        .order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (latestIntentError || !latestIntent) throw new Error("PROJECT_SPEC_NOT_READY");
      let compilerResponse: Response;
      try {
        compilerResponse = await fetch(`${SUPABASE_URL}/functions/v1/pandora-project-spec-compiler`, {
          method: "POST",
          headers: { authorization, apikey: SUPABASE_ANON_KEY, "content-type": "application/json" },
          body: JSON.stringify({ intentId: latestIntent.id }),
          signal: AbortSignal.timeout(20000),
        });
      } catch { throw new Error("PROVIDER_UNAVAILABLE"); }
      if (compilerResponse.status >= 500) throw new Error("PROVIDER_UNAVAILABLE");
      if (compilerResponse.status === 202 || compilerResponse.status === 422) {
        return response({ ok: true, state: "working", stage: "understanding", streamId: null }, 202);
      }
      if (compilerResponse.status === 409) {
        const { data: compilation } = await admin.from("pandora_project_spec_compilations")
          .select("status,attempt_count,retry_after_at").eq("source_intent_id", latestIntent.id).maybeSingle();
        if (!compilation || Number(compilation.attempt_count || 0) < 20) {
          return response({ ok: true, state: "working", stage: "understanding", streamId: null }, 202);
        }
        throw new Error("PROJECT_SPEC_NOT_READY");
      }
      if (compilerResponse.status !== 200) throw new Error("PROJECT_SPEC_NOT_READY");
      const retry = await admin.from("pandora_project_specs")
        .select("id,organization_id,project_id,source_intent_id,project_type,business_summary,product_scope,data_scope,integration_scope,experience_scope,deployment_scope,acceptance_scope,content_sha256")
        .eq("organization_id", project.organization_id).eq("project_id", projectId).eq("status", "active")
        .order("version", { ascending: false }).limit(1).maybeSingle();
      if (retry.error || !retry.data) return response({ ok: true, state: "working", stage: "understanding", streamId: null }, 202);
      spec = retry.data;
    }

    const authorized = await user.rpc("pandora_authorize_project_build_v1", {
      p_project_id: projectId,
      p_project_spec_id: spec.id,
      p_idempotency_key: idempotencyKey,
    });
    if (authorized.error || !authorized.data) throw new Error("BUILD_AUTHORIZATION_FAILED");
    const authorizationResult = rec(authorized.data);
    const authorizationId = text(authorizationResult.authorizationId);
    if (!UUID.test(authorizationId)) throw new Error("BUILD_AUTHORIZATION_FAILED");

    const admitted = await admin.rpc("pandora_admit_authorized_build_service_v1", {
      p_authorization_id: authorizationId,
      p_stream_idempotency_key: idempotencyKey,
    });
    if (admitted.error || !admitted.data) throw new Error("BUILD_ADMISSION_FAILED");
    const admission = rec(admitted.data);
    const buildJobId = text(admission.buildJobId);
    const streamId = text(admission.streamId);
    const sourceQueueId = text(admission.sourceQueueId);
    const sourceIdempotencyKey = text(admission.sourceIdempotencyKey);
    if (![buildJobId, streamId, sourceQueueId].every((value) => UUID.test(value)) || sourceIdempotencyKey.length < 8) {
      throw new Error("BUILD_ADMISSION_FAILED");
    }

    let fastPathStarted = false;
    const runtime = (globalThis as unknown as { EdgeRuntime?: { waitUntil(promise: Promise<unknown>): void } }).EdgeRuntime;
    if (runtime?.waitUntil && !admission.projectVersionId) {
      const fastClaim = await admin.rpc("pandora_claim_source_fastpath_service_v1", {
        p_queue_id: sourceQueueId,
        p_build_job_id: buildJobId,
      });
      if (!fastClaim.error && fastClaim.data === true) {
        fastPathStarted = true;
        runtime.waitUntil(runGenerationInBackground({
          authorization,
          project: rec(project),
          spec: rec(spec),
          requestedBy: auth.user.id,
          idempotencyKey: sourceIdempotencyKey,
          streamId,
          buildJobId,
          sourceQueueId,
        }));
      }
    }

    return response({
      ok: true,
      state: admission.state || "working",
      stage: admission.projectVersionId ? "building" : fastPathStarted ? "generating_source" : "queued",
      authorizationId,
      buildJobId,
      streamId,
      sourceQueueId,
      projectSpecId: spec.id,
      projectVersionId: admission.projectVersionId || null,
      admittedAt: admission.admittedAt || null,
    }, admission.state === "ready" ? 200 : 202);
  } catch (error) {
    const code = error instanceof Error ? error.message : "BUILD_REQUEST_FAILED";
    const status = code === "SIGN_IN_REQUIRED" ? 401
      : code === "INVALID_REQUEST" ? 400
      : code === "PROJECT_NOT_AVAILABLE" ? 404
      : code === "PROJECT_SPEC_NOT_READY" || code === "BUILD_AUTHORIZATION_FAILED" ? 409
      : 503;
    return response({ ok: false, state: status === 503 ? "waiting" : "blocked", error: { code } }, status);
  }
});
