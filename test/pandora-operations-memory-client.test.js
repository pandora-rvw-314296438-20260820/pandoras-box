const test = require('node:test');
const assert = require('node:assert/strict');
const NOW = Date.parse('2026-09-25T18:00:00Z');
const ids = Array.from({length:9}, (_,i) => `${String(i+1).repeat(8)}-${String(i+1).repeat(4)}-4${String(i+1).repeat(3)}-8${String(i+1).repeat(3)}-${String(i+1).repeat(12)}`);
const mapping = () => ({organizationId:ids[0],projectId:ids[1],memoryProjectRef:'ivmvufhcsezyhczzondn',
  memoryProjectId:ids[2],memoryUserId:ids[3],namespace:'real_life',principalKey:'ops-test-principal',environment:'test'});
const scope = () => ({organizationId:ids[0],projectId:ids[1]});
const outcome = () => ({contractVersion:'pandora-operations-model-outcome-v1',sourceRunId:ids[4],
  provider:'fixture',model:'fixture-model',modelRevision:null,taskClass:'complex_coding',routingPolicyVersion:'policy.v1',
  executionStatus:'succeeded',verificationStatus:'pass',downstreamOutcomeStatus:'accepted',qualitySignal:null,
  latencyMs:42,estimatedCostMicros:100,billedCostMicros:null,occurredAt:'2026-09-25T17:00:00Z',
  evidenceRefs:['verification:fixture-result'],sourceCommit:'a'.repeat(40),sourceDeploymentRef:null,
  reviewDueAt:'2026-10-25T17:00:00Z',usage:{inputTokens:null,outputTokens:null,totalTokens:null},retryCount:0,configurationDigest:null});
const query = () => ({intent:'coding_building',actionMode:'state_change',consequential:true,
  terms:['router','memory'],requiredCapabilities:['inference.execute'],maxBytes:12288});
function pack(args) {
  const q=args.p_payload;
  return {kind:'task_context',projectId:ids[2],namespace:'real_life',authorizationGranted:false,context:{
    schemaVersion:'m5.task-aware-retrieval.v1',status:'available',namespace:'real_life',project:{id:ids[2]},
    contextSha256:'b'.repeat(64),task:{intent:q.intent,actionMode:q.actionMode,consequential:q.consequential},
    authorization:{principalKey:'ops-test-principal',environment:'test',canRead:true,retrievalDoesNotGrantExecutionAuthority:true},
    policyMemory:[],advisoryMemory:[{id:ids[5],recordType:'fact',canonStatus:'hard_canon',knowledgeSchemaVersion:'m5.v1',summary:'Synthetic fixture context.',authorizationEffect:'none'}],
    degradation:{degraded:false},warnings:[]}};
}
async function fixture(transform = null, options = {}) {
  const {NativeOperationsMemoryClient}=await import('../packages/pandora-operations-memory/native-client.mjs');
  const {stableDigest}=await import('../packages/pandora-operations-memory/contracts.mjs');
  const calls=[],rows=new Map();
  const server = async (name,args) => {
    assert.equal(name,'memory_operations_bridge_v1');
    assert.equal(args.p_project_id,ids[2]);assert.equal(args.p_memory_user_id,ids[3]);
    assert.equal(args.p_namespace,'real_life');assert.equal(args.p_principal_key,'ops-test-principal');
    if(args.p_operation==='context')return {data:pack(args),error:null};
    const body=args.p_operation==='readback'?args.p_payload.expectedPayload:args.p_payload;
    const digest=stableDigest(body),old=rows.get(body.sourceRunId);
    if(old&&old.payloadSha256!==digest)return {data:null,error:{code:'22023',message:'OPS_MEMORY_REPLAY_CONFLICT'}};
    if(args.p_operation==='propose_outcome'&&!old)rows.set(body.sourceRunId,{kind:'outcome_receipt',found:true,readbackVerified:true,
      projectId:ids[2],namespace:'real_life',sourceRunId:body.sourceRunId,receiptId:ids[6],candidateId:ids[7],reviewItemId:ids[8],
      payloadSha256:digest,idempotentReplay:false,currentReviewStatus:'pending_review',requiresReview:true,
      canonicalMemoryWritten:false,modelRevisionKnown:body.modelRevision!==null});
    return {data:structuredClone(rows.get(body.sourceRunId)??{found:false,requiresReconciliation:true,canonicalMemoryWritten:false}),error:null};
  };
  const client={supabaseUrl:'https://ivmvufhcsezyhczzondn.supabase.co',rpc(name,args){
    calls.push({name,args:structuredClone(args)});
    const request={abortSignal(signal){this.signal=signal;return this;},then(resolve,reject){return Promise.resolve().then(()=>transform?transform(name,args,server,rows,request.signal):server(name,args)).then(resolve,reject);}};
    return request;
  }};
  return {bridge:new NativeOperationsMemoryClient({client,mapping:mapping(),clock:()=>NOW,...options}),calls,rows,client,NativeOperationsMemoryClient};
}

test('native context retrieval uses fixed mapped project and preserves authority separation',async()=>{
  const f=await fixture(),r=await f.bridge.getTaskContext(scope(),query());
  assert.equal(r.state,'available');assert.equal(r.authorizationGranted,false);
  assert.equal(r.performanceStatisticsDerived,false);assert.equal(r.context.advisoryMemory.length,1);
  assert.equal(r.receiptRef,'memory-context:'+'b'.repeat(64));assert.equal(r.transportSha256.length,64);
  assert.deepEqual(f.calls[0].args.p_payload.terms,['memory','router']);
  assert(Object.isFrozen(r.context.advisoryMemory));
});
test('model outcome persists once then requires a separate readback',async()=>{
  const f=await fixture(),r=await f.bridge.proposeOutcome(scope(),outcome());
  assert.equal(r.state,'pending_review');assert.equal(r.deliveryVerified,true);assert.equal(r.canonicalMemoryWritten,false);
  assert.deepEqual(f.calls.map(c=>c.args.p_operation),['propose_outcome','readback']);assert.equal(f.rows.size,1);
  assert.equal(f.calls[0].args.p_payload.billedCostMicros,null);assert.equal(r.modelRevisionKnown,false);
});
test('same exact outcome replay is idempotent; changed outcome is rejected',async()=>{
  const f=await fixture();await f.bridge.proposeOutcome(scope(),outcome());await f.bridge.proposeOutcome(scope(),outcome());
  assert.equal(f.rows.size,1);
  await assert.rejects(f.bridge.proposeOutcome(scope(),{...outcome(),model:'other-model'}),{code:'OPS_MEMORY_REPLAY_CONFLICT'});
});
test('lost write response is reconciled with a read, never a repeated write',async()=>{
  const f=await fixture(async(n,a,server)=>{const r=await server(n,a);if(a.p_operation==='propose_outcome')throw Error('Bearer '+'x'.repeat(30));return r;});
  const r=await f.bridge.proposeOutcome(scope(),outcome());assert.equal(r.deliveryVerified,true);assert.equal(r.recoveredAfterUnknownResponse,true);
  assert.equal(f.calls.filter(c=>c.args.p_operation==='propose_outcome').length,1);
  assert(!JSON.stringify(r).includes('Bearer'));assert.equal(f.rows.size,1);
});
test('unknown uncommitted outcome remains reconciliation_required, not a false success',async()=>{
  const f=await fixture(async(n,a,server)=>{if(a.p_operation==='propose_outcome')throw Error('network');return server(n,a);});
  const r=await f.bridge.proposeOutcome(scope(),outcome());assert.equal(r.state,'reconciliation_required');assert.equal(r.deliveryVerified,false);
  assert.deepEqual(f.calls.map(c=>c.args.p_operation),['propose_outcome','readback']);
});
test('readback-only reconciliation cannot create a candidate',async()=>{
  const f=await fixture(),r=await f.bridge.reconcileOutcome(scope(),outcome());assert.equal(r.state,'reconciliation_required');
  assert.equal(f.rows.size,0);assert.deepEqual(f.calls.map(c=>c.args.p_operation),['readback']);
});
test('provider grant denial is not relabeled as an ambiguous mutation',async()=>{
  const f=await fixture(async()=>({data:null,error:{message:'OPS_MEMORY_GRANT_DENIED',code:'42501'}}));
  await assert.rejects(f.bridge.proposeOutcome(scope(),outcome()),{code:'OPS_MEMORY_GRANT_DENIED',outcomeUnknown:false});
  assert.equal(f.calls.length,1);
});
test('cross-project and cross-organization requests fail before RPC',async()=>{
  const f=await fixture();
  for(const s of [{...scope(),projectId:ids[5]},{...scope(),organizationId:ids[5]}])
    await assert.rejects(f.bridge.getTaskContext(s,query()),{code:'OPS_MEMORY_SOURCE_SCOPE_DENIED'});
  assert.equal(f.calls.length,0);
});
test('wrong Memory host, credential URL and unapproved namespace are rejected',async()=>{
  const f=await fixture();
  for(const url of ['https://jcyqixttuebxqqfkjonq.supabase.co','https://ivmvufhcsezyhczzondn.supabase.co.evil.test','https://user:pass@ivmvufhcsezyhczzondn.supabase.co','http://ivmvufhcsezyhczzondn.supabase.co'])
    assert.throws(()=>new f.NativeOperationsMemoryClient({client:{...f.client,supabaseUrl:url},mapping:mapping()}));
  assert.throws(()=>new f.NativeOperationsMemoryClient({client:f.client,mapping:{...mapping(),namespace:'au'}}));
});
test('mapping and source inputs are snapshotted before awaits',async()=>{
  const f=await fixture(),m=mapping(),bridge=new f.NativeOperationsMemoryClient({client:f.client,mapping:m,clock:()=>NOW});
  m.memoryProjectId=ids[5];const o=outcome(),p=bridge.proposeOutcome(scope(),o);o.model='tampered';
  assert.equal((await p).deliveryVerified,true);assert.equal(f.calls[0].args.p_payload.model,'fixture-model');
});

const invalid=[
  ['unknown field',o=>{o.rawSql='select 1';}],['prompt field',o=>{o.prompt='customer data';}],
  ['version',o=>{o.contractVersion='other';}],['run identity',o=>{o.sourceRunId='not-uuid';}],
  ['numeric provider',o=>{o.provider=1;}],['provider case',o=>{o.provider='Fixture';}],
  ['model whitespace',o=>{o.model=' model';}],['model newline',o=>{o.model='a\nb';}],
  ['revision type',o=>{o.modelRevision=123;}],['source hash',o=>{o.sourceCommit='main';}],
  ['config hash',o=>{o.configurationDigest='not-sha';}],['deployment credentials',o=>{o.sourceDeploymentRef='https://x:y@host';}],
  ['no verification',o=>{o.verificationStatus='unavailable';}],['fake success status',o=>{o.executionStatus='ready';}],
  ['downstream status',o=>{o.downstreamOutcomeStatus='complete';}],['quality string',o=>{o.qualitySignal='1';}],
  ['quality range',o=>{o.qualitySignal=2;}],['negative latency',o=>{o.latencyMs=-1;}],
  ['latency string',o=>{o.latencyMs='42';}],['unsafe cost',o=>{o.billedCostMicros=Number.MAX_SAFE_INTEGER+1;}],
  ['usage missing field',o=>{delete o.usage.totalTokens;}],['usage secret field',o=>{o.usage.apiKey='x';}],
  ['negative usage',o=>{o.usage.inputTokens=-1;}],['usage string',o=>{o.usage.totalTokens='12';}],
  ['fractional retries',o=>{o.retryCount=0.5;}],['unbounded retries',o=>{o.retryCount=17;}],
  ['missing evidence',o=>{o.evidenceRefs=[];}],['duplicate evidence',o=>{o.evidenceRefs=['v:1','v:1'];}],
  ['evidence overflow',o=>{o.evidenceRefs=Array.from({length:32},(_,i)=>'v:'+i);}],
  ['evidence credentials',o=>{o.evidenceRefs=['Bearer '+'x'.repeat(30)];}],
  ['future timestamp',o=>{o.occurredAt='2027-01-01T00:00:00Z';}],['missing timezone',o=>{o.occurredAt='2026-09-25T17:00:00';}],
  ['reversed freshness',o=>{o.reviewDueAt=o.occurredAt;}],['unbounded freshness',o=>{o.reviewDueAt='2030-01-01T00:00:00Z';}],
  ['missing nullable metric',o=>{delete o.billedCostMicros;}],['token in model',o=>{o.model='github_pat_'+'x'.repeat(24);}]
];
for(const[name,mutate]of invalid)test('outcome rejects '+name+' without any provider call',async()=>{
  const f=await fixture(),o=outcome();mutate(o);await assert.rejects(f.bridge.proposeOutcome(scope(),o));assert.equal(f.calls.length,0);
});
for(const[name,mutate]of [
  ['foreign context',r=>{r.context.project.id=ids[8];}],['soft canon',r=>{r.context.advisoryMemory[0].canonStatus='soft_canon';}],
  ['grant escalation',r=>{r.context.authorization.retrievalDoesNotGrantExecutionAuthority=false;}],
  ['advisory authority',r=>{r.context.advisoryMemory[0].authorizationEffect='allow';}],
  ['wrong principal',r=>{r.context.authorization.principalKey='other';}],
  ['wrong task',r=>{r.context.task.intent='travel';}],['unsupported shape',r=>{r.context.policyMemory={};}]
])test('context rejects '+name,async()=>{
  const f=await fixture(async(n,a,server)=>{const r=await server(n,a);mutate(r.data);return r;});
  await assert.rejects(f.bridge.getTaskContext(scope(),query()));
});
test('degraded context stays degraded',async()=>{
  const f=await fixture(async(n,a,server)=>{const r=await server(n,a);r.data.context.degradation.degraded=true;return r;});
  assert.equal((await f.bridge.getTaskContext(scope(),query())).state,'degraded');
});
test('pre-cancelled task does not call Memory',async()=>{
  const f=await fixture(),c=new AbortController();c.abort();
  await assert.rejects(f.bridge.proposeOutcome(scope(),outcome(),{signal:c.signal}),{code:'OPS_MEMORY_CANCELLED'});assert.equal(f.calls.length,0);
});
test('deadline is bounded and never starts a second write',async()=>{
  const f=await fixture((n,a,server)=>a.p_operation==='propose_outcome'?new Promise(()=>{}):server(n,a),{timeoutMs:100});
  const r=await f.bridge.proposeOutcome(scope(),outcome());assert.equal(r.state,'reconciliation_required');assert.equal(f.calls.length,2);
});
test('receipt drift prevents delivery acknowledgement',async()=>{
  const f=await fixture(async(n,a,server)=>{const r=await server(n,a);if(a.p_operation==='readback')r.data.candidateId=ids[5];return r;});
  const r=await f.bridge.proposeOutcome(scope(),outcome());assert.equal(r.deliveryVerified,false);assert.equal(r.reason,'OPS_MEMORY_RECEIPT_DRIFT');
});
