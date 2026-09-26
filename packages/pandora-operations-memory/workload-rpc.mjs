
import {randomUUID} from 'node:crypto';
import {BRIDGE_RPC,MEMORY_PROJECT_REF,MemoryIntegrationError,normalizeMapping,exact,isRecord,serialized,requireThat} from './contracts.mjs';
import {NativeOperationsMemoryClient} from './native-client.mjs';
import {NativeOperationsPerformanceClient,PERFORMANCE_RPC} from './performance-client.mjs';
const ENDPOINT=`https://${MEMORY_PROJECT_REF}.supabase.co/functions/v1/pandora-memory-bridge`;
const error=(code,unknown=false)=>new MemoryIntegrationError(code,{outcomeUnknown:unknown});
async function boundedBody(response,signal) {
  const declared=response.headers.get('content-length');
  requireThat(declared===null || (/^[0-9]+$/.test(declared)&&Number(declared)<=48000),'OPS_MEMORY_RESPONSE_INVALID');
  requireThat(response.body?.getReader,'OPS_MEMORY_RESPONSE_INVALID');
  const reader=response.body.getReader();let bytes=0,text='';const decoder=new TextDecoder('utf-8',{fatal:true});
  const cancel=()=>{Promise.resolve(reader.cancel()).catch(()=>{});};
  signal.addEventListener('abort',cancel,{once:true});
  try {
    while(true){if(signal.aborted)throw error('OPS_MEMORY_CANCELLED');const chunk=await reader.read();if(chunk.done)break;
      bytes+=chunk.value.byteLength;if(bytes>48000){cancel();throw error('OPS_MEMORY_RESPONSE_INVALID');}text+=decoder.decode(chunk.value,{stream:true});}
    text+=decoder.decode();const value=JSON.parse(text);requireThat(isRecord(value),'OPS_MEMORY_RESPONSE_INVALID');return value;
  } finally {signal.removeEventListener('abort',cancel);try{reader.releaseLock();}catch{}}
}
/** RPC-compatible transport over the existing native Memory bridge. No Memory service key is copied. */
export class WorkloadOperationsMemoryRpc {
  #mapping;#resolve;#fetch;#timeout;
  constructor({mapping,resolveWorkloadToken,fetchFn=globalThis.fetch,timeoutMs=14000}) {
    this.#mapping=normalizeMapping(mapping);requireThat(typeof resolveWorkloadToken==='function'&&typeof fetchFn==='function','OPS_MEMORY_WORKLOAD_CONFIGURATION_REQUIRED');
    requireThat(this.#mapping.principalKey==='pandora-mcpmaster-production'&&this.#mapping.environment==='production','OPS_MEMORY_WORKLOAD_PRINCIPAL_DENIED');
    requireThat(Number.isSafeInteger(timeoutMs)&&timeoutMs>=1&&timeoutMs<=28000,'OPS_MEMORY_RUNTIME_OPTIONS_INVALID');
    this.#resolve=resolveWorkloadToken;this.#fetch=fetchFn;this.#timeout=timeoutMs;
    Object.defineProperty(this,'supabaseUrl',{value:`https://${MEMORY_PROJECT_REF}.supabase.co`,writable:false,configurable:false,enumerable:true});
  }
  rpc(name,args) {
    const m=this.#mapping;requireThat([BRIDGE_RPC,PERFORMANCE_RPC].includes(name),'OPS_MEMORY_RPC_DENIED');
    const performance=name===PERFORMANCE_RPC;
    exact(args,['p_memory_user_id','p_namespace','p_project_id','p_principal_key','p_environment',...(performance?['p_request']:['p_operation','p_payload'])]);
    requireThat(args.p_memory_user_id===m.memoryUserId&&args.p_namespace===m.namespace&&args.p_project_id===m.memoryProjectId
      &&args.p_principal_key===m.principalKey&&args.p_environment===m.environment,'OPS_MEMORY_MAPPING_MISMATCH');
    const operation=performance?'performance':args.p_operation;
    requireThat(['context','performance','propose_outcome','readback'].includes(operation),'OPS_MEMORY_OPERATION_DENIED');
    const payload=structuredClone(performance?args.p_request:args.p_payload);requireThat(isRecord(payload),'OPS_MEMORY_FIELDS_INVALID');serialized(payload);
    const body=Object.freeze({action:'operations',operation,requestId:randomUUID(),projectId:m.memoryProjectId,namespace:m.namespace,payload});
    let signal,pending;const start=()=>pending??=(this.#send(body,signal));
    const request={abortSignal(value){requireThat(!pending,'OPS_MEMORY_SIGNAL_AFTER_SEND');signal=value;return request;},
      then(resolve,reject){return start().then(resolve,reject);}};
    return request;
  }
  async #send(body,signal) {
    const mutation=body.operation==='propose_outcome';if(signal?.aborted)throw error('OPS_MEMORY_CANCELLED');
    const controller=new AbortController();let timer,cancel,sent=false;
    const stopped=new Promise((_,reject)=>{
      cancel=()=>{controller.abort();reject(error('OPS_MEMORY_CANCELLED',mutation&&sent));};signal?.addEventListener('abort',cancel,{once:true});
      timer=setTimeout(()=>{controller.abort();reject(error('OPS_MEMORY_TIMEOUT',mutation&&sent));},this.#timeout);
    });
    try {
      return await Promise.race([(async()=>{
        const token=await this.#resolve();
        requireThat(typeof token==='string'&&token.length>=64&&token.length<=8192&&/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token),'OPS_MEMORY_WORKLOAD_IDENTITY_UNAVAILABLE');
        if(controller.signal.aborted)throw error('OPS_MEMORY_CANCELLED');
        sent=true;
        const response=await this.#fetch(ENDPOINT,{method:'POST',headers:{'x-pandora-vercel-oidc':token,'content-type':'application/json','accept':'application/json'},
          body:JSON.stringify(body),redirect:'error',signal:controller.signal});
        const envelope=await boundedBody(response,controller.signal);
        if(!response.ok || envelope.ok!==true){
          const definite=envelope.outcomeUnknown===false&&[400,401,403,409,422].includes(response.status);
          const code=/^OPS_MEMORY_[A-Z0-9_]{1,100}$/.test(envelope.error||'')?envelope.error:'OPS_MEMORY_PROVIDER_REJECTED';
          throw error(code,mutation&&!definite);
        }
        requireThat(envelope.requestId===body.requestId&&envelope.operation===body.operation&&envelope.projectId===body.projectId
          &&envelope.namespace===body.namespace&&envelope.memoryProjectRef===MEMORY_PROJECT_REF&&isRecord(envelope.data),'OPS_MEMORY_WORKLOAD_RECEIPT_MISMATCH');
        serialized(envelope.data,40000);return {data:envelope.data,error:null};
      })(),stopped]);
    } catch(cause) {
      if(cause instanceof MemoryIntegrationError){
        if(mutation&&sent&&['OPS_MEMORY_WORKLOAD_RECEIPT_MISMATCH','OPS_MEMORY_RESPONSE_INVALID','OPS_MEMORY_PAYLOAD_LIMIT','OPS_MEMORY_CREDENTIAL_REJECTED'].includes(cause.code))throw error(cause.code,true);
        throw cause;
      }
      throw error('OPS_MEMORY_WORKLOAD_TRANSPORT_UNAVAILABLE',mutation&&sent);
    } finally {clearTimeout(timer);signal?.removeEventListener('abort',cancel);}
  }
}
export function createWorkloadOperationsMemory(options) {
  const client=new WorkloadOperationsMemoryRpc(options);
  const context=new NativeOperationsMemoryClient({client,mapping:options.mapping});
  const performance=new NativeOperationsPerformanceClient({client,mapping:options.mapping});
  return Object.freeze({getTaskContext:context.getTaskContext.bind(context),getPerformance:performance.getPerformance.bind(performance),
    proposeOutcome:context.proposeOutcome.bind(context),reconcileOutcome:context.reconcileOutcome.bind(context)});
}
