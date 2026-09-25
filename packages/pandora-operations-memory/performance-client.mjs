import {randomUUID} from 'node:crypto';
import {MEMORY_PROJECT_REF, MemoryIntegrationError, UUID, SHA256, exact, immutable,
  isRecord, normalizeMapping, normalizeScope, requireThat, serialized, stableDigest} from './contracts.mjs';

export const PERFORMANCE_RPC = 'memory_operations_performance_v1';
export const PERFORMANCE_CONTRACT = 'pandora-operations-performance-v1';
export const PERFORMANCE_CLASSES = Object.freeze(['deep_reasoning','complex_coding','fast_coding',
  'vision','long_context','research','structured_extraction','local_private','cheap_bulk','independent_verification']);
const ID = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,179}$/;
const REF = /^[A-Za-z0-9][A-Za-z0-9:./_?#=&%-]{0,499}$/;
const TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/;
const count = n => Number.isSafeInteger(n) && n >= 0;
const timestamp = value => typeof value === 'string' && TIME.test(value) && Number.isFinite(Date.parse(value));
const identity = value => typeof value === 'string' && ID.test(value);
const provider = value => typeof value === 'string' && /^[a-z][a-z0-9._-]{0,119}$/.test(value);
function request(raw) {
  exact(raw,['taskClass','provider','model','modelRevision','configurationDigest','maxRecords'],['taskClass']);
  const q={provider:null,model:null,modelRevision:null,configurationDigest:null,maxRecords:16,...structuredClone(raw)};
  requireThat(PERFORMANCE_CLASSES.includes(q.taskClass),'OPS_MEMORY_PERFORMANCE_CLASS_INVALID');
  requireThat(q.provider===null || provider(q.provider),'OPS_MEMORY_PERFORMANCE_FILTER_INVALID');
  for(const k of ['model','modelRevision']) requireThat(q[k]===null || identity(q[k]),'OPS_MEMORY_PERFORMANCE_FILTER_INVALID');
  requireThat(q.configurationDigest===null || (typeof q.configurationDigest==='string' && SHA256.test(q.configurationDigest)),
    'OPS_MEMORY_PERFORMANCE_FILTER_INVALID');
  requireThat(count(q.maxRecords) && q.maxRecords>=1 && q.maxRecords<=16,'OPS_MEMORY_PERFORMANCE_LIMIT_INVALID');
  serialized(q); return immutable({...q,requestId:randomUUID()});
}
const fail = code => {throw new MemoryIntegrationError(code);};
const ROW_FIELDS = ['memoryItemId','recordType','canonStatus','recordDigest','provider','model','modelRevision',
  'modelRevisionKnown','configurationDigest','configurationKnown','taskClass','sampleCount','verificationPassCount',
  'negativeOutcomeCount','qualitySignal','meanLatencyMs','estimatedWindowCostMicros','billedWindowCostMicros',
  'evidenceWindowStart','evidenceWindowEnd','reviewDueAt','approvedAt','sourceRunCount','sourceRunsDigest',
  'evidenceRefs','evidenceRefCount','evidenceDigest'];
function validateRow(row,q,asOf,now) {
  exact(row,ROW_FIELDS); requireThat(typeof row.memoryItemId==='string' && UUID.test(row.memoryItemId) && row.recordType==='provider_performance'
    && row.canonStatus==='hard_canon' && typeof row.recordDigest==='string' && SHA256.test(row.recordDigest),'OPS_MEMORY_PERFORMANCE_RECORD_INVALID');
  requireThat(provider(row.provider) && identity(row.model) && (row.modelRevision===null || identity(row.modelRevision))
    && row.taskClass===q.taskClass,'OPS_MEMORY_PERFORMANCE_IDENTITY_INVALID');
  requireThat((row.configurationDigest===null || (typeof row.configurationDigest==='string' && SHA256.test(row.configurationDigest)))
    && row.configurationKnown===(row.configurationDigest!==null)
    && row.modelRevisionKnown===(row.modelRevision!==null && row.modelRevision!=='unreported'),'OPS_MEMORY_PERFORMANCE_UNKNOWN_INVALID');
  for(const k of ['provider','model','modelRevision','configurationDigest']) {
    requireThat(q[k]===null || q[k]===row[k],'OPS_MEMORY_PERFORMANCE_FILTER_MISMATCH');
  }
  requireThat(count(row.sampleCount) && row.sampleCount>0 && count(row.verificationPassCount)
    && row.verificationPassCount<=row.sampleCount && count(row.negativeOutcomeCount)
    && row.negativeOutcomeCount<=row.sampleCount && row.sourceRunCount===row.sampleCount
    && typeof row.sourceRunsDigest==='string' && SHA256.test(row.sourceRunsDigest),'OPS_MEMORY_PERFORMANCE_COUNTS_INVALID');
  requireThat(row.qualitySignal===null || (typeof row.qualitySignal==='number' && Number.isFinite(row.qualitySignal)
    && row.qualitySignal>=0 && row.qualitySignal<=1),'OPS_MEMORY_PERFORMANCE_QUALITY_INVALID');
  for(const k of ['meanLatencyMs','estimatedWindowCostMicros','billedWindowCostMicros']) {
    requireThat(row[k]===null || count(row[k]),'OPS_MEMORY_PERFORMANCE_METRIC_INVALID');
  }
  const fields=['evidenceWindowStart','evidenceWindowEnd','reviewDueAt','approvedAt'];
  requireThat(fields.every(k=>timestamp(row[k])),'OPS_MEMORY_PERFORMANCE_TIME_INVALID');
  const [start,end,due,approved]=fields.map(k=>Date.parse(row[k]));
  requireThat(start<=end && end<=approved && approved<=asOf && due>asOf && due>now,
    'OPS_MEMORY_PERFORMANCE_STALE');
  requireThat(Array.isArray(row.evidenceRefs) && count(row.evidenceRefCount) && row.evidenceRefCount>=1
    && row.evidenceRefCount<=200 && row.evidenceRefs.length===Math.min(4,row.evidenceRefCount)
    && new Set(row.evidenceRefs).size===row.evidenceRefs.length
    && row.evidenceRefs.every(x=>typeof x==='string' && REF.test(x)) && typeof row.evidenceDigest==='string' && SHA256.test(row.evidenceDigest),
    'OPS_MEMORY_PERFORMANCE_EVIDENCE_INVALID');
}
function validateReply(reply,q,mapping,now) {
  exact(reply,['schemaVersion','requestId','projectId','namespace','principalKey','environment','taskClass',
    'requested','observedAt','state','records','statistics','truncated','aggregation','summingSamplesAllowed',
    'authorizationGranted','providerApprovalGranted']);
  serialized(reply,32768);
  requireThat(reply.schemaVersion===PERFORMANCE_CONTRACT && reply.requestId===q.requestId
    && reply.projectId===mapping.memoryProjectId && reply.namespace===mapping.namespace
    && reply.principalKey===mapping.principalKey && reply.environment===mapping.environment
    && reply.taskClass===q.taskClass,'OPS_MEMORY_PERFORMANCE_SCOPE_MISMATCH');
  const {requestId,taskClass,...filters}=q;
  exact(reply.requested,Object.keys(filters));
  requireThat(Object.keys(filters).every(k=>reply.requested[k]===filters[k]),'OPS_MEMORY_PERFORMANCE_REQUEST_MISMATCH');
  requireThat(reply.authorizationGranted===false && reply.providerApprovalGranted===false
    && reply.summingSamplesAllowed===false && reply.aggregation==='latest_snapshot_per_model_revision_configuration',
    'OPS_MEMORY_PERFORMANCE_AUTHORITY_INVALID');
  requireThat(timestamp(reply.observedAt) && Number.isFinite(now),'OPS_MEMORY_PERFORMANCE_TIME_INVALID');
  const asOf=Date.parse(reply.observedAt);
  requireThat(asOf<=now+30000 && now-asOf<=60000,'OPS_MEMORY_PERFORMANCE_STALE');
  requireThat(Array.isArray(reply.records) && reply.records.length<=q.maxRecords && typeof reply.truncated==='boolean',
    'OPS_MEMORY_PERFORMANCE_RESPONSE_INVALID');
  exact(reply.statistics,['scannedRecords','invalidRecords','eligibleSnapshots']);
  const s=reply.statistics;
  requireThat(Object.values(s).every(count) && s.scannedRecords<=128 && s.invalidRecords<=s.scannedRecords
    && s.eligibleSnapshots<=s.scannedRecords-s.invalidRecords && reply.records.length<=s.eligibleSnapshots
    && (reply.truncated || reply.records.length===s.eligibleSnapshots),'OPS_MEMORY_PERFORMANCE_STATISTICS_INVALID');
  requireThat(reply.state===(reply.records.length ? 'available':'insufficient_history'),'OPS_MEMORY_PERFORMANCE_STATE_INVALID');
  const keys=new Set();
  for(const row of reply.records) {
    validateRow(row,q,asOf,now);
    const key=JSON.stringify([row.provider,row.model,row.modelRevision,row.configurationDigest,row.taskClass]);
    requireThat(!keys.has(key),'OPS_MEMORY_PERFORMANCE_OVERLAPPING_SNAPSHOTS'); keys.add(key);
  }
  return immutable({...structuredClone(reply),receiptRef:`memory-performance:${reply.requestId}`,
    transportSha256:stableDigest(reply)});
}
/** Server-only read of approved performance snapshots. Never selects or approves a provider.
 * Client credentials remain with the trusted holder; this module has no mutation method.
 */
export class NativeOperationsPerformanceClient {
  #client; #mapping; #timeoutMs; #clock;
  constructor({client,mapping,timeoutMs=15000,clock=Date.now}) {
    requireThat(typeof client?.rpc==='function','OPS_MEMORY_CLIENT_REQUIRED');
    this.#client=client; this.#target(); this.#mapping=normalizeMapping(mapping);
    requireThat(Number.isSafeInteger(timeoutMs) && timeoutMs>=100 && timeoutMs<=30000 && typeof clock==='function',
      'OPS_MEMORY_RUNTIME_OPTIONS_INVALID');
    this.#timeoutMs=timeoutMs; this.#clock=clock;
  }
  #target() {
    let url; try {url=new URL(this.#client.supabaseUrl);} catch {fail('OPS_MEMORY_CLIENT_TARGET_INVALID');}
    requireThat(url.origin===`https://${MEMORY_PROJECT_REF}.supabase.co` && url.pathname==='/'
      && !url.search && !url.hash && !url.username && !url.password,'OPS_MEMORY_CLIENT_TARGET_DENIED');
  }
  async getPerformance(scope,raw,{signal}={}) {
    normalizeScope(scope,this.#mapping); const q=request(raw); this.#target();
    requireThat(signal===undefined || (typeof signal?.aborted==='boolean'
      && typeof signal.addEventListener==='function' && typeof signal.removeEventListener==='function'),
      'OPS_MEMORY_SIGNAL_INVALID');
    if(signal?.aborted) fail('OPS_MEMORY_CANCELLED');
    const m=this.#mapping, controller=new AbortController(); let timer,cancel;
    const args=immutable({p_memory_user_id:m.memoryUserId,p_namespace:m.namespace,p_project_id:m.memoryProjectId,
      p_principal_key:m.principalKey,p_environment:m.environment,p_request:q});
    const stop=new Promise((_,reject)=>{
      cancel=()=>{controller.abort();reject(new MemoryIntegrationError('OPS_MEMORY_CANCELLED'));};
      signal?.addEventListener('abort',cancel,{once:true});
      timer=setTimeout(()=>{controller.abort();reject(new MemoryIntegrationError('OPS_MEMORY_TIMEOUT'));},this.#timeoutMs);
    });
    try {
      let pending=this.#client.rpc(PERFORMANCE_RPC,args);
      if(typeof pending?.abortSignal==='function') pending=pending.abortSignal(controller.signal);
      const response=await Promise.race([Promise.resolve(pending),stop]); this.#target();
      if(response?.error) {
        const code=response.error.message;
        if(typeof code==='string' && /^OPS_MEMORY_[A-Z0-9_]{1,100}$/.test(code)) fail(code);
        if(response.error.code==='42501') fail('OPS_MEMORY_ACCESS_DENIED');
        fail('OPS_MEMORY_PROVIDER_ERROR');
      }
      requireThat(isRecord(response?.data),'OPS_MEMORY_PERFORMANCE_RESPONSE_INVALID');
      return validateReply(response.data,q,m,this.#clock());
    } catch(error) {
      if(error instanceof MemoryIntegrationError) throw error;
      throw new MemoryIntegrationError('OPS_MEMORY_TRANSPORT_UNAVAILABLE');
    } finally {
      clearTimeout(timer); signal?.removeEventListener('abort',cancel);
    }
  }
}
