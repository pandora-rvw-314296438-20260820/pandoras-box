
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

function sourcePrompt(spec: JsonRecord, project: JsonRecord, adapter: string) {
  const contract = adapter === "static-web"
    ? "Create a self-contained production-quality website. index.html is mandatory; keep JavaScript and CSS inline unless additional local files materially improve quality."
    : adapter === "flutter-web"
      ? "Create a complete Flutter project that builds with Flutter stable for web. pubspec.yaml and lib/main.dart are mandatory. Do not require secret environment values to render the preview."
      : "Create a complete Vite web application. package.json, index.html and src/main.* are mandatory. Use only npm packages declared in package.json. Do not require secret environment values to render the preview.";
  return {
    systemInstruction: { parts: [{ text: [
      "You generate source files for Pandora from an already-governed ProjectSpec.",
      "Return JSON only with exactly: schemaVersion, files.",
      "schemaVersion must be 1. files is an array of {path,content} UTF-8 text files.",
      "Do not return markdown fences, commentary, shell commands, credentials, API keys, tokens, .env files, generated binaries, lockfiles, node_modules, build output, or remote secrets.",
      "Use relative POSIX file paths only. Implement the requested experience and acceptance criteria. Never invent measured business results.",
      contract,
    ].join(" ") }] },
    contents: [{ role: "user", parts: [{ text: JSON.stringify({ project: { name: text(project.name), objective: text(project.objective) }, projectSpec: { id: spec.id, projectType: spec.project_type, businessSummary: spec.business_summary, product: spec.product_scope, data: spec.data_scope, integrations: spec.integration_scope, experience: spec.experience_scope, deployment: spec.deployment_scope, acceptance: spec.acceptance_scope }, buildAdapter: adapter }) }] }],
    generationConfig: { responseMimeType: "application/json", temperature: 0.2, maxOutputTokens: 32768 },
  };
}

function providerText(envelope: JsonRecord) {
  const status = Number(envelope.status || 0); if (status < 200 || status >= 300) throw new Error(status === 429 || status >= 500 ? "PROVIDER_UNAVAILABLE" : "PROVIDER_REJECTED");
  const candidates = Array.isArray(rec(envelope.body).candidates) ? rec(envelope.body).candidates as unknown[] : [];
  const parts = Array.isArray(rec(rec(candidates[0]).content).parts) ? rec(rec(candidates[0]).content).parts as unknown[] : [];
  const out = parts.map((part) => text(rec(part).text)).filter(Boolean).join(""); if (!out) throw new Error("INVALID_GENERATED_SOURCE"); return out;
}

async function canonicalBundle(raw: unknown, projectSpecId: string, adapter: string) {
  const root = rec(raw);
  if (!exactKeys(root, ["schemaVersion", "files"]) || root.schemaVersion !== 1 || !Array.isArray(root.files) || root.files.length < 1 || root.files.length > MAX_FILES) throw new Error("INVALID_GENERATED_SOURCE");
  const seen = new Set<string>(); let total = 0; const files = [] as JsonRecord[];
  for (const value of root.files) {
    const row = rec(value); if (!exactKeys(row, ["path", "content"])) throw new Error("INVALID_GENERATED_SOURCE");
    const path = text(row.path); const content = typeof row.content === "string" ? row.content : "";
    if (!SAFE_PATH.test(path) || path.length > 512 || path.startsWith(".env") || path.includes("/.env") || path.includes("node_modules/") || path.startsWith("build/") || path.startsWith("dist/") || path.startsWith(".next/") || seen.has(path)) throw new Error("INVALID_GENERATED_SOURCE");
    const bytes = new TextEncoder().encode(content); if (!bytes.length || bytes.length > MAX_FILE_BYTES || SECRET.test(content)) throw new Error("INVALID_GENERATED_SOURCE");
    total += bytes.length; if (total > MAX_SOURCE_BYTES) throw new Error("INVALID_GENERATED_SOURCE"); seen.add(path);
    files.push({ file: path, data: base64(bytes), encoding: "base64", sha256: await sha256Bytes(bytes), byteSize: bytes.length });
  }
  files.sort((a, b) => String(a.file).localeCompare(String(b.file), "en"));
  if (adapter === "static-web" && !seen.has("index.html")) throw new Error("INVALID_GENERATED_SOURCE");
  if (adapter === "node-vite-web" && (!seen.has("package.json") || !seen.has("index.html") || ![...seen].some((p) => p.startsWith("src/main.")))) throw new Error("INVALID_GENERATED_SOURCE");
  if (adapter === "flutter-web" && (!seen.has("pubspec.yaml") || !seen.has("lib/main.dart"))) throw new Error("INVALID_GENERATED_SOURCE");
  const bundle = { kind: "pandora.source-bundle.v1", schemaVersion: 1, projectSpecId, buildAdapter: adapter, files };
  const bytes = new TextEncoder().encode(JSON.stringify(bundle));
  if (bytes.byteLength > MAX_SOURCE_BYTES * 2) throw new Error("INVALID_GENERATED_SOURCE");
  return { bundle, bytes, sha256: await sha256Bytes(bytes) };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return response({ ok: false, state: "rejected" }, 405);
  const authorization = req.headers.get("authorization") || ""; if (!/^Bearer\s+\S+$/i.test(authorization)) return response({ ok: false, state: "rejected" }, 401);
  try {
    const { projectId, idempotencyKey } = await readBody(req);
    const user = userClient(authorization); const { data: auth, error: authError } = await user.auth.getUser(); if (authError || !auth.user) throw new Error("SIGN_IN_REQUIRED");
    const { data: project, error: projectError } = await user.from("projectos_projects").select("id,organization_id,name,objective").eq("id", projectId).maybeSingle();
    if (projectError || !project) throw new Error("PROJECT_NOT_AVAILABLE");
    const admin = adminClient();
    const { data: existing } = await admin.from("pandora_build_jobs").select("id,status,current_stage,target_project_version_id,public_error_summary").eq("organization_id", project.organization_id).eq("project_id", projectId).eq("idempotency_key", idempotencyKey).maybeSingle();
    if (existing) return response({ ok: existing.status !== "failed", state: existing.status === "succeeded" ? "ready" : existing.status === "failed" ? "blocked" : "working", buildJobId: existing.id, projectVersionId: existing.target_project_version_id, stage: existing.current_stage }, existing.status === "failed" ? 409 : existing.status === "succeeded" ? 200 : 202);
    const { data: spec, error: specError } = await admin.from("pandora_project_specs").select("id,organization_id,project_id,source_intent_id,project_type,business_summary,product_scope,data_scope,integration_scope,experience_scope,deployment_scope,acceptance_scope,content_sha256").eq("organization_id", project.organization_id).eq("project_id", projectId).eq("status", "active").order("version", { ascending: false }).limit(1).maybeSingle();
    if (specError || !spec) throw new Error("PROJECT_SPEC_NOT_READY");
    const adapter = chooseAdapter(rec(spec));
    const providerRequest = sourcePrompt(rec(spec), rec(project), adapter); const requestSha = await sha256Text(JSON.stringify(providerRequest));
    const { data: modelData, error: modelError } = await admin.rpc("pandora_worker_b_gemini_request_20260829", { p_model: MODEL, p_body: providerRequest }); if (modelError) throw new Error("PROVIDER_UNAVAILABLE");
    const modelEnvelope = rec(modelData); const output = providerText(modelEnvelope); const responseSha = await sha256Text(output);
    let parsed: unknown; try { parsed = JSON.parse(output); } catch { throw new Error("INVALID_GENERATED_SOURCE"); }
    const canonical = await canonicalBundle(parsed, String(spec.id), adapter);
    const providerBody = rec(modelEnvelope.body); const usage = rec(providerBody.usageMetadata); const requestId = crypto.randomUUID();
    const { data: modelRun, error: modelRunError } = await admin.from("pandora_model_runs").insert({ organization_id: project.organization_id, project_id: projectId, project_spec_id: spec.id, request_id: requestId, task: "generate_project_source", output_mode: "structured", status: "succeeded", provider: "gemini", model: MODEL, model_revision: text(providerBody.modelVersion) || MODEL, request_sha256: requestSha, context_sha256: spec.content_sha256, response_sha256: responseSha, input_tokens: Number(usage.promptTokenCount || 0), output_tokens: Number(usage.candidatesTokenCount || 0), total_tokens: Number(usage.totalTokenCount || 0), started_at: new Date().toISOString(), completed_at: new Date().toISOString() }).select("id").single();
    if (modelRunError || !modelRun) throw new Error("MODEL_RUN_WRITE_FAILED");
    const storagePath = `${project.organization_id}/${projectId}/${spec.id}/${canonical.sha256}.json`;
    const { error: uploadError } = await admin.storage.from(BUCKET).upload(storagePath, canonical.bytes, { contentType: "application/json", upsert: false });
    if (uploadError && !/already exists|duplicate/i.test(uploadError.message || "")) throw new Error("SOURCE_STORAGE_FAILED");
    const { data: intake, error: intakeError } = await admin.rpc("pandora_commit_generated_build_intake_20260829", { p_organization_id: project.organization_id, p_project_id: projectId, p_project_spec_id: spec.id, p_requested_by: auth.user.id, p_idempotency_key: idempotencyKey, p_source_sha256: canonical.sha256, p_source_byte_size: canonical.bytes.byteLength, p_storage_path: storagePath, p_model_run_id: modelRun.id, p_build_adapter: adapter });
    if (intakeError) throw new Error("BUILD_INTAKE_FAILED");
    const result = rec(intake); return response({ ok: true, state: text(result.state) || "working", buildJobId: result.buildJobId, projectVersionId: result.projectVersionId }, 202);
  } catch (error) {
    const code = error instanceof Error ? error.message : "BUILD_REQUEST_FAILED";
    const status = code === "SIGN_IN_REQUIRED" ? 401 : code === "INVALID_REQUEST" ? 400 : code === "PROJECT_NOT_AVAILABLE" ? 404 : code === "PROJECT_SPEC_NOT_READY" ? 409 : code === "PROVIDER_UNAVAILABLE" ? 503 : code === "PROVIDER_REJECTED" || code === "INVALID_GENERATED_SOURCE" || code === "BUILD_TYPE_NOT_SUPPORTED" ? 422 : 503;
    return response({ ok: false, state: status === 503 ? "waiting" : "blocked", error: { code } }, status);
  }
});
