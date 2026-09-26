
import {NativeInferenceStore,boundedCall} from './native-store.mjs';
import {OperationsInferenceService} from './service.mjs';
import {GeminiNativeProvider} from './gemini-native.mjs';
import {createInferenceHandler} from './http-handler.mjs';
import {InferenceError,UUID,record,demand} from './policy.mjs';
import {createWorkloadOperationsMemory} from '../pandora-operations-memory/workload-rpc.mjs';
import {OPERATIONS_MEMORY_MAPPING} from '../pandora-operations-memory/owner-read.mjs';
const BOX='https://jcyqixttuebxqqfkjonq.supabase.co';
const RPCS=new Set(['pandora_ops_inference_authenticate_v1','pandora_ops_inference_transition_v1','pandora_ops_event_feed_v1','pandora_worker_b_gemini_request_20260829']);
const encode=new TextEncoder();
async function json(response,signal,maxBytes=1048576){
 const declared=response.headers.get('content-length');
 demand(declared===null||(/^[0-9]+$/.test(declared)&&Number(declared)<=maxBytes),'INFERENCE_RESPONSE_LIMIT');
 demand(response.body?.getReader,'INFERENCE_RESPONSE_INVALID');
 const reader=response.body.getReader();let size=0,text='';const decoder=new TextDecoder('utf-8',{fatal:true});
 const cancel=()=>{void reader.cancel().catch(()=>{});};signal.addEventListener('abort',cancel,{once:true});
 try{while(true){if(signal.aborted)throw new InferenceError('INFERENCE_CANCELLED');const x=await reader.read();if(x.done)break;
  size+=x.value.byteLength;if(size>maxBytes){cancel();throw new InferenceError('INFERENCE_RESPONSE_LIMIT');}text+=decoder.decode(x.value,{stream:true});}
  text+=decoder.decode();const value=JSON.parse(text);demand(record(value),'INFERENCE_RESPONSE_INVALID');return value;
 }finally{signal.removeEventListener('abort',cancel);try{reader.releaseLock();}catch{}}
}
/** Server-only fixed RPC facade. Reads the existing Vercel Box credential; never copies a Memory service key. */
export class VercelInferenceRpc{
 #key;#fetch;#timeout;
 constructor({supabaseUrl,serviceRoleKey,fetchFn=globalThis.fetch,timeoutMs=15000}){
  demand(supabaseUrl===BOX&&typeof serviceRoleKey==='string'&&serviceRoleKey.length>=40&&serviceRoleKey.length<=8192,'INFERENCE_SERVER_CONFIGURATION_DENIED');
  demand(typeof fetchFn==='function'&&Number.isSafeInteger(timeoutMs)&&timeoutMs>=1&&timeoutMs<=120000,'INFERENCE_SERVER_CONFIGURATION_DENIED');
  this.#key=serviceRoleKey;this.#fetch=fetchFn;this.#timeout=timeoutMs;
  Object.defineProperty(this,'supabaseUrl',{value:BOX,writable:false,configurable:false});
 }
 rpc(name,args){
  demand(RPCS.has(name)&&record(args),'INFERENCE_RPC_DENIED');
  const body=JSON.stringify(args);demand(encode.encode(body).byteLength<=1048576,'INFERENCE_BODY_LIMIT');
  let signal,pending;
  const start=()=>pending??=boundedCall(async inner=>{
   const response=await this.#fetch(`${BOX}/rest/v1/rpc/${name}`,{method:'POST',redirect:'error',signal:inner,
    headers:{apikey:this.#key,authorization:`Bearer ${this.#key}`,'content-type':'application/json',accept:'application/json'},body});
   const data=await json(response,inner);
   return response.ok?{data,error:null}:{data:null,error:{code:typeof data.code==='string'?data.code:'HTTP_ERROR',message:typeof data.message==='string'?data.message:'INFERENCE_NATIVE_RPC_UNAVAILABLE'}};
  },{signal,timeoutMs:this.#timeout,mutation:!['pandora_ops_inference_authenticate_v1','pandora_ops_event_feed_v1'].includes(name)});
  const request={abortSignal(value){demand(!pending,'INFERENCE_LATE_SIGNAL');signal=value;return request;},then(resolve,reject){return start().then(resolve,reject);}};return request;
 }
}
export function createVercelInferenceRuntime({supabaseUrl,serviceRoleKey,publishableKey,resolveWorkloadToken,allowedOrigins=[],fetchFn=globalThis.fetch}){
 demand(supabaseUrl===BOX&&typeof publishableKey==='string'&&publishableKey.length>=20,'INFERENCE_SERVER_CONFIGURATION_DENIED');
 const client=new VercelInferenceRpc({supabaseUrl,serviceRoleKey,fetchFn,timeoutMs:120000});
 const store=new NativeInferenceStore(client);
 const memory=createWorkloadOperationsMemory({mapping:OPERATIONS_MEMORY_MAPPING,resolveWorkloadToken,fetchFn});
 const service=new OperationsInferenceService({store,providers:{gemini_rpc:new GeminiNativeProvider(client)},memory,performance:memory});
 return createInferenceHandler({store,allowedOrigins,
  serviceForActor:actor=>{
   demand(actor?.organizationId===OPERATIONS_MEMORY_MAPPING.organizationId&&actor.projectId===OPERATIONS_MEMORY_MAPPING.projectId,'INFERENCE_MEMORY_MAPPING_DENIED');
   return {service,memory};
  },
  authenticateOwner:async(jwt,{signal}={})=>{
   // The actual authentication service verifies the bearer; decoding a JWT is never authentication.
   const response=await fetchFn(`${BOX}/auth/v1/user`,{method:'GET',redirect:'error',signal,
    headers:{apikey:publishableKey,authorization:`Bearer ${jwt}`,accept:'application/json'}});
   if(!response.ok)return null;
   const user=await json(response,signal,65536);
   if(!UUID.test(user.id)||user.is_anonymous===true)return null;
   return {userId:user.id,active:true};
  },
 });
}
