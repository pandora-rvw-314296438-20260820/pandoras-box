// Synthetic transport contract tests. Native SQL is verified separately; no live provider claim.
(async () => {
const {default:test}=await import('node:test');
const assert=await import('node:assert/strict');
const {NativeOperationsPerformanceClient,PERFORMANCE_RPC,PERFORMANCE_CLASSES}=await import('../packages/pandora-operations-memory/performance-client.mjs');
const NOW=Date.now(), iso=delta=>new Date(NOW+delta).toISOString();
const mapping={organizationId:'11111111-1111-4111-8111-111111111111',projectId:'22222222-2222-4222-8222-222222222222',
 memoryProjectRef:'ivmvufhcsezyhczzondn',memoryProjectId:'33333333-3333-4333-8333-333333333333',
 memoryUserId:'44444444-4444-4444-8444-444444444444',namespace:'real_life',principalKey:'ops-perf-test',environment:'test'};
const scope={organizationId:mapping.organizationId,projectId:mapping.projectId};
const row=()=>({memoryItemId:'66666666-6666-4666-8666-666666666666',recordType:'provider_performance',canonStatus:'hard_canon',
 recordDigest:'a'.repeat(64),provider:'fixture',model:'fixture-model',modelRevision:'rev-1',modelRevisionKnown:true,
 configurationDigest:null,configurationKnown:false,taskClass:'complex_coding',sampleCount:3,verificationPassCount:2,
 negativeOutcomeCount:1,qualitySignal:null,meanLatencyMs:42,estimatedWindowCostMicros:100,billedWindowCostMicros:null,
 evidenceWindowStart:iso(-14400000),evidenceWindowEnd:iso(-3600000),reviewDueAt:iso(86400000),approvedAt:iso(-1800000),
 sourceRunCount:3,sourceRunsDigest:'b'.repeat(64),evidenceRefs:['verification:fixture-1'],evidenceRefCount:1,evidenceDigest:'c'.repeat(64)});
function envelope(args) {
 const {requestId,taskClass,...requested}=args.p_request;
 return {schemaVersion:'pandora-operations-performance-v1',requestId,taskClass,requested,projectId:mapping.memoryProjectId,
 namespace:mapping.namespace,principalKey:mapping.principalKey,environment:mapping.environment,observedAt:iso(0),
 state:'available',records:[row()],statistics:{scannedRecords:1,invalidRecords:0,eligibleSnapshots:1},truncated:false,
 aggregation:'latest_snapshot_per_model_revision_configuration',summingSamplesAllowed:false,
 authorizationGranted:false,providerApprovalGranted:false};
}
function make(change=()=>{},options={}) {
 const calls=[]; const client={supabaseUrl:'https://ivmvufhcsezyhczzondn.supabase.co',rpc(name,args) {
  calls.push({name,args}); const data=envelope(args); change(data,args); return Promise.resolve({data});
 }};
 return {calls,transport:client,reader:new NativeOperationsPerformanceClient({client,mapping,clock:()=>NOW,...options})};
}
test('approved numeric snapshot preserves provenance, unknown cost, and no authority',async()=>{
 const {reader,calls}=make();const r=await reader.getPerformance(scope,{taskClass:'complex_coding'});
 assert.equal(calls.length,1);assert.equal(calls[0].name,PERFORMANCE_RPC);assert.equal(r.records[0].sampleCount,3);
 assert.equal(r.records[0].billedWindowCostMicros,null);assert.equal(r.providerApprovalGranted,false);
 assert.equal(r.authorizationGranted,false);assert.equal(r.summingSamplesAllowed,false);
 assert.ok(Object.isFrozen(r.records[0]));assert.match(r.transportSha256,/^[a-f0-9]{64}$/);
 assert.equal(typeof reader.proposeOutcome,'undefined');
});
test('zero approved history stays insufficient without invented ranking',async()=>{
 const {reader}=make(r=>{r.records=[];r.state='insufficient_history';r.statistics={scannedRecords:0,invalidRecords:0,eligibleSnapshots:0};});
 const r=await reader.getPerformance(scope,{taskClass:'complex_coding'});assert.equal(r.state,'insufficient_history');
 assert.deepEqual(r.records,[]);assert.equal(Object.hasOwn(r,'bestModel'),false);
});
test('request snapshot stays immutable during an async provider call',async()=>{
 const {reader,calls}=make();const q={taskClass:'complex_coding',model:'fixture-model'};
 const result=reader.getPerformance(scope,q);q.model='other';const r=await result;
 assert.equal(calls[0].args.p_request.model,'fixture-model');assert.ok(Object.isFrozen(calls[0].args.p_request));
 assert.equal(r.requested.model,'fixture-model');
});
test('all ten frozen capability classes are recognized',()=>{assert.equal(PERFORMANCE_CLASSES.length,10);assert.ok(Object.isFrozen(PERFORMANCE_CLASSES));});
for(const [name,delta] of Object.entries({unknownClass:{taskClass:'other'},wrongModel:{model:1},providerCase:{provider:'UPPER'},
 badConfig:{configurationDigest:'x'},negativeLimit:{maxRecords:-1},zeroLimit:{maxRecords:0},overLimit:{maxRecords:17},
 stringLimit:{maxRecords:'16'},unsafeLimit:{maxRecords:1e100},extraSql:{sql:'select 1'},extraUrl:{url:'https://example.test'}})) {
 test(`request rejects ${name} before transport`,async()=>{const {reader,calls}=make();
  await assert.rejects(reader.getPerformance(scope,{taskClass:'complex_coding',...delta}),e=>e.code.startsWith('OPS_MEMORY_'));
  assert.equal(calls.length,0);
 });
}
for(const [name,change] of Object.entries({wrongNonce:r=>r.requestId='55555555-5555-4555-8555-555555555555',
 wrongProject:r=>r.projectId=scope.projectId,wrongNamespace:r=>r.namespace='au',wrongPrincipal:r=>r.principalKey='other',
 wrongEnvironment:r=>r.environment='production',wrongClass:r=>r.taskClass='vision',wrongFilters:r=>r.requested.model='other',
 grantedAuthority:r=>r.authorizationGranted=true,approvedProvider:r=>r.providerApprovalGranted=true,
 sumOverlaps:r=>r.summingSamplesAllowed=true,unknownAggregation:r=>r.aggregation='sum',extraField:r=>r.raw='private',
 oldEnvelope:r=>r.observedAt=iso(-61000),futureEnvelope:r=>r.observedAt=iso(31000),
 emptyAvailable:r=>r.records=[],wrongCounts:r=>r.statistics.invalidRecords=2,unreportedTruncation:r=>r.statistics.eligibleSnapshots=2,
 duplicateCohort:r=>{r.records.push({...r.records[0],memoryItemId:'77777777-7777-4777-8777-777777777777'});r.statistics={scannedRecords:2,invalidRecords:0,eligibleSnapshots:2};}})) {
 test(`response rejects ${name}`,async()=>{const {reader}=make(change);
  await assert.rejects(reader.getPerformance(scope,{taskClass:'complex_coding'}),e=>e.code.startsWith('OPS_MEMORY_'));
 });
}
for(const [name,delta] of Object.entries({unapproved:{canonStatus:'soft_canon'},wrongType:{recordType:'fact'},
 invalidDigest:{recordDigest:'bad'},arrayId:{memoryItemId:['66666666-6666-4666-8666-666666666666']},
 arrayRecordDigest:{recordDigest:['a'.repeat(64)]},arrayRunsDigest:{sourceRunsDigest:['b'.repeat(64)]},
 arrayEvidenceDigest:{evidenceDigest:['c'.repeat(64)]},arrayConfiguration:{configurationDigest:['a'.repeat(64)],configurationKnown:true},numericModel:{model:2},providerCase:{provider:'Fixture'},unknownRevisionLie:{modelRevision:null},
 knownConfigLie:{configurationKnown:true},zeroSamples:{sampleCount:0},wrongRunCount:{sourceRunCount:4},
 tooManyPasses:{verificationPassCount:4},tooManyFailures:{negativeOutcomeCount:4},fractionalCount:{sampleCount:3.2},
 unsafeCount:{sampleCount:9007199254740992},qualityString:{qualitySignal:'1'},qualityOutside:{qualitySignal:2},
 negativeLatency:{meanLatencyMs:-1},costString:{billedWindowCostMicros:'100'},unsafeCost:{estimatedWindowCostMicros:1e100},
 expired:{reviewDueAt:iso(-1)},futureApproval:{approvedAt:iso(1)},reversedWindow:{evidenceWindowStart:iso(0)},
 missingZone:{evidenceWindowEnd:'2026-01-01T00:00:00'},missingRefs:{evidenceRefs:[]},evidenceCount:{evidenceRefCount:5},
 invalidRef:{evidenceRefs:['https://a:b@host']},numericRef:{evidenceRefs:[1]},wrongTask:{taskClass:'vision'}})) {
 test(`record rejects ${name}`,async()=>{const {reader}=make(r=>Object.assign(r.records[0],delta));
  await assert.rejects(reader.getPerformance(scope,{taskClass:'complex_coding'}),e=>e.code.startsWith('OPS_MEMORY_'));
 });
}
test('unknown revision and unknown configuration are explicit',async()=>{const {reader}=make(r=>{
 Object.assign(r.records[0],{modelRevision:null,modelRevisionKnown:false,configurationDigest:null,configurationKnown:false});
});assert.equal((await reader.getPerformance(scope,{taskClass:'complex_coding'})).records[0].modelRevisionKnown,false);});
test('exact provider filter mismatch is rejected',async()=>{const {reader}=make();
 await assert.rejects(reader.getPerformance(scope,{taskClass:'complex_coding',provider:'different'}),/FILTER_MISMATCH/);
});
test('foreign source scope is denied before transport',async()=>{const {reader,calls}=make();
 await assert.rejects(reader.getPerformance({...scope,projectId:mapping.memoryProjectId},{taskClass:'complex_coding'}),/SOURCE_SCOPE_DENIED/);
 assert.equal(calls.length,0);
});
for(const url of ['http://ivmvufhcsezyhczzondn.supabase.co','https://example.test','https://ivmvufhcsezyhczzondn.supabase.co/?q=1',
 'https://user:pass@ivmvufhcsezyhczzondn.supabase.co','https://ivmvufhcsezyhczzondn.supabase.co/rest/v1']) {
 test(`rejects unexpected client target ${url}`,()=>{assert.throws(()=>new NativeOperationsPerformanceClient({
  client:{supabaseUrl:url,rpc(){}},mapping}),/TARGET_DENIED/);});
}
test('client target mutation is detected before call',async()=>{const {reader,transport,calls}=make();transport.supabaseUrl='https://example.test';
 await assert.rejects(reader.getPerformance(scope,{taskClass:'complex_coding'}),/TARGET_DENIED/);assert.equal(calls.length,0);});
test('pre-cancelled read does not execute',async()=>{const {reader,calls}=make();const controller=new AbortController();controller.abort();
 await assert.rejects(reader.getPerformance(scope,{taskClass:'complex_coding'},{signal:controller.signal}),/CANCELLED/);assert.equal(calls.length,0);});
test('timeout aborts a hung request with no retry',async()=>{const {reader,transport,calls}=make(()=>{},{timeoutMs:100});let attempted=0;
 transport.rpc=()=>{attempted++;return new Promise(()=>{});};
 await assert.rejects(reader.getPerformance(scope,{taskClass:'complex_coding'}),/TIMEOUT/);assert.equal(attempted,1);assert.equal(calls.length,0);});
test('active cancellation aborts the read',async()=>{const {reader,transport}=make();transport.rpc=()=>new Promise(()=>{});
 const controller=new AbortController();const pending=reader.getPerformance(scope,{taskClass:'complex_coding'},{signal:controller.signal});
 controller.abort();await assert.rejects(pending,/CANCELLED/);});
for(const [name,error,expected] of [['revoked',{message:'OPS_MEMORY_PERFORMANCE_GRANT_DENIED'},'OPS_MEMORY_PERFORMANCE_GRANT_DENIED'],
 ['permission',{message:'sensitive provider detail',code:'42501'},'OPS_MEMORY_ACCESS_DENIED'],
 ['provider',{message:'sensitive provider detail',code:'unexpected'},'OPS_MEMORY_PROVIDER_ERROR']]) {
 test(`sanitized ${name} provider error`,async()=>{const {reader,transport}=make();transport.rpc=async()=>({error});
  await assert.rejects(reader.getPerformance(scope,{taskClass:'complex_coding'}),e=>e.code===expected&&e.message===expected);
 });
}
test('thrown transport details are never leaked',async()=>{const {reader,transport}=make();transport.rpc=()=>{throw new Error('private URL');};
 await assert.rejects(reader.getPerformance(scope,{taskClass:'complex_coding'}),e=>e.message==='OPS_MEMORY_TRANSPORT_UNAVAILABLE');});
test('secret-shaped evidence is rejected rather than returned',async()=>{const {reader}=make(r=>{r.records[0].evidenceRefs=['github_pat_'+'x'.repeat(30)];});
 await assert.rejects(reader.getPerformance(scope,{taskClass:'complex_coding'}),/CREDENTIAL_REJECTED/);});
test('mapping is immutable after construction',async()=>{const mutable={...mapping};const {reader,calls}=make(()=>{},{mapping:mutable});
 mutable.memoryProjectId=scope.projectId;await reader.getPerformance(scope,{taskClass:'complex_coding'});
 assert.equal(calls[0].args.p_project_id,mapping.memoryProjectId);});
test('exact native SQL and real client agree on approved history and denial', {skip:!process.env.PANDORA_PERFORMANCE_SQL}, async()=>{
 const {readFileSync}=await import('node:fs');
 const {PGlite}=await import(process.env.PANDORA_PGLITE_MODULE || '@electric-sql/pglite');
 const db=new PGlite();
 try {
  await db.exec(readFileSync(process.env.PANDORA_PERFORMANCE_SQL,'utf8'));
  const client={supabaseUrl:'https://ivmvufhcsezyhczzondn.supabase.co',async rpc(name,a) {
   assert.equal(name,PERFORMANCE_RPC);
   try {return {data:(await db.query('select public.memory_operations_performance_v1($1::uuid,$2,$3::uuid,$4,$5,$6::jsonb) as payload',
    [a.p_memory_user_id,a.p_namespace,a.p_project_id,a.p_principal_key,a.p_environment,JSON.stringify(a.p_request)])).rows[0].payload};}
   catch(e){return {error:{code:e.code,message:e.message}};}
  }};
  const reader=new NativeOperationsPerformanceClient({client,mapping});
  const actual=await reader.getPerformance(scope,{taskClass:'complex_coding'});
  assert.equal(actual.state,'available');assert.equal(actual.records[0].sampleCount,3);
  assert.equal(actual.records[0].billedWindowCostMicros,null);assert.equal(actual.records[0].configurationKnown,false);
  const empty=await reader.getPerformance(scope,{taskClass:'complex_coding',provider:'not_present'});
  assert.equal(empty.state,'insufficient_history');assert.equal(empty.authorizationGranted,false);
  await db.exec("update public.pandora_project_grants set revoked_at=clock_timestamp() where principal_key='ops-perf-test'");
  await assert.rejects(reader.getPerformance(scope,{taskClass:'complex_coding'}),/PERFORMANCE_GRANT_DENIED/);
 } finally {await db.close();}
});
})().catch(error=>{console.error(error);process.exitCode=1;});
