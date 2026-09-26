import {InferenceError,bounded,demand,record,sha256,ID} from './policy.mjs';
import {boundedCall,BOX_PROJECT_REF} from './native-store.mjs';
const count=value=>Number.isSafeInteger(value)&&value>=0?value:null;
/** Reuse Pandora's existing Vault-backed Gemini gateway; no model names or credentials live in worker requests. */
export class GeminiNativeProvider{
 #client;#clock;
 constructor(client,{clock=Date.now}={}){demand(client?.supabaseUrl===`https://${BOX_PROJECT_REF}.supabase.co`&&typeof client.rpc==='function','INFERENCE_PROVIDER_TARGET_DENIED');this.#client=client;this.#clock=clock;}
 async execute(request,model,{signal}={}){
  demand(model.provider==='gemini'&&model.transport==='gemini_rpc'&&model.executionBoundary==='cloud'&&request.taskClass!=='local_private','INFERENCE_PROVIDER_SCOPE_DENIED');
  const parts=request.parts.map(p=>p.type==='text'?{text:p.text}:{inlineData:{mimeType:p.mimeType,data:p.data}});
  const body={contents:[{role:'user',parts}],generationConfig:{maxOutputTokens:request.maxOutputTokens}};
  if(request.memoryContext)body.systemInstruction={parts:[{text:request.memoryContext}]};
  if(request.taskClass==='structured_extraction')body.generationConfig.responseMimeType='application/json';
  bounded(body);const started=this.#clock();
  const response=await boundedCall(async inner=>{let pending=this.#client.rpc('pandora_worker_b_gemini_request_20260829',{p_model:model.model,p_body:body});if(typeof pending?.abortSignal==='function')pending=pending.abortSignal(inner);return await pending;},{signal,timeoutMs:request.deadlineMs,mutation:true});
  if(response?.error||!record(response?.data)||!Number.isInteger(response.data.status))throw new InferenceError('INFERENCE_PROVIDER_OUTCOME_UNKNOWN',{outcomeUnknown:true});
  const http=response.data.status,providerBody=response.data.body;
  demand(record(providerBody),'INFERENCE_PROVIDER_RESPONSE_INVALID');
  // Hash the actual provider body without copying provider diagnostic text into logs or Memory.
  const providerReceipt=`gemini-http-${http}-sha256:${sha256(providerBody)}`;
  const usage=providerBody.usageMetadata??{},revision=typeof providerBody.modelVersion==='string'&&ID.test(providerBody.modelVersion)?providerBody.modelVersion:null;
  let code=null,output=null;
  if(http!==200)code=http===429?'rate_limit':[401,403].includes(http)?'permission_denied':'unavailable';
  else{
   const candidate=providerBody.candidates?.[0];
   if(providerBody.promptFeedback?.blockReason||['SAFETY','PROHIBITED_CONTENT','BLOCKLIST','RECITATION'].includes(candidate?.finishReason))code='safety_refusal';
   else if(candidate?.finishReason!=='STOP'||!Array.isArray(candidate?.content?.parts))code='invalid_output';
   else{
    output=candidate.content.parts.filter(p=>p?.thought!==true&&typeof p?.text==='string').map(p=>p.text).join('');
    if(!output.trim())code='invalid_output';
    if(!code&&model.modelRevision!==null&&revision!==model.modelRevision)code='model_revision_mismatch';
    if(!code&&request.taskClass==='structured_extraction'){try{JSON.parse(output);}catch{code='invalid_output';}}
    if(!code){try{bounded({output});}catch{code='invalid_output';}}
   }
  }
  if(code)output=null;
  const elapsed=this.#clock()-started;
  return{output,receipt:{state:code?'failed':'received',outputDigest:output===null?null:sha256(output),providerReceipt,billedCostMicros:null,
   usage:{inputTokens:count(usage.promptTokenCount),outputTokens:count(usage.candidatesTokenCount),totalTokens:count(usage.totalTokenCount)},
   code,latencyMs:Number.isSafeInteger(elapsed)&&elapsed>=0?elapsed:null,modelRevision:revision}};
 }
}
