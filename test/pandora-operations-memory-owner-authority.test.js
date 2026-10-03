'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const {SupabaseBearerAuthenticator} = require('../apps/meta-business-mcp/src/auth/supabase-bearer.js');

const ownerModule = import('../packages/pandora-operations-memory/owner-read.mjs');
const box = 'https://jcyqixttuebxqqfkjonq.supabase.co';
const authorizationUrl = `${box}/rest/v1/rpc/pandora_core_authorize_memory_v1`;
const publishableKey = 'sb_publishable_owner_memory_test_fixture';
const jwt = ['header'.repeat(6),'payload'.repeat(8),'signature'.repeat(5)].join('.');
const userId = '33e5b2de-048b-4814-b601-7d7daac7a649';
const request = {operation:'context',request:{intent:'general_assistance',actionMode:'read_only'}};
const safeError = (code) => error => error.code === code && error.message === code && error.cause === undefined;

async function authorizer(fetchFn, options = {}) {
  const {CoreOwnerMemoryAuthorizer} = await ownerModule;
  return new CoreOwnerMemoryAuthorizer({supabaseUrl:box,publishableKey,fetchFn,...options});
}

test('Core authority uses only the canonical no-argument RPC and actual caller JWT', async () => {
  let calls = 0;
  const gate = await authorizer(async (url, init) => {
    calls++;
    assert.equal(url, authorizationUrl);
    assert.equal(init.method, 'POST');
    assert.equal(init.redirect, 'error');
    assert.equal(init.body, '{}');
    assert.deepEqual(init.headers, {apikey:publishableKey,authorization:`Bearer ${jwt}`,
      'content-type':'application/json',accept:'application/json'});
    assert.ok(init.signal instanceof AbortSignal);
    return Response.json(true);
  });
  assert.equal(await gate.authorize(jwt), true);
  assert.equal(calls, 1);
});

for (const supabaseUrl of ['https://example.invalid',`${box}/`,`${box}?target=elsewhere`]) {
  test(`Core authority refuses a noncanonical configured URL: ${supabaseUrl}`, async () => {
    await assert.rejects(authorizer(() => assert.fail('provider must not be called'), {supabaseUrl}), /OWNER_CONFIGURATION_REQUIRED/);
  });
}

for (const key of ['sb_secret_test_credential_never_used',jwt,'','fixture']) {
  test(`Core authority rejects non-publishable configuration ${key.length}`, async () => {
    await assert.rejects(authorizer(() => assert.fail('provider must not be called'), {publishableKey:key}), /OWNER_CONFIGURATION_REQUIRED/);
  });
}

for (const value of [false,null,'true',1,{},[true]]) {
  test(`Core authorization must return literal true, not ${JSON.stringify(value)}`, async () => {
    const gate = await authorizer(async () => Response.json(value));
    await assert.rejects(gate.authorize(jwt), safeError('OPS_MEMORY_OWNER_SCOPE_DENIED'));
  });
}

for (const status of [401,403,500,503]) {
  test(`Core authorization ${status} response is redacted and never retried`, async () => {
    let calls = 0;
    const gate = await authorizer(async () => {
      calls++;
      return Response.json({code:'42501',message:'Private provider diagnostics',details:jwt},{status});
    });
    const code = status < 500 ? 'OPS_MEMORY_OWNER_SCOPE_DENIED' : 'OPS_MEMORY_OWNER_AUTHORIZATION_UNAVAILABLE';
    await assert.rejects(gate.authorize(jwt), safeError(code));
    assert.equal(calls, 1);
  });
}

test('Malformed authorization JSON and transport errors expose no diagnostics', async () => {
  for (const fetchFn of [async () => new Response('private malformed response'),async () => {throw new Error(`provider failure ${jwt}`);}]) {
    const gate = await authorizer(fetchFn);
    await assert.rejects(gate.authorize(jwt), safeError('OPS_MEMORY_OWNER_AUTHORIZATION_UNAVAILABLE'));
  }
});

test('Authorization response is bounded with and without Content-Length', async () => {
  for (const headers of [{},{'content-length':'10000'}]) {
    const gate = await authorizer(async () => new Response(' '.repeat(10000)+'true',{headers}));
    await assert.rejects(gate.authorize(jwt), safeError('OPS_MEMORY_OWNER_AUTHORIZATION_UNAVAILABLE'));
  }
});

test('An unresponsive authorization provider cannot retain the request past its deadline', async () => {
  let signal;
  const gate = await authorizer((_url, init) => {signal=init.signal;return new Promise(() => {});},{timeoutMs:10});
  await assert.rejects(gate.authorize(jwt), safeError('OPS_MEMORY_OWNER_AUTHORIZATION_UNAVAILABLE'));
  assert.equal(signal.aborted, true);
});

test('An unresponsive authorization response stream is also cancelled at the deadline', async () => {
  let cancelled = false;
  const gate = await authorizer(async () => new Response(new ReadableStream({cancel(){cancelled=true;}})), {timeoutMs:10});
  await assert.rejects(gate.authorize(jwt), safeError('OPS_MEMORY_OWNER_AUTHORIZATION_UNAVAILABLE'));
  assert.equal(cancelled, true);
});

async function readerFixture({answers=[true,true],identity={},fetchFailureAt=0}={}) {
  const {createOwnerMemoryRead} = await ownerModule;
  const calls = [];
  let authorizationCalls = 0;
  const coreAuthorizer = await authorizer(async () => {
    calls.push('core');
    authorizationCalls++;
    if (authorizationCalls === fetchFailureAt) throw new Error('private transport failure');
    return Response.json(answers[authorizationCalls-1]);
  });
  const run = createOwnerMemoryRead({
    authenticator:{authenticate:async () => {calls.push('authenticate');return {userId,accessToken:jwt,scopeClaimsPresent:false,...identity};}},
    coreAuthorizer,
    // Legacy membership flags are intentionally not consulted for authorization.
    membershipResolver:{resolve:async () => assert.fail('legacy role gate must not be used')},
    memory:{
      getTaskContext:async scope => {calls.push('memory');return {scope,state:'available',authorizationGranted:false};},
      getPerformance:async () => {calls.push('memory');return {state:'insufficient_history',authorizationGranted:false};},
    },
  });
  return {run,calls};
}

test('Core owner authority is checked before and after the Memory read with fixed scope', async () => {
  const {OPERATIONS_MEMORY_MAPPING:m} = await ownerModule;
  const f = await readerFixture();
  const result = await f.run(`Bearer ${jwt}`,request);
  assert.deepEqual(f.calls,['authenticate','core','memory','core']);
  assert.deepEqual(result.data.scope,{organizationId:m.organizationId,projectId:m.projectId});
  assert.equal(result.authorizationGranted,false);
});

test('Platform owner/admin membership alone cannot initiate a Memory provider read', async () => {
  const f = await readerFixture({answers:[false]});
  await assert.rejects(f.run(`Bearer ${jwt}`,request),safeError('OPS_MEMORY_OWNER_SCOPE_DENIED'));
  assert.deepEqual(f.calls,['authenticate','core']);
});

test('Core grant revocation during the provider read prevents the response from leaving the endpoint', async () => {
  const f = await readerFixture({answers:[true,false]});
  await assert.rejects(f.run(`Bearer ${jwt}`,request),safeError('OPS_MEMORY_OWNER_SCOPE_DENIED'));
  assert.deepEqual(f.calls,['authenticate','core','memory','core']);
});

for (const fetchFailureAt of [1,2]) {
  test(`Core authorization network failure at check ${fetchFailureAt} fails closed`, async () => {
    const f = await readerFixture({fetchFailureAt});
    await assert.rejects(f.run(`Bearer ${jwt}`,request),safeError('OPS_MEMORY_OWNER_AUTHORIZATION_UNAVAILABLE'));
    assert.equal(f.calls.filter(x=>x==='memory').length,fetchFailureAt===1?0:1);
  });
}

for (const header of ['',`Basic ${jwt}`,'Bearer pmt_v1_fixture_credential_not_used','Bearer opaque_test_token_not_used']) {
  test(`Non-user bearer input is denied before authentication (${header.split(' ')[0]||'empty'})`, async () => {
    const f = await readerFixture();
    await assert.rejects(f.run(header,request),safeError('OPS_MEMORY_OWNER_AUTH_REQUIRED'));
    assert.deepEqual(f.calls,[]);
  });
}

for (const identity of [{scopeClaimsPresent:true},{accessToken:`${jwt}different`},{userId:null}]) {
  test(`Invalid authenticated identity cannot reach Core RPC (${Object.keys(identity)[0]})`, async () => {
    const f = await readerFixture({identity});
    await assert.rejects(f.run(`Bearer ${jwt}`,request),safeError('OPS_MEMORY_OWNER_AUTH_REQUIRED'));
    assert.deepEqual(f.calls,['authenticate']);
  });
}

for (const key of ['organizationId','projectId','memoryUserId','principalKey']) {
  test(`The Memory read body cannot override ${key}`, async () => {
    const f = await readerFixture();
    await assert.rejects(f.run(`Bearer ${jwt}`,{...request,[key]:'caller-selected'}), /FIELDS_INVALID/);
    assert.deepEqual(f.calls,[]);
  });
}

test('The real bearer authenticator verifies the user before both caller-JWT Core RPC checks', async () => {
  const {createOwnerMemoryRead} = await ownerModule;
  const calls = [];
  const fetchFn = async (url,init) => {
    calls.push(String(url));
    assert.equal(init.headers.apikey,publishableKey);
    assert.equal(init.headers.authorization,`Bearer ${jwt}`);
    if (String(url) === `${box}/auth/v1/user`) return Response.json({id:userId,is_anonymous:false});
    assert.equal(url,authorizationUrl);
    return Response.json(true);
  };
  const options = {supabaseUrl:box,publishableKey,fetchFn,timeoutMs:1000};
  const {CoreOwnerMemoryAuthorizer} = await ownerModule;
  const run = createOwnerMemoryRead({authenticator:new SupabaseBearerAuthenticator(options),
    coreAuthorizer:new CoreOwnerMemoryAuthorizer(options),
    memory:{getTaskContext:async()=>{calls.push('memory');return {state:'available'};},getPerformance:async()=>assert.fail()},
  });
  const result = await run(`Bearer ${jwt}`,request);
  assert.deepEqual(calls,[`${box}/auth/v1/user`,authorizationUrl,'memory',authorizationUrl]);
  assert.equal(result.authorizationGranted,false);
});

test('Vercel owner endpoint wires mandatory Core authorization without legacy membership fallback', () => {
  const route = fs.readFileSync('api/operations-memory.ts','utf8');
  assert.match(route,/coreAuthorizer:new CoreOwnerMemoryAuthorizer\(options\)/);
  assert.doesNotMatch(route,/SupabaseOrganizationMembershipResolver|membershipResolver:/);
  assert.match(route,/new SupabaseBearerAuthenticator\(options\)/);
});
