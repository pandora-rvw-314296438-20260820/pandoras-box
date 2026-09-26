import {InferenceError, bounded, demand, record, UUID} from './policy.mjs';
export const BOX_PROJECT_REF='jcyqixttuebxqqfkjonq';
export async function boundedCall(start,{signal,timeoutMs=15000,mutation=false}={}){
 if(signal?.aborted)throw new InferenceError('INFERENCE_CANCELLED');
 const controller=new AbortController();let timer,cancel;
 const stop=new Promise((_,reject)=>{cancel=()=>{controller.abort();reject(new InferenceError('INFERENCE_CANCELLED',{outcomeUnknown:mutation}));};signal?.addEventListener('abort',cancel,{once:true});timer=setTimeout(()=>{controller.abort();reject(new InferenceError('INFERENCE_TIMEOUT',{outcomeUnknown:mutation}));},timeoutMs);});
 try{return await Promise.race([Promise.resolve().then(()=>start(controller.signal)),stop]);}
 finally{clearTimeout(timer);signal?.removeEventListener('abort',cancel);}
}
/** Fixed native RPCs only. The supplied client belongs to the server credential holder. */
export class NativeInferenceStore{
 #client;
 constructor(client){let url;try{url=new URL(client.supabaseUrl);}catch{throw new InferenceError('INFERENCE_STORE_TARGET_DENIED');}
  demand(url.origin===`https://${BOX_PROJECT_REF}.supabase.co`&&url.pathname==='/'&&!url.search&&!url.hash&&!url.username&&!url.password&&typeof client.rpc==='function','INFERENCE_STORE_TARGET_DENIED');this.#client=client;this.durability='durable';}
 async #rpc(name,args,{signal,mutation=false}={}){
  bounded(args,131072);
  try{return await boundedCall(async inner=>{let pending=this.#client.rpc(name,args);if(typeof pending?.abortSignal==='function')pending=pending.abortSignal(inner);const response=await pending;
   if(response?.error){const code=response.error.message;if(typeof code==='string'&&/^(INFERENCE|OPS_EVENT)_[A-Z0-9_]{1,100}$/.test(code))throw new InferenceError(code);
    throw new InferenceError(response.error.code==='42501'?'INFERENCE_ACCESS_DENIED':'INFERENCE_STORE_REJECTED');}
   demand(record(response?.data),'INFERENCE_STORE_RESPONSE_INVALID');bounded(response.data,262144);return response.data;
  },{signal,mutation});}catch(error){if(error instanceof InferenceError)throw error;throw new InferenceError('INFERENCE_STORE_UNAVAILABLE',{outcomeUnknown:mutation});}
 }
 authenticate(digest,options){return this.#rpc('pandora_ops_inference_authenticate_v1',{p_digest:digest},options);}
 transition(operation,actor,payload,options={}){
  demand(['context','admit','prepare','send','record','billing','verify','status','cancel'].includes(operation),'INFERENCE_OPERATION_DENIED');
  return this.#rpc('pandora_ops_inference_transition_v1',{p_operation:operation,p_actor:actor,p_payload:payload},{...options,mutation:!['context','status'].includes(operation)});
 }
 context(actor,metadata,options){return this.transition('context',actor,metadata,options);}
 admit(actor,metadata,options){return this.transition('admit',actor,metadata,options);}
 status(actor,requestId,options){demand(UUID.test(requestId),'INFERENCE_IDENTITY_INVALID');return this.transition('status',actor,{requestId},options);}
 prepare(actor,requestId,modelKey,policyDigest,options){return this.transition('prepare',actor,{requestId,modelKey,policyDigest},options);}
 send(actor,requestId,attemptId,policyDigest,options){return this.transition('send',actor,{requestId,attemptId,policyDigest},options);}
 record(actor,requestId,attemptId,receipt,options){return this.transition('record',actor,{requestId,attemptId,receipt},options);}
 verify(actor,requestId,verificationRunId,options){return this.transition('verify',actor,{requestId,verificationRunId},options);}
 cancel(actor,requestId,options){return this.transition('cancel',actor,{requestId},options);}
 events({organizationId,projectId,userId,after='0',limit=100},options){return this.#rpc('pandora_ops_event_feed_v1',{p_organization_id:organizationId,p_project_id:projectId,p_actor_id:userId,p_after:after,p_limit:limit},options);}
}
