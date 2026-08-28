import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import {
  createClient,
  type SupabaseClient,
} from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const VERCEL_TEAM_ID =
  Deno.env.get("PANDORA_VERCEL_TEAM_ID") ||
  "team_IcdJUnzLi5wUN1GD8ALHyjF7";

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
  const { data, error } = await context.client.rpc("consume_runtime_rate_limit", {
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
  const separator = path.includes("?") ? "&" : "?";
  const scopedPath = `${path}${separator}teamId=${encodeURIComponent(VERCEL_TEAM_ID)}`;
  let requestBody: JsonRecord | null = null;
  if (typeof init.body === "string" && init.body) {
    try {
      requestBody = asRecord(JSON.parse(init.body));
    } catch {
      throw new Error("VERCEL_REQUEST_INVALID");
    }
  }
  const admin = serviceClient();
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
  const { error: updateError } = await context.client.from("projectos_projects")
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

function escapeHtml(value: string) {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#039;");
}

function kindLabel(kind: string) {
  return ({ website: "Website", web_app: "Web app", mobile_app: "Mobile app", internal_tool: "Internal business tool", automation: "Automation", api_backend: "API / backend", full_system: "Full system", help_me_decide: "Digital product" } as Record<string, string>)[kind] || "Digital product";
}

function featureSet(kind: string) {
  const map: Record<string, string[]> = {
    website: ["Clear customer journey", "Responsive pages", "Strong calls to action", "Lead and enquiry capture"],
    web_app: ["Customer workflow", "Accounts and dashboard", "Structured data views", "Responsive application UI"],
    mobile_app: ["Mobile-first experience", "Clear app navigation", "Primary user action", "Web preview before store release"],
    internal_tool: ["Simple operator workflow", "Business dashboard", "Roles and access", "Action history"],
    automation: ["Trigger and workflow", "Human approval points", "Result tracking", "Failure-safe handling"],
    api_backend: ["API contract", "Secure data boundary", "Observable operations", "Deployment-ready service"],
    full_system: ["Customer frontend", "Business operations", "Data and integrations", "Deployment and monitoring"],
    help_me_decide: ["Outcome-first design", "Fast visual prototype", "Business workflow", "Room to evolve"],
  };
  return map[kind] || map.help_me_decide;
}

function previewHtml(project: JsonRecord) {
  const config = asRecord(project.config);
  const journey = asRecord(config.customerJourney);
  const kind = textValue(journey.buildKind, "help_me_decide");
  const name = escapeHtml(textValue(project.name, "Your new project"));
  const objective = escapeHtml(textValue(project.objective, "Pandora is turning your idea into a working digital experience."));
  const features = featureSet(kind).map((feature) => `<article class="feature"><span>✓</span><strong>${escapeHtml(feature)}</strong></article>`).join("");
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${name} — Pandora Preview</title><style>
:root{font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#181818;background:#fbfaf8}*{box-sizing:border-box}body{margin:0;min-height:100vh;background:radial-gradient(circle at 50% -10%,#fff 0,#fbfaf8 45%,#f7f3f2 100%)}main{max-width:1120px;margin:auto;padding:28px 22px 72px}.nav{display:flex;align-items:center;justify-content:space-between;padding:10px 0 42px}.brand{display:flex;align-items:center;gap:10px;font-weight:800}.mark{width:34px;height:34px;border-radius:50%;background:#df0a2b;color:white;display:grid;place-items:center;box-shadow:0 8px 24px #df0a2b2c}.pill{font-size:12px;background:white;border:1px solid #e8e3df;border-radius:999px;padding:8px 12px;color:#6c6864}.hero{padding:72px 0 52px;max-width:850px}.eyebrow{color:#c90726;font-weight:800;font-size:13px;letter-spacing:.08em;text-transform:uppercase}.hero h1{font-size:clamp(42px,7vw,78px);line-height:.98;letter-spacing:-.055em;margin:16px 0 22px}.hero p{font-size:clamp(18px,2.2vw,24px);line-height:1.5;color:#605d59;max-width:760px}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:30px 0 60px}.feature{min-height:118px;background:rgba(255,255,255,.86);border:1px solid #ebe6e2;border-radius:22px;padding:22px;box-shadow:0 14px 38px rgba(54,36,32,.055);display:flex;flex-direction:column;gap:18px}.feature span{color:#df0a2b;font-weight:900}.stage{background:#181818;color:#fff;border-radius:30px;padding:34px;display:flex;justify-content:space-between;gap:30px;align-items:center}.stage p{color:#bbb;margin:7px 0 0;line-height:1.5}.live{width:12px;height:12px;border-radius:50%;background:#29b765;box-shadow:0 0 0 7px #29b76522}@media(max-width:760px){.grid{grid-template-columns:1fr 1fr}.hero{padding-top:42px}.stage{flex-direction:column;align-items:flex-start}}@media(max-width:480px){.grid{grid-template-columns:1fr}.hero h1{font-size:48px}}
</style></head><body><main><nav class="nav"><div class="brand"><div class="mark">✦</div><span>Pandora Preview</span></div><div class="pill">${escapeHtml(kindLabel(kind))}</div></nav><section class="hero"><div class="eyebrow">First live preview</div><h1>${name}</h1><p>${objective}</p></section><section class="grid">${features}</section><section class="stage"><div><strong>Pandora is building this project</strong><p>This live preview is the visual starting point. Pandora can keep changing it before you publish.</p></div><div class="live"></div></section></main></body></html>`;
}

async function createVercelDeployment(provider: { id: string; name: string }, html: string, target: "preview" | "production", metadata: JsonRecord) {
  const requestBody: JsonRecord = { name: provider.name, project: provider.id, files: [{ file: "index.html", data: html }], meta: metadata };
  if (target === "production") requestBody.target = "production";
  const deployment = await vercelRequest("/v13/deployments", { method: "POST", body: JSON.stringify(requestBody) }, [200, 201]);
  const deploymentId = textValue(deployment.id);
  if (!deploymentId) throw new Error("VERCEL_DEPLOYMENT_INVALID");
  let latest = deployment;
  for (let attempt = 0; attempt < 8; attempt++) {
    const state = textValue(latest.readyState ?? latest.status).toUpperCase();
    if (["READY", "ERROR", "CANCELED"].includes(state)) break;
    await new Promise((resolve) => setTimeout(resolve, 750));
    try { latest = await vercelRequest(`/v13/deployments/${encodeURIComponent(deploymentId)}`, { method: "GET" }, [200]); } catch { break; }
  }
  return latest;
}

async function createProject(context: UserContext, body: JsonRecord) {
  const name = textValue(body.name);
  const objective = textValue(body.objective);
  const kind = buildKind(body.buildKind);
  if (name.length < 2 || name.length > 100) throw new Error("INVALID_PROJECT_NAME");
  if (objective.length < 10 || objective.length > 6000) throw new Error("INVALID_OBJECTIVE");

  const projectKey = `${slugify(name)}-${crypto.randomUUID().slice(0, 8)}`;
  const now = new Date().toISOString();
  const config = { customerJourney: { buildKind: kind, stage: "understanding", runtimeStatus: "creating", createdFrom: "simple_mode", updatedAt: now } };
  const { data, error } = await context.client.from("projectos_projects")
    .insert({ organization_id: context.organizationId, project_key: projectKey, name, workspace_path: `projects/${projectKey}`, status: "active", objective, roadmap_version: "2.0.0", config, created_by: context.userId })
    .select("id, project_key, name, objective, status, config, created_at, updated_at").single();
  if (error || !data) throw new Error("BACKEND_WRITE_FAILED");

  let project = asRecord(data);
  try {
    const provider = await ensureVercelProject(context, project);
    project = { ...project, config: provider.config, updated_at: now };
  } catch {
    const current = asRecord(project.config);
    const journey = asRecord(current.customerJourney);
    const nextConfig = { ...current, customerJourney: { ...journey, runtimeStatus: "needs_attention", runtimeUpdatedAt: now } };
    await context.client.from("projectos_projects").update({ config: nextConfig, updated_at: now }).eq("organization_id", context.organizationId).eq("id", project.id);
    project = { ...project, config: nextConfig, updated_at: now };
  }
  return projectResponse(project);
}

async function runtimeSummary(context: UserContext, identifier: string) {
  const project = await projectByIdentifier(context, identifier);
  const projectId = textValue(project.id);
  const [preview, production, domain] = await Promise.all([
    context.client.from("pandora_project_deployments").select("id, version_id, environment, provider_deployment_id, url, status, source_sha256, created_at").eq("organization_id", context.organizationId).eq("project_id", projectId).eq("environment", "preview").order("created_at", { ascending: false }).limit(1).maybeSingle(),
    context.client.from("pandora_project_deployments").select("id, version_id, environment, provider_deployment_id, url, status, source_sha256, created_at").eq("organization_id", context.organizationId).eq("project_id", projectId).eq("environment", "production").order("created_at", { ascending: false }).limit(1).maybeSingle(),
    context.client.from("pandora_project_domains").select("id, domain, status, verified, primary_domain, verification, updated_at").eq("organization_id", context.organizationId).eq("project_id", projectId).eq("primary_domain", true).limit(1).maybeSingle(),
  ]);
  if (preview.error || production.error || domain.error) throw new Error("BACKEND_READ_FAILED");
  return { project: projectResponse(project), preview: preview.data || null, production: production.data || null, domain: domain.data || null };
}

async function createPreview(context: UserContext, identifier: string) {
  let project = await projectByIdentifier(context, identifier);
  const provider = await ensureVercelProject(context, project);
  project = { ...project, config: provider.config };
  const html = previewHtml(project);
  const sourceSha = await sha256Hex(html);
  const sourcePayload = { files: [{ file: "index.html", data: html }] };
  const { data: version, error: versionError } = await context.client.from("pandora_project_versions")
    .insert({ organization_id: context.organizationId, project_id: project.id, kind: "preview", source_payload: sourcePayload, source_sha256: sourceSha, created_by: context.userId })
    .select("id, sequence_no, source_sha256, created_at").single();
  if (versionError || !version) throw new Error("BACKEND_WRITE_FAILED");

  let deployment: JsonRecord;
  try {
    deployment = await createVercelDeployment({ id: provider.id, name: provider.name }, html, "preview", { pandoraProjectId: textValue(project.id), pandoraVersionId: textValue(version.id), sourceSha256: sourceSha });
  } catch {
    const { data: failed } = await context.client.from("pandora_project_deployments")
      .insert({ organization_id: context.organizationId, project_id: project.id, version_id: version.id, provider: "vercel", environment: "preview", provider_project_id: provider.id, status: "failed", source_sha256: sourceSha, metadata: { reason: "provider_request_failed" } })
      .select("id, version_id, environment, provider_deployment_id, url, status, source_sha256, created_at").single();
    return { project: projectResponse(project), version, deployment: failed || { status: "failed" }, previewUrl: null };
  }

  const providerDeploymentId = textValue(deployment.id);
  const rawUrl = textValue(deployment.url);
  const previewUrl = rawUrl ? `https://${rawUrl.replace(/^https?:\/\//, "")}` : null;
  const status = textValue(deployment.readyState ?? deployment.status, "pending").toLowerCase();
  const { data: deploymentRow, error: deploymentError } = await context.client.from("pandora_project_deployments")
    .insert({ organization_id: context.organizationId, project_id: project.id, version_id: version.id, provider: "vercel", environment: "preview", provider_project_id: provider.id, provider_deployment_id: providerDeploymentId || null, url: previewUrl, status, source_sha256: sourceSha, metadata: { providerName: provider.name, readyState: deployment.readyState ?? null } })
    .select("id, version_id, environment, provider_deployment_id, url, status, source_sha256, created_at").single();
  if (deploymentError || !deploymentRow) throw new Error("BACKEND_WRITE_FAILED");

  const config = asRecord(project.config);
  const journey = asRecord(config.customerJourney);
  const nextConfig = { ...config, customerJourney: { ...journey, stage: "preview_ready", runtimeStatus: status === "ready" ? "ready" : "working", previewUrl, previewVersionId: version.id, previewDeploymentId: providerDeploymentId || null, runtimeUpdatedAt: new Date().toISOString() } };
  const { error: updateError } = await context.client.from("projectos_projects").update({ config: nextConfig, updated_at: new Date().toISOString() }).eq("organization_id", context.organizationId).eq("id", project.id);
  if (updateError) throw new Error("BACKEND_WRITE_FAILED");
  return { project: projectResponse({ ...project, config: nextConfig }), version, deployment: deploymentRow, previewUrl };
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
    .select("id, source_payload, source_sha256, project_spec_id, build_job_id, source_commit, artifact_digest_sha256, migration_set_digest_sha256, runtime_target_digest_sha256, verification_run_id, lifecycle_status, created_at")
    .eq("organization_id", context.organizationId).eq("project_id", projectId).eq("id", requestedVersion).maybeSingle();
  if (versionError) throw new Error("BACKEND_READ_FAILED");
  if (!versionData) throw new Error("PREVIEW_REQUIRED");
  const version = asRecord(versionData);
  const payload = asRecord(version.source_payload);
  const files = Array.isArray(payload.files) ? payload.files : [];
  const first = asRecord(files[0]);
  const html = textValue(first.data);
  if (textValue(first.file) !== "index.html" || !html) throw new Error("VERSION_SOURCE_INVALID");
  const sourceDigest = await sha256Hex(html);
  if (sourceDigest !== textValue(version.source_sha256)) throw new Error("VERSION_SOURCE_MISMATCH");

  const projectSpecId = textValue(version.project_spec_id);
  const buildJobId = textValue(version.build_job_id);
  const sourceCommit = textValue(version.source_commit);
  const artifactDigest = textValue(version.artifact_digest_sha256);
  if (!projectSpecId || !buildJobId || !/^[0-9a-f]{40}$/.test(sourceCommit) || !/^[0-9a-f]{64}$/.test(artifactDigest)) throw new Error("VERIFICATION_REQUIRED");

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
  if (textValue(preview.source_commit_sha) && textValue(preview.source_commit_sha) !== sourceCommit) throw new Error("VERIFICATION_IDENTITY_MISMATCH");

  let verificationQuery = admin.from("pandora_verification_runs")
    .select("id, project_spec_id, project_version_id, build_job_id, source_commit, source_digest, artifact_digest, migration_set_digest, runtime_target_digest, preview_deployment_id, target_environment, status, completed_at, created_at")
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
      textValue(verification.build_job_id) !== buildJobId || textValue(verification.source_commit) !== sourceCommit ||
      textValue(verification.source_digest) !== sourceDigest || textValue(verification.artifact_digest) !== artifactDigest ||
      textValue(verification.migration_set_digest) !== textValue(version.migration_set_digest_sha256) ||
      textValue(verification.runtime_target_digest) !== textValue(version.runtime_target_digest_sha256) ||
      textValue(verification.preview_deployment_id) !== previewDeploymentId) throw new Error("VERIFICATION_IDENTITY_MISMATCH");
  const completedAt = Date.parse(textValue(verification.completed_at));
  const versionCreatedAt = Date.parse(textValue(version.created_at));
  const previewCreatedAt = Date.parse(textValue(preview.created_at));
  if (!Number.isFinite(completedAt) || !Number.isFinite(versionCreatedAt) || !Number.isFinite(previewCreatedAt) || completedAt < Math.max(versionCreatedAt, previewCreatedAt)) throw new Error("VERIFICATION_STALE");

  const { data: currentEnvironment, error: environmentError } = await admin.from("pandora_runtime_environments")
    .select("id, current_version_id, current_deployment_id").eq("project_id", projectId).eq("environment", "production").maybeSingle();
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

    if (currentEnvironment) {
      let environmentUpdate = admin.from("pandora_runtime_environments")
        .update({ current_version_id: requestedVersion, current_deployment_id: preview.id, status: "ready", verification_state: "live_verified", last_reconciled_at: new Date().toISOString(), updated_at: new Date().toISOString() })
        .eq("id", currentEnvironment.id);
      environmentUpdate = expectedProductionVersionId == null ? environmentUpdate.is("current_version_id", null) : environmentUpdate.eq("current_version_id", expectedProductionVersionId);
      const { data: updatedEnvironment, error: environmentUpdateError } = await environmentUpdate.select("id").maybeSingle();
      if (environmentUpdateError || !updatedEnvironment) throw new Error("PRODUCTION_PRECONDITION_MISMATCH");
    } else {
      const { error: environmentInsertError } = await admin.from("pandora_runtime_environments").insert({ organization_id: context.organizationId, project_id: projectId, environment: "production", provider: "vercel", provider_project_id: provider.id, status: "ready", current_version_id: requestedVersion, current_deployment_id: preview.id, verification_state: "live_verified", last_reconciled_at: new Date().toISOString() });
      if (environmentInsertError) throw new Error("PRODUCTION_PRECONDITION_MISMATCH");
    }

    const { data: productionRow, error: productionError } = await admin.from("pandora_project_deployments").insert({
      organization_id: context.organizationId, project_id: projectId, version_id: requestedVersion, provider: "vercel", environment: "production",
      provider_project_id: provider.id, provider_deployment_id: previewDeploymentId, url: deploymentUrl, status, source_sha256: sourceDigest,
      promoted_from_id: preview.id, artifact_digest: artifactDigest, source_commit_sha: sourceCommit, verification_ref: textValue(verification.id), verification_state: "live_verified",
      provider_state: providerState, immutable_url: deploymentUrl, metadata: { providerName: provider.name, promotionOnly: true, verificationRunId: textValue(verification.id) },
    }).select("id, version_id, environment, provider_deployment_id, url, status, source_sha256, created_at").single();
    if (productionError || !productionRow) throw new Error("BACKEND_WRITE_FAILED");

    if (currentVersionId) await admin.from("pandora_project_versions").update({ rollback_eligible: true }).eq("organization_id", context.organizationId).eq("project_id", projectId).eq("id", currentVersionId);
    const { error: versionPromoteError } = await admin.from("pandora_project_versions")
      .update({ lifecycle_status: "live", promoted_at: new Date().toISOString(), rollback_eligible: true, verification_run_id: textValue(verification.id) })
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
    const liveUrl = domain && domainVerified ? `https://${domain}` : deploymentUrl;
    const nextConfig = { ...config, customerJourney: { ...journey, stage: "live", runtimeStatus: "ready", liveUrl, productionDeploymentId: previewDeploymentId, publishedVersionId: requestedVersion, requestedDomain: domain, domainStatus, runtimeUpdatedAt: new Date().toISOString() } };
    const { error: projectError } = await admin.from("projectos_projects").update({ config: nextConfig, updated_at: new Date().toISOString() }).eq("organization_id", context.organizationId).eq("id", projectId);
    if (projectError) throw new Error("BACKEND_WRITE_FAILED");
    await admin.from("pandora_runtime_operations").update({ status: "succeeded", ambiguous: false, provider_resource_id: previewDeploymentId, result_facts: { projectVersionId: requestedVersion, providerDeploymentId: previewDeploymentId, verificationRunId: textValue(verification.id), promotedFromDeploymentId: previewDeploymentId }, finished_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", operationId);
    return { project: projectResponse({ ...project, config: nextConfig }), production: productionRow, domain: domainRow, liveUrl, domainVerified };
  } catch (error) {
    const code = error instanceof Error ? error.message : "PROJECT_RUNTIME_ERROR";
    if (providerMutationStarted) {
      await admin.from("pandora_runtime_operations").update({ status: "uncertain", ambiguous: true, normalized_error: { code: "reconciliation_required" }, updated_at: new Date().toISOString() }).eq("id", operationId);
      if (code !== "PRODUCTION_PRECONDITION_MISMATCH") throw new Error("PUBLISH_RECONCILIATION_REQUIRED");
    } else {
      await admin.from("pandora_runtime_operations").update({ status: "failed", ambiguous: false, normalized_error: { code }, finished_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", operationId);
    }
    throw error;
  }
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
    if (req.method === "POST" && previewMatch) return jsonResponse(await createPreview(context, decodeURIComponent(previewMatch[1])), 201, requestId, origin);
    const publishMatch = route.match(/^\/projects\/([^/]+)\/publish$/);
    if (req.method === "POST" && publishMatch) return jsonResponse(await publishProject(context, decodeURIComponent(publishMatch[1]), await bodyJson(req)), 201, requestId, origin);
    return jsonResponse({ code: "PROJECT_RUNTIME_ROUTE_NOT_FOUND", plainMessage: "That project action is not available yet.", requestId }, 404, requestId, origin);
  } catch (error) {
    const code = error instanceof Error ? error.message : "PROJECT_RUNTIME_ERROR";
    const invalid = new Set(["INVALID_JSON", "BODY_TOO_LARGE", "INVALID_PROJECT_NAME", "INVALID_OBJECTIVE", "INVALID_BUILD_KIND", "INVALID_DOMAIN"]);
    const conflicts = new Set(["PREVIEW_REQUIRED", "VERSION_SOURCE_INVALID", "VERSION_SOURCE_MISMATCH", "VERCEL_CONFLICT", "VERCEL_DOMAIN_REJECTED"]);
    if (code === "SIGN_IN_REQUIRED") return jsonResponse({ code, plainMessage: "Please sign in again.", requestId }, 401, requestId, origin);
    if (["ORGANIZATION_ACCESS_REQUIRED", "OWNER_ROLE_REQUIRED"].includes(code)) return jsonResponse({ code, plainMessage: "You do not have permission for this project.", requestId }, 403, requestId, origin);
    if (code === "ORGANIZATION_SELECTION_REQUIRED") return jsonResponse({ code, plainMessage: "Choose which organization you want to use.", requestId }, 409, requestId, origin);
    if (code === "RATE_LIMITED") return jsonResponse({ code, plainMessage: "Please wait a moment before trying again.", requestId }, 429, requestId, origin);
    if (invalid.has(code)) return jsonResponse({ code, plainMessage: "Check that project information and try again.", requestId }, 400, requestId, origin);
    if (code === "PROJECT_NOT_FOUND") return jsonResponse({ code, plainMessage: "Pandora could not find that project.", requestId }, 404, requestId, origin);
    if (conflicts.has(code)) return jsonResponse({ code, plainMessage: "That project cannot be published in its current state.", requestId }, 409, requestId, origin);
    if (code === "VERCEL_NOT_CONFIGURED") return jsonResponse({ code, plainMessage: "Project previews are temporarily unavailable.", requestId }, 503, requestId, origin);
    console.error(JSON.stringify({ requestId, code }));
    return jsonResponse({ code: "PROJECT_RUNTIME_UNAVAILABLE", plainMessage: "Pandora cannot reach the project runtime right now.", requestId }, 503, requestId, origin);
  }
});
