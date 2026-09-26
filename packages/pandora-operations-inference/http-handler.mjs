import {InferenceError,sha256,bounded,exact,demand,UUID,integer,record} from './policy.mjs';
import {boundedCall} from './native-store.mjs';
import {deliverVerifiedOutcome} from './memory-adoption.mjs';
const headers={'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff','referrer-policy':'no-referrer'};
function reply(value,status=200,origin=null){return new Response(value===null?null:JSON.stringify(value),{status,headers:{...headers,...(origin?{'access-control-allow-origin':origin,'vary':'origin'}:{})}});}
export async function readJson(request,{maxBytes=1048576,timeoutMs=5000}={}){
 const advertised=request.headers.get('content-length');
 if(advertised!==null)demand(/^(0|[1-9][0-9]{0,9})$/.test(advertised)&&Number(advertised)<=maxBytes,'INFERENCE_BODY_LIMIT');
 demand(request.headers.get('content-type')?.split(';')[0].trim()==='application/json','INFERENCE_CONTENT_TYPE_REQUIRED');
 demand(request.body&&typeof request.body.getReader==='function','INFERENCE_BODY_REQUIRED');
 const reader=request.body.getReader();let bytes=0,parts=[];
 try{return await boundedCall(async signal=>{
   while(true){if(signal.aborted)throw new InferenceError('INFERENCE_BODY_TIMEOUT');const x=await reader.read();if(x.done)break;bytes+=x.value.byteLength;demand(bytes<=maxBytes,'INFERENCE_BODY_LIMIT');parts.push(x.value);}
   const all=new Uint8Array(bytes);let at=0;for(const part of parts){all.set(part,at);at+=part.byteLength;}
   let value;try{value=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(all));}catch{throw new InferenceError('INFERENCE_JSON_INVALID');}
   bounded(value,maxBytes);return value;
  },{signal:request.signal,timeoutMs});
 }finally{parts=[];void reader.cancel().catch(()=>{});}
}
export function createInferenceHandler({store,serviceForActor,authenticateOwner,allowedOrigins=[]}){
 demand(store?.durability==='durable'&&typeof store.authenticate==='function'&&typeof serviceForActor==='function'
  &&typeof authenticateOwner==='function','INFERENCE_HANDLER_CONFIGURATION_INVALID');
 demand(Array.isArray(allowedOrigins)&&allowedOrigins.every(s=>{try{const u=new URL(s);return u.protocol==='https:'&&u.origin===s;}catch{return false;}}),'INFERENCE_ORIGIN_CONFIGURATION_INVALID');
 const origins=new Set(allowedOrigins);
 return async request=>{
  const origin=request.headers.get('origin');if(origin&&!origins.has(origin))return reply({error:'INFERENCE_ORIGIN_DENIED'},403);
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers:{...headers,...(origin?{'access-control-allow-origin':origin,'vary':'origin'}:{}),
   'access-control-allow-methods':'POST, OPTIONS','access-control-allow-headers':'authorization, apikey, content-type'}});
  if(request.method!=='POST')return reply({error:'INFERENCE_METHOD_DENIED'},405,origin);
  const url=new URL(request.url),match=url.pathname.match(/(?:^|\/)pandora-intelligence-router\/(infer|status|verify|cancel|events)$/);
  if(!match||url.search||url.hash)return reply({error:'INFERENCE_ROUTE_DENIED'},404,origin);
  const operation=match[1],auth=request.headers.get('authorization')??'';
  if(!auth.startsWith('Bearer ')||auth.length<39||auth.length>8192)return reply({error:'INFERENCE_AUTH_REQUIRED'},401,origin);
  try{
   if(operation==='events'){
    const identity=await boundedCall(signal=>authenticateOwner(auth.slice(7),{signal}),{signal:request.signal,timeoutMs:10000});
    demand(identity&&UUID.test(identity.userId)&&identity.active===true,'INFERENCE_OWNER_AUTH_DENIED');
    const payload=await readJson(request,{maxBytes:4096});exact(payload,['organizationId','projectId','after','limit']);
    demand(UUID.test(payload.organizationId)&&UUID.test(payload.projectId)&&typeof payload.after==='string'&&/^(0|[1-9][0-9]{0,18})$/.test(payload.after)
     &&BigInt(payload.after)<=9223372036854775807n&&integer(payload.limit,1,200),'INFERENCE_EVENT_SCOPE_INVALID');
    const events=await store.events({...payload,userId:identity.userId},{signal:request.signal});
    return reply(events,200,origin);
   }
   // An application worker bearer is not a ChatGPT subscription or a Supabase owner JWT.
   demand(/^opw_[A-Za-z0-9_-]{43,128}$/.test(auth.slice(7)),'INFERENCE_WORKER_AUTH_DENIED');
   const actor=await store.authenticate(sha256(auth.slice(7)),{signal:request.signal});
   const binding=await boundedCall(signal=>serviceForActor(actor,{signal}),{signal:request.signal,timeoutMs:10000});
   demand(typeof binding?.service?.infer==='function','INFERENCE_SERVICE_NOT_CONFIGURED');
   const payload=await readJson(request,{maxBytes:operation==='infer'?1048576:4096});
   const options={signal:request.signal};
   if(operation==='infer')return reply(await binding.service.infer(actor,payload,options),202,origin);
   if(operation==='verify'){
    exact(payload,['requestId','verificationRunId']);demand(UUID.test(payload.requestId)&&UUID.test(payload.verificationRunId),'INFERENCE_IDENTITY_INVALID');
    const result=await binding.service.verify(actor,payload.requestId,payload.verificationRunId,options);
    let memory;try{memory=await deliverVerifiedOutcome(binding.memory,actor,result.native,options);}catch{memory={state:'delivery_unavailable_or_pending',deliveryVerified:false,canonicalMemoryWritten:false};}
    // Memory delivery failure cannot erase or fabricate the already-read-back verification.
    return reply({...result.status,memory:{state:memory.state,deliveryVerified:memory.deliveryVerified===true,canonicalMemoryWritten:false}},200,origin);
   }
   exact(payload,['requestId']);demand(UUID.test(payload.requestId),'INFERENCE_IDENTITY_INVALID');
   return reply(await binding.service[operation](actor,payload.requestId,options),200,origin);
  }catch(error){
   const known=error instanceof InferenceError&&/^(INFERENCE|OPS_EVENT)_[A-Z0-9_]{1,100}$/.test(error.code);
   const code=known?error.code:'INFERENCE_SERVICE_UNAVAILABLE';
   const status=/AUTH_REQUIRED|AUTH_DENIED|CALLER_DENIED/.test(code)?401:/DENIED/.test(code)?403:/BODY_LIMIT/.test(code)?413:
    /FIELDS_INVALID|JSON_INVALID|CONTENT_TYPE|BODY_REQUIRED|IDENTITY_INVALID|CLASS_INVALID|INPUT_INVALID|BUDGET_INVALID|CREDENTIAL_REJECTED|EVENT_SCOPE_INVALID/.test(code)?400:
    /TIMEOUT|UNAVAILABLE|NOT_CONFIGURED/.test(code)?503:409;
   return reply({error:code,outcomeUnknown:error?.outcomeUnknown===true,taskComplete:false},status,origin);
  }
 };
}
