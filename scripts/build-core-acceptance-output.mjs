import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { lstat, mkdir, readFile, realpath, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { canonicalAcceptanceConfig, resolveCoreRuntimeProfile } from "../supabase/functions/_shared/core-acceptance-profile.mjs";

const require = createRequire(import.meta.url);
const { nodeFileTrace } = require("@vercel/nft");
export const ACCEPTANCE_ENTRYPOINT = "src/providers/core-acceptance-entrypoint.js";
const sourceAllowlist = new Set([
  ACCEPTANCE_ENTRYPOINT, "src/providers/aws-bedrock-chat-http.js", "src/providers/aws-bedrock-runtime.js",
  "src/providers/aws-bedrock-catalog.js", "src/runtime/vercel-workload-identity.js",
  "supabase/functions/_shared/core-acceptance-profile.mjs", "package.json",
]);
const sha = bytes => createHash("sha256").update(bytes).digest("hex");
const fail = code => { throw Error(`CORE_ACCEPTANCE_BUILD_${code}`); };
const contained = (root, path) => path === root || path.startsWith(root + sep);

export async function validateBuildBinding(targetJson, configSha256, sourceSha) {
  if (typeof targetJson !== "string" || targetJson.length > 4096) fail("TARGET_INVALID");
  let fields;
  try { fields = JSON.parse(targetJson); } catch { fail("TARGET_INVALID"); }
  const canonical = canonicalAcceptanceConfig(fields);
  if (JSON.stringify(canonical) !== targetJson || canonical.sourceSha !== sourceSha) fail("TARGET_INVALID");
  const environment = {
    PANDORA_RUNTIME_PROFILE: canonical.profile,
    PANDORA_ACCEPTANCE_SUPABASE_PROJECT_REF: canonical.supabaseProjectRef,
    PANDORA_ACCEPTANCE_ORGANIZATION_ID: canonical.organizationId,
    PANDORA_ACCEPTANCE_SOURCE_SHA: canonical.sourceSha,
    PANDORA_ACCEPTANCE_PUBLISHABLE_KEY_SHA256: canonical.publishableKeySha256,
    PANDORA_ACCEPTANCE_CONFIG_SHA256: configSha256,
    // An inherited SUPABASE_URL can never quietly choose the parent project.
    SUPABASE_URL: canonical.supabaseUrl,
  };
  const profile = await resolveCoreRuntimeProfile(environment, { role: "build" });
  return { canonical, environment, configSha256: profile.configSha256 };
}

export function verifySourceIdentity(repositoryRoot, sourceSha) {
  if (typeof sourceSha !== "string" || sourceSha.length !== 40 || !/^[0-9a-f]{40}$/.test(sourceSha)) fail("SOURCE_INVALID");
  const git = args => execFileSync("git", ["-C", repositoryRoot, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
  if (git(["rev-parse", "HEAD"]) !== sourceSha) fail("SOURCE_MISMATCH");
  if (git(["status", "--porcelain", "--untracked-files=all"])) fail("SOURCE_DIRTY");
}

export async function traceAcceptanceFiles(repositoryRoot) {
  const root = await realpath(repositoryRoot);
  const dependencies = await realpath(join(root, "node_modules"));
  // Local checkouts may share a read-only dependency installation. The trace
  // can see its real path; only files in that exact dependency root are copied.
  let base = root;
  while (!contained(base, dependencies)) {
    const parent = dirname(base);
    if (parent === base) fail("DEPENDENCY_ROOT_INVALID");
    base = parent;
  }
  const trace = await nodeFileTrace([join(root, ACCEPTANCE_ENTRYPOINT)], { base, processCwd: root });
  if (trace.warnings.size) fail("TRACE_INCOMPLETE");
  const files = new Map();
  for (const item of trace.fileList) {
    const candidate = resolve(base, item);
    const info = await lstat(candidate);
    if (info.isSymbolicLink() && candidate === join(root, "node_modules")) continue;
    if (!info.isFile()) fail("TRACE_FILE_INVALID");
    const actual = await realpath(candidate);
    let name;
    if (contained(dependencies, actual)) name = `node_modules/${relative(dependencies, actual).split(sep).join("/")}`;
    else if (contained(root, actual)) {
      name = relative(root, actual).split(sep).join("/");
      if (!sourceAllowlist.has(name)) fail("SOURCE_GRAPH_DENIED");
    } else fail("TRACE_ESCAPE");
    if (!name || name.includes("..") || isAbsolute(name)) fail("TRACE_PATH_INVALID");
    files.set(name, await readFile(actual));
  }
  for (const name of sourceAllowlist) if (!files.has(name)) fail("SOURCE_GRAPH_INCOMPLETE");
  if (![...files.keys()].some(name => name.startsWith("node_modules/@vercel/oidc/"))) fail("OIDC_GRAPH_INCOMPLETE");
  return files;
}

// Build Output API v3 is constructed directly, so no inherited vercel.json,
// framework build, rewrite, cron or unrelated API can enter this artifact.
export async function assembleCoreAcceptanceOutput({ repositoryRoot, destination, binding }) {
  const files = await traceAcceptanceFiles(repositoryRoot);
  const stage = resolve(destination);
  if (contained(await realpath(repositoryRoot), stage)) fail("OUTPUT_INSIDE_SOURCE");
  try { await lstat(stage); fail("OUTPUT_EXISTS"); } catch (error) { if (error.code !== "ENOENT") throw error; }
  const output = join(stage, ".vercel", "output");
  const fn = join(output, "functions", "api", "operations-inference.func");
  for (const [name, bytes] of files) {
    await mkdir(dirname(join(fn, name)), { recursive: true });
    await writeFile(join(fn, name), bytes);
  }
  const functionConfig = {
    runtime: "nodejs24.x", handler: ACCEPTANCE_ENTRYPOINT, launcherType: "Nodejs",
    shouldAddHelpers: false, supportsResponseStreaming: true, maxDuration: 180,
    environment: binding.environment,
  };
  await writeFile(join(fn, ".vc-config.json"), JSON.stringify(functionConfig));
  const outputConfig = { version: 3, crons: [], routes: [
    { src: "^/api/operations-inference$", dest: "/api/operations-inference" },
    { src: "^/core-acceptance-release.json$", dest: "/core-acceptance-release.json" },
    { src: "/.*", status: 404 },
  ] };
  await writeFile(join(output, "config.json"), JSON.stringify(outputConfig));
  // CLI project configuration is intentionally distinct from the repository's
  // production config, and contains no environment values or build command.
  await writeFile(join(stage, "vercel.json"), JSON.stringify({ version: 2, crons: [], git: { deploymentEnabled: false } }));
  const fileReceipts = [...files].map(([path, bytes]) => ({ path, sha256: sha(bytes) })).sort((a, b) => a.path.localeCompare(b.path));
  const runtimeSha256 = sha(JSON.stringify({ files: fileReceipts, functionConfig, outputConfig }));
  const receipt = {
    schemaVersion: "pandora.core-acceptance-output.v1", profile: binding.canonical.profile,
    sourceSha: binding.canonical.sourceSha, configSha256: binding.configSha256,
    supabaseProjectRef: binding.canonical.supabaseProjectRef, runtimeSha256,
    route: "/api/operations-inference?operation=bedrock-chat", memoryMode: "unavailable",
    crons: [], functions: ["api/operations-inference"], productionRelease: false,
  };
  await mkdir(join(output, "static"), { recursive: true });
  await writeFile(join(output, "static", "core-acceptance-release.json"), JSON.stringify(receipt));
  // Private CI audit manifest includes only public config and content digests.
  await writeFile(join(stage, "acceptance-build-receipt.json"), JSON.stringify({ ...receipt, files: fileReceipts }));
  return receipt;
}

export async function runCli(argv = process.argv.slice(2), env = process.env) {
  if (argv.length !== 2 || argv[0] !== "--output") fail("ARGUMENTS_INVALID");
  const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
  const sourceSha = env.PANDORA_CORE_QA_REVIEWED_SOURCE_SHA;
  verifySourceIdentity(repositoryRoot, sourceSha);
  const binding = await validateBuildBinding(env.PANDORA_CORE_QA_TARGET_JSON, env.PANDORA_CORE_QA_CONFIG_SHA256, sourceSha);
  return await assembleCoreAcceptanceOutput({ repositoryRoot, destination: argv[1], binding });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli().then(receipt => process.stdout.write(JSON.stringify(receipt) + "\n")).catch(error => {
    const code = /^(?:CORE_ACCEPTANCE_BUILD|CORE_RUNTIME)_[A-Z_]+$/.test(error.message || "") ? error.message : "CORE_ACCEPTANCE_BUILD_FAILED";
    process.stderr.write(code + "\n"); process.exitCode = 1;
  });
}
