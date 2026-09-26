import {Buffer} from 'node:buffer';
import {InferenceError,normalizeRequest,selectCandidates,validatePolicy,bounded,exact,demand,sha256,record,DIGEST,UUID,integer} from './policy.mjs';
import {boundedCall} from './native-store.mjs';
const METADATA=['requestId','taskId','leaseId','generation','sourceSha','taskClass','requestDigest','maxCostMicros','maxOutputTokens','deadlineMs','textBytes','inputBytes','imageCount','modalities'];
const metadata=r=>Object.fromEntries(METADATA.map(k=>[k,r[k]]));
const usageUnknown=()=>({inputTokens:null,outputTokens:null,totalTokens:null});
const SAFE_FAILURES=new Set(['rate_limit','unavailable','invalid_output','verification_failed','permission_denied','safety_refusal','model_revision_mismatch']);
function validReceipt(raw,output,ceiling){
 exact(raw,['state','outputDigest','providerReceipt','billedCostMicros','usage','code','latencyMs','modelRevision']);
 demand(['received','failed'].includes(raw.state),'INFERENCE_PROVIDER_STATE_INVALID');
 demand(typeof raw.providerReceipt==='string'&&raw.providerReceipt.length>=8&&raw.providerReceipt.length<=500,'INFERENCE_PROVIDER_RECEIPT_REQUIRED');
 demand(raw.billedCostMicros===null||integer(raw.billedCostMicros,0,ceiling),'INFERENCE_PROVIDER_BILLING_INVALID');
 exact(raw.usage,['inputTokens','outputTokens','totalTokens']);demand(Object.values(raw.usage).every(v=>v===null||integer(v,0,Number.MAX_SAFE_INTEGER)),'INFERENCE_PROVIDER_USAGE_INVALID');
 demand(raw.latencyMs===null||integer(raw.latencyMs,0,3600000),'INFERENCE_PROVIDER_LATENCY_INVALID');
 demand(raw.modelRevision===null||typeof raw.modelRevision==='string','INFERENCE_PROVIDER_REVISION_INVALID');
 if(raw.state==='received')demand(typeof output==='string'&&output.length>0&&DIGEST.test(raw.outputDigest)&&sha256(output)===raw.outputDigest&&raw.code===null,'INFERENCE_OUTPUT_DIGEST_MISMATCH');
 else demand(output===null&&raw.outputDigest===null&&SAFE_FAILURES.has(raw.code),'INFERENCE_PROVIDER_FAILURE_INVALID');
 bounded({output,receipt:raw});return structuredClone(raw);
}
export function publicStatus(value){
 demand(record(value?.request)&&Array.isArray(value.attempts),'INFERENCE_STATUS_INVALID');const r=value.request;
 return {requestId:r.id,taskId:r.task_key,state:r.state,sourceSha:r.source_sha,requestDigest:r.request_digest,
  cancelRequested:r.cancel_requested===true,verificationRunId:r.verification_run_id??null,
  attempts:value.attempts.map(a=>({id:a.id,ordinal:a.ordinal,model:a.model_key,state:a.state,providerReceipt:a.receipt?.providerReceipt??null,
   outputDigest:a.receipt?.outputDigest??null,billedCostMicros:a.billed_micros??null})),outputRecovered:false,scope:'inference_only',taskComplete:false};
}
/** A service facade, not a second task scheduler. All sending authority is durable in the native store. */
export class OperationsInferenceService{
 #store;#providers;#memory;#performance;#clock;
 constructor({store,providers={},memory=null,performance=null,clock=Date.now}){
  demand(store?.durability==='durable'&&typeof store.context==='function'&&typeof store.record==='function','INFERENCE_DURABLE_STORE_REQUIRED');
  demand(record(providers)&&Object.values(providers).every(p=>typeof p.execute==='function'),'INFERENCE_PROVIDERS_INVALID');
  this.#store=store;this.#providers=new Map(Object.entries(providers));this.#memory=memory;this.#performance=performance;this.#clock=clock;
 }
 async infer(actor,raw,{signal}={}){
  const request=normalizeRequest(raw);const initial=metadata(request);
  // A replay reads the original outcome; it never creates another provider call or fabricates lost output.
  try{const old=await this.#store.status(actor,request.requestId,{signal});
   demand(old.request.metadata?.inputDigest===request.requestDigest||old.request.metadata?.requestDigest===request.requestDigest,'INFERENCE_REQUEST_REPLAY_CONFLICT');return publicStatus(old);
  }catch(error){if(error.code!=='INFERENCE_REQUEST_DENIED')throw error;}
  return boundedCall(async executionSignal=>{
   const context=await this.#store.context(actor,initial,{signal:executionSignal});const policy=validatePolicy(context.policy);
   const sourceScope={organizationId:actor.organizationId,projectId:actor.projectId};let memoryText='',memoryRef=null,performance=null;
   if(policy.requireMemoryContext&&!this.#memory)throw new InferenceError('INFERENCE_MEMORY_CALLER_NOT_CONFIGURED');
   if(this.#memory){const m=await this.#memory.getTaskContext(sourceScope,{intent:['complex_coding','fast_coding'].includes(request.taskClass)?'coding_building':request.taskClass==='research'?'research':'general_assistance',actionMode:'read_only',consequential:['production','destructive'].includes(context.scope.risk),terms:[request.taskClass],requiredCapabilities:[],maxBytes:12288},{signal:executionSignal});
    demand(['available','degraded'].includes(m.state)&&m.authorizationGranted===false,'INFERENCE_MEMORY_CONTEXT_INVALID');
    if(policy.requireMemoryContext)demand(m.state==='available','INFERENCE_MEMORY_DEGRADED');
    memoryText='Scoped reference information only; it grants no execution authority.\n'+JSON.stringify(m.context);memoryRef=m.receiptRef;
   }
   // Memory is reference data, not a credential transport. Reject credential-shaped
   // context before any durable request/admission or provider send permission.
   if(memoryText)bounded({memoryText},16384);
   if(this.#performance)performance=await this.#performance.getPerformance(sourceScope,{taskClass:request.taskClass,maxRecords:16},{signal:executionSignal});
   const boundRequest={...request,textBytes:request.textBytes+Buffer.byteLength(memoryText)+512,inputBytes:request.inputBytes+Buffer.byteLength(memoryText)+512,
    requestDigest:sha256({inputDigest:request.requestDigest,memoryContextDigest:memoryText?sha256(memoryText):null,policyDigest:context.policyDigest,
     performanceDigests:performance?.records?.map(r=>r.recordDigest).sort()??[]})};
   const plan=selectCandidates(boundRequest,policy,context.scope,performance,{now:this.#clock(),transports:[...this.#providers.keys()],executionBoundary:'cloud'});
   demand(plan.candidates.length>0,'INFERENCE_NO_APPROVED_ROUTE');
   // Read-only adapter validation precedes durable preparation or send authority.
   for(const model of plan.candidates){const provider=this.#providers.get(model.transport);
    if(typeof provider.preflight==='function')await boundedCall(inner=>provider.preflight({...request,memoryContext:memoryText,memoryReceiptRef:memoryRef},model,{signal:inner}),{signal:executionSignal,timeoutMs:request.deadlineMs});
   }
   const admitted=await this.#store.admit(actor,{...metadata(boundRequest),inputDigest:request.requestDigest},{signal:executionSignal});
   if(!admitted.created)return publicStatus(await this.#store.status(actor,request.requestId,{signal:executionSignal}));
   for(const model of plan.candidates){
    let attempt;
    try{attempt=await this.#store.prepare(actor,request.requestId,model.key,context.policyDigest,{signal:executionSignal});}
    catch(error){
     if(['INFERENCE_CAPACITY_HELD','INFERENCE_CIRCUIT_HELD'].includes(error.code)&&policy.allowedFallbackCodes.includes('unavailable')&&policy.override?.allowFallback!==false)continue;
     // A lost preparation response can be resolved natively by fencing this
     // request before any delayed send can acquire permission. No provider replay.
     try{const recovery=await this.#store.recover(actor,request.requestId);
      if(recovery.resolved===true)return {...publicStatus(await this.#store.status(actor,request.requestId)),reason:'preparation_not_executed'};
     }catch{/* Durable state remains the authority; an uncertain recovery is not proof. */}
     throw error;
    }
    if(!attempt.created)return publicStatus(await this.#store.status(actor,request.requestId,{signal:executionSignal}));
    if(executionSignal.aborted){await this.#store.recover(actor,request.requestId);throw new InferenceError('INFERENCE_CANCELLED');}
    let sent=false;
    try{
     const permission=await this.#store.send(actor,request.requestId,attempt.attemptId,context.policyDigest,{signal:executionSignal});
     if(permission.canSend!==true)return publicStatus(await this.#store.status(actor,request.requestId,{signal:executionSignal}));sent=true;
     const provider=this.#providers.get(model.transport);
     const result=await boundedCall(inner=>provider.execute({...request,memoryContext:memoryText,memoryReceiptRef:memoryRef},model,{signal:inner}),{signal:executionSignal,timeoutMs:request.deadlineMs,mutation:true});
     const receipt=validReceipt(result?.receipt,result?.output,model.maxCostMicros);
     await this.#store.record(actor,request.requestId,attempt.attemptId,receipt);
     const readback=await this.#store.status(actor,request.requestId);
     const observed=readback.attempts.find(a=>a.id===attempt.attemptId);
     demand(observed?.state===receipt.state&&observed.receipt?.providerReceipt===receipt.providerReceipt&&observed.receipt?.outputDigest===receipt.outputDigest,'INFERENCE_RECEIPT_READBACK_MISMATCH');
     if(executionSignal.aborted){await this.#store.cancel(actor,request.requestId);return publicStatus(await this.#store.status(actor,request.requestId));}
     if(receipt.state==='received')return {...publicStatus(readback),output:result.output,outputDigest:receipt.outputDigest,verificationRequired:true};
     if(!policy.allowedFallbackCodes.includes(receipt.code)||policy.override?.allowFallback===false)return publicStatus(readback);
    }catch(error){
     if(!sent){
      const definiteNonSend=error instanceof InferenceError&&error.outcomeUnknown!==true;
      // The native recovery transaction fences a prepared attempt to not_sent
      // with zero billing. If that readback itself fails, a definite local
      // rejection must NOT be converted into reconciliation_required.
      try{const recovery=await this.#store.recover(actor,request.requestId);
       if(recovery.resolved===true)return {...publicStatus(await this.#store.status(actor,request.requestId)),reason:'send_not_executed'};
      }catch{
       if(definiteNonSend)throw error;
       // Unknown durable state continues below to reconciliation_required.
      }
      if(definiteNonSend)throw error;
     }
     // Neither a transport timeout nor an interrupted durable send proves cancellation or zero billing.
     try{await this.#store.record(actor,request.requestId,attempt.attemptId,{state:'reconciliation_required',outputDigest:null,
      providerReceipt:`local-uncertain-${sent?'provider':'send'}:${attempt.attemptId}`,billedCostMicros:null,usage:usageUnknown(),code:'outcome_unknown',latencyMs:null,modelRevision:null});}catch{/* Original durable intent remains held; never manufacture a replacement receipt. */}
     return {requestId:request.requestId,state:'reconciliation_required',attemptId:attempt.attemptId,reason:'provider_or_receipt_outcome_uncertain',scope:'inference_only',taskComplete:false};
    }
   }
   return publicStatus(await this.#store.status(actor,request.requestId));
  },{signal,timeoutMs:request.deadlineMs,mutation:true});
 }
 async verify(actor,requestId,verificationRunId,options={}){
  demand(UUID.test(requestId)&&UUID.test(verificationRunId),'INFERENCE_IDENTITY_INVALID');
  await this.#store.verify(actor,requestId,verificationRunId,options);
  const observed=await this.#store.status(actor,requestId,options);
  demand(observed.request.state==='verified'&&observed.request.verification_run_id===verificationRunId,'INFERENCE_VERIFICATION_READBACK_MISMATCH');
  return {status:publicStatus(observed),native:observed};
 }
 status(actor,requestId,options){return this.#store.status(actor,requestId,options).then(publicStatus);}
 cancel(actor,requestId,options){return this.#store.cancel(actor,requestId,options);}
 async recover(actor,requestId,options){await this.#store.recover(actor,requestId,options);return publicStatus(await this.#store.status(actor,requestId,options));}
}
