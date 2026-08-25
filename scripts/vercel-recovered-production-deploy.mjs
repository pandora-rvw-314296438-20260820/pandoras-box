import { appendFile, readFile, readdir, stat } from "node:fs/promises";
import path from "node:path";

const token = process.env.VERCEL_TOKEN;
const teamId = process.env.VERCEL_TEAM_ID;
const projectId = process.env.VERCEL_PROJECT_ID;
const projectName = "mcpmaster";
const sourceBaseSha = "7398de0014485089150ab154cbcac5617c9fdd6c";
const expectedTree = "419e109c161f397ad77c874a4634b8f49985c3b0";
const aliases = [
  "mcpmaster.vercel.app",
  "pandoras-box-system.vercel.app",
  "mcpmaster-hazel.vercel.app",
];

if (!token || !teamId || !projectId) {
  throw new Error("Required Vercel deployment credentials or project identifiers are missing");
}

const rootFiles = new Set([
  ".npmrc",
  ".vercelignore",
  "package.json",
  "package-lock.json",
  "tsconfig.json",
  "tsconfig.vercel.json",
  "vercel.json",
  "vercel-entrypoint.js",
  "SOURCE_AUTHORITY_POLICY.json",
]);
const exactFiles = new Set([
  "apps/meta-business-mcp/package.json",
  "apps/meta-business-mcp/tsconfig.json",
  "packages/shared-security/package.json",
  "packages/shared-security/tsconfig.json",
]);
const prefixes = [
  "api/",
  "src/",
  "public/",
  "assets/brand/pandoras-box/",
  "apps/meta-business-mcp/src/",
  "packages/shared-security/src/",
  "supabase/migrations/",
  "docs/status/",
];

function selected(relative) {
  return rootFiles.has(relative) || exactFiles.has(relative) || prefixes.some((prefix) => relative.startsWith(prefix));
}

async function walk(directory, base = directory) {
  const output = [];
  for (const name of await readdir(directory)) {
    if (name === ".git" || name === "node_modules" || name === "dist" || name === "coverage" || name === ".vercel") continue;
    const absolute = path.join(directory, name);
    const info = await stat(absolute);
    if (info.isDirectory()) output.push(...await walk(absolute, base));
    else if (info.isFile()) output.push(path.relative(base, absolute).split(path.sep).join("/"));
  }
  return output;
}

const paths = (await walk(process.cwd())).filter(selected).sort();
if (paths.length < 50 || paths.length > 350) throw new Error(`Unexpected deployment file count: ${paths.length}`);
for (const required of rootFiles) {
  if (!paths.includes(required)) throw new Error(`Required deployment file is missing: ${required}`);
}

let sourceBytes = 0;
const files = [];
for (const file of paths) {
  const bytes = await readFile(file);
  sourceBytes += bytes.byteLength;
  files.push({ file, data: bytes.toString("base64"), encoding: "base64" });
}
if (sourceBytes < 500_000 || sourceBytes > 4_000_000) throw new Error(`Unexpected deployment source size: ${sourceBytes}`);

const headers = {
  authorization: `Bearer ${token}`,
  accept: "application/json",
  "content-type": "application/json",
  "user-agent": "Pandora-Recovered-Production-Actions/1.0",
};

async function jsonResponse(result) {
  const raw = await result.text();
  if (!raw) return {};
  try { return JSON.parse(raw); }
  catch { return { rawPrefix: raw.slice(0, 500) }; }
}

const createResult = await fetch(`https://api.vercel.com/v13/deployments?teamId=${encodeURIComponent(teamId)}&forceNew=1&skipAutoDetectionConfirmation=1`, {
  method: "POST",
  headers,
  body: JSON.stringify({
    name: projectName,
    project: projectId,
    target: "production",
    files,
    meta: {
      pandoraRecovery: "true",
      sourceRepository: process.env.GITHUB_REPOSITORY ?? "pandora-rvw-314296438-20260820/pandoras-box",
      sourceRef: "production/recovered-convergence-20260825",
      sourceBaseSha,
      sourceTree: expectedTree,
      automationCommitSha: process.env.GITHUB_SHA ?? "unknown",
      automationRunId: process.env.GITHUB_RUN_ID ?? "unknown",
    },
    projectSettings: {
      framework: "express",
      buildCommand: "npm run build",
      installCommand: "npm ci",
      nodeVersion: "24.x",
      skipGitConnectDuringLink: true,
      sourceFilesOutsideRootDirectory: false,
    },
  }),
});
const created = await jsonResponse(createResult);
if (!createResult.ok) {
  const code = created?.error?.code ?? created?.code ?? "error";
  const message = created?.error?.message ?? created?.message ?? "deployment submission failed";
  throw new Error(`Vercel deployment failed (${createResult.status} ${code}): ${message}`);
}

const deploymentId = created.id ?? created.uid;
const deploymentHost = created.url;
if (!deploymentId || !deploymentHost) throw new Error("Vercel deployment receipt is missing");

let deployment;
for (let attempt = 0; attempt < 180; attempt += 1) {
  await new Promise((resolve) => setTimeout(resolve, 5000));
  const result = await fetch(`https://api.vercel.com/v13/deployments/${deploymentId}?teamId=${encodeURIComponent(teamId)}`, { headers });
  deployment = await jsonResponse(result);
  if (!result.ok) throw new Error(`Vercel deployment status failed: ${result.status}`);
  const state = deployment.readyState ?? deployment.status ?? deployment.state;
  if (state === "READY") break;
  if (["ERROR", "CANCELED", "BLOCKED"].includes(state)) throw new Error(`Vercel deployment ended in ${state}`);
  if (attempt === 179) throw new Error("Vercel deployment did not become ready in time");
}

for (const alias of aliases) {
  const result = await fetch(`https://api.vercel.com/v2/deployments/${deploymentId}/aliases?teamId=${encodeURIComponent(teamId)}`, {
    method: "POST",
    headers,
    body: JSON.stringify({ alias }),
  });
  const body = await jsonResponse(result);
  if (!result.ok) throw new Error(`Alias ${alias} failed (${result.status}): ${body?.error?.message ?? body?.message ?? "unknown"}`);
}

async function healthy(url) {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const result = await fetch(url, { headers: { accept: "application/json", "cache-control": "no-cache" } });
    if (result.ok) return await result.text();
    await new Promise((resolve) => setTimeout(resolve, 3000));
  }
  throw new Error(`Health verification failed for ${url}`);
}

const deploymentUrl = `https://${deploymentHost}`;
const deploymentHealth = await healthy(`${deploymentUrl}/health`);
const canonicalHealth = await healthy("https://mcpmaster.vercel.app/health");
const receipt = {
  deploymentId,
  deploymentUrl,
  canonicalUrl: "https://mcpmaster.vercel.app",
  sourceBaseSha,
  automationCommitSha: process.env.GITHUB_SHA ?? null,
  fileCount: files.length,
  sourceBytes,
  deploymentHealth,
  canonicalHealth,
};
console.log(JSON.stringify(receipt));
if (process.env.GITHUB_STEP_SUMMARY) {
  await appendFile(process.env.GITHUB_STEP_SUMMARY, `## Recovered production deployment\n\n- Deployment: \`${deploymentId}\`\n- Source base: \`${sourceBaseSha}\`\n- Files: ${files.length}\n- Canonical URL: https://mcpmaster.vercel.app\n`);
}
