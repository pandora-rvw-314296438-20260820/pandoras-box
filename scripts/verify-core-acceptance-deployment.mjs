import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const TEAM = "team_3yw1CN59ce4pj5SwyQGCAqN3";
const PROJECT = "prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk";
const ALIASES = ["mcpmaster.vercel.app", "mcpmaster-mbanatao.vercel.app"];
const sha = value => createHash("sha256").update(value).digest("hex");
const fail = code => { throw Error(`CORE_ACCEPTANCE_DEPLOY_${code}`); };
const requireThat = (condition, code) => { if (!condition) fail(code); };
const exact = (value, pattern) => typeof value === "string" && pattern.exec(value)?.[0].length === value.length;
function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])]));
  return value;
}
export function validateAcceptanceOrigin(value) {
  requireThat(exact(value, /^https:\/\/mcpmaster-[a-z0-9]{9}-mbanatao\.vercel\.app$/), "ORIGIN_INVALID");
  return value;
}
async function boundedResponse(url, options, fetchImpl, limit) {
  const controller = new AbortController();
  const deadline = setTimeout(() => controller.abort(), 20_000);
  let reader;
  try {
    const response = await fetchImpl(url, { ...options, redirect: "error", signal: controller.signal });
    requireThat(!response.redirected && response.url === url && response.body, "RESPONSE_INVALID");
    reader = response.body.getReader();
    const chunks = []; let size = 0;
    for (;;) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.length; requireThat(size <= limit, "RESPONSE_TOO_LARGE"); chunks.push(value);
    }
    return { response, bytes: Buffer.concat(chunks) };
  } catch (error) {
    if (error.message?.startsWith("CORE_ACCEPTANCE_DEPLOY_")) throw error;
    fail("REQUEST_FAILED");
  } finally {
    clearTimeout(deadline); controller.abort(); if (reader) void reader.cancel().catch(() => {});
  }
}
async function provider(path, token, fetchImpl) {
  requireThat(typeof token === "string" && token.length > 0, "PROVIDER_AUTH_REQUIRED");
  const url = `https://api.vercel.com${path}${path.includes("?") ? "&" : "?"}teamId=${TEAM}`;
  const { response, bytes } = await boundedResponse(url, { headers: { authorization: `Bearer ${token}`, accept: "application/json" } }, fetchImpl, 1024 * 1024);
  requireThat(response.status === 200, "PROVIDER_READBACK_FAILED");
  try { return JSON.parse(bytes); } catch { fail("PROVIDER_RESPONSE_INVALID"); }
}
export async function captureProductionState({ token, fetchImpl = globalThis.fetch }) {
  const project = await provider(`/v9/projects/${PROJECT}`, token, fetchImpl);
  requireThat(project.id === PROJECT && project.accountId === TEAM && project.name === "mcpmaster", "OWNER_MISMATCH");
  // An omitted/unreadable scheduler object is an evidence gap, not "no cron".
  requireThat(project.crons && typeof project.crons === "object" && Array.isArray(project.crons.definitions), "CRON_READBACK_REQUIRED");
  const aliases = [];
  for (const alias of ALIASES) {
    const result = await provider(`/v4/aliases/${alias}?projectId=${PROJECT}`, token, fetchImpl);
    requireThat(result.alias === alias && result.projectId === PROJECT && exact(result.deploymentId, /^dpl_[A-Za-z0-9]+$/), "ALIAS_READBACK_INVALID");
    aliases.push({ alias, deploymentId: result.deploymentId });
  }
  return { schemaVersion: "pandora.core-acceptance-production-state.v1", projectId: PROJECT, teamId: TEAM,
    aliases, cronSha256: sha(JSON.stringify(stable(project.crons))), cronCount: project.crons.definitions.length,
    productionTargetId: project.targets?.production?.id ?? null };
}
export function assertUnchangedProduction(before, after) {
  requireThat(before?.schemaVersion === "pandora.core-acceptance-production-state.v1" && JSON.stringify(before) === JSON.stringify(after), "PRODUCTION_CHANGED");
}
export async function verifyAcceptanceDeployment({ origin, stage, sourceSha, configSha256, token, before, fetchImpl = globalThis.fetch }) {
  validateAcceptanceOrigin(origin);
  requireThat(exact(sourceSha, /^[0-9a-f]{40}$/) && exact(configSha256, /^[0-9a-f]{64}$/), "INPUT_BINDING_INVALID");
  const receiptBytes = await readFile(resolve(stage, ".vercel/output/static/core-acceptance-release.json"));
  let local; try { local = JSON.parse(receiptBytes); } catch { fail("LOCAL_RECEIPT_INVALID"); }
  requireThat(local.schemaVersion === "pandora.core-acceptance-output.v1" && local.profile === "core_acceptance_v1" &&
    local.sourceSha === sourceSha && local.configSha256 === configSha256 && local.productionRelease === false &&
    exact(local.runtimeSha256, /^[0-9a-f]{64}$/), "LOCAL_RECEIPT_INVALID");
  const deployment = await provider(`/v13/deployments/${new URL(origin).hostname}`, token, fetchImpl);
  requireThat(deployment.name === "mcpmaster" && deployment.projectId === PROJECT && deployment.ownerId === TEAM &&
    deployment.url === new URL(origin).hostname && deployment.readyState === "READY" && deployment.target === "production" &&
    exact(deployment.id, /^dpl_[A-Za-z0-9]+$/), "DEPLOYMENT_IDENTITY_MISMATCH");
  requireThat(deployment.meta?.pandoraSourceSha === sourceSha && deployment.meta?.pandoraConfigSha256 === configSha256 &&
    deployment.meta?.pandoraRuntimeProfile === "core_acceptance_v1", "DEPLOYMENT_BINDING_MISMATCH");
  requireThat(Array.isArray(deployment.alias) && deployment.alias.length === 0 && deployment.aliasAssigned !== true, "UNEXPECTED_ALIAS");
  const served = await boundedResponse(`${origin}/core-acceptance-release.json`, {
    headers: { accept: "application/json", "cache-control": "no-cache" },
  }, fetchImpl, 4096);
  requireThat(served.response.status === 200 && (served.response.headers.get("content-type") || "").startsWith("application/json") &&
    served.bytes.equals(receiptBytes), "SERVED_RECEIPT_MISMATCH");
  // Empty invalid ticket proves the actual function loaded its server profile
  // and echoed the binding. It cannot claim a ticket, resolve OIDC or infer.
  const markers = { "x-pandora-runtime-profile": "core_acceptance_v1", "x-pandora-config-sha256": configSha256,
    "x-pandora-source-sha": sourceSha };
  const denial = await boundedResponse(`${origin}/api/operations-inference?operation=bedrock-chat`, {
    method: "POST", headers: { ...markers, "content-type": "application/json" }, body: "{}",
  }, fetchImpl, 4096);
  let denied; try { denied = JSON.parse(denial.bytes); } catch { fail("RUNTIME_BINDING_UNVERIFIED"); }
  requireThat(denial.response.status === 404 && denied.error === "BEDROCK_CHAT_DENIED" &&
    Object.entries(markers).every(([name, value]) => denial.response.headers.get(name) === value), "RUNTIME_BINDING_UNVERIFIED");
  const after = await captureProductionState({ token, fetchImpl });
  assertUnchangedProduction(before, after);
  return { schemaVersion: "pandora.core-acceptance-deployment.v1", observedAt: new Date().toISOString(),
    sourceSha, configSha256, runtimeSha256: local.runtimeSha256, origin, deploymentId: deployment.id,
    projectId: PROJECT, teamId: TEAM, productionAliasesAndCronUnchanged: true,
    servedReceiptSha256: sha(receiptBytes), runtimeBindingVerified: true, providerInferenceVerified: false,
    authorityIsolation: "shared_production_workload_identity", productionRelease: false };
}

export async function runCli(argv = process.argv.slice(2), env = process.env) {
  if (argv[0] === "snapshot" && argv.length === 2) {
    const state = await captureProductionState({ token: env.VERCEL_TOKEN });
    await writeFile(argv[1], JSON.stringify(state)); return { captured: true };
  }
  if (argv[0] === "verify" && argv.length === 4) {
    const before = JSON.parse(await readFile(argv[3], "utf8"));
    return await verifyAcceptanceDeployment({ origin: argv[1], stage: argv[2], before,
      sourceSha: env.PANDORA_CORE_QA_REVIEWED_SOURCE_SHA, configSha256: env.PANDORA_CORE_QA_CONFIG_SHA256,
      token: env.VERCEL_TOKEN });
  }
  fail("ARGUMENTS_INVALID");
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli().then(receipt => process.stdout.write(JSON.stringify(receipt) + "\n")).catch(error => {
    const code = /^CORE_ACCEPTANCE_DEPLOY_[A-Z_]+$/.test(error.message || "") ? error.message : "CORE_ACCEPTANCE_DEPLOY_FAILED";
    process.stderr.write(code + "\n"); process.exitCode = 1;
  });
}
