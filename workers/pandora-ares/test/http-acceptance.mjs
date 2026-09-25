import test from 'node:test';
import assert from 'node:assert/strict';
import {fixture,signed,grant} from './fixtures.mjs';
import {createAresHandler} from '../handler.mjs';
import {createHttpsLeaseReader} from '../authority.mjs';

const endpoint='https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-ares-control';
async function setup(t){const x=await fixture();t.after(()=>x.close());return x;}
function request(value,headers={}) {return new Request('https://ares.invalid/',{method:'POST',headers:{'content-type':'application/json',...headers},body:JSON.stringify(value)});}

test('ARES HTTP handler invokes exact signed job and replays without another SDK call',async t=>{
  const x=await setup(t),handler=createAresHandler({host:x.host}),job=x.job(),value={job,grantToken:signed(grant(job))};
  const first=await handler(request(value));assert.equal(first.status,200);const calls=x.sdk.calls.length;
  const second=await handler(request(value));assert.equal((await second.json()).result.replayed,true);assert.equal(x.sdk.calls.length,calls);
});
test('ARES HTTP denies browser origins, wrong methods and unsupported content type',async t=>{
  const x=await setup(t),handler=createAresHandler({host:x.host});
  assert.equal((await handler(new Request('https://ares.invalid/'))).status,405);
  assert.equal((await handler(request({},{origin:'https://foreign.invalid'}))).status,403);
  assert.equal((await handler(request({},{'content-type':'text/plain'}))).status,415);assert.equal(x.sdk.calls.length,0);
});
test('ARES HTTP rejects credentials in a job before execution and never echoes input',async t=>{
  const x=await setup(t),handler=createAresHandler({host:x.host}),job=x.job();
  const r=await handler(request({job:{...job,service_role:'sb_secret_'+ 's'.repeat(40)},grantToken:'bogus'}));
  assert.equal(r.status,400);const text=await r.text();assert.ok(!text.includes('sb_secret_'));assert.equal(x.sdk.calls.length,0);
});
test('ARES HTTP enforces actual streamed body size even without length header',async t=>{
  const x=await setup(t),handler=createAresHandler({host:x.host});
  const r=await handler(request({x:'a'.repeat(50000)}));assert.equal(r.status,413);
});
test('ARES HTTP body timeout is bounded and does not occupy a worker forever',async t=>{
  const x=await setup(t),handler=createAresHandler({host:x.host,maxConcurrent:1,bodyTimeoutMs:50});
  const stream=new ReadableStream({start(controller){controller.enqueue(new TextEncoder().encode('{'));}});
  const req=new Request('https://ares.invalid/',{method:'POST',headers:{'content-type':'application/json'},body:stream,duplex:'half'});
  const result=await handler(req);assert.equal((await result.json()).code,'ARES_BODY_TIMEOUT');
  const job=x.job(),ok=await handler(request({job,grantToken:signed(grant(job))}));assert.equal(ok.status,200);
});
for(const url of ['http://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-ares-control','https://example.com/functions/v1/pandora-ares-control',endpoint+'?token=notreal',endpoint+'/other',endpoint.replace('https://','https://user:password@')]) {
  test('Control transport rejects wrong endpoint '+url.replace(/user:password/,'redacted'),()=>assert.throws(()=>createHttpsLeaseReader({endpoint:url,signNodeRequest:async()=>''}),/ENDPOINT_DENIED/));
}
test('Control HTTP read uses signed node request and returns only proof',async()=>{
  let options;
  const reader=createHttpsLeaseReader({endpoint,signNodeRequest:async()=> 'node-jws-fixture',fetchImpl:async(_url,opts)=>{options=opts;return new Response(JSON.stringify({ok:true,signedProof:'control-jws-fixture'}));}});
  assert.equal(await reader({nonce:'fixture'}),'control-jws-fixture');assert.equal(options.redirect,'error');assert.deepEqual(Object.keys(options.headers),['content-type']);assert.equal(JSON.parse(options.body).signedRequest,'node-jws-fixture');
});
test('Control timeout includes the protected signing callback',async()=>{
  const reader=createHttpsLeaseReader({endpoint,timeoutMs:100,signNodeRequest:async()=>new Promise(()=>{}),fetchImpl:async()=>{throw Error('must not call');}});
  await assert.rejects(()=>reader({nonce:'fixture'}),/CONTROL_UNAVAILABLE/);
});
test('Control timeout includes response body, not just headers',async()=>{
  const reader=createHttpsLeaseReader({endpoint,timeoutMs:100,signNodeRequest:async()=> 'fixture',fetchImpl:async()=>new Response(new ReadableStream({start(controller){controller.enqueue(new TextEncoder().encode('{'));}}))});
  await assert.rejects(()=>reader({nonce:'fixture'}),/CONTROL_UNAVAILABLE/);
});
test('Control stream output is bounded independently from headers',async()=>{
  const reader=createHttpsLeaseReader({endpoint,signNodeRequest:async()=> 'fixture',fetchImpl:async()=>new Response('x'.repeat(21000))});
  await assert.rejects(()=>reader({nonce:'fixture'}),/CONTROL_RESPONSE_LIMIT/);
});
