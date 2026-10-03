"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const { readFile, mkdtemp, rm, readdir, writeFile } = require("node:fs/promises");
const { join, resolve } = require("node:path"), { tmpdir } = require("node:os");
const { execFileSync } = require("node:child_process");
const root = resolve(__dirname, "..");
let builder, fixture;
test.before(async () => {
  builder = await import("../scripts/build-core-acceptance-output.mjs");
  fixture = JSON.parse(await readFile(join(root, "apps/pandora-mobile/test/fixtures/core_acceptance_profile_v1.json"), "utf8"));
});
async function assembled(t) {
  const temp = await mkdtemp(join(tmpdir(), "pandora-core-acceptance-output-"));
  t.after(() => rm(temp, { recursive: true, force: true }));
  const binding = await builder.validateBuildBinding(fixture.canonicalJson, fixture.configSha256, fixture.canonical.sourceSha);
  const stage = join(temp, "stage");
  const receipt = await builder.assembleCoreAcceptanceOutput({ repositoryRoot: root, destination: stage, binding });
  return { temp, stage, binding, receipt, output: join(stage, ".vercel/output") };
}

test("public build manifest is exact, ordered and rejects unknown, duplicate, missing or retargeted fields", async () => {
  const c = fixture.canonical;
  const invalid = [JSON.stringify({ ...c, extra: "caller" }), JSON.stringify({ ...c, sourceSha: "b".repeat(40) }),
    JSON.stringify({ ...c, ownerApiBaseUrl: "https://mcpmaster.vercel.app/api/operator" }),
    fixture.canonicalJson.replace('"profile":', '"profile":"core_acceptance_v1","profile":'),
    JSON.stringify(Object.fromEntries(Object.entries(c).reverse())), JSON.stringify({ ...c, memoryMode: undefined })];
  for (const value of invalid) await assert.rejects(builder.validateBuildBinding(value, fixture.configSha256, c.sourceSha));
  await assert.rejects(builder.validateBuildBinding(fixture.canonicalJson, "b".repeat(64), c.sourceSha));
});

test("actual traced output contains only the approved source graph and complete OIDC dependencies", async t => {
  const f = await assembled(t);
  const fn = join(f.output, "functions/api/operations-inference.func");
  const config = JSON.parse(await readFile(join(f.output, "config.json")));
  assert.deepEqual(config.crons, []); assert.equal(config.routes.length, 3);
  assert.deepEqual(await readdir(join(f.output, "functions/api")), ["operations-inference.func"]);
  assert.deepEqual(await readdir(join(f.output, "static")), ["core-acceptance-release.json"]);
  const runtime = JSON.parse(await readFile(join(fn, ".vc-config.json")));
  assert.equal(runtime.handler, builder.ACCEPTANCE_ENTRYPOINT); assert.equal(runtime.supportsResponseStreaming, true);
  assert.equal(runtime.shouldAddHelpers, false);
  assert.equal(runtime.environment.SUPABASE_URL, fixture.canonical.supabaseUrl);
  assert.equal(runtime.environment.SUPABASE_SERVICE_ROLE_KEY, undefined);
  const receipt = JSON.parse(await readFile(join(f.stage, "acceptance-build-receipt.json")));
  assert.ok(receipt.files.some(file => file.path === "supabase/functions/_shared/core-acceptance-profile.mjs"));
  assert.ok(receipt.files.some(file => file.path.startsWith("node_modules/@vercel/oidc/")));
  assert.ok(receipt.files.every(file => !file.path.startsWith("api/") && !/operations-memory|operations-native-worker|\.env/.test(file.path)));
  assert.equal(f.receipt.productionRelease, false); assert.equal(f.receipt.configSha256, fixture.configSha256);
  const cliConfig = JSON.parse(await readFile(join(f.stage, "vercel.json")));
  assert.deepEqual(cliConfig, { version: 2, crons: [], git: { deploymentEnabled: false } });
});

test("the actual copied runtime rejects all alternate routes and invalid tickets with zero network calls", async t => {
  const f = await assembled(t);
  const entry = join(f.output, "functions/api/operations-inference.func", builder.ACCEPTANCE_ENTRYPOINT);
  const script = String.raw`
    const assert=require('node:assert/strict'),{EventEmitter}=require('node:events');
    const handler=require(process.argv[1]), env=JSON.parse(process.argv[2]);
    for(const key of Object.keys(process.env))if(key.startsWith('PANDORA_ACCEPTANCE_')||key==='PANDORA_RUNTIME_PROFILE')delete process.env[key];
    Object.assign(process.env,env); let network=0;globalThis.fetch=async()=>{network++;throw Error('UNEXPECTED_NETWORK');};
    async function invoke(url,markers=true){
      const req=new EventEmitter(); req.method='POST';req.url=url;
      req.headers=markers?{'x-pandora-runtime-profile':env.PANDORA_RUNTIME_PROFILE,'x-pandora-config-sha256':env.PANDORA_ACCEPTANCE_CONFIG_SHA256,'x-pandora-source-sha':env.PANDORA_ACCEPTANCE_SOURCE_SHA}:{};
      req[Symbol.asyncIterator]=async function*(){yield Buffer.from('{}');};
      const res=new EventEmitter();res.headers={};res.setHeader=(k,v)=>res.headers[k]=v;
      res.end=value=>{res.body=JSON.parse(value);res.writableEnded=true;return res;};
      await handler(req,res);return res;
    }
    (async()=>{
      for(const url of ['/api/operations-memory','/api/operations-inference?operation=bedrock-control','/api/operations-inference?operation=infer','/api/operations-inference?operation=bedrock-chat&operation=bedrock-chat']){
        const r=await invoke(url);assert.equal(r.statusCode,404);assert.equal(r.body.error,'CORE_RUNTIME_OPERATION_DENIED');
      }
      let r=await invoke('/api/operations-inference?operation=bedrock-chat');assert.equal(r.statusCode,404);assert.equal(r.body.error,'BEDROCK_CHAT_DENIED');assert.equal(r.headers['x-pandora-config-sha256'],env.PANDORA_ACCEPTANCE_CONFIG_SHA256);
      r=await invoke('/api/operations-inference?operation=bedrock-chat',false);assert.equal(r.statusCode,400);
      delete process.env.PANDORA_RUNTIME_PROFILE;r=await invoke('/api/operations-inference?operation=bedrock-chat');assert.equal(r.statusCode,400);
      assert.equal(network,0);process.stdout.write('runtime checks passed');
    })().catch(e=>{process.stderr.write(e.stack);process.exitCode=1;});`;
  const result = execFileSync(process.execPath, ["--no-experimental-require-module", "-e", script, entry, JSON.stringify(f.binding.environment)], {
    encoding: "utf8", timeout: 30000,
  });
  assert.equal(result, "runtime checks passed");
});

test("release CLI refuses wrong source and a dirty checkout before it can assemble an output", async t => {
  const temporary = await mkdtemp(join(tmpdir(), "pandora-core-acceptance-source-"));
  t.after(() => rm(temporary, { recursive: true, force: true }));
  // A disposable one-file Git fixture tests both states without depending on
  // whether the developer/CI checkout happens to have uncommitted changes.
  const git = args => execFileSync("git", ["-C", temporary, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
  git(["init", "--quiet"]); await writeFile(join(temporary, "fixture.txt"), "original");
  git(["add", "fixture.txt"]);
  git(["-c", "user.name=Unit Test", "-c", "user.email=unit@example.invalid", "commit", "--quiet", "-m", "Synthetic source fixture"]);
  const actual = git(["rev-parse", "HEAD"]);
  builder.verifySourceIdentity(temporary, actual);
  assert.throws(() => builder.verifySourceIdentity(temporary, "b".repeat(40)), /SOURCE_MISMATCH/);
  await writeFile(join(temporary, "fixture.txt"), "changed");
  assert.throws(() => builder.verifySourceIdentity(temporary, actual), /SOURCE_DIRTY/);
  await writeFile(join(temporary, "fixture.txt"), "original");
  await writeFile(join(temporary, "untracked.txt"), "untracked");
  assert.throws(() => builder.verifySourceIdentity(temporary, actual), /SOURCE_DIRTY/);
  await assert.rejects(builder.runCli(["--output", join(temporary, "forbidden")], {
    PANDORA_CORE_QA_REVIEWED_SOURCE_SHA: "b".repeat(40), PANDORA_CORE_QA_TARGET_JSON: fixture.canonicalJson,
    PANDORA_CORE_QA_CONFIG_SHA256: fixture.configSha256,
  }), /SOURCE_MISMATCH/);
  assert.equal((await readdir(temporary)).includes("forbidden"), false);
});

test("existing outputs cannot be silently reused and source source-tree destinations are denied", async t => {
  const f = await assembled(t);
  await assert.rejects(builder.assembleCoreAcceptanceOutput({ repositoryRoot: root, destination: f.stage, binding: f.binding }), /OUTPUT_EXISTS/);
  await assert.rejects(builder.assembleCoreAcceptanceOutput({ repositoryRoot: root, destination: join(root, "never-created-output"), binding: f.binding }), /OUTPUT_INSIDE_SOURCE/);
});
