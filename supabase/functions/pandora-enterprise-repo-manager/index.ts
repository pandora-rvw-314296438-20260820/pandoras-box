import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const MAX_BODY_BYTES = 8192;
const MAX_REPO_FILES = 500;
const MAX_DEPLOY_BYTES = 250 * 1024 * 1024;
const MAX_DEPLOY_FILE_BYTES = 100 * 1024 * 1024;

type JsonRecord = Record<string, unknown>;
type UserContext = {
  userId: string;
  organizationId: string;
  authorization: string;
};
type RepoFile = { path: string; size: number; sha: string };
type VercelRuntime = { token: string; teamId: string };

function rec(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}
function text(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}
function jsonResponse(body: unknown, status = 200) {
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
function decodeBase64(value: string) {
  const normalized = value.replace(/\s+/g, "");
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
function decodeUtf8Base64(value: string) {
  return new TextDecoder().decode(decodeBase64(value));
}
function parseRepositoryUrl(value: string) {
  let url: URL;
  try {
    url = new URL(value.trim());
  } catch {
    throw new Error("INVALID_REPOSITORY_URL");
  }
  if (url.protocol !== "https:" || url.hostname.toLowerCase() !== "github.com") {
    throw new Error("INVALID_REPOSITORY_URL");
  }
  const parts = url.pathname.replace(/^\/+|\/+$/g, "").split("/");
  if (parts.length !== 2) throw new Error("INVALID_REPOSITORY_URL");
  const owner = parts[0];
  const repo = parts[1].replace(/\.git$/i, "");
  if (!/^[A-Za-z0-9_.-]+$/.test(owner) || !/^[A-Za-z0-9_.-]+$/.test(repo)) {
    throw new Error("INVALID_REPOSITORY_URL");
  }
  return {
    owner,
    repo,
    fullName: `${owner}/${repo}`,
    htmlUrl: `https://github.com/${owner}/${repo}`,
  };
}
function encodeRepoPath(path: string) {
  return path.split("/").map((part) => encodeURIComponent(part)).join("/");
}
async function authenticate(req: Request): Promise<UserContext> {
  const authorization = req.headers.get("authorization") || "";
  if (!/^Bearer\s+\S+$/i.test(authorization)) throw new Error("SIGN_IN_REQUIRED");
  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await client.auth.getUser();
  if (authError || !authData.user) throw new Error("SIGN_IN_REQUIRED");

  const requestedOrganization = req.headers.get("x-organization-id")?.trim() || null;
  let query = client.from("memberships")
    .select("organization_id, role, status")
    .eq("user_id", authData.user.id)
    .eq("status", "active")
    .limit(3);
  if (requestedOrganization) query = query.eq("organization_id", requestedOrganization);
  const { data: memberships, error } = await query;
  if (error || !memberships?.length) throw new Error("ORGANIZATION_ACCESS_REQUIRED");
  if (!requestedOrganization && memberships.length > 1) {
    throw new Error("ORGANIZATION_SELECTION_REQUIRED");
  }
  if (!["owner", "admin"].includes(String(memberships[0].role))) {
    throw new Error("OWNER_ROLE_REQUIRED");
  }
  return { userId: authData.user.id, organizationId: String(memberships[0].organization_id), authorization };
}
function base64UrlBytes(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
function base64UrlText(value: string) {
  return base64UrlBytes(new TextEncoder().encode(value));
}
function pemDer(value: string) {
  const body = value.replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  return decodeBase64(body);
}
function derLength(length: number) {
  if (length < 128) return new Uint8Array([length]);
  const parts: number[] = [];
  let value = length;
  while (value > 0) { parts.unshift(value & 0xff); value >>= 8; }
  return new Uint8Array([0x80 | parts.length, ...parts]);
}
function concatBytes(...parts: Uint8Array[]) {
  const length = parts.reduce((sum, item) => sum + item.length, 0);
  const out = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) { out.set(part, offset); offset += part.length; }
  return out;
}
function derWrap(tag: number, body: Uint8Array) {
  return concatBytes(new Uint8Array([tag]), derLength(body.length), body);
}
function pkcs1ToPkcs8(pkcs1: Uint8Array) {
  const version = new Uint8Array([0x02, 0x01, 0x00]);
  const rsaAlgorithmIdentifier = new Uint8Array([
    0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7,
    0x0d, 0x01, 0x01, 0x01, 0x05, 0x00,
  ]);
  return derWrap(0x30, concatBytes(
    version,
    rsaAlgorithmIdentifier,
    derWrap(0x04, pkcs1),
  ));
}
async function githubAppJwt(appId: number, privateKeyPem: string) {
  const decoded = pemDer(privateKeyPem);
  const keyData = privateKeyPem.includes("BEGIN RSA PRIVATE KEY")
    ? pkcs1ToPkcs8(decoded)
    : decoded;
  const privateKey = await crypto.subtle.importKey(
    "pkcs8", keyData,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false, ["sign"],
  );
  const now = Math.floor(Date.now() / 1000);
  const signingInput = `${base64UrlText(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${base64UrlText(JSON.stringify({ iat: now - 30, exp: now + 540, iss: appId }))}`;
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", privateKey,
    new TextEncoder().encode(signingInput),
  ));
  return `${signingInput}.${base64UrlBytes(signature)}`;
}

async function githubInstallationToken(admin: ReturnType<typeof adminClient>) {
  const { data, error } = await admin.rpc("pandora_get_github_app_runtime_material");
  if (error) throw new Error("GITHUB_APP_UNAVAILABLE");
  const material = rec(data);
  const appId = Number(material.appId);
  const installationId = Number(material.installationId);
  const privateKeyPem = text(material.privateKeyPem);
  if (!Number.isInteger(appId) || !Number.isInteger(installationId) || !privateKeyPem.includes("PRIVATE KEY")) {
    throw new Error("GITHUB_APP_UNAVAILABLE");
  }
  const jwt = await githubAppJwt(appId, privateKeyPem);
  const response = await fetch(`https://api.github.com/app/installations/${installationId}/access_tokens`, {
    method: "POST",
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${jwt}`,
      "content-type": "application/json",
      "user-agent": "Pandora-Enterprise-Repository-Intake/1.0",
      "x-github-api-version": "2022-11-28",
    },
    body: "{}",
    signal: AbortSignal.timeout(12000),
  });
  const payload = rec(await response.json().catch(() => ({})));
  const token = text(payload.token);
  if (response.status !== 201 || !token) throw new Error("GITHUB_APP_UNAVAILABLE");
  return token;
}

async function githubAppGet(admin: ReturnType<typeof adminClient>, path: string) {
  try {
    const token = await githubInstallationToken(admin);
    const response = await fetch(`https://api.github.com${path}`, {
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${token}`,
        "user-agent": "Pandora-Enterprise-Repository-Intake/1.0",
        "x-github-api-version": "2022-11-28",
      },
      signal: AbortSignal.timeout(15000),
    });
    const body = await response.json().catch(() => null);
    return { status: response.status, body };
  } catch {
    return null;
  }
}

async function githubVaultGet(admin: ReturnType<typeof adminClient>, path: string) {
  const { data, error } = await admin.rpc("pandora_enterprise_github_runtime_material_20260917");
  if (error) throw new Error("GITHUB_PROVIDER_FAILED");
  const token = text(rec(data).token);
  if (!token) throw new Error("GITHUB_PROVIDER_FAILED");
  const response = await fetch(`https://api.github.com${path}`, {
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${token}`,
      "user-agent": "Pandora-Enterprise-Repository-Intake/1.2",
      "x-github-api-version": "2022-11-28",
    },
    signal: AbortSignal.timeout(30000),
  });
  const body = await response.json().catch(() => null);
  return { status: response.status, body };
}

async function githubGet(admin: ReturnType<typeof adminClient>, path: string) {
  const app = await githubAppGet(admin, path);
  if (app && app.status >= 200 && app.status < 300) {
    return { ...app, source: "github_app" };
  }
  const fallback = await githubVaultGet(admin, path);
  if (fallback.status < 200 || fallback.status >= 300) {
    const error = rec(fallback.body).message;
    throw new Error(text(error) || "GITHUB_REPOSITORY_UNAVAILABLE");
  }
  return { ...fallback, source: "vault_fallback" };
}

async function readBody(req: Request) {
  const raw = await req.text();
  if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) throw new Error("INVALID_REQUEST");
  let parsed: unknown;
  try { parsed = JSON.parse(raw || "{}"); } catch { throw new Error("INVALID_REQUEST"); }
  const body = rec(parsed);
  const action = text(body.action || "inspect").toLowerCase();
  if (!["inspect", "deploy", "status"].includes(action)) throw new Error("INVALID_REQUEST");
  const repositoryUrl = text(body.repositoryUrl);
  const deploymentId = text(body.deploymentId);
  if (action !== "status" && !repositoryUrl) throw new Error("INVALID_REPOSITORY_URL");
  if (action === "status" && !/^dpl_[A-Za-z0-9]+$/.test(deploymentId)) {
    throw new Error("INVALID_DEPLOYMENT_ID");
  }
  return { action, repositoryUrl, deploymentId };
}

async function listRepositoryFiles(
  admin: ReturnType<typeof adminClient>,
  owner: string,
  repo: string,
  ref: string,
) {
  const queue = [""];
  const files: RepoFile[] = [];
  while (queue.length) {
    const directory = queue.shift()!;
    const suffix = directory ? `/${encodeRepoPath(directory)}` : "";
    const result = await githubGet(admin, `/repos/${owner}/${repo}/contents${suffix}?ref=${encodeURIComponent(ref)}`);
    const entries = Array.isArray(result.body) ? result.body : [];
    for (const raw of entries) {
      const entry = rec(raw);
      const type = text(entry.type);
      const path = text(entry.path);
      if (!path) continue;
      if (type === "dir") {
        queue.push(path);
      } else if (type === "file") {
        files.push({
          path,
          size: Math.max(0, Number(entry.size || 0)),
          sha: text(entry.sha),
        });
      }
      if (files.length + queue.length > MAX_REPO_FILES) {
        throw new Error("REPOSITORY_TOO_LARGE");
      }
    }
  }
  return files.sort((a, b) => a.path.localeCompare(b.path));
}

async function readRepositoryFile(
  admin: ReturnType<typeof adminClient>, owner: string, repo: string,
  path: string, ref: string,
) {
  const result = await githubGet(admin, `/repos/${owner}/${repo}/contents/${encodeRepoPath(path)}?ref=${encodeURIComponent(ref)}`);
  const body = rec(result.body);
  if (text(body.encoding) !== "base64" || !text(body.content)) return null;
  return { text: decodeUtf8Base64(text(body.content)), base64: text(body.content).replace(/\s+/g, "") };
}
async function readRepositoryBytes(
  admin: ReturnType<typeof adminClient>, owner: string, repo: string,
  path: string, ref: string,
) {
  const result = await githubGet(admin, `/repos/${owner}/${repo}/contents/${encodeRepoPath(path)}?ref=${encodeURIComponent(ref)}`);
  const body = rec(result.body);
  const inlineRaw = typeof body.content === "string" ? body.content : "";
  const inline = inlineRaw.trim();
  if (text(body.encoding) === "base64") {
    if (inline) return decodeBase64(inline);
    if (Number(body.size || 0) === 0) return new Uint8Array(0);
  }
  const blobSha = text(body.sha);
  if (!/^[0-9a-f]{40}$/i.test(blobSha)) return null;
  const blobResult = await githubGet(admin, `/repos/${owner}/${repo}/git/blobs/${blobSha}`);
  const blob = rec(blobResult.body);
  if (text(blob.encoding) !== "base64") return null;
  const blobContent = typeof blob.content === "string" ? blob.content : "";
  if (!blobContent.trim() && Number(blob.size || 0) === 0) return new Uint8Array(0);
  if (!blobContent.trim()) return null;
  return decodeBase64(blobContent);
}

function ignoredByVercel(path: string, patterns: string[]) {
  for (const raw of patterns) {
    const pattern = raw.trim().replace(/^\/+/, "");
    if (!pattern || pattern.startsWith("#") || pattern.startsWith("!")) continue;
    if (pattern.endsWith("/*") && path.startsWith(pattern.slice(0, -1))) return true;
    if (!pattern.includes("*") && path === pattern) return true;
  }
  return false;
}

async function sha1Hex(bytes: Uint8Array) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-1", bytes));
  return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function vercelRuntimeMaterial(admin: ReturnType<typeof adminClient>): Promise<VercelRuntime> {
  const { data, error } = await admin.rpc("pandora_enterprise_vercel_runtime_material_20260917");
  if (error) throw new Error("VERCEL_PROVIDER_FAILED");
  const material = rec(data);
  const token = text(material.token);
  const teamId = text(material.teamId);
  if (!token || !/^team_[A-Za-z0-9]+$/.test(teamId)) throw new Error("VERCEL_PROVIDER_FAILED");
  return { token, teamId };
}

async function uploadVercelFile(runtime: VercelRuntime, digest: string, bytes: Uint8Array) {
  const response = await fetch(`https://api.vercel.com/v2/files?teamId=${encodeURIComponent(runtime.teamId)}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${runtime.token}`,
      "content-type": "application/octet-stream",
      "user-agent": "Pandora-Enterprise-Repository-Intake/1.1",
      "x-vercel-digest": digest,
    },
    body: bytes,
    signal: AbortSignal.timeout(60000),
  });
  if (![200, 201, 409].includes(response.status)) {
    const payload = rec(await response.json().catch(() => ({})));
    const error = rec(payload.error);
    throw new Error(text(error.message) || "VERCEL_FILE_UPLOAD_FAILED");
  }
}
function detectEnvironmentNames(...texts: string[]) {
  const names = new Set<string>();
  const patterns = [
    /(?:^|\n)\s*([A-Z][A-Z0-9_]{2,})\s*=/g,
    /process\.env\.([A-Z][A-Z0-9_]{2,})/g,
    /Deno\.env\.get\(["']([A-Z][A-Z0-9_]{2,})["']\)/g,
    /import\.meta\.env\.([A-Z][A-Z0-9_]{2,})/g,
  ];
  for (const source of texts) {
    for (const pattern of patterns) {
      pattern.lastIndex = 0;
      let match: RegExpExecArray | null;
      while ((match = pattern.exec(source)) !== null) names.add(match[1]);
    }
  }
  return [...names].sort();
}

function detectStack(packageJson: JsonRecord, files: RepoFile[]) {
  const dependencies = { ...rec(packageJson.dependencies), ...rec(packageJson.devDependencies) };
  const names = new Set(Object.keys(dependencies));
  const stack: string[] = [];
  if (names.has("react")) stack.push("React");
  if (names.has("vite")) stack.push("Vite");
  if (names.has("next")) stack.push("Next.js");
  if (names.has("tailwindcss")) stack.push("Tailwind CSS");
  if (names.has("@vercel/functions") || files.some((file) => file.path.startsWith("api/"))) stack.push("Vercel Functions");
  if (files.some((file) => file.path.startsWith("supabase/"))) stack.push("Supabase");
  if (files.some((file) => /paypal/i.test(file.path))) stack.push("PayPal");
  return stack;
}

async function inspectRepository(
  admin: ReturnType<typeof adminClient>,
  repositoryUrl: string,
) {
  const parsed = parseRepositoryUrl(repositoryUrl);
  const repoResult = await githubGet(admin, `/repos/${parsed.owner}/${parsed.repo}`);
  const repository = rec(repoResult.body);
  const defaultBranch = text(repository.default_branch) || "main";
  const commitResult = await githubGet(
    admin,
    `/repos/${parsed.owner}/${parsed.repo}/commits/${encodeURIComponent(defaultBranch)}`,
  );
  const commit = rec(commitResult.body);
  const exactSha = text(commit.sha);
  if (!/^[0-9a-f]{40}$/i.test(exactSha)) throw new Error("GITHUB_SOURCE_UNVERIFIED");
  const languagesResult = await githubGet(admin, `/repos/${parsed.owner}/${parsed.repo}/languages`);
  const languages = rec(languagesResult.body);
  const files = await listRepositoryFiles(admin, parsed.owner, parsed.repo, exactSha);
  const byPath = new Map(files.map((file) => [file.path.toLowerCase(), file]));
  const packageFile = byPath.get("package.json");
  const vercelFile = byPath.get("vercel.json");
  const readmeFile = byPath.get("readme.md");
  const packageSource = packageFile
    ? await readRepositoryFile(admin, parsed.owner, parsed.repo, packageFile.path, exactSha)
    : null;
  const vercelSource = vercelFile
    ? await readRepositoryFile(admin, parsed.owner, parsed.repo, vercelFile.path, exactSha)
    : null;
  const readmeSource = readmeFile
    ? await readRepositoryFile(admin, parsed.owner, parsed.repo, readmeFile.path, exactSha)
    : null;
  let packageJson: JsonRecord = {};
  let vercelJson: JsonRecord = {};
  try { packageJson = rec(JSON.parse(packageSource?.text || "{}")); } catch { /* invalid config is surfaced below */ }
  try { vercelJson = rec(JSON.parse(vercelSource?.text || "{}")); } catch { /* invalid config is surfaced below */ }
  const scripts = rec(packageJson.scripts);
  const buildScript = text(scripts.build);
  const stack = detectStack(packageJson, files);
  const framework = stack.includes("Vite") ? "vite" : stack.includes("Next.js") ? "nextjs" : "other";
  const outputDirectory = framework === "vite" ? "dist" : framework === "nextjs" ? ".next" : null;
  const envNames = detectEnvironmentNames(
    readmeSource?.text || "",
    packageSource?.text || "",
    vercelSource?.text || "",
  );
  const apiFiles = files.filter((file) => file.path.startsWith("api/"));
  const migrationFiles = files.filter((file) => /^supabase\/migrations\//.test(file.path));
  return {
    repository: {
      id: Number(repository.id || 0),
      name: text(repository.name),
      fullName: text(repository.full_name) || parsed.fullName,
      htmlUrl: text(repository.html_url) || parsed.htmlUrl,
      private: repository.private === true,
      visibility: text(repository.visibility),
      defaultBranch,
      exactSha,
      primaryLanguage: text(repository.language),
      languages,
      sizeKb: Number(repository.size || 0),
      pushedAt: text(repository.pushed_at),
      accessPath: repoResult.source,
    },
    detected: {
      framework,
      stack,
      packageName: text(packageJson.name),
      packageVersion: text(packageJson.version),
      buildCommand: buildScript ? "npm run build" : null,
      buildScript: buildScript || null,
      installCommand: packageFile ? "npm install" : null,
      outputDirectory,
      serverlessFunctionCount: apiFiles.length,
      supabaseMigrationCount: migrationFiles.length,
      fileCount: files.length,
      environmentVariables: envNames,
      hasVercelConfig: vercelFile != null,
      rewriteCount: Array.isArray(vercelJson.rewrites) ? vercelJson.rewrites.length : 0,
      redirectCount: Array.isArray(vercelJson.redirects) ? vercelJson.redirects.length : 0,
      headerRuleCount: Array.isArray(vercelJson.headers) ? vercelJson.headers.length : 0,
      documentedRuntimeConfigurationRequired: envNames.length > 0,
    },
    files,
  };
}

async function vercelRequest(
  admin: ReturnType<typeof adminClient>, method: string, path: string,
  body: JsonRecord | null = null,
) {
  const { data, error } = await admin.rpc("pandora_worker_f_vercel_request_20260829", {
    p_method: method,
    p_path: path,
    p_body: body,
  });
  if (error) throw new Error("VERCEL_PROVIDER_FAILED");
  const envelope = rec(data);
  return { status: Number(envelope.status || 0), body: rec(envelope.body) };
}

async function vercelTeamId(admin: ReturnType<typeof adminClient>) {
  const { data, error } = await admin.from("pandora_runtime_provider_configs")
    .select("config_value")
    .eq("provider", "vercel")
    .eq("config_key", "team_id")
    .eq("active", true)
    .single();
  const teamId = text(rec(data).config_value);
  if (error || !/^team_[A-Za-z0-9]+$/.test(teamId)) throw new Error("VERCEL_PROVIDER_FAILED");
  return teamId;
}

function safeProjectKey(repoName: string, repoId: number) {
  const slug = repoName.toLowerCase().replace(/[^a-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "").slice(0, 52) || "repo";
  return `enterprise-${slug}-${String(repoId).slice(-8)}`.slice(0, 80);
}

async function resolveProject(
  admin: ReturnType<typeof adminClient>,
  context: UserContext,
  inspection: JsonRecord,
) {
  const repository = rec(inspection.repository);
  const fullName = text(repository.fullName);
  const repoName = text(repository.name);
  const repoId = Number(repository.id || 0);
  const { data: existing, error: existingError } = await admin.from("projectos_projects")
    .select("id, project_key, name, repository, config")
    .eq("organization_id", context.organizationId)
    .eq("repository", fullName)
    .maybeSingle();
  if (existingError) throw new Error("PROJECTOS_READ_FAILED");
  let project = existing ? rec(existing) : null;
  if (!project) {
    const projectKey = safeProjectKey(repoName, repoId);
    const { data: created, error } = await admin.from("projectos_projects").insert({
      organization_id: context.organizationId,
      project_key: projectKey,
      name: repoName || fullName,
      repository: fullName,
      workspace_path: `projectos/projects/${projectKey}`,
      status: "active",
      objective: `Manage and deploy ${fullName} through Pandora Enterprise.`,
      created_by: context.userId,
      config: {
        customerJourney: {
          createdFrom: "enterprise_repo_import",
          githubRepository: fullName,
          githubDefaultBranch: text(repository.defaultBranch),
          githubProvisioningState: "linked_existing",
        },
      },
    }).select("id, project_key, name, repository, config").single();
    if (error || !created) throw new Error("PROJECTOS_WRITE_FAILED");
    project = rec(created);
  }
  return project;
}
async function resolveVercelProject(
  admin: ReturnType<typeof adminClient>,
  project: JsonRecord,
  teamId: string,
) {
  const config = rec(project.config);
  const journey = rec(config.customerJourney);
  let projectId = text(journey.vercelProjectId);
  let projectName = text(journey.vercelProjectName);
  if (projectId) {
    const current = await vercelRequest(admin, "GET", `/v9/projects/${projectId}?teamId=${teamId}`);
    if (current.status === 200) {
      return { id: projectId, name: text(current.body.name) || projectName };
    }
    projectId = "";
  }

  const suffix = text(project.id).replace(/-/g, "").slice(0, 8);
  const base = text(project.name).toLowerCase().replace(/[^a-z0-9-]+/g, "-")
    .replace(/^-+|-+$/g, "").slice(0, 55) || "project";
  projectName = `pandora-${base}-${suffix}`.slice(0, 100);
  const created = await vercelRequest(admin, "POST", `/v11/projects?teamId=${teamId}`, {
    name: projectName,
    framework: null,
    skipGitConnectDuringLink: true,
    enablePreviewFeedback: true,
    enableProductionFeedback: true,
  });
  if (created.status !== 200 && created.status !== 201) throw new Error("VERCEL_PROJECT_CREATE_FAILED");
  projectId = text(created.body.id);
  if (!/^prj_[A-Za-z0-9]+$/.test(projectId)) throw new Error("VERCEL_PROJECT_CREATE_FAILED");

  const nextConfig = {
    ...config,
    customerJourney: {
      ...journey,
      vercelProjectId: projectId,
      vercelProjectName: projectName,
      vercelProjectCreatedAt: new Date().toISOString(),
    },
  };
  const { error } = await admin.from("projectos_projects")
    .update({ config: nextConfig, updated_at: new Date().toISOString() })
    .eq("id", text(project.id));
  if (error) throw new Error("PROJECTOS_WRITE_FAILED");
  return { id: projectId, name: projectName };
}

async function collectUploadedFiles(
  admin: ReturnType<typeof adminClient>,
  inspection: JsonRecord,
) {
  const repository = rec(inspection.repository);
  const fullName = text(repository.fullName);
  const [owner, repo] = fullName.split("/");
  const exactSha = text(repository.exactSha);
  const allFiles = Array.isArray(inspection.files)
    ? inspection.files.map((item) => rec(item))
    : [];

  const ignoreSource = allFiles.some((file) => text(file.path) === ".vercelignore")
    ? await readRepositoryFile(admin, owner, repo, ".vercelignore", exactSha)
    : null;
  const ignorePatterns = (ignoreSource?.text || "").split(/\r?\n/);
  const files = allFiles.filter((file) => !ignoredByVercel(text(file.path), ignorePatterns));

  let totalBytes = 0;
  for (const file of files) {
    const size = Math.max(0, Number(file.size || 0));
    if (size > MAX_DEPLOY_FILE_BYTES) throw new Error("REPOSITORY_FILE_TOO_LARGE");
    totalBytes += size;
  }
  if (totalBytes > MAX_DEPLOY_BYTES) throw new Error("REPOSITORY_TOO_LARGE");

  const runtime = await vercelRuntimeMaterial(admin);
  const output: JsonRecord[] = [];
  for (let offset = 0; offset < files.length; offset += 4) {
    const batch = files.slice(offset, offset + 4);
    const resolved = await Promise.all(batch.map(async (file) => {
      const path = text(file.path);
      const bytes = await readRepositoryBytes(admin, owner, repo, path, exactSha);
      if (!bytes) throw new Error(`SOURCE_FILE_UNAVAILABLE:${path}`);
      const expectedSize = Math.max(0, Number(file.size || 0));
      if (expectedSize && bytes.byteLength !== expectedSize) throw new Error(`SOURCE_FILE_SIZE_MISMATCH:${path}`);
      const digest = await sha1Hex(bytes);
      await uploadVercelFile(runtime, digest, bytes);
      return { file: path, sha: digest, size: bytes.byteLength };
    }));
    output.push(...resolved);
  }
  return { files: output, totalBytes };
}

async function deployRepository(
  admin: ReturnType<typeof adminClient>,
  context: UserContext,
  inspection: JsonRecord,
) {
  const repository = rec(inspection.repository);
  const detected = rec(inspection.detected);
  const project = await resolveProject(admin, context, inspection);
  const teamId = await vercelTeamId(admin);
  const vercelProject = await resolveVercelProject(admin, project, teamId);
  const repoId = Number(repository.id || 0);
  const exactSha = text(repository.exactSha);
  const defaultBranch = text(repository.defaultBranch) || "main";

  const gitAttempt = await vercelRequest(admin, "POST", `/v13/deployments?teamId=${teamId}`, {
    name: vercelProject.name,
    project: vercelProject.id,
    target: "production",
    gitSource: {
      type: "github",
      repoId,
      ref: defaultBranch,
      sha: exactSha,
    },
  });
  if (gitAttempt.status >= 200 && gitAttempt.status < 300) {
    return deploymentResult(gitAttempt.body, project, vercelProject, "vercel_git");
  }

  const gitError = rec(gitAttempt.body.error);
  if (text(gitError.code) !== "incorrect_git_source_info") {
    throw new Error(text(gitError.message) || "VERCEL_DEPLOY_FAILED");
  }
  const uploaded = await collectUploadedFiles(admin, inspection);
  const projectSettings: JsonRecord = {};
  if (text(detected.buildCommand)) projectSettings.buildCommand = text(detected.buildCommand);
  if (text(detected.installCommand)) projectSettings.installCommand = text(detected.installCommand);
  if (text(detected.outputDirectory)) projectSettings.outputDirectory = text(detected.outputDirectory);

  const fileAttempt = await vercelRequest(admin, "POST", `/v13/deployments?teamId=${teamId}`, {
    name: vercelProject.name,
    project: vercelProject.id,
    target: "production",
    files: uploaded.files,
    gitMetadata: {
      remoteUrl: text(repository.htmlUrl),
      commitRef: defaultBranch,
      commitSha: exactSha,
      dirty: false,
      ci: false,
      ciGitRepoVisibility: repository.private === true ? "private" : "public",
    },
    projectSettings,
    meta: {
      pandoraManaged: "true",
      pandoraSourceRepository: text(repository.fullName),
      pandoraSourceSha: exactSha,
      pandoraTransport: "vault_file_upload",
    },
  });
  if (fileAttempt.status < 200 || fileAttempt.status >= 300) {
    const error = rec(fileAttempt.body.error);
    throw new Error(text(error.message) || "VERCEL_DEPLOY_FAILED");
  }
  const result = deploymentResult(fileAttempt.body, project, vercelProject, "vault_file_upload");
  const config = rec(project.config);
  const journey = rec(config.customerJourney);
  const nextConfig = {
    ...config,
    customerJourney: {
      ...journey,
      githubRepository: text(repository.fullName),
      githubDefaultBranch: defaultBranch,
      canonicalMainSha: exactSha,
      vercelProjectId: vercelProject.id,
      vercelProjectName: vercelProject.name,
      lastEnterpriseDeploymentId: text(rec(result.deployment).id),
      lastEnterpriseDeploymentAt: new Date().toISOString(),
      lastEnterpriseDeploymentTransport: "vault_file_upload",
    },
  };
  await admin.from("projectos_projects")
    .update({ config: nextConfig, updated_at: new Date().toISOString() })
    .eq("id", text(project.id));
  return result;
}

function deploymentResult(
  payload: JsonRecord,
  project: JsonRecord,
  vercelProject: { id: string; name: string },
  transport: string,
) {
  const deploymentId = text(payload.id);
  if (!/^dpl_[A-Za-z0-9]+$/.test(deploymentId)) throw new Error("VERCEL_DEPLOY_FAILED");
  return {
    project: {
      id: text(project.id),
      key: text(project.project_key),
      name: text(project.name),
      repository: text(project.repository),
    },
    vercelProject: { id: vercelProject.id, name: vercelProject.name },
    deployment: {
      id: deploymentId,
      url: text(payload.url),
      status: text(payload.readyState || payload.status) || "QUEUED",
      target: text(payload.target) || "production",
      transport,
    },
  };
}

async function deploymentStatus(admin: ReturnType<typeof adminClient>, deploymentId: string) {
  const teamId = await vercelTeamId(admin);
  const result = await vercelRequest(
    admin,
    "GET",
    `/v13/deployments/${deploymentId}?teamId=${teamId}`,
  );
  if (result.status !== 200) throw new Error("DEPLOYMENT_NOT_FOUND");
  return {
    id: text(result.body.id),
    url: text(result.body.url),
    status: text(result.body.readyState || result.body.status),
    target: text(result.body.target),
    readySubstate: text(result.body.readySubstate),
    aliasAssigned: result.body.aliasAssigned === true,
    alias: Array.isArray(result.body.alias)
      ? result.body.alias.filter((item) => typeof item === "string")
      : [],
    sourceSha: text(rec(result.body.meta).githubCommitSha) ||
      text(rec(result.body.meta).pandoraSourceSha),
  };
}

function errorStatus(code: string) {
  if (["SIGN_IN_REQUIRED"].includes(code)) return 401;
  if (["ORGANIZATION_ACCESS_REQUIRED", "OWNER_ROLE_REQUIRED"].includes(code)) return 403;
  if (["INVALID_REQUEST", "INVALID_REPOSITORY_URL", "INVALID_DEPLOYMENT_ID"].includes(code)) return 400;
  if (["GITHUB_REPOSITORY_UNAVAILABLE", "DEPLOYMENT_NOT_FOUND"].includes(code)) return 404;
  if (["REPOSITORY_TOO_LARGE", "REPOSITORY_FILE_TOO_LARGE"].includes(code)) return 413;
  return 500;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204 });
  if (req.method !== "POST") return jsonResponse({ ok: false, code: "METHOD_NOT_ALLOWED" }, 405);
  try {
    const context = await authenticate(req);
    const body = await readBody(req);
    const admin = adminClient();
    if (body.action === "status") {
      const status = await deploymentStatus(admin, body.deploymentId);
      return jsonResponse({ ok: true, action: "status", deployment: status });
    }

    const inspection = await inspectRepository(admin, body.repositoryUrl);
    if (body.action === "inspect") {
      const visible = { ...inspection };
      delete (visible as JsonRecord).files;
      return jsonResponse({ ok: true, action: "inspect", inspection: visible });
    }

    const deployment = await deployRepository(admin, context, inspection);
    const visible = { ...inspection };
    delete (visible as JsonRecord).files;
    return jsonResponse({
      ok: true,
      action: "deploy",
      inspection: visible,
      ...deployment,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "UNKNOWN_ERROR";
    const code = message.includes(":") ? message.split(":", 1)[0] : message;
    console.error("pandora-enterprise-repo-manager", code);
    return jsonResponse({ ok: false, code }, errorStatus(code));
  }
});
