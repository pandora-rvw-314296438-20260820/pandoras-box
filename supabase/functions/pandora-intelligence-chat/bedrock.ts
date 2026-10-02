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
  if((enabled&&(!model||!allowedModels.includes(model)))||txt(m.streamMode,"buffered_v1")!=="buffered_v1")throw Error("PROVIDER_CONFIG_INVALID");
  return{enabled,routingEligible,fallbackEnabled:m.fallbackEnabled!==false,model,allowedModels,imageModels,tasks:["chat"],preferredTasks:[] as string[],policyVersion:txt(m.policyVersion,"bedrock-live-catalog-chat-v1"),streamMode:"buffered_v1"};
}

export function bedrockBodyFromOpenAi(v:unknown){
  const body=rec(v),messages=Array.isArray(body.messages)?body.messages:[],system:string[]=[],parts:any[]=[];
  for(const item of messages){
    const m=rec(item),role=txt(m.role),content=m.content;
    if((role==="developer"||role==="system")&&typeof content==="string"){if(content.trim())system.push(content.trim());continue}
    if(typeof content==="string"){if(content.trim())parts.push({type:"text",text:(role==="assistant"?"Assistant: ":"User: ")+content.trim()});continue}
    if(!Array.isArray(content))continue;
    for(const raw of content){
      const p=rec(raw);
      if(p.type==="text"&&typeof p.text==="string"&&p.text.trim()){parts.push({type:"text",text:p.text});continue}
      const image=rec(p.image_url),url=txt(image.url),match=url.match(/^data:(image\/(?:png|jpeg|webp));base64,([A-Za-z0-9+/=]+)$/);
      if(p.type==="image_url"&&match)parts.push({type:"image",mimeType:match[1],data:match[2]});
    }
  }
  if(!parts.length)throw Error("BEDROCK_CHAT_REQUEST_INVALID");
  const maxTokens=Number(body.max_completion_tokens??4096);
  if(!Number.isSafeInteger(maxTokens)||maxTokens<1||maxTokens>8192)throw Error("BEDROCK_CHAT_REQUEST_INVALID");
  return{system:system.join("\n\n"),parts,maxTokens};
}

function fail(kind:string,retryable:boolean,crossProviderEligible=true){
  const e=Error("PROVIDER_UNAVAILABLE");
  Object.assign(e,{code:kind,retryable,crossProviderEligible});
  return e;
}
function classify(v:unknown){
  const e=rec(v),kind=txt(rec(e.error).kind,"provider_error"),retryable=rec(e.error).retryable===true;
  if(kind==="authorization"||kind==="authentication")throw fail("authentication_failed",false,true);
  if(kind==="rate_limit")throw fail("rate_limited",retryable,true);
  if(kind==="timeout")throw fail("timeout",retryable,true);
  if(kind==="provider_unavailable"||kind==="transport_unavailable")throw fail("provider_unavailable",retryable,true);
  if(kind==="quota_exhausted")throw fail("quota_exhausted",false,true);
  if(kind==="invalid_request")throw fail("invalid_request",false,false);
  if(kind==="unsupported_capability"||kind==="not_found")throw fail("unsupported_capability",false,true);
  throw fail("provider_error",retryable,true);
}
const BEDROCK_CHAT_URL="https://mcpmaster.vercel.app/api/operations-inference?operation=bedrock-chat";
const ticketPattern=/^[0-9a-f]{64}$/;

export async function bedrockCall(c:any,model:string,body:R){
  const issued=await c.rpc("pandora_issue_bedrock_chat_ticket_v1",{p_model:model,p_body:body});
  if(issued.error)throw fail("provider_unavailable",true,true);
  const ticket=txt(rec(issued.data).ticket);
  if(!ticketPattern.test(ticket))throw fail("provider_unavailable",true,true);
  let response:Response;
  try{
    response=await fetch(BEDROCK_CHAT_URL,{
      method:"POST",
      headers:{"content-type":"application/json","accept":"application/json"},
      body:JSON.stringify({ticket}),
      redirect:"error",
      signal:AbortSignal.timeout(90000),
    });
  }catch{
    throw fail("provider_unavailable",true,true);
  }
  const rawEnvelope=await response.text();
  let e:R;try{e=rec(rawEnvelope?JSON.parse(rawEnvelope):{})}catch{throw fail("provider_unavailable",true,true)}
  const status=Number(e.status||response.status||0);
  if(!response.ok||e.ok!==true||status<200||status>=300)classify(e);
  const b=rec(e.body),raw=txt(b.text);
  if(!raw)throw Error("INVALID_MODEL_OUTPUT");
  let valueRaw:unknown;try{valueRaw=JSON.parse(raw)}catch{throw Error("INVALID_MODEL_OUTPUT")}
  return{body:b,raw,valueRaw};
}
export function bedrockUsage(v:unknown){
  const u=rec(rec(v).usage),n=(x:unknown)=>Number.isSafeInteger(Number(x))&&Number(x)>=0?Number(x):0;
  return{inputTokens:n(u.inputTokens),outputTokens:n(u.outputTokens),totalTokens:n(u.totalTokens)};
}
