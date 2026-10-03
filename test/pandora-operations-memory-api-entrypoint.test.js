'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const {execFileSync} = require('node:child_process');

// Test the actual API after the CommonJS transform, not only its ESM helper.
// Requests and every provider transport are in-memory; no server is opened.
const smoke = String.raw`
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const {IncomingMessage, ServerResponse} = require('node:http');
const {PassThrough} = require('node:stream');
const ts = require('typescript');
const root = process.cwd();
const box = 'https://jcyqixttuebxqqfkjonq.supabase.co';
const memoryRef = 'ivmvufhcsezyhczzondn';
const org = '2270b266-59da-4c39-bfd9-9f8d08352af0';
const project = 'ee282126-3f61-4058-8c92-2fedbfcecf1f';
const memoryProject = '7c686cbd-d968-49d5-86cc-918f5e777bd2';
const user = '00000000-0000-4000-8000-000000000001';
const jwt = ['fixtureheader'.repeat(3), 'fixturepayload'.repeat(4), 'fixturesignature'.repeat(3)].join('.');
const workload = ['workloadheader'.repeat(3), 'workloadpayload'.repeat(4), 'workloadsignature'.repeat(3)].join('.');
for (const key of Object.keys(process.env)) {
  if (/^(MCPMASTER_OPERATOR_|META_REMOTE_MCP_)/.test(key)) delete process.env[key];
}
process.env.SUPABASE_URL = box;
process.env.SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_' + 'not_real_fixture'.repeat(3);
process.env.VERCEL = '1';
require(path.join(root, 'src/runtime/vercel-workload-identity.js')).resolveVercelWorkloadToken = async () => workload;
let calls = [], mode = 'success', authorizationCalls = 0;
globalThis.fetch = async (url, init) => {
  const address = String(url);
  if (address === box + '/auth/v1/user') {
    calls.push('user');
    assert.equal(init.headers.authorization, 'Bearer ' + jwt);
    return Response.json({id:user, is_anonymous:false});
  }
  if (address === box + '/rest/v1/rpc/pandora_core_authorize_memory_v1') {
    calls.push('core'); authorizationCalls++;
    assert.equal(init.headers.authorization, 'Bearer ' + jwt);
    assert.equal(init.body, '{}');
    if (mode === 'scope_denied' || (mode === 'revoked' && authorizationCalls === 2)) {
      return Response.json({code:'42501', message:'private provider diagnostic'}, {status:403});
    }
    return Response.json(true);
  }
  assert.equal(address, 'https://' + memoryRef + '.supabase.co/functions/v1/pandora-memory-bridge');
  calls.push('memory');
  assert.equal(init.headers['x-pandora-vercel-oidc'], workload);
  assert.equal(init.headers.authorization, undefined);
  const payload = JSON.parse(init.body);
  assert.equal(payload.action, 'operations');
  assert.equal(payload.operation, 'context');
  assert.equal(payload.projectId, memoryProject);
  assert.equal(payload.namespace, 'real_life');
  const context = {
    schemaVersion:'m5.task-aware-retrieval.v1', status:'available', namespace:'real_life',
    project:{id:memoryProject}, contextSha256:'a'.repeat(64), asOf:'2026-10-03T12:00:00Z',
    authorization:{principalKey:'pandora-mcpmaster-production', environment:'production',
      canRead:true, retrievalDoesNotGrantExecutionAuthority:true},
    task:{intent:payload.payload.intent, actionMode:payload.payload.actionMode,
      consequential:payload.payload.consequential},
    policyMemory:[], advisoryMemory:[], degradation:{degraded:false},
  };
  return Response.json({ok:true, requestId:payload.requestId, operation:'context',
    projectId:memoryProject, namespace:'real_life', memoryProjectRef:memoryRef,
    data:{kind:'task_context', projectId:memoryProject, namespace:'real_life',
      authorizationGranted:mode === 'authority_expanded', context}});
};
const sourcePath = path.join(root, 'api/operations-memory.ts');
const parsed = ts.readConfigFile(path.join(root, 'tsconfig.json'), ts.sys.readFile);
assert.equal(parsed.error, undefined);
const options = ts.convertCompilerOptionsFromJson(parsed.config.compilerOptions, root);
assert.equal(options.errors.length, 0);
const compiled = ts.transpileModule(fs.readFileSync(sourcePath, 'utf8'), {
  fileName:sourcePath, compilerOptions:options.options,
}).outputText;
const entry = new Module(path.join(root, 'api/operations-memory.js'), module);
entry.filename = path.join(root, 'api/operations-memory.js');
entry.paths = Module._nodeModulePaths(path.dirname(entry.filename));
entry._compile(compiled, entry.filename);
const app = entry.exports.default;
const body = {operation:'context', request:{intent:'general_assistance', actionMode:'read_only',
  consequential:false, terms:['owner'], requiredCapabilities:[], maxBytes:12288}};
function request({method='POST', payload=body, authenticated=true, origin='https://mcpmaster.vercel.app'}={}) {
  calls = []; authorizationCalls = 0;
  return new Promise((resolve, reject) => {
    const bytes = Buffer.from(JSON.stringify(payload));
    const req = new IncomingMessage(new PassThrough());
    req.method = method; req.url = '/api/operations-memory';
    req.headers = {'content-type':'application/json','content-length':String(bytes.length),origin};
    if (authenticated) req.headers.authorization = 'Bearer ' + jwt;
    const res = new ServerResponse(req);
    res.end = value => {
      res.finished = true;
      const encoded = String(value);
      for (const forbidden of [jwt, workload, 'private provider diagnostic', 'stack']) {
        assert.equal(encoded.includes(forbidden), false);
      }
      resolve({status:res.statusCode, body:JSON.parse(encoded), headers:res.getHeaders()});
      return res;
    };
    app(req, res, reject); req.push(bytes); req.push(null);
  });
}
(async () => {
  let result = await request({authenticated:false});
  assert.equal(result.status, 403); assert.equal(result.body.error, 'OPS_MEMORY_OWNER_AUTH_REQUIRED');
  assert.deepEqual(calls, []);
  result = await request();
  assert.equal(result.status, 200); assert.deepEqual(calls, ['user','core','memory','core']);
  assert.equal(result.body.organizationId, org); assert.equal(result.body.projectId, project);
  assert.equal(result.body.authorizationGranted, false); assert.equal(result.body.data.authorizationGranted, false);
  assert.equal(result.body.data.state, 'available'); assert.equal(result.body.data.context.project.id, memoryProject);
  assert.equal(result.headers['cache-control'], 'no-store');
  mode = 'scope_denied'; result = await request();
  assert.equal(result.status, 403); assert.deepEqual(calls, ['user','core']);
  assert.equal(result.body.error, 'OPS_MEMORY_OWNER_SCOPE_DENIED');
  mode = 'revoked'; result = await request();
  assert.equal(result.status, 403); assert.deepEqual(calls, ['user','core','memory','core']);
  assert.equal(result.body.authorizationGranted, false); assert.equal(result.body.data, undefined);
  mode = 'authority_expanded'; result = await request();
  assert.equal(result.status, 503); assert.deepEqual(calls, ['user','core','memory']);
  assert.equal(result.body.error, 'OPS_MEMORY_CONTEXT_SCOPE_MISMATCH');
  mode = 'success'; result = await request({payload:{...body, organizationId:'caller-selected'}});
  assert.equal(result.status, 503); assert.deepEqual(calls, []);
  result = await request({origin:'https://unapproved.invalid'});
  assert.equal(result.status, 403); assert.deepEqual(calls, []);
  result = await request({method:'GET'});
  assert.equal(result.status, 403); assert.deepEqual(calls, []);
  const safe = JSON.stringify(result);
  for (const forbidden of [jwt, workload, 'private provider diagnostic', 'stack']) assert.equal(safe.includes(forbidden), false);
  process.stdout.write(JSON.stringify({checks:8, passed:true}));
})().catch(error => { process.stderr.write(error.stack); process.exitCode = 1; });
`;

for (const restricted of [false, true]) {
  test(`compiled owner Memory API preserves ESM and authority with require(ESM) ${restricted ? 'disabled' : 'default'}`, () => {
    const result = execFileSync(process.execPath,
      [...(restricted ? ['--no-experimental-require-module'] : []), '-e', smoke],
      {cwd:path.join(__dirname, '..'), encoding:'utf8', timeout:30000});
    assert.deepEqual(JSON.parse(result), {checks:8, passed:true});
  });
}
