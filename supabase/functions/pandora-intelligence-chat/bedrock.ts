import { consumeServerEvents } from "./chat-stream.ts";
type R=Record<string,unknown>;
const rec=(v:unknown):R=>v&&typeof v==="object"&&!Array.isArray(v)?v as R:{};
const txt=(v:unknown,d="")=>typeof v==="string"&&v.trim()?v.trim():d;
const modelId=/^[A-Za-z0-9][A-Za-z0-9._:-]{1,199}$/;
const asList=(v:unknown)=>Array.isArray(v)?v.map(x=>txt(x)).filter(x=>modelId.test(x)).slice(0,256):[];

export async function bedrockRoutingConfig(c:any){
  const r=await c.rpc("pandora_bedrock_chat_routing_config_v1");
  if(r.error)throw Error("BACKEND_READ_FAILED");
  const m=rec(r.data),allowedModels=asList(m.allowedModels),imageModels=asList(m.imageModels),model=txt(m.model);
  const enabled=m.enabled===true,routingEligible=m.routingEligible===true;
  if((enabled&&(!model||!allowedModels.includes(model)))||!["buffered_v1","converse_stream_v1"].includes(txt(m.streamMode,"buffered_v1")))throw Error("PROVIDER_CONFIG_INVALID");
  return{enabled,routingEligible,fallbackEnabled:m.fallbackEnabled!==false,model,allowedModels,imageModels,streamingModels:asList(m.streamingModels).filter(x=>allowedModels.includes(x)),tasks:["chat"],preferredTasks:[] as string[],policyVersion:txt(m.policyVersion,"bedrock-live-catalog-chat-v1"),streamMode:txt(m.streamMode,"buffered_v1")};
}

export function bedrockBodyFromOpenAi(v:unknown){
  const body=rec(v),source=Array.isArray(body.messages)?body.messages:[],system:string[]=[],messages:any[]=[];
  for(const item of source){
    const m=rec(item),role=txt(m.role),content=m.content;
    if((role==="developer"||role==="system")&&typeof content==="string"){if(content.trim())system.push(content.trim());continue}
    if(!["user","assistant"].includes(role))continue;
    const parts:any[]=[];
    if(typeof content==="string"){if(content.trim())parts.push({text:content.trim()});}
    for(const raw of Array.isArray(content)?content:[]){
      const p=rec(raw);
      if(p.type==="text"&&typeof p.text==="string"&&p.text.trim()){parts.push({text:p.text});continue}
      const image=rec(p.image_url),url=txt(image.url),match=url.match(/^data:(image\/(?:png|jpeg|webp));base64,([A-Za-z0-9+/=]+)$/);
      if(p.type==="image_url"&&match&&role==="user")parts.push({image:{format:match[1].slice(6),source:{bytes:match[2]}}});
    }
    if(parts.length){const last=messages.at(-1);if(last?.role===role)last.content.push(...parts);else messages.push({role,content:parts});}
  }
  if(!messages.length||messages[0].role!=="user"||messages.at(-1).role!=="user")throw Error("BEDROCK_CHAT_REQUEST_INVALID");
  const maxTokens=Number(body.max_completion_tokens??4096);
  if(!Number.isSafeInteger(maxTokens)||maxTokens<1||maxTokens>8192)throw Error("BEDROCK_CHAT_REQUEST_INVALID");
  return{system:system.join("\n\n"),messages,maxTokens};
}

function fail(kind:string,retryable:boolean,crossProviderEligible=true){
  const e=Error("PROVIDER_UNAVAILABLE");
  Object.assign(e,{code:kind,retryable,crossProviderEligible});
  return e;
}
function classify(v:unknown){
  const e=rec(v),kind=txt(rec(e.error).kind,"provider_error"),retryable=rec(e.error).retryable===true;
  const classifiedFail=(code:string,retry:boolean,cross:boolean)=>{const failure=fail(code,retry,cross);Object.assign(failure,{providerRequestId:typeof e.providerRequestId==="string"?e.providerRequestId:null,providerHttpStatus:Number.isSafeInteger(e.providerHttpStatus)?e.providerHttpStatus:null,providerLatencyMs:Number.isFinite(e.providerLatencyMs)?e.providerLatencyMs:null,timeToFirstTokenMs:Number.isFinite(e.timeToFirstTokenMs)?e.timeToFirstTokenMs:null});return failure;};
  if(kind==="authorization"||kind==="authentication")throw classifiedFail("authentication_failed",false,true);
  if(kind==="rate_limit")throw classifiedFail("rate_limited",retryable,true);
  if(kind==="timeout")throw classifiedFail("timeout",retryable,true);
  if(kind==="provider_unavailable"||kind==="transport_unavailable")throw classifiedFail("provider_unavailable",retryable,true);
  if(kind==="quota_exhausted")throw classifiedFail("quota_exhausted",false,true);
  if(kind==="invalid_request")throw classifiedFail("invalid_request",false,false);
  if(kind==="unsupported_capability"||kind==="not_found")throw classifiedFail("unsupported_capability",false,true);
  throw classifiedFail("provider_error",retryable,true);
}
const BEDROCK_CHAT_URL="https://mcpmaster.vercel.app/api/operations-inference?operation=bedrock-chat";
const ticketPattern=/^[0-9a-f]{64}$/;

export async function bedrockCall(c:any,model:string,body:R,options:{stream?:boolean;signal?:AbortSignal;onDelta?:(text:string)=>Promise<void>}={}){
  const started=Date.now();
  const issued=await c.rpc("pandora_issue_bedrock_chat_ticket_v1",{p_model:model,p_body:{...body,...(options.stream?{stream:true}:{})}});
  if(issued.error)throw fail("provider_unavailable",true,true);
  const ticket=txt(rec(issued.data).ticket);
  if(!ticketPattern.test(ticket))throw fail("provider_unavailable",true,true);
  const deadline=AbortSignal.timeout(150000);
  const signal=options.signal?AbortSignal.any([options.signal,deadline]):deadline;
  const transportFailure=(error:unknown)=>{
    if(options.signal?.aborted)return Error("REQUEST_CANCELLED");
    const value=rec(error);
    if(deadline.aborted||value.name==="TimeoutError")return fail("timeout",true,true);
    if(value.message==="PROVIDER_UNAVAILABLE"&&typeof value.code==="string")return error;
    const failure=fail("provider_unavailable",true,true);
    // Keep a bounded protocol diagnostic, never a parser exception's raw input.
    Object.assign(failure,{transportCode:/^PROVIDER_STREAM_(?:MISSING|INVALID|TRUNCATED)$/.test(String(value.message))
      ?value.message:"PROVIDER_STREAM_INVALID"});
    return failure;
  };
  let response:Response;
  try{
    response=await fetch(BEDROCK_CHAT_URL,{
      method:"POST",
      headers:{"content-type":"application/json","accept":options.stream?"text/event-stream":"application/json"},
      body:JSON.stringify({ticket}),
      redirect:"error",
      signal,
    });
  }catch(error){
    throw transportFailure(error);
  }
  if(response.ok&&response.headers.get("content-type")?.includes("text/event-stream")){
    let final:R|null=null;let firstDelta:number|null=null;
    let downstreamFailed=false,downstreamError:unknown;
    try{await consumeServerEvents(response,async event=>{
      if(final)throw Error("PROVIDER_STREAM_INVALID");
      if(event.type==="delta"){
        if(typeof event.text!=="string")throw Error("PROVIDER_STREAM_INVALID");
        firstDelta??=Date.now()-started;
        try{await options.onDelta?.(event.text);}catch(error){
          downstreamFailed=true;downstreamError=error;throw error;
        }
      }else if(event.type==="completed")final=rec(event.body);
      else if(event.type==="failed")classify(event);
      else throw Error("PROVIDER_STREAM_INVALID");
    });
    if(!final)throw Error("PROVIDER_STREAM_TRUNCATED");
    }catch(error){
      if(options.signal?.aborted)throw Error("REQUEST_CANCELLED");
      // Generation fences, output guards and persistence errors belong to the
      // caller. Reclassifying them as transport failures could trigger fallback.
      if(downstreamFailed&&error===downstreamError)throw error;
      throw transportFailure(error);
    }
    const b=final as R,raw=txt(b.text);if(!raw)throw Error("INVALID_MODEL_OUTPUT");
    let valueRaw:unknown;try{valueRaw=JSON.parse(raw)}catch{throw Error("INVALID_MODEL_OUTPUT")}
    return{body:{...b,transportLatencyMs:Date.now()-started,timeToFirstTokenMs:b.timeToFirstTokenMs??firstDelta},raw,valueRaw};
  }
  let rawEnvelope:string;
  try{rawEnvelope=await response.text();}catch(error){throw transportFailure(error);}
  let e:R;try{e=rec(rawEnvelope?JSON.parse(rawEnvelope):{})}catch{throw fail("provider_unavailable",true,true)}
  const status=Number(e.status||response.status||0);
  if(!response.ok||e.ok!==true||status<200||status>=300)classify(e);
  const b=rec(e.body),raw=txt(b.text);
  if(!raw)throw Error("INVALID_MODEL_OUTPUT");
  let valueRaw:unknown;try{valueRaw=JSON.parse(raw)}catch{throw Error("INVALID_MODEL_OUTPUT")}
  return{body:{...b,transportLatencyMs:Date.now()-started,streaming:false,streamMode:"buffered_v1"},raw,valueRaw};
}
export function bedrockUsage(v:unknown){
  const u=rec(rec(v).usage),n=(x:unknown)=>Number.isSafeInteger(Number(x))&&Number(x)>=0?Number(x):0;
  return{inputTokens:n(u.inputTokens),outputTokens:n(u.outputTokens),totalTokens:n(u.totalTokens)};
}
