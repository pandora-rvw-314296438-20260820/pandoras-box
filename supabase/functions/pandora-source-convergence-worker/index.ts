import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const MODEL = Deno.env.get("PANDORA_SOURCE_GENERATION_MODEL") || "gemini-3.5-flash-lite";
const BUCKET = "pandora-build-artifacts";
const MAX_FILES = 120;
const MAX_FILE_BYTES = 512 * 1024;
const MAX_SOURCE_BYTES = 4 * 1024 * 1024;
const MAX_BASE_CONTEXT_BYTES = 120 * 1024;
const MIN_STATIC_INDEX_BYTES = 1024;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SAFE_PATH = /^(?!\.)(?!.*(?:^|\/)\.\.?(?:\/|$))[A-Za-z0-9_@+.-]+(?:\/[A-Za-z0-9_@+.-]+)*$/;
const SECRET = /(?:AIza[0-9A-Za-z_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|(?:api[_-]?key|secret|password|authorization)\s*[:=]\s*["'][^"']{12,}["'])/i;

type JsonRecord = Record<string, unknown>;

function rec(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}
function text(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
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
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error("SERVICE_UNAVAILABLE");
  }
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
async function sha256Bytes(bytes: Uint8Array) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
async function sha256Text(value: string) {
  return sha256Bytes(new TextEncoder().encode(value));
}
function base64(bytes: Uint8Array) {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}
function decodeBase64(value: string) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
function exactKeys(value: JsonRecord, expected: string[]) {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return actual.length === wanted.length &&
    actual.every((key, index) => key === wanted[index]);
}

function chooseAdapter(spec: JsonRecord) {
  const type = text(spec.project_type);
  const experience = rec(spec.experience_scope);
  const platforms = Array.isArray(experience.platforms)
    ? experience.platforms.map(text)
    : [];
  if (type === "website") return "static-web";
  if (
    type === "mobile_application" || platforms.includes("android") ||
    platforms.includes("ios")
  ) return "flutter-web";
  if (
    ["web_application", "system", "api", "automation", "other"].includes(type)
  ) return "node-vite-web";
  throw new Error("BUILD_TYPE_NOT_SUPPORTED");
}

function sourcePrompt(
  spec: JsonRecord,
  project: JsonRecord,
  adapter: string,
  priorSource: JsonRecord | null,
  repairFeedback: JsonRecord[],
) {
  const contract = adapter === "static-web"
    ? "Create a self-contained production-quality website. index.html is mandatory; keep JavaScript and CSS inline unless additional local files materially improve quality."
    : adapter === "flutter-web"
    ? "Create a complete Flutter project that builds with Flutter stable for web. pubspec.yaml and lib/main.dart are mandatory. Do not require secret environment values to render the preview."
    : "Create a complete Vite web application. package.json, index.html and src/main.* are mandatory. Use only npm packages declared in package.json. Do not require secret environment values to render the preview.";

  const repairInstruction = repairFeedback.length
    ? "This is a bounded repair. Independently verified failures are supplied. Repair those failures without weakening, deleting, bypassing, or reinterpreting acceptance requirements. Preserve every already-working behavior."
    : "This is a governed continuation from an active ProjectSpec.";

  const sourceInstruction = priorSource
    ? "An exact previously verified source snapshot is supplied. Treat it as the product baseline. Modify the minimum necessary surface to satisfy the new ProjectSpec; preserve its identity, content, behavior, responsiveness, accessibility, and working interactions."
    : "No previous verified source is available; build the complete first working version.";

  return {
    systemInstruction: {
      parts: [{
        text: [
          "You generate source files for Pandora from an already-governed ProjectSpec.",
          "Return JSON only with exactly: schemaVersion, files.",
          "schemaVersion must be 1. files is an array of {path,content} UTF-8 text files.",
          "Do not return markdown fences, commentary, shell commands, credentials, API keys, tokens, .env files, generated binaries, lockfiles, node_modules, build output, or remote secrets.",
          "Use relative POSIX file paths only. Implement the requested experience and every acceptance criterion. Never invent measured business results.",
          repairInstruction,
          sourceInstruction,
          contract,
        ].join(" "),
      }],
    },
    contents: [{
      role: "user",
      parts: [{
        text: JSON.stringify({
          project: {
            name: text(project.name),
            objective: text(project.objective),
          },
          projectSpec: {
            id: spec.id,
            projectType: spec.project_type,
            businessSummary: spec.business_summary,
            product: spec.product_scope,
            data: spec.data_scope,
            integrations: spec.integration_scope,
            experience: spec.experience_scope,
            deployment: spec.deployment_scope,
            acceptance: spec.acceptance_scope,
          },
          existingVerifiedSource: priorSource,
          independentVerificationFailures: repairFeedback,
          buildAdapter: adapter,
        }),
      }],
    }],
    generationConfig: {
      responseMimeType: "application/json",
      temperature: repairFeedback.length ? 0.1 : 0.2,
      maxOutputTokens: 32768,
    },
  };
}

function providerText(envelope: JsonRecord) {
  const status = Number(envelope.status || 0);
  if (status < 200 || status >= 300) {
    throw new Error(
      status === 429 || status >= 500
        ? "PROVIDER_UNAVAILABLE"
        : "PROVIDER_REJECTED",
    );
  }
  const candidates = Array.isArray(rec(envelope.body).candidates)
    ? rec(envelope.body).candidates as unknown[]
    : [];
  const parts = Array.isArray(rec(rec(candidates[0]).content).parts)
    ? rec(rec(candidates[0]).content).parts as unknown[]
    : [];
  const out = parts.map((part) => text(rec(part).text)).filter(Boolean).join("");
  if (!out) throw new Error("INVALID_GENERATED_SOURCE");
  return out;
}

async function canonicalBundle(
  raw: unknown,
  projectSpecId: string,
  adapter: string,
) {
  const root = rec(raw);
  if (
    !exactKeys(root, ["schemaVersion", "files"]) || root.schemaVersion !== 1 ||
    !Array.isArray(root.files) || root.files.length < 1 ||
    root.files.length > MAX_FILES
  ) {
    throw new Error("INVALID_GENERATED_SOURCE");
  }

  const seen = new Set<string>();
  let total = 0;
  let staticIndexContent = "";
  const files: JsonRecord[] = [];

  for (const value of root.files) {
    const row = rec(value);
    if (!exactKeys(row, ["path", "content"])) {
      throw new Error("INVALID_GENERATED_SOURCE");
    }
    const path = text(row.path);
    const content = typeof row.content === "string" ? row.content : "";
    if (adapter === "static-web" && path === "index.html") {
      staticIndexContent = content;
    }
    if (
      !SAFE_PATH.test(path) || path.length > 512 ||
      path.startsWith(".env") || path.includes("/.env") ||
      path.includes("node_modules/") || path.startsWith("build/") ||
      path.startsWith("dist/") || path.startsWith(".next/") ||
      seen.has(path)
    ) {
      throw new Error("INVALID_GENERATED_SOURCE");
    }
    const bytes = new TextEncoder().encode(content);
    if (
      !bytes.length || bytes.length > MAX_FILE_BYTES || SECRET.test(content)
    ) {
      throw new Error("INVALID_GENERATED_SOURCE");
    }
    total += bytes.length;
    if (total > MAX_SOURCE_BYTES) throw new Error("INVALID_GENERATED_SOURCE");
    seen.add(path);
    files.push({
      file: path,
      data: base64(bytes),
      encoding: "base64",
      sha256: await sha256Bytes(bytes),
      byteSize: bytes.length,
    });
  }

  files.sort((a, b) =>
    String(a.file).localeCompare(String(b.file), "en")
  );

  if (adapter === "static-web") {
    if (!seen.has("index.html")) throw new Error("INVALID_GENERATED_SOURCE");
    const indexBytes = new TextEncoder().encode(staticIndexContent);
    const normalized = staticIndexContent.replace(/\s+/g, " ").trim();
    if (
      indexBytes.byteLength < MIN_STATIC_INDEX_BYTES ||
      !/<meta[^>]+name=["']viewport["'][^>]*>/i.test(staticIndexContent) ||
      /<body[^>]*>\s*(?:loading(?:\.\.\.)?|coming soon|placeholder)\s*<\/body>/i
        .test(normalized)
    ) {
      throw new Error("INVALID_GENERATED_SOURCE");
    }
  }

  if (
    adapter === "node-vite-web" &&
    (!seen.has("package.json") || !seen.has("index.html") ||
      ![...seen].some((path) => path.startsWith("src/main.")))
  ) {
    throw new Error("INVALID_GENERATED_SOURCE");
  }
  if (
    adapter === "flutter-web" &&
    (!seen.has("pubspec.yaml") || !seen.has("lib/main.dart"))
  ) {
    throw new Error("INVALID_GENERATED_SOURCE");
  }

  const bundle = {
    kind: "pandora.source-bundle.v1",
    schemaVersion: 1,
    projectSpecId,
    buildAdapter: adapter,
    files,
  };
  const bytes = new TextEncoder().encode(JSON.stringify(bundle));
  if (bytes.byteLength > MAX_SOURCE_BYTES * 2) {
    throw new Error("INVALID_GENERATED_SOURCE");
  }
  return { bundle, bytes, sha256: await sha256Bytes(bytes) };
}

async function loadBaseSource(
  admin: ReturnType<typeof adminClient>,
  organizationId: string,
  projectId: string,
  baseVersionId: string,
) {
  if (!UUID.test(baseVersionId)) return null;
  const version = await admin.from("pandora_project_versions")
    .select("id,root_artifact_version_id,lifecycle_status")
    .eq("id", baseVersionId)
    .eq("organization_id", organizationId)
    .eq("project_id", projectId)
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
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("BASE_SOURCE_INVALID");
  }
  const bundle = rec(parsed);
  const rows = Array.isArray(bundle.files) ? bundle.files : [];
  const prioritized = [...rows].sort((left, right) => {
    const a = text(rec(left).file);
    const b = text(rec(right).file);
    const rank = (path: string) =>
      path === "index.html"
        ? 0
        : path === "package.json" || path === "pubspec.yaml"
        ? 1
        : path.startsWith("src/main.") || path === "lib/main.dart"
        ? 2
        : 3;
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

  return files.length
    ? {
      versionId: baseVersionId,
      artifactVersionId: version.data.root_artifact_version_id,
      sourceDigest: artifact.data.content_sha256,
      files,
    }
    : null;
}

async function loadRepairFeedback(
  admin: ReturnType<typeof adminClient>,
  verificationRunId: string,
) {
  if (!UUID.test(verificationRunId)) return [];
  const checks = await admin.from("pandora_verification_checks")
    .select("check_key,status,failure_class,summary,details_redacted")
    .eq("verification_run_id", verificationRunId)
    .neq("status", "PASS")
    .limit(8);
  if (checks.error) throw new Error("VERIFICATION_FEEDBACK_READ_FAILED");
  return (checks.data || []).map((row) => ({
    checkKey: row.check_key,
    status: row.status,
    failureClass: row.failure_class,
    summary: row.summary,
    details: row.details_redacted,
  }));
}

async function markQueueError(
  admin: ReturnType<typeof adminClient>,
  queueId: string,
  dispatchCount: number,
  code: string,
) {
  const terminal = dispatchCount >= 5 ||
    [
      "PROJECT_SPEC_SUPERSEDED",
      "PROJECT_NOT_AVAILABLE",
      "BASE_SOURCE_UNSAFE",
      "BUILD_TYPE_NOT_SUPPORTED",
    ].includes(code);
  await admin.from("pandora_source_generation_queue").update({
    status: terminal ? "failed" : "queued",
    last_error_code: code.slice(0, 120),
    dispatched_at: null,
    completed_at: terminal ? new Date().toISOString() : null,
    updated_at: new Date().toISOString(),
  }).eq("id", queueId);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return response({ ok: false, state: "rejected" }, 405);
  }
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return response({ ok: false, state: "unavailable" }, 503);
  }

  const internalKey = req.headers.get("x-pandora-internal-key")?.trim() || "";
  const admin = adminClient();
  const validated = await admin.rpc(
    "pandora_validate_source_worker_key_20260831",
    { p_token: internalKey },
  );
  if (validated.error || validated.data !== true) {
    return response({ ok: false, state: "rejected" }, 401);
  }

  let queueId = "";
  let dispatchCount = 0;
  try {
    const raw = await req.text();
    if (new TextEncoder().encode(raw).byteLength > 2048) {
      throw new Error("INVALID_REQUEST");
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      throw new Error("INVALID_REQUEST");
    }
    const body = rec(parsed);
    if (!exactKeys(body, ["queueId"]) || !UUID.test(text(body.queueId))) {
      throw new Error("INVALID_REQUEST");
    }
    queueId = text(body.queueId);

    const queue = await admin.from("pandora_source_generation_queue")
      .select("*")
      .eq("id", queueId)
      .maybeSingle();
    if (queue.error || !queue.data) throw new Error("QUEUE_NOT_FOUND");

    const row = queue.data;
    dispatchCount = Number(row.dispatch_count || 0);
    if (row.status === "succeeded" || row.status === "cancelled") {
      return response({
        ok: true,
        state: row.status,
        buildJobId: row.build_job_id,
        projectVersionId: row.project_version_id,
        replayed: true,
      });
    }
    if (!["queued", "dispatching"].includes(String(row.status))) {
      throw new Error("QUEUE_NOT_ACTIONABLE");
    }

    const specResult = await admin.from("pandora_project_specs")
      .select(
        "id,organization_id,project_id,status,source_intent_id,project_type,business_summary,product_scope,data_scope,integration_scope,experience_scope,deployment_scope,acceptance_scope,content_sha256",
      )
      .eq("id", row.project_spec_id)
      .eq("organization_id", row.organization_id)
      .eq("project_id", row.project_id)
      .maybeSingle();
    if (specResult.error || !specResult.data) {
      throw new Error("PROJECT_SPEC_NOT_READY");
    }
    const spec = rec(specResult.data);
    if (text(spec.status) !== "active") {
      await admin.from("pandora_source_generation_queue").update({
        status: "cancelled",
        last_error_code: "PROJECT_SPEC_SUPERSEDED",
        completed_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }).eq("id", queueId);
      return response({ ok: true, state: "cancelled" });
    }

    const primitiveResolutionResult = await admin.rpc(
      "pandora_worker_i_resolve_project_spec_primitives_20260831",
      { p_project_spec_id: text(spec.id), p_require_trusted: true },
    );
    if (primitiveResolutionResult.error) throw new Error("PRIMITIVE_SELECTION_UNAVAILABLE");
    const primitiveResolution = rec(primitiveResolutionResult.data);
    const primitiveState = text(primitiveResolution.state);
    if (primitiveState === "BLOCKED") {
      const blockedPrimitives = Array.isArray(primitiveResolution.blockedPrimitives)
        ? primitiveResolution.blockedPrimitives.map((value) => text(value)).filter(Boolean).slice(0, 50)
        : [];
      await admin.from("pandora_source_generation_queue").update({
        status: "failed",
        last_error_code: "TRUSTED_PRIMITIVE_UNAVAILABLE",
        completed_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }).eq("id", queueId);
      return response({
        ok: false,
        state: "blocked",
        error: { code: "TRUSTED_PRIMITIVE_UNAVAILABLE" },
        blockedPrimitives,
      }, 409);
    }
    if (primitiveState !== "READY") throw new Error("PRIMITIVE_SELECTION_UNAVAILABLE");

    const projectResult = await admin.from("projectos_projects")
      .select("id,organization_id,name,objective,status")
      .eq("id", row.project_id)
      .eq("organization_id", row.organization_id)
      .maybeSingle();
    if (
      projectResult.error || !projectResult.data ||
      projectResult.data.status !== "active"
    ) {
      throw new Error("PROJECT_NOT_AVAILABLE");
    }
    const project = rec(projectResult.data);

    if (row.reason === "active_spec") {
      const existing = await admin.from("pandora_build_jobs")
        .select("id,target_project_version_id,status,created_at")
        .eq("organization_id", row.organization_id)
        .eq("project_id", row.project_id)
        .eq("project_spec_id", row.project_spec_id)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (existing.error) throw new Error("BUILD_READ_FAILED");
      if (existing.data) {
        await admin.from("pandora_source_generation_queue").update({
          status: "succeeded",
          build_job_id: existing.data.id,
          project_version_id: existing.data.target_project_version_id,
          completed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }).eq("id", queueId);
        return response({
          ok: true,
          state: "succeeded",
          buildJobId: existing.data.id,
          projectVersionId: existing.data.target_project_version_id,
          replayed: true,
        });
      }
    }

    if (row.reason === "acceptance_repair") {
      const original = await admin.from("pandora_build_jobs")
        .select("id,status,error_code,created_at,project_spec_id")
        .eq("id", row.repair_of_build_job_id)
        .eq("organization_id", row.organization_id)
        .eq("project_id", row.project_id)
        .maybeSingle();
      if (
        original.error || !original.data ||
        original.data.status !== "failed" ||
        original.data.error_code !== "VERIFICATION_FAILED"
      ) {
        await admin.from("pandora_source_generation_queue").update({
          status: "cancelled",
          last_error_code: "REPAIR_SOURCE_NO_LONGER_FAILED",
          completed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }).eq("id", queueId);
        return response({ ok: true, state: "cancelled" });
      }
      const newer = await admin.from("pandora_build_jobs")
        .select("id")
        .eq("organization_id", row.organization_id)
        .eq("project_id", row.project_id)
        .eq("project_spec_id", row.project_spec_id)
        .gt("created_at", original.data.created_at)
        .neq("status", "cancelled")
        .limit(1);
      if (newer.error) throw new Error("BUILD_READ_FAILED");
      if ((newer.data || []).length) {
        await admin.from("pandora_source_generation_queue").update({
          status: "cancelled",
          last_error_code: "SUPERSEDED_BY_NEWER_BUILD",
          completed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }).eq("id", queueId);
        return response({ ok: true, state: "cancelled" });
      }
    }

    const adapter = chooseAdapter(spec);
    const priorSource = row.base_version_id
      ? await loadBaseSource(
        admin,
        String(row.organization_id),
        String(row.project_id),
        String(row.base_version_id),
      )
      : null;
    const repairFeedback = row.reason === "acceptance_repair"
      ? await loadRepairFeedback(
        admin,
        String(row.repair_of_verification_run_id),
      )
      : [];
    if (row.reason === "acceptance_repair" && repairFeedback.length !== 1) {
      throw new Error("REPAIR_FEEDBACK_INVALID");
    }

    const providerRequest = sourcePrompt(
      spec,
      project,
      adapter,
      priorSource,
      repairFeedback,
    );
    const requestSha = await sha256Text(JSON.stringify(providerRequest));
    const modelResult = await admin.rpc("pandora_worker_b_gemini_request_20260829", {
      p_model: MODEL,
      p_body: providerRequest,
    });
    if (modelResult.error) throw new Error("PROVIDER_UNAVAILABLE");
    const modelEnvelope = rec(modelResult.data);
    const output = providerText(modelEnvelope);
    const responseSha = await sha256Text(output);

    let parsed: unknown;
    try {
      parsed = JSON.parse(output);
    } catch {
      throw new Error("INVALID_GENERATED_SOURCE");
    }
    const canonical = await canonicalBundle(
      parsed,
      String(spec.id),
      adapter,
    );

    const providerBody = rec(modelEnvelope.body);
    const usage = rec(providerBody.usageMetadata);
    const requestId = crypto.randomUUID();
    const modelRun = await admin.from("pandora_model_runs").insert({
      organization_id: row.organization_id,
      project_id: row.project_id,
      project_spec_id: row.project_spec_id,
      request_id: requestId,
      task: row.reason === "acceptance_repair"
        ? "repair_code"
        : "generate_project_source",
      output_mode: "structured",
      status: "succeeded",
      provider: "gemini",
      model: MODEL,
      model_revision: text(providerBody.modelVersion) || MODEL,
      request_sha256: requestSha,
      context_sha256: text(spec.content_sha256) || null,
      response_sha256: responseSha,
      input_tokens: Number(usage.promptTokenCount || 0),
      output_tokens: Number(usage.candidatesTokenCount || 0),
      total_tokens: Number(usage.totalTokenCount || 0),
      attempt: Number(row.attempt_no || 0) + 1,
      max_attempts: 3,
      started_at: new Date().toISOString(),
      completed_at: new Date().toISOString(),
    }).select("id").single();
    if (modelRun.error || !modelRun.data) {
      throw new Error("MODEL_RUN_WRITE_FAILED");
    }

    const storagePath =
      `${row.organization_id}/${row.project_id}/${row.project_spec_id}/${canonical.sha256}.json`;
    const upload = await admin.storage.from(BUCKET).upload(
      storagePath,
      canonical.bytes,
      { contentType: "application/json", upsert: false },
    );
    if (
      upload.error &&
      !/already exists|duplicate/i.test(upload.error.message || "")
    ) {
      throw new Error("SOURCE_STORAGE_FAILED");
    }

    const intake = await admin.rpc(
      "pandora_commit_generated_build_intake_service_20260830",
      {
        p_organization_id: row.organization_id,
        p_project_id: row.project_id,
        p_project_spec_id: row.project_spec_id,
        p_requested_by: row.requested_by,
        p_idempotency_key: row.idempotency_key,
        p_source_sha256: canonical.sha256,
        p_source_byte_size: canonical.bytes.byteLength,
        p_storage_path: storagePath,
        p_model_run_id: modelRun.data.id,
        p_build_adapter: adapter,
      },
    );
    if (intake.error) throw new Error("BUILD_INTAKE_FAILED");
    const result = rec(intake.data);

    await admin.from("pandora_source_generation_queue").update({
      status: "succeeded",
      build_job_id: result.buildJobId || null,
      project_version_id: result.projectVersionId || null,
      last_error_code: null,
      completed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", queueId);

    return response({
      ok: true,
      state: "succeeded",
      buildJobId: result.buildJobId,
      projectVersionId: result.projectVersionId,
      repairAttempt: row.reason === "acceptance_repair"
        ? row.attempt_no
        : null,
    }, 200);
  } catch (error) {
    const code = error instanceof Error ? error.message : "SOURCE_WORKER_FAILED";
    if (queueId) {
      await markQueueError(admin, queueId, dispatchCount, code);
    }
    return response({
      ok: false,
      state: "retryable",
      error: { code },
    }, code === "INVALID_REQUEST" ? 400 : code === "QUEUE_NOT_FOUND" ? 404 : 503);
  }
});
