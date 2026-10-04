"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const { readFile, mkdtemp, mkdir, writeFile, rm } = require("node:fs/promises");
const { join, resolve } = require("node:path"), { tmpdir } = require("node:os");
const { spawnSync } = require("node:child_process");
let verify, workflow;
const root = resolve(__dirname, ".."), source = "a".repeat(40), digest = "b".repeat(64);
const team = "team_3yw1CN59ce4pj5SwyQGCAqN3", project = "prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk";
const origin = "https://mcpmaster-123abc456-mbanatao.vercel.app";
const receipt = { schemaVersion: "pandora.core-acceptance-output.v1", profile: "core_acceptance_v1",
  sourceSha: source, configSha256: digest, runtimeSha256: "c".repeat(64), productionRelease: false };
function response(url, body, status = 200, headers = {}) {
  const res = new Response(typeof body === "string" ? body : JSON.stringify(body), { status, headers: { "content-type": "application/json", ...headers } });
  Object.defineProperty(res, "url", { value: url }); return res;
}
test.before(async () => {
  verify = await import("../scripts/verify-core-acceptance-deployment.mjs");
  const source = await readFile(join(root, ".github/workflows/task-146-prebuilt-vercel-deploy.yml"), "utf8");
  const jobSections = source.split(/^  (?=[a-z-]+:\n)/m);
  workflow = { jobs: Object.fromEntries(["deploy", "core-acceptance"].map(name => {
    const section = jobSections.find(value => value.startsWith(`${name}:\n`));
    assert.ok(section, `missing job ${name}`);
    const steps = section.split(/^      - name: /m).slice(1).map(block => {
      const body = block.split("        run: |\n")[1];
      return { name: block.split("\n")[0], ...(body ? { run: body.split("\n").filter(line => line.startsWith("          ")).map(line => line.slice(10)).join("\n") } : {}) };
    });
    return [name, { if: section.match(/^    if: (.*)$/m)?.[1], environment: section.match(/^    environment: (.*)$/m)?.[1], steps }];
  })) };
});
async function fixture(t) {
  const stage = await mkdtemp(join(tmpdir(), "pandora-core-acceptance-deployment-"));
  t.after(() => rm(stage, { recursive: true, force: true }));
  await mkdir(join(stage, ".vercel/output/static"), { recursive: true });
  await writeFile(join(stage, ".vercel/output/static/core-acceptance-release.json"), JSON.stringify(receipt));
  const state = { mode: "ok", calls: [] };
  const fetchImpl = async (url, init) => {
    state.calls.push({ url, method: init.method ?? "GET" });
    if (url.startsWith("https://api.vercel.com/")) {
      assert.equal(init.headers.authorization, "Bearer synthetic_provider_token");
      if (url.includes("/v9/projects/")) return response(url, {
        id: project, accountId: team, name: "mcpmaster", env: [{ value: "NEVER_RETURN_PRIVATE_PROVIDER_FIELD" }],
        crons: state.mode === "missing-cron" ? undefined : { definitions: [{ path: "/api/worker", schedule: state.mode === "cron-drift" ? "1 * * * *" : "0 0 * * *" }], deploymentId: "dpl_existing" },
        targets: { production: { id: "dpl_existing" } },
      });
      if (url.includes("/v4/aliases/")) return response(url, { alias: new URL(url).pathname.split("/").at(-1), projectId: project,
        deploymentId: state.mode === "alias-drift" ? "dpl_changed" : "dpl_existing", creator: { email: "never-return@example.invalid" } });
      if (url.includes("/v13/deployments/")) return response(url, {
        id: "dpl_candidate", name: "mcpmaster", ownerId: team, projectId: state.mode === "wrong-project" ? "prj_foreign" : project,
        url: new URL(origin).hostname, readyState: "READY", target: "production", aliasAssigned: false,
        alias: state.mode === "unexpected-alias" ? ["mcpmaster.vercel.app"] : [],
        meta: { pandoraSourceSha: state.mode === "wrong-source" ? "f".repeat(40) : source, pandoraConfigSha256: digest, pandoraRuntimeProfile: "core_acceptance_v1" },
      });
      throw Error("unexpected provider URL");
    }
    assert.equal(init.headers.authorization, undefined);
    if (url.endsWith("/core-acceptance-release.json")) return response(url, state.mode === "wrong-bytes" ? { ...receipt, sourceSha: "f".repeat(40) } : receipt);
    assert.equal(url, origin + "/api/operations-inference?operation=bedrock-chat");
    assert.equal(init.body, "{}"); assert.equal(init.method, "POST");
    return response(url, { error: "BEDROCK_CHAT_DENIED" }, 404, {
      "x-pandora-runtime-profile": "core_acceptance_v1", "x-pandora-source-sha": source,
      "x-pandora-config-sha256": state.mode === "wrong-runtime" ? "f".repeat(64) : digest,
    });
  };
  const token = "synthetic_provider_token";
  const before = await verify.captureProductionState({ token, fetchImpl });
  return { stage, state, before, run: () => verify.verifyAcceptanceDeployment({ origin, stage, sourceSha: source, configSha256: digest, before, token, fetchImpl }) };
}

test("deployment verification binds provider identity, exact served receipt and actual function metadata without inference", async t => {
  const f = await fixture(t); const result = await f.run();
  assert.equal(result.deploymentId, "dpl_candidate"); assert.equal(result.runtimeBindingVerified, true);
  assert.equal(result.providerInferenceVerified, false); assert.equal(result.productionRelease, false);
  assert.equal(result.productionAliasesAndCronUnchanged, true);
  assert.equal(result.authorityIsolation, "shared_production_workload_identity");
  assert.equal(f.state.calls.filter(call => call.method === "POST").length, 1);
  assert.ok(f.state.calls.every(call => !/supabase|amazonaws|operations-memory/.test(call.url)));
  assert.doesNotMatch(JSON.stringify({ result, before: f.before }), /NEVER_RETURN|synthetic_provider_token|never-return/);
});

test("foreign deployment, alias assignment, source/config drift and served-byte mismatches block acceptance", async t => {
  const f = await fixture(t);
  for (const mode of ["wrong-project", "unexpected-alias", "wrong-source", "wrong-bytes", "wrong-runtime", "alias-drift", "cron-drift", "missing-cron"]) {
    f.state.mode = mode; await assert.rejects(f.run(), /CORE_ACCEPTANCE_DEPLOY_/);
  }
});

test("target validation never accepts production aliases, caller URLs or alternate teams", () => {
  for (const value of ["https://mcpmaster.vercel.app", "https://mcpmaster-mbanatao.vercel.app", `${origin}/`, `${origin}?a=b`,
    "https://mcpmaster-123abc456-foreign.vercel.app", "https://mcpmaster-git-branch-mbanatao.vercel.app", "http://mcpmaster-123abc456-mbanatao.vercel.app", origin + "\n", origin + "\r\n"]) {
    assert.throws(() => verify.validateAcceptanceOrigin(value), /ORIGIN_INVALID/);
  }
  assert.equal(verify.validateAcceptanceOrigin(origin), origin);
});

test("newline-suffixed source and config identities are rejected before any provider read", async t => {
  const f = await fixture(t);
  for (const ending of ["\n", "\r\n"]) {
    for (const changed of [{ sourceSha: source + ending, configSha256: digest }, { sourceSha: source, configSha256: digest + ending }]) {
      await assert.rejects(verify.verifyAcceptanceDeployment({ origin, stage: f.stage, before: f.before, ...changed,
        token: "unused", fetchImpl: () => { throw Error("UNEXPECTED_PROVIDER"); } }), /INPUT_BINDING_INVALID/);
    }
  }
});

test("production job stays separate; acceptance binds canonical reviewed source and has no promote/alias path", async t => {
  const job = workflow.jobs["core-acceptance"], production = workflow.jobs.deploy;
  assert.match(production.if, /!= 'core_acceptance_v1'/); assert.match(job.if, /== 'core_acceptance_v1'/);
  assert.equal(job.environment, "pandora-core-mobile-qa");
  const gate = job.steps.find(step => step.name === "Validate canonical reviewed workflow and source").run;
  const env = { ...process.env, GITHUB_EVENT_NAME: "workflow_dispatch", GITHUB_REPOSITORY: "pandora-rvw-314296438-20260820/pandoras-box",
    PANDORA_CORE_QA_RUNTIME_PROFILE: "core_acceptance_v1", SOURCE_SHA: source, GITHUB_SHA: source, PANDORA_CORE_QA_REVIEWED_SOURCE_SHA: source };
  assert.equal(spawnSync("bash", ["-c", gate], { env }).status, 0);
  for (const changed of [{ GITHUB_REPOSITORY: "foreign/repo" }, { GITHUB_SHA: "f".repeat(40) }, { PANDORA_CORE_QA_REVIEWED_SOURCE_SHA: "f".repeat(40) }, { GITHUB_EVENT_NAME: "pull_request" }]) {
    assert.notEqual(spawnSync("bash", ["-c", gate], { env: { ...env, ...changed } }).status, 0);
  }
  const runs = job.steps.filter(step => step.run).map(step => step.run).join("\n");
  assert.doesNotMatch(runs, /vercel@59\.10\.0 (?:promote|alias)|vercel\.com\/v\d+\/.*(?:POST|PATCH)| pull | build --prod/);
  assert.match(runs, /--prebuilt --prod --skip-domain/);
  assert.match(runs, /core-production-before\.json/);
});

test("real acceptance stage shell has one permitted deploy command and propagates build/readback failure", async t => {
  const temporary = await mkdtemp(join(tmpdir(), "pandora-core-acceptance-shell-"));
  t.after(() => rm(temporary, { recursive: true, force: true }));
  const bin = join(temporary, "bin"); await mkdir(bin);
  const commands = join(temporary, "commands");
  await writeFile(join(bin, "node"), '#!/bin/bash\nset -e\nprintf "node %s\\n" "$*" >> "$COMMAND_LOG"\nif [[ "$1" = scripts/build-core-acceptance-output.mjs ]]; then\n  [[ "${FAIL_BUILD:-0}" != 1 ]] || exit 17\n  mkdir -p "$RUNNER_TEMP/core-acceptance-deploy/.vercel"\nelif [[ "$1" = scripts/verify-pandora-web-release.mjs ]]; then\n  echo "https://mcpmaster-123abc456-mbanatao.vercel.app"\nelif [[ "$1" = scripts/verify-core-acceptance-deployment.mjs && "$2" = verify ]]; then\n  [[ "${FAIL_VERIFY:-0}" != 1 ]] || exit 18\nfi\n', { mode: 0o700 });
  await writeFile(join(bin, "npx"), '#!/bin/bash\nset -e\nprintf "npx %s\\n" "$*" >> "$COMMAND_LOG"\n[[ "$*" = *"--skip-domain"* && "$*" != *"promote"* && "$*" != *"alias"* ]] || exit 90\necho "https://mcpmaster-123abc456-mbanatao.vercel.app"\n', { mode: 0o700 });
  const job = workflow.jobs["core-acceptance"];
  const names = ["Build the restricted source and config bound output", "Capture current production aliases and scheduler", "Stage restricted acceptance output without domain assignment", "Verify immutable binding and unchanged production state"];
  const script = names.map(name => job.steps.find(step => step.name === name).run).join("\n");
  const env = { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: temporary, COMMAND_LOG: commands,
    SOURCE_SHA: source, PANDORA_CORE_QA_CONFIG_SHA256: digest, VERCEL_ORG_ID: team, VERCEL_PROJECT_ID: project,
    VERCEL_TOKEN: "synthetic_workflow_token", DEPLOYMENT_URL: origin, GITHUB_OUTPUT: join(temporary, "out") };
  let result = spawnSync("bash", ["-c", script], { env: { ...env, FAIL_BUILD: "1" }, encoding: "utf8" });
  assert.equal(result.status, 17); assert.doesNotMatch(await readFile(commands, "utf8"), /^npx/m);
  await writeFile(commands, "");
  result = spawnSync("bash", ["-c", script], { env, encoding: "utf8" }); assert.equal(result.status, 0, result.stderr);
  assert.equal((await readFile(commands, "utf8")).split("\n").filter(line => line.startsWith("npx")).length, 1);
  result = spawnSync("bash", ["-c", script], { env: { ...env, FAIL_VERIFY: "1" }, encoding: "utf8" }); assert.equal(result.status, 18);
});
