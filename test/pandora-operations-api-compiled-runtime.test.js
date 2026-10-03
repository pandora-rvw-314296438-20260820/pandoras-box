'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const {execFileSync} = require('node:child_process');

// Exercise the real API after the root CommonJS TypeScript transform used by
// Vercel. Directly importing the .mjs service would miss this release boundary.
const smoke = String.raw`
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const {PassThrough} = require('node:stream');
const {EventEmitter} = require('node:events');
const ts = require('typescript');
const root = process.cwd();
const sourcePath = path.join(root, 'api/operations-inference.ts');
const parsed = ts.readConfigFile(path.join(root, 'tsconfig.json'), ts.sys.readFile);
assert.equal(parsed.error, undefined);
const options = ts.convertCompilerOptionsFromJson(parsed.config.compilerOptions, root);
assert.equal(options.errors.length, 0);
const compiled = ts.transpileModule(fs.readFileSync(sourcePath, 'utf8'), {
  fileName: sourcePath, compilerOptions: options.options,
}).outputText;
const entry = new Module(path.join(root, 'api/operations-inference.js'), module);
entry.filename = path.join(root, 'api/operations-inference.js');
entry.paths = Module._nodeModulePaths(path.dirname(entry.filename));
entry._compile(compiled, entry.filename);
const handle = entry.exports.default;
const box = 'https://jcyqixttuebxqqfkjonq.supabase.co';
const org = '2270b266-59da-4c39-bfd9-9f8d08352af0';
const project = 'ee282126-3f61-4058-8c92-2fedbfcecf1f';
const user = '00000000-0000-4000-8000-000000000001';
const jwt = 'fixture-owner-auth-not-a-real-credential'.repeat(2);
const service = 'fixture-server-secret-never-log-'.repeat(3);
const diagnostics = [];
console.error = (...parts) => diagnostics.push(parts);
let fetches = [];
let mode = 'success';
globalThis.fetch = async (url, init) => {
  fetches.push({url, body:init.body});
  if (url === box + '/auth/v1/user') {
    assert.equal(init.headers.authorization, 'Bearer ' + jwt);
    return mode === 'auth_denied'
      ? Response.json({error:'fixture'}, {status:401})
      : Response.json({id:user, is_anonymous:false});
  }
  assert.equal(url, box + '/rest/v1/rpc/pandora_ops_event_feed_v1');
  const args = JSON.parse(init.body);
  assert.deepEqual(args, {p_organization_id:org, p_project_id:project, p_actor_id:user, p_after:'0', p_limit:200});
  if (mode === 'scope_denied') return Response.json({code:'42501', message:'OPS_EVENT_OWNER_DENIED'}, {status:403});
  return Response.json({schemaVersion:'pandora-operations-events-v1', organizationId:org,
    projectId:project, observedAt:'2026-10-03T12:00:00Z', events:[], nextCursor:'0',
    highWatermark:'0', hasMore:false, authority:'immutable_operations_events', syntheticProgress:false});
};
for (const key of Object.keys(process.env)) {
  if (/^(MCPMASTER_OPERATOR_|META_REMOTE_MCP_)/.test(key)) delete process.env[key];
}
process.env.SUPABASE_URL = box;
process.env.SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_' + 'fixture_not_real'.repeat(3);
Object.assign(process.env, {SUPABASE_SERVICE_ROLE_KEY: service});
process.env.VERCEL = '0';
const body = {organizationId:org, projectId:project, after:'0', limit:200};
async function request(method, payload=body, authenticated=false) {
  fetches = [];
  const req = new PassThrough();
  req.url = '/api/operations-inference?operation=events';
  req.method = method;
  req.headers = {'content-type':'application/json', origin:'https://mcpmaster.vercel.app'};
  if (authenticated) req.headers.authorization = 'Bearer ' + jwt;
  if (method === 'POST') req.end(JSON.stringify(payload));
  const res = new EventEmitter();
  res.headersSent = false;
  res.writableEnded = false;
  res.headers = {};
  res.setHeader = (key, value) => {res.headers[key.toLowerCase()] = value; return res;};
  res.status = code => {res.statusCode = code; return res;};
  res.json = value => {res.body = value; res.writableEnded = true;};
  res.end = value => {res.body = JSON.parse(String(value)); res.writableEnded = true;};
  await handle(req, res);
  assert.equal(res.writableEnded, true);
  assert.equal(req.listenerCount('aborted'), 0);
  assert.equal(res.listenerCount('close'), 0);
  return res;
}
(async () => {
  let r = await request('GET');
  assert.equal(r.statusCode, 405); assert.equal(fetches.length, 0);
  r = await request('POST');
  assert.equal(r.statusCode, 401); assert.equal(r.body.error, 'INFERENCE_AUTH_REQUIRED');
  assert.equal(fetches.length, 0);
  r = await request('POST', body, true);
  assert.equal(r.statusCode, 200); assert.equal(fetches.length, 2);
  assert.equal(r.body.authority, 'immutable_operations_events');
  assert.equal(r.body.syntheticProgress, false);
  mode = 'auth_denied';
  r = await request('POST', body, true);
  assert.equal(r.statusCode, 401); assert.equal(fetches.length, 1);
  mode = 'scope_denied';
  r = await request('POST', body, true);
  assert.equal(r.statusCode, 403); assert.equal(r.body.error, 'OPS_EVENT_OWNER_DENIED');
  mode = 'success';
  r = await request('POST', {...body, userId:user}, true);
  assert.equal(r.statusCode, 400); assert.equal(fetches.length, 1);
  assert.equal(diagnostics.length, 0);
  delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  r = await request('POST', body, true);
  assert.equal(r.statusCode, 503); assert.equal(fetches.length, 0);
  assert.deepEqual(diagnostics.pop(), ['pandora_operations_runtime_failure',
    {stage:'runtime_create', code:'INFERENCE_SERVER_CONFIGURATION_DENIED'}]);
  Object.assign(process.env, {SUPABASE_SERVICE_ROLE_KEY: service});
  process.env.MCPMASTER_OPERATOR_SUPABASE_URL = 'https://fixture-private-user:fixture-private-password@example.invalid';
  r = await request('GET');
  assert.equal(r.statusCode, 503); assert.equal(fetches.length, 0);
  assert.deepEqual(diagnostics, [['pandora_operations_runtime_failure',
    {stage:'public_config', code:'UNCLASSIFIED_RUNTIME_FAILURE'}]]);
  const output = JSON.stringify({checks:8, diagnostics, response:r.body});
  for (const forbidden of [jwt, service, 'fixture-private-user', 'fixture-private-password', 'stack', 'message']) {
    assert.equal(output.includes(forbidden), false);
  }
  process.stdout.write(JSON.stringify({checks:8, passed:true}));
})().catch(error => { process.stderr.write(error.stack); process.exitCode = 1; });
`;

for (const restricted of [false, true]) {
  test(`compiled Operations API preserves ESM and authorization with require(ESM) ${restricted ? 'disabled' : 'default'}`, () => {
    const result = execFileSync(process.execPath,
      [...(restricted ? ['--no-experimental-require-module'] : []), '-e', smoke],
      {cwd:path.join(__dirname, '..'), encoding:'utf8', timeout:30000});
    assert.deepEqual(JSON.parse(result), {checks:8, passed:true});
  });
}
